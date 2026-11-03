import CoreGraphics
import Foundation
import Testing

@testable import Cue

/// The shelf's geometry: how wide it opens, how it clears the housing, and
/// where its shoulders sit (§8, §20).
///
/// The numbers come from the Dynamic Island — 480pt compact, 560pt spacious,
/// a 360–600 custom bracket, a 14pt shoulder, 28pt of side inset, 76pt of
/// chrome — so the expectations here are stated against those rather than
/// against whatever the layout happens to produce.
@MainActor
struct TrayShapeTests {
    private let screenWidth: CGFloat = 1470
    private let screenHeight: CGFloat = 956

    /// A display with no camera housing: the island recreates one, 180pt wide
    /// against a 32pt menu bar, scaled to the bar this screen has.
    private let plainCutout = CGSize(width: 135, height: 24)
    private let notchedCutout = CGSize(width: 179, height: 32)

    private func expanded(
        _ size: TraySize,
        cutout: CGSize? = nil,
        customWidth: Double = TraySize.defaultWidth,
        customHeight: Double = TraySize.defaultHeight,
        item: TrayItemMetrics = .default
    ) -> TrayShape {
        TrayShape.expanded(
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            cutout: cutout ?? plainCutout,
            size: size,
            customWidth: customWidth,
            customHeight: customHeight,
            item: item
        )
    }

    // MARK: - The recreated housing

    @Test func `a display without a notch gets the island's own cutout`() {
        // 180pt against a 32pt bar, scaled to this one.
        let cutout = TrayMetrics.cutout(notchSize: nil, menuBarHeight: 24, screenWidth: screenWidth)

        #expect(cutout.height == 24)
        #expect(cutout.width == CGFloat(180 * 24) / 32)
    }

    @Test func `a display with a notch uses the housing it actually has`() {
        let cutout = TrayMetrics.cutout(
            notchSize: notchedCutout,
            menuBarHeight: 37,
            screenWidth: screenWidth
        )

        #expect(cutout == notchedCutout)
    }

    @Test func `the recreated cutout never takes over the display`() {
        let cutout = TrayMetrics.cutout(notchSize: nil, menuBarHeight: 64, screenWidth: 300)

        #expect(cutout.width <= 300 * 0.7)
    }

    // MARK: - Width

    @Test func `the presets open to the island's own widths`() {
        #expect(expanded(.compact).width == 480)
        #expect(expanded(.spacious).width == 560)
    }

    @Test func `spacious is wider than compact`() {
        #expect(expanded(.spacious).width > expanded(.compact).width)
    }

    @Test func `a custom width is used as given`() {
        #expect(expanded(.custom, customWidth: 440).width == 440)
        #expect(expanded(.custom, customWidth: 600).width == 600)
    }

    @Test func `a custom width has no bracket of its own`() {
        // Anything between the housing and the display, and nothing in the
        // middle of that span is refused for being an odd number to want.
        #expect(expanded(.custom, customWidth: 200).width == 200)
        #expect(expanded(.custom, customWidth: 1200).width == 1200)
    }

