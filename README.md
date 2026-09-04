# Cue

A speed dial for YouTube Music, one keystroke away.

Press a key anywhere on the Mac and a panel appears over whatever you were
doing: a search field on top, nine tiles below it. Type to find something, or
press ⌘3 to open the third thing without looking. Pick one and it plays — in
Cue's own player, signed in as you — and the panel is gone by the time the
first bar starts.

Cue is the thirty seconds between *wanting* music and *having* music, and
nothing else.

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

**⌥Space** out of the box, changeable in Settings → General, and it needs no
permission at all.

That last part is worth being precise about, because most apps with a global
shortcut ask for Accessibility. Cue uses `RegisterEventHotKey`, which hands the
window server one combination and asks to be told when it is pressed. It is
never shown any other keystroke, so there is nothing to grant. Accessibility and
Input Monitoring are what you need to *watch* the keyboard — an event tap — and
watching the keyboard is exactly what Cue has no business doing.

If pressing it does nothing, another app already owns that combination. macOS
gives a hotkey to whoever asked first and says nothing about the loser, so pick
a different one.

Cue also answers a URL, which is the way in for Shortcuts.app, a launcher you
already use, or anything that can run a command:

```sh
open cue://open
```

`cue://toggle` closes the panel again if it is already open; `cue://settings`
opens Settings. A `--dev` build claims `cue-dev://` instead, so a development
copy and an installed release do not fight over the same scheme.

## Playback

Cue plays it. Nothing opens.

YouTube Music's real player runs inside Cue, in a window kept off to one side
and all but invisible, so picking a song starts the music and leaves you exactly
where you were. Premium applies as it does on the web — no ads, background
playback, higher bitrate — because it is the same player and the same account.

What you get instead of a window is a small plaque in the top-right corner of
the screen, over every app including full-screen ones: the record, previous,
play/pause, next and mute. Scroll the speaker for volume. Click the record and
the full player appears, on whatever is playing.

The full player is a real window when you want one — back, forward and Home in
its toolbar, because a search result that is not in YouTube Music's catalogue
redirects to youtube.com and you need a way back. `cue://player` opens it, so
does the button in Settings, and signing in the first time needs it. Closing it
hides it; the music keeps going.

The panel shows the same thing in miniature: while something is playing, a
record spins in the corner of the search bar with notes drifting off it, and
clicking that opens the player too.

What Cue will not do is pull the audio stream out and play it through
`AVPlayer`. It would be more "native", and it means going around YouTube's
terms, its advertising and its accounting for the artists — and it breaks every
time Google rotates the signature ciphering, which is often. Settings →
General can switch back to handing off to your browser if you prefer that.

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
| ⌥Space | Open the panel, or close it if it is already open |
| Scroll the plaque's speaker | Volume |
| ⌘1 – ⌘9 | Open that position in the grid |
| ⌘E | Swap between your own music and Explore |
| ⌘R | Deal a different nine on this page |
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
├── Player/    the player window and where a chosen item is sent
├── UI/        search field, grid, tiles, results
├── Library/   the model, the provider protocol, both backends, the merge
├── Auth/      OAuth, the loopback listener, the Music session, the keychain
├── Services/  the global shortcut, thumbnails, launch at login
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

It does not decode or download audio, hold a queue of its own, reimplement a
player, scrobble, or touch a file on your disk. It chooses; YouTube Music's own
player does the rest, inside a window Cue owns. Anything past choosing is
YouTube Music's job and it is already better at it.

## Privacy

Cue talks to Google's own hosts and nowhere else. There is no analytics, no
crash reporting, no server of its own. Tokens and the Music session cookie live
in the keychain; pinned tiles and preferences live in `UserDefaults`. Nothing
logs a search query, a title, or any part of a credential unless you turn on
`CUE_DEBUG_NETWORK` yourself in a debug build.

No Accessibility, no Screen Recording, no Full Disk Access, no Input
Monitoring. The global shortcut is a registered hotkey rather than an event tap,
so Cue is told when its own combination is pressed and is never shown anything
else you type.

## License

MIT.
