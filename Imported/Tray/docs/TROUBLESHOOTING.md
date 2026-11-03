# Troubleshooting

## "Tray can't be opened because Apple cannot check it for malicious software"

You are running a build that was not notarized — usually one you compiled
yourself, or a disk image from a fork.

Right-click Tray in Applications, choose **Open**, then **Open** again in the
dialog. macOS remembers the decision and will not ask again. Official releases
are signed with an Apple Developer ID and notarized, so they do not show this.

## The menu bar icon is missing

Two possibilities.

If you switched it off in Settings, bring it back by launching Tray again — the
app is already running, so this does nothing — or by opening the tray at the
top of the screen and using it directly. If you would rather have the icon
back, quit Tray from Activity Monitor, then delete the preference:

```sh
defaults delete com.tray.app showsMenuBarIcon
```

If your menu bar is simply full, macOS hides the icons that do not fit,
starting from the left. Removing another menu bar item, or widening the bar by
hiding something else, brings it back.

## Launch at Login does not stick

Three separate things can cause this, and Tray tells you which one in Settings.

**"Move Tray to your Applications folder for this to stick."** The app is
running from a mounted disk image, from Downloads under Gatekeeper's app
translocation, or from another read-only location. macOS cannot register a
login item that will still be at the same path next time. Move Tray to
`/Applications` and try again.

**"Tray is switched off in System Settings ▸ General ▸ Login Items."** The item
exists but is disabled. Tray opens that pane for you when this happens; switch
it on there.

**It worked, then stopped after you rebuilt.** An ad-hoc code signature is
different on every build, so macOS treats each rebuild as a new application and
drops the registration. Run `./Scripts/setup-signing.sh` once — it creates a
stable local identity — then rebuild.

## The tray does not appear over a full-screen app

Tray sits at the status bar window level and joins all Spaces, which puts it
alongside full-screen windows rather than behind them. If a specific app still
covers it, that app is drawing above the status bar level, which is unusual and
worth [reporting](https://github.com/DarkZeen/Tray/issues) with the app's name.

## Dragging onto the tray does nothing

Check **Settings ▸ Tray ▸ Open the tray with**. If it is set to *Hover*, drags
will not open the shelf. *Both* is the default.

The drop target is wide but not unlimited — roughly 320 points across the top
centre of the display the pointer is on. Aim for the middle of the screen's top
edge.

## Thumbnails show as plain file icons

Not every file has a Quick Look preview. Plain text, code, archives and folders
have no thumbnail to generate, so Tray shows the system icon, which is what
Finder shows too.

For files that *should* have a preview, the first one after a restart can take
a moment while macOS's thumbnail service warms up. Tray shows the icon
immediately and swaps in the preview when it arrives, so nothing is ever blank.

## An item says the file is unavailable

The file was moved, renamed or deleted after you dropped it. The tray holds a
reference rather than a copy, so it has nothing to fall back on. Remove the
item with a secondary click, and drag the file in again from its new home.

## The tray opens when I did not mean it to

Turn the hover activation off: **Settings ▸ Tray ▸ Open the tray with ▸ Drag
files to top**. The shelf will then only open when something is actually being
dragged, or from the menu bar.

## Reporting something else

[Open an issue](https://github.com/DarkZeen/Tray/issues) with your macOS version,
your Mac model, whether the display involved has a notch, and what you were
doing. If it is a positioning problem, a build with `TRAY_DEBUG=1` shows the
exact geometry Tray measured — a photo of that overlay answers most of these
questions instantly.
