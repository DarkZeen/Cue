import SwiftUI

/// The panel's motion, in one place.
///
/// Three rules held it together and are worth stating, because the temptation
/// with an overlay like this is always to add more:
///
/// * **In is faster than out.** Appearing has to keep up with the keystroke
///   that asked for it; leaving is allowed to be seen, because it is what tells
///   the user the click landed.
/// * **The panel scales from just below one.** 0.96, not 0.8. A big scale
///   reads as a zoom and draws attention to the animation; a small one reads as
///   the surface arriving.
/// * **Nothing bounces.** A spring that overshoots is playful, and this is a
///   thing people hit forty times a day. Forty overshoots a day is a tic.
enum CueAnimation {
    /// Appearing. Short, and slightly springy without overshoot.
    static let present = Animation.spring(response: 0.26, dampingFraction: 1.0)

    /// Leaving. Longer than arriving so the dismissal is legible rather than a
    /// disappearance the eye reads as a glitch.
    static let dismiss = Animation.easeOut(duration: 0.16)

    /// Real seconds for `dismiss`, because AppKit has to order the window out
    /// after the animation and cannot ask SwiftUI when it finished.
    static let dismissDuration: Duration = .milliseconds(160)

    /// Growing and shrinking between the grid and the results list. The window
    /// frame changes with it, so it is deliberately quick — a resizing window
    /// is the one thing here that cannot be made to look weightless.
    static let resize = Animation.spring(response: 0.22, dampingFraction: 1.0)
    static let resizeDuration: TimeInterval = 0.22

    /// Selection moving between rows and tiles. Fast enough to keep up with a
    /// held arrow key.
    static let selection = Animation.easeOut(duration: 0.12)

    /// Moving between the gallery's pages.
    ///
    /// Slightly slower than the selection, because a whole page is travelling
    /// and the eye needs to see it arrive rather than notice it has changed.
    /// Still no overshoot: three pages held by arrow keys would bounce three
    /// times.
    static let page = Animation.spring(response: 0.34, dampingFraction: 1.0)

    static let startScale: CGFloat = 0.96
    /// Two points of downward travel on the way in. Enough to read as arriving
    /// from somewhere, not enough to notice as movement.
    static let startOffset: CGFloat = -6
}
