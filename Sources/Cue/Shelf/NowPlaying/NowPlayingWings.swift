import AppKit
import SwiftUI
import os

/// The closed shelf while Cue is playing: the cover in the left wing, the
/// housing in the middle, Cue's mark in the right wing.
///
/// The Dynamic Island's live activity, translated. The wings live inside the
/// same surface as the housing — `TrayShape.nowPlaying` widens it — so this
/// only fills the shape; it never draws one of its own (§16). The middle
/// segment is exactly the housing's width and holds whatever the closed shelf
/// already showed there, unchanged: on a notched Mac that is under the camera
/// and invisible, on any other display it is the shelf's own dots (§76).
///
/// Two clicks do things here and one click does one thing. The mark plays and
/// pauses on one click and skips on two; the cover likes the song on two, and
/// a heart springs out of it to say so. Neither wing opens the shelf: the
/// window keeps them out of the hover strip (§74, §75).
struct NowPlayingWings<Centre: View>: View {
    let source: NowPlayingSource
    let track: NowPlayingSource.Track
    /// The housing the wings hang either side of.
    let cutout: CGSize
    /// Raised the moment the cover is double-clicked, before the page has
    /// answered, so the heart is drawn where nothing clips it.
    let onLike: () -> Void
    @ViewBuilder let centre: () -> Centre

    @Environment(\.trayPalette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cover's colour, made legible on this surface. `nil` for covers
    /// that have none — the mark is then the surface's own ink. Starts from
    /// whatever the wings showed last, so opening and closing the shelf, which
    /// rebuilds them, does not flash the mark white.
    @State private var tint: Color?

    init(
        source: NowPlayingSource,
        track: NowPlayingSource.Track,
        cutout: CGSize,
        onLike: @escaping () -> Void,
        @ViewBuilder centre: @escaping () -> Centre
    ) {
        self.source = source
        self.track = track
        self.cutout = cutout
        self.onLike = onLike
        self.centre = centre
        _tint = State(initialValue: source.tints.current)
    }

    /// How long a track change holds the last cover's colour while the new
    /// cover loads, before giving up on it and going back to the ink.
    private static var tintHold: Duration { .seconds(3) }

    /// Waits between asks for a cover that has not arrived. The thumbnail
    /// cache tries each request once and forgets failures, and evicts the
    /// oldest covers as the gallery fills it; nothing else in Cue asks for
    /// the playing track's cover, so the wings keep asking.
    private static var artworkRetries: [Duration] { [.zero, .seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)] }

    private static var logger: Logger { Diagnostics.logger("now-playing") }

    var body: some View {
        // Read here, not in the wing, so the tint below can be keyed on it.
        // Reading it also reads the provider's version, so a cover landing
        // redraws this — and only this, not the shelf around it.
        let image = source.artwork(track.artworkURL)

        HStack(spacing: 0) {
            artWing(image)
            // Held open by something that is always there: an empty shelf
            // has no dots, and a frame around nothing takes no room at all,
            // which folds the two wings together in the middle.
            Color.clear
                .frame(width: cutout.width, height: cutout.height)
                .overlay { centre() }
            waveWing
        }
        .frame(height: cutout.height)
        .task(id: ArtworkRequest(url: track.artworkURL, hasImage: image != nil)) {
            // `task(id:)`, not `onAppear`, for the reason `ArtworkTileView`
            // gives: the cover changes under a view that is already there.
            // Keyed on whether it has arrived too, so a cover the cache has
            // since dropped is asked for again the moment it goes.
            guard image == nil, let url = track.artworkURL else { return }
            for wait in Self.artworkRetries {
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                source.prefetchArtwork(url)
            }
        }
        .task(id: TintKey(
            artworkURL: track.artworkURL,
            hasImage: image != nil,
            groundLuminance: palette.groundLuminance,
            isPlain: contrast == .increased
        )) {
            await updateTint(from: image)
        }
    }

    // MARK: - Metrics

    private var artSize: CGFloat { TrayMetrics.wingArtSize(forHeight: cutout.height) }
    private var padding: CGFloat { TrayMetrics.wingPadding(forHeight: cutout.height) }
    private var shoulder: CGFloat { TrayMetrics.effectiveShoulder(forHeight: cutout.height) }

    // MARK: - The cover

