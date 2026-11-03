import AppKit
import SwiftUI

/// The settings window (§33, §55).
///
/// A sidebar and a detail pane, which is the shape macOS itself uses for
/// settings — so nobody has to learn where anything is. Deliberately not a
/// custom dashboard: this is not the product, and the product is at the top of
/// the screen.
///
/// Four pages, and only one of them was a judgement call. General and Tray hold
/// the settings §33 asks for. About is table stakes. Privacy is there because
/// an app that lives over your screen and takes your files should answer that
/// question somewhere you can find it, and Tray's answer — no permissions, no
/// network, nothing written down — is worth stating plainly (§58).
struct SettingsView: View {
    let settings: SettingsStore
    let launchAtLogin: LaunchAtLoginService

    let onLaunchAtLoginChanged: @MainActor @Sendable (Bool) -> Void
    let onMenuBarIconChanged: @MainActor @Sendable (Bool) -> Void
    let onOpenLoginItems: @MainActor @Sendable () -> Void

    @State private var selection: SettingsPane? = SettingsPane.initialSelection

    var body: some View {
        NavigationSplitView {
            // The explicit ForEach form, not `List(data, selection:)` — the
            // latter selects by element id, which does not match a binding of
            // the element type itself.
            List(selection: $selection) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.icon)
                        .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(SettingsMetrics.sidebarWidth)
        } detail: {
            detail
                .frame(minWidth: SettingsMetrics.detailWidth)
                .navigationTitle(selection?.title ?? "Settings")
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralPane(
                settings: settings,
                launchAtLogin: launchAtLogin,
                onLaunchAtLoginChanged: { onLaunchAtLoginChanged($0) },
                onMenuBarIconChanged: { onMenuBarIconChanged($0) },
                onOpenLoginItems: { onOpenLoginItems() }
            )
        case .tray:
            TrayPane(settings: settings)
        case .privacy:
            PrivacyPane()
        case .about:
            AboutPane()
        }
    }
}

/// Hosts `SettingsView` in an ordinary window.
///
/// The settings window is the one place Tray behaves like a normal app: it
/// activates, takes focus, and appears in the window menu, because that is what
/// someone who just chose "Settings…" expects. The tray itself never does any
/// of that (§28).
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(state: AppState) {
        let view = SettingsView(
            settings: state.settings,
            launchAtLogin: state.launchAtLogin,
            onLaunchAtLoginChanged: { [weak state] in state?.setLaunchAtLogin($0) },
            onMenuBarIconChanged: { [weak state] in state?.setMenuBarIconVisible($0) },
            onOpenLoginItems: { [weak state] in state?.launchAtLogin.openLoginItemsSettings() }
        )

        window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsMetrics.sidebarWidth + SettingsMetrics.detailWidth,
                height: SettingsMetrics.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Tray Settings"
        // Lets the sidebar's material run all the way to the top of the window,
        // which is what makes it read as one surface rather than a panel with a
        // bar stuck on it.
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(
            width: SettingsMetrics.sidebarWidth + SettingsMetrics.detailWidth,
            height: SettingsMetrics.windowHeight
        ))
        window.contentMinSize = NSSize(width: 560, height: 380)
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
