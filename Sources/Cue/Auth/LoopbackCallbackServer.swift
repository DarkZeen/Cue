import Foundation
import Network
import Synchronization

/// A one-shot HTTP server on the loopback interface that catches Google's
/// OAuth redirect.
///
/// This is the redirect strategy Google calls "loopback IP address", and it is
/// the right one for a desktop app: no custom URL scheme to be hijacked by
/// another app on the machine, and no embedded web view — the user signs in in
/// their own browser, where they can see the address bar and their password
/// manager works. Cue never sees the password.
///
/// The port is whatever the system hands out. Google matches loopback
/// redirects on host and path only and ignores the port, which is what makes
/// an ephemeral one legal.
nonisolated final class LoopbackCallbackServer: Sendable {
    /// What came back on the redirect. Exactly one of `code` and `error` is
    /// meaningful; `state` is checked by the caller.
    struct Callback: Sendable {
        var code: String?
        var state: String?
        var error: String?
    }

    /// The path Google is told to redirect to. Part of the registered redirect
    /// URI, so it has to match on both sides.
    static let path = "/cue-oauth"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.cue.app.oauth-callback")
    private let waiter = Mutex<CheckedContinuation<Callback, any Error>?>(nil)
    private let started = Mutex<CheckedContinuation<UInt16, any Error>?>(nil)
    private let isFinished = Mutex<Bool>(false)

    private let logger = Diagnostics.logger("oauth-callback")

    init() throws {
        let parameters = NWParameters.tcp
        // Bound to loopback and nothing else: no other machine on the network
        // is ever in a position to answer, or to listen.
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: .any)
    }

    /// Binds and returns the port that was assigned.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            started.withLock { $0 = continuation }

            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        resumeStart(with: .failure(Failure.noPort))
                        return
                    }
                    resumeStart(with: .success(port))
                case .failed(let error), .waiting(let error):
                    resumeStart(with: .failure(error))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [self] connection in
                handle(connection)
            }

            listener.start(queue: queue)
        }
    }

    /// Waits for the browser to arrive. Resumes once; later connections — a
    /// favicon request, a refresh — are answered and dropped.
    func awaitCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            let alreadyDone = isFinished.withLock { $0 }
            if alreadyDone {
                continuation.resume(throwing: Failure.cancelled)
                return
            }
            waiter.withLock { $0 = continuation }
        }
    }

    func stop() {
        listener.cancel()
        // A caller that gave up — a timeout, a cancelled sign-in — must not
        // leave a continuation suspended forever.
        let pending = waiter.withLock { value -> CheckedContinuation<Callback, any Error>? in
            defer { value = nil }
            return value
        }
        pending?.resume(throwing: Failure.cancelled)
    }

    // MARK: - Connections

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    /// Reads until the end of the request headers.
    ///
    /// A redirect is a bare GET with no body, so the headers are the whole
    /// request — but they do not necessarily arrive in one segment, and a
    /// half-read request line means a lost authorization code.
    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, isComplete, error in
            var buffer = accumulated
            if let data { buffer.append(data) }

            let terminator = Data("\r\n\r\n".utf8)
            let hasHeaders = buffer.range(of: terminator) != nil

            // 16 KB is far more than any redirect, and the ceiling is what
            // stops a connection that never sends a blank line from holding a
            // read open until the sign-in times out.
            if hasHeaders || isComplete || error != nil || buffer.count > 16_384 {
                finish(connection, with: buffer)
            } else {
                receiveRequest(on: connection, accumulated: buffer)
            }
        }
    }

    private func finish(_ connection: NWConnection, with request: Data) {
        let target = Self.requestTarget(in: request)
        let callback = target.map(Self.parse(target:))

        // Anything that is not the redirect — the browser asking for a favicon
        // is the common one — gets a 404 and does not end the wait.
        guard let callback, target?.hasPrefix(Self.path) == true else {
            respond(on: connection, status: "404 Not Found", body: "<!doctype html><title>Cue</title>")
            return
        }

        respond(on: connection, status: "200 OK", body: Self.completionPage(succeeded: callback.code != nil))

        let pending = waiter.withLock { value -> CheckedContinuation<Callback, any Error>? in
            defer { value = nil }
            return value
        }

        isFinished.withLock { $0 = true }

        if let pending {
            pending.resume(returning: callback)
        } else {
            // The browser beat `awaitCallback()` to it, which is possible on a
            // fast machine. Nothing to do but log it; the caller's continuation
            // will see `isFinished` and fail rather than hang, and the sign-in
            // is retried.
            logger.notice("Callback arrived before anything was waiting for it.")
        }
    }

    private func respond(on connection: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let head = """
            HTTP/1.1 \(status)\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(bytes.count)\r
            Cache-Control: no-store\r
            Connection: close\r
            \r

            """
        connection.send(
            content: Data(head.utf8) + bytes,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private func resumeStart(with result: Result<UInt16, any Error>) {
        let pending = started.withLock { value -> CheckedContinuation<UInt16, any Error>? in
            defer { value = nil }
            return value
        }
        pending?.resume(with: result)
    }

    // MARK: - Parsing

    /// The request target out of `GET /path?query HTTP/1.1`.
    private static func requestTarget(in request: Data) -> String? {
        guard let line = String(data: request.prefix(2048), encoding: .utf8)?
            .split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
        else { return nil }

        let fields = line.split(separator: " ")
        guard fields.count >= 2, fields[0] == "GET" else { return nil }
        return String(fields[1])
    }

    private static func parse(target: String) -> Callback {
        // Resolved against a dummy base because the target is a path, and
        // `URLComponents` will not parse query items out of a bare one.
        guard let components = URLComponents(string: "http://127.0.0.1" + target) else {
            return Callback(error: "malformed_redirect")
        }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        return Callback(code: value("code"), state: value("state"), error: value("error"))
    }

    /// What the browser tab is left showing.
    ///
    /// Deliberately plain and self-contained — no network, no fonts to fetch —
    /// because it renders in whatever browser the user has, on a loopback
    /// origin, possibly offline.
    private static func completionPage(succeeded: Bool) -> String {
        let heading = succeeded ? "Cue is connected." : "Sign-in was cancelled."
        let detail = succeeded
            ? "You can close this tab and go back to what you were doing."
            : "Nothing was changed. You can try again from Cue's settings."

        return """
            <!doctype html>
            <html lang="en">
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Cue</title>
            <style>
              :root { color-scheme: light dark; }
              body {
                margin: 0; min-height: 100vh; display: grid; place-items: center;
                font: 16px/1.5 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
                background: Canvas; color: CanvasText;
              }
              main { text-align: center; padding: 2rem; max-width: 30rem; }
              h1 { font-size: 1.375rem; font-weight: 600; margin: 0 0 .5rem; }
              p { margin: 0; opacity: .65; }
            </style>
            <main>
              <h1>\(heading)</h1>
              <p>\(detail)</p>
            </main>
            </html>
            """
    }

    enum Failure: Error {
        case noPort
        case cancelled
    }
}
