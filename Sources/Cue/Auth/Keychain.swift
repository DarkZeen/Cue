import Foundation
import OSLog
import Security

/// The only place a secret is written down.
///
/// Tokens and cookies live here rather than in `UserDefaults`, which is a
/// world-readable plist in the user's Library. Nothing in this file ever logs
/// a value, and callers are expected not to either.
///
/// A note that costs an afternoon if you do not know it: keychain items are
/// bound to the *signature* of the app that wrote them. An ad-hoc signature is
/// different on every build, so a rebuilt debug app is a different application
/// as far as the keychain is concerned and will be refused access to what the
/// previous build stored. `Scripts/setup-signing.sh` exists to make the local
/// signature stable, and it is the fix for the "signed in, then wasn't"
/// mystery.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.cue.app"
    private static let logger = Diagnostics.logger("keychain")

    /// Writes, or — with `nil` — removes. Overwrites in place rather than
    /// delete-then-add, so a failed write cannot leave the account empty.
    static func set(_ value: String?, for account: String) {
        guard let value, !value.isEmpty else {
            remove(account)
            return
        }

        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
            // Cue refreshes tokens in the background after a reboot-and-unlock,
            // so the item has to survive being read while the screen is locked.
            // `WhenUnlocked` would turn every locked-screen refresh into a
            // silent failure and a spurious "sign in again".
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert.merge(update) { current, _ in current }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Could not store \(account, privacy: .public): OSStatus \(addStatus).")
            }
        default:
            logger.error("Could not update \(account, privacy: .public): OSStatus \(status).")
        }
    }

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            // Not found is the ordinary state before signing in, and saying so
            // every launch would bury the failures that matter.
            if status != errSecItemNotFound {
                logger.error("Could not read \(account, privacy: .public): OSStatus \(status).")
            }
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Accounts

    /// One constant per secret, so a typo is a compile error rather than a
    /// value that silently reads back `nil` forever.
    enum Account {
        static let googleClientID = "google.client-id"
        static let googleClientSecret = "google.client-secret"
        static let googleRefreshToken = "google.refresh-token"
        static let ytMusicCookie = "ytmusic.cookie"
    }
}
