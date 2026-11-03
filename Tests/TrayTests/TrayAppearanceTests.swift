import AppKit
import SwiftUI
import Testing

@testable import Tray

/// Renders the tray in each of its states to PNGs so the visual design can be
/// judged by eye rather than by reading numbers (§70 — "automated screenshot
/// tests are optional"; §84's build-run-look-fix loop needs *something* to
/// look at).
///
/// Off unless asked for, because it writes files:
///
///     ./Scripts/test.sh --previews
///
/// Rendered through a real `NSHostingView` in an offscreen window rather than
/// through `ImageRenderer`, which silently substitutes a placeholder for
/// `Image(nsImage:)` and skips `ScrollView` contents — it would have shown a
/// shelf full of yellow "prohibited" tiles for a tray that draws file icons
/// perfectly well.
///
/// One caveat remains: `.ultraThinMaterial` samples the window server's
/// backdrop, which an offscreen window has none of, so translucency renders as
/// its opaque fallback. Layout, type, icons, contrast and proportion are
/// faithful; the exact vibrancy has to be confirmed on screen.
@MainActor
struct TrayAppearanceTests {
    /// `nonisolated` because the trait is evaluated outside the test's
    /// isolation, before it runs.
    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TRAY_RENDER_PREVIEWS"] == "1"
    }

    private let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/previews")

    @Test(.enabled(if: TrayAppearanceTests.isEnabled))
    func `render every tray state`() throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let notchless = ScreenGeometry(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            notchSize: nil,
            topInset: 0,
            menuBarHeight: 24
        )

        // The development Mac: an M2 Air reporting safeAreaInsets.top == 32 (§8).
        let notched = ScreenGeometry(
            id: 2,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            notchSize: CGSize(width: 200, height: 32),
            topInset: 32,
            menuBarHeight: 32
        )

        try render("01-collapsed-empty", geometry: notchless, items: 0, state: .collapsed)
        try render("02-collapsed-with-items", geometry: notchless, items: 3, state: .collapsed)
        try render("03-collapsed-notched", geometry: notched, items: 3, state: .collapsed)
        try render("04-expanded-empty", geometry: notchless, items: 0, state: .expanded)
        try render("05-drop-target", geometry: notchless, items: 0, state: .dragOver)
        try render("06-expanded-four", geometry: notchless, items: 4, state: .expanded)
        try render("07-expanded-many", geometry: notchless, items: 12, state: .expanded)
        try render("08-expanded-notched", geometry: notched, items: 4, state: .expanded)
        try render("09-selected", geometry: notchless, items: 4, state: .expanded, selecting: [1, 2])

        // The two surfaces that are not the island. Light has to stay legible
        // with its ink flipped; graphite has to stay findable against a
        // wallpaper close to its own colour.
        try render("10-light", geometry: notchless, items: 4, state: .expanded, appearance: .light)
        try render("11-light-empty", geometry: notchless, items: 0, state: .expanded, appearance: .light)
        try render("12-graphite", geometry: notchless, items: 4, state: .expanded, appearance: .graphite)
        try render("13-graphite-notched", geometry: notched, items: 3, state: .collapsed, appearance: .graphite)

        // The housing clearance only looks different on a notched display, and
        // the outline is off by default.
        try render("14-notch-clearance", geometry: notched, items: 4, state: .expanded)
        try render("15-drop-outline", geometry: notchless, items: 0, state: .dragOver, outlined: true)
        try render("16-outline-with-items", geometry: notched, items: 3, state: .expanded, outlined: true)

        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count >= 16)
    }

    /// The images the README shows.
    ///
    /// Rendered through the same path as everything else, so they are the real
    /// interface rather than a mockup — composited over a backdrop instead of
    /// over a desktop, which is the one thing about them that is not literal.
    @Test(.enabled(if: TrayAppearanceTests.isEnabled))
    func `render the readme images`() throws {
        let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/assets/readme")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let screen = ScreenGeometry(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            notchSize: CGSize(width: 179, height: 32),
            topInset: 32,
            menuBarHeight: 32
        )

        try renderAsset("shelf", into: assets, geometry: screen, items: 5, state: .expanded)
        try renderAsset("closed", into: assets, geometry: screen, items: 3, state: .collapsed)
        try renderAsset("drop", into: assets, geometry: screen, items: 0, state: .dragOver)

        // The three surfaces, matched in size so they can sit in a row.
        for appearance in TrayAppearance.allCases {
            try renderAsset(
                "surface-\(appearance.rawValue)",
                into: assets,
                geometry: screen,
                items: 3,
                state: .expanded,
                appearance: appearance,
                size: CGSize(width: 620, height: 260)
            )
        }
    }

    private func renderAsset(
        _ name: String,
        into directory: URL,
        geometry: ScreenGeometry,
        items: Int,
        state: TrayPresentationState,
        appearance: TrayAppearance = .black,
        size: CGSize = CGSize(width: 900, height: 300)
    ) throws {
        let store = TrayStore()
        store.add(Self.sampleURLs(count: items))

        let presenter = TrayPresenter()
        switch state {
        case .collapsed: presenter.collapseNow()
        case .expanded: presenter.open()
        case .dragOver: presenter.dragEntered()
        case .draggingItems: break
        }

        let view = TrayContentView(
            store: store,
            presenter: presenter,
            selection: TraySelection(),
            thumbnails: ThumbnailProvider(),
            settings: Self.settings(appearance: appearance),
            geometry: geometry,
            onRemove: { _ in }, onCopy: { _ in }, onClick: { _, _ in },
            onReveal: { _ in }, onQuickLook: { _ in },
            onItemDragBegan: { _ in }, onItemDragEnded: { _, _ in },
            onShapeChange: { _ in }
        )
        .background(Self.wallpaper)

        guard let png = Self.rasterize(view, size: size) else {
            Issue.record("could not render \(name)")
            return
        }
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// The menu bar glyph at the sizes a menu bar actually uses, on a dark
    /// strip, because that is how it will be seen.
    @Test(.enabled(if: TrayAppearanceTests.isEnabled))
    func `render the menu bar glyph`() throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let heights: [CGFloat] = [16, 18, 22, 44]
        let padding: CGFloat = 14
        let canvas = NSSize(
            width: heights.reduce(0) { $0 + $1 + padding } + padding,
            height: 64
        )

        let strip = NSImage(size: canvas)
        strip.lockFocus()
        // A light strip, so the template glyph's own black shows as-is. Tinting
        // it would only test the tinting.
        NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas).fill()

        let glyph = TrayIcon.menuBarImage()
        var x = padding
        for height in heights {
            let width = height * glyph.size.width / glyph.size.height
            glyph.draw(in: NSRect(
                x: x,
                y: (canvas.height - height) / 2,
                width: width,
                height: height
            ))
            x += height + padding
        }
        strip.unlockFocus()

        guard let tiff = strip.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            Issue.record("could not render the glyph strip")
            return
        }
        try png.write(to: output.appendingPathComponent("menu-bar-glyph.png"))
    }

    // MARK: - Machinery

    private func render(
        _ name: String,
        geometry: ScreenGeometry,
        items: Int,
        state: TrayPresentationState,
        selecting indices: [Int] = [],
        appearance: TrayAppearance = .black,
        outlined: Bool = false
    ) throws {
        let store = TrayStore()
        store.add(Self.sampleURLs(count: items))

        let selection = TraySelection()
        for index in indices where store.items.indices.contains(index) {
            selection.toggle(store.items[index].id)
        }

        let presenter = TrayPresenter()
        switch state {
        case .collapsed: presenter.collapseNow()
        case .expanded: presenter.open()
        case .dragOver: presenter.dragEntered()
        case .draggingItems: break
        }

        let view = TrayContentView(
            store: store,
            presenter: presenter,
            selection: selection,
            thumbnails: ThumbnailProvider(),
            settings: Self.settings(appearance: appearance, outlined: outlined),
            geometry: geometry,
            onRemove: { _ in }, onCopy: { _ in }, onClick: { _, _ in },
            onReveal: { _ in }, onQuickLook: { _ in },
            onItemDragBegan: { _ in }, onItemDragEnded: { _, _ in },
            onShapeChange: { _ in }
        )
        // A busy, bright backdrop is the hard case: it is where a dark surface
        // with no border disappears, and where the edge highlight earns its
        // keep (§48, §49).
        .background(Self.wallpaper)

        guard let png = Self.rasterize(view, size: CGSize(width: 820, height: 300)) else {
            Issue.record("could not render \(name)")
            return
        }

        try png.write(to: output.appendingPathComponent("\(name).png"))
    }

    /// Draws a view the way the app draws it: hosted in a real window, then
    /// captured from the layer tree.
    private static func rasterize(_ view: some View, size: CGSize) -> Data? {
        let frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear

        let hosting = NSHostingView(rootView: view)
        hosting.frame = frame
        window.contentView = hosting

        // Let SwiftUI lay out and the icons resolve before the snapshot.
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: frame)
        else { return nil }
        representation.size = size
        hosting.cacheDisplay(in: frame, to: representation)

        return representation.representation(using: .png, properties: [:])
    }

    private static var wallpaper: some View {
        LinearGradient(
            colors: [
                Color(red: 0.36, green: 0.62, blue: 0.86),
                Color(red: 0.93, green: 0.90, blue: 0.83),
                Color(red: 0.85, green: 0.45, blue: 0.36),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Real files, so thumbnails and icons are the ones the tray would actually
    /// show. `/System/Applications` is present on every Mac.
    private static func sampleURLs(count: Int) -> [URL] {
        guard count > 0 else { return [] }
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/System/Applications"),
            includingPropertiesForKeys: nil
        )) ?? []
        return Array(candidates.prefix(count))
    }

    private static func settings(
        appearance: TrayAppearance,
        outlined: Bool = false
    ) -> SettingsStore {
        let settings = SettingsStore(defaults: emptyDefaults())
        settings.appearance = appearance
        settings.showsDropOutline = outlined
        return settings
    }

    private static func emptyDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TrayPreviews-\(UUID().uuidString)") ?? .standard
    }
}
