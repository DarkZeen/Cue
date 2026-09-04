# Dial — build plan

*Working name: `Dial`. Rename freely.*

## Assumption

One app, not two: hotkey → overlay panel → search bar on top, 3×3 speed-dial grid below.
(If two separate binaries were actually intended, everything below still applies — just split into two targets.)

## Stack — forking `Tray`'s shell

Native Swift/SwiftUI (SwiftPM), `LSUIElement` agent, `NSPanel` non-activating overlay (Tray's `TrayPanel` / `TrayWindowController` / `TrayPresenter` pattern), custom URL scheme (`dial://open`) bound to a hotkey via Shortcuts.app / System Settings → Keyboard Shortcuts.

No Carbon hotkey code, no Accessibility permission — same trick Tray already uses.

## Data layer — merged official + unofficial

One `MusicLibraryProvider` protocol, two backends behind it:

- **`YouTubeDataAPI`** — OAuth, official, safe. Playlists, liked videos, `search.list`. Ships first, default.
- **`YTMusicInternal`** — unofficial, ytmusicapi-style. Real YT Music library/mixes/history via a one-time cookie capture in a hidden `WKWebView`. Feature-flagged, isolated — if Google breaks it, only this degrades.

Search hits both when the unofficial layer is on and merges results; the 9 tiles prefer whichever provider actually has library data.

## Repo structure

```
Dial/
  Package.swift
  Sources/Dial/
    App/       AppState, DialApp, AppDelegate, Diagnostics
    Panel/     DialPanel, DialWindowController, DialPresenter, DialLayout
    UI/        SearchBarView, SpeedDialGridView, TileView, ResultsListView
    Library/   MusicLibraryProvider, YouTubeDataAPIProvider, YTMusicInternalProvider
    Auth/      GoogleOAuthService, YTMusicSessionService
    Services/  ThumbnailProvider, LaunchAtLoginService
    Settings/  SettingsView, SettingsStore
  Resources/   Info.plist (dial:// scheme), entitlements
  Scripts/     build.sh
  Tests/DialTests/
```

## Milestones (function only — design/animation deferred)

- **M0** — repo scaffold, empty targets build + launch as background agent.
- **M1** — `dial://open` → panel appears, floats over any app, Esc closes. Proves the shortcut→overlay loop alone.
- **M2** — search bar wired to `YouTubeDataAPIProvider`, results list, click → hands off to `music.youtube.com/watch?v=…`.
- **M3** — 3×3 grid, tiles = pinned playlists/liked videos (manual pin in Settings, or auto-recent).
- **M4** — `YTMusicInternalProvider`: cookie capture, Settings toggle, merges into search + drives tile curation when signed in.
- **M5** *(later)* — design, animations, in-app playback instead of hand-off.

## GitHub

New repo, defaulting to name `Dial` unless renamed. Creating the remote and pushing touches the account — confirm before that step.

Next move: M0 scaffold.
