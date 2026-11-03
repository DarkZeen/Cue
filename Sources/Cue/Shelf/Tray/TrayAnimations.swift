import AppKit
import SwiftUI

/// The tray's motion, in one place (§44).
///
/// Three layers move differently on purpose (§15, §45). The container is the
/// heaviest thing on screen and settles softly; items arriving carry a little
/// more energy because the user just threw them; removal is quick because a
/// departure should not be dwelt on; hover is barely there. Applying one
/// global spring to everything is what makes an interface read as "SwiftUI
/// with `.animation()` everywhere" rather than as a designed object.
///
/// Every value here is a starting point to be judged by eye on real hardware.
enum TrayAnimation {
    // MARK: Response — how quickly a spring reaches its target, in seconds.

    static let hoverResponse = 0.24
    static let expandResponse = 0.32

    /// Closing is quicker than opening, not slower.
    ///
    /// §45 asks for a collapse that is "slightly slower and smoother", and that
    /// was right when a 0.65s grace period ran before it. The shelf now closes
    /// the moment the pointer leaves, so the spring's own settle is the entire
    /// delay the user perceives — and half a second of it on the exit of the
    /// most-seen element in the app reads as lag. An exit is the part you have
    /// already stopped caring about; it should get out of the way.
    static let collapseResponse = 0.26
    static let itemEntranceResponse = 0.34
    static let itemRemovalResponse = 0.20
    static let itemShiftResponse = 0.30

    // MARK: Damping — 1.0 settles without overshoot, lower bounces.

    /// The container never overshoots. A shelf that wobbles reads as cheap.
    static let expandDamping = 0.86
    /// Nearly critical: a quick exit that also overshoots would read as a flinch.
    static let collapseDamping = 0.95
    static let hoverDamping = 0.90
    /// Items get the only real bounce in the product, and only a hint of one,
    /// because the gesture that delivered them carried momentum.
    static let itemEntranceDamping = 0.74
    static let itemRemovalDamping = 1.0
    static let itemShiftDamping = 0.88

    // MARK: Timings

    /// Long enough that crossing the menu bar does not open the tray; short
    /// enough that deliberately going there feels immediate (§12).
    static let hoverActivationDelay: TimeInterval = 0.10

    /// The grace period after the pointer leaves. Covers the gap between
    /// dropping one file and going to fetch the next (§17).
    static let collapseDelay: TimeInterval = 0.65

    /// A drag leaving the drop area gets longer rope — a drag that clips the
    /// edge of the target should not slam the shelf shut mid-gesture.
    static let dragExitGrace: TimeInterval = 0.35

    // MARK: Built animations
    //
    // Deliberately absent. Animations are built by `TrayMotion` below, from a
    // motion preference SwiftUI can observe. A static accessor here would work
    // exactly once — nothing invalidates when Reduce Motion is switched — and
    // having one available is how that bug comes back.

    /// The compression when something lands, and the settle out of it (§46).
    ///
    /// Underdamped on purpose and only here: the overshoot *is* the "0.96 then
    /// 1.02 then 1.00" the spec describes, produced by physics rather than by
    /// hand-keyframing three values.
    static let dropImpactResponse = 0.26
    static let dropImpactDamping = 0.55

    /// How long the tray stays compressed before springing back.
    static let dropImpactDuration: TimeInterval = 0.09
}

/// The tray's animations, resolved against the viewer's motion preference.
///
/// A value in the environment rather than a set of static properties, for the
/// same reason `TrayPalette` is: SwiftUI has to be able to *see* the input
/// change. Reading `NSWorkspace.accessibilityDisplayShouldReduceMotion`
/// directly from a view body works exactly once — nothing invalidates when the
/// setting is switched, so the tray keeps springing until the app is
/// relaunched.
struct TrayMotion: Equatable, Sendable {
    var reduceMotion: Bool

    static let standard = TrayMotion(reduceMotion: false)

    /// Reduced motion is not *no* motion — it is a short, non-vestibular
    /// equivalent. Springs and overshoot go; a brief fade stays, because
    /// removing all feedback loses information (§50).
    private var reducedSubstitute: Animation { .easeOut(duration: 0.14) }

    private func spring(_ response: Double, _ damping: Double) -> Animation {
        if reduceMotion { return reducedSubstitute }
        return .spring(response: response, dampingFraction: damping, blendDuration: 0.05)
    }

    var expand: Animation {
        spring(TrayAnimation.expandResponse, TrayAnimation.expandDamping)
    }

    var collapse: Animation {
        spring(TrayAnimation.collapseResponse, TrayAnimation.collapseDamping)
    }

    var hover: Animation {
        spring(TrayAnimation.hoverResponse, TrayAnimation.hoverDamping)
    }

    var itemEntrance: Animation {
        spring(TrayAnimation.itemEntranceResponse, TrayAnimation.itemEntranceDamping)
    }

    var itemShift: Animation {
        spring(TrayAnimation.itemShiftResponse, TrayAnimation.itemShiftDamping)
    }

    var dropImpact: Animation {
        spring(TrayAnimation.dropImpactResponse, TrayAnimation.dropImpactDamping)
    }

    /// A colour change is not a movement, so it gets a plain curve rather than
    /// the spring the pointer feedback uses.
    var appearance: Animation {
        reduceMotion ? reducedSubstitute : .easeOut(duration: 0.20)
    }

    /// How an item arrives and leaves (§45, §46). No fireworks.
    var itemTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            // Files travel *upward* into the tray, so an arriving item comes
            // from below (§4). The scale stays inside the 0.9–0.97 band the
            // departure amplitude already respects — the old 0.72 was nearly
            // twice the exit's and read as a pop.
            insertion: .scale(scale: 0.90)
                .combined(with: .opacity)
                .combined(with: .offset(y: 10)),
            removal: .scale(scale: TrayScale.itemDeparting).combined(with: .opacity)
        )
    }
}

private struct TrayMotionKey: EnvironmentKey {
    static let defaultValue = TrayMotion.standard
}

extension EnvironmentValues {
    var trayMotion: TrayMotion {
        get { self[TrayMotionKey.self] }
        set { self[TrayMotionKey.self] = newValue }
    }
}

/// Scale values for interaction feedback (§13, §46).
///
/// The amplitudes are tiny on purpose. Everything here is meant to be felt
/// rather than watched.
enum TrayScale {
    static let resting: CGFloat = 1.0
    /// A drag is approaching but has not entered the drop area.
    static let dragApproaching: CGFloat = 1.03
    /// The pointer is inside and a drop would land.
    static let dropTargetActive: CGFloat = 1.04
    /// Pointer resting on a single item.
    static let itemHover: CGFloat = 1.025
    /// An item picked up and being carried out.
    static let itemLifted: CGFloat = 1.04
    /// The compression at the instant of a drop, before it settles back.
    static let dropImpact: CGFloat = 0.97
    /// An item on its way out.
    static let itemDeparting: CGFloat = 0.86
}
