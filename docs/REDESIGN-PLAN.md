# Panel redesign — plan of record

Agreed with the user, not yet built. Resume here.

## Decisions already taken

| Question | Answer |
|---|---|
| Page contents | **Mixed** — page 1 pinned songs, page 2 liked songs (individual tracks), page 3 albums as containers |
| Tile text | **Song title only.** Artwork fills the tile, one line over a gradient scrim. Artist lives in the tooltip and the plaque |
| Randomize | **Reshuffles which tiles are shown** — redeals nine from a larger pool. It browses, it does not play |
| The spinning disc | **Replaced by the new logo mark**, small, dimming or pulsing rather than spinning |
| Both designs | **Toggleable in Settings.** The old grid stays selectable |
| Aesthetic | Closer to YouTube Music: near-black grounds, artwork-forward, one red accent, minimal chrome |

Mode is **Operate**: the panel is a tool for completing a task, so scanability
and native expectations outrank expression. Brand lives in the details.

## Done

- **The logo.** A cue point — a white playhead marker and a red play triangle
  starting from it. `Scripts/make-icon.swift` draws it; the icon is code, per
  the brand commitment in PRODUCT.md.
  - The first draft put a red bar of similar weight beside the triangle and
    read as the universal "skip forward" glyph. The marker is now deliberately
    unlike the triangle in every available way — thinner, taller, and white.
  - **Open:** at 16px the marker thins almost to nothing. It needs a minimum
    stroke weight at the small rungs, which means drawing those sizes with
    their own proportions rather than scaling the 1024 canvas down.

## Not yet built

1. **Library layer.** Neither backend can currently fetch the *contents* of a
   playlist, which pages 2 and 3 need.
   - Data API: `playlistItems.list` for the liked playlist. It has no album
     concept, so page 3 is InnerTube-only there.
   - InnerTube: `browse` with `VL` + playlist id for tracks;
     `FEmusic_liked_albums` for saved albums.
   - `MusicLibraryProvider` gains `tracks(inPlaylist:)` and `albums()`;
     `LibraryCoordinator` exposes `likedSongs` and `albums`.
2. **The paged grid.** Three pages, page dots, ← → to move between them,
   artwork tiles with a title scrim, a randomize control with a shortcut.
   ⌘1–⌘9 must keep addressing the *visible* page, or the muscle memory that
   justifies the grid is lost.
3. **The plaque mark.** Swap the drawn record for the logo; dim or pulse with
   playback state instead of spinning.
4. **The Settings toggle** between the two panel designs.

## Constraints this must not break

From PRODUCT.md, and each already paid for once:

- Fixed positions beat clever ordering. Randomize redeals *pages 2 and 3*;
  page 1 is pinned and must stay exactly where the user put it.
- Nothing appears that was not asked for.
- The unofficial layer must be able to fail alone — pages that depend on it
  degrade to an empty state with a reason, never a broken panel.
