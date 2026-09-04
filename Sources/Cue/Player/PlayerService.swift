import AppKit
import Foundation
import Observation
import WebKit

/// Playback, inside Cue.
///
/// A `WKWebView` running music.youtube.com in a window Cue owns. That is a
/// deliberate choice over the two alternatives:
///
/// * **Handing off to the browser** is what Cue did first. It works, and it is
///   wrong for the app's actual purpose: you press a key, pick a song, and end
///   up looking at a browser window you did not ask for, in an app you were not
///   using, with your place in whatever you *were* doing lost.
/// * **Extracting the audio stream and playing it with `AVPlayer`** would be
///   the "native" answer, and Cue will not do it. It means going around
///   YouTube's player — its terms, its advertising, its accounting for the
///   artists — and it breaks completely every time Google rotates the
///   signature ciphering, which is often. It is not a foundation.
///
/// So the real player runs, signed in as you, and Cue is the thing that decides
/// what it plays. This is the same shape as every YouTube Music desktop wrapper,
/// for the same reasons.
@Observable
final class PlayerService: NSObject {
    /// Whether the player has been built and has something loaded. False until
    /// the first thing is played, so Cue starts with no web view at all.
    private(set) var isLoaded = false
    /// Whether the window is on screen. The window can be closed while
    /// playback continues, so this is not "is playing".
    private(set) var isWindowVisible = false {
        didSet {
            guard isWindowVisible != oldValue else { return }
            onStateChange?()
        }
    }
    private(set) var lastError: String?

    /// What is playing, as the page reports it through the Media Session API.
    /// `nil` when nothing has started yet.
    private(set) var nowPlaying: NowPlaying? {
        didSet {
            guard nowPlaying != oldValue else { return }
            onStateChange?()
        }
    }

    private var window: NSWindow?
    private var webView: WKWebView?

    private let logger = Diagnostics.logger("player")

    /// Raised whenever what is playing, or whether the window is up, changes.
    ///
    /// A callback rather than the mini player observing this object directly:
    /// showing and hiding a window is not something to do from inside a
    /// SwiftUI dependency read, and there are four conditions to weigh which
    /// belong in one place.
    var onStateChange: (() -> Void)?

    /// The message handler's name on the JavaScript side.
    private static let bridgeName = "cue"

    /// Where Home goes, and where the player starts.
    static let home = URL(string: "https://music.youtube.com/")!

    /// Whether the page is signed in, as the page itself reports it.
    ///
    /// `nil` until something has loaded and said either way. Playing signed
    /// out works, but it is not what someone with a Premium subscription is
    /// paying for, so it is worth being able to say so.
    private(set) var isSignedIn: Bool?

    struct NowPlaying: Equatable, Sendable {
        var title: String
        var artist: String?
        var artworkURL: URL?
        var isPlaying: Bool
        var isMuted: Bool = false
    }

    /// How much of the concealed window is left on screen.
    ///
    /// The previous attempt kept the whole window on screen at 1.2% opacity and
    /// did not work: macOS does not count a window that faint as visible, so
    /// WebKit went on treating the page as hidden and the autoplay policy went
    /// on refusing to start it. The symptom was exact — showing the window once
    /// and hiding it again made everything work from then on.
    ///
    /// So the window is fully opaque and almost entirely off screen instead,
    /// with a few pixels left in the corner. A partly-visible window is
    /// unambiguously visible, and three pixels in the top-left corner is not
    /// something anyone will find.
    private static let visibleSliver: CGFloat = 1

    /// How opaque the window is while it is "hidden".
    ///
    /// Not zero, and not off-screen, and this is the whole trick. A window
    /// parked at coordinates no display covers — or at `alphaValue` 0 — is
    /// reported as not visible; WebKit then marks the page hidden, and the
    /// autoplay policy refuses to start a hidden page. The symptom is precise
    /// and baffling: skipping tracks works, but nothing ever *starts* until you
    /// open the window.
    ///
    /// So the window stays on screen, above everything so nothing can occlude
    /// it, click-through so it cannot be interacted with, and at an opacity
    /// that is technically non-zero and practically invisible.
    /// Fully opaque, deliberately. Only the sliver is on screen, and opacity
    /// is what macOS was judging visibility by.
    private static let hiddenAlpha: CGFloat = 1

