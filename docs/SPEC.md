# Tray — Master Specification

## Project: Minimal macOS Notch File Tray

You are an expert macOS application engineer, UI engineer, interaction designer, and release engineer.

Build a polished native macOS app whose **single purpose** is to provide a beautiful temporary file tray/shelf attached to the top-center of the screen, inspired by the interaction model of NotchNook's file tray.

This is **not** a NotchNook clone.

Do not copy NotchNook's branding, logo, assets, exact UI, text, or proprietary implementation. We are borrowing the general product concept:

> "A small tray integrated into the Mac's top edge where I can temporarily stash files and drag them back out later."

The application should feel like a product Apple could have shipped.

The app must be extremely focused. **Do not add media controls, calendar, weather, widgets, webcam, clipboard manager, system HUDs, notification aggregation, AI functionality, shortcuts/workflows, or other unrelated features.**

The entire product is:

**drag files in → files live in tray → inspect/reorder → drag files out**

---

# 0. REVISION NOTE

This document is revision 2, amended 2026-09-01 after a review of the actual
development environment and a decision pass with the project owner.

Amended sections, and what changed:

| § | Was | Now |
|---|---|---|
| 34 | "use `SMAppService`" | plus the three conditions that actually make it work |
| 39 | ambiguous on sandboxing | explicitly **not** sandboxed |
| 42 | `Tray/` source tree | `Sources/Tray/` (SwiftPM layout) |
| 60 | macOS 14.6+, universal build | **macOS 26+**, arm64 only |
| 61 | `Tray.xcodeproj` | **SwiftPM** + `Scripts/build.sh` |
| 62 | repo tree with `.xcodeproj` | repo tree with `Package.swift` |
| 63 | README says 14.6+ | README says 26+ |
| 66 | `xcodebuild` in CI | `swift build` in CI |
| 67 | "structure for signing" | concrete three-tier signing ladder |

Everything else stands as originally written.

---

# 1. PRODUCT VISION

The working concept is a small app currently referred to as:

**Tray**

Use this name throughout the project — app name, bundle identifier, and
repository. The working directory is called `NotchTray` for historical reasons;
that name does not appear in the product.

The app should live primarily in the macOS menu bar and visually attach itself to the top-center of the active display.

When nothing is happening, the UI should be extremely unobtrusive.

When the user approaches the tray or drags something toward the top of the screen, it should elegantly expand into a compact black/dark floating shelf.

The interaction should feel physical:

- closed → compact pill
- hover → subtle anticipation
- drag-over → expand
- item enters → item settles into shelf
- shelf remains open briefly
- cursor leaves → shelf contracts
- empty shelf → becomes almost invisible
- multiple files → horizontally arranged thumbnails
- many files → compact scrolling shelf

Think:

**macOS native + Dynamic Island physicality + Finder drag/drop utility**

but **much simpler**.

---

# 2. CORE FUNCTIONALITY

Implement only these core operations.

## Add items

The user can drag:

- files
- folders

onto the tray.

When a draggable filesystem object enters the tray's hit area:

1. The tray should expand.
2. The background should subtly brighten.
3. The drop target should visually activate.
4. A gentle "landing" animation should communicate that dropping is possible.
5. When dropped, the item becomes a tray item.

Support multiple simultaneous dragged files.

Example:

```text
photo.jpg
invoice.pdf
presentation.key
Assets/
```

and drags them toward the top-center.

The tray opens and accepts them all.

---

# 3. TRAY SEMANTICS

The tray is a **temporary holding shelf**, not a second filesystem.

Very important:

Do NOT move, copy, modify, or delete the original files when adding them.

The tray should simply retain references/URLs to the original filesystem objects.

Example:

```text
~/Desktop/photo.jpg
```

remains on the Desktop.

The tray merely remembers:

```text
file:///Users/name/Desktop/photo.jpg
```

until the user takes it out.

## Recommended default behavior

Tray state should live in memory for the current application session.

When the application quits:

- tray contents disappear
- original files are untouched

Do not create a permanent database.

However, structure the storage layer so persistence could theoretically be added later without rewriting the UI.

---

# 4. WHAT HAPPENS WHEN A FILE IS ADDED

Upon drop:

## Empty tray

If the tray was empty:

```text
collapsed pill
        ↓
expanded shelf
        ↓
file lands into shelf
        ↓
slight settling animation
        ↓
shelf remains open
```

## Existing tray

If there are already files:

```text
existing items
     +
new item
     ↓
new item enters from cursor/drop direction
     ↓
existing items gently shift
     ↓
new item settles into position
```

Do not use a crude `fadeIn`.

The item should feel like it has physically joined the tray.

---

# 5. EMPTY STATE

The empty state should be extremely minimal.

Collapsed:

```text
• small dark pill
```

or an almost invisible handle.

Expanded:

```text
┌──────────────────────────────────────────────┐
│              Drop files here                 │
└──────────────────────────────────────────────┘
```

Do not put large instructional text in the default UI.

The instruction can appear subtly only when the user is dragging something over the area.

For example:

```text
↓  Drop to stash
```

Use very small secondary text.

The application should never feel like it is presenting a permanent onboarding screen.

---

# 6. VISUAL DESIGN

The tray should be inspired by Apple's modern macOS aesthetic without copying any specific application's interface.

## Overall appearance

Dark translucent capsule.

Characteristics:

- almost-black base
- subtle transparency
- subtle background blur
- very soft shadow
- extremely smooth corners
- slight internal highlight
- high-quality thumbnail rendering
- restrained typography
- no gradients unless extremely subtle

Use native macOS materials where appropriate. With a macOS 26 floor (§60), the
current system materials are available unconditionally — no availability
fallbacks are needed.

Preferred visual character:

```text
dark graphite surface
85–95% visual opacity
strong contrast
soft edges
no borders or only an extremely subtle edge highlight
```

Do not make it look like:

- a web app
- a standard SwiftUI rectangular window
- a giant floating black rectangle
- a glassmorphism Dribbble mockup

It should look **native to macOS**.

---

# 7. DIMENSIONS

These should be implemented as constants/configuration values rather than scattered magic numbers.

Use something approximately like:

Tray now uses the Dynamic Island's own measurements, which is what the
paragraph below asks for: they were arrived at by looking at a shipping
implementation of exactly this shape rather than by guessing at brackets.

