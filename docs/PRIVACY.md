# Cue — Privacy Policy

*Last updated: 4 September 2026*

Cue is a macOS application that opens a search panel over whatever you are
doing and hands what you pick to YouTube Music. It runs entirely on your own
Mac.

## The short version

Cue has no server. There is no account to create, no analytics, no crash
reporting, and no telemetry of any kind. Nothing you type, play, or pin is sent
anywhere except to Google, and only in order to answer the request you just
made.

## What Cue stores, and where

Everything Cue keeps is on your Mac.

| What | Where | Why |
|---|---|---|
| Your Google OAuth refresh token | macOS keychain | So you do not sign in every hour |
| Your Google OAuth client ID and secret | macOS keychain | You supply these; they identify your own API project |
| Your YouTube Music session cookie, if you enable that feature | macOS keychain | The only way to read a YouTube Music library |
| Pinned tiles — titles, subtitles, artwork addresses | Application preferences (`UserDefaults`) | So the grid draws instantly and works offline |
| Your preferences | Application preferences (`UserDefaults`) | Switches you set in Settings |
| The player's browsing session | WebKit's website data store, private to Cue | So the player stays signed in between launches |

Removing Cue and its preferences removes all of it. Settings → Accounts →
Disconnect removes the credentials immediately and asks Google to revoke the
token as well.

## What Cue sends, and to whom

Cue talks to Google's own hosts and to nobody else:

- `accounts.google.com` and `oauth2.googleapis.com` — signing in, refreshing and
  revoking your token.
- `www.googleapis.com` — the YouTube Data API: your search terms, and requests
  for your own playlists.
- `music.youtube.com` — only if you enable the YouTube Music library feature:
  the same searches, and requests for your library, history and home feed.
- Google's image hosts — fetching the artwork shown on tiles and rows.

When you play something, Cue's player window loads music.youtube.com in a web
view, exactly as a browser would. From that point the page is talking to Google
on its own account, as YouTube Music always does — Cue does not intercept,
modify, filter or record what passes between them, and it does not inject
anything into the page beyond a small script that reads the standard Media
Session metadata so Cue can show what is playing.

There is no other network destination in the application. There is no Cue
server to send anything to.

## Signing in

Sign-in happens in your own browser, on Google's own pages, against a local
loopback address. Cue never sees your Google password. The optional YouTube
Music feature signs in inside a web view whose data store is discarded when the
window closes; what Cue keeps afterwards is the session cookie, in the keychain.

## What Cue asks permission for

One scope: `https://www.googleapis.com/auth/youtube.readonly`. Read-only. Cue
cannot modify, delete, or add anything to your YouTube account, and does not
try.

You can revoke Cue's access at any time from
[your Google account's third-party access page](https://myaccount.google.com/permissions),
independently of anything Cue does.

## macOS permissions

None. Cue requests no Accessibility, Screen Recording, Full Disk Access,
Input Monitoring, camera, microphone, location, or contacts access.

Its global keyboard shortcut is a *registered hotkey*, not an event tap. Cue
asks the window server to be told when one specific combination is pressed, and
that is the only keystroke it is ever shown. It cannot see, and does not
receive, anything else you type — in Cue or in any other application. This is
why no permission is requested for it, and it is the reason that API was chosen
over the ones that would have needed one.

## Logging

Cue writes to the standard macOS unified log for diagnostics. It does not log
search queries, titles, or any part of a credential. A debug build can be asked
to log network activity with an environment variable, which is a developer
switch and is compiled out of released builds entirely.

## Children

Cue is not directed at children and collects nothing from anyone.

## Changes

Changes to this policy are made in the repository's history, which is public.

## Contact

Open an issue on the project's repository.