    /// How big it is while concealed.
    ///
    /// Only `visibleSliver` of it is ever on screen, so this is not about how
    /// much can be seen — it is about how much room YouTube Music has to lay
    /// itself out in. There is a floor: below about 320 points the page drops
    /// its player bar, and the controls Cue drives go with it. This is as small
    /// as it goes while still building a player.
    private static let hiddenSize = NSSize(width: 360, height: 280)

    /// The size the window opens at the first time it is actually shown.
    private static let shownSize = NSSize(width: 1_020, height: 700)

    /// Set while a freshly-loaded page is expected to start playing.
    ///
    /// Cleared once it does, or after a few seconds of trying. Without the
    /// window, this is scoped deliberately tightly: a nudge that ran after
    /// *any* navigation would restart the music every time the user paused it
    /// and clicked something.
    private var wantsPlayback = false
    /// Set when what was opened is an album, which has to be started by hand.
    private var wantsAlbumShuffle = false
    private var playbackNudge: Task<Void, Never>?

    /// Where the window goes when it is shown. Remembered so that hiding and
    /// showing does not reset a window the user has placed and sized.
    private var visibleFrame: NSRect?

    // MARK: - Playing

    /// Plays an item, building the player the first time it is needed.
    func play(_ item: MusicItem, shuffled: Bool = false) -> Bool {
        guard let url = item.playbackURL else {
            logger.error("No playable URL for a \(item.kind.rawValue, privacy: .public).")
            return false
        }

        // Deliberately does *not* call `show()`. The player is furniture: it
        // plays, and the panel is the interface. The window only appears when
        // it is asked for, or when signing in genuinely needs one.
        let webView = prepareWebView()

        logger.notice("Playing a \(item.kind.rawValue, privacy: .public) in the player.")
        wantsPlayback = true
        wantsAlbumShuffle = shuffled
        webView.load(URLRequest(url: url))
        isLoaded = true
        return true
    }

    /// Makes sure the page actually started.
    ///
    /// The autoplay policy will not start a page WebKit considers hidden, and
    /// Cue's player is as close to hidden as a window gets. Pressing the site's
    /// own play button is a direct instruction rather than autoplay, so it is
    /// not subject to the policy — but the button does not exist until the
    /// player has built itself, which is why this is several attempts spread
    /// over a few seconds rather than one.
    private func nudgeIntoPlaying() {
        playbackNudge?.cancel()
        playbackNudge = Task { [weak self] in
            // Spread over twelve seconds rather than three. `didFinish` means
            // the document loaded, not that YouTube Music has built its player,
            // and on a cold start the gap between the two is seconds.
            let schedule: [Duration] = [
                .milliseconds(800), .milliseconds(1_200), .seconds(2),
                .seconds(2), .seconds(3), .seconds(3),
            ]
            for delay in schedule {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.wantsPlayback else { return }

                if self.nowPlaying?.isPlaying == true {
                    self.wantsPlayback = false

                    // Shuffled only once it is actually playing: the control
                    // does not exist until the player bar does, and toggling it
                    // before then does nothing and reports success.
                    if self.wantsAlbumShuffle {
                        self.wantsAlbumShuffle = false
                        self.evaluate("__cue.setShuffle(true)")
                    }
                    return
                }

                self.evaluate("__cue.ensurePlaying()")
            }
            self?.wantsPlayback = false
            self?.wantsAlbumShuffle = false
        }
    }

    /// Opens the player on its own, with nothing queued — the front page, so
    /// there is something to browse rather than an empty window.
    func showHome() {
        let webView = prepareWebView()
        show()
        if !isLoaded {
            webView.load(URLRequest(url: Self.home))
            isLoaded = true
        }
    }

