import SwiftUI

/// The building blocks the settings window is made of.
///
/// The visual language — a sidebar, cards of rows, an icon and a title and a
/// line of explanation on the left with the control on the right — is the one
/// macOS itself uses in System Settings. Every value lives here rather than in
/// the panes, so the four panes cannot drift apart from each other.
enum SettingsMetrics {
    static let cardCornerRadius: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 11
    static let rowHorizontalPadding: CGFloat = 12
    static let iconColumnWidth: CGFloat = 22
    static let iconSpacing: CGFloat = 12

    /// Dividers start where the text starts, not where the icon does, so the
    /// icon column reads as one column rather than as a series of boxes.
    static var dividerInset: CGFloat { rowHorizontalPadding + iconColumnWidth + iconSpacing }

    static let sidebarWidth: CGFloat = 186
    // Wide enough that most row descriptions fit on one line, which is
    // what keeps the Tray pane from needing to be scrolled to reach its last
    // card.
    static let detailWidth: CGFloat = 504
    static let windowHeight: CGFloat = 528
}

/// A group of related rows.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                content
            }
            .background {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                    .padding(.top, 1)
            }
        }
    }
}

/// One row: a symbol, a label, an explanation, and whatever control the
/// setting actually needs.
struct SettingsRow<Trailing: View>: View {
    var icon: String
    var title: String
    var description: String?
    var tint: Color = .accentColor
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.iconSpacing) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: SettingsMetrics.iconColumnWidth, alignment: .center)
                // Symbols have their own baseline; align on the cap height of
                // the title instead so icon and text sit on one line.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))

                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing
                .labelsHidden()
        }
        .padding(.horizontal, SettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(icon: String, title: String, description: String? = nil, tint: Color = .accentColor) {
        self.init(icon: icon, title: title, description: description, tint: tint) { EmptyView() }
    }
}

/// The hairline between rows in a card.
struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, SettingsMetrics.dividerInset)
    }
}

/// A short status, the way System Settings states one: a coloured dot and a
/// word, not a sentence.
struct SettingsStatus: View {
    var text: String
    var colour: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(colour)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// An inset note inside a card — used where something needs explaining rather
/// than merely labelling, such as a login item the system has switched off.
struct SettingsCallout: View {
    var icon: String
    var tint: Color
    var text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .padding(.horizontal, SettingsMetrics.rowHorizontalPadding)
        .padding(.bottom, SettingsMetrics.rowVerticalPadding)
    }
}

/// The scrolling body of a pane: a lead sentence, then cards.
struct SettingsPaneLayout<Content: View>: View {
    var lead: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(lead)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                content
            }
            // Less at the top than the sides: the navigation title already
            // supplies the breathing room above the lead sentence, and adding
            // a full margin on top of it leaves a hole.
            .padding(.top, 6)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
