# Cue

A speed dial for YouTube Music, one keystroke away.

Press a key anywhere on the Mac and a panel appears over whatever you were
doing: a search field on top, nine tiles below it. Type to find something, or
press ⌘3 to open the third thing without looking. Pick one and it opens in
YouTube Music; the panel is gone before the page has loaded.

Cue does not play anything itself. It is the thirty seconds between *wanting*
music and *having* music, and nothing else.

## What it needs

macOS 26, and the Xcode Command Line Tools to build it. No Xcode, no Apple
Developer account, no package manager, no third-party dependencies.

```sh
./Scripts/setup-signing.sh          # once — see below, it matters
./Scripts/build.sh --dev --install
```

`setup-signing.sh` is not optional here. An ad-hoc signature changes on every
build, so macOS treats each rebuild as a different application and the keychain
refuses it access to what the previous build stored — which is where your sign-in
lives. Without a stable identity you are signed out after every build.

## The keyboard shortcut

Cue registers no hotkey. Registering one would mean asking for Accessibility
access to your keyboard, and it does not need it — so instead, bind any key you
like to a shortcut that runs:

```sh
open cue://open
```

Shortcuts.app will do it, so will System Settings → Keyboard → Keyboard
Shortcuts, so will any launcher you already have. `cue://toggle` closes the
panel again if it is already open; `cue://settings` opens Settings.

A `--dev` build claims `cue-dev://` instead, so a development copy and an
installed release do not fight over the same scheme.

## Connecting an account

Cue talks to YouTube two ways, and the second one is optional.

**YouTube Data API** — official, OAuth, on by default. It needs an OAuth client
of your own, which takes about five minutes to make and costs nothing:
[docs/GOOGLE-SETUP.md](docs/GOOGLE-SETUP.md) walks through it, including the
step that otherwise signs you out every seven days. The credentials go in your
keychain.

Cue ships with no client of its own on purpose. An OAuth client checked into a
public repository is a client whose daily quota anybody can spend.

**YouTube Music session** — unofficial, off by default. The official API cannot
see a YouTube Music library: not liked songs, not history, not mixes. Turning
this on signs you in to music.youtube.com in a window and keeps the session
cookie in your keychain, which is how the site itself works. It uses endpoints
Google does not document and may change without notice. If it breaks, turn it
off — everything official keeps running.

Search asks both and merges the answers, preferring whichever knows more.

## Keyboard

| Key | Does |
|---|---|
| ⌘1 – ⌘9 | Open that position in the grid |
| ↑ ↓ ← → | Move around the grid, or up and down the results |
| Return | Open what is highlighted, or the first result |
| Escape | Clear the search; on an empty panel, close it |
| ⌘Q | Quit |

Right-click a tile or a search result to keep it in the grid, or to copy its
link.

## Layout

```text
Sources/Cue/
├── App/       entry point, delegate, composition root, main menu, logging
├── Panel/     the panel, its window, layout, motion, presentation state
├── UI/        search field, grid, tiles, results
├── Library/   the model, the provider protocol, both backends, the merge
├── Auth/      OAuth, the loopback listener, the Music session, the keychain
├── Services/  thumbnails, launch at login
└── Settings/  settings window and stored preferences
```

AppKit owns anything system-level — the borderless panel, window levels,
collection behaviour, screen coordinates, the keyboard. SwiftUI draws the
contents. The parts that look like they would be nicer in SwiftUI are usually
the parts that need AppKit.

## Development

```sh
./Scripts/build.sh --debug          # build
./Scripts/test.sh                   # tests
./build/Cue.app/Contents/MacOS/Cue  # run
```

Four environment variables help, all compiled out of release builds entirely:

| Variable | Does |
|---|---|
| `CUE_DEBUG_OPEN=1` | Shows the panel at launch |
| `CUE_DEBUG_QUERY=ambient` | Opens the panel with that already typed |
| `CUE_DEBUG_HOLD=1` | Stops the panel closing when it loses focus |
| `CUE_DEBUG_SETTINGS=1` | Opens Settings at launch; a pane name such as `accounts` opens that page |
| `CUE_DEBUG_NETWORK=1` | Logs every request, with its size |

`HOLD` is how you look at the panel for longer than the two seconds it normally
survives being clicked away from.

## What it does not do

It does not play audio, hold a queue, show a mini player, control playback,
scrobble, download anything, or touch a file on your disk. It finds a thing and
hands it to YouTube Music. Anything past that is YouTube Music's job and it is
already better at it.

## Privacy

Cue talks to Google's own hosts and nowhere else. There is no analytics, no
crash reporting, no server of its own. Tokens and the Music session cookie live
in the keychain; pinned tiles and preferences live in `UserDefaults`. Nothing
logs a search query, a title, or any part of a credential unless you turn on
`CUE_DEBUG_NETWORK` yourself in a debug build.

No Accessibility, no Screen Recording, no Full Disk Access, no Input
Monitoring. The shortcut is a URL open rather than a keyboard tap precisely so
that none of those are needed.

## License

MIT.
