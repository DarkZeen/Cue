import AppKit
import SwiftUI

/// The four pages of the settings window.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case tray
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .tray: "Tray"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// Which page opens first. Always General, unless a debug build was asked
    /// to open somewhere else.
    static var initialSelection: SettingsPane {
        guard let requested = Diagnostics.debugSettingsPane,
              let pane = SettingsPane(rawValue: requested)
        else { return .general }
        return pane
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .tray: "tray"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

// MARK: - General

struct ShelfGeneralPane: View {
    let settings: ShelfSettingsStore
    let launchAtLogin: LaunchAtLoginService
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onMenuBarIconChanged: (Bool) -> Void
    let onOpenLoginItems: () -> Void

    var body: some View {
        SettingsPaneLayout(lead: "How Tray behaves when your Mac starts, and where you can reach it.") {
            SettingsCard(
                footnote: "With the icon hidden, the tray at the top of the screen still works exactly the same."
            ) {
                SettingsRow(
                    icon: "power",
                    title: "Launch at login",
                    description: "Start Tray automatically when you log in."
                ) {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin.state.isEffectivelyEnabled },
                        set: { onLaunchAtLoginChanged($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                // Registration fails for three specific reasons, and each one
                // has something the user can actually do about it. Saying which
                // one beats a toggle that quietly disagrees with the system
                // (§34).
                if let explanation = launchAtLogin.state.explanation {
                    SettingsCallout(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: explanation,
                        actionTitle: launchAtLogin.state == .requiresApproval
                            ? "Open Login Items"
                            : nil,
                        action: launchAtLogin.state == .requiresApproval
                            ? onOpenLoginItems
                            : nil
                    )
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "menubar.arrow.up.rectangle",
                    title: "Show menu bar icon",
                    description: "The menu bar is how you reach Settings and Quit."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsMenuBarIcon },
                        set: { onMenuBarIconChanged($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Tray

struct TrayPane: View {
    let settings: ShelfSettingsStore

    var body: some View {
        SettingsPaneLayout(lead: "What opens the shelf, how big it is, and how it behaves once it is up.") {
            SettingsCard(title: "Opening") {
SettingsRow(
                    icon: "cursorarrow.motionlines",
                    title: "Open the tray with",
                    description: description(for: settings.activation)
                ) {
                    Picker("", selection: Binding(
                        get: { settings.activation },
                        set: { settings.activation = $0 }
                    )) {
                        ForEach(ShelfSettingsStore.Activation.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 148)
                }
            }

            // Size sits second rather than inside Appearance: it is the group
            // people come here to change, and burying it under a scroll is how
            // a setting goes unfound.
            SettingsCard(title: "Size", footnote: sizeFootnote) {
                SettingsRow(
                    icon: "rectangle.expand.vertical",
                    title: "Shelf size",
                    description: settings.traySize.note
                ) {
                    Picker("", selection: Binding(
                        get: { settings.traySize },
                        set: { settings.traySize = $0 }
                    )) {
                        ForEach(TraySize.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 148)
                }

                // The two sliders only exist for the size that reads them. A
                // width control that does nothing while a preset is chosen is
                // a control that teaches people not to trust the page.
                if settings.traySize == .custom {
                    SettingsRowDivider()

                    SettingsRow(
                        icon: "arrow.left.and.right",
                        title: "Width",
                        description: "Anything from the camera housing to the width of this display."
                    ) {
                        sizeSlider(
                            value: Binding(
                                get: { settings.customWidth },
                                set: { settings.customWidth = $0 }
                            ),
                            in: widthRange,
                            showing: shape.width
                        )
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        icon: "arrow.up.and.down",
                        title: "Height",
                        description: "Measured under the housing. Anything down to what the icons need, and up to this display."
                    ) {
                        sizeSlider(
                            value: Binding(
                                get: { settings.customHeight },
                                set: { settings.customHeight = $0 }
                            ),
                            in: heightRange,
                            showing: shape.height - shape.contentTop
                        )
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "square.resize",
                    title: "Icon size",
                    description: "How large each file is drawn on the shelf."
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { settings.thumbnailSize },
                                set: { settings.thumbnailSize = $0 }
                            ),
                            in: TrayMetrics.thumbnailSizeRange
                        )
                        .frame(width: 110)

                        Text("\(Int(settings.thumbnailSize.rounded()))pt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "arrow.left.and.right.square",
                    title: "Header padding",
                    description: "How far the name and the buttons sit from the sides."
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { settings.headerInset },
                                set: { settings.headerInset = $0 }
                            ),
                            in: TrayMetrics.headerInsetRange
                        )
                        .frame(width: 110)

                        Text("\(Int(settings.headerInset.rounded()))pt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "align.horizontal.center",
                    title: "Position",
                    description: settings.contentAlignment.note
                ) {
                    Picker("", selection: Binding(
                        get: { settings.contentAlignment },
                        set: { settings.contentAlignment = $0 }
                    )) {
                        ForEach(TrayAlignment.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 176)
                }
            }

            SettingsCard(
                title: "Behaviour",
                footnote: "The shelf holds up to \(TrayStore.capacity) items and always empties when Tray quits."
            ) {
SettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Close after",
                    description: settings.autoCollapseDelay < ShelfSettingsStore.immediateThreshold
                        ? "The shelf closes as the pointer leaves."
                        : "How long the shelf waits once the pointer leaves."
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { settings.autoCollapseDelay },
                                set: { settings.autoCollapseDelay = $0 }
                            ),
                            in: ShelfSettingsStore.collapseDelayRange
                        )
                        .frame(width: 110)

                        Text(
                            settings.autoCollapseDelay < ShelfSettingsStore.immediateThreshold
                                ? "Now"
                                : String(format: "%.2fs", settings.autoCollapseDelay)
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

SettingsRow(
                    icon: "arrow.down.to.line",
                    title: "Open after a drop",
                    description: settings.expandsAfterDrop
                        ? "The shelf stays up for a moment so you can see what landed."
                        : "The shelf closes as soon as the drop is done."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.expandsAfterDrop },
                        set: { settings.expandsAfterDrop = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                SettingsRowDivider()

SettingsRow(
                    icon: "hand.tap",
                    title: "Stay open after a click",
                    description: settings.staysOpenAfterClick
                        ? "A tray you have clicked into waits for a click elsewhere, or Escape."
                        : "The tray always closes when the pointer leaves."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.staysOpenAfterClick },
                        set: { settings.staysOpenAfterClick = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(
                title: "Appearance",
                footnote: "Tray keeps its own look rather than following the system between light and dark. Island is the Dynamic Island's own opaque black."
            ) {
SettingsRow(
                    icon: "circle.lefthalf.filled",
                    title: "Surface",
                    description: settings.appearance.note
                ) {
                    Picker("", selection: Binding(
                        get: { settings.appearance },
                        set: { settings.appearance = $0 }
                    )) {
                        ForEach(TrayAppearance.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 148)
                }

                SettingsRowDivider()

SettingsRow(
                    icon: "textformat",
                    title: "Show file names",
                    description: "Names sit under each thumbnail."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsFileNames },
                        set: { settings.showsFileNames = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                SettingsRowDivider()

SettingsRow(
                    icon: "rectangle.dashed",
                    title: "Outline the drop area",
                    description: "A dashed border showing where a dropped file will land."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsDropOutline },
                        set: { settings.showsDropOutline = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if settings.showsDropOutline {
                    SettingsRowDivider()

                    SettingsRow(
                        icon: "arrow.down.right.and.arrow.up.left",
                        title: "Outline inset",
                        description: "How far inside the edge the outline sits."
                    ) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { settings.dropOutlineInset },
                                    set: { settings.dropOutlineInset = $0 }
                                ),
                                in: TrayMetrics.dropOutlineInsetRange
                            )
                            .frame(width: 110)

                            Text("\(Int(settings.dropOutlineInset.rounded()))pt")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    /// A size slider, reading out what the shelf *becomes* rather than what was
    /// asked for.
    ///
    /// The two differ whenever a physical limit bites — a width inside the
    /// camera housing, a height shorter than the icons, either one larger than
    /// the display — and a slider whose number kept climbing after the shelf
    /// had stopped growing would look broken.
    ///
    /// The value is clamped on the way *in* as well, so a size carried over
    /// from a larger display shows the thumb somewhere real without the slider
    /// writing a smaller number that nobody chose.
    private func sizeSlider(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        showing effective: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) },
                    set: { value.wrappedValue = $0 }
                ),
                in: range
            )
            .frame(width: 110)

            Text("\(Int(effective.rounded()))pt")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// What the shelf works out to right now, on the display this window is on.
    ///
    /// Always visible, including for the two presets, because the presets are
    /// the sizes most people will keep and "Spacious" on its own does not say
    /// how much of the screen that is.
    private var sizeFootnote: String {
        let width = Int(shape.width.rounded())
        let height = Int((shape.height - shape.contentTop).rounded())
        return "The shelf opens \(width) × \(height) points on this display. "
            + "Changing any of this opens the tray so you can watch it happen."
    }

    // MARK: - The display this window is on

    /// The limits are the hardware, not a bracket chosen here: a custom shelf
    /// runs from the camera housing to the edges of the display.
    private var geometry: ScreenGeometry? {
        NSScreen.main.flatMap(ScreenGeometryService.geometry(for:))
    }

    private var screenSize: CGSize {
        geometry?.frame.size ?? CGSize(width: 1470, height: 956)
    }

    /// Down to the Dock, not to the bottom of the glass.
    private var usableHeight: CGFloat {
        geometry?.usableHeight ?? screenSize.height
    }

    private var cutout: CGSize {
        TrayMetrics.cutout(
            notchSize: geometry?.notchSize,
            menuBarHeight: geometry?.menuBarHeight ?? 24,
            screenWidth: screenSize.width
        )
    }

    private var widthRange: ClosedRange<Double> {
        TraySize.widthRange(screenWidth: screenSize.width, cutoutWidth: cutout.width)
    }

    private var heightRange: ClosedRange<Double> {
        TraySize.heightRange(
            screenHeight: usableHeight,
            cutoutHeight: cutout.height,
            item: settings.itemMetrics
        )
    }

    /// The shelf these settings currently produce.
    private var shape: TrayShape {
        TrayShape.expanded(
            screenWidth: screenSize.width,
            screenHeight: usableHeight,
            cutout: cutout,
            size: settings.traySize,
            customWidth: settings.customWidth,
            customHeight: settings.customHeight,
            item: settings.itemMetrics
        )
    }

    private func description(for activation: ShelfSettingsStore.Activation) -> String {
        switch activation {
        case .hover: "Only moving the pointer to the top of the screen."
        case .drag: "Only dragging files at the top of the screen."
        case .both: "Either the pointer or a drag reaching the top of the screen."
        }
    }
}

// MARK: - Privacy

/// Modelled on the transparency page every good menu bar app now has — except
/// that Tray's version is a list of permissions it does *not* want.
///
/// It is worth a page rather than a sentence: an app that lives at the top of
/// your screen and touches your files has to answer the question, and the
/// answer here is unusually short (§58).
struct PrivacyPane: View {
    var body: some View {
        SettingsPaneLayout(lead: "Tray knows about the files you drag onto it, and nothing else.") {
            SettingsCard(
                title: "Permissions",
                footnote: "The only thing Tray asks macOS for is a login item, and only if you switch that on."
            ) {
                ForEach(Array(Self.permissions.enumerated()), id: \.offset) { index, permission in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(
                        icon: permission.icon,
                        title: permission.name,
                        description: permission.note,
                        tint: .secondary
                    ) {
                        SettingsStatus(text: "Not needed", colour: .green)
                    }
                }
            }

            SettingsCard(title: "Data") {
                SettingsRow(
                    icon: "network.slash",
                    title: "Network",
                    description: "Tray opens no connections. No account, no analytics, no update check.",
                    tint: .secondary
                ) {
                    SettingsStatus(text: "Never used", colour: .green)
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "internaldrive",
                    title: "What gets stored",
                    description: "Only the settings on these pages. Which files you stashed is never written down.",
                    tint: .secondary
                ) {
                    SettingsStatus(text: "Settings only", colour: .secondary)
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "doc.on.doc",
                    title: "Your files",
                    description: "The shelf holds a reference. Nothing is moved, copied, renamed or deleted.",
                    tint: .secondary
                ) {
                    SettingsStatus(text: "Untouched", colour: .green)
                }
            }
        }
    }

    private struct Permission {
        let name: String
        let icon: String
        let note: String
    }

    private static let permissions: [Permission] = [
        .init(
            name: "Accessibility",
            icon: "accessibility",
            note: "Tray never reads your input or controls other windows."
        ),
        .init(
            name: "Screen Recording",
            icon: "rectangle.dashed.badge.record",
            note: "Tray never looks at what is on your screen."
        ),
        .init(
            name: "Full Disk Access",
            icon: "externaldrive",
            note: "Tray only ever sees files you drag onto it."
        ),
        .init(
            name: "Camera and Microphone",
            icon: "mic.slash",
            note: "Nothing here records anything."
        ),
    ]
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        SettingsPaneLayout(lead: "A shelf at the top of your screen. Drag files in, drag them back out.") {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage ?? TrayIcon.menuBarImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tray")
                            .font(.system(size: 17, weight: .semibold))
                        Text(Self.versionString)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("MIT licensed, and open source.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(SettingsMetrics.rowHorizontalPadding)
            }

            SettingsCard(title: "Links") {
                ForEach(Array(Self.links.enumerated()), id: \.offset) { index, link in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(icon: link.icon, title: link.title, description: link.note) {
                        Button("Open") { NSWorkspace.shared.open(link.url) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private struct Link {
        let title: String
        let note: String
        let icon: String
        let url: URL
    }

    private static let repository = "https://github.com/DarkZeen/Tray"

    private static let links: [Link] = [
        .init(
            title: "Source code",
            note: "Small enough to read in an evening.",
            icon: "chevron.left.forwardslash.chevron.right",
            url: URL(string: repository)!
        ),
        .init(
            title: "What changed",
            note: "The changelog for every release.",
            icon: "list.bullet.rectangle",
            url: URL(string: "\(repository)/blob/main/CHANGELOG.md")!
        ),
        .init(
            title: "Report a problem",
            note: "Bugs, and things that felt wrong.",
            icon: "ladybug",
            url: URL(string: "\(repository)/issues")!
        ),
    ]

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }
}
