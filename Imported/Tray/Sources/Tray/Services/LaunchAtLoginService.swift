import Foundation
import OSLog
import ServiceManagement

/// Launch at login (§34).
///
/// `SMAppService` needs no Developer ID, but it does need three things that
/// each fail quietly if you assume them, so each one is checked and reported
/// rather than hoped for:
///
/// 1. **A stable location.** Registration cannot survive a relaunch from a
///    mounted DMG or a translocated path.
/// 2. **User approval.** `.requiresApproval` means the item exists and is
///    switched *off* in System Settings. Registering over it looks like
///    success and does nothing at the next login.
/// 3. **A stable code signature.** An ad-hoc signature changes on every build,
///    so macOS treats each rebuild as a different app and drops the item —
///    which is the entire reason `Scripts/setup-signing.sh` exists.
///
/// The user's wish and the system's state are stored separately and reconciled
/// at startup, because they genuinely diverge.
@Observable
final class LaunchAtLoginService {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but switched off by the user in System Settings.
        case requiresApproval
        /// The app is somewhere registration cannot survive.
        case unstableLocation
        case failed(String)

        var isEffectivelyEnabled: Bool { self == .enabled }
    }

    private(set) var state: State = .disabled

    private let logger = Diagnostics.logger("launch-at-login")
    private let service = SMAppService.mainApp

    // MARK: - Reading

    func refresh() {
        guard isInStableLocation else {
            state = .unstableLocation
            return
        }

        logger.debug("SMAppService.mainApp.status = \(self.service.status.rawValue, privacy: .public)")

        state = switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    /// What startup reconciliation should do (§34).
    ///
    /// Pulled out as a pure function over (wish, system state) because it is a
    /// decision table with one genuinely surprising row, and a decision table
    /// that cannot be tested is a decision table that will be got wrong.
    enum Reconciliation: Equatable {
        /// Leave things alone and store this wish, which may be "none".
        case keep(Bool?)
        /// The system lost an item the user asked for; register it again.
        case reregister
        /// The user switched it on in System Settings; take their word for it.
        case adopt
    }

    static func decide(intent: Bool?, state: State) -> Reconciliation {
        switch (intent, state) {
        case (nil, _):
            // The surprising row. On a fresh install `SMAppService` reports
            // `.enabled` before anyone has asked for anything, so treating an
            // absent wish as "off" would make the next case fire and record a
            // choice the user never made — which then re-registers forever.
            // Report the system's real state in the UI; write nothing down.
            .keep(nil)

        case (true, .disabled):
            .reregister

        case (false, .enabled):
            .adopt

        default:
            .keep(intent)
        }
    }

    /// Reconciles the stored wish with what the system actually has (§34).
    ///
    /// Runs once at launch. Returns the wish to store, which may still be
    /// "none".
    func reconcile(intent: Bool?) -> Bool? {
        refresh()

        switch Self.decide(intent: intent, state: state) {
        case .keep(let wish):
            return wish

        case .reregister:
            logger.notice("Login item missing though the user asked for it; re-registering.")
            setEnabled(true)
            return true

        case .adopt:
            logger.notice("Login item enabled outside the app; adopting.")
            return true
        }
    }

    // MARK: - Writing

    /// Returns the state after the attempt, so a UI toggle can be corrected
    /// rather than left showing a lie.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> State {
        guard isInStableLocation else {
            state = .unstableLocation
            logger.error("Refusing to register a login item from a read-only or translocated path.")
            return state
        }

        do {
            if enabled {
                try service.register()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            return state
        }

        refresh()
        return state
    }

    /// Opens the exact pane the user needs when approval is the blocker.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Location

    /// A read-only volume means a mounted DMG; a `AppTranslocation` path means
    /// Gatekeeper moved the app somewhere temporary. Neither survives a
    /// relaunch, so the toggle must not pretend otherwise (§34).
    private var isInStableLocation: Bool {
        let bundleURL = Bundle.main.bundleURL

        if bundleURL.path.contains("/AppTranslocation/") { return false }

        let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return !(values?.volumeIsReadOnly ?? false)
    }
}

extension LaunchAtLoginService.State {
    /// Plain words for the settings window. No error codes.
    var explanation: String? {
        switch self {
        case .enabled, .disabled:
            nil
        case .requiresApproval:
            "Tray is switched off in System Settings ▸ General ▸ Login Items."
        case .unstableLocation:
            "Move Tray to your Applications folder for this to stick."
        case .failed(let message):
            message
        }
    }
}
