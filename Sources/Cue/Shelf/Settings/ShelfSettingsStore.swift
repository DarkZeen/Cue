import Foundation
import Observation

/// How the tray should behave (§33).
///
/// Deliberately short. Every option here changes something the user can point
/// at in the tray itself; there is no settings screen full of knobs for
/// preferences nobody has.
/// Settings only ever record a *choice*.
///
/// Every write is guarded on the value actually changing. SwiftUI's
/// `Binding(get:set:)` setters fire during view updates as well as on user
/// input, so without the guard, merely opening the settings window writes every
/// default on the page to disk as though the user had picked it — and a slider
/// writes a clamped value, which is how a setting nobody touched ends up at the
/// end of its range. It is the same failure as the Launch at Login one: an app
/// should not claim a preference that was never expressed.
@Observable
final class ShelfSettingsStore {
    /// What is allowed to open the tray (§12, §13).
    enum Activation: String, CaseIterable, Sendable {
        case hover
        case drag
        case both

        var title: String {
            switch self {
            case .hover: "Hover"
            case .drag: "Drag files to top"
            case .both: "Both"
            }
        }

        var allowsHover: Bool { self != .drag }
        var allowsDrag: Bool { self != .hover }
    }

    /// Prefixed, because the shelf now shares Cue's defaults domain and a key
    /// called `appearance` would one day mean two things.
    private enum Key {
        static let launchAtLogin = "shelf.launchAtLogin"
        static let showsMenuBarIcon = "shelf.showsMenuBarIcon"
        static let activation = "shelf.activation"
        static let autoCollapseDelay = "shelf.autoCollapseDelay"
        static let showsFileNames = "shelf.showsFileNames"
        static let staysOpenAfterClick = "shelf.staysOpenAfterClick"
        static let appearance = "shelf.appearance"
        static let traySize = "shelf.traySize"
        static let showsDropOutline = "shelf.showsDropOutline"
        static let thumbnailSize = "shelf.thumbnailSize"
        static let expandsAfterDrop = "shelf.expandsAfterDrop"
        static let dropOutlineInset = "shelf.dropOutlineInset"
        static let customWidth = "shelf.customWidth"
        static let customHeight = "shelf.customHeight"
        static let headerInset = "shelf.headerInset"
        static let contentAlignment = "shelf.contentAlignment"

        /// Every key above, for the one-time import from Tray — except the
        /// menu bar icon. Tray's icon was one way into Tray; the item it
        /// controls now is Cue's only menu, and hiding Tray's should not hide
        /// that.
        static let all = [
            launchAtLogin,
            activation,
            autoCollapseDelay,
            showsFileNames,
            staysOpenAfterClick,
            appearance,
            traySize,
            showsDropOutline,
            thumbnailSize,
            expandsAfterDrop,
            dropOutlineInset,
            customWidth,
            customHeight,
            headerInset,
            contentAlignment,
        ]
    }

    /// Brings a Tray user's settings across the first time the merged app runs.
    ///
    /// Tray kept them in its own domain under bare names. Nothing is copied over
    /// a value Cue already has, and the import is recorded, so a shelf setting
    /// changed here is never put back by a stale Tray preference later.
    ///
    /// Both sides are read as persistent domains rather than through
    /// `object(forKey:)`, which also answers with registered defaults — and
    /// a registered default would look like a choice already made here, or
    /// be copied as if Tray's user had made it.
    static func importFromTray(
        into defaults: UserDefaults = .standard,
        domain: String? = Bundle.main.bundleIdentifier,
        trayDomain: String = "com.tray.app"
    ) {
        let marker = "shelf.importedFromTray"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)

        let saved = domain.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        guard let tray = defaults.persistentDomain(forName: trayDomain) else { return }

