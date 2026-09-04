import SwiftUI

/// A three-by-three picker for where the panel appears.
///
/// The control is the thing it configures: nine positions in the shape of a
/// screen, so choosing "bottom right" is pointing at the bottom right rather
/// than reading a menu of nine similar phrases.
struct AnchorPicker: View {
    @Binding var selection: PanelAnchor

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(PanelAnchor.grid.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { anchor in
                        cell(anchor)
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary.opacity(0.4))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel position")
    }

    private func cell(_ anchor: PanelAnchor) -> some View {
        let isSelected = selection == anchor

        return Button {
            selection = anchor
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? AnyShapeStyle(CuePalette.accent) : AnyShapeStyle(.quaternary))
                .frame(width: 16, height: 11)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(anchor.title)
        .accessibilityLabel(anchor.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
