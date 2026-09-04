import AppKit
import CryptoKit
import Foundation
import Observation
import WebKit

/// The credential half of the unofficial provider: a YouTube Music web
/// session, captured once and then replayed.
///
/// There is no OAuth for the endpoints music.youtube.com talks to itself.
/// What the site sends is a cookie plus a hash of one of its values, and that
/// is what Cue has to send too. So the sign-in happens where it should — in a
/// real web view, on Google's own pages, with the user typing their own
/// password into Google's own form — and what Cue keeps afterwards is the
/// resulting cookie, in the keychain.
///
/// Two deliberate choices in here are worth defending:
///
/// * The web view's data store is **non-persistent**. When the window closes,
///   the browsing session evaporates and the keychain copy is the only one
///   left. A persistent store would leave a second, plainer copy of the same
///   credentials in Application Support forever.
/// * Nothing is captured until the user is actually signed in. Loading the
///   page sets cookies immediately, and grabbing those would store something
///   that looks like a session and authenticates as nobody.
@Observable
final class YTMusicSessionService: NSObject {
    /// Whether there is a stored session. Read while drawing Settings.
    private(set) var isConnected: Bool
    private(set) var isPresentingSignIn = false
    private(set) var lastError: String?

    /// Raised when a session arrives, so the library can reload without
    /// Settings having to know what a library is.
    var onSessionChange: (() -> Void)?

    private var window: NSWindow?
    private var webView: WKWebView?
    private var pollTask: Task<Void, Never>?

    private let logger = Diagnostics.logger("ytmusic-session")

    private static let origin = "https://music.youtube.com"
    private static let signInURL = URL(string: "https://music.youtube.com/")!

    /// The cookie whose value is hashed into the authorization header. Modern
    /// sessions carry the `__Secure-3PAPISID` variant as well; either will do,
    /// and having both means a session that keeps working when Google retires
    /// one of them.
    private static let hashCookieNames = ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"]

    override init() {
        isConnected = Keychain.string(for: Keychain.Account.ytMusicCookie) != nil
        super.init()
    }

    // MARK: - Sign in

    /// Opens the sign-in window. Returns immediately; the capture happens when
    /// the user finishes.
    func presentSignIn() {
        guard !isPresentingSignIn else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        lastError = nil
        isPresentingSignIn = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 460, height: 720),
            configuration: configuration
        )
        webView.navigationDelegate = self
        // Google refuses to sign in on anything it reads as an embedded web
        // view, and the default WebKit agent is one. This is Safari's own
        // string: the request is coming from WebKit either way, and the point
        // is to be allowed to present a real login form rather than a page
        // saying to use a browser.
        webView.customUserAgent = Self.userAgent

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to YouTube Music"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.webView = webView
        self.window = window

        webView.load(URLRequest(url: Self.signInURL))

        // An accessory app has to ask: without this the window opens behind
        // whatever the user was in, and a login form you cannot type into is
        // worse than no login form.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        startPolling()
    }

    /// Watches for the session to become real.
    ///
    /// Polling rather than reacting to navigation, because signing in to
    /// Google is not one navigation: it is a redirect chain through
    /// accounts.google.com with an interstitial or two, sometimes a device
    /// prompt, and the cookies land somewhere in the middle of it. The end of
    /// *a* navigation says nothing about whether it was the last one.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard let self, self.isPresentingSignIn else { return }
                if await self.captureIfSignedIn() { return }
            }
        }
    }

    private func captureIfSignedIn() async -> Bool {
        guard let webView else { return false }

        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let relevant = cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return domain.hasSuffix("youtube.com") || domain.hasSuffix("google.com")
        }

        guard relevant.contains(where: { Self.hashCookieNames.contains($0.name) }) else {
            return false
        }

        // De-duplicated by name, last one winning: the same cookie is set on
        // both `.google.com` and `.youtube.com`, and sending it twice in one
        // header is a request Google answers with a 400.
        var byName: [String: String] = [:]
        for cookie in relevant { byName[cookie.name] = cookie.value }
        let header = byName.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")

        Keychain.set(header, for: Keychain.Account.ytMusicCookie)
        isConnected = true
        logger.notice("Captured a YouTube Music session (\(byName.count, privacy: .public) cookies).")

        dismissSignIn()
        onSessionChange?()
        return true
    }

    func dismissSignIn() {
        pollTask?.cancel()
        pollTask = nil
        isPresentingSignIn = false

        // Order matters: the delegate is cleared first so that closing the
        // window does not come back through `windowWillClose` and re-enter.
        window?.delegate = nil
        window?.close()
        window = nil
        webView?.navigationDelegate = nil
        webView = nil
    }

    func disconnect() {
        Keychain.remove(Keychain.Account.ytMusicCookie)
        isConnected = false
        lastError = nil
        logger.notice("Disconnected the YouTube Music session.")
        onSessionChange?()
    }

    /// Called when the stored cookie turns out to be dead, so Settings can say
    /// so rather than the grid silently emptying.
    func invalidate(reason: String) {
        guard isConnected else { return }
        Keychain.remove(Keychain.Account.ytMusicCookie)
        isConnected = false
        lastError = reason
        logger.notice("The stored session was rejected; disconnected.")
        onSessionChange?()
    }

    // MARK: - Request signing

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    var cookieHeader: String? {
        Keychain.string(for: Keychain.Account.ytMusicCookie)
    }

    /// The headers that make an InnerTube request look like the website's own.
    ///
    /// The authorization value is Google's `SAPISIDHASH` scheme: a timestamp
    /// and the SHA-1 of `timestamp SAPISID origin`. It is not a signature over
    /// the request — it proves nothing about the body — but it is what the
    /// site sends, and a request without it is answered with a 401.
    func authorizationHeaders() -> [String: String]? {
        guard let cookieHeader else { return nil }

        let jar = Self.parse(cookieHeader: cookieHeader)
        guard let name = Self.hashCookieNames.first(where: { jar[$0] != nil }),
              let secret = jar[name]
        else { return nil }

        let timestamp = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(secret) \(Self.origin)".utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        // The prefix names which cookie was hashed. `SAPISID` uses the plain
        // one; the `1P`/`3P` variants have their own, and sending the wrong
        // label with the right value is rejected.
        let label = switch name {
        case "__Secure-1PAPISID": "SAPISID1PHASH"
        case "__Secure-3PAPISID": "SAPISID3PHASH"
        default: "SAPISIDHASH"
        }

        return [
            "Authorization": "\(label) \(timestamp)_\(hash)",
            "Cookie": cookieHeader,
            "Origin": Self.origin,
            "X-Origin": Self.origin,
            "X-Goog-AuthUser": "0",
            "User-Agent": Self.userAgent,
        ]
    }

    static func parse(cookieHeader: String) -> [String: String] {
        var jar: [String: String] = [:]
        for pair in cookieHeader.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[trimmed.startIndex..<separator])
            // Values contain `=` — base64 padding — so only the first one
            // separates, and splitting on every `=` truncates the cookie.
            let value = String(trimmed[trimmed.index(after: separator)...])
            jar[name] = value
        }
        return jar
    }
}

extension YTMusicSessionService: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        MainActor.assumeIsolated {
            // Cancellations are the redirect chain doing its job, not a
            // failure worth putting in front of anyone.
            let code = (error as NSError).code
            guard code != NSURLErrorCancelled else { return }
            self.lastError = error.localizedDescription
        }
    }
}

extension YTMusicSessionService: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard self.isPresentingSignIn else { return }
            self.pollTask?.cancel()
            self.pollTask = nil
            self.isPresentingSignIn = false
            self.window = nil
            self.webView = nil
        }
    }
}
