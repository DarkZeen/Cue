import SwiftUI

/// How one set of wings hands over to another: into the notch, and out.
///
/// When headphones have been shown, they do not fade in place — the device
/// and its battery shrink toward the middle and are gone under the camera,
/// and a beat later the music grows back out of the same place into the
/// wings. Scaled about the pill's centre, which is the housing's: everything
/// in the wings travels inward as it shrinks, so on a notched Mac it reads as
/// being drawn under the camera rather than switched off. Under Reduce Motion,
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
    /// One set of wings sinking into the notch as the next comes out of it.
    static func wings(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(.easeOut(duration: 0.2)) }
        let sink = AnyTransition.modifier(
            active: SinkIntoNotch(progress: 1),
            identity: SinkIntoNotch(progress: 0)
        )
        return .asymmetric(
            // Out after the old ones have gone in, with a little spring as
            // they reach the wings.
            insertion: sink.animation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.26)),
            // In quickly, accelerating, the way something is pulled.
            removal: sink.animation(.easeIn(duration: 0.26))
        )
    }
}
