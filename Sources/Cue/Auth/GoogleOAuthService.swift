import AppKit
import CryptoKit
import Foundation
import Observation

/// The OAuth half of the official provider: getting, keeping and refreshing a
/// YouTube Data API access token.
///
/// Authorization-code flow with PKCE, in the system browser, against a
/// loopback redirect. Cue holds a refresh token and nothing else — it never
/// sees a password, and revoking it is one click in the Google account page
/// as well as one button in Settings.
///
/// The client credentials are the user's own. Cue ships with none: an OAuth
/// client that lives in a public repository is a client whose quota anyone can
/// spend, and Google's verification process is not something to put between
/// someone and their own playlists. Settings explains how to make one.
@Observable
final class GoogleOAuthService {
    /// Read-only access to the signed-in user's YouTube account. The narrowest
    /// scope that can list playlists and read their contents; anything wider
    /// would let Cue modify a library it has no business modifying.
    static let scope = "https://www.googleapis.com/auth/youtube.readonly"

    private static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// True once there is a refresh token to work with. Drawn in Settings, so
    /// it is observable rather than computed on demand.
    private(set) var isConnected: Bool
    /// Set when a sign-in fails, for Settings to show. Cleared on the next
    /// attempt.
    private(set) var lastError: String?
    private(set) var isSigningIn = false

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    /// Coalesces concurrent refreshes. Three providers waking at once on the
    /// same expired token should perform one exchange, not three — Google
    /// invalidates on reuse in some configurations, and even where it does not,
    /// two of the three would be wasted.
    private var refreshTask: Task<String, any Error>?

    private let logger = Diagnostics.logger("google-oauth")

    init() {
        isConnected = Keychain.string(for: Keychain.Account.googleRefreshToken) != nil
    }

    // MARK: - Credentials

    var clientID: String? {
        get { Keychain.string(for: Keychain.Account.googleClientID) }
        set { Keychain.set(newValue, for: Keychain.Account.googleClientID) }
    }

    var clientSecret: String? {
        get { Keychain.string(for: Keychain.Account.googleClientSecret) }
        set { Keychain.set(newValue, for: Keychain.Account.googleClientSecret) }
    }

    var hasClientCredentials: Bool {
        clientID?.isEmpty == false
    }

    // MARK: - Sign in

