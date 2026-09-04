# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

<!--
  Not one of Impeccable's four enumerated values. Cue is a native macOS app —
  AppKit for anything system-level, SwiftUI for drawing — and recording it as
  `web` would point every future round at the wrong design language. Apple's
  HIG applies; iOS guidance does not, because AppKit is not UIKit and a panel
  over a full-screen Mac app has no iOS equivalent.
-->

## Users

One primary user: the author, on his own Mac, with a YouTube Premium
subscription, reaching for music dozens of times a day while in the middle of
something else. The defining fact about him is that he is *always already doing
something* when he uses Cue — the app is an interruption he chose, and its whole
job is to be a short one.

A secondary audience exists but is not courted: technically capable people who
find the public repository, clone it, and build it themselves. They are expected
to read a README and own a Google Cloud project. Cue does not pursue people who
would need to be persuaded or onboarded, and design should not trade the primary
user's speed for their comprehension.

## Product Purpose

Cue closes the gap between wanting a particular piece of music and hearing it.

Without it, that gap is: leave what you are doing, find or open a browser,
find the tab or make one, wait for a heavy page, search, click, then find your
way back to the thing you were actually doing. Cue makes it a keystroke, a few
letters, and Return — with nothing appearing on screen and nothing to return
from.

Success is that the user never thinks about Cue. The measure is whether the app
is still invisible once the music is playing.

## Positioning

Other launchers find things and hand them off; other YouTube Music wrappers give
you a window to live in. Cue does neither: it finds the thing, plays it in a
window nobody ever sees, and disappears.

Four commitments hold that position together, and a neighbouring product could
not truthfully copy them all at once:

- **A global shortcut that costs no permission.** `RegisterEventHotKey` is told
  when its own combination is pressed and is shown no other keystroke, so Cue
  asks for no Accessibility or Input Monitoring access — the permissions that
  every comparable utility requests and that most users are right to resent.
- **Fixed positions, not smart ordering.** Nine slots that stay where they were
  put, reachable by ⌘1–⌘9 without looking. A grid that reorders itself by
  recency would be cleverer and would destroy the muscle memory that makes it
  fast.
- **Playback with no window.** The real YouTube Music player runs concealed, so
  Premium, the catalogue, the queue and the radio all work exactly as the
  subscription promises, while the visible product remains a panel and a plaque.
- **The user's own API credentials.** No OAuth client ships with the app, so
  there is no shared quota for strangers to exhaust and no key in a public
  repository.

## Operating Context

- Summoned by ⌥Space from inside whatever app is frontmost, including
  full-screen ones. The panel appears on the display under the pointer, takes
  the keyboard without making Cue the frontmost app in any way the user notices,
  and dismisses when it loses focus.
- Playback is handed to YouTube Music's own web player, running in a window
  concealed at one pixel in the bottom-left corner. It is never shown unless
  asked for.
- A plaque sits in the top-right corner over every app, including full-screen
  ones, while something is playing: record, previous, play/pause, next, mute.
  It is the only persistent visible surface Cue owns.
- Multi-display and Space changes are ordinary, not edge cases. The panel
  follows the pointer; the plaque re-pins when the display arrangement changes.
- The app has no Dock icon and no menu bar item. It is quit from Settings or
  with ⌘Q while frontmost.

## Capabilities and Constraints

**Two backends behind one provider protocol.** The official YouTube Data API
(OAuth, on by default) can see playlists and liked videos but not a YouTube
Music library — no liked songs as Music understands them, no history, no mixes.
The unofficial InnerTube endpoints can see all of that and are off by default
behind a feature flag. Search asks both and merges by content.

**The unofficial layer is expected to break.** Its responses are walked by leaf
renderer name rather than by path so an added wrapper changes nothing, every
field is optional, and a rejected session disconnects rather than emptying the
grid. When Google changes something for real, the feature flag turns it off and
the official path keeps working.

**No credentials ship with the app.** The user supplies a Google Cloud OAuth
client of their own; it and the refresh token live in the keychain. The Cloud
project is published in production and unverified, which is why refresh tokens
survive longer than seven days and why sign-in shows an unverified-app warning.

**Cue will not extract audio streams.** Playing through anything but YouTube's
own player would circumvent its terms, its advertising and its payments to
artists, and would break whenever Google rotates the signature ciphering. This
is a standing product decision, not an unimplemented feature.

**Technical constraints that shape everything:** Swift 6, SwiftPM, macOS 26, no
third-party dependencies, and a build that needs only the Command Line Tools —
no Xcode, no `.xcodeproj`, no package manager. Not sandboxed. No Accessibility,
Screen Recording, Input Monitoring or Full Disk Access. Development builds
require a stable local signing identity, without which the keychain treats every
rebuild as a different application.

**Explicitly undecided.** Media keys and Now Playing in Control Centre were
scoped and agreed but not built. Badging results that are not in YouTube Music's
catalogue — which redirect the player to youtube.com — was chosen but not built.
Neither is a commitment.

## Brand Commitments

- **Cue.** The name is settled. The bundle is `com.cue.app`; development builds
  are `com.cue.app.dev` with a `cue-dev://` scheme so the two never fight over a
  shortcut.
- **The icon is code**, drawn by `Scripts/make-icon.swift` rather than stored as
  a binary: a three-by-three grid of dots on a warm-dark plate, with the centre
  cell a red play triangle. It is the app's argument in one image — a speed dial
  with playback at its centre.
- **One accent colour**, the red the play triangle and the plaque's record share.
  Everything else is system material and greyscale.
- **The documentation voice is established and deliberate:** comments and prose
  explain *why*, never *what*; the reason a value is 0.65 rather than 0.3 is the
  part worth writing down. Failures and their causes are stated plainly,
  including the author's own mistakes. This voice runs through the README, the
  privacy policy, the commit history and the source, and future work should
  match it rather than reverting to neutral technical prose.
- **MIT licensed**, public at `github.com/DarkZeen/Cue`.

## Evidence on Hand

- The working application and its full source at this repository root; 76
  passing tests, most of them pinning the unofficial parser against realistic
  fixtures.
- `README.md`, `docs/PRIVACY.md` (also serving as the published privacy policy
  Google requires), `docs/GOOGLE-SETUP.md`, and `Scripts/` — build, test, icon
  and signing, all self-contained.
- A public GitHub repository with a commit history that records the reasoning
  behind each decision, including the wrong turns.

**Absences that future work must not paper over:** there are no other users yet,
no user research, no testimonials, no press, no download numbers, and no
notarized build. Cue has never been installed on a machine other than the
author's. Any surface that needs social proof does not currently have any.

## Product Principles

1. **Choosing is the product; playing is YouTube Music's job.** Cue's
   responsibility ends the moment the right thing starts. Every proposal to
   reimplement a queue, a library browser or a player is a proposal to build a
   worse version of something the embedded player already does well.
2. **Ask for no permission that can be avoided.** Where a design needs
   Accessibility, Input Monitoring or Full Disk Access, the design is wrong
   before the code is. This has already redirected the hotkey, the panel and
   playback, and it should keep doing so.
3. **Fixed positions beat clever ordering.** The value of the grid is that the
   fourth thing is still fourth tomorrow. Recency, ranking and personalisation
   are improvements that would remove the reason it is fast.
4. **The unofficial layer must be able to fail alone.** It is undocumented and
   will change without notice. It degrades, it is switchable, and it never takes
   the official path down with it.
5. **Nothing appears that was not asked for.** No window on play, no dock icon,
   no notification, no focus stolen. The plaque is the single exception, and it
   earns that by being the only thing that can say the app is doing anything.
