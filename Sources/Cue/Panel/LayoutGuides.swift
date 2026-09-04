import AppKit
import SwiftUI

/// The alignment guides shown while the layout is being edited, and the maths
/// that makes things settle onto them.
enum LayoutGuides {
    /// Fractions of the free space a surface can be dragged through: hard
    /// against either edge, the thirds, and the middle.
    ///
    /// Thirds as well as the centre because two floating surfaces are usually
    /// being arranged *relative to each other* rather than to the screen, and
    /// the thirds are where that tends to land.
    static let fractions: [CGFloat] = [0, 1.0 / 3, 0.5, 2.0 / 3, 1]

    /// How close a drag has to come before the guide takes it.
    ///
    /// Eight points is about a finger's worth of imprecision on a trackpad:
    /// enough that aiming for the centre lands on it, small enough that
    /// deliberately sitting just off-centre is still possible.
    static let pull: CGFloat = 8

    /// The increment ⇧ constrains a resize to.
    static let sizeStep: CGFloat = 20

    /// Pulls a position onto a guide when it is close enough.
    ///
    /// Works in the free space — the room a surface has to move in — rather
    /// than in screen coordinates, so the same fractions mean the same thing on
    /// a laptop display and a monitor.
    static func snap(offset: CGFloat, free: CGFloat) -> CGFloat {
        guard free > 0 else { return 0 }

        let clamped = min(max(offset, 0), free)
        for fraction in fractions {
            let guidePosition = fraction * free
            if abs(clamped - guidePosition) <= pull { return guidePosition }
        }
        return clamped
    }

    /// Rounds a size to the nearest step, for a ⇧-constrained resize.
    static func step(_ value: CGFloat) -> CGFloat {
        (value / sizeStep).rounded() * sizeStep
    }
}

/// The full-screen overlay drawn behind the surfaces being arranged.
///
/// Its own window rather than something drawn inside the panel, because the
/// guides describe the *screen* — they have to reach the edges the panel is
/// being aligned to, and a panel cannot draw outside itself.
struct LayoutGuidesView: View {
    let bounds: CGSize
    let onDone: () -> Void

    var body: some View {
        ZStack {
            guides

            VStack {
                Spacer()
                hint
                    .padding(.bottom, 28)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    private var guides: some View {
        Canvas { context, size in
            // Grey and translucent rather than coloured: these are scaffolding
            // to align against, and a guide that competes with the thing being
            // aligned is working against itself.
            let style = StrokeStyle(lineWidth: 1, dash: [5, 5])
            let colour = Color.white.opacity(0.22)

            for fraction in LayoutGuides.fractions {
                var vertical = Path()
                vertical.move(to: CGPoint(x: size.width * fraction, y: 0))
                vertical.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                context.stroke(vertical, with: .color(colour), style: style)

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: size.height * fraction))
                horizontal.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(horizontal, with: .color(colour), style: style)
            }
        }
    }

    private var hint: some View {
        HStack(spacing: 14) {
            Label("Drag to move", systemImage: "hand.draw")
            Label("Drag the edge to resize", systemImage: "arrow.left.and.right")
            Label("⇧ for steps", systemImage: "square.grid.3x3")

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.85))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color(white: 0.11).opacity(0.94))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

/// The window the guides live in.
final class LayoutGuidesPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isRestorable = false

        // Genuinely below the panel and the plaque, not merely ordered behind
        // them. Both are `.floating`; a full-screen window at the same level
        // ordered in last sits on top and swallows every drag aimed at the
        // things it is supposed to be helping you place.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    /// Key, unlike Cue's other panels: Escape has to end the edit, and the Done
    /// button has to be clickable.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
    var onCancel: (() -> Void)?
}


/// Runs an arranging session: guides up, both surfaces movable, and everything
/// back as it was when it ends.
@MainActor
final class LayoutEditor {
    private var guides: LayoutGuidesPanel?
    private let logger = Diagnostics.logger("layout-editor")

    /// Raised so the session's owner can put its own surfaces back.
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?

    private(set) var isEditing = false

    func toggle() {
        isEditing ? end() : begin()
    }

    func begin() {
        guard !isEditing else { return }
        isEditing = true

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let panel = LayoutGuidesPanel(contentRect: frame)
        panel.onCancel = { [weak self] in self?.end() }

        let view = LayoutGuidesView(
            bounds: frame.size,
            onDone: { [weak self] in self?.end() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hosting
        panel.setFrame(frame, display: true)

        self.guides = panel

        NSApp.activate()
        panel.orderFrontRegardless()

        onBegin?()

        // The surfaces are ordered front after the guides on purpose: the
        // guides are the backdrop, and the things being arranged have to be
        // both visible and clickable above them.
        logger.notice("Arranging the layout.")
    }

    func end() {
        guard isEditing else { return }
        isEditing = false

        guides?.orderOut(nil)
        guides = nil

        onEnd?()
        logger.notice("Finished arranging.")
    }
}