```text
shoulder            14        # how far the shape draws in from the top edge
cornerRadius        28        # clamped to height / 2, so one expression fits both states

horizontalInset     28
headerHeight        36
spacing             18        # header to content
bottomInset         22
cutoutClearance     10        # below the camera housing, real or recreated

closed width        the camera housing, or 180 × menuBarHeight / 32 without one
closed height       the camera housing, or the menu bar's height

open width          480 compact, 560 spacious, 360–600 custom
open height         clearance + chrome + content, +40 spacious, 160–520 custom

thumbnailSize       52 (32–88)
itemSpacing         12
```

Do not hardcode these exact values forever.

The final values should be adjusted by actually running the application and visually inspecting it on real macOS.

---

# 8. NOTCH GEOMETRY

This is one of the most important parts.

Do not assume every Mac has a notch.

Use `NSScreen` APIs to determine screen safe areas.

Apple documents `NSScreen.safeAreaInsets`, including the fact that the top inset can correspond to the area occupied by a camera housing, and exposes `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` for the usable regions around it.

Create a dedicated component:

```text
ScreenGeometryService
```

Responsibilities:

- identify active screen
- identify primary screen
- detect changes in display configuration
- determine top safe-area/notch geometry
- calculate tray anchor
- calculate collapsed width
- calculate expanded width
- react to monitor connection/disconnection
- react to resolution changes
- react to display sleep/wake

Do NOT rely on fixed pixel coordinates such as:

```swift
screen.width / 2 - 200
```

alone.

The position needs to adapt to actual screen geometry.

**Reference measurement.** The development Mac is an M2 MacBook Air with a
notched built-in display reporting `safeAreaInsets.top == 32.0`. Use that as a
sanity check, never as a constant.

---

# 9. NOTCHED DISPLAY

On a MacBook with a physical notch:

The tray should visually align with the notch area.

The closed state should appear as though it is naturally integrated into the top-center.

It should not visibly float 30–50 px below the menu bar.

The top edge should feel physically attached to the screen's upper boundary.

The animation should make it feel as though the tray is emerging from the top edge.

---

# 10. NOTCHLESS DISPLAY

On an external display or older Mac without a notch:

Create a small virtual top-center capsule.

Do NOT attempt to fake an enormous black camera notch.

Instead:

```text
             ┌──────────────┐
             │     tray     │
             └──────────────┘
```

The result should be visually elegant even when there is no physical notch.

The same interaction model should work.

---

# 11. MULTI-MONITOR SUPPORT

This is mandatory.

Every connected display should be independently capable of hosting the tray.

If the mouse is on display B and the user drags a file toward the top-center of display B:

**display B's tray should respond.**

Do not permanently pin the tray to the main display.

Build:

```text
TrayWindowController
ScreenGeometryService
DisplayCoordinator
```

so that the application can create/manage one tray presentation per relevant display.

Handle:

- monitor connected
- monitor disconnected
- resolution changed
- display arrangement changed
- sleep/wake
- external monitor becoming primary

Listen for:

```swift
NSApplication.didChangeScreenParametersNotification
```

and rebuild/reposition geometry accordingly.

**This is testable.** The project owner has a second external display available,
so multi-monitor behaviour must be verified on real hardware, not reasoned about.

---

# 12. MOUSE INTERACTION

The tray needs multiple ways to open.

## Method A — hover

When the pointer approaches the collapsed tray:

```text
collapsed
   ↓
tiny scale/height increase
   ↓
expanded
```

But make the activation delay short enough to feel immediate.

Suggested:

```text
hover activation delay: 80–140ms
```

Do NOT instantly trigger it from a large invisible region.

Avoid accidental activation.

---

# 13. DRAG-OVER ACTIVATION

This is the most important interaction.

The tray should respond intelligently to macOS drag operations.

When a file is dragged toward the top-center:

```text
                    pointer
                       ↓

               ┌────────────┐
               │    tray    │
               └────────────┘
```

The tray expands.

The drop target becomes active.

Suggested animation:

```text
normal:
scale 1.00

drag approaching:
scale 1.03

drop target:
scale 1.04
```

Use subtle movement, not exaggerated bouncing.

---

# 14. DRAG ENTER ANIMATION

When the user enters with a file:

1. Capsule expands horizontally.
2. Height increases slightly.
3. Corners remain perfectly smooth.
4. Content fades/slides into visibility.
5. Background blur becomes slightly stronger.
6. A subtle glow/highlight appears along the drop area.
7. File thumbnails animate into place.

Timing target:

```text
expand:       220–320ms
content:      140–220ms
settling:     180–260ms
```

Use spring physics rather than linear animations.

A good starting point:

```swift
Animation.spring(
    response: 0.30,
    dampingFraction: 0.82,
    blendDuration: 0.05
)
```

Then tune visually.

Do not mechanically apply one global spring to every UI element.

---

# 15. ANIMATION PHILOSOPHY

The animation system should have three conceptual layers.

## Layer 1 — container

The overall tray changes:

```text
width
height
corner radius
position
opacity
scale
```

## Layer 2 — items

Individual tray items animate:

```text
position
opacity
scale
```

## Layer 3 — interaction feedback

Subtle:

```text
drop highlight
item landing
hover scale
removal
```

The container and items must not all animate identically.

This is what makes the interaction feel sophisticated rather than "SwiftUI with `.animation()` everywhere."

---

# 16. CLOSED → OPEN MORPH

This is critical.

Avoid:

```text
fade out
resize
fade in
```

Instead, make it feel like a single physical object changing shape.

Conceptually:

```text
        CLOSED

        ████████


        OPEN

     ╭────────────────────╮
     │  ◉  ◉  ◉  ◉        │
     ╰────────────────────╯
```

The same background surface remains visible throughout.

The shape changes continuously.

Use `matchedGeometryEffect` only where it genuinely helps. Do not build the entire interface around SwiftUI matched geometry if it introduces jitter in the AppKit window itself.

For the outer window/surface, window-frame interpolation may be more stable.

---

# 17. IDLE COLLAPSE

After interaction finishes:

Suggested behavior:

```text
cursor leaves
    ↓
wait 500–800ms
    ↓
collapse
```

Do not collapse immediately.

The delay gives the user enough time to move from a dropped file toward another file.

If the cursor moves from the tray toward the outside, begin collapse after a short grace period.