    /// Brings the window up on whatever is currently playing.
    ///
    /// What the disc in the panel does when it is clicked: the page is already
    /// showing the track, so this is purely a matter of putting the window
    /// where it can be seen.
    func showCurrent() {
        _ = prepareWebView()
        if !isLoaded {
            showHome()
        } else {
            show()
        }
    }

    /// Back to YouTube Music, from wherever the page wandered to.
    ///
    /// It wanders more than you would expect: a video that is not in YouTube
    /// Music's catalogue — which is most of what the official Data API can
    /// find — redirects to youtube.com, and from there the player is a general
    /// YouTube browser with no way home. This is that way.
    @objc func goHome() {
        prepareWebView().load(URLRequest(url: Self.home))
        isLoaded = true
    }

    @objc func goBack() {
        webView?.goBack()
    }

    @objc func goForward() {
        webView?.goForward()
    }

    // MARK: - Transport

    /// Play or pause, without bringing the window forward.
    ///
    /// Driven through YouTube Music's own controls rather than the media
    /// element, because the media element is not reliably reachable from
    /// `document`: skip and previous worked while play/pause and mute did
    /// nothing, and the only thing separating them was that the working two
    /// clicked buttons. `__cue` falls back to the element — found by walking
    /// shadow roots — when a selector stops matching, which is the failure
    /// mode to expect from an interface nobody promised would stay the same.
    func togglePlayPause() {
        evaluate("__cue.toggle()")
    }

    func next() {
        evaluate("__cue.next()")
    }

    func previous() {
        evaluate("__cue.previous()")
    }

    func toggleMute() {
        evaluate("__cue.mute()")
    }

    /// Nudges the volume, for scrolling over the plaque's speaker.
    func adjustVolume(by delta: Double) {
        evaluate("__cue.nudgeVolume(\(delta))")
    }