    private func artWing(_ image: NSImage?) -> some View {
        PillArt(
            image: image,
            size: artSize,
            cornerRadius: TrayMetrics.wingArtRadius(forHeight: cutout.height)
        )
        .frame(width: artSize, height: cutout.height)
        .padding(.horizontal, padding)
        .contentShape(.rect)
        .overlay {
            // A lone click on the cover does nothing, so its double click has
            // nothing to wait for.
            PillClickTarget(onSingle: nil, onDouble: like, toolTip: toolTip)
        }
        // In from the outer wall by the shoulder the surface draws in over,
        // so the cover sits inside the visible body rather than under the
        // curve where the shape meets the bezel. Outside the click target:
        // the menu bar shows through there (`TrayShape.wingRects`).
        .padding(.leading, shoulder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(artLabel)
        .accessibilityAddTraits(.isImage)
        .modifier(PillActions(source: source, track: track, like: like))
        .help(toolTip)
    }

    /// Optimistic: the heart goes up at once and the page is asked after.
    /// Waiting for a web view to confirm a like that is idempotent anyway
    /// would put a visible pause between the click and its answer. A failure
    /// is only logged — the page is the record, and an apologetic animation
    /// for a like that did not reach it would be noise.
    private func like() {
        onLike()
        let videoID = track.videoID
        let like = source.like
        Task {
            if !(await like(videoID)) {
                Self.logger.notice("Like for \(videoID, privacy: .public) did not reach the page.")
            }
        }
    }

    // MARK: - The mark

    private var waveWing: some View {
        PillWave(source: source, isPlaying: track.isPlaying, tint: markColour)
            .frame(width: artSize, height: cutout.height)
            .padding(.horizontal, padding)
            .contentShape(.rect)
            .overlay {
                PillClickTarget(
                    onSingle: { source.togglePlayPause() },
                    onDouble: { source.next() },
                    toolTip: toolTip
                )
            }
            .padding(.trailing, shoulder)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(waveLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { source.togglePlayPause() }
            .modifier(PillActions(source: source, track: track, like: like))
            .help(toolTip)
    }

    /// The cover's colour, or the surface's ink until there is one.
    ///
    /// This is the one place Cue's mark is anything but white on black.
    /// `CuePalette` keeps the mark white everywhere else and that rule stands;
    /// here the mark sits beside the cover it is playing, and taking the
    /// cover's colour is what ties the two wings into one object. It applies
    /// to the mark only — never to the surface, which stays the housing.
    private var markColour: Color {
        tint ?? palette.primaryInk
    }

    private struct ArtworkRequest: Equatable {
        var url: URL?
        var hasImage: Bool
    }

    private struct TintKey: Equatable {
        var artworkURL: URL?
        var hasImage: Bool
        var groundLuminance: Double
        /// Increase Contrast: the mark stays the surface's ink.
        var isPlain: Bool
    }

    private func updateTint(from image: NSImage?) async {
        let ground = palette.groundLuminance
        let next: Color?

        if contrast == .increased {
            // Increase Contrast: the surface's own ink, always.
            next = nil
        } else if track.artworkURL != nil, image == nil {
            // A new track whose cover has not landed: keep the last colour
            // rather than flash white between two tinted ones. If the cover
            // never comes, let go of a colour that belongs to another song.
            try? await Task.sleep(for: Self.tintHold)
            guard !Task.isCancelled else { return }
            next = nil
        } else if let url = track.artworkURL, let image {
            let key = ArtworkTintMemory.Key(artworkURL: url, groundLuminance: ground)
            if let known = source.tints.tint(for: key) {
                next = known
            } else {
                var worked: Color?
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let rgb = await ArtworkTint.tint(for: cgImage, groundLuminance: ground) {
                    worked = Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
                }
                guard !Task.isCancelled else { return }
                source.tints.remember(worked, for: key)
                next = worked
            }
        } else {
            // No cover at all.
            next = nil
        }

        guard !Task.isCancelled else { return }
        source.tints.current = next
        guard next != tint else { return }

        // A change of colour, not a movement: under Reduce Motion it is still
        // a fade, just a shorter one.
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.35)) {
            tint = next
        }
    }

    // MARK: - Words

    private var toolTip: String {
        track.artist.map { "\(track.title) — \($0)" } ?? track.title
    }

    private var artLabel: String {
        track.artist.map { "Album art, \(track.title) by \($0)" } ?? "Album art, \(track.title)"
    }

