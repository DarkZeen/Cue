import Foundation
import Testing

@testable import Cue

/// The one-time import of a Tray user's settings into the merged app.
@MainActor
struct ShelfImportTests {
    /// A fresh pair of domains: Cue's side and Tray's side.
    private func domains() -> (cue: String, cueDefaults: UserDefaults, tray: String) {
        let id = UUID().uuidString
        let cue = "ShelfImportTests-cue-\(id)"
        return (cue, UserDefaults(suiteName: cue)!, "ShelfImportTests-tray-\(id)")
    }

    @Test func `Tray's settings arrive under the shelf's names`() {
        let (cue, defaults, tray) = domains()
        defaults.setPersistentDomain(["appearance": "graphite", "showsFileNames": false], forName: tray)

        ShelfSettingsStore.importFromTray(into: defaults, domain: cue, trayDomain: tray)

        #expect(ShelfSettingsStore(defaults: defaults).appearance == .graphite)
        #expect(ShelfSettingsStore(defaults: defaults).showsFileNames == false)
    }

    @Test func `a setting already made here is not overwritten`() {
        let (cue, defaults, tray) = domains()
        defaults.set("light", forKey: "shelf.appearance")
        defaults.setPersistentDomain(["appearance": "graphite"], forName: tray)

        ShelfSettingsStore.importFromTray(into: defaults, domain: cue, trayDomain: tray)

        #expect(ShelfSettingsStore(defaults: defaults).appearance == .light)
    }

    @Test func `the import runs once`() {
        let (cue, defaults, tray) = domains()
        ShelfSettingsStore.importFromTray(into: defaults, domain: cue, trayDomain: tray)

        defaults.setPersistentDomain(["appearance": "graphite"], forName: tray)
        ShelfSettingsStore.importFromTray(into: defaults, domain: cue, trayDomain: tray)

        #expect(defaults.persistentDomain(forName: cue)?["shelf.appearance"] == nil)
    }

    @Test func `hiding Tray's menu bar icon does not hide Cue's`() {
        let (cue, defaults, tray) = domains()
        defaults.setPersistentDomain(["showsMenuBarIcon": false], forName: tray)

        ShelfSettingsStore.importFromTray(into: defaults, domain: cue, trayDomain: tray)

        #expect(ShelfSettingsStore(defaults: defaults).showsMenuBarIcon)
    }
}
