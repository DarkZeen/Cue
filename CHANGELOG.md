# Changelog

All notable changes to Tray are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- *Open after a drop*, which decides whether the shelf stays up for a moment to
  show what landed or closes as soon as the drop is done.
- A slider for how far inside the tray's edge the dashed drop outline sits.
- A new app icon and menu bar glyph: something living in the tray, peering out.
  Two shapes and nothing else, with the corner radii uneven on every corner and
  the eyes deliberately mismatched, which is the difference between a creature
  and a rounded rectangle with dots on it.
- *Icon size*, which sets how large each file is drawn on the shelf. Thumbnails
  are re-rendered at the chosen size rather than scaled up, and the shelf grows
  to fit them.
- *Shelf size*, which opens the tray Compact, Spacious, or at a width and
  height you set yourself. The presets are the Dynamic Island's own widths —
  480 and 560 points. Custom has no bracket of its own: it runs from the
  camera housing out to the edges of the display, and from whatever the icons
  need down to the Dock. The only limits are physical, and the readout shows
  what the shelf actually becomes rather than what was asked for, so a slider
  that has stopped doing anything says so.
- *Header padding*, which sets how far the name and the buttons sit from the
  sides of the shelf. Sides only: the header shares the menu bar's line, and
  anything vertical would take it off the line it is there to share. It stops
  at the shoulder, below which the header would be drawn outside the shape.
- *Position*, which puts the files left, centred or right across the shelf. The
  prompt on an empty shelf stands where the files will, so a left-aligned shelf
  does not point at the middle and then fill from the edge.
- Changing how the tray looks opens the tray. Drag a size slider and the shelf
  is up and changing under your hand; it closes on its own a couple of seconds
  after you stop. Size, icon size, file names, surface and the drop outline all
  do it — a shelf you cannot see while you are choosing it is a shelf you
  choose by trial and error.
- *Outline the drop area*, a dashed border marking where a dropped file will
  land. Rounded on all four corners, faint enough to stay a hint rather than a
  frame, and starting below the camera housing so the whole border is visible.
- Three surfaces, chosen in Settings. Island is the default: fully opaque and
  the same black as the camera housing, so on a notched Mac the shelf reads as
  the notch growing rather than as something hanging below it. Graphite is dark
  and slightly translucent; Light flips the ink so it stays legible.
- A header on the open shelf, in the menu bar rather than under it: the tray is
  drawn over the top of the menu bar, so the header sits in that same strip and
  its contents line up with the menu bar items either side of the shelf. The
  app's own glyph, the name and how many files are on it go hard against the
  left wall; a chevron that closes it and a gear holding *Clear the Shelf* and
  *Settings…* against the right. The whole of the middle belongs to the files,
  and the shelf no longer depends on the pointer wandering off to shut.
- *Stay open after a click*, which turns off the rule that a tray you have
  clicked into waits to be dismissed. With it off, the pointer leaving always
  closes the shelf.
- Keyboard control of the shelf. Click an item to select it, then Delete to
  remove it, Space to Quick Look it, ⌘C to copy it and ⌘V to paste files in.
  ⌘-click selects several, ⌘A selects everything, the arrow keys walk along the
  shelf, and Escape closes it. Copying writes file URLs, so pasting into Finder
  or a Save dialog lands the file itself and the original never moves.
- Copy in the item's secondary-click menu, so ⌘C is discoverable.
- Opening Tray while it is already running opens Settings. An app with no Dock
  icon and no windows would otherwise appear to do nothing when opened.
- A settings window with sidebar navigation and four pages: General, Tray,
  Privacy and About. The Privacy page states, permission by permission, what
  Tray does not ask for — no Accessibility, no Screen Recording, no Full Disk
  Access, no camera or microphone, and no network at all.

### Changed

- The tray now looks like a Dynamic Island, because that is what it is: a black
  shape hanging off the top edge of the display. The silhouette spans its full
  width where it meets the bezel and draws in over a 14-point shoulder on each
  side — the move the hardware makes where the notch meets the bezel — with a
  28-point bottom radius clamped to half the height, so the closed housing and
  the open shelf are one expression at two sizes rather than two constants.
  The content keeps the island's 28 points of side inset; the header does not,
  because it is in the menu bar's strip and belongs in the corners. What is
  left of the island's 36 / 18 / 22 chrome is 12 points of gap and 14
  underneath — the island's is sized for pages of controls, this is a name and
  two buttons over a single row of files — and all of what it gives back comes
  off the shortest shelf anyone can ask for. Controls are its 28-point squares
  with 9-point radii, lifting 2.2% under the pointer and settling to 96.5% on
  a press. Colour is its white on opaque black — 6.5% for a control, 12% for
  one that is chosen, 9% for the wash under the pointer — with an outline only
  when Increase Contrast asks for one, and no shadow at all, because a hole in
  the display does not cast one.
- Closed on a display without a camera housing, the tray recreates one rather
  than sitting there as a rounded pill: 180 points wide against a 32-point menu
  bar, scaled to the bar it actually has. One design on a MacBook Pro and on a
  5K panel.
- The open shelf is measured in points rather than as a share of the screen. A
  shelf is a small object near the top of the display and has no reason to grow
  with the monitor behind it.
- A selected file is lit with ink rather than the accent colour, and thumbnails
  are drawn as squircles at 19% of their own size with a hairline edge. One
  blue tile in a black cutout turns the whole thing back into a panel.
- The empty shelf is one symbol and nothing else — no plate behind it and no
  caption under it. The island puts its empty states on a plate with a line of
  text because it has a dozen sections to tell apart; Tray has one, and the
  shelf is already labelled.
