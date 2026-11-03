import SwiftUI

/// How the tray is painted.
///
/// The default is the Dynamic Island's own: true black, fully opaque, the
/// colour of the camera housing itself. The other two are choices, not modes:
/// Tray does not follow the system appearance, because the shelf is a
/// persistent object with its own identity rather than a panel that inverts
/// underneath you (§49).
enum TrayAppearance: String, CaseIterable, Sendable {
    /// True black and fully opaque, with nothing showing through — so the
    /// shelf reads as the notch growing rather than as something hanging below
    /// it. The raw value is historical; this is the island.
    case black
    /// Almost-black, translucent, blurred.
    case graphite
    /// A light translucent surface, for anyone who wants the shelf to sit with
    /// a light desktop rather than against it.
    case light

    var title: String {
        switch self {
        case .black: "Island"
        case .graphite: "Graphite"
        case .light: "Light"
        }
    }

    var note: String {
        switch self {
        case .black: "The same opaque black as the camera housing."
        case .graphite: "Dark and slightly translucent."
        case .light: "Light and slightly translucent."
        }
    }

    /// Whether this is the island's own surface, rather than one of the two
    /// translucent alternatives. The island earns things the others do not —
    /// no shadow, no edge, no seam where it meets the bezel.
    var isIsland: Bool { self == .black }

    var palette: TrayPalette { TrayPalette(appearance: self) }
}

/// Every colour the tray draws, derived from one appearance.
///
/// The values are the island's: white ink on black, controls at 6.5% white and
/// 12% when selected, a 9% wash under the pointer, borders only when Increase
/// Contrast asks for them. Gathered into a struct rather than scattered as
/// `.white.opacity(0.6)` across the views, because "make the tray light" has to
/// be one change, not thirty — and because a foreground that does not flip with
/// its background is how a light theme ends up unreadable.
struct TrayPalette: Equatable, Sendable {
    let appearance: TrayAppearance

    init(appearance: TrayAppearance) {
        self.appearance = appearance
    }

    /// Whether content on this surface should be drawn light or dark.
    var colorScheme: ColorScheme {
        appearance == .light ? .light : .dark
    }

    /// The blur behind the surface. The island has none: a camera housing does
    /// not let anything through, and neither should this.
    var usesMaterial: Bool {
        !appearance.isIsland
    }

    func surfaceFill(reduceTransparency: Bool) -> Color {
        switch appearance {
        case .black:
            .black
        case .graphite:
            // Almost-black rather than black, so the surface still reads as a
            // material when it happens to sit over black content.
            Self.colour(Self.graphiteGround)
                .opacity(reduceTransparency ? 1 : 0.78)
        case .light:
            Self.colour(Self.lightGround)
                .opacity(reduceTransparency ? 1 : 0.76)
        }
    }

    /// The two translucent grounds' own colours, kept once so the fill and
    /// the luminance below cannot drift apart.
    private static let graphiteGround = ArtworkTint.RGB(red: 0.055, green: 0.058, blue: 0.065)
    private static let lightGround = ArtworkTint.RGB(red: 0.93, green: 0.93, blue: 0.945)

    private static func colour(_ rgb: ArtworkTint.RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// How bright the surface is, as WCAG relative luminance: what a colour
    /// drawn on it has to contrast with.
    ///
    /// Taken from the opaque fill. The translucent surfaces let a little of
    /// the desktop through, which no number here can know; at 76–78% opacity
    /// the fill is most of what is seen.
    var groundLuminance: Double {
        switch appearance {
        case .black: 0
        case .graphite: ArtworkTint.relativeLuminance(Self.graphiteGround)
        case .light: ArtworkTint.relativeLuminance(Self.lightGround)
        }
    }

    /// The edge highlight (§48) — brightest at the top, where light would catch
    /// a real object.
    func edgeHighlight(isEmphasised: Bool) -> (top: Color, bottom: Color) {
        switch appearance {
        case .black:
            // Nothing at all. A real housing has no highlight, and the whole
            // point of this surface is that you cannot tell where it ends.
            (.clear, .clear)
        case .graphite:
            (.white.opacity(isEmphasised ? 0.16 : 0.10), .white.opacity(0.02))
        case .light:
            // A light surface needs a dark edge to hold its shape against a
            // pale wallpaper; a white one would vanish.
            (.black.opacity(isEmphasised ? 0.14 : 0.09), .black.opacity(0.03))
        }
    }

    /// Foreground ink at full strength — filenames, the drop prompt when lit.
    var primaryInk: Color {
        appearance == .light ? .black : .white
    }

    func ink(_ opacity: Double) -> Color {
        primaryInk.opacity(opacity)
    }

    /// A control sitting on the surface: a header button's background, the
    /// plate behind an empty-state symbol. The island's 6.5%, and its 12% for
    /// anything currently chosen.
    func controlFill(selected: Bool) -> Color {
        appearance == .light
            ? .black.opacity(selected ? 0.10 : 0.055)
            : .white.opacity(selected ? 0.12 : 0.065)
    }

    /// The wash a button takes under the pointer. The island's 9%.
    var controlHover: Color {
        appearance == .light ? .black.opacity(0.07) : .white.opacity(0.09)
    }

    /// Icon ink in a header button: full strength for the one you are on,
    /// 55% for the rest.
    func iconInk(selected: Bool) -> Color {
        ink(selected ? 1 : 0.55)
    }

    /// The hairline around artwork, so a pale thumbnail still has an edge.
    var artworkEdge: Color { ink(0.12) }

    /// The dashed outline around the drop area, when it is switched on.
    ///
    /// The island's own 24%: a hint about where a drop lands, not a frame
    /// around the contents.
    var dropOutlineInk: Color {
        appearance == .light ? .black.opacity(0.20) : .white.opacity(0.24)
    }

    /// Fill behind an item under the pointer.
    func hoverFill(_ isHovering: Bool) -> Color {
        guard isHovering else { return .clear }
        return controlHover
    }

    /// The shadow under the tray, when there is one.
    ///
    /// `nil` for the island. A hole in the display casts nothing, and a soft
    /// grey halo under the notch is the single clearest tell that what you are
    /// looking at is a window.
    var shadow: (colour: Color, radius: CGFloat, y: CGFloat)? {
        switch appearance {
        case .black: nil
        // Kept soft and wide — a tight one reads as a black halo, which §47
        // rules out.
        case .graphite: (.black.opacity(0.30), 22, 6)
        case .light: (.black.opacity(0.22), 20, 5)
        }
    }
}

private struct TrayPaletteKey: EnvironmentKey {
    static let defaultValue = TrayPalette(appearance: .black)
}

extension EnvironmentValues {
    var trayPalette: TrayPalette {
        get { self[TrayPaletteKey.self] }
        set { self[TrayPaletteKey.self] = newValue }
    }
}