If cursor returns during grace period:

**cancel collapse.**

---

# 18. FILE ITEMS

Each file should appear as a compact visual tile.

For an image:

```text
┌──────────┐
│          │
│ thumbnail│
│          │
└──────────┘
```

For a document:

Use Quick Look / system-provided representations where possible.

For generic files:

- application icon
- document icon
- folder icon

The filename can optionally appear below/alongside the thumbnail when there is enough room.

Do not turn the tray into a file browser.

Keep the interface compact.

---

# 19. ITEM LAYOUT

Recommended:

```text
horizontal shelf
```

Example:

```text
╭────────────────────────────────────────────╮
│  [img] [pdf] [folder] [zip] [doc]         │
╰────────────────────────────────────────────╯
```

Do not automatically create a grid.

For large numbers of files, keep a horizontal scrolling shelf.

---

# 20. MANY ITEMS

The tray must remain visually controlled with 1, 2, 5, 10, 20+ items.

For example:

```text
[1] [2] [3] [4] [5] →
```

could become a horizontally scrollable shelf.

Never let the tray expand across the entire screen.

Set:

```text
maximumTrayWidth
```

based on screen dimensions.

Suggested starting point:

```text
max width ≈ min(720pt, screen width * 0.60)
```

Tune after testing.

---

# 21. DRAGGING ITEMS OUT

This is essential.

A user must be able to drag a file from the tray directly into:

- Finder
- Desktop
- another application accepting files
- file dialogs
- supported drop targets

The drag should be a **real macOS drag operation**, not a simulated mouse movement.

Use appropriate AppKit drag-and-drop APIs.

Architecture should separate:

```text
TrayItem
    ↓
DragSource
```

from:

```text
TrayDropTarget
```

---

# 22. DRAG-OUT ANIMATION

When the user picks up an item:

```text
item slightly scales up
item becomes visually detached
other items compress slightly
```

Then:

```text
item follows native macOS drag behavior
```

When the drag finishes successfully:

```text
item disappears from tray
remaining items shift
```

If drag is cancelled:

```text
item returns to original position
```

with a subtle spring.

The cancel animation should feel like the item "snaps back."

---

# 23. REMOVING ITEMS

Provide a way to remove an item without dragging it somewhere.

Preferred:

```text
right click / secondary click
```

menu:

```text
Remove from Tray
Reveal in Finder
Quick Look
```

Keep this context menu small.

Do not add:

```text
Rename
Compress
Convert
Share
Open With
Copy
Move
Delete
```

unless macOS itself makes one of these unavoidable.

The tray is not Finder.

---

# 24. QUICK LOOK

Implement Quick Look as a convenience interaction if stable.

For example:

```text
select tray item
press Space
```

or:

```text
double click
```

could show the native Quick Look preview.

Apple provides `QLPreviewPanel` for displaying previews of items.

However:

**do not implement a custom preview engine.**

Use native macOS functionality.

If Quick Look integration becomes unstable because the tray uses a nonactivating panel, prioritize core drag/drop behavior and omit it from v1.

---

# 25. FILE ICON / THUMBNAIL STRATEGY

Use native filesystem information.

Possible sources:

```swift
NSWorkspace.shared.icon(forFile:)
```

for icons.

For previews:

```text
QuickLookThumbnailing
```

if appropriate.

Do not ship third-party icon packs.

Do not embed huge thumbnail caches.

Thumbnail loading should be asynchronous.

Never block the main thread while generating thumbnails.

---

# 26. PERFORMANCE

The app should be essentially invisible in Activity Monitor when idle.

No:

```text
polling every 10ms
continuous timer loops
screen screenshot polling
CPU-heavy mouse tracking
```

Prefer:

- AppKit event mechanisms
- mouse tracking areas
- drag destination APIs
- notifications
- lightweight state observation

Idle target:

```text
CPU effectively ~0%
```

Memory should remain modest even with many tray items.

---

# 27. WINDOW ARCHITECTURE

Use AppKit where macOS-specific behavior matters.

Recommended architecture:

```text
SwiftUI
    ↓
UI / TrayContentView

AppKit
    ↓
TrayPanel
TrayWindowController
Drag/drop integration
screen positioning
menu bar integration
window level
Spaces/full-screen behavior
```

Do **not** attempt to implement everything purely in SwiftUI.

This is a system-level macOS utility; AppKit gives better control over:

- borderless panels
- click-through behavior
- window levels
- screen coordinates
- drag/drop
- nonactivating windows
- multi-monitor presentation

---

# 28. WINDOW TYPE

Use an `NSPanel`/`NSWindow` configured as a utility-style nonactivating panel.

Desired behavior:

- no title bar
- no standard window chrome
- transparent outside content
- no Dock icon
- no focus stealing
- does not behave like a normal application window

The user should remain in the application they were using.

Dragging a file toward the tray must **not activate the Tray app like a normal application window**.

---

# 29. WINDOW LEVEL

Choose the **lowest appropriate window level** that provides the desired utility behavior.

Do not immediately jump to:

```swift
.screenSaver
```

unless absolutely necessary.

Apple's window-level APIs distinguish between normal, floating, status, popup, and screen-saver levels.

Start conservatively and test against:

- Finder
- Safari
- Chrome
- Xcode
- full-screen Safari
- full-screen video
- Mission Control
- Stage Manager

If the tray is hidden by full-screen applications, adjust the collection behavior/window level based on actual testing.

Apple documents `.fullScreenAuxiliary` for windows intended to display alongside a full-screen window, and `.canJoinAllApplications` for utility-style windows that can join other applications/spaces.

Do not compromise normal macOS window behavior just to force the tray above everything.

---

# 30. SPACES

The tray should work correctly across:

- Desktop
- multiple Spaces
- full-screen apps
- Stage Manager

Use appropriate `NSWindow.CollectionBehavior`.

Investigate:

```swift
.canJoinAllSpaces
.canJoinAllApplications
.fullScreenAuxiliary
.transient
```

and select the minimum combination that produces the desired behavior.

Do not blindly combine every collection behavior.

---

# 31. MENU BAR APP

The application should be a menu-bar utility.

Use:

```swift
NSStatusItem
```

Menu bar menu:

```text
Tray

Open Tray

──────────────

Launch at Login      ✓

Settings…

──────────────

About Tray

Quit Tray
```

