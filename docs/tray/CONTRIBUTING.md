# Contributing

Thanks for looking. Tray is small on purpose, and the fastest way to get a
change merged is to keep it that way.

## Scope

The whole product is: **drag files in → files live in the tray → drag files
out**. [docs/SPEC.md](docs/SPEC.md) §78 lists what is explicitly out of scope —
media controls, clipboard history, weather, widgets, AI, automation, file
conversion, and so on. A pull request that adds one of those will be declined
however well written it is. A pull request that makes the existing interaction
feel better is the most welcome kind.

## Getting set up

You need the Xcode Command Line Tools and macOS 26. Nothing else — no Xcode, no
Apple Developer account, no package manager.

```sh
./Scripts/setup-signing.sh    # once
./Scripts/build.sh --dev --install
```

`--dev` stamps a separate bundle identifier, so a development build can sit
next to an installed release without the two fighting over the same login-item
registration.

`./Scripts/setup-signing.sh` creates a self-signed certificate called
`Tray Signing` in its own keychain. It matters more than it looks: an ad-hoc
signature is different on every build, so macOS treats each rebuild as a
different application and drops Launch at Login along with it.

## The loop

```sh
./Scripts/build.sh --debug            # build
TRAY_DEBUG=1 ./build/Tray.app/Contents/MacOS/Tray   # run with the geometry overlay
./Scripts/test.sh                     # tests
./Scripts/test.sh --previews          # render every tray state into build/previews
```

`--previews` is the fastest way to look at a visual change: it renders the tray
in each of its states through the real `NSHostingView` path and writes PNGs.
It is not a substitute for running the app — translucency only exists over a
real desktop — but it catches layout and typography in a second rather than a
minute.

Three environment variables help, all compiled out of release builds entirely:

| Variable | Does |
|---|---|
| `TRAY_DEBUG=1` | Draws the screen, safe area, notch size, tray frame and state next to the tray |
| `TRAY_DEBUG_SEED=/path/a:/path/b` | Puts those files on the shelf and opens it at launch |
| `TRAY_DEBUG_HOLD=1` | Stops the tray closing on its own |
| `TRAY_DEBUG_SETTINGS=1` | Opens the settings window at launch; a pane name such as `privacy` opens that page |

`SEED` and `HOLD` together are how you get a particular state onto a real
screen, over a real desktop, and then look at it for as long as you like:

```sh
TRAY_DEBUG_HOLD=1 TRAY_DEBUG_SEED="/System/Applications/Music.app:/System/Applications/Chess.app" \
  ./build/Tray.app/Contents/MacOS/Tray
```

Every interesting state of this app is one the tray leaves after a second or
two. Without a way to freeze them, reviewing translucency, notch alignment or
a spring's settle is a race against a timer you will lose.

## Layout

```text
Sources/Tray/
├── App/         entry point, delegate, composition root, logging
├── MenuBar/     status item, menu actions, the menu bar glyph
├── Tray/        the panel, its content view, layout, motion, state machine
├── DragDrop/    drag source, drop handler, pasteboard reading
├── Files/       the model, the store, thumbnails
├── Screen/      display geometry, one tray per display
├── Services/    launch at login, Quick Look
└── Settings/    settings window and stored preferences
```

AppKit owns anything system-level — the borderless non-activating panel, window
levels, collection behaviour, screen coordinates, real drag sessions. SwiftUI
draws the tray. Please keep that seam where it is; the parts that look like they
would be nicer in SwiftUI are usually the parts that need AppKit.

## Conventions

- **No third-party dependencies.** `Package.swift` declares none and should
  keep declaring none.
- **Swift 6 language mode, main actor by default.** Start single-threaded and
  move work off the main actor only where something is measurably slow.
- **State machine over booleans.** Every visible configuration of the tray is
  one case of `TrayPresentationState`. Adding a `var isSomething` to the
  presenter is almost always the wrong fix.
- **Constants live in `TrayMetrics` and `TrayAnimation`.** No magic numbers in
  views.
- **Comments explain why.** The what is in the code; the reason a value is 0.65
  rather than 0.3 is not.
- **Never touch the user's files.** The tray holds URLs. Nothing in this
  codebase should ever move, copy, rename or delete something a user dropped
  in, and a drag out is advertised as `.copy` for exactly that reason.

## Motion

The three animation layers — container, items, interaction feedback — move
differently on purpose, and the amplitudes are small. Before changing a spring,
read [docs/SPEC.md](docs/SPEC.md) §44–46: the tray is meant to feel expensive
rather than playful, and "add more bounce" is the one review comment that will
always be pushed back on.

## Pull requests

- One change per pull request.
- Run `./Scripts/test.sh` and `./Scripts/build.sh` before opening it.
- Say what you did on real hardware. Notch behaviour, multi-monitor behaviour
  and full-screen behaviour cannot be reasoned about — they have to be tried.
- Screenshots or a screen recording for anything visual.
