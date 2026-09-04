import AppKit
import SwiftUI

/// The control that captures a keyboard shortcut.
///
/// A local event monitor rather than a first-responder `NSView`, for the same
/// reason the panel uses one: the monitor sees the event before anything else
/// and can decline to pass it on, which is the only way to record ⌘Q without
/// quitting or ⌘W without closing the window you are recording in.
struct ShortcutRecorder: View {
    @Binding var combination: KeyCombination?

    @State private var isRecording = false
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 108)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isRecording ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.tint, lineWidth: isRecording ? 1.5 : 0)
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Press the keys you want" : "Click to change the shortcut")

            if isRecording {
                Text("⎋ cancels, ⌫ clears")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if combination != nil {
                Button("Clear") { combination = nil }
                    .buttonStyle(.borderless)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isRecording)
        // A monitor that outlives the window would swallow keystrokes for the
        // rest of the session, which is about the worst bug this control could
        // have.
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording {
            // Echoes the modifiers as they go down, so it is obvious the
            // control is listening before the key that ends it is pressed.
            let preview = KeyCombination.symbols(for: heldModifiers)
            return preview.isEmpty ? "Press keys…" : preview + "…"
        }
        return combination?.displayString ?? "None"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        heldModifiers = []

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event) ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        heldModifiers = []
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(KeyCombination.allowed)

        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return true
        }

        switch event.keyCode {
        case 53 where modifiers.isEmpty: // Escape
            stopRecording()
            return true

        case 51 where modifiers.isEmpty: // Delete
            combination = nil
            stopRecording()
            return true

        default:
            let candidate = KeyCombination(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            // A bare letter would swallow that key system-wide. Keep listening
            // rather than accepting it or bailing out — the user is mid-gesture
            // and has simply not pressed a modifier yet.
            guard candidate.isValid else { return true }

            combination = candidate
            stopRecording()
            return true
        }
    }
}