Keep this tiny.

The menu bar is primarily an access point, not the product itself.

---

# 32. MENU BAR ICON

Create a simple custom SF-symbol-like icon.

Do not use a generic "folder" icon.

Concept:

```text
small horizontal tray
```

It should be recognizable at:

```text
16px
18px
20px
```

Use template rendering where appropriate so macOS can correctly adapt the icon to light/dark menu bars.

---

# 33. SETTINGS

Only implement settings that directly support the tray.

Settings window can contain:

## General

```text
Launch at login       [toggle]
Show menu bar icon     [toggle]
```

## Tray

```text
Activation:
○ Hover
○ Drag files to top
○ Both

Auto-collapse:
[ slider ]

Show file names:
[ toggle ]
```

## Behavior

```text
Keep tray contents between launches
[ toggle ]
```

This option may be implemented later; it is not required for v1.

Do not create 30 settings.

---

# 34. LAUNCH AT LOGIN

Use Apple's modern `SMAppService` rather than legacy login-item APIs.

Implement:

```swift
LaunchAtLoginService
```

and isolate it from the rest of the application.

## What actually makes this work

`SMAppService.mainApp.register()` does **not** require an Apple Developer ID.
It requires three things, and each one is a real failure mode that must be
handled explicitly rather than assumed:

### 1. A stable location

Registration cannot survive a relaunch when the app runs from a read-only
volume (a mounted DMG) or a translocated path. Detect this and surface an
actionable error telling the user to move the app to `/Applications` — do not
let the toggle silently lie.

```swift
URL(fileURLWithPath: Bundle.main.bundlePath)
    .resourceValues(forKeys: [.volumeIsReadOnlyKey])
```

### 2. User approval

`SMAppService.mainApp.status == .requiresApproval` means the item exists but
System Settings ▸ General ▸ Login Items has it switched **off**. Registering
over it appears to succeed while doing nothing at the next login. Detect this
state specifically and tell the user where to finish the job.

### 3. A stable code signature

An ad-hoc signature changes on every build, so macOS treats each rebuild as a
different application and drops the registration. See §67 — the stable
self-signed identity exists precisely to prevent this.

## Startup repair

Run a repair pass once at launch that:

- re-registers when the system has lost an item the user asked for
- adopts an enable the user made directly in System Settings
- keeps the stored intent and the real registration from drifting apart

Store the user's *wish* separately from the system's *state*, and reconcile
them at startup.

---

# 35. ACCESSIBILITY

Support:

- VoiceOver labels
- keyboard navigation inside expanded tray
- meaningful accessibility roles
- clear item names

Example:

```text
"Tray containing 4 items"

"IMG_3029.png"

"Projects folder"
```

The aesthetic must not come at the expense of basic accessibility.

---

# 36. KEYBOARD SHORTCUT

Do not create a complicated hotkey manager.

For v1, a simple optional shortcut to open the tray is acceptable.

Example:

```text
⌥ Space
```

But do not make this mandatory.

If global hotkeys introduce unnecessary dependencies or complexity, omit it.

Mouse/drag interaction is the primary product.

---

# 37. NO DOCK ICON

The application should behave as an agent/menu-bar utility.

Set `LSUIElement` in the bundle's `Info.plist` so it does not clutter the Dock.

Test:

```text
Finder
Activity Monitor
Cmd + Tab
Dock
Menu Bar
```

The app should not feel like a foreground application.

---

# 38. DRAG/DROP TECHNICAL REQUIREMENTS

This needs special care.

Use real AppKit drag destination/source handling.

The tray should accept Finder file URLs via the pasteboard.

Support:

```text
NSPasteboard
file URL representations
```

The tray drop target should properly reject unsupported drag payloads.

When dragging a supported filesystem object, advertise an appropriate drag operation such as `NSDragOperation.copy` depending on semantics.

Dropping into the tray must **not copy the file**.

It creates a reference in the tray.

Document this distinction clearly in the code.

---

# 39. SECURITY / FILE ACCESS

**The app is NOT sandboxed.**

It ships as a directly-distributed DMG, not through the App Store, so the
sandbox buys nothing here and would add security-scoped bookmark handling to
every dropped URL for no benefit.

Consequences to respect:

- Plain `URL`s are sufficient; no security-scoped bookmark dance is required
  for v1's in-memory session storage.
- The hardened runtime is still required for notarization (§68). Add
  entitlements only where the hardened runtime genuinely blocks something the
  app needs — and for this app, it should block nothing.
- A `Tray.entitlements` file should exist and should be, ideally, empty.

Avoid requesting broad filesystem permissions unnecessarily.

Do not request or require:

- Full Disk Access
- Accessibility permission
- Screen Recording
- Microphone
- Camera
- Contacts
- Calendar

None of these should be required.

This app should not need them.

---

# 40. PERSISTENCE MODEL

Create:

```swift
TrayStore
```

with methods similar to:

```swift
add(url:)
remove(id:)
removeAll()
move(id:to:)
items()
contains(url:)
```

For v1:

```text
in-memory storage
```

is the safest/simple default.

Avoid storing copies of files.

---

# 41. MODEL

Create a model resembling:

```swift
struct TrayItem: Identifiable, Equatable {
    let id: UUID
    let url: URL

    var filename: String
    var isDirectory: Bool

    var thumbnail: NSImage?
}
```

Do not make thumbnail generation part of the model itself.

Use an asynchronous thumbnail provider:

```text
ThumbnailProvider
```

---

# 42. ARCHITECTURE

Prefer a clean modular structure.

SwiftPM layout (see §61):

```text
Sources/Tray/
├── App/
│   ├── TrayApp.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
│
├── MenuBar/
│   ├── StatusItemController.swift
│   └── StatusMenu.swift
│
├── Tray/
│   ├── TrayPanel.swift
│   ├── TrayWindowController.swift
│   ├── TrayContentView.swift
│   ├── TrayDropView.swift
│   ├── TrayItemView.swift
│   ├── TrayLayout.swift
│   └── TrayAnimations.swift
│
├── DragDrop/
│   ├── FileDropHandler.swift
│   ├── FileDragSource.swift
│   └── PasteboardFileReader.swift
│
├── Files/
│   ├── TrayItem.swift
│   ├── TrayStore.swift
│   ├── ThumbnailProvider.swift
│   └── FileMetadataProvider.swift
│
├── Screen/
│   ├── ScreenGeometryService.swift
│   └── DisplayCoordinator.swift
│
├── Services/
│   ├── LaunchAtLoginService.swift
│   └── QuickLookService.swift
│
└── Settings/
    ├── SettingsView.swift
    └── SettingsStore.swift
```

