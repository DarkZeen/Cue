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
            add(query, update, for: account)

        case errSecAuthFailed, errSecInteractionNotAllowed, errSecInteractionRequired:
            // An item left behind by a build with a different code signature.
            // Its access list names an application that no longer exists, so
            // this one cannot update it and macOS asks for the login keychain
            // password every single time instead.
            //
            // Replacing it outright is the recovery: the value being written is
            // the newer one anyway, and the fresh item gets an access list that
            // names *this* build. Without this, a developer who rebuilds with a
            // changed signature is prompted forever and re-entering the value
            // does not help, because re-entering it takes this same path.
            logger.notice("Replacing an inaccessible \(account, privacy: .public) left by another build.")
            SecItemDelete(query as CFDictionary)
            add(query, update, for: account)

        default:
            logger.error("Could not update \(account, privacy: .public): OSStatus \(status).")
        }
    }

    private static func add(_ query: [String: Any], _ update: [String: Any], for account: String) {
        var insert = query
        insert.merge(update) { current, _ in current }
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Could not store \(account, privacy: .public): OSStatus \(status).")
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

    // MARK: - Repair

    /// Re-creates the stored items so they belong to *this* build.
    ///
    /// A keychain item's access list is built when the item is written, and it
    /// names the application that wrote it. Items written by an earlier build
    /// with a different code signature therefore name an application that no
    /// longer exists — and macOS asks for the login keychain password on every
    /// read, forever. "Always Allow" appears to fix it and does not: it grafts
    /// a grant onto a list that is still being evaluated against entries that
    /// can never match again.
    ///
    /// The only real cure is for the item to be written afresh by the app that
    /// will be reading it, which is what this does: read the value once, delete
    /// the item, write it back. There is one last prompt per item on the read,
    /// and then silence.
    ///
    /// Values are held only in memory between the delete and the write, and the
    /// delete never happens unless the read produced something — a repair that
    /// can lose a refresh token is worse than the prompt it removes.
    @discardableResult
    static func reclaim(_ accounts: [String]) -> Int {
        var repaired = 0

        for account in accounts {
            guard let value = string(for: account), !value.isEmpty else { continue }

            remove(account)

            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            query[kSecValueData as String] = Data(value.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess {
                repaired += 1
            } else {
                logger.error("Could not rewrite \(account, privacy: .public): OSStatus \(status).")
            }
        }

        if repaired > 0 {
            logger.notice("Rewrote \(repaired, privacy: .public) keychain item(s) for this build.")
        }
        return repaired
    }

    /// Everything Cue stores, for the repair above.
    static let allAccounts = [
        Account.googleClientID,
        Account.googleClientSecret,
        Account.googleRefreshToken,
        Account.ytMusicCookie,
    ]

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
