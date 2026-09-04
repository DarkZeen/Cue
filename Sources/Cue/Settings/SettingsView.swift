import AppKit
import SwiftUI

/// The settings window.
///
/// Three tabs, and the middle one is the only one that matters: without an
/// OAuth client Cue cannot do anything at all, so Accounts is where a first
/// run ends up and it is written as instructions rather than as a form.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let coordinator: LibraryCoordinator
    @Bindable var launchAtLogin: LaunchAtLoginService

    @State private var selection: Pane = Pane(rawValue: Diagnostics.debugSettingsPane ?? "") ?? .general

    /// Not named `Tab`: SwiftUI has its own, and it is the one being used below.
    enum Pane: String {
        case general
        case accounts
        case tiles
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: .general) {
                GeneralPane(settings: settings, launchAtLogin: launchAtLogin)
            } label: {
                Label("General", systemImage: "gearshape")
            }

            Tab(value: .accounts) {
                AccountsPane(settings: settings, coordinator: coordinator)
            } label: {
                Label("Accounts", systemImage: "person.crop.circle")
            }

            Tab(value: .tiles) {
                TilesPane(settings: settings)
            } label: {
                Label("Grid", systemImage: "square.grid.3x3")
            }
        }
        .tabViewStyle(.tabBarOnly)
        .frame(width: 560, height: 520)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var launchAtLogin: LaunchAtLoginService

    @State private var didCopyCommand = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin.isEnabled)
                if launchAtLogin.requiresApproval {
                    Text("macOS is waiting for you to allow this in System Settings → General → Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Close the panel after opening something", isOn: $settings.closesAfterOpening)
                Toggle("Fill empty tiles with recent and library items", isOn: $settings.autoFillsEmptyTiles)
            } footer: {
                Text("Filled-in tiles are drawn slightly faded. Right-click one to keep it where it is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard shortcut") {
                // Cue registers no hotkey of its own. Explaining that plainly
                // is better than a shortcut recorder that would need
                // Accessibility access to work — the permission this whole
                // design exists to avoid.
                Text("""
                    Cue has no built-in hotkey, on purpose: registering one \
                    would mean asking for Accessibility access to your \
                    keyboard, and it does not need it.

                    Instead, make a shortcut that runs this command, and give \
                    it whatever key you like — in Shortcuts.app, or with any \
                    launcher you already use.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Accounts

private struct AccountsPane: View {
    @Bindable var settings: SettingsStore
    let coordinator: LibraryCoordinator

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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Client ID", text: $clientID, prompt: Text("…apps.googleusercontent.com"))
                    SecureField("Client secret", text: $clientSecret, prompt: Text("Desktop clients have one; leave empty otherwise"))

                    HStack {
                        Button("Sign in with Google") {
                            google.clientID = clientID.trimmingCharacters(in: .whitespaces)
                            google.clientSecret = clientSecret.trimmingCharacters(in: .whitespaces)
                            signInError = nil
                            Task {
                                do {
                                    try await google.signIn()
                                } catch {
                                    signInError = error.localizedDescription
                                }
                            }
                        }
                        .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || google.isSigningIn)

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
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.unofficialProviderEnabled {
                    if session.isConnected {
                        LabeledContent("Status") {
                            Label("Signed in", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Button("Sign out", role: .destructive) { session.disconnect() }
                    } else {
                        Button("Sign in to YouTube Music…") { session.presentSignIn() }
                            .disabled(session.isPresentingSignIn)
                    }

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

private struct TilesPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Text("""
                    The grid holds nine positions. Anything you keep stays in \
                    its position; the rest fill in from your library and change \
                    as that does. Press ⌘1 to ⌘9 in the panel to open a \
                    position without looking at it.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        }
        .formStyle(.grouped)
    }
}
