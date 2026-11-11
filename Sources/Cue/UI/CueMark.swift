import SwiftUI

/// Cue's mark, still. Used where a logo is wanted rather than a performance.
struct CueMark: View {
    var height: CGFloat = 18
    var tint: Color = .white

    var body: some View {
        CueLogoPath.path(in: CGRect(
            origin: .zero,
            size: CGSize(width: height * CueLogoPath.aspect, height: height)
        ))
        .fill(tint)
        .frame(width: height * CueLogoPath.aspect, height: height)
        .accessibilityHidden(true)
    }
}

/// The colours the surfaces are drawn from: Mia's Milanote look (`MiaLook`).
///
/// Small on purpose. Solid dark grounds, one accent, and artwork — which means
/// most of the colour on screen belongs to the album covers, and anything Cue
/// adds competes with them.
enum CuePalette {
    /// The single accent, Mia's blue. Used for what is active, never for the
    /// mark itself: the logo is white on black, and it stays that way.
    static let accent = MiaLook.accent

    /// The panel's ground: Milanote's solid #1E1E1E.
    static let ground = MiaLook.ground

    /// The ground a tile sits on before its artwork arrives: a Milanote card.
    static let tileGround = MiaLook.card
}
