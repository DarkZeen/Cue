import SwiftUI
import Testing

@testable import Tray

/// The three surfaces, and the settings that drive them.
@MainActor
struct TrayAppearanceOptionTests {
    // MARK: - Palette

    @Test func `a light surface flips its ink`() {
        // The failure this guards against is a light theme with white text on
        // it, which is unreadable rather than merely wrong.
        #expect(TrayAppearance.light.palette.primaryInk == Color.black)
        #expect(TrayAppearance.light.palette.colorScheme == .light)
    }

    @Test func `dark surfaces keep light ink`() {
        for appearance in [TrayAppearance.graphite, .black] {
            #expect(appearance.palette.primaryInk == Color.white)
            #expect(appearance.palette.colorScheme == .dark)
        }
    }

    @Test func `the island lets nothing through`() {
        // The whole point of this option is that it matches the camera housing,
        // and the housing is not translucent.
        #expect(TrayAppearance.black.palette.usesMaterial == false)
        #expect(TrayAppearance.black.palette.surfaceFill(reduceTransparency: false) == Color.black)
    }

    @Test func `the translucent surfaces blur what is behind them`() {
        #expect(TrayAppearance.graphite.palette.usesMaterial)
        #expect(TrayAppearance.light.palette.usesMaterial)
    }

    @Test func `every surface says what it is`() {
        for appearance in TrayAppearance.allCases {
            #expect(!appearance.title.isEmpty)
            #expect(!appearance.note.isEmpty)
        }
    }

    // MARK: - Settings

    private func freshSettings() -> SettingsStore {
        let defaults = UserDefaults(
            suiteName: "TrayTests-\(UUID().uuidString)"
        ) ?? .standard
        return SettingsStore(defaults: defaults)
    }

    @Test func `the tray starts on the island's black and stays open after a click`() {
        let settings = freshSettings()

        #expect(settings.appearance == .black)
        #expect(settings.staysOpenAfterClick)
    }

    @Test func `both new settings survive a relaunch`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        // Not the island: that is the default, so storing it would prove
        // nothing about whether the choice was written down.
        let first = SettingsStore(defaults: defaults)
        first.appearance = .graphite
        first.staysOpenAfterClick = false

        let second = SettingsStore(defaults: defaults)
        #expect(second.appearance == .graphite)
        #expect(second.staysOpenAfterClick == false)
    }

    @Test func `an unrecognised stored surface falls back to the island`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set("chartreuse", forKey: "appearance")

        #expect(SettingsStore(defaults: defaults).appearance == .black)
    }

    // MARK: - The click requirement

    @Test func `with the click requirement off the tray closes anyway`() {
        let tray = TrayPresenter()
        tray.collapseDelay = { 0 }
        tray.holdsOpenWhenClicked = { false }
        tray.open()

        // Selecting still works — this setting only decides whether a selection
        // is enough to hold the shelf open.
        tray.beganInteracting()
        #expect(!tray.isInteracting)

        tray.pointerExited()
        #expect(tray.state == .collapsed)
    }

    @Test func `with the click requirement on the tray waits`() {
        let tray = TrayPresenter()
        tray.collapseDelay = { 0 }
        tray.holdsOpenWhenClicked = { true }
        tray.open()

        tray.beganInteracting()
        tray.pointerExited()

        #expect(tray.state == .expanded)
    }
}
