import AppKit
import CoreGraphics

/// Everything the tray needs to know about one display's top edge.
///
/// Derived entirely from `NSScreen`, never from hardcoded pixel values (§87).
/// A MacBook Air, a Studio Display and a 4K panel at 1.5× scaling all produce
/// correct anchors from the same code path.
struct ScreenGeometry: Equatable, Identifiable, Sendable {
    let id: CGDirectDisplayID

    /// Full display bounds in AppKit's global coordinate space
    /// (origin bottom-left, y increasing upward).
    let frame: CGRect

    /// The camera housing, when there is one — width and height in points.
    ///
    /// `nil` on any display without a notch, which is most of them. The
    /// notchless case is a first-class layout, not a degraded one (§10).
    let notchSize: CGSize?

    /// `safeAreaInsets.top`. On a notched built-in display this is the housing
    /// height; elsewhere it is zero.
    let topInset: CGFloat

    /// Height of the menu bar on this display, notch or no notch.
    let menuBarHeight: CGFloat

    /// What macOS says is usable on this display — everything except the menu
    /// bar and the Dock.
    ///
    /// The tray hangs *over* the menu bar on purpose, so this is not where it
    /// starts. It is where it has to stop: with no bracket on a custom height,
    /// a shelf someone drags all the way out would otherwise end up covering
    /// the Dock, and so would the window holding it.
    var visibleFrame: CGRect = .zero

    /// How far the tray may reach from the top edge of the display.
    ///
    /// Falls back to the whole display when nothing sensible was reported,
    /// which is what a test that does not care about the Dock will hand us.
    var usableHeight: CGFloat {
        guard visibleFrame.height > 0, visibleFrame.minY >= frame.minY else {
            return frame.height
        }
        return frame.maxY - visibleFrame.minY
    }

    var hasNotch: Bool { notchSize != nil }

    /// The x the tray centres on: the middle of the display, which on a notched
    /// Mac is also the middle of the housing.
    var anchorCenterX: CGFloat { frame.midX }

    /// The very top of the display. The tray hangs from here, so that it reads
    /// as attached to the screen's edge rather than floating below it (§9).
    var topEdgeY: CGFloat { frame.maxY }
}

/// Reads display geometry, and tells its owner when it changes.
///
/// Purely reactive: it answers questions and posts a notification-driven
/// callback when macOS says the display arrangement moved. Nothing here polls
/// (§26).
@Observable
final class ScreenGeometryService {
    private(set) var geometries: [ScreenGeometry] = []

    /// Called after the display arrangement changes — a monitor connected or
    /// disconnected, a resolution or scaling change, a rearrangement, a wake
    /// (§11).
    var onChange: (() -> Void)?

    private var observer: (any NSObjectProtocol)?

    init() {
        refresh()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                self.onChange?()
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        geometries = NSScreen.screens.compactMap(Self.geometry(for:))
    }

    func geometry(forDisplay id: CGDirectDisplayID) -> ScreenGeometry? {
        geometries.first { $0.id == id }
    }

    /// The display the pointer is currently on, which is the one whose tray
    /// should react (§11).
    var geometryUnderPointer: ScreenGeometry? {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
              let id = Self.displayID(of: screen)
        else { return geometries.first }
        return geometry(forDisplay: id)
    }

    // MARK: - Reading a single screen

    static func geometry(for screen: NSScreen) -> ScreenGeometry? {
        guard let id = displayID(of: screen) else { return nil }

        let insets = screen.safeAreaInsets
        let notchSize = notchSize(of: screen)

        // On a notched display the auxiliary areas *are* the menu bar, so their
        // height is the authoritative menu bar height. Elsewhere, ask the status
        // bar. Both beat subtracting `visibleFrame`, which is also shortened by
        // the Dock.
        let menuBarHeight: CGFloat = if let aux = screen.auxiliaryTopLeftArea {
            aux.height
        } else {
            NSStatusBar.system.thickness
        }

        return ScreenGeometry(
            id: id,
            frame: screen.frame,
            notchSize: notchSize,
            topInset: insets.top,
            menuBarHeight: menuBarHeight,
            visibleFrame: screen.visibleFrame
        )
    }

    /// Measures the camera housing without hardcoding a single model's
    /// dimensions (§87).
    ///
    /// The housing is the gap between the two usable regions macOS reports on
    /// either side of it, so its width falls out of arithmetic that stays
    /// correct across MacBook generations and scaling modes.
    private static func notchSize(of screen: NSScreen) -> CGSize? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        let width = screen.frame.width - left.width - right.width
        guard width > 1 else { return nil }

        return CGSize(width: width, height: screen.safeAreaInsets.top)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID
    }
}