    @Test func `only the hardware limits a custom width`() {
        // Below the housing it stops at the housing; above the display it
        // stops at the display. Nothing else is imposed.
        #expect(expanded(.custom, customWidth: 40).width
            == plainCutout.width + TrayMetrics.minimumSideRoom)
        #expect(expanded(.custom, customWidth: 9000).width
            == screenWidth - TrayMetrics.screenMargin)
    }

    @Test func `the achievable width range is the housing to the display`() {
        let range = TraySize.widthRange(screenWidth: screenWidth, cutoutWidth: plainCutout.width)

        #expect(range.lowerBound == Double(plainCutout.width + TrayMetrics.minimumSideRoom))
        #expect(range.upperBound == Double(screenWidth - TrayMetrics.screenMargin))
    }

    @Test func `the shelf never spans the whole display`() {
        // It has to read as an object on the screen rather than as a second
        // menu bar (§20).
        let shape = TrayShape.expanded(
            screenWidth: 420,
            cutout: plainCutout,
            size: .custom,
            customWidth: 9000
        )

        #expect(shape.width < 420)
        #expect(shape.width == 420 - TrayMetrics.screenMargin)
    }

    @Test func `the shelf is never narrower than the housing it hangs from`() {
        // A shelf inside the cutout would be a shelf nobody can see.
        let wide = CGSize(width: 520, height: 32)
        let shape = expanded(.custom, cutout: wide, customWidth: 100)

        #expect(shape.width == wide.width + TrayMetrics.minimumSideRoom)
    }

    @Test func `the same setting is the same size on any display`() {
        // Points rather than a share of the screen: the shelf is a small object
        // near the top of the display and has no reason to grow with the panel.
        let laptop = TrayShape.expanded(screenWidth: 1470, cutout: plainCutout, size: .spacious)
        let bigScreen = TrayShape.expanded(screenWidth: 5120, cutout: plainCutout, size: .spacious)

        #expect(laptop.width == bigScreen.width)
    }

    // MARK: - Height

    @Test func `compact is the menu bar strip plus exactly what the row needs`() {
        let shape = expanded(.compact)

        #expect(shape.height == plainCutout.height + TrayMetrics.spacing
            + TrayItemMetrics.default.contentFloor)
    }

    @Test func `spacious buys the island's extra forty points`() {
        #expect(expanded(.spacious).height == expanded(.compact).height + TrayMetrics.spaciousExtra)
    }

    @Test func `a custom height is measured under the housing`() {
        let shape = expanded(.custom, customHeight: 240)

        #expect(shape.height == plainCutout.height + TrayMetrics.spacing + 240)
    }

    @Test func `a taller setting gives a taller shelf`() {
        #expect(expanded(.custom, customHeight: 300).height
            > expanded(.custom, customHeight: 180).height)
    }

    @Test func `a custom height has no bracket of its own`() {
        #expect(expanded(.custom, customHeight: 700).height
            == plainCutout.height + TrayMetrics.spacing + 700)
    }

    @Test func `the height setting is a floor, not a ceiling`() {
        // A shelf shorter than the icons it holds would clip them, and no
        // setting should be able to ask for that.
        let large = TrayItemMetrics(thumbnailSize: 88, showsFilename: true)
        let shape = expanded(.custom, customHeight: 40, item: large)

        #expect(shape.height == plainCutout.height + TrayMetrics.spacing + large.contentFloor)
    }

    @Test func `the shelf never reaches the bottom of the display`() {
        let shape = TrayShape.expanded(
            screenWidth: screenWidth,
            screenHeight: 400,
            cutout: plainCutout,
            size: .custom,
            customHeight: 9000
        )

        #expect(shape.height == 400 - TrayMetrics.bottomScreenMargin)
    }

    @Test func `the achievable height range runs from the icons to the display`() {
        let range = TraySize.heightRange(
            screenHeight: screenHeight,
            cutoutHeight: plainCutout.height,
            item: .default
        )

        #expect(range.lowerBound == Double(TrayItemMetrics.default.contentFloor))
        #expect(range.upperBound == Double(
            screenHeight - TrayMetrics.bottomScreenMargin
                - plainCutout.height - TrayMetrics.spacing
        ))
    }

    @Test func `the header padding never crosses the shape's wall`() {
        // Below the shoulder the header would be drawn outside the silhouette.
        #expect(TrayMetrics.headerInsetRange.lowerBound == Double(TrayMetrics.shoulder))
    }

    @Test func `the header padding survives a relaunch and is clamped on the way in`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        let first = ShelfSettingsStore(defaults: defaults)
        #expect(first.headerInset == Double(TrayMetrics.defaultHeaderInset))
        first.headerInset = 40

        #expect(ShelfSettingsStore(defaults: defaults).headerInset == 40)

        defaults.set(900.0, forKey: "shelf.headerInset")
        #expect(ShelfSettingsStore(defaults: defaults).headerInset
            == TrayMetrics.headerInsetRange.upperBound)

        defaults.set(0.0, forKey: "shelf.headerInset")
        #expect(ShelfSettingsStore(defaults: defaults).headerInset
            == TrayMetrics.headerInsetRange.lowerBound)
    }

    @Test func `the header padding leaves the files where they were`() {
        // Sides of the header only: it does not move the shelf's contents, and
        // it has no vertical component to change the height.
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        let settings = ShelfSettingsStore(defaults: defaults)

        let before = expanded(.compact, item: settings.itemMetrics)
        settings.headerInset = 60
        let after = expanded(.compact, item: settings.itemMetrics)

        #expect(before == after)
    }

    @Test func `the shelf starts centred and remembers being moved`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        let first = ShelfSettingsStore(defaults: defaults)
        #expect(first.contentAlignment == .center)
        first.contentAlignment = .leading

        #expect(ShelfSettingsStore(defaults: defaults).contentAlignment == .leading)
    }

    @Test func `an unrecognised stored position falls back to centred`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set("diagonal", forKey: "shelf.contentAlignment")

        #expect(ShelfSettingsStore(defaults: defaults).contentAlignment == .center)
    }

    @Test func `bigger icons raise the shortest shelf on offer`() {
        let small = TraySize.heightRange(
            screenHeight: screenHeight,
            cutoutHeight: plainCutout.height,
            item: TrayItemMetrics(thumbnailSize: 36, showsFilename: false)
        )
        let large = TraySize.heightRange(
            screenHeight: screenHeight,
            cutoutHeight: plainCutout.height,
            item: TrayItemMetrics(thumbnailSize: 88, showsFilename: true)
        )

        #expect(large.lowerBound > small.lowerBound)
    }

    @Test func `the shelf stops above the Dock rather than at the glass`() {
        // With no bracket on a custom height, the only thing keeping a shelf
        // someone dragged all the way out from covering the Dock is what macOS
        // reports as usable.
        let screen = CGRect(x: 0, y: 0, width: screenWidth, height: 956)
        let withDock = ScreenGeometry(
            id: 1,
            frame: screen,
            notchSize: nil,
            topInset: 0,
            menuBarHeight: 24,
            visibleFrame: CGRect(x: 0, y: 96, width: screenWidth, height: 836)
        )

        #expect(withDock.usableHeight == CGFloat(956 - 96))
    }

    @Test func `a display that reports nothing usable falls back to itself`() {
        let unknown = ScreenGeometry(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: screenWidth, height: 956),
            notchSize: nil,
            topInset: 0,
            menuBarHeight: 24
        )

        #expect(unknown.usableHeight == CGFloat(956))
    }

    @Test func `a tiny display still offers a range rather than an inverted one`() {
        // A ClosedRange built low-above-high traps. A 200pt screen cannot fit
        // the chrome, and the slider still has to be constructible.
        let range = TraySize.heightRange(
            screenHeight: 200,
            cutoutHeight: plainCutout.height,
            item: .default
        )

        #expect(range.lowerBound <= range.upperBound)
    }

    @Test func `the window is sized for the tallest shelf the display allows`() {
        #expect(TrayItemMetrics.maximumExpandedHeight(screenHeight: screenHeight)
            >= screenHeight - TrayMetrics.bottomScreenMargin)
    }

    @Test func `a stored custom size survives being read on another Mac`() {
        // No bracket to be clamped to: a size set on a 5K display has to come
        // back intact on a laptop, where the shape — not the store — decides
        // what it can actually produce.
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set(2400.0, forKey: "shelf.customWidth")
        defaults.set(1300.0, forKey: "shelf.customHeight")

        let settings = ShelfSettingsStore(defaults: defaults)
        #expect(settings.customWidth == 2400)
        #expect(settings.customHeight == 1300)
    }

    @Test func `a nonsense stored size falls back rather than being trusted`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set(-5.0, forKey: "shelf.customWidth")
        defaults.set(99_999.0, forKey: "shelf.customHeight")

        let settings = ShelfSettingsStore(defaults: defaults)
        #expect(settings.customWidth == TraySize.storable.lowerBound)
        #expect(settings.customHeight == TraySize.storable.upperBound)
    }

    // MARK: - Housing clearance

    @Test func `a notched display gets its files pushed clear of the housing`() {
        // Nothing drawn under the notch is visible; it is a hole in the display.
        // The header is up in that strip, at the corners where the auxiliary
        // areas are; only the files have to start below it.
        let shape = expanded(.compact, cutout: notchedCutout)

        #expect(shape.contentTop == notchedCutout.height + TrayMetrics.spacing)
    }

    @Test func `a display without a notch still clears its menu bar`() {
        // The recreated cutout covers the bar, so content starts under it just
        // the same — that is what keeps one design on every Mac.
        let shape = expanded(.compact)

        #expect(shape.contentTop == plainCutout.height + TrayMetrics.spacing)
    }

    @Test func `clearance and height add up rather than compete`() {
        let plain = expanded(.custom, customHeight: 240)
        let notched = expanded(.custom, cutout: notchedCutout, customHeight: 240)

        #expect(notched.height - plain.height == notchedCutout.height - plainCutout.height)
    }

    // MARK: - Silhouette

    @Test func `the open shelf draws in over the island's shoulders`() {
        #expect(expanded(.compact).shoulder == TrayMetrics.shoulder)
    }

    @Test func `the closed cutout keeps its shoulders too`() {
        // The island's shoulders are inside the declared width, so the closed
        // shape is still exactly housing-wide where it meets the bezel; the
        // path scales the shoulder down to suit a 32pt shape.
        let onNotch = TrayShape.collapsed(cutout: notchedCutout, isEmpty: false)

        #expect(onNotch.shoulder == TrayMetrics.shoulder)
    }

    @Test func `the empty handle has none`() {
        // Five points tall, so a shoulder would be the whole shape.
        let handle = TrayShape.collapsed(cutout: plainCutout, isEmpty: true)

        #expect(handle.shoulder == 0)
        #expect(handle.width == TrayMetrics.handleWidth)
        #expect(handle.height == TrayMetrics.handleHeight)
    }

    @Test func `the closed tray on a notched Mac matches the housing exactly`() {
        let shape = TrayShape.collapsed(cutout: notchedCutout, isEmpty: false)

        #expect(shape.width == notchedCutout.width)
        #expect(shape.height == notchedCutout.height)
    }

    @Test func `the closed tray on any other display recreates one`() {
        let shape = TrayShape.collapsed(cutout: plainCutout, isEmpty: false)

        #expect(shape.width == plainCutout.width)
        #expect(shape.height == plainCutout.height)
    }

    @Test func `the corner radius is the same expression at both sizes`() {
        // 28pt when there is room for it, half the height when there is not.
        #expect(TrayShape.radius(forHeight: 200) == TrayMetrics.cornerRadius)
        #expect(TrayShape.radius(forHeight: 32) == 16)
    }

    // MARK: - Scrolling

    @Test func `items scroll once they outgrow the chosen width`() {
        #expect(TrayShape.fits(itemCount: 3, screenWidth: screenWidth, size: .compact, item: .default))
        #expect(!TrayShape.fits(itemCount: 40, screenWidth: screenWidth, size: .compact, item: .default))
    }

    @Test func `a wider shelf fits more before it scrolls`() {
        // Six default items need 512pt of row; compact gives 480 and spacious
        // gives 560.
        #expect(!TrayShape.fits(itemCount: 6, screenWidth: screenWidth, size: .compact, item: .default))
        #expect(TrayShape.fits(itemCount: 6, screenWidth: screenWidth, size: .spacious, item: .default))
    }

    // MARK: - Item size

    @Test func `a bigger icon setting makes a taller shelf`() {
        let small = TrayItemMetrics(thumbnailSize: 36, showsFilename: true)
        let large = TrayItemMetrics(thumbnailSize: 80, showsFilename: true)

        #expect(large.contentFloor > small.contentFloor)
        #expect(large.itemWidth > small.itemWidth)
    }

    @Test func `hiding file names reclaims the space they used`() {
        let named = TrayItemMetrics(thumbnailSize: 52, showsFilename: true)
        let bare = TrayItemMetrics(thumbnailSize: 52, showsFilename: false)

        #expect(bare.contentFloor < named.contentFloor)
    }

    @Test func `bigger icons mean fewer fit before the shelf scrolls`() {
        let small = TrayItemMetrics(thumbnailSize: 36, showsFilename: true)
        let large = TrayItemMetrics(thumbnailSize: 88, showsFilename: true)

        // Six 36pt items need 416pt; six 88pt items need 728pt. The compact
        // shelf is 480pt wide.
        #expect(TrayShape.fits(itemCount: 6, screenWidth: screenWidth, size: .compact, item: small))
        #expect(!TrayShape.fits(itemCount: 6, screenWidth: screenWidth, size: .compact, item: large))
    }

    @Test func `the window is sized for the largest icons the setting allows`() {
        // The panel never resizes — the shelf animates inside it — so it has to
        // be tall enough for the biggest setting, not the current one.
        let largest = TrayItemMetrics(
            thumbnailSize: TrayMetrics.thumbnailSizeRange.upperBound,
            showsFilename: true
        )

        let tallest = TrayItemMetrics.maximumExpandedHeight(screenHeight: screenHeight)
        #expect(tallest >= largest.contentFloor)
        #expect(tallest >= TrayItemMetrics.default.contentFloor)
    }

    @Test func `a stored icon size outside the range is clamped on the way in`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set(500.0, forKey: "shelf.thumbnailSize")

        #expect(ShelfSettingsStore(defaults: defaults).thumbnailSize
            == TrayMetrics.thumbnailSizeRange.upperBound)
    }

    // MARK: - Settings

    @Test func `the shelf starts spacious, the island's own default`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        #expect(ShelfSettingsStore(defaults: defaults).traySize == .spacious)
    }

    @Test func `an unrecognised stored size falls back to spacious`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set("enormous", forKey: "shelf.traySize")

        #expect(ShelfSettingsStore(defaults: defaults).traySize == .spacious)
    }

    @Test func `size and outline settings survive a relaunch`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        let first = ShelfSettingsStore(defaults: defaults)
        #expect(first.showsDropOutline == false)
        first.traySize = .custom
        first.customWidth = 520
        first.showsDropOutline = true

        let second = ShelfSettingsStore(defaults: defaults)
        #expect(second.traySize == .custom)
        #expect(second.customWidth == 520)
        #expect(second.showsDropOutline)
    }

    // MARK: - Showing the change

    @Test func `changing how the tray looks asks for it to be shown`() {
        // A size you cannot see while you choose it is a size you choose by
        // trial and error, so every setting that changes the look of the shelf
        // opens the shelf.
        let settings = ShelfSettingsStore(defaults: UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!)
        var requests = 0
        settings.onPreviewRequested = { requests += 1 }

        settings.traySize = .custom
        settings.customWidth = 520
        settings.customHeight = 300
        settings.thumbnailSize = 64
        settings.showsFileNames = false
        settings.appearance = .graphite
        settings.showsDropOutline = true
        settings.dropOutlineInset = 12
        settings.headerInset = 24
        settings.contentAlignment = .leading

        #expect(requests == 10)
    }

    @Test func `a setting that did not change asks for nothing`() {
        // SwiftUI's binding setters fire during view updates as well as on
        // input. Without the same guard the writes use, merely opening the
        // settings window would keep reopening the tray.
        let settings = ShelfSettingsStore(defaults: UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!)
        var requests = 0
        settings.onPreviewRequested = { requests += 1 }

        settings.traySize = settings.traySize
        settings.customWidth = settings.customWidth
        settings.customHeight = settings.customHeight
        settings.thumbnailSize = settings.thumbnailSize
        settings.appearance = settings.appearance
        settings.headerInset = settings.headerInset
        settings.contentAlignment = settings.contentAlignment

        #expect(requests == 0)
    }

    @Test func `settings that are not about the look ask for nothing`() {
        // Opening the tray to demonstrate a login item would be a non sequitur.
        let settings = ShelfSettingsStore(defaults: UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!)
        var requests = 0
        settings.onPreviewRequested = { requests += 1 }

        settings.activation = .hover
        settings.autoCollapseDelay = 1.5
        settings.staysOpenAfterClick = false
        settings.expandsAfterDrop = false
        settings.showsMenuBarIcon = false

        #expect(requests == 0)
    }

    @Test func `a custom width is remembered while a preset is chosen`() {
        // Switching to a preset and back must not lose the number you set.
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        let settings = ShelfSettingsStore(defaults: defaults)
        settings.traySize = .custom
        settings.customWidth = 380
        settings.traySize = .spacious

        #expect(ShelfSettingsStore(defaults: defaults).customWidth == 380)
    }
}