    private func evaluate(_ script: String) {
        guard let webView else { return }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.debug("Player script failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Window

    func show() {
        let window = prepareWindow()

        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        if let visibleFrame {
            window.setFrame(visibleFrame, display: true)
        } else {
            window.setContentSize(Self.shownSize)
            window.center()
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        isWindowVisible = true

        logger.notice("Player window shown.")
    }

    /// Hides the window without stopping the music.
    ///
    /// The distinction the whole design turns on: closing the player is
    /// "get this off my screen", never "stop playing". An app that stopped the
    /// music when its window closed would be unusable as a music player.
    func hide() {
        guard let window, isWindowVisible else { return }
        visibleFrame = window.frame
        conceal(window)
        isWindowVisible = false
    }

    /// The screen to hide against.
    ///
    /// `NSScreen.main` is the screen holding the window with keyboard focus,
    /// and it is `nil` when nothing has focus — which for an agent app at
    /// launch is every single time. Reading it through an `if let` and simply
    /// not positioning the window when it fails is how the player ends up
    /// sitting in the bottom-left corner of the screen, fully visible, doing
    /// an excellent impression of a bug in the hiding code.
    private var concealmentScreen: NSScreen? {
        window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Puts the window into its invisible state: on screen, on top, small,
    /// click-through and all but transparent. See `hiddenAlpha` for why every
    /// one of those is load-bearing.
    private func conceal(_ window: NSWindow) {
        window.alphaValue = Self.hiddenAlpha
        window.ignoresMouseEvents = true
        // Above other windows so nothing can cover it: an occluded window is a
        // hidden page, which is the thing being worked around.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setContentSize(Self.hiddenSize)

        // Pushed down and left until only its top-right corner pokes into the
        // bottom-left of the usable screen — `visibleSliver` square.
        //
        // `visibleFrame` rather than `frame`, so the sliver lands in the area
        // the Dock does not cover. The rest of the window hangs below and to
        // the left of the screen, which costs nothing: occlusion is judged on
        // the part that is on screen, and this window sits above ordinary ones
        // so nothing can cover that part.
        // Sized first, then positioned from the frame that resulted: the
        // window's frame is its content plus a title bar and a toolbar, and
        // positioning from the content size alone leaves it tens of points off.
        let size = window.frame.size
        let visible = (concealmentScreen ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)

        window.setFrameOrigin(NSPoint(
            x: visible.minX + Self.visibleSliver - size.width,
            y: visible.minY + Self.visibleSliver - size.height
        ))

        window.orderFrontRegardless()

        // Worth knowing for certain rather than inferring from whether the
        // music started: if this says the window is not visible, the autoplay
        // policy will refuse to start it and no amount of nudging will help.
        logger.notice(
            "Player concealed at \(window.frame.debugDescription, privacy: .public); visible to the window server: \(window.occlusionState.contains(.visible), privacy: .public)"
        )
    }

    func toggleWindow() {
        isWindowVisible ? hide() : show()
    }

    private func prepareWindow() -> NSWindow {
        if let window { return window }

        let webView = prepareWebView()

        let window = PlayerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 700),
            // Deliberately *without* `.fullSizeContentView`. With it, the page
            // runs under the title bar and Cue's own back/forward/home buttons
            // land on top of YouTube Music's search field and wordmark — two
            // sets of chrome fighting over the same forty points. The toolbar
            // gets its own strip instead.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cue"
        // No title text: the page below says what it is far better than the
        // word "Cue" would, and the toolbar already fills the strip.
        window.titleVisibility = .hidden
        // The strip is painted by the window rather than the page now, so it
        // has to match what the page paints — anything lighter reads as a grey
        // bar stuck above a black app.
        window.backgroundColor = NSColor(calibratedWhite: 0.03, alpha: 1)
        window.contentView = webView
        // Without this the window is a web browser with no controls at all:
        // one redirect and there is no way back, which is exactly what
        // happened the first time this was tried.
        window.toolbar = makeToolbar()
        window.toolbarStyle = .unified
        window.center()
        window.isReleasedWhenClosed = false
        // No larger than the concealed size, or `setContentSize` is clamped and
        // the window is bigger than intended while hiding.
        window.minSize = Self.hiddenSize
        window.delegate = self

        // Without this the player opens on the desktop Space while you are in a
        // full-screen app — created, ordered front, and completely invisible,
        // because "front" meant front of a Space you are not looking at. Cue is
        // summoned from wherever you happen to be, so its player has to arrive
        // there rather than somewhere else.
        //
        // `.moveToActiveSpace` rather than `.canJoinAllSpaces`: this is an
        // ordinary window that should follow you, not a panel that should be
        // on every Space at once.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        self.window = window

        // Born concealed, so the web view has a real, on-screen window from the
        // moment it exists and the first thing played starts on its own rather
        // than waiting for someone to open a window.
        conceal(window)
        primeVisibility()

        return window
    }

    /// Gives the window one moment of genuine visibility, if it needs it.
    ///
    /// Measured rather than assumed, because the behaviour is peculiar and cost
    /// several wrong guesses. A window that has *only ever* existed as a
    /// one-pixel sliver is reported by the window server as not visible — so
    /// WebKit treats the page as hidden and the autoplay policy refuses to
    /// start it. Once the window has been genuinely on screen even briefly, the
    /// same one-pixel sliver is reported as visible from then on, and playback
    /// starts on its own for the rest of the session.
    ///
    ///     Player concealed; visible to the window server: false   ← at creation
    ///     Player concealed; visible to the window server: true    ← after one show
    ///
    /// So: check, and only if the window server disagrees, put the window on
    /// screen for a quarter of a second. Cue creates its player at launch, so
    /// this happens once, before anyone has asked for music — not in the middle
    /// of playing something.
    private func primeVisibility() {
        Task { [weak self] in
            // Long enough for the window server to have formed an opinion; an
            // occlusion state read in the same turn as the order-front is not
            // yet meaningful.
            try? await Task.sleep(for: .milliseconds(400))

            guard let self, let window = self.window, !self.isWindowVisible else { return }
            guard !window.occlusionState.contains(.visible) else {
                self.logger.notice("Player already visible to the window server; no priming needed.")
                return
            }

            let visible = (self.concealmentScreen ?? NSScreen.screens.first)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
            window.setFrameOrigin(NSPoint(x: visible.minX, y: visible.minY))
            window.orderFrontRegardless()

            try? await Task.sleep(for: .milliseconds(250))

            guard !self.isWindowVisible, let window = self.window else { return }
            self.conceal(window)
            self.logger.notice(
                "Primed; visible to the window server: \(window.occlusionState.contains(.visible), privacy: .public)"
            )
        }
    }

    /// Builds the player and loads YouTube Music without playing anything.
    ///
    /// Called at launch so the priming above, and the several seconds
    /// YouTube Music takes to build itself, are spent before the first time
    /// someone actually asks for a song rather than during it.
    func warmUp() {
        let webView = prepareWebView()
        _ = prepareWindow()
        guard !isLoaded else { return }
        webView.load(URLRequest(url: Self.home))
        isLoaded = true
        logger.notice("Player warmed up.")
    }

    // MARK: - Toolbar

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "CuePlayer")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    /// `nonisolated` because `NSToolbarDelegate`'s methods are, and these are
    /// constants that never needed an actor in the first place.
    nonisolated enum ToolbarItem {
        static let back = NSToolbarItem.Identifier("cue.back")
        static let forward = NSToolbarItem.Identifier("cue.forward")
        static let home = NSToolbarItem.Identifier("cue.home")
    }

    // MARK: - Web view

    private func prepareWebView() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        // Persistent, unlike the sign-in web view in `YTMusicSessionService`:
        // this one *is* the session, and being signed out every launch would
        // make it useless. It is the same store Safari-style browsing uses for
        // this app alone.
        configuration.websiteDataStore = .default()
        // Without this, navigating to a watch URL loads the page and waits for
        // a click that the whole point of Cue is to avoid.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true

        let controller = WKUserContentController()
        controller.add(self, name: Self.bridgeName)
        controller.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        // Google refuses to sign in on anything it reads as an embedded web
        // view, and the default WebKit agent is one.
        webView.customUserAgent = YTMusicSessionService.userAgent
        webView.allowsBackForwardNavigationGestures = true
        // Matches YouTube Music's own dark page, so there is no white flash
        // between navigations. `underPageBackgroundColor` is the supported way
        // to do this; the `drawsBackground` KVC trick that circulates for it is
        // private API and can stop working in any release.
        webView.underPageBackgroundColor = .black

        self.webView = webView
        return webView
    }

    // The player deliberately does *not* seed itself from the cookies captured
    // in Settings, and this is worth writing down because doing so is the
    // obvious idea and it is wrong.
    //
    // Those cookies are a flattened `name=value` snapshot taken once. Google
    // sets several of the same names on `.google.com` and `.youtube.com` with
    // *different* values, so flattening them picks one arbitrarily and the
    // other domain gets a value that was never its own. Worse, `__Secure-3PSIDTS`
    // rotates continuously — writing a stale copy of it over a live session is
    // how you get an account that signs in, plays one track, and signs out.
    //
    // So the player owns its own persistent WebKit session and signs in once,
    // exactly as a browser would, and WebKit handles rotation. The captured
    // cookie is for the API provider and stays there.

    /// Reports what is playing back to Cue.
    ///
    /// Reads `navigator.mediaSession`, which is a web standard YouTube Music
    /// fills in for the system's own now-playing UI — so it is both accurate
    /// and far more durable than scraping the player bar's CSS classes.
    private static let bridgeScript = """
        (function () {
          // YouTube Music is built from custom elements, and what is in the
          // light DOM moves between releases. Walking shadow roots costs a few
          // milliseconds on a call nobody makes in a loop, and it keeps working
          // when a control gets re-parented into a component.
          function deep(selector, root) {
            root = root || document;
            const direct = root.querySelector(selector);
            if (direct) { return direct; }
            const hosts = root.querySelectorAll('*');
            for (let i = 0; i < hosts.length; i++) {
              if (hosts[i].shadowRoot) {
                const found = deep(selector, hosts[i].shadowRoot);
                if (found) { return found; }
              }
            }
            return null;
          }

          const cue = {
            _media: null,

            // The cheap lookup, for the once-a-second poll. A plain
            // `querySelector` costs nothing; the deep walk below costs a
            // traversal of every element and shadow root on the page, and
            // doing that every second is enough to stall it.
            media() {
              if (this._media && this._media.isConnected) { return this._media; }
              this._media = document.querySelector('video') || document.querySelector('audio');
              return this._media;
            },

            // The thorough lookup, only ever run when a button is pressed.
            deepMedia() {
              const cheap = this.media();
              if (cheap) { return cheap; }
              this._media = deep('video') || deep('audio');
              return this._media;
            },

            press(selectors) {
              for (const selector of selectors) {
                const element = deep(selector);
                if (element) { element.click(); return true; }
              }
              return false;
            },

            // Finds a control by what it says rather than by where it lives.
            // An album page's Shuffle button has moved between markup shapes
            // several times; the word on it has not.
            pressLabelled(pattern) {
              const candidates = document.querySelectorAll(
                'button, a, tp-yt-paper-button, yt-button-shape, ytmusic-play-button-renderer'
              );
              for (const node of candidates) {
                const label = (node.getAttribute('aria-label') || node.textContent || '').trim();
                if (label && pattern.test(label)) { node.click(); return true; }
              }
              return false;
            },

            // Turns shuffle on, and only on.
            //
            // A plain click toggles, so a queue that was already shuffled would
            // be un-shuffled by asking for shuffle — which is the kind of bug
            // that looks like the feature working half the time.
            setShuffle(on) {
              const button = deep('tp-yt-paper-icon-button.shuffle')
                || deep('ytmusic-player-bar tp-yt-paper-icon-button[aria-label*="huffle"]')
                || deep('[aria-label*="huffle"]');
              if (!button) { return false; }

              const pressed = button.getAttribute('aria-pressed') === 'true'
                || button.classList.contains('style-primary-text');
              if (pressed === on) { return true; }

              button.click();
              // Shuffling reorders what comes *after* the current track, so
              // without this the album still starts on track one and only then
              // becomes random.
              if (on) { setTimeout(() => this.next(), 400); }
              return true;
            },

            toggle() {
              // The site's own button first: it knows about the queue, ads and
              // whatever else is between a click and the sound changing.
              if (this.press(['#play-pause-button', '.play-pause-button'])) { return; }
              const media = this.deepMedia();
              if (media) { media.paused ? media.play() : media.pause(); }
            },

            next() {
              if (this.press(['.next-button', 'tp-yt-paper-icon-button.next-button'])) { return; }
              const media = this.deepMedia();
              if (media) { media.currentTime = media.duration || 0; }
            },

            previous() {
              this.press(['.previous-button', 'tp-yt-paper-icon-button.previous-button']);
            },

            mute() {
              const media = this.deepMedia();
              if (media) { media.muted = !media.muted; return; }
              this.press(['tp-yt-paper-icon-button.volume', '#volume-slider']);
            },

            // Starts playback if it has not started on its own.
            //
            // The autoplay policy will not start a page it considers hidden,
            // and Cue's player is deliberately as close to hidden as a window
            // can be. Pressing the site's own play button is a direct
            // instruction rather than autoplay, so it is not subject to it.
            ensurePlaying() {
              const session = navigator.mediaSession;
              if (session && session.playbackState === 'playing') { return true; }
              const media = this.deepMedia();
              if (media && !media.paused) { return true; }
              this.toggle();
              return false;
            },

            nudgeVolume(delta) {
              const media = this.deepMedia();
              if (!media) { return; }
              media.muted = false;
              media.volume = Math.min(1, Math.max(0, media.volume + delta));
            },

            state() {
              const session = navigator.mediaSession;
              if (!session || !session.metadata) { return null; }
              const media = this.media();
              const artwork = session.metadata.artwork || [];
              // `playbackState` is the site's own answer and does not depend on
              // having found the media element. The element is only consulted
              // when the site has not said.
              const playing = session.playbackState
                ? session.playbackState === 'playing'
                : !!media && !media.paused;
              return {
                title: session.metadata.title || '',
                artist: session.metadata.artist || '',
                artwork: artwork.length ? artwork[artwork.length - 1].src : '',
                // `ytcfg` is the page's own configuration blob, and LOGGED_IN
                // is what the site itself checks. Far steadier than looking for
                // a sign-in button whose markup changes with every redesign.
                signedIn: !!(window.ytcfg && ytcfg.get && ytcfg.get('LOGGED_IN')),
                isPlaying: playing,
                muted: !!media && media.muted
              };
            }
          };

          window.__cue = cue;

          let last = null;
          function report() {
            // Wrapped, because this runs on a timer against a page that is
            // rewritten without warning: one thrown exception must not be the
            // end of every future report, and with it the only sign on screen
            // that Cue is playing anything.
            try {
              const state = cue.state();
              if (!state) { return; }
              const signature = JSON.stringify(state);
              if (signature === last) { return; }
              last = signature;
              window.webkit.messageHandlers.cue.postMessage(state);
            } catch (error) {
              /* ignored on purpose */
            }
          }

          // Polled rather than observed: mediaSession has no change event, and
          // a second is far below the rate at which a person notices a
          // now-playing label being stale.
          setInterval(report, 1000);
          document.addEventListener('play', report, true);
          document.addEventListener('pause', report, true);
          document.addEventListener('volumechange', report, true);
        })();
        """
}

// MARK: - Toolbar

extension PlayerService: NSToolbarDelegate {
    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItem.back, ToolbarItem.forward, .flexibleSpace, ToolbarItem.home]
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    nonisolated func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self

