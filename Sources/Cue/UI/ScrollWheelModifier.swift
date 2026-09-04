import AppKit
import SwiftUI

/// Scroll-wheel events for a SwiftUI view.
///
/// SwiftUI has no scroll gesture for a view that is not a scroll view, and the
/// plaque's speaker needs one — a volume slider would need somewhere to live,
/// and the plaque is deliberately five glyphs wide.
struct ScrollWheelModifier: ViewModifier {
    let onScroll: (Double) -> Void

    func body(content: Content) -> some View {
        content.background(ScrollWheelCatcher(onScroll: onScroll))
    }
}

extension View {
    func onScrollWheel(_ onScroll: @escaping (Double) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: onScroll))
    }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((Double) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            // Scaled well down: a trackpad reports scrolling in the tens per
            // flick, and volume that jumps from silent to full on one gesture
            // is not a control, it is a hazard.
            let delta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY / 400
                : event.scrollingDeltaY / 20

            guard delta != 0 else { return }
            onScroll?(Double(delta))
        }
    }
}