Bundle resources (icon, `Info.plist`, entitlements) live in a package-root
`Resources/` directory and are copied into the `.app` by `Scripts/build.sh`,
not vended through SwiftPM's resource pipeline.

Do not create an unnecessarily huge architecture.

The project should remain understandable by one developer.

---

# 43. STATE MACHINE

Do not let the UI become a pile of booleans.

Create a clear tray presentation state.

For example:

```swift
enum TrayPresentationState {
    case collapsed
    case expanding
    case expanded
    case dragOver
    case draggingItem(id: UUID)
    case collapsing
}
```

Or a better equivalent if you find one.

Transitions should be explicit.

Example:

```text
collapsed
    ↓
hover
    ↓
expanded
```

and:

```text
collapsed
    ↓
drag enter
    ↓
dragOver
    ↓
drop
    ↓
expanded
```

and:

```text
expanded
    ↓
drag item
    ↓
draggingItem
    ↓
successful drop
    ↓
expanded
```

This will make animation bugs significantly easier to diagnose.

---

# 44. ANIMATION CONSTANTS

Create a centralized system.

For example:

```swift
enum TrayAnimation {
    static let hoverResponse = 0.28
    static let expandResponse = 0.32
    static let collapseResponse = 0.36

    static let hoverDamping = 0.84
    static let expandDamping = 0.80
    static let collapseDamping = 0.88

    static let collapseDelay = 0.65
}
```

These numbers are starting points.

Tune them based on actual interaction rather than assuming they are perfect.

---

# 45. IMPORTANT ANIMATION RULE

Do NOT make every animation "bouncy."

Apple-like motion generally benefits from controlled physicality.

Use:

### Container

soft spring

### Item entrance

slightly more energetic spring

### Item removal

quick ease/spring

### Hover

near-imperceptible scale

### Drop

tiny impact/settle

### Collapse

slightly slower and smoother

The tray should feel **expensive**, not playful.

---

# 46. MICRO-INTERACTIONS

Include tiny details that make the product feel finished.

Examples:

### Hover on an item

```text
scale 1.00 → 1.025
```

### Dragging item

```text
scale 1.04
shadow increases subtly
```

### Drop

```text
scale 0.96
then 1.02
then 1.00
```

But keep amplitude extremely small.

### Removing an item

```text
opacity 1 → 0
scale 1 → 0.86
remaining items move into its place
```

No fireworks.

No confetti.

No excessive blur.

---

# 47. SHADOW

The tray needs a soft separation from the content underneath.

Use a shadow equivalent to roughly:

```text
radius: 20–30
opacity: low/moderate
y-offset: 4–8
```

The exact implementation should account for macOS vibrancy/material rendering.

Avoid black halos around the tray.

---

# 48. BORDER / EDGE

Consider a very subtle top/outer highlight:

```text
white ≈ 5–10% opacity
```

Only if needed.

The goal is to define the tray against bright wallpapers.

Do not create a visible "stroke."

---

# 49. LIGHT MODE

The tray should still look correct on macOS light appearance.

Do not simply invert black to white.

A dark tray can remain dark in both modes if the concept is intentionally persistent.

The preferred approach:

```text
dark neutral surface
native contrast-aware foreground
```

Test against:

- white wallpaper
- black wallpaper
- colorful wallpaper
- light mode
- dark mode

---

# 50. REDUCED MOTION

Respect:

```swift
NSWorkspace.accessibilityDisplayShouldReduceMotion
```

or the appropriate accessibility setting.

When reduced motion is enabled:

replace large springs with:

```text
short fades
small scale changes
simple frame changes
```

Never disable functionality.

---

# 51. FULL-SCREEN APPLICATION TESTS

Manually verify:

### Safari full screen

Tray still behaves correctly.

### YouTube full screen

Tray does not permanently obscure important content when idle.

### Finder

Drag files from Finder → tray.

### Desktop

Drag files from desktop → tray.

### Photoshop / Xcode

Drag accepted files into tray.

### File dialog

Drag file from tray → file dialog.

### Finder destination

Drag tray item → Finder folder.

---

# 52. EDGE CASES

Handle:

### File deleted outside the app

Tray item remains but becomes invalid.

Display:

```text
missing file
```

or remove it gracefully.

Do not crash.

### File moved outside the app

Resolve the item intelligently if macOS security/bookmark mechanisms permit.

At minimum, display that it is unavailable.

### Duplicate file

Preferred:

**prevent identical URL duplicates.**

Dragging the exact same file twice should not create multiple identical entries.

Instead keep one tray entry.

### Same filename from different locations

Allow both:

```text
~/Desktop/report.pdf
~/Documents/report.pdf
```

because they are different URLs.

---

# 53. SORTING

Do not automatically sort alphabetically.

The tray order should represent the user's interaction.

Newest file should generally appear at the end or nearest the drop location.

Pick one consistent rule.

Recommended:

**newest additions enter on the right**

The user should be able to reorder via drag within the tray if practical.

For v1, internal reorder is optional.

If implementing it:

- drag within shelf
- insertion indicator
- spring movement of neighboring items

---

# 54. ITEM METADATA

Don't display clutter.

On hover, a small tooltip/popover can show:

```text
filename
path
```

but only if useful.

Do not permanently display full paths.

---

# 55. SETTINGS WINDOW DESIGN

The settings window is not the core experience, so keep it very native.

Standard macOS settings-like layout.

Sections:

```text
General
Tray
About
```

No custom web-style dashboard.

---

# 56. APP ICON

Design a simple tray-like abstract symbol.

Do not imitate NotchNook's icon.

Requirements:

- recognizable at 16px
- works as macOS app icon
- simple silhouette
- monochrome core concept
- can have a polished macOS icon treatment

Make the icon communicate:

```text
tray / shelf / capsule
```

not:

```text
folder manager
```

---

# 57. PRODUCT COPY

Keep copy concise.

Examples:

### Empty tray

```text
Drop files here
```

### Drag active

```text
Release to stash
```

### Missing item