    /// Runs the whole flow: listener up, browser open, code back, token
    /// exchanged. Returns when there is a refresh token in the keychain.
    func signIn() async throws {
        guard let clientID, !clientID.isEmpty else {
            throw Failure.missingClientCredentials
        }

        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        let server = try LoopbackCallbackServer()
        defer { server.stop() }

        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)\(LoopbackCallbackServer.path)"

        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let expectedState = Self.randomURLSafeString(byteCount: 24)

        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Without both of these Google issues an access token and no
            // refresh token, and Cue would ask the user to sign in again every
            // hour. `prompt=consent` is what makes a *re*-authorization return
            // one too.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: expectedState),
        ]

        guard let authorizationURL = components.url else {
            throw Failure.malformedAuthorizationURL
        }

        logger.notice("Opening the browser for sign-in on port \(port, privacy: .public).")
        NSWorkspace.shared.open(authorizationURL)

        let callback = try await withThrowingTaskGroup(of: LoopbackCallbackServer.Callback.self) { group in
            group.addTask { try await server.awaitCallback() }
            group.addTask {
                // Five minutes is generous for "find the right Google account,
                // read the consent screen, maybe do 2FA" and still short
                // enough that an abandoned sign-in does not leave a socket
                // open for the rest of the session.
                try await Task.sleep(for: .seconds(300))
                throw Failure.timedOut
            }

            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        guard callback.state == expectedState else {
            // The one check that makes the loopback redirect safe: another
            // process on this machine could have raced a request at the port,
            // and a code that did not come from the URL we opened is not one
            // to exchange.
            throw Failure.stateMismatch
        }

        if let error = callback.error {
            throw Failure.denied(error)
        }

        guard let code = callback.code else {
            throw Failure.noAuthorizationCode
        }

        try await exchange(code: code, verifier: verifier, redirectURI: redirectURI)
    }

    /// Forgets everything, and tells Google to forget it too.
    ///
    /// The revocation is best-effort: if the network is down, the local
    /// credentials still go, because the button says "Disconnect" and leaving
    /// a token behind after being told that would be a lie.
    func signOut() async {
        let token = Keychain.string(for: Keychain.Account.googleRefreshToken)

        Keychain.remove(Keychain.Account.googleRefreshToken)
        accessToken = nil
        accessTokenExpiry = nil
        refreshTask?.cancel()
        refreshTask = nil
        isConnected = false
        lastError = nil

        guard let token else { return }

        var request = URLRequest(url: Self.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("token=\(token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? token)".utf8)

        do {
            _ = try await URLSession.shared.data(for: request)
            logger.notice("Revoked the refresh token.")
        } catch {
            logger.notice("Could not reach Google to revoke the token; it was removed locally.")
        }
    }

    // MARK: - Tokens

    /// A valid access token, refreshing if the cached one is spent.
    func currentAccessToken() async throws -> String {
        if let accessToken, let expiry = accessTokenExpiry, expiry > Date().addingTimeInterval(60) {
            return accessToken
        }

        if let refreshTask {
            return try await refreshTask.value
        }

        guard let refreshToken = Keychain.string(for: Keychain.Account.googleRefreshToken) else {
            throw MusicLibraryError.notAuthorized
        }

        let task = Task { try await self.refresh(using: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }

    private func refresh(using refreshToken: String) async throws -> String {
        guard let clientID else { throw MusicLibraryError.notAuthorized }

        var fields = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        // Desktop clients are issued a secret that is not really secret — it
        // ships inside every copy of the app — but Google still requires it on
        // the token endpoint. Clients created as "iOS" or "TV" have none, and
        // must not send an empty one.
        if let clientSecret, !clientSecret.isEmpty { fields["client_secret"] = clientSecret }

        do {
            let response = try await postForm(fields, to: Self.tokenEndpoint)
            store(response, keepingRefreshToken: refreshToken)
            return response.accessToken
        } catch Failure.rejected(let error, _) where error == "invalid_grant" {
            // The refresh token is dead: revoked in the Google account page,
            // expired after six months of disuse, or the password changed.
            // Nothing to retry — the user has to sign in again.
            Keychain.remove(Keychain.Account.googleRefreshToken)
            isConnected = false
            logger.notice("The refresh token was rejected; disconnected.")
            throw MusicLibraryError.authenticationExpired
        }
    }

    private func exchange(code: String, verifier: String, redirectURI: String) async throws {
        guard let clientID else { throw Failure.missingClientCredentials }

        var fields = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        if let clientSecret, !clientSecret.isEmpty { fields["client_secret"] = clientSecret }

        let response = try await postForm(fields, to: Self.tokenEndpoint)

        guard let refreshToken = response.refreshToken else {
            // Reached when the account has authorized this client before and
            // Google decided not to re-issue one. `prompt=consent` above is
            // what prevents it, so this is a genuine surprise worth surfacing.
            throw Failure.noRefreshToken
        }

        Keychain.set(refreshToken, for: Keychain.Account.googleRefreshToken)
        store(response, keepingRefreshToken: refreshToken)
        isConnected = true
        logger.notice("Signed in.")
    }

    private func store(_ response: TokenResponse, keepingRefreshToken refreshToken: String) {
        accessToken = response.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        if let issued = response.refreshToken, issued != refreshToken {
            Keychain.set(issued, for: Keychain.Account.googleRefreshToken)
        }
        isConnected = true
    }

    // MARK: - Transport

    private func postForm(_ fields: [String: String], to url: URL) async throws -> TokenResponse {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // `URLComponents` leaves `+` alone in a query, where it means a space
        // once a server form-decodes it. Authorization codes and tokens
        // routinely contain one.
        let body = (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            let failure = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let code = failure?.error ?? "http_\(status)"
            logger.error("Token endpoint refused: \(code, privacy: .public).")
            throw Failure.rejected(code, failure?.errorDescription)
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - PKCE

    /// The verifier, and the `state` value, both come from here: 
    /// cryptographically random bytes in base64url, which is exactly the
    /// alphabet the spec allows for a code verifier.
    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        // `SecRandomCopyBytes` cannot fail for a buffer this size, and a
        // predictable verifier defeats the entire point of PKCE — so a failure
        // here is not something to paper over with `Int.random`.
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "The system random source failed.")
        return Data(bytes).urlSafeBase64EncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).urlSafeBase64EncodedString()
    }

    // MARK: - Wire types

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    enum Failure: Error, LocalizedError {
        case missingClientCredentials
        case malformedAuthorizationURL
        case timedOut
        case stateMismatch
        case denied(String)
        case noAuthorizationCode
        case noRefreshToken
        case rejected(String, String?)

        var errorDescription: String? {
            switch self {
            case .missingClientCredentials:
                "Add a Google OAuth client ID in Settings first."
            case .malformedAuthorizationURL:
                "The sign-in address could not be built."
            case .timedOut:
                "Sign-in timed out."
            case .stateMismatch:
                "The sign-in response did not match the request, so it was discarded."
            case .denied(let reason):
                reason == "access_denied" ? "Sign-in was declined." : "Sign-in failed (\(reason))."
            case .noAuthorizationCode:
                "Google did not return an authorization code."
            case .noRefreshToken:
                "Google did not issue a refresh token. Remove Cue from your Google account's third-party access list and try again."
            case .rejected(let code, let detail):
                detail.map { "\(code): \($0)" } ?? "Google rejected the request (\(code))."
            }
        }
    }
}

extension Data {
    /// base64url without padding — RFC 4648 §5, which is what PKCE requires.
    func urlSafeBase64EncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
