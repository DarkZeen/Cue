import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Cue

@Suite("Keyboard shortcuts")
struct KeyCombinationTests {
    @Test("Modifiers are translated into Carbon's own constants")
    func carbonModifiers() {
        // Two unrelated numbering schemes for the same four keys. Passing
        // `NSEvent`'s raw value straight through registers a combination
        // nobody can type, and it fails silently.
        let all = KeyCombination(keyCode: 49, modifiers: [.command, .option, .control, .shift])
        #expect(all.carbonModifiers == UInt32(cmdKey | optionKey | controlKey | shiftKey))

        let option = KeyCombination(keyCode: 49, modifiers: .option)
        #expect(option.carbonModifiers == UInt32(optionKey))

        #expect(KeyCombination(keyCode: 49, modifiers: []).carbonModifiers == 0)
    }

    @Test("Modifier symbols are written in the order macOS writes them")
    func symbolOrder() {
        // ⌃⌥⇧⌘ is the order every menu in the system uses. Any other order is
        // quietly, persistently wrong-looking.
        let combination = KeyCombination(
            keyCode: 49,
            modifiers: [.command, .shift, .option, .control]
        )
        #expect(combination.displayString == "⌃⌥⇧⌘Space")
    }

    @Test("The default shortcut is ⌥Space")
    func defaultShortcut() {
        #expect(KeyCombination.default.displayString == "⌥Space")
        #expect(KeyCombination.default.isValid)
    }

    @Test("Named keys are labelled rather than translated")
    func namedKeys() {
        #expect(KeyCodes.label(for: 49) == "Space")
        #expect(KeyCodes.label(for: 53) == "⎋")
        #expect(KeyCodes.label(for: 36) == "↩")
        #expect(KeyCodes.label(for: 126) == "↑")
        #expect(KeyCodes.label(for: 96) == "F5")
    }

    @Test("A bare key is refused")
    func bareKeyIsInvalid() {
        // Registering one would swallow that key everywhere on the system.
        // That is not a shortcut, it is a fault.
        #expect(!KeyCombination(keyCode: 49, modifiers: []).isValid)
        #expect(!KeyCombination(keyCode: 0, modifiers: []).isValid)
    }

    @Test("A function key needs no modifier")
    func functionKeysStandAlone() {
        // Already global by convention, and meaningless on their own.
        #expect(KeyCombination(keyCode: 96, modifiers: []).isValid)
        #expect(KeyCodes.isFunctionKey(122))
        #expect(!KeyCodes.isFunctionKey(49))
    }

    @Test("Modifiers outside the allowed set are discarded")
    func strayModifiersAreDropped() {
        // Caps Lock in a shortcut is a shortcut that stops working the moment
        // someone types in capitals, and `fn` is not reported the same way on
        // every keyboard.
        let combination = KeyCombination(
            keyCode: 49,
            modifiers: [.option, .capsLock, .function, .numericPad]
        )
        #expect(combination.modifiers == .option)
        #expect(combination.displayString == "⌥Space")
    }

    @Test("A shortcut survives being written down and read back")
    func codableRoundTrip() throws {
        let combination = KeyCombination(keyCode: 96, modifiers: [.control, .command])
        let data = try JSONEncoder().encode(combination)
        let restored = try JSONDecoder().decode(KeyCombination.self, from: data)
        #expect(restored == combination)
    }
}

@Suite("Shortcut preferences")
struct HotKeyPreferenceTests {
    private func store() -> SettingsStore {
        let suite = "com.cue.app.tests.\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("A fresh install gets the default shortcut")
    func freshInstall() {
        #expect(store().hotKey == .default)
    }

    @Test("Clearing the shortcut is remembered as cleared, not as unset")
    func clearedIsDistinctFromUnset() {
        // The bug this rules out: someone removes the shortcut, relaunches,
        // and the default comes back because "no shortcut" and "never chose
        // one" were stored the same way.
        let suite = "com.cue.app.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let first = SettingsStore(defaults: defaults)
        first.hotKey = nil

        #expect(SettingsStore(defaults: defaults).hotKey == nil)
    }

    @Test("A chosen shortcut survives a relaunch")
    func chosenShortcutPersists() {
        let suite = "com.cue.app.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let chosen = KeyCombination(keyCode: 96, modifiers: [.control, .option])

        SettingsStore(defaults: defaults).hotKey = chosen

        #expect(SettingsStore(defaults: defaults).hotKey == chosen)
    }

    @Test("Changing the shortcut announces itself so it can be re-registered")
    func changeIsAnnounced() {
        let settings = store()
        var changes = 0
        settings.onHotKeyChange = { changes += 1 }

        settings.hotKey = KeyCombination(keyCode: 96, modifiers: .control)
        settings.hotKey = nil
        // Assigning the same value again is not a change; re-registering for
        // nothing would unregister and re-register the live shortcut.
        settings.hotKey = nil

        #expect(changes == 2)
    }
}

@Suite("Shortcut registration")
struct HotKeyServiceTests {
    @Test("Registering a valid shortcut succeeds")
    func registers() {
        let service = HotKeyService()
        // F19 with three modifiers: nothing on a stock system claims it, so
        // this does not fight the machine the tests are running on.
        service.register(KeyCombination(keyCode: 80, modifiers: [.control, .option, .shift]))

        #expect(service.isRegistered)
        #expect(service.lastError == nil)

        service.unregister()
        #expect(!service.isRegistered)
    }

    @Test("Registering nothing is not an error")
    func registersNothing() {
        // Someone driving Cue from Shortcuts wants no registration at all.
        let service = HotKeyService()
        service.register(nil)

        #expect(!service.isRegistered)
        #expect(service.lastError == nil)
    }

    @Test("A bare key is refused with a reason")
    func refusesBareKey() {
        let service = HotKeyService()
        service.register(KeyCombination(keyCode: 49, modifiers: []))

        #expect(!service.isRegistered)
        #expect(service.lastError != nil)
    }

    @Test("Re-registering replaces rather than stacking")
    func reregistering() {
        // Registering the same combination twice in one process fails, so a
        // change of shortcut has to unregister first. Without that, the second
        // shortcut you pick silently does nothing.
        let service = HotKeyService()
        service.register(KeyCombination(keyCode: 80, modifiers: [.control, .option, .shift]))
        service.register(KeyCombination(keyCode: 80, modifiers: [.control, .option, .shift]))

        #expect(service.isRegistered)
        #expect(service.lastError == nil)

        service.unregister()
    }
}
