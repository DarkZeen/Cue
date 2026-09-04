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

    /// Where the window sits when it is not being looked at.
    ///
    /// Far off-screen rather than ordered out. A `WKWebView` whose window was
    /// never made visible is not reliably given a rendering context, and the
    /// media element inside it may never start — so the window is always
    /// genuinely on screen as far as the window server is concerned, just at
    /// coordinates no display covers.
    private static let hiddenOrigin = NSPoint(x: -30_000, y: -30_000)

    /// Where the window goes when it is shown. Remembered so that hiding and
    /// showing does not reset a window the user has placed and sized.
    private var visibleFrame: NSRect?

    // MARK: - Playing

    /// Plays an item, building the player the first time it is needed.
    func play(_ item: MusicItem) -> Bool {
        guard let url = item.playbackURL else {
            logger.error("No playable URL for a \(item.kind.rawValue, privacy: .public).")
            return false
        }

        // Deliberately does *not* call `show()`. The player is furniture: it
        // plays, and the panel is the interface. The window only appears when
        // it is asked for, or when signing in genuinely needs one.
        let webView = prepareWebView()

        logger.notice("Playing a \(item.kind.rawValue, privacy: .public) in the player.")
        webView.load(URLRequest(url: url))
        isLoaded = true
        return true
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
    /// Driven through the page's own player rather than by clicking a button
    /// whose selector changes every few months: `video.play()` and
    /// `video.pause()` are the media element itself, and YouTube Music's own
    /// interface updates to match because it is watching the same element.
    func togglePlayPause() {
        evaluate("const v=document.querySelector('video'); if(v){v.paused?v.play():v.pause();}")
    }

    /// Mutes or unmutes, on the media element itself.
    func toggleMute() {
        evaluate("const v=document.querySelector('video'); if(v){v.muted=!v.muted;}")
    }

    func next() {
        evaluate("document.querySelector('.next-button, tp-yt-paper-icon-button.next-button')?.click();")
    }

    func previous() {
        evaluate("document.querySelector('.previous-button, tp-yt-paper-icon-button.previous-button')?.click();")
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

        if let visibleFrame {
            window.setFrame(visibleFrame, display: true)
        } else {
            window.setFrameOrigin(Self.hiddenOrigin)
        // Ordered in immediately, off-screen. See `hiddenOrigin`.
        window.orderFrontRegardless()
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
        guard let window else { return }

        // Moved off-screen rather than ordered out, and *not* ordered out
        // afterwards: the web view keeps its rendering context, so the music
        // keeps playing. Ordering the window out is the obvious thing to write
        // here and it is how you get a player that stops when you close it.
        visibleFrame = window.frame
        window.setFrameOrigin(Self.hiddenOrigin)
        isWindowVisible = false
    }

    func toggleWindow() {
        isWindowVisible ? hide() : show()
    }

    private func prepareWindow() -> NSWindow {
        if let window { return window }

        let webView = prepareWebView()

        let window = NSWindow(
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
        window.minSize = NSSize(width: 420, height: 480)
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
        return window
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
          let last = null;

          function report() {
            const media = navigator.mediaSession;
            const video = document.querySelector('video');
            if (!media || !media.metadata) { return; }

            const artwork = media.metadata.artwork || [];
            const state = {
              title: media.metadata.title || '',
              artist: media.metadata.artist || '',
              artwork: artwork.length ? artwork[artwork.length - 1].src : '',
              // `ytcfg` is the page's own configuration blob, and LOGGED_IN is
              // what the site itself checks. Far steadier than looking for a
              // sign-in button whose markup changes with every redesign.
              signedIn: !!(window.ytcfg && ytcfg.get && ytcfg.get('LOGGED_IN')),
              isPlaying: !!video && !video.paused,
              muted: !!video && video.muted
            };

            const signature = JSON.stringify(state);
            if (signature === last) { return; }
            last = signature;
            window.webkit.messageHandlers.cue.postMessage(state);
          }

          // Polled rather than observed: mediaSession has no change event, and
          // a second is far below the rate at which a person notices a
          // now-playing label being stale.
          setInterval(report, 1000);
          document.addEventListener('play', report, true);
          document.addEventListener('pause', report, true);
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
        MainActor.assumeIsolated { self.lastError = nil }
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
