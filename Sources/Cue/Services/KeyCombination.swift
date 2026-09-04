import AppKit
import Carbon.HIToolbox
import Foundation

/// A key and the modifiers held with it.
///
/// Stored as a raw key code rather than a character, because a key code is what
/// the window server registers and what survives changing keyboard layout. The
/// *label* is resolved through the current layout every time it is drawn, so a
/// shortcut recorded on a Latvian layout and then used on a US one still points
/// at the same physical key and still says the right thing about it.
struct KeyCombination: Codable, Hashable, Sendable {
    /// A virtual key code, as `NSEvent.keyCode` reports it.
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags`, already reduced to the device-independent set.
    var modifierFlags: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(Self.allowed).rawValue
    }

    /// The four modifiers a shortcut may use. Function and Caps Lock are
    /// deliberately excluded: `fn` is not reported consistently across
    /// keyboards, and a shortcut that depends on Caps Lock is a shortcut that
    /// stops working when someone types in capitals.
    static let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(Self.allowed)
    }

    /// ⌥Space.
    ///
    /// Free on a stock system, reachable with one hand, and the combination
    /// several launchers have used for years — which is exactly why it may
    /// already be taken on *this* machine. It is a starting point, not a
    /// commitment; Settings changes it in two keystrokes.
    static let `default` = KeyCombination(keyCode: 49, modifiers: .option)

    /// Whether this is safe to register.
    ///
    /// A bare letter with no modifier would swallow that key everywhere on the
    /// system, which is not a shortcut, it is a fault. Function keys are the
    /// exception — they are already global by convention and carry no meaning
    /// on their own.
    var isValid: Bool {
        !modifiers.isEmpty || KeyCodes.isFunctionKey(keyCode)
    }

    // MARK: - Carbon

    /// The same modifiers in the bit layout Carbon's hotkey API expects.
    ///
    /// A different set of constants for the same four keys, and no relationship
    /// between the two numbering schemes — passing `NSEvent`'s raw value
    /// registers a combination nobody can type.
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    // MARK: - Display

    /// What the user sees: `⌥Space`, `⌃⌥K`, `F5`.
    ///
    /// Modifier symbols in the order macOS always writes them — ⌃⌥⇧⌘ — because
    /// that order is the one every menu in the system uses and getting it wrong
    /// is quietly, persistently wrong-looking.
    var displayString: String {
        Self.symbols(for: modifiers) + KeyCodes.label(for: keyCode)
    }

    /// Just the modifier symbols, so the recorder can echo them while the keys
    /// are still held and no key code exists yet.
    static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var output = ""
        if modifiers.contains(.control) { output += "⌃" }
        if modifiers.contains(.option) { output += "⌥" }
        if modifiers.contains(.shift) { output += "⇧" }
        if modifiers.contains(.command) { output += "⌘" }
        return output
    }
}

/// Turning a virtual key code into something a person can read.
enum KeyCodes {
    /// Keys with no character of their own, or whose character would be
    /// unreadable as a label. Everything else is asked of the keyboard layout.
    private static let named: [UInt32: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        71: "⌧", 114: "?⃝",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    private static let functionKeys: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
    ]

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys.contains(keyCode)
    }

    static func label(for keyCode: UInt32) -> String {
        if let name = named[keyCode] { return name }
        if let character = character(for: keyCode) { return character.uppercased() }
        // A key the layout will not speak for. Better an honest number than a
        // blank chip that looks like the recorder failed.
        return "#\(keyCode)"
    }

    /// The character this physical key produces on the current layout.
    ///
    /// `UCKeyTranslate` rather than a hardcoded QWERTY table, because the table
    /// is wrong for everyone who does not use QWERTY — and the whole point of a
    /// recorder is that it echoes back the key they actually pressed.
    private static func character(for keyCode: UInt32) -> String? {
        // The ASCII-capable source rather than the current one: with a
        // non-Latin layout active (Russian, Greek, Hebrew) the current source
        // would label the shortcut in a script the shortcut does not depend on.
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)

            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                // No modifiers: the label is for the *key*, and the modifiers
                // are already drawn as symbols beside it. Translating with
                // Shift held would label ⇧2 as "@".
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )

            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