- The tray's window is sized from the display rather than from a fixed maximum,
  and stops where macOS says the usable area does, so a shelf dragged out to
  its full height never ends up over the Dock.
- The shelf closes faster than it opens. Closing used to be the slowest motion
  in the app, sitting on the exit of the most-seen element — which was fine
  when a grace period ran before it, and reads as lag now that it starts the
  moment the pointer leaves.
- Items arrive from below rather than growing from nothing in place, and at a
  gentler scale. Files travel upward into the tray, so that is the direction an
  arriving one comes from.
- The open shelf's walls flare outwards where they meet the top edge of the
  screen, instead of stopping at a square corner. The closed tray keeps its
  square silhouette, because on a notched Mac it *is* the camera housing and
  has to match it exactly.
- The shelf now closes as the pointer leaves rather than after a grace period.
  *Close after* in Settings still goes up to three seconds for anyone who wants
  the old behaviour, and a tray you have clicked into stays open regardless —
  otherwise reaching for the keyboard would close it.

### Fixed

- Dragging a file to the top of the screen did not open the tray. The panel is
  transparent, and macOS hands a drag to a transparent window only over pixels
  it has painted — so the wide drop target existed only in `hitTest`, and the
  real one was whatever the surface drew. That used to include a soft shadow;
  with the island's shadow gone it was a 56 × 5 handle behind the camera
  housing. The hover region is now painted at 1% opacity, and the wider drag
  region joins it only while the mouse button is down and moving, so ordinary
  clicks along the menu bar still go where they were aimed.
- A pointer resting at the top centre could make the tray flicker open and
  shut ten times a second. The tray marked itself open a beat before its new
  shape arrived, and in that beat the pointer seemed to have left the old one.
  The open region now always includes the strip that opened it.
- Reduce Motion had no effect until the app was relaunched. The preference was
  read straight from `NSWorkspace` inside view bodies, so nothing invalidated
  when it changed. It now travels through the environment, the way the
  reduced-transparency preference already did.
- The tray gave no feedback at all until a drag was directly over the drop
  area. The anticipation step had a value defined for it and no call site.
- A drop landed with no acknowledgement. The shelf now gives a little as
  something lands and springs back — two values and an underdamped spring
  rather than three hand-written keyframes.
- The shelf could stick open after the pointer left. Two separate causes, both
  of which stopped anything from ever telling the tray the pointer had gone.
  The hover tracking area was sized to the tray and rebuilt every time the tray
  changed shape; a rebuild makes AppKit re-emit enter and exit events that
  match no pointer movement, and once an *enter* was missed that way the
  matching exit never arrived either. The tracking area is now constant and
  where the pointer is gets decided from its actual position. Separately, a
  drag session that ended without a `draggingExited` — cancelled with Escape,
  or finished elsewhere — left the tray believing a drag was still overhead,
  and a tray that thinks a drag is overhead refuses to close.
- Settings recorded preferences nobody chose. SwiftUI's binding setters fire
  during view updates as well as on input, so merely opening the settings
  window wrote every value on the page to disk — and a slider wrote a *clamped*
  value, which is how a setting nobody touched ended up pinned to the end of
  its range. Every write is now guarded on the value actually changing.
- The open shelf's contents sat under the camera housing on a notched Mac,
  where nothing is visible, cutting the top off every thumbnail in the middle
  of the shelf.
- The *Close after* setting had no effect at all. The presenter read a constant
  instead of the stored value, so the slider moved and nothing happened.
- Tray no longer records a Launch at Login preference the user never expressed.
  `SMAppService` reports the app as enabled on a fresh install, and startup
  reconciliation treated an absent preference as "off" — so it read that as the
  user having switched it on elsewhere, adopted it, and wrote it down. "Never
  asked" is now a distinct state from "asked for off".
- The tray's closed item indicator drew below the tray instead of inside it.
  The open shelf was setting the height of the layer stack, so the closed
  layer's alignment resolved against the wrong bounds.
- A tray opened from the menu bar never closed on its own, because nothing
  schedules a collapse when there is no pointer to leave.
- The tray could open when nothing had gone near it: rebuilding a tracking area
  makes AppKit fire enter and exit events that do not correspond to any pointer
  movement, and only the exit was being verified.

## [0.1.0]

First release. The scope is deliberately locked: a shelf at the top of the
screen that files go into and come back out of, and nothing else.

### Added

- A tray anchored to the top centre of the screen, measured from the display's
  own safe area rather than hardcoded, so notched MacBooks, external monitors
  and scaling changes all place it correctly.
- Drag files and folders in from anywhere, several at once. The tray keeps a
  reference; the originals are never moved, copied or modified.
- Drag items back out into Finder, Save dialogs, upload fields, or any other
  destination that accepts a file, as a real macOS drag session.
- File icons immediately, replaced by Quick Look thumbnails as they arrive.
- One tray per connected display, following monitors as they come and go.
- Secondary click for Remove from Tray, Reveal in Finder and Quick Look.
- A menu bar item with Open Tray, Launch at Login, Settings and Quit.
- Settings for activation (hover, drag, or both), auto-collapse delay, file
  names, the menu bar icon and Launch at Login.
- Launch at Login through `SMAppService`, with the three states that actually
  fail — read-only location, approval revoked in System Settings, unstable
  signature — detected and explained instead of silently ignored.
- Full-screen and Spaces support, without ever taking focus from the app in
  front.
- Reduced motion and reduced transparency support, VoiceOver labels, and a
  dark surface that holds up in both light and dark appearance.
- A signed, notarized disk image built by a GitHub Actions workflow, and a
  three-tier local signing ladder that needs no Apple Developer account.

[Unreleased]: https://github.com/DarkZeen/Tray/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DarkZeen/Tray/releases/tag/v0.1.0
