import SwiftUI

/// How one set of wings hands over to another: into the notch, and out.
///
/// When headphones have been shown, they do not fade in place — the device
/// and its battery shrink toward the middle and are gone under the camera,
/// and a beat later the music grows back out of the same place into the
/// wings. Scaled about the pill's centre, which is the housing's: everything
/// in the wings travels inward as it shrinks, so on a notched Mac it reads as
/// being drawn under the camera rather than switched off. Unhurried — about
/// half a second in, a beat, and half a second out — so it reads as a
/// movement rather than a cut. Under Reduce Motion,
/// a plain fade.
struct SinkIntoNotch: ViewModifier {
    /// 0 is in place; 1 is gone under the notch.
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.78 * progress, anchor: .center)
            .opacity(1 - progress)
            .blur(radius: 2.5 * progress)
    }
}

extension AnyTransition {
    /// How a set of wings comes in.
    enum WingsEntrance {
        /// Out of the notch, a beat after the set it replaces has gone in.
        case handover
        /// Out of the notch at once — nothing was there to go first.
        case fromNotch
        /// A plain fade: the shelf closing over wings that were there all
        /// along, or music simply starting.
        case fade
    }

    /// One set of wings sinking into the notch as the next comes out of it.
    /// Going, a set always sinks; coming, it depends on what it replaces.
    static func wings(reduceMotion: Bool, entrance: WingsEntrance) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(.easeOut(duration: 0.2)) }
        let sink = AnyTransition.modifier(
            active: SinkIntoNotch(progress: 1),
            identity: SinkIntoNotch(progress: 0)
        )
        let rise = Animation.spring(response: 0.75, dampingFraction: 0.82)
        let insertion: AnyTransition = switch entrance {
        case .handover: sink.animation(rise.delay(0.5))
        case .fromNotch: sink.animation(rise)
        case .fade: .opacity.animation(.easeOut(duration: 0.2))
        }
        return .asymmetric(
            insertion: insertion,
            // In, accelerating, the way something is pulled.
            removal: sink.animation(.easeIn(duration: 0.55))
        )
    }
}
