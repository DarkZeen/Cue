# Getting a Google OAuth client for Cue

Cue ships with no OAuth client of its own. One checked into a public repository
is a client whose daily quota anybody can spend, and Google's verification
process is not something to put between someone and their own playlists — so
you make your own. It takes about five minutes and costs nothing.

What you end up with is a **client ID** and a **client secret** to paste into
Settings → Accounts. They go into your keychain, not into this repository.

---

## 1. Make a project

Open the [Google Cloud console](https://console.cloud.google.com/) and sign in
with the Google account whose YouTube library you want Cue to see. That
matters: the account you build the project with does not have to be the account
you later sign in as, but keeping them the same avoids a class of confusing
permission errors.

Use the project picker at the top of the page → **New project**. Any name will
do — `Cue` is fine. Create it, then make sure the picker is showing it before
you go on.

## 2. Enable the YouTube Data API

**APIs & Services → Library**, search for **YouTube Data API v3**, open it, and
press **Enable**.

Without this step everything else appears to work and every request comes back
403 with `accessNotConfigured`.

## 3. Configure the consent screen

This lives under **Google Auth Platform**, which is where the console moved what
used to be called the OAuth consent screen. Its sidebar reads *Overview,
Branding, Audience, Clients, Data access, Verification centre, Settings*. Older
guides — including an earlier version of this one — say **APIs & Services →
OAuth consent screen**; that is the same thing under its previous name, and a
console that still shows it that way works identically.

First time through, it runs as a **Create branding** wizard covering *App
Information → Audience → Contact Information → Finish*:

- **App name**: `Cue`. You will see this on the consent screen.
- **User support email** and **Contact information**: your own address.
- **Audience**: if you are on a Google Workspace account, choose **Internal** —
  it skips test users and verification entirely, and it skips the seven-day
  problem in step 5. Otherwise choose **External**.

Press **Create** at the end. Then two pages in that same sidebar:

- **Data access → Add or remove scopes**: filter for `youtube.readonly`, tick
  `https://www.googleapis.com/auth/youtube.readonly`, **Update**, then **Save**.
  Read-only is the narrowest scope that can list playlists and read their
  contents; anything wider would let Cue modify a library it has no business
  modifying.
- **Audience → Test users** (External only): add your own Google address. An app
  in testing will refuse to sign in an account that is not on this list.

## 4. Create the client

**Google Auth Platform → Clients → Create client.** (On a console still using
the old layout: *APIs & Services → Credentials → Create credentials → OAuth
client ID*.)

- **Application type**: **Desktop app**. This is the one that matters. Desktop
  clients are the only type allowed to use the loopback redirect Cue signs in
  with, and picking *Web application* instead means adding redirect URIs by
  hand for a port that changes on every launch.
- **Name**: anything.

Press **Create**. The panel shows a **Client ID** and a **Client secret** — copy
both. If you lose them, they are still on the client's own page, and the JSON
download has them too.

There is no redirect URI to configure. Google matches loopback redirects on host
and path and ignores the port, which is what lets Cue use whichever one the
system hands it.

## 5. Publish the app, or re-authorize every week

This is the step that is easy to skip and annoying to diagnose.

While an **External** project's publishing status is **Testing**, Google expires
its refresh tokens after **seven days**. Cue will work perfectly, and then one
morning it will say the connection expired and ask you to sign in again — and it
will do that every week forever.

Go to **Google Auth Platform → Audience**. If the publishing status reads
*Testing*, press **Publish app** to move it to *In production*. Because
`youtube.readonly` is a sensitive scope, Google will point out that the app is
not verified. Publish anyway: an unverified app still works, it just shows a
warning screen at sign-in and is capped at a hundred users. Verification exists
to remove that warning for strangers, and you are not a stranger to yourself.

**Internal** (Workspace) projects are in production from the start and never had
this problem.

## 6. Paste it into Cue

Open Cue's Settings — press ⌥Space then the gear, or run `open cue://settings`
— then **Accounts** → paste the client ID and secret → **Sign in with Google**.

Your browser opens on Google's own sign-in page — Cue never sees your password.
On an unverified app you will get a screen saying *Google hasn't verified this
app*; **Advanced → Go to Cue** is the way through, and it is expected. Grant the
read-only YouTube permission, and the tab will tell you it is done.

---

## When it goes wrong

| What you see | What it is |
|---|---|
| `accessNotConfigured` | Step 2 was skipped, or you enabled the API on a different project |
| `access_denied` immediately | External + Testing, and your account is not on the test-user list |
| "Google did not issue a refresh token" | This client has been authorized before. Remove Cue from [your account's third-party access list](https://myaccount.google.com/permissions) and sign in again |
| Signed out after about a week | Step 5 — the project is still in *Testing* |
| "daily API quota is used up" | See below |

## About the quota

A new project gets **10,000 quota units a day**, which resets at midnight
Pacific. Listing playlists costs 1 unit. **Searching costs 100** — so the budget
is roughly a hundred searches a day, and that is the reason Cue debounces the
search field rather than firing on every keystroke.

Turning on the YouTube Music session in Settings takes most searches off the
official API entirely, because the internal provider answers first and costs no
quota at all.

If you genuinely run out, the console has a quota increase request form under
**APIs & Services → YouTube Data API v3 → Quotas**. For one person's use you
will not need it.