        for key in Key.all {
            let bare = String(key.dropFirst("shelf.".count))
            guard saved[key] == nil, let value = tray[bare] else { continue }
            defaults.set(value, forKey: key)
        }
    }

    private let defaults: UserDefaults

    /// The user's *wish* about launching at login, stored separately from what
    /// the system actually has registered. §34 is emphatic about this: the two
    /// drift apart for real reasons — a build with a different signature, an
    /// approval revoked in System Settings — and reconciling them at startup is
    /// only possible if both are recorded.
    ///
    /// Optional, because "never asked" is a genuinely different state from
    /// "asked for off", and conflating them is not harmless: on a fresh install
    /// `SMAppService` can report the app as already enabled, and a `Bool` would
    /// make startup reconciliation write that down as a preference the user
    /// never expressed.
    var launchAtLoginIntent: Bool? {
        didSet {
            guard launchAtLoginIntent != oldValue else { return }
            if let launchAtLoginIntent {
                defaults.set(launchAtLoginIntent, forKey: Key.launchAtLogin)
            } else {
                defaults.removeObject(forKey: Key.launchAtLogin)
            }
        }
    }

    var showsMenuBarIcon: Bool {
        didSet {
            guard showsMenuBarIcon != oldValue else { return }
            defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon)
        }
    }

    var activation: Activation {
        didSet {
            guard activation != oldValue else { return }
            defaults.set(activation.rawValue, forKey: Key.activation)
        }
    }

    /// Seconds the tray waits after the pointer leaves before closing (§17).
    ///
    /// Zero means it closes as the pointer leaves. That is the default: the
    /// shelf is somewhere you visit, and a shelf that lingers after you have
    /// looked away is in the way. The delay is still available for anyone who
    /// wants the grace period §17 describes.
    var autoCollapseDelay: Double {
        didSet {
            guard autoCollapseDelay != oldValue else { return }
            defaults.set(autoCollapseDelay, forKey: Key.autoCollapseDelay)
        }
    }

    var showsFileNames: Bool {
        didSet {
            guard showsFileNames != oldValue else { return }
            defaults.set(showsFileNames, forKey: Key.showsFileNames)
            onPreviewRequested?()
        }
    }

    /// Whether clicking into the tray pins it open until it is dismissed.
    ///
    /// On, a tray you have clicked into waits for a click elsewhere or Escape,
    /// so that reaching for the keyboard does not close the thing you were
    /// reaching for. Off, the pointer leaving always closes it, and the
    /// keyboard only works while you are hovering.
    var staysOpenAfterClick: Bool {
        didSet {
            guard staysOpenAfterClick != oldValue else { return }
            defaults.set(staysOpenAfterClick, forKey: Key.staysOpenAfterClick)
        }
    }

    /// How the tray surface is painted (§49).
    var appearance: TrayAppearance {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            onPreviewRequested?()
        }
    }

    /// Raised when a setting changes that can only be judged by looking at the
    /// tray — how big it is, how large the icons are, how it is painted.
    ///
    /// The app answers by opening the shelf, so dragging a size slider shows
    /// the shelf changing under your hand rather than asking you to close
    /// Settings and go and check. A closure rather than a direct call into the
    /// displays, because a settings store that knows about windows is a
    /// settings store nothing can test.
    var onPreviewRequested: (() -> Void)?

    /// How big the open shelf is: the island's two presets, or a size of your
    /// own.
    var traySize: TraySize {
        didSet {
            guard traySize != oldValue else { return }
            defaults.set(traySize.rawValue, forKey: Key.traySize)
            onPreviewRequested?()
        }
    }

    /// The width the custom size asks for, in points. Only consulted while
    /// `traySize` is `.custom`, but remembered either way, so switching to a
    /// preset and back does not lose it.
    ///
    /// Unbracketed: what it can actually produce is decided against the
    /// display the shelf is on, not here.
    var customWidth: Double {
        didSet {
            guard customWidth != oldValue else { return }
            defaults.set(customWidth, forKey: Key.customWidth)
            onPreviewRequested?()
        }
    }

    /// The height the custom size asks for, in points, measured under the
    /// camera housing. A floor: content that needs more room still gets it.
    var customHeight: Double {
        didSet {
            guard customHeight != oldValue else { return }
            defaults.set(customHeight, forKey: Key.customHeight)
            onPreviewRequested?()
        }
    }

    /// How far the name and the buttons sit from the sides of the shelf, in
    /// points. Sides only — the header shares the menu bar's line and has no
    /// vertical room to give.
    var headerInset: Double {
        didSet {
            guard headerInset != oldValue else { return }
            defaults.set(headerInset, forKey: Key.headerInset)
            onPreviewRequested?()
        }
    }

    /// Where the files — and the prompt on an empty shelf — sit across the
    /// shelf's width.
    var contentAlignment: TrayAlignment {
        didSet {
            guard contentAlignment != oldValue else { return }
            defaults.set(contentAlignment.rawValue, forKey: Key.contentAlignment)
            onPreviewRequested?()
        }
    }

    /// A dashed outline marking where a drop will land.
    var showsDropOutline: Bool {
        didSet {
            guard showsDropOutline != oldValue else { return }
            defaults.set(showsDropOutline, forKey: Key.showsDropOutline)
            onPreviewRequested?()
        }
    }

    /// Whether the shelf opens up to show what just landed, or closes as soon
    /// as the drop is done.
    var expandsAfterDrop: Bool {
        didSet {
            guard expandsAfterDrop != oldValue else { return }
            defaults.set(expandsAfterDrop, forKey: Key.expandsAfterDrop)
        }
    }

    /// How far the dashed outline sits inside the tray's edge, in points.
    var dropOutlineInset: Double {
        didSet {
            guard dropOutlineInset != oldValue else { return }
            defaults.set(dropOutlineInset, forKey: Key.dropOutlineInset)
            onPreviewRequested?()
        }
    }

    /// How large each file is drawn on the shelf, in points.
    var thumbnailSize: Double {
        didSet {
            guard thumbnailSize != oldValue else { return }
            defaults.set(thumbnailSize, forKey: Key.thumbnailSize)
            onPreviewRequested?()
        }
    }

    /// The two settings that decide how big an item is, as one value.
    var itemMetrics: TrayItemMetrics {
        TrayItemMetrics(thumbnailSize: thumbnailSize, showsFilename: showsFileNames)
    }

    static let collapseDelayRange: ClosedRange<Double> = 0...3.0

    /// Below this, the delay reads as "immediately" rather than as a number.
    static let immediateThreshold: Double = 0.05

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Key.showsMenuBarIcon: true,
            Key.showsFileNames: true,
            Key.activation: Activation.both.rawValue,
            Key.autoCollapseDelay: 0.0,
            Key.staysOpenAfterClick: true,
            Key.appearance: TrayAppearance.black.rawValue,
            Key.traySize: TraySize.spacious.rawValue,
            Key.showsDropOutline: false,
            Key.thumbnailSize: TrayMetrics.defaultThumbnailSize,
            Key.expandsAfterDrop: true,
            Key.dropOutlineInset: TrayMetrics.defaultDropOutlineInset,
            Key.customWidth: TraySize.defaultWidth,
            Key.customHeight: TraySize.defaultHeight,
            Key.headerInset: TrayMetrics.defaultHeaderInset,
            Key.contentAlignment: TrayAlignment.center.rawValue,
        ])

        // `object(forKey:)` rather than `bool(forKey:)`, so an absent key
        // stays absent instead of arriving as `false`.
        launchAtLoginIntent = defaults.object(forKey: Key.launchAtLogin) as? Bool
        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        showsFileNames = defaults.bool(forKey: Key.showsFileNames)
        autoCollapseDelay = defaults.double(forKey: Key.autoCollapseDelay)
        staysOpenAfterClick = defaults.bool(forKey: Key.staysOpenAfterClick)
        activation = Activation(rawValue: defaults.string(forKey: Key.activation) ?? "")
            ?? .both
        showsDropOutline = defaults.bool(forKey: Key.showsDropOutline)
        expandsAfterDrop = defaults.bool(forKey: Key.expandsAfterDrop)
        appearance = TrayAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "")
            ?? .black
        traySize = TraySize(rawValue: defaults.string(forKey: Key.traySize) ?? "")
            ?? .spacious

        // Clamped on the way in: a stored value from an older build, or one
        // edited by hand, must not produce a shelf wider than the display.
        // Sanity only. A custom size has no design bracket to be clamped to:
        // what it produces is decided against the display it is drawn on, and
        // a value stored on one Mac has to survive being read on another.
        customWidth = TraySize.clamped(
            defaults.double(forKey: Key.customWidth),
            to: TraySize.storable,
            fallback: TraySize.defaultWidth
        )
        headerInset = TraySize.clamped(
            defaults.double(forKey: Key.headerInset),
            to: TrayMetrics.headerInsetRange,
            fallback: Double(TrayMetrics.defaultHeaderInset)
        )
        contentAlignment = TrayAlignment(rawValue: defaults.string(forKey: Key.contentAlignment) ?? "")
            ?? .center

        customHeight = TraySize.clamped(
            defaults.double(forKey: Key.customHeight),
            to: TraySize.storable,
            fallback: TraySize.defaultHeight
        )

        let storedThumbnail = defaults.double(forKey: Key.thumbnailSize)
        thumbnailSize = min(
            max(storedThumbnail, TrayMetrics.thumbnailSizeRange.lowerBound),
            TrayMetrics.thumbnailSizeRange.upperBound
        )

        let storedInset = defaults.double(forKey: Key.dropOutlineInset)
        dropOutlineInset = min(
            max(storedInset, TrayMetrics.dropOutlineInsetRange.lowerBound),
            TrayMetrics.dropOutlineInsetRange.upperBound
        )

        Diagnostics.logger("settings").debug(
            """
            loaded: collapse=\(self.autoCollapseDelay, privacy: .public) \
            names=\(self.showsFileNames, privacy: .public) \
            icon=\(self.showsMenuBarIcon, privacy: .public) \
            launchIntent=\(self.launchAtLoginIntent.map(String.init(describing:)) ?? "unset", privacy: .public)
            """
        )
    }
}
