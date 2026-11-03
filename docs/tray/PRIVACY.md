# Privacy

Short version: Tray knows about the files you drag onto it, and nothing else.

## What the app can see

A file becomes visible to Tray in exactly one way — you drag it onto the tray.
There is no folder scanning, no indexing, no watching of directories, and no
way for anything to arrive on the shelf that you did not put there.

For each file on the shelf, Tray reads:

- the path, so it can hand the file back when you drag it out
- the name macOS displays for it
- whether it is a folder
- whether it still exists
- an icon, and a Quick Look thumbnail

That is the whole list. File *contents* are never read by Tray; the thumbnail
comes from macOS's own Quick Look service, which is the same thing that draws
the preview in Finder.

## What leaves your Mac

Nothing. Tray opens no network connections at all — no update check, no
telemetry, no crash reporting, no analytics. There is no account and nothing to
sign in to.

## What is stored

The shelf lives in memory for as long as the app is running. Quitting empties
it. Nothing about which files you stashed is written to disk, ever.

The only thing Tray saves is your settings — activation mode, auto-collapse
delay, whether to show file names, whether to show the menu bar icon, and
whether you asked it to launch at login. Those live in the standard macOS
preferences for `com.tray.app`.

## What is never touched

Dropping a file on the tray does not move it, copy it, rename it or modify it.
The shelf holds a reference to where the file already is. Dragging an item out
is advertised to the destination as a copy, specifically so that no destination
can relocate your original.

## Permissions

Tray requests none, and needs none:

| Permission | Needed? |
|---|---|
| Full Disk Access | No |
| Accessibility | No |
| Screen Recording | No |
| Camera, Microphone | No |
| Contacts, Calendar, Photos | No |
| Automation | No |

The one thing Tray asks macOS for is a login item, and only if you switch on
Launch at Login yourself.

## Verifying any of this

The source is here, and it is small. `Sources/Tray/Files/` is the entire
relationship between this app and your filesystem, and there is no networking
code anywhere in the repository to read.
