import AppKit
import Foundation

/// Where on the display the panel appears.
///
/// Nine fixed positions rather than a free drag. The panel is summoned and
/// dismissed dozens of times a day, and the argument for its fixed grid — that
/// you can aim without looking — applies just as much to where the whole thing
/// lands. A panel you can knock out of place is a panel you have to find.
enum PanelAnchor: String, Codable, CaseIterable, Sendable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    /// Reading order, for the three-by-three picker.
    static let grid: [[PanelAnchor]] = [
        [.topLeading, .top, .topTrailing],
        [.leading, .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing],
    ]

    var title: String {
        switch self {
        case .topLeading: "Top left"
        case .top: "Top"
        case .topTrailing: "Top right"
        case .leading: "Left"
        case .center: "Centre"
        case .trailing: "Right"
        case .bottomLeading: "Bottom left"
        case .bottom: "Bottom"
        case .bottomTrailing: "Bottom right"
        }
    }

    /// Clear of the screen edge without hugging it.
    private static let margin: CGFloat = 24

    /// Where a panel of this size sits inside a display's usable area.
    func origin(for size: NSSize, in visible: NSRect) -> NSPoint {
        let x: CGFloat = switch self {
        case .topLeading, .leading, .bottomLeading:
            visible.minX + Self.margin
        case .top, .center, .bottom:
            visible.midX - size.width / 2
        case .topTrailing, .trailing, .bottomTrailing:
            visible.maxX - size.width - Self.margin
        }

        let y: CGFloat = switch self {
        case .topLeading, .top, .topTrailing:
            visible.maxY - size.height - Self.margin
        case .leading, .center, .trailing:
            // Lifted above the true middle. The optical centre of a screen sits
            // higher than its geometric one, and a panel pinned to the exact
            // middle reads as slightly low — which is why every launcher since
            // Spotlight has put it here.
            visible.midY + visible.height * 0.10 - size.height / 2
        case .bottomLeading, .bottom, .bottomTrailing:
            visible.minY + Self.margin
        }

        return NSPoint(x: x, y: y)
    }
}
