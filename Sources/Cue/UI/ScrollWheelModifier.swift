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


/// Two-finger horizontal swipes, reported once per gesture.
///
/// SwiftUI has no gesture for this: `DragGesture` never sees a trackpad scroll,
/// and a raw scroll-wheel handler fires dozens of times across one flick. So
/// the movement is accumulated within a gesture and reported once, after which
/// the direction is locked until the fingers lift — otherwise a single
/// enthusiastic swipe pages three times.
struct HorizontalSwipeModifier: ViewModifier {
    let onSwipe: (Int) -> Void

    func body(content: Content) -> some View {
        content.background(SwipeCatcher(onSwipe: onSwipe))
    }
}

extension View {
    /// `-1` for a swipe left, `+1` for a swipe right.
    func onHorizontalSwipe(_ onSwipe: @escaping (Int) -> Void) -> some View {
        modifier(HorizontalSwipeModifier(onSwipe: onSwipe))
    }
}

private struct SwipeCatcher: NSViewRepresentable {
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onSwipe = onSwipe
    }

    final class CatcherView: NSView {
        var onSwipe: ((Int) -> Void)?

        private var travelled: CGFloat = 0
        private var handled = false

        /// How far two fingers must travel before it counts.
        ///
        /// Low enough that a deliberate flick works, high enough that scrolling
        /// past the panel on the way somewhere else does not turn a page.
        private static let threshold: CGFloat = 42

        override func scrollWheel(with event: NSEvent) {
            // Momentum is not intent. After the fingers lift, macOS keeps
            // sending events for the coast — and since the gesture had already
            // "ended" by then, the accumulator had reset and each burst of
            // momentum counted as a fresh swipe. One flick paged to the end.
            guard event.momentumPhase == [] else { return }

            switch event.phase {
            case .began:
                travelled = 0
                handled = false
            case .ended, .cancelled:
                travelled = 0
                handled = false
                return
            default:
                break
            }

            // Vertical intent is not horizontal intent. Without this a diagonal
            // scroll pages sideways while the user is trying to scroll a list.
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }

            travelled += event.scrollingDeltaX
            guard !handled, abs(travelled) >= Self.threshold else { return }

            handled = true
            // Natural scrolling: fingers moving left carry the content left,
            // which reveals the page to the *right*.
            onSwipe?(travelled < 0 ? 1 : -1)
        }
    }
}
