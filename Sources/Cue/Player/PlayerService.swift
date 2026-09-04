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
    private(set) var isWindowVisible = false
    private(set) var lastError: String?

    /// What is playing, as the page reports it through the Media Session API.
    /// `nil` when nothing has started yet.
    private(set) var nowPlaying: NowPlaying?

    private var window: NSWindow?
    private var webView: WKWebView?

    private let session: YTMusicSessionService
    private let logger = Diagnostics.logger("player")

    /// The message handler's name on the JavaScript side.
    private static let bridgeName = "cue"

    /// Where Home goes, and where the player starts.
    static let home = URL(string: "https://music.youtube.com/")!

    struct NowPlaying: Equatable, Sendable {
        var title: String
        var artist: String?
        var isPlaying: Bool
    }

    init(session: YTMusicSessionService) {
        self.session = session
        super.init()
    }

    // MARK: - Playing

    /// Plays an item, building the player the first time it is needed.
    func play(_ item: MusicItem) -> Bool {
        guard let url = item.playbackURL else {
            logger.error("No playable URL for a \(item.kind.rawValue, privacy: .public).")
            return false
        }

        let webView = prepareWebView()
        show()

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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        isWindowVisible = true

        logger.notice(
            "Player shown at \(window.frame.debugDescription, privacy: .public) on \(window.screen?.localizedName ?? "no screen", privacy: .public)."
        )
    }

    /// Hides the window without stopping the music.
    ///
    /// The distinction the whole design turns on: closing the player is
    /// "get this off my screen", never "stop playing". An app that stopped the
    /// music when its window closed would be unusable as a music player.
    func hide() {
        window?.orderOut(nil)
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
        window.setFrameAutosaveName("CuePlayer")
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

        adoptCapturedSession(into: webView)

        return webView
    }

    /// Copies the cookies captured in Settings into the player.
    ///
    /// A convenience, not a requirement: someone who connected the YouTube
    /// Music library in Settings should not then have to sign in a second time
    /// in the player. If they never did, the player is simply a signed-out
    /// music.youtube.com and they can sign in inside it.
    private func adoptCapturedSession(into webView: WKWebView) {
        guard let header = session.cookieHeader else { return }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        let jar = YTMusicSessionService.parse(cookieHeader: header)

        for (name, value) in jar {
            guard let cookie = HTTPCookie(properties: [
                .name: name,
                .value: value,
                // The domain the cookies were captured from. Google sets the
                // same names on `.google.com` too, but the player only ever
                // talks to YouTube.
                .domain: ".youtube.com",
                .path: "/",
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 365),
            ]) else { continue }

            store.setCookie(cookie)
        }

        logger.notice("Seeded the player with \(jar.count, privacy: .public) captured cookies.")
    }

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

            const state = {
              title: media.metadata.title || '',
              artist: media.metadata.artist || '',
              isPlaying: !!video && !video.paused
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

            self.nowPlaying = NowPlaying(
                title: title,
                artist: (artist?.isEmpty == false) ? artist : nil,
                isPlaying: body["isPlaying"] as? Bool ?? false
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
