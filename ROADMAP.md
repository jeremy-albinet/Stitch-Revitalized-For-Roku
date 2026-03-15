# Stitch Revitalized Roadmap

This roadmap describes the path toward full parity with the official Twitch app for Android, plus additional features that go beyond what the Android app offers.

---

## ✅ Completed (v2.3 — this release)

### Bug Fixes & Audit
- Fixed wrong registry key (`auth_token` → `access_token`) for clip playback HTTP headers
- Fixed `translation` field being assigned a string `"[0, 0]"` instead of an array `[0, 0]` in scene construction
- Fixed infinite retry loop in M3U8/Usher playlist fetching (now capped at 3 attempts with 1 s delay)
- Fixed swapped `access_token` / `refresh_token` values in `getTokenFromRegistry()`
- Fixed IRC RECONNECT command being logged but never acted upon — client now reconnects when the Twitch IRC server requests it
- Added missing `FollowBarOption` setting to `settings.json` (was referenced in code but had no UI entry or default value)
- Enabled chat backend (`ChatWebOption`) by default so new users see chat working out-of-the-box
- Bumped app version to 2.3.0

---

## ✅ Completed (v2.4 — this release)

### Chat — Sending Messages
- [x] Add a text input overlay within the VideoPlayer scene (triggered by pressing the **Send** button in the control overlay while chat is open)
- [x] Send `PRIVMSG` over the existing IRC socket in `ChatJob`
- [x] Display a "Sent ✓" confirmation inline in the chat panel
- [x] Handle `NOTICE` replies from Twitch IRC (e.g. slow mode, subscriber-only mode errors)

### Chat — Quality of Life
- [x] Show a "Chat is loading…" indicator while `EmoteJob` is running
- [x] Configurable chat delay override (exposed as a setting; default 29 s)
- [x] Render `/me` action messages with the user's color applied to the whole line
- [x] Show `USERNOTICE` subscription/gift-sub/raid alert banners in the chat panel
- [x] `CLEARMSG` / `CLEARCHAT` support — cross-out deleted messages / clear on ban

### Emote Improvements
- [x] Animated WEBP/GIF emotes from 7TV (check `animated` flag, prefer `.webp`)
- [x] BTTV animated emotes (use `animated/1x.gif` endpoint when `animated: true`)
- [x] FrankerFaceZ global emote set (via BetterTTV CDN global FFZ endpoint)
- [x] Twitch channel point/reward emotes (`custom-reward-id` tag — highlights message with a reward background)
- [ ] Emote picker overlay so users can browse and insert emotes while composing a message

---

## ✅ Completed (v2.5 — this release)

### Chat — Emote Picker
- [x] Emote picker overlay so users can browse and insert emotes while composing a message
  - Press the **✸ (Options)** button while the chat compose overlay is open to launch the picker
  - Filter emotes by provider using the **All / Twitch / BTTV / FFZ / 7TV** tabs
  - Navigate the emote grid with the d-pad; press **OK** to insert the selected emote into the message
  - Press **Back** to return to the compose keyboard without inserting anything
  - Bumped app version to 2.5.0

---

## 🔜 Near-term (v2.6 — next milestone)

### Feature Parity with Twitch for Android
- [ ] **Clips** — record and submit a clip from the current stream via the `createClip` Helix API endpoint
- [ ] **Predictions** — display active prediction widgets (poll-style overlays) sourced from PubSub/EventSub
- [ ] **Channel Points** — show point balance and allow redemption of channel point rewards that do not require text input
- [ ] **Hype Train** — display the animated Hype Train progress bar during an active hype train event
- [ ] **Polls** — render active polls in an overlay and show live vote percentages
- [ ] **Squad Streams** — support the `/squad` multi-stream layout for watching up to 4 streams simultaneously
- [ ] **Raids** — detect and display incoming `USERNOTICE msgid=raid` events with a "Join Raid" prompt
- [ ] **Followed Games / Categories** — add a "My Games" tab to the categories page showing followed categories
- [ ] **VOD Chapters** — display the chapter markers scraped from VOD metadata as a seek bar overlay
- [ ] **Token Refresh** — automatically renew the OAuth token using the stored refresh token before it expires, instead of forcing re-login

### Stream Discovery
- [ ] Featured clips on the Discover page (currently only live shelf rows)
- [ ] Search autocomplete / suggestions (GraphQL `searchSuggestions` query)
- [ ] Category/game search in addition to channel search
- [ ] Followed category stream filtering on the Following page

### Playback
- [ ] Remember preferred quality per-channel (currently global only)
- [ ] Picture-in-picture (PiP) mode — Roku OS 11+ supports a `roVideoPlayer` PiP overlay
- [ ] Audio-only mode for background listening

---

## 🔭 Long-term / Stretch Goals

### Chat Plugins / Extended Emote Support
- [ ] **STV Cosmetics** — render user paint/effects from SevenTV (color gradients on usernames)
- [ ] **Pronouns** — display pronouns from the `pronouns.alejo.io` API next to usernames
- [ ] **Chatter colors** — respect Twitch name color even for anonymous viewers
- [ ] Plugin architecture — a registry of optional third-party emote/badge endpoints that users can opt in to, similar to the BetterTTV / 7TV / FFZ toggle system already in place

### Multi-Account Support
- [ ] Switch between multiple logged-in Twitch accounts without re-authenticating
- [ ] Per-account notification badges on the Following page

### Accessibility & Localisation
- [ ] High-contrast chat text option
- [ ] Locale/language override (currently uses Roku system locale for time formatting only)

### Developer / Community
- [ ] Unit tests for utility functions (`misc.brs`, `config.brs`, `array.brs`) using the [Roku unit testing framework](https://github.com/rokucommunity/rooibos)
- [ ] Integration test stubs for `GetTwitchContent` M3U8 parsing
- [ ] CI artifact upload of the sideloadable `.zip` on every push to `main`