```text
File unavailable
```

### Menu

```text
Open Tray
Settings…
Quit Tray
```

Avoid marketing language inside the application.

---

# 58. PRIVACY

The application should be privacy-first.

It should:

- process file metadata locally
- never upload file contents
- never use analytics by default
- never inspect unrelated directories
- never read clipboard contents
- never record screen contents
- never monitor unrelated applications

The app should only know about files that the user explicitly drags into the tray.

---

# 59. NO THIRD-PARTY DEPENDENCIES UNLESS ABSOLUTELY NECESSARY

Prefer:

```text
Swift
SwiftUI
AppKit
UniformTypeIdentifiers
QuickLook
QuickLookThumbnailing
ServiceManagement
Foundation
```

Do not add React/Electron/Tauri.

This should be a **native macOS application**.

`Package.swift` should declare **zero** external package dependencies.

---

# 60. TARGET

Target:

```text
macOS 26+
```

**Raised from the original 14.6 floor.** Two reasons: the current macOS design
language and materials become available without availability fallbacks, and the
development Mac runs macOS 26.6 — so 26 is the only floor whose appearance can
actually be verified by eye rather than guessed at.

Architecture:

```text
arm64
```

**Do not produce a universal build by default.** An `x86_64` slice is close to
dead weight at a macOS 26 floor: Tahoe runs on only a handful of Intel models
and is the end of that line. Keep the `lipo` step available in `build.sh`
behind an opt-in flag, not in the default path.

---

# 61. PROJECT / BUILD SYSTEM

**Do not create an `.xcodeproj`.**

The development Mac has Command Line Tools only — no Xcode — so `xcodebuild`
is unavailable locally. A project file could be neither built nor visually
verified here, which would break the build-run-look-fix loop §84 depends on.

Use SwiftPM plus a bundle assembly script:

```text
Package.swift          → executable target "Tray", platform .macOS("26.0")
Scripts/build.sh       → compiles, then assembles Tray.app by hand
```

`Scripts/build.sh` must:

1. `swift build -c release`
2. create the bundle layout — `Tray.app/Contents/{MacOS,Resources}`
3. copy the built executable into `Contents/MacOS/`
4. copy `Resources/Info.plist` and stamp it with `PlistBuddy`
   (`CFBundleIdentifier`, `CFBundleVersion`, `CFBundleShortVersionString`,
   `CFBundleExecutable`, `LSUIElement`)
5. copy the icon and any other resources
6. `xattr -c -r` the staged bundle — extended attributes picked up from
   Downloads or File Provider invalidate a signature
7. code-sign per the ladder in §67
8. `codesign --verify --deep --strict` and fail loudly if it does not pass

Provide a `--dev` mode that stamps a distinct bundle identifier
(`com.tray.app.dev`) and display name, so a development build can coexist with
an installed release without the two fighting over the same login-item
registration.

Use Swift 6-compatible code where available.

Avoid overengineering with external project generators.

> An `.xcodeproj` may be added later if Xcode is installed. It is not the
> source of truth and must never become the only way to build.

---

# 62. GITHUB REPOSITORY

The entire project lives in GitHub.

Repository structure:

```text
/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CHANGELOG.md
├── .gitignore
├── Package.swift
├── Sources/
│   └── Tray/
├── Resources/
│   ├── Info.plist
│   ├── Tray.entitlements
│   └── Assets/
├── Scripts/
│   ├── build.sh
│   ├── setup-signing.sh
│   ├── create-dmg.sh
│   └── release.sh
├── Tests/
├── docs/
│   └── SPEC.md
└── .github/
    └── workflows/
        └── release.yml
```

---

# 63. README

Write a professional README.

Structure:

```markdown
# Tray

A tiny native macOS file shelf that lives at the top of your screen.

## Features

- Drag files into the tray
- Temporarily stash files
- Drag them back out
- Native macOS drag & drop
- Notch-aware
- Works on notchless displays
- Multi-monitor support
- Lightweight
- Native Swift / AppKit

## Requirements

macOS 26+ · Apple Silicon

## Install

Download the latest DMG from Releases.

## Build from source

    ./Scripts/build.sh

Requires the Xcode Command Line Tools. Xcode itself is not needed.

## Architecture

...

## License

...
```

Do not make claims about functionality that does not exist.

---

# 64. GITHUB RELEASES

Every tagged release should produce:

```text
Tray-x.y.z.dmg
```

Example:

```text
Tray-0.1.0.dmg
```

DMG should contain:

```text
Tray.app        → /Applications
```

with a nice standard drag-to-Applications layout.

Do not create an ugly raw disk image.

---

# 65. DMG DESIGN

The DMG should look professional.

Layout:

```text
          Tray.app        →        Applications
```

Use:

- clean background
- app icon
- Applications alias
- appropriate DMG window size
- no unnecessary files

No installer wizard.

---

# 66. AUTOMATED BUILD

Create a GitHub Actions workflow.

Flow:

```text
push tag v*
     ↓
checkout
     ↓
swift build -c release
     ↓
assemble Tray.app  (Scripts/build.sh)
     ↓
sign
     ↓
create DMG
     ↓
notarize + staple
     ↓
calculate SHA256
     ↓
GitHub Release
     ↓
attach DMG
```

Note there is no `xcodebuild archive` / `export` step — SwiftPM builds the
binary and `Scripts/build.sh` assembles the bundle, so CI runs the *same*
script a developer runs locally. That symmetry is the point: if it builds on a
laptop it builds in CI.

Use a runner image whose Xcode provides a macOS 26 SDK.

Publish checksum:

```text
SHA256SUMS.txt
```

---

# 67. CODE SIGNING

Signing has three tiers, tried in order. `Scripts/build.sh` selects
automatically; nothing about the source tree should require a paid account.

### 1. Developer ID Application

The real, Apple-issued identity used for notarized releases. Signed with the
hardened runtime (required for notarization), the app's entitlements, and a
secure timestamp.

```bash
codesign --force --strip-disallowed-xattrs --options runtime --timestamp \
    --entitlements Resources/Tray.entitlements --sign "$DEVID" Tray.app
```

### 2. A stable self-signed identity

`Scripts/setup-signing.sh` creates a code-signing certificate named
`Tray Signing` in a dedicated keychain, offline, with `openssl req -x509`, and
imports it. Free, no Apple account, idempotent.

