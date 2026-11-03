import AppKit
import SwiftUI

/// The tray's physical surface (§6, §47, §48) — the Dynamic Island's silhouette.
///
/// One shape, one material, from closed cutout to open shelf. The whole point
/// of §16 is that this surface never fades out and back in — it changes shape
/// continuously, so it reads as a single object rather than two views
/// cross-dissolving.
///
/// The island's outline, point for point: the shape spans its full width where
/// it meets the top of the display, curves *inwards* over a 14pt shoulder, runs
/// straight down, and rounds off at the bottom. The concave shoulder is the
/// whole trick — it is what the hardware does where the housing meets the
/// bezel, and it is why the shape reads as carved out of the display rather
/// than hung underneath it.
struct TraySurface: InsettableShape {
    var cornerRadius: CGFloat

    /// How far each side draws in from the top edge. Zero gives a plain
    /// square-shouldered shape, which is what the closed cutout wants.
    var shoulder: CGFloat = TrayMetrics.shoulder

    var inset: CGFloat = 0

    /// Both curves interpolate, so the corner tightens and the shoulder draws
    /// in as part of the same motion rather than snapping when the state
    /// changes.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, shoulder) }
        set {
            cornerRadius = newValue.first
            shoulder = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> TraySurface {
        TraySurface(cornerRadius: cornerRadius, shoulder: shoulder, inset: inset + amount)
    }

    func path(in rect: CGRect) -> Path {
        let body = rect.insetBy(dx: inset, dy: inset)
        guard body.width > 0, body.height > 0 else { return Path() }

        // A shoulder taller than a third of the shape would swallow it, so a
        // short surface gets a proportionally shorter one. The closed cutout
        // relies on this: the same constant that shapes a 200pt shelf has to
        // behave on a 32pt housing.
        let shoulder = max(0, min(self.shoulder, body.height * 0.28, body.width / 2))
        let bottom = max(0, min(cornerRadius, body.height / 2, (body.width - shoulder * 2) / 2))

        // The magic number that turns a Bézier into a quarter circle.
        let tangent: CGFloat = 0.55228475

        var path = Path()
        path.move(to: CGPoint(x: body.minX, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY))

        // In over the right shoulder.
        path.addCurve(
            to: CGPoint(x: body.maxX - shoulder, y: body.minY + shoulder),
            control1: CGPoint(x: body.maxX - shoulder * tangent, y: body.minY),
            control2: CGPoint(x: body.maxX - shoulder, y: body.minY + shoulder * (1 - tangent))
        )

        // Down the right wall and round the bottom-right corner.
        path.addLine(to: CGPoint(x: body.maxX - shoulder, y: body.maxY - bottom))
        path.addCurve(
            to: CGPoint(x: body.maxX - shoulder - bottom, y: body.maxY),
            control1: CGPoint(x: body.maxX - shoulder, y: body.maxY - bottom * (1 - tangent)),
            control2: CGPoint(x: body.maxX - shoulder - bottom * (1 - tangent), y: body.maxY)
        )

        // Along the bottom and round the bottom-left corner.
        path.addLine(to: CGPoint(x: body.minX + shoulder + bottom, y: body.maxY))
        path.addCurve(
            to: CGPoint(x: body.minX + shoulder, y: body.maxY - bottom),
            control1: CGPoint(x: body.minX + shoulder + bottom * (1 - tangent), y: body.maxY),
            control2: CGPoint(x: body.minX + shoulder, y: body.maxY - bottom * (1 - tangent))
        )

        // Up the left wall and out over the left shoulder.
        path.addLine(to: CGPoint(x: body.minX + shoulder, y: body.minY + shoulder))
        path.addCurve(
            to: CGPoint(x: body.minX, y: body.minY),
            control1: CGPoint(x: body.minX + shoulder, y: body.minY + shoulder * (1 - tangent)),
            control2: CGPoint(x: body.minX + shoulder * tangent, y: body.minY)
        )

        path.closeSubpath()
        return path
    }
}

/// The material treatment applied to `TraySurface`.
///
/// The island's answer to this is one line: the base is opaque black and
/// nothing else. No shadow, no edge highlight, no stroke — a camera housing
/// has none of those, and every one of them would give away that this is a
/// window rather than a hole. The only outline that ever appears is the one
/// Increase Contrast asks for.
///
/// Every colour still comes from the palette, so the two alternative surfaces
/// remain one change rather than thirty (§49).
struct TraySurfaceStyle: ViewModifier {
    var cornerRadius: CGFloat
    var shoulder: CGFloat
    /// Slightly stronger blur while a drag is over the target (§14, step 5).
    var isEmphasised: Bool
    /// The optional dashed outline marking the drop area, and how far inside
    /// the surface edge it sits.
    var showsDropOutline: Bool
    var dropOutlineInset: CGFloat = TrayMetrics.defaultDropOutlineInset
    /// Space at the top the camera housing covers. The outline starts below it,
    /// so the whole border is visible rather than having its top run disappear
    /// into the notch.
    var contentTop: CGFloat = 0

