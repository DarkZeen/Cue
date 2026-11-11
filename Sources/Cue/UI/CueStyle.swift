import SwiftUI

/// Cue in Mia's Milanote look: the same type and the same quiet, square-ish surfaces, so the two apps read
/// as one set of tools.
///
/// Mia's own values (its `Theme.make(.milanote)` and spec 1C §5): titles in bold New York, everything else in
/// SF Pro; a solid #1E1E1E ground, #2A2A2A cards with 2 pt corners and no border, #2C2C2C one-pixel dividers,
/// #3A3A3E outlines, one blue accent and an orange for links. The notch's shelf keeps its true black — the
/// island has to be the camera housing — and takes the type and the accents.
enum CueType {
    /// A title: bold serif, as Mia's board titles, headings and section names are.
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    /// Numbers that are the point of the view — a countdown, a total. Mia's serif, light, with figures that
    /// don't jitter as they count.
    static func numerals(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }

    /// Body text: SF Pro, as Mia's notes are.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// A small label or caption above or beside something.
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium)
    }
}

/// Mia's Milanote colours and shapes.
enum MiaLook {
    static let ground = Color(hex: 0x1E1E1E)
    static let bar = Color(hex: 0x232323)
    static let card = Color(hex: 0x2A2A2A)
    static let divider = Color(hex: 0x2C2C2C)
    static let outline = Color(hex: 0x3A3A3E)
    static let accent = Color(hex: 0x4B7CF0)
    static let link = Color(hex: 0xFF7A45)
    static let text = Color(white: 0.9)
    static let secondaryText = Color(white: 0.6)

    /// Cards and images: nearly square, as in Milanote.
    static let cardRadius: CGFloat = 2
    /// Sections and larger panels.
    static let sectionRadius: CGFloat = 3
    /// Pills and fields.
    static let pillRadius: CGFloat = 6
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