**This tier exists for a specific reason.** An ad-hoc signature differs on
every build, so macOS treats each rebuild as a *different application* and
drops the launch-at-login registration (§34) along with any granted
permissions. A constant identity — even a self-signed one — gives every local
build the same designated requirement, so state survives rebuilding.

It does **not** replace notarization: downloaded builds still show Gatekeeper's
"unverified developer" prompt on first launch.

### 3. Ad-hoc

```bash
codesign --force --strip-disallowed-xattrs --sign - Tray.app
```

The fallback for a fresh clone with no identity at all. The app runs; the
launch-at-login toggle will be unreliable across rebuilds. Say so in the
script's output rather than letting the developer discover it.

Do not hardcode credentials. Release signing uses environment variables:

```text
APPLE_CERTIFICATE
APPLE_CERTIFICATE_PASSWORD
KEYCHAIN_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_PASSWORD
```

---

# 68. NOTARIZATION

Prepare the release pipeline for Apple notarization.

The final production flow should be:

```text
archive
→ sign
→ create DMG
→ notarize
→ staple
→ verify
```

The source repository should still allow developers without signing credentials to build locally.

---

# 69. LOCAL BUILD COMMAND

Provide a simple:

```bash
./Scripts/build.sh
```

that builds the application.

Also:

```bash
./Scripts/setup-signing.sh
```

to create the stable local signing identity (§67, tier 2), and:

```bash
./Scripts/create-dmg.sh
```

to create the local DMG.

And:

```bash
./Scripts/release.sh
```

for release preparation.

Scripts must fail loudly when prerequisites are missing.

---

# 70. TESTING

Create unit tests for:

```text
TrayStore
duplicate handling
add/remove
ordering
invalid files
display geometry
```

Run them with:

```bash
swift test
```

Create UI/manual tests for:

```text
drag into tray
drag out
multi-file drop
monitor changes
full-screen
Spaces
light/dark mode
reduced motion
```

Automated screenshot tests are optional.

---

# 71. DEBUG MODE

During development, provide a debug overlay that can be enabled through an environment flag.

Example:

```text
TRAY_DEBUG=1
```

When enabled show:

```text
screen:
safeArea:
top inset:
tray frame:
state:
drag active:
item count:
```

This must never appear in release builds.

This will make notch positioning dramatically easier to debug.

---

# 72. DEVELOPMENT PHASES

Do not try to perfect everything simultaneously.

Build in phases.

## Phase 1 — Skeleton

Get:

- menu bar app
- tray panel
- notch-aware positioning
- empty tray
- open/close state

working.

Stop and test.

## Phase 2 — Drag into tray

Implement:

- Finder drag
- desktop drag
- drag detection
- expanded drop state
- filesystem URL extraction
- tray storage

Stop and test heavily.

## Phase 3 — Tray items

Implement:

- thumbnails
- icons
- filenames
- multiple items
- horizontal layout

Stop and visually refine.

## Phase 4 — Drag out

Implement actual macOS drag source behavior.

Test with Finder and applications.

This is critical.

## Phase 5 — Animation refinement

Only once functionality works:

Tune:

- container expansion
- item entry
- collapse
- drag-over response
- removal
- hover

Do not polish animations before the geometry and drag model are reliable.

## Phase 6 — Multi-monitor / Spaces

Stress test:

- 1 display
- 2 displays
- external monitor
- monitor disconnect
- full screen
- Stage Manager
- display sleep/wake

A second external display is available for this. Verify on real hardware —
multi-monitor geometry is not something to reason about from the armchair.

## Phase 7 — Packaging

Implement:

- icon
- settings
- DMG
- GitHub Actions
- signing/notarization hooks
- README

---

# 73. VISUAL QUALITY BAR

This is extremely important.

Do not stop at:

> "Technically the drag-and-drop works."

The final app should feel polished enough that a person could mistake it for a first-party macOS utility.

Pay particular attention to:

- exact vertical alignment
- corner curvature
- spacing
- thumbnail cropping
- shadows
- animation timing
- cursor behavior
- hitbox size
- menu-bar icon quality
- display transitions
- no flickering
- no one-frame jumps
- no window activation
- no focus stealing

---

# 74. IMPORTANT INTERACTION DETAIL: CURSOR + TRAY

Avoid the common mistake where the tray expands, moves, and suddenly the pointer is technically outside the new hit region.

The hit-testing region should be thoughtfully designed.

The app may use:

```text
activation region
presentation region
content region
```

as separate concepts.

For example:

```text
activation region:
small invisible zone around top-center

presentation region:
actual visible tray

content region:
interactive thumbnails
```

Do not make the entire top 150px of the screen a giant invisible mouse trap.

That would make the application annoying.

---

# 75. IMPORTANT DRAG DETAIL

The drag activation area can be larger than the normal hover activation area.

Example:

Normal:

```text
~100–160px wide
```

Drag target:

```text
~260–360px wide
```

This makes dragging files toward the top intuitive without making ordinary mouse behavior annoying.

---

# 76. COLLAPSED STATE WHEN FILES EXIST

Do not fully disappear when files are stored.

There should always be some indication that the shelf contains items.

Example:

```text
     ╭─────────╮
     │  ● ● ●  │
     ╰─────────╯
```

or a tiny count:

```text
        [3]
```

However, avoid making it visually noisy.

The preferred behavior is a very small capsule with miniature item hints or a subtle item count.

---

# 77. EMPTY COLLAPSED STATE

When empty, the tray should be nearly invisible.

The user should still know where it is, but it should not occupy attention.

Think:

```text
       ───────
```

rather than:

```text
     ┌────────────┐
     │ DROP FILES │
     └────────────┘
```

---

# 78. CONTENT LIMIT

Do not implement:

- media player
- AirDrop
- clipboard
- URL collection
- text notes
- calendar
- reminders
- AI
- workflows
- automation
- file compression
- file conversion
- image editing
- screen recording
- webcam
- system indicators

The tray should do **one thing exceptionally well**.

---

# 79. FUTURE EXTENSIBILITY WITHOUT IMPLEMENTATION

Structure the internal code so future functionality could be added, but **do not implement any of it now**.

For example:

```text
TrayItemProvider
TrayStore
TrayPresentation
```

should not assume every future item is a filesystem object.

But v1 should support only:

```text
file URL
folder URL
```