            switch identifier {
            case ToolbarItem.back:
                item.label = "Back"
                item.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back")
                item.action = #selector(PlayerService.goBack)
            case ToolbarItem.forward:
                item.label = "Forward"
                item.image = NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: "Forward")
                item.action = #selector(PlayerService.goForward)
            case ToolbarItem.home:
                item.label = "YouTube Music"
                item.image = NSImage(systemSymbolName: "house", accessibilityDescription: "YouTube Music")
                item.action = #selector(PlayerService.goHome)
            default:
                return nil
            }

            return item
        }
    }
}

// MARK: - Bridge

extension PlayerService: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // `WKScriptMessage` is delivered on the main thread, and its `body` is
        // main-actor isolated, so the hop comes first and the unpacking happens
        // inside it.
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any] else { return }

            let title = body["title"] as? String ?? ""
            guard !title.isEmpty else { return }

            let artist = body["artist"] as? String
            let artwork = body["artwork"] as? String

            self.isSignedIn = body["signedIn"] as? Bool

            self.nowPlaying = NowPlaying(
                title: title,
                artist: (artist?.isEmpty == false) ? artist : nil,
                artworkURL: (artwork?.isEmpty == false) ? artwork.flatMap(URL.init(string:)) : nil,
                isPlaying: body["isPlaying"] as? Bool ?? false,
                isMuted: body["muted"] as? Bool ?? false
            )
        }
    }
}

// MARK: - Navigation

extension PlayerService: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        MainActor.assumeIsolated {
            // Cancellations are the page's own redirect chain, not a failure
            // worth putting in front of anyone.
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            self.lastError = error.localizedDescription
            self.logger.error("Player navigation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        MainActor.assumeIsolated {
            self.lastError = nil
            if self.wantsPlayback { self.nudgeIntoPlaying() }
        }
    }
}

// MARK: - Window

extension PlayerService: NSWindowDelegate {
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            // Hidden, not closed. Closing would destroy the web view and with
            // it the music, which is not what the red button means on a player.
            self.hide()
        }
        return false
    }
}

/// The player's own window.
///
/// It exists for one reason: AppKit will not leave a titled window where you
/// put it. `constrainFrameRect(_:to_:)` quietly drags any window whose title bar
/// would leave the screen back into view, so setting an origin that hides the
/// window off the corner is silently undone — the frame comes back as
/// `(0, 0, 360, 332)`, sitting in the bottom-left corner in full view, looking
/// exactly like a bug in the hiding code rather than in the placing code.
///
/// Overriding it to return the rectangle unchanged is the supported way to say
/// that this window means it.
final class PlayerWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