    @Environment(\.trayPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: TraySurface {
        TraySurface(cornerRadius: cornerRadius, shoulder: shoulder)
    }

    /// The dashed outline is a plain rounded rectangle — rounded on all four
    /// corners, not just the two the surface rounds.
    ///
    /// The surface has square shoulders because it hangs off the top edge of
    /// the display and has nowhere else to go. The outline sits *inside* it,
    /// where nothing is holding its top corners square, so squaring them only
    /// made it look unfinished.
    private var outlineShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: TrayMetrics.dropOutlineCornerRadius,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(palette.surfaceFill(reduceTransparency: reduceTransparency))
                    .background {
                        // Skipped under reduced transparency, where a solid
                        // surface is both the accessible answer and the cheaper
                        // one — and skipped for the island, which is opaque by
                        // definition.
                        if palette.usesMaterial && !reduceTransparency {
                            shape.fill(.ultraThinMaterial)
                        }
                    }
            }
            .overlay {
                // An edge highlight, not a stroke (§48). The island has none;
                // the translucent surfaces need one, or they have no edge
                // against a wallpaper their own colour.
                let highlight = palette.edgeHighlight(isEmphasised: isEmphasised)
                shape.strokeBorder(
                    LinearGradient(
                        colors: [highlight.top, highlight.bottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
            .overlay {
                // The island's one concession: someone who cannot see a black
                // shape against a dark wallpaper gets an outline that says
                // where it ends.
                if contrast == .increased {
                    shape
                        .strokeBorder(palette.ink(0.5), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if showsDropOutline {
                    outlineShape
                        .stroke(
                            palette.dropOutlineInk,
                            style: StrokeStyle(
                                lineWidth: 1,
                                dash: [TrayMetrics.dropOutlineDash, TrayMetrics.dropOutlineGap]
                            )
                        )
                        .padding(.horizontal, dropOutlineInset + shoulder)
                        .padding(.bottom, dropOutlineInset)
                        .padding(.top, contentTop)
                }
            }
            .compositingGroup()
            .shadow(color: shadow.colour, radius: shadow.radius, x: 0, y: shadow.y)
    }

    private var shadow: (colour: Color, radius: CGFloat, y: CGFloat) {
        palette.shadow ?? (.clear, 0, 0)
    }
}

extension View {
    func traySurface(
        cornerRadius: CGFloat,
        shoulder: CGFloat = TrayMetrics.shoulder,
        isEmphasised: Bool = false,
        showsDropOutline: Bool = false,
        dropOutlineInset: CGFloat = TrayMetrics.defaultDropOutlineInset,
        contentTop: CGFloat = 0
    ) -> some View {
        modifier(
            TraySurfaceStyle(
                cornerRadius: cornerRadius,
                shoulder: shoulder,
                isEmphasised: isEmphasised,
                showsDropOutline: showsDropOutline,
                dropOutlineInset: dropOutlineInset,
                contentTop: contentTop
            )
        )
    }
}