This keeps the code clean without bloating the product.

---

# 80. FAILURE HANDLING

Never crash because of:

- invalid drag data
- file disappearing
- thumbnail failure
- disconnected display
- unsupported file
- Quick Look failure
- malformed pasteboard

Log useful diagnostics in debug builds.

Release builds should fail gracefully.

---

# 81. DON'T CHEAT ON THE CORE EXPERIENCE

Do not simulate the tray with:

- a normal application window
- an Electron webview
- a webpage positioned at the top
- a screenshot overlay
- fake drag animations

This must be a real macOS overlay and real macOS drag source/drop destination.

---

# 82. IMPLEMENTATION PRIORITY

When forced to choose:

### Priority 1

Reliable native drag/drop.

### Priority 2

Correct notch/display positioning.

### Priority 3

No focus stealing.

### Priority 4

Beautiful animation.

### Priority 5

Thumbnail polish.

### Priority 6

Settings.

### Priority 7

Packaging polish.

Never sacrifice 1–3 to make 4–7 easier.

---

# 83. ACCEPTANCE CRITERIA

The project is complete only when all of these are true.

## Basic

- [ ] App launches as a menu-bar utility.
- [ ] No Dock icon.
- [ ] Tray appears top-center.
- [ ] Works with physical notch.
- [ ] Works without notch.

## Drag in

- [ ] Finder files can be dragged into tray.
- [ ] Folders can be dragged into tray.
- [ ] Multiple files can be dropped.
- [ ] Tray visually reacts before drop.
- [ ] Dropping does not move/copy original files.

## Tray

- [ ] Items display correctly.
- [ ] Images get useful thumbnails.
- [ ] Generic files get native icons.
- [ ] Multiple items fit elegantly.
- [ ] Large collections do not explode in width.

## Drag out

- [ ] Files can be dragged to Finder.
- [ ] Files can be dragged to supported apps.
- [ ] Successful drag removes item.
- [ ] Cancelled drag returns item.

## Interaction

- [ ] Hover works.
- [ ] Drag-over works.
- [ ] Auto-collapse works.
- [ ] Return of cursor cancels collapse.
- [ ] No accidental huge hit area.

## System

- [ ] Multi-monitor works.
- [ ] Spaces work.
- [ ] Full-screen behavior is sane.
- [ ] Stage Manager doesn't break it.
- [ ] Display changes reposition it.

## Quality

- [ ] No visible frame jumps.
- [ ] No flashing.
- [ ] No focus stealing.
- [ ] No obvious animation glitches.
- [ ] Light mode works.
- [ ] Dark mode works.
- [ ] Reduced Motion works.

## Packaging

- [ ] README exists.
- [ ] `./Scripts/build.sh` produces a runnable `Tray.app` on a clean checkout.
- [ ] DMG builds.
- [ ] GitHub Actions builds releases.
- [ ] SHA256 checksum generated.
- [ ] Release version injected into app.
- [ ] Signing/notarization hooks documented.
- [ ] Launch at login survives a rebuild when a stable identity is installed.

---

# 84. FINAL DEVELOPMENT INSTRUCTION

Do not simply write the code and assume it works.

After implementation:

1. Build the application.
2. Run it.
3. Test the menu bar.
4. Test the tray on the notched built-in display.
5. Test on the external (notchless) display.
6. Drag files into it.
7. Drag files out.
8. Test multiple files.
9. Test monitor changes.
10. Test full-screen.
11. Inspect animation timing.
12. Fix visual problems.
13. Build the DMG.
14. Verify the GitHub release workflow.
15. Update README.

Whenever something looks "technically correct but visually cheap," fix it.

Do not finish with a prototype-quality UI.

The end goal is:

> **A tiny, beautiful, native Mac utility whose entire personality comes from one excellent interaction: putting files into a tray at the top of the screen and taking them back out.**

Build the smallest possible application that achieves that extremely well.

---

# 85. PRODUCT DIRECTION / DESIGN NORTH STAR

The strongest distinction from NotchNook should be **focus**. NotchNook positions itself as a broader notch utility with widgets, live activities and a files shelf; this project deliberately throws almost all of that away and makes the shelf itself the product.

The visual target should be closer to:

**"a physical black capsule embedded into the Mac's top edge"**

than:

**"a black window floating near the menu bar."**

And the animation should follow this hierarchy:

```text
REST
  │
  │ pointer approaches
  ▼
PEEK
  │
  │ hover / drag
  ▼
OPEN
  │
  │ file enters
  ▼
LAND
  │
  │ interaction ends
  ▼
OPEN
  │
  │ timeout
  ▼
REST
```

That state-machine approach is important because it prevents the common low-quality result where the entire interface simply uses generic fade/scale animations.

---

# 86. ARCHITECTURAL RECOMMENDATION

Make **AppKit the system-integration layer and SwiftUI the visual layer**.

Use AppKit for:

- borderless/nonactivating panels
- window levels
- screen coordinates
- drag/drop
- menu bar integration
- multi-monitor positioning
- Spaces/full-screen behavior

Use SwiftUI for:

- tray content
- item cards
- labels
- settings UI
- internal layout and visual state

`NSStatusItem` is the native menu-bar primitive, while `NSVisualEffectView` can provide macOS-native translucency/vibrancy where appropriate.

This hybrid architecture should give much more reliable system behavior than trying to build the entire application as a pure SwiftUI surface.

---

# 87. IMPORTANT TECHNICAL TRAP

Do not hard-code the notch's dimensions.

Derive placement from `NSScreen.safeAreaInsets` and the auxiliary top areas when available, and react to display changes.

The tray must remain robust across different MacBook generations, external monitors, scaling settings, and changing display arrangements.

---

# 88. V0.1 SCOPE LOCK

For the first release, ship exactly this:

- tray/shelf UI
- top-center positioning
- notch-aware positioning
- notchless fallback
- menu-bar icon
- drag files/folders in
- drag files/folders out
- temporary in-memory references
- native file icons/thumbnails
- multiple-item shelf
- basic remove/reveal/Quick Look context menu where stable
- multi-monitor support
- Spaces/full-screen compatibility
- polished animations
- launch-at-login setting
- arm64 build
- DMG creation
- GitHub Actions release pipeline

Everything else is explicitly **out of scope**.

Do not expand scope without a strong technical reason.
