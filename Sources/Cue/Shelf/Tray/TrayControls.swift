import AppKit
import SwiftUI

/// The small controls the open shelf is made of — the Dynamic Island's, down
/// to the numbers.
///
/// The island's buttons are 28pt squares with a 9pt radius holding a 12pt
/// medium symbol, white when chosen and 55% white when not. The pointer lifts
/// one by 2.2% and a press settles it back to 96.5%, on two different springs.
/// That pair of scales is the whole reason the panel feels physical rather than
/// painted on, and it is cheap: the feedback is local to a visible control, so
/// nothing recurring runs to produce it.

/// Hover lifts, press settles. Both amplitudes are tiny on purpose — this is
/// meant to be felt rather than watched — and both disappear under Reduce
/// Motion, where the wash alone still says the pointer is here.
struct TrayButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var lifts = true

    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.trayPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let active = enabled && hovered

        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(active ? palette.controlHover : .clear)
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(
                reduceMotion || !lifts
                    ? 1
                    : configuration.isPressed ? 0.965 : (active ? 1.022 : 1)
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                value: configuration.isPressed
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.75),
                value: hovered
            )
            .onHover { hovered = $0 }
    }
}

/// A header button: symbol only, a rounded square, 9pt radius.
///
/// The island's is always 28 across. This one shrinks to fit the menu bar it
/// has to sit in, because the header is in that strip now and a button taller
/// than the strip would hang out of the top of the screen.
struct TrayIconButton: View {
    let symbol: String
    let title: String
    var selected = false
    var size: CGFloat = 28
    let action: () -> Void

    @Environment(\.trayPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.iconInk(selected: selected))
                // A symbol that changes meaning should morph rather than swap.
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: symbol)
                .frame(width: size, height: size)
                .background(selected ? palette.controlFill(selected: true) : .clear, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(TrayButtonStyle(cornerRadius: 9))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The empty state: one symbol, and nothing else.
///
/// The island puts its empty states on a plate with a line of text under them,
/// because it has a dozen sections and has to say which one you are looking
/// at. Tray has one, and the shelf is already labelled — so the plate would be
/// a box around nothing and the text would be a caption naming the thing it is
/// written on. What survives the cut is the island's light weight and quiet
/// ink. No permanent onboarding screen (§5): this exists only while the shelf
/// is open and has nothing in it.
struct TrayEmptyState: View {
    let symbol: String
    /// The prompt lights up once a drag is actually overhead. With the text
    /// gone this is the whole of the feedback, so it is the symbol that
    /// changes as well as its weight of ink.
    var isLit = false
    /// Where it stands across the shelf — the same place the files will.
    var alignment: Alignment = .center

    @Environment(\.trayPalette) private var palette

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(palette.ink(isLit ? 0.85 : 0.4))
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .accessibilityHidden(true)
    }
}

/// The plate a control sits on. The base stays opaque; only what is on it is
/// ever tinted, and the outline appears only for Increase Contrast.
struct TrayControlSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    var selected = false

    @Environment(\.trayPalette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background(palette.controlFill(selected: selected), in: shape)
            .overlay {
                shape
                    .strokeBorder(
                        palette.ink(contrast == .increased ? 0.5 : 0),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func trayControlSurface(cornerRadius: CGFloat = 18, selected: Bool = false) -> some View {
        modifier(TrayControlSurface(cornerRadius: cornerRadius, selected: selected))
    }
}