    private var waveLabel: String {
        "\(track.isPlaying ? "Pause" : "Play") \(track.title)"
    }
}

/// The three things either wing can be asked to do without a pointer.
///
/// Both wings carry all three, so whichever one VoiceOver lands on can do
/// what the other does with a double click.
private struct PillActions: ViewModifier {
    let source: NowPlayingSource
    let track: NowPlayingSource.Track
    let like: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: track.isPlaying ? "Pause" : "Play") {
                source.togglePlayPause()
            }
            .accessibilityAction(named: "Next Track") { source.next() }
            .accessibilityAction(named: "Like") { like() }
    }
}

// MARK: - The cover

/// The cover, a small rounded tile. A quiet placeholder until it arrives —
/// not a spinner, for the reason `ArtworkTileView` gives.
private struct PillArt: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.trayPalette) private var palette

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            palette.controlFill(selected: true)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    // Video tracks bring 16:9 frames with bars; filling the
                    // square crops the bars rather than drawing them.
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                CueMark(height: size * 0.5, tint: palette.ink(0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(tile)
        // A pale cover on a light surface still needs an edge.
        .overlay(tile.strokeBorder(palette.artworkEdge, lineWidth: 0.5))
        .animation(.easeOut(duration: 0.2), value: image != nil)
    }
}

// MARK: - The mark

/// Cue's wave, beat-reactive, at the size of a wing.
///
/// `WaveIndicator` in its own timeline rather than `NowPlayingIndicator`,
/// which brings a tap that opens the player and a hover that enlarges it —
/// both wrong here, where one click is play/pause and the shelf's own hover is
/// what the pointer is near.
///
/// The level and the bands are read here and nowhere above. They change every
/// sixteen milliseconds while music plays; read in the shelf's body they would
/// re-lay out the whole notch at that rate.
private struct PillWave: View {
    let source: NowPlayingSource
    let isPlaying: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAnimating: Bool { isPlaying && !reduceMotion }

    var body: some View {
        // Capped at 60: this is permanently on screen while anything plays,
        // and a 12pt mark gains nothing from a 120Hz display.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isAnimating)) { context in
            WaveIndicator(
                elapsed: context.date.timeIntervalSinceReferenceDate,
                // Not read at all while the mark is still — paused, or under
                // Reduce Motion — so sixty audio updates a second do not
                // redraw a mark that is not moving.
                level: isAnimating ? source.level() : 0,
                bands: isAnimating ? source.bands() : [],
                isAnimating: isAnimating,
                height: 12,
                tint: tint,
                // Kept inside the housing: at full excursion the centre shape
                // would reach past a 32pt menu bar.
                excursion: 0.6
            )
        }
        // Paused is dimmed rather than hidden, the way the plaque does it: the
        // wings stay, the mark stops being lit.
        .opacity(isPlaying ? 1 : 0.42)
        .animation(.easeOut(duration: 0.25), value: isPlaying)
    }
}

// MARK: - The heart

/// The heart that springs out of the cover on a like.
///
/// Drawn by the shelf outside its own clip, because the whole point is that
/// it leaves the cover. It drifts down, not up: the top of the screen is the
/// bezel, and there is nothing above the menu bar to drift into. Under Reduce
/// Motion it simply fades where it is.
struct LikeHeart: View {
    let reduceMotion: Bool
    let onFinished: () -> Void

    @Environment(\.trayMotion) private var motion

    @State private var scale: CGFloat
    @State private var drop: CGFloat = 0
    @State private var opacity: Double = 1

    init(reduceMotion: Bool, onFinished: @escaping () -> Void) {
        self.reduceMotion = reduceMotion
        self.onFinished = onFinished
        _scale = State(initialValue: reduceMotion ? 1 : 0.4)
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(CuePalette.accent)
            .scaleEffect(scale)
            .offset(y: drop)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear(perform: play)
    }

    private func play() {
        if !reduceMotion {
            withAnimation(motion.heart) { scale = 1.15 }
            withAnimation(.easeOut(duration: 0.7)) { drop = 16 }
        }
        // Eased in, so it holds while it springs and is gone by the time it
        // has drifted — one property, one animation, nothing to fight over.
        withAnimation(.easeIn(duration: 0.7), completionCriteria: .logicallyComplete) {
            opacity = 0
        } completion: {
            onFinished()
        }
    }
}
