import Foundation
import Observation
import ServiceManagement

/// The Launch at Login switch.
///
/// `SMAppService` rather than a login-item helper: it is one call, macOS shows
/// the app in Login Items where the user expects to find it, and it can be
/// turned off there without Cue being involved.
///
/// The registration is bound to the app's code signature, so a rebuild with an
/// ad-hoc signature quietly loses it — the same trap as the keychain, with the
/// same fix in `Scripts/setup-signing.sh`.
@Observable
final class LaunchAtLoginService {
    private let logger = Diagnostics.logger("launch-at-login")

    /// Read from the system rather than mirrored in `UserDefaults`, so that
    /// turning it off in System Settings is reflected here rather than
    /// contradicted.
    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { setEnabled(newValue) }
    }

    /// Whether macOS is holding the request behind the user's approval.
    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.notice("Registered for launch at login.")
            } else {
                try SMAppService.mainApp.unregister()
                logger.notice("Unregistered from launch at login.")
            }
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
