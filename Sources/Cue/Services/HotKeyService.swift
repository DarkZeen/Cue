import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// The global keyboard shortcut.
///
/// `RegisterEventHotKey` — Carbon, old, and still the right answer. It hands
/// the window server one combination and asks to be told when it is pressed,
/// which means:
///
/// * **No permission of any kind.** Not Accessibility, not Input Monitoring.
///   Those are needed to *observe* the keyboard — `CGEventTap`,
///   `addGlobalMonitorForEvents` — and observing the keyboard is exactly what
///   Cue has no business doing. A registered hotkey never sees a keystroke that
///   is not its own.
/// * **It works while another app is frontmost**, including full-screen apps,
///   which is the entire requirement.
///
/// The `cue://` URLs still work and are still the way to drive Cue from a
/// script or from Shortcuts. This is simply the path that does not require
/// setting anything up.
@Observable
final class HotKeyService {
    /// Set when registration failed, for Settings to show.
    private(set) var lastError: String?
    private(set) var isRegistered = false

    /// Called on the main thread when the shortcut is pressed.
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private let logger = Diagnostics.logger("hotkey")

    /// Identifies Cue's hotkey among any others in the process. The value is
    /// arbitrary; it only has to be ours.
    private static let signature: OSType = 0x4355_4521  // 'CUE!'

    isolated deinit {
        unregister()
    }

    // MARK: - Registration

    /// Registers `combination`, replacing whatever was registered before.
    ///
    /// Passing `nil` simply unregisters — which is a legitimate choice, not an
    /// error state. Someone who drives Cue from Shortcuts wants no hotkey at
    /// all.
    func register(_ combination: KeyCombination?) {
        unregister()
        lastError = nil

        guard let combination else {
            logger.notice("No shortcut registered.")
            return
        }

        guard combination.isValid else {
            lastError = "A shortcut needs at least one modifier key."
            return
        }

        installHandlerIfNeeded()

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            // The only failure that happens in practice is registering the same
            // combination twice within one process, which `unregister()` above
            // rules out. Anything else is worth showing rather than swallowing.
            lastError = "macOS refused that shortcut (error \(status))."
            logger.error("RegisterEventHotKey failed: \(status, privacy: .public)")
            return
        }

        isRegistered = true
        logger.notice("Registered \(combination.displayString, privacy: .public).")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        isRegistered = false
    }

    /// Installs the Carbon handler once and leaves it installed.
    ///
    /// Tearing it down and rebuilding it on every shortcut change would be
    /// churn for nothing: the handler dispatches on the hotkey id, and there is
    /// only ever one.
    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            cueHotKeyEventHandler,
            1,
            &eventType,
            // Unretained: the handler outlives nothing — this object is owned by
            // `AppState` for the life of the process, and retaining itself here
            // would guarantee it never went away even if that changed.
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    fileprivate func fire() {
        logger.debug("Shortcut pressed.")
        onFire?()
    }
}

/// Carbon's callback.
///
/// A C function pointer, so it can capture nothing and has to be handed the
/// service through `userData`. It is called on the main thread — Carbon
/// dispatches application event-target handlers on the main run loop — which is
/// what makes `assumeIsolated` true rather than hopeful.
private nonisolated func cueHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }

    let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { service.fire() }

    return noErr
}
