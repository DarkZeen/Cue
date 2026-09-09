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

/// The colours the redesigned surfaces are drawn from.
///
/// Small on purpose. The world is near-black grounds, one accent, and artwork —
/// which means most of the colour on screen belongs to the album covers, and
/// anything Cue adds competes with them.
enum CuePalette {
    /// The single accent. Used for what is active, never for the mark itself:
    /// the logo is white on black, and it stays that way.
    static let accent = Color(red: 1.0, green: 0.13, blue: 0.24)

    /// The panel's ground. Near-black rather than black: true black gives a
    /// translucent surface nothing to be translucent against.
    static let ground = Color(white: 0.07)

    /// The ground a tile sits on before its artwork arrives.
    static let tileGround = Color(white: 0.14)
}
