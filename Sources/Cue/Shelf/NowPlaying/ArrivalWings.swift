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
            Group {
                if let sheet = DeviceTurn.sheet(for: arrival.kind) {
                    DeviceTurn(sheet: sheet, size: cutout.height - 4)
                } else {
                    Image(systemName: arrival.kind.symbol)
                        .font(.system(size: artSize * 0.72, weight: .regular))
                        .foregroundStyle(palette.primaryInk)
                }
            }
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
        let width: CGFloat = 1.3
        let outline = PartyOutline(cornerRadius: cornerRadius, shoulder: shoulder, gap: width / 2 + 1)

        ZStack {
            outline
                .stroke(Color.green, style: StrokeStyle(lineWidth: width * 1.6, lineCap: .round))
                .blur(radius: 3)
                .opacity(0.45)
            outline
                .stroke(Color.green, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Headphones turning: one revolution over an arrival, the way the iPhone
/// shows AirPods when they connect.
///
/// Pre-rendered rather than drawn in 3D here — forty-eight studio-lit frames
/// in one sheet per model (Resources/*Turn.png): the AirPods Pro without
/// their case, and Sony's WH-1000XM5. What runs in the notch is choosing a
/// picture, not lighting a model. Drawn a little wider than the wing, centred
/// on it: the sheet's frames are square with room round the turn.
struct DeviceTurn: View {
    let frames: [CGImage]
    let size: CGFloat

    init(sheet frames: [CGImage], size: CGFloat) {
        self.frames = frames
        self.size = size
    }

    /// The frames for a kind of headphones, or `nil` when there is no model
    /// for it — the wing then shows the system's symbol.
    static func sheet(for kind: HeadphonesWatcher.Kind) -> [CGImage]? {
        switch kind {
        case .airPodsPro: frames(named: "AirPodsTurn")
        case .sonyXM5: frames(named: "HeadphonesXM5Turn")
        default: nil
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When this arrival's turn began.
    @State private var start = Date()

    /// One revolution, matched to how long an arrival shows.
    private static let period: TimeInterval = 4

    var body: some View {
        if !frames.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                // From the front, the moment it appears — the first frame is
                // the device facing you — and round once over the arrival.
                let index = reduceMotion
                    ? 0
                    : Int(max(0, context.date.timeIntervalSince(start)) / Self.period * Double(frames.count))
                        % frames.count
                Image(decorative: frames[index], scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            }
            // A soft light-grey glow behind the device, the way a product is
            // shot against a lit backdrop: just enough to lift a black pair of
            // headphones off the black notch, never enough to read as a disc.
            .background {
                RadialGradient(
                    colors: [Color(white: 0.85).opacity(0.13), Color(white: 0.85).opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.55
                )
                .frame(width: size * 1.1, height: size * 1.1)
                .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
        }
    }

    static let columns = 8
    static let side = 96

    private static var cache: [String: [CGImage]] = [:]

    /// A sheet cut into frames, once; `nil` when the sheet is missing.
    static func frames(named name: String) -> [CGImage]? {
        if let cached = cache[name] { return cached }
        guard let url = sheetURL(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let rows = sheet.height / side
        var frames: [CGImage] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(x: column * side, y: row * side, width: side, height: side)
                if let frame = sheet.cropping(to: rect) { frames.append(frame) }
            }
        }
        guard !frames.isEmpty else { return nil }
        cache[name] = frames
        return frames
    }

    private static func sheetURL(_ name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: "png") {
            return bundled
        }
        #if DEBUG
        // Tests and previews run outside the app bundle; the sheet is in the
        // source tree beside the other resources.
        let tree = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NowPlaying
            .deletingLastPathComponent()   // Shelf
            .deletingLastPathComponent()   // Cue
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repository
            .appendingPathComponent("Resources/\(name).png")
        return FileManager.default.fileExists(atPath: tree.path) ? tree : nil
        #else
        return nil
        #endif
    }
}

