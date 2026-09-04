import Foundation

/// Which grid the panel draws.
enum PanelDesign: String, Codable, CaseIterable, Sendable {
    /// Three pages of album artwork, one title to a tile. The default.
    case gallery
    /// The original: one page of nine, artwork small, title and subtitle beside
    /// it. Denser, and faster to read when the covers all look alike.
    case classic

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .classic: "Compact"
        }
    }

    var summary: String {
        switch self {
        case .gallery:
            "Three pages of artwork — kept, liked and albums. ← and → move between them."
        case .classic:
            "One page of nine, with titles beside small artwork."
        }
    }
}