/// Settings must only ever record a *choice*.
@MainActor
struct SettingsPersistenceTests {
    /// Runs `body` against a settings store backed by a throwaway domain, then
    /// hands back whatever that domain actually contains on disk.
    private func writtenKeys(
        _ body: (ShelfSettingsStore) -> Void
    ) -> [String] {
        let name = "TrayTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        body(ShelfSettingsStore(defaults: defaults))

        return (defaults.persistentDomain(forName: name) ?? [:]).keys.sorted()
    }

    @Test func `reading every setting writes nothing`() {
        // Opening the settings window reads all of these. If reading persisted
        // them, a fresh install would immediately claim a full set of
        // preferences the user never chose.
        let written = writtenKeys { settings in
            _ = settings.appearance
            _ = settings.traySize
            _ = settings.customWidth
            _ = settings.customHeight
            _ = settings.showsDropOutline
            _ = settings.staysOpenAfterClick
            _ = settings.autoCollapseDelay
            _ = settings.showsFileNames
            _ = settings.showsMenuBarIcon
            _ = settings.activation
            _ = settings.launchAtLoginIntent
        }

        #expect(written.isEmpty)
    }

    @Test func `assigning a value that has not changed writes nothing`() {
        // This is the real one. SwiftUI's `Binding(get:set:)` setters fire
        // during view updates, not only on user input, so every control on the
        // page assigns its current value back on layout. A slider does it with
        // a clamped value, which is how a setting nobody touched ends up
        // pinned to the end of its range.
        let written = writtenKeys { settings in
            settings.appearance = settings.appearance
            settings.traySize = settings.traySize
            settings.customWidth = settings.customWidth
            settings.customHeight = settings.customHeight
            settings.showsDropOutline = settings.showsDropOutline
            settings.staysOpenAfterClick = settings.staysOpenAfterClick
            settings.autoCollapseDelay = settings.autoCollapseDelay
            settings.showsFileNames = settings.showsFileNames
            settings.activation = settings.activation
        }

        #expect(written.isEmpty)
    }

    @Test func `the drop outline inset is clamped on the way in`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set(-40.0, forKey: "shelf.dropOutlineInset")

        #expect(ShelfSettingsStore(defaults: defaults).dropOutlineInset
            == TrayMetrics.dropOutlineInsetRange.lowerBound)
    }

    @Test func `the newest settings start where they should and survive`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        let first = ShelfSettingsStore(defaults: defaults)
        #expect(first.expandsAfterDrop)
        // `Double(...)` is not decoration: comparing a Double against a CGFloat
        // inside #expect fails even when both values are exactly 7, because the
        // macro captures the operands before the implicit bridge applies.
        #expect(first.dropOutlineInset == Double(TrayMetrics.defaultDropOutlineInset))

        first.expandsAfterDrop = false
        first.dropOutlineInset = 20

        let second = ShelfSettingsStore(defaults: defaults)
        #expect(second.expandsAfterDrop == false)
        #expect(second.dropOutlineInset == 20)
    }

    @Test func `an actual change is written`() {
        let written = writtenKeys { settings in
            settings.appearance = .graphite
            settings.traySize = .compact
        }

        #expect(written == ["shelf.appearance", "shelf.traySize"])
    }
}
