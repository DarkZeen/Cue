import AppKit
import SwiftUI

/// The settings window — Cue's, and since Tray moved in, the shelf's too.
///
/// A sidebar and a detail pane, the shape macOS itself uses for settings, so
/// nobody has to learn where anything is (§33, §55). Cue's three pages come
/// first, then the shelf's, then the two pages that are about the whole app.
/// Accounts still matters most: without an OAuth client Cue cannot do anything
/// at all, so it is where a first run ends up, and it is written as
/// instructions rather than as a form.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let shelfSettings: ShelfSettingsStore
    let coordinator: LibraryCoordinator
    @Bindable var launchAtLogin: LaunchAtLoginService
    let hotKey: HotKeyService
    let player: PlayerService
    let onEditLayout: () -> Void
    let updates: UpdateService
    let onShowPlayer: () -> Void
    /// Through the shelf, which records the wish as well as making the
    /// registration — see `ShelfState.setLaunchAtLogin`.
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onMenuBarIconChanged: (Bool) -> Void

    @State private var selection: Pane? = Pane(rawValue: Diagnostics.debugSettingsPane ?? "") ?? .general

    /// Not named `Tab` or `Page`: SwiftUI has both.
    enum Pane: String, CaseIterable, Identifiable {
        case general
        case accounts
        case tiles
        case notch
        case shelf
        case privacy
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .accounts: "Accounts"
            case .tiles: "Grid"
            case .notch: "Notch"
            case .shelf: "Shelf"
            case .privacy: "Privacy"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .accounts: "person.crop.circle"
            case .tiles: "square.grid.3x3"
            case .notch: "waveform"
            case .shelf: "tray"
            case .privacy: "hand.raised"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // The explicit ForEach form, not `List(data, selection:)` — the
            // latter selects by element id, which does not match a binding of
            // the element type itself.
            List(selection: $selection) {
                ForEach(Pane.allCases) { pane in
                    Label(pane.title, systemImage: pane.icon)
                        .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(SettingsMetrics.sidebarWidth)
        } detail: {
            detail
                .frame(minWidth: SettingsMetrics.detailWidth)
                .navigationTitle(selection?.title ?? "Settings")
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralPane(
                settings: settings,
                shelfSettings: shelfSettings,
                launchAtLogin: launchAtLogin,
                hotKey: hotKey,
                player: player,
                onEditLayout: onEditLayout,
                updates: updates,
                onLaunchAtLoginChanged: onLaunchAtLoginChanged,
                onMenuBarIconChanged: onMenuBarIconChanged
            )
        case .accounts:
            AccountsPane(
                settings: settings,
                coordinator: coordinator,
                onShowPlayer: onShowPlayer
            )
        case .tiles:
            TilesPane(settings: settings, coordinator: coordinator)
        case .notch:
            NotchPane(settings: settings)
        case .shelf:
            TrayPane(settings: shelfSettings)
        case .privacy:
            PrivacyPane()
        case .about:
            AboutPane()
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    let shelfSettings: ShelfSettingsStore
    let launchAtLogin: LaunchAtLoginService
    let hotKey: HotKeyService
    let player: PlayerService
    let onEditLayout: () -> Void
    let updates: UpdateService
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onMenuBarIconChanged: (Bool) -> Void

    @State private var didCopyCommand = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { onLaunchAtLoginChanged($0) }
                ))
                // Registration fails for specific reasons, each with something
                // to do about it. Saying which beats a toggle that quietly
                // disagrees with the system (§34).
                if let explanation = launchAtLogin.state.explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Toggle("Show in the menu bar", isOn: Binding(
                    get: { shelfSettings.showsMenuBarIcon },
                    set: { onMenuBarIconChanged($0) }
                ))
                Text("""
                    With it hidden, the shortcut, the shelf and the notch all \
                    work the same; opening Cue from Applications brings this \
                    window back.
                    """)
                    .hint(settings.showsHints)

                Toggle("Explain each setting", isOn: $settings.showsHints)
            }

            Section("Playback") {
                Picker("When you pick something", selection: $settings.playbackDestination) {
                    ForEach(PlaybackDestination.allCases, id: \.self) { destination in
                        Text(destination.title).tag(destination)
                    }
                }

                if settings.playbackDestination == .inApp {
                    Toggle("Shuffle playlists and albums", isOn: $settings.shufflesContainers)

                    Toggle("Pause when another app plays sound", isOn: $settings.pausesForOtherAudio)

                    Text("""
                        A video, a call, a game: Cue pauses while it plays and \
                        carries on once it has been quiet for two seconds. A \
                        pause you make yourself stays a pause. Notification \
                        sounds do not count, and pressing play in Cue while \
                        something else is playing keeps Cue playing.
                        """)
                        .hint(settings.showsHints)

                    Toggle("Make the mark move with the music", isOn: $settings.analysesAudio)

                    Text("""
                        Reads what Cue is playing through macOS's own audio \
                        tap, so the mark follows the actual sound instead of a \
                        rhythm of its own. macOS will ask permission the first \
                        time. Only Cue's own audio is read — not the system's, \
                        not another app's — and nothing is recorded or sent \
                        anywhere. Off means the mark invents its motion, which \
                        is what it has always done.
                        """)
                        .hint(settings.showsHints)

                    if settings.analysesAudio, player.audioTap.isReading {
                        Label("Listening.", systemImage: "waveform")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else if settings.analysesAudio {
                        Label(
                            "Nothing to listen to yet — this starts when music does.",
                            systemImage: "waveform.slash"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }

                    Text("""
                        Cue plays it in its own window, signed in as you. Closing \
                        that window hides it — the music keeps going — and \
                        `\(CueURL.scheme)://player` brings it back.
                        """)
                        .hint(settings.showsHints)

                    HStack {
                        Button(player.isWindowVisible ? "Hide Player" : "Show Player") {
                            player.isWindowVisible ? player.hide() : player.showHome()
                        }

                        if let nowPlaying = player.nowPlaying {
                            Text(nowPlaying.artist.map { "\(nowPlaying.title) — \($0)" } ?? nowPlaying.title)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Section("Panel") {
                LabeledContent("Size and position") {
                    HStack(spacing: 10) {
                        Button("Edit Layout…", action: onEditLayout)

                        Button("Reset") { settings.resetPanelLayout() }
                            .buttonStyle(.borderless)
                    }
                }

                // Direct manipulation instead of a slider and a picker: size
                // and position are spatial, and the honest control for a
                // spatial property is the thing itself.
                Text("""
                    Puts the panel and the plaque on screen with alignment \
                    guides: drag either to move it, drag the panel's edge to \
                    resize, hold ⇧ to move in steps. The covers scale with the \
                    panel. Position is kept as a proportion of the screen, so \
                    it means the same thing on any display.
                    """)
                    .hint(settings.showsHints)

                Picker("Grid", selection: $settings.panelDesign) {
                    ForEach(PanelDesign.allCases, id: \.self) { design in
                        Text(design.title).tag(design)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.panelDesign.summary)
                    .hint(settings.showsHints)

                if settings.panelDesign == .gallery {
                    Text("⌘1 to ⌘9 open a tile on the page you are looking at. ⌘R deals a different nine. ⌘E swaps between your own music and Explore.")
                        .hint(settings.showsHints)
                }
            }

            Section {
                Toggle("Close the panel after opening something", isOn: $settings.closesAfterOpening)
                Toggle("Fill empty tiles with recent and library items", isOn: $settings.autoFillsEmptyTiles)
            } footer: {
                Text("Applies to the speed dial. Right-click a tile to keep it where it is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard shortcut") {
                LabeledContent("Open Cue") {
                    ShortcutRecorder(combination: $settings.hotKey)
                }

                // Worth saying out loud, because every other app that puts a
                // shortcut recorder in front of someone follows it with a
                // permission prompt. This one does not: a registered hotkey is
                // told when its own combination is pressed and never sees any
                // other keystroke, which is why it needs nothing granted.
                Text("""
                    Works over any app, including full-screen ones, and needs \
                    no Accessibility or Input Monitoring permission — a \
                    registered shortcut is never shown any keystroke but its \
                    own.
                    """)
                    .hint(settings.showsHints)

                if let error = hotKey.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if settings.hotKey != nil, !hotKey.isRegistered {
                    Text("The shortcut is not registered.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("""
                    If pressing it does nothing, another app already owns that \
                    combination — macOS gives it to whoever asked first, and \
                    says nothing about it. Pick a different one.
                    """)
                    .hint(settings.showsHints)
            }

            Section("From a script") {
                Text("""
                    Cue also answers a URL, for Shortcuts.app, a launcher you \
                    already use, or anything else that can run a command.
                    """)
                    .hint(settings.showsHints)

                HStack {
                    // Taken from the bundle, so a development build shows the
                    // command that actually reaches *it* rather than the one
                    // that reaches an installed release.
                    Text(CueURL.command("open"))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))

                    Spacer()

                    Button(didCopyCommand ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CueURL.command("open"), forType: .string)
                        didCopyCommand = true
                    }
                    .disabled(didCopyCommand)
                }

                Text("\(CueURL.scheme)://toggle closes the panel again if it is already open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                UpdatesRow(updates: updates, settings: settings)
            }

            Section {
                HStack {
                    Button("Quit Cue") {
                        NSApp.terminate(nil)
                    }

                    Spacer()

                    Text("⌘Q also works while Cue is in front.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                // Worth saying: an app with no Dock icon and no menu bar item
                // is an app most people cannot work out how to quit, and
                // reaching for Activity Monitor is not an answer.
                Text("Cue has no Dock icon, so this is the way out. Quitting stops the music.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Accounts

private struct AccountsPane: View {
    /// Strips what a copy-and-paste tends to bring with it.
    static func cleaned(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Bindable var settings: SettingsStore
    let coordinator: LibraryCoordinator
    let onShowPlayer: () -> Void

    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var signInError: String?

    private var google: GoogleOAuthService { coordinator.google }
    private var session: YTMusicSessionService { coordinator.ytSession }

    var body: some View {
        Form {
            Section("YouTube account") {
                if google.isConnected {
                    LabeledContent("Status") {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Disconnect", role: .destructive) {
                        Task { await google.signOut() }
                    }
                } else {
                    // The credentials are the user's own. Cue ships with none:
                    // an OAuth client checked into a public repository is a
                    // client whose daily quota anybody can spend, and there is
                    // no way to put one in a distributed app that does not
                    // amount to publishing it.
                    Text("""
                        Cue needs an OAuth client of your own. In the Google \
                        Cloud console: make a project, enable the YouTube Data \
                        API v3, then create an OAuth client of type Desktop app \
                        and paste it here. It stays in your keychain.
                        """)
                        .hint(settings.showsHints)

                    TextField("Client ID", text: $clientID, prompt: Text("…apps.googleusercontent.com"))
                    SecureField("Client secret", text: $clientSecret, prompt: Text("Desktop clients have one; leave empty otherwise"))

                    HStack {
                        Button("Sign in with Google") {
                            // Newlines as well as spaces, and any quotes the
                            // copy came wrapped in. A secret pasted out of the
                            // Cloud console routinely carries a trailing
                            // newline, and Google rejects the pair as
                            // `invalid_client` without ever saying that a
                            // stray character is the reason.
                            google.clientID = Self.cleaned(clientID)
                            google.clientSecret = Self.cleaned(clientSecret)
                            signInError = nil
                            Task {
                                do {
                                    try await google.signIn()
                                } catch {
                                    signInError = error.localizedDescription
                                }
                            }
                        }
                        .disabled(Self.cleaned(clientID).isEmpty || google.isSigningIn)

                        if google.isSigningIn {
                            ProgressView().controlSize(.small)
                            Text("Waiting for your browser…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let signInError {
                        Text(signInError)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("YouTube Music library") {
                Toggle("Use my YouTube Music library", isOn: $settings.unofficialProviderEnabled)

                Text("""
                    The official API cannot see a YouTube Music library — not \
                    liked songs, not history, not mixes. Turning this on signs \
                    in to music.youtube.com in a window and keeps the session \
                    cookie in your keychain, which is how the site itself \
                    works.

                    It uses endpoints Google does not document and may change \
                    without notice. If it stops working, turn it off; \
                    everything official keeps running.
                    """)
                    .hint(settings.showsHints)

                if settings.unofficialProviderEnabled {
                    let signedIn = coordinator.player?.isSignedIn == true

                    LabeledContent("Status") {
                        if signedIn {
                            Label("Signed in", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Signed out", systemImage: "person.crop.circle.badge.xmark")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Sign-in happens *in the player*, and nowhere else.
                    //
                    // There used to be a button here that signed in to a
                    // separate throwaway web view and kept a copy of the
                    // cookies. That copy goes stale within a day — Google
                    // rotates it — and once the API started borrowing the
                    // player's live session instead, this button was signing
                    // you into a window that no longer mattered. It looked like
                    // it had worked, and nothing played.
                    Button(signedIn ? "Open the Player" : "Sign in to YouTube Music…") {
                        onShowPlayer()
                    }

                    Text("""
                        Opens the player. Sign in to YouTube Music there and \
                        close the window — that one session is what plays your \
                        music and what reads your library, so there is only \
                        ever one place to sign in.
                        """)
                        .hint(settings.showsHints)

                    if let error = session.lastError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Pre-filled so that "sign in again after a revoked token" is one
            // button rather than a trip back to the Cloud console. The secret
            // is deliberately not pre-filled into a `SecureField` it would only
            // be shown back as dots in.
            clientID = google.clientID ?? ""
        }
    }
}

// MARK: - Grid

// MARK: - Notch

/// How the notch looks while Cue plays: which mark the right wing draws, and
/// party mode. The mark chosen here is the search bar's too — one mark for
/// the app.
private struct NotchPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Waveform") {
                Picker("Style", selection: $settings.plaqueAnimation) {
                    ForEach(PlaqueAnimation.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.plaqueAnimation.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Reacts to", selection: $settings.markReaction) {
                    ForEach(MarkReaction.allCases, id: \.self) { reaction in
                        Text(reaction.title).tag(reaction)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.plaqueAnimation.reacts)

                Text(settings.plaqueAnimation.reacts
                    ? settings.markReaction.summary
                    : "\(settings.plaqueAnimation.title) moves the way it always has; Wave and Island follow this.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("""
                    Drawn in the notch beside the cover, in the cover's colour, \
                    and in the search bar. The Record keeps its own colours.
                    """)
                    .hint(settings.showsHints)
            }

            Section("Headphones") {
                Toggle("Show AirPods when they connect", isOn: $settings.showsHeadphones)
                Text("""
                    When AirPods or other Bluetooth headphones connect, or move \
                    over to this Mac, the notch shows them for a few seconds \
                    with their battery and a green outline.
                    """)
                    .hint(settings.showsHints)
            }

            Section("Party mode") {
                LabeledContent("Strength") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.partyIntensity, in: 0...1) {
                            Text("Strength")
                        } minimumValueLabel: {
                            Text("Off")
                        } maximumValueLabel: {
                            Text("Full")
                        }
                        Text(partyReadout)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Text("""
                    A border in the cover's colours runs round the notch while \
                    music plays, surging on the beat, and the waveform's long \
                    and short lines take the cover's two colours. Further right \
                    is brighter, thicker and quicker.
                    """)
                    .hint(settings.showsHints)

                if settings.partyIntensity > 0, !settings.analysesAudio {
                    Label(
                        "Turn on “Make the mark move with the music” in General for the border to follow the real beat.",
                        systemImage: "waveform.badge.exclamationmark"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var partyReadout: String {
        settings.partyIntensity <= 0 ? "Off" : "\(Int((settings.partyIntensity * 100).rounded()))%"
    }
}

private struct TilesPane: View {
    @Bindable var settings: SettingsStore
    let coordinator: LibraryCoordinator

    /// The picker's own selection, because "no genre" has to be a real choice
    /// in the list rather than an absent one.
    private var genreSelection: Binding<String> {
        Binding(
            get: { settings.exploreGenre?.id ?? "" },
            set: { id in
                settings.exploreGenre = coordinator.genres.first { $0.id == id }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Text("""
                    The grid holds nine positions. Anything you keep stays in \
                    its position; the rest fill in from your library and change \
                    as that does. Press ⌘1 to ⌘9 in the panel to open a \
                    position without looking at it.
                    """)
                    .hint(settings.showsHints)
            }

            Section("Kept") {
                let kept = settings.pinnedTiles.enumerated().filter { $0.element != nil }

                if kept.isEmpty {
                    Text("Nothing kept yet. Right-click a tile or a search result to keep it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(kept, id: \.offset) { index, item in
                        if let item {
                            HStack {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button("Remove") { settings.unpin(at: index) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            Section("Explore") {
                Picker("Genre", selection: genreSelection) {
                    Text("Whatever YouTube Music suggests").tag("")

                    if let chosen = settings.exploreGenre,
                       !coordinator.genres.contains(where: { $0.id == chosen.id }) {
                        // The saved choice, listed even before the fetch has
                        // answered. Without this the picker opens showing the
                        // default and quietly discards a genre that is in fact
                        // in force.
                        Text(chosen.title).tag(chosen.id)
                    }

                    ForEach(coordinator.genres) { genre in
                        Text(genre.title).tag(genre.id)
                    }
                }
                .disabled(coordinator.genres.isEmpty && settings.exploreGenre == nil)

                if coordinator.isLoadingGenres {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Asking YouTube Music what it has…")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if coordinator.genres.isEmpty {
                    Text("The list arrives once you are signed in to YouTube Music.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("""
                    Explore's first page — ⌘E in the panel — asks for this \
                    genre instead of for whatever the service would have \
                    suggested. There is nothing to filter here: what the home \
                    feed returns carries no genre on it, so honouring a choice \
                    means asking a different question. The third page follows \
                    it where it can. New releases stay new releases.
                    """)
                    .hint(settings.showsHints)
            }
        }
        .formStyle(.grouped)
        .task { coordinator.loadGenres() }
    }
}


// MARK: - Updates

/// The update row: what version this is, and what Cue knows about newer ones.
private struct UpdatesRow: View {
    let updates: UpdateService
    @Bindable var settings: SettingsStore

    var body: some View {
        Toggle("Check for updates automatically", isOn: $settings.checksForUpdates)

        LabeledContent("Version") {
            HStack(spacing: 10) {
                Text(updates.currentVersion)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                action
            }
        }

        if let message = status {
            Text(message)
                .font(.callout)
                .foregroundStyle(isFailure ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch updates.state {
        case .checking:
            ProgressView().controlSize(.small)

        case .downloading:
            ProgressView().controlSize(.small)

        case .readyToRelaunch:
            Button("Relaunch to Update") { updates.installAndRelaunch() }
                .buttonStyle(.borderedProminent)

        default:
            Button("Check Now") {
                Task { await updates.check(userInitiated: true) }
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = updates.state { return true }
        return false
    }

    private var status: String? {
        switch updates.state {
        case .idle: nil
        case .checking: "Looking for a newer version…"
        case .upToDate: "Cue is up to date."
        case .available(let version, _): "Version \(version) is available."
        case .downloading: "Downloading…"
        case .readyToRelaunch:
            // Said plainly, because an update that swaps the running app is not
            // something to do quietly behind someone's back.
            "An update is downloaded and verified. Relaunching will install it."
        case .failed(let reason): reason
        }
    }
}


// MARK: - Hints

/// The small grey explanation under a setting.
///
/// Hideable, because the two audiences are different people: someone meeting a
/// switch for the first time needs to know what it does, and someone who has
/// used it for a month needs the window to be short enough to scan. Written as
/// a modifier rather than a wrapper view so the call sites read as the styling
/// they replaced.
private struct HintModifier: ViewModifier {
    let shows: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if shows {
            content
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// Styles a line as an explanation, and hides it when explanations are off.
    func hint(_ shows: Bool) -> some View {
        modifier(HintModifier(shows: shows))
    }
}
