import SwiftUI

/// The closed shelf for a few seconds after headphones arrive: what they are
/// in the left wing, how full they are in the right.
///
/// The iPhone's AirPods moment, translated — the same two wings the music
/// uses, so the notch does not change shape to say it, only what it holds.
/// The ring shows the emptier ear; hovering says all three. Until the
/// system's report comes back the ring is an empty track, and it fills in.
struct ArrivalWings<Centre: View>: View {
    let arrival: HeadphonesWatcher.Arrival
    let cutout: CGSize
    @ViewBuilder let centre: () -> Centre

    @Environment(\.trayPalette) private var palette

    var body: some View {
        let artSize = TrayMetrics.wingArtSize(forHeight: cutout.height)
        let padding = TrayMetrics.wingPadding(forHeight: cutout.height)
        let shoulder = TrayMetrics.effectiveShoulder(forHeight: cutout.height)

        HStack(spacing: 0) {
            Image(systemName: arrival.kind.symbol)
                .font(.system(size: artSize * 0.72, weight: .regular))
                .foregroundStyle(palette.primaryInk)
                .frame(width: artSize, height: cutout.height)
                .padding(.horizontal, padding)
                .overlay { quietTarget }
                .padding(.leading, shoulder)

            Color.clear
                .frame(width: cutout.width, height: cutout.height)
                .overlay { centre() }

            BatteryRing(level: arrival.battery?.shown, diameter: artSize * 0.86)
                .frame(width: artSize, height: cutout.height)
                .padding(.horizontal, padding)
                .overlay { quietTarget }
                .padding(.trailing, shoulder)
        }
        .frame(height: cutout.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// Takes a click on a wing without doing anything with it, so the click
    /// neither reaches the shelf behind nor takes the keyboard (`TrayPanel`).
    private var quietTarget: some View {
        PillClickTarget(onSingle: nil, onDouble: {}, toolTip: toolTip)
    }

    private var toolTip: String {
        guard let battery = arrival.battery else { return "\(arrival.name) connected" }
        return "\(arrival.name) — \(battery.summary)"
    }

    private var label: String {
        guard let level = arrival.battery?.shown else { return "\(arrival.name) connected" }
        return "\(arrival.name) connected, battery \(level) percent"
    }
}

/// The iPhone's battery ring: a track, and an arc as full as the battery.
/// Green, until the emptier ear drops under a fifth.
private struct BatteryRing: View {
    let level: Int?
    let diameter: CGFloat

    @Environment(\.trayPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width = max(2.5, diameter * 0.15)
        let fraction = Double(level ?? 0) / 100

        ZStack {
            Circle()
                .stroke(palette.ink(0.18), lineWidth: width)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(colour, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter - width, height: diameter - width)
        .animation(reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.6), value: level)
    }

    private var colour: Color {
        (level ?? 100) < 20 ? .orange : .green
    }
}

/// The green line round the pill while headphones arrive: party mode's
/// outline, in one colour, standing still.
struct ArrivalBorder: View {
    let cornerRadius: CGFloat
    let shoulder: CGFloat

    var body: some View {
        let width: CGFloat = 2
        let outline = PartyOutline(cornerRadius: cornerRadius, shoulder: shoulder, gap: width / 2 + 1)

        ZStack {
            outline
                .stroke(Color.green, style: StrokeStyle(lineWidth: width * 1.6, lineCap: .round))
                .blur(radius: 4)
                .opacity(0.6)
            outline
                .stroke(Color.green, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
