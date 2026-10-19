# Plan: switch the UI from 720p (`hd`) to 1080p (`fhd`)

Branch: `feat/fhd-ui` (from main `9319b57`). Status: plan only. Nothing in this
file is implemented yet.

## 1. Goal and scope

Change `manifest:19` `ui_resolutions=hd` to `ui_resolutions=fhd` and get a real
1080p app: **less zoomed than today**. More content fits on screen. Screen-wide
things fill 1920x1080; content keeps its current pixel size.

Out of scope: redesign, new layouts, token or lint systems, dedup of
`CustomVideo`/`StitchVideo`, stream-quality logic (`GetTwitchContent.brs:274`
`Val(res) >= 720` is a video resolution, not UI).

## 2. Sizing rule

There is **no global scale factor** (no x1.5, no other ratio). Each literal falls
into one of three cases:

| Case | What | Rule | Example |
|---|---|---|---|
| A. Screen-sized | backgrounds, bars, video window, overlays, row `itemSize` width, chat panel height | 1280 -> 1920, 720 -> 1080 | `MenuBar.xml:8` width `1280 -> 1920` |
| B. Anchored to right, bottom or center | chat panel x, right-aligned icons, bottom control overlay, centered spinner and message boxes | Keep the size, recompute the position against 1920x1080 | overlay `[0,580] -> [0,940]` (1080 - 140) |
| C. Content | cards, thumbnails, fonts, buttons, icons, paddings, left/top offsets | **Keep the value as it is** | `rowItemSize [[320,180]]` stays |

Result: on the FHD TV everything is 2/3 of today's size on screen and rows show
more cards. On the HD stick (720p UI) the firmware scales the whole UI by 2/3,
so it shows the same 2/3 size and density.

Rules:
- Case C is the default when in doubt. Never invent a ratio. If something looks
  broken under case C (text unreadable on the stick, overlap, cut-off), the
  stick report flags it with a screenshot. Jeremy decides the fix; no ratio rule
  gets applied without his OK.
- Chat font: pass the saved `ChatFontSize` value through unchanged
  (`VideoPlayer.brs:396` stays as is). Users already have the setting to make
  it bigger. No registry migration.
- System fonts (`font:LargeBoldSystemFont` etc., 12 uses) are picked per
  resolution by the firmware. Leave them. Fixed `fontSize=`/`size=` (43 XML
  attributes, `menuFontSize` 22/20) stay as they are (case C).
- Thumbnails: keep today's fetch sizes and `loadWidth/loadHeight` (section 5).
- Prefer values divisible by 3 for new case-B positions (clean 2/3 downscale on
  HD devices; [Roku display resolution](https://developer.roku.com/docs/developer-program/core-concepts/specifying-display-resolution.md)).

## 3. Workflow

- **Local only until the dev stick passes.** No push, no PR before the stick
  test at the end (phase 6) passes and Jeremy says go. Each phase is a local
  commit on `feat/fhd-ui` (never pushed). Rebase on main before the PR.
- **This session is the orchestrator.** It plans, dispatches, reviews diffs, and
  keeps the phase list. It does not edit code itself.
- **Every task runs in a subagent.**
  - Code changes, reviews, investigation: `model: "sonnet"` (Sonnet 5.5).
  - Build, sideload, screenshots, ECP key presses, console reads: `model:
    "haiku"` (Haiku 4.5; there is no Haiku 5). If a haiku agent fails the same
    step twice or misreads a screenshot, rerun that step with `"sonnet"`.
- Each code subagent gets: the phase section from this file, `AGENTS.md`, the
  sizing rule (section 2), and must run
  `npm run fmt && npm run fmt:check && npm run lint && npm run package` before
  it reports. It reports changed files and anything it put under "flag for
  Jeremy" instead of guessing.
- **Devices.** Dev stick (HD 3840X, 512 MB, 720p UI): the agents deploy and
  screenshot freely; credentials and commands are in `DEV.md` (main checkout,
  gitignored). FHD TV (1 GB): no deploy unless Jeremy asks. Simulator
  (brs-desktop, localhost per `AGENTS.md`) is fine for quick layout checks at
  1080p, but the stick is the source of truth.
- **Testing.** After each phase a haiku agent sideloads to the stick, walks the
  screens for that phase over ECP, takes screenshots and reads the console
  (port 8085) for crashes. The orchestrator reviews the screenshots and pings
  Jeremy only when something looks off or needs his eyes. Jeremy does **one**
  full pass at the end (phase 6).

## 4. Verified inventory (main `9319b57`)

| Area | Location | Literals |
|---|---|---|
| Manifest | `manifest:19` | `ui_resolutions=hd` |
| Constants | `source/constants.brs:5-6`, `:45-47` | `GetUIResolution()`, `/1280` |
| Player layout | `VideoPlayer.brs:439-456`, `VideoPlayer.xml:26` | 1280/720/960/320 |
| VOD/clip player | `CustomVideo.xml` (106 geometry attrs; overlay `:168-172`), `CustomVideo.brs:123-146,246-250,299,494,711-713` | |
| Live player | `StitchVideo.xml` (32 geometry attrs; overlay `:48-52`, spinner `:115`), `StitchVideo.brs:127-150,404-406,624-626` | |
| Chat | `Chat.xml:14-15,31-32,38-39`, `Chat.brs:16` | panel 1280x720 |
| Menu bar | `MenuBar.xml:8-9`, `MenuBar.brs:12,276` | width 1280 |
| Channel menu | `ChannelMenu.xml:8,16` | width 1280 |
| Dialog | `heroScene.brs:151-152` | What's New 1100 |
| Rows | `Following.xml:20`, `Browse.xml:18`, `Search.xml:33`, `GamePage.xml:30`, `ChannelPage.xml:47` | `itemSize=[1280,295]` (ChannelPage `[1980,295]`) |
| Channel page | `ChannelPage.xml:14,16`, `ChannelPage.brs:37` | 1280x720 backgrounds, banner width 1280 |
| Settings | `settings.xml:7`, `settings.brs:27-29` | background 1280x720 |
| Login | `LoginPage.xml:37-39` | QR at x 900 (right side of 1280) |

Not touched (case C): `contentBuilder.brs` row configs and its test,
`Search.brs:188-204`, `VideoItem`, `CirclePoster`, `RecentlyWatchedBar`, fonts.

`constants.screenWidth/screenHeight` have no readers on main; only
`maskScaleFactor` is read (`Chat.brs:16`, `CirclePoster.brs:22-23`). The left
sidebar on main is `RecentlyWatchedBar` (`AGENTS.md` still says
`FollowedStreamsBar`).

## 5. Phases

Global stop condition for every phase: a crash on the stick, a black or blank
screen, or video that does not fill its window. Fix before the next phase, or
`git reset --hard` to the previous phase commit.

### Phase 0: flip and constants (about 10 lines)

- `manifest:19`: `ui_resolutions=fhd`. Do not add a second `rsg_version`
  (`manifest:15` already has `rsg_version=1.3`).
- `source/constants.brs:5-6`: delete `uiResolutionWidth` and `scaleFactor`.
- `source/constants.brs:45-47`: `screenWidth: 1920`, `screenHeight: 1080`,
  `maskScaleFactor: 1.0`, plus a short comment: the design space is fixed at
  1920x1080; `GetUIResolution()` returns the physical plane (1280 on an HD
  device) and must never feed layout math.
- Keep `supportedGraphicsResolution` (`:7-16`); it is a device capability.

Why 1.0: MaskGroup `maskSize` is in the group coordinate system
([MaskGroup](https://developer.roku.com/docs/references/scenegraph/layout-group-nodes/maskgroup.md)).
Today on an FHD TV production uses 1.5 (`GetUIResolution().width` is 1920
there), so circles and the chat mask need a look on the stick.

Stick check: app boots, each tab renders (content top-left, screen not yet
filled: expected). Circle avatars round and centered.

### Phase 1: video player (about 60 lines)

- `VideoPlayer.brs:439-456`: chat hidden: video `1920x1080` at `[0,0]`. Chat
  visible: chat width stays `320` (case C), chat at `[1600,0]`, height `1080`;
  video `1600x1080`. Use `m.global.constants.screenWidth/screenHeight` and one
  local `chatWidth = 320`.
- `VideoPlayer.xml:26`: Chat `translation="[1600,0]"`.
- `StitchVideo.xml` (live) and `CustomVideo.xml` (VOD/clip):
  - Case A: overlay background rectangles and gradient mask `1280 -> 1920`
    (`StitchVideo.xml:50-52`, `CustomVideo.xml:170-172`).
  - Case B: control overlay `[0,580] -> [0,940]`; loading spinner group
    `[640,360] -> [960,540]` (`StitchVideo.xml:115`, same in CustomVideo);
    any right-aligned label (time, duration) moved against 1920.
  - Case C: buttons, icons, avatar, fonts, left offsets stay.
  - Progress bar: full width minus the same side margins as today. Today
    `1160 = 1280 - 2*60` and with chat `900`. New: `1800` (1920 - 120) and with
    chat `1480` (1600 - 120). Apply in `StitchVideo.xml:58-59`,
    `StitchVideo.brs:404-406`, `CustomVideo.brs:246-250` and the XML default.
  - Control buttons (`StitchVideo.xml:65-89`: back x 200, chat 540, play 610,
    quality 690) are laid out around the 1280 center (640). Move the group so
    it centers on 960 (+320 on x), sizes unchanged. Same in CustomVideo.
- `StitchVideo.brs:127-150,624-626` and `CustomVideo.brs:123-146,711-713`:
  message box `600x150` stays; recenter `[340,285] -> [660,465]` and siblings
  (+320 x, +180 y).
- `CustomVideo.brs:299` progress dot y and `:494` thumbnail preview y: move by
  the same +360 as the overlay (`59` is inside the overlay, so it stays; `400`
  is screen-absolute, so `400 -> 760`). Verify on the stick.
- `CustomVideo.brs:479` (BIF sprite offsets): do not change.

Stick check: live stream, VOD, clip. Chat on/off. Overlay at the bottom, bar
spans the width, buttons centered, spinner centered, quality dialog, seek with
thumbnails. Playback starts as fast as on main.

### Phase 2: chat (about 6 lines)

- `Chat.xml:31-32,38-39`: rectangles `1280x720 -> 1920x1080`. `Chat.xml:15`:
  default height `720 -> 1080`. Width default `275` (`:14`) stays; VideoPlayer
  sets 320.
- `VideoPlayer.brs:396`: no change (raw `ChatFontSize`).
- `Chat.brs:16`: no change (uses `maskScaleFactor`, now 1.0).

Stick check: chat fills the right edge top to bottom, messages wrap inside 320,
emotes/badges aligned, nothing clipped by the mask (Chat aliases `translation`
to `chatPanel.translation`, `Chat.xml:16`, so mask and panel can drift). Note
the readability of the default font 14 for Jeremy's final pass; no change
unless he asks.

### Phase 3: nav chrome and dialogs (about 15 lines)

- `MenuBar.xml:8`: `1280 -> 1920`. `MenuBar.brs:12`:
  `m.screenWidth = m.global.constants.screenWidth` (right-aligned icons at
  `:276` follow). Height 64, font 22, `[78,0]` stay.
- `ChannelMenu.xml:8,16`: `1280 -> 1920`.
- `heroScene.brs:151-152`: What's New width `1100`: keep (case C), it is a
  centered dialog; check it is centered on the stick.

Stick check: bar spans the full width, icons at the right edge, sidebar under
the bar, menu focus works, What's New centered.

### Phase 4: rows and pages (about 20 lines)

- Row `itemSize` width `1280 -> 1920` (case A): `Following.xml:20`,
  `Browse.xml:18`, `Search.xml:33`, `GamePage.xml:30`; `ChannelPage.xml:47`
  `1980 -> 1920`. Card sizes, spacing, row heights, offsets stay.
- `RowList` `numRows`: rows now fit more vertically
  (`Browse.xml`, `Search.xml`, `GamePage.xml` have `numRows="4"`): check on the
  stick that the lowest visible row is not cut; raise `numRows` only if the
  list ends short of the screen bottom.
- `ChannelPage.xml:14,16`: backgrounds `1280x720 -> 1920x1080`.
  `ChannelPage.brs:37`: banner width `m.global.constants.screenWidth`; height
  320 stays.
- Search keyboard (`Search.xml:10-26`, `Search.brs:60`): positions stay; check
  the system keyboard does not overlap results.

Memory: card textures do not grow, but about 2 to 3 times more cards are on
screen at once (section 6). Measure on the stick in this phase.

Stick check: Following, Browse, Search results, GamePage, ChannelPage: rows
reach the right edge, more cards per row, scroll fast for blank or late
thumbnails, console clean. Rooibos: `rm -rf out && npm test` (simulator).

### Phase 5: settings, login, misc (about 10 lines)

- `settings.xml:7`: background `1280x720 -> 1920x1080`. `settings.brs:27-29`
  already uses `currentDesignResolution` (1080 under fhd), so more rows fit;
  no change.
- `LoginPage.xml:37-39`: the QR sits at x 900, the right side of 1280. Move it
  to the same distance from the right edge: `900 -> 1540` (1920 - 1280 + 900).
  Size stays.
- Sweep: `grep -rnE '\b(1280|720|960|640|360)\b' components source` and check
  each hit (expected leftovers: thumbnail URL sizes, stream-quality logic).
- 9-patches (`focusindicator.9.png` 19 px, `dialog.9.png` 102 px): look on the
  stick; flag if the focus ring is too thin.

Stick check: settings (scroll to the last item), login page (QR scans with a
phone), error dialogs.

### Phase 6: final pass and PR

1. Haiku agent: clean build, sideload to the stick, screenshot every screen.
2. Jeremy: one full pass on the stick (boot, login, each tab, channel page,
   game page, search, settings, live + VOD + clip with chat, deep link). FHD TV
   only if he wants it.
3. Fix what he finds (sonnet agents), recheck on the stick.
4. On his go: rebase on main, push, open the PR. Ship as its own minor release
   (e.g. 2.7.0) so any regression maps to this change.

Total: about 120 to 150 changed lines.

## 6. Memory budget (512 MB stick)

- Texture size follows `loadWidth/loadHeight`
  ([Poster](https://developer.roku.com/docs/references/scenegraph/renderable-nodes/poster.md)).
  These do not change: cards stay 320x180 / 188x250 (`VideoItem.xml:16-19`,
  `VideoItem.brs:62-65`). Fetch sizes do not change.
- What grows: the number of cards on screen. Following today shows about 3.5
  cards x 2 rows; at 1920x1080 about 5 cards x 3 rows. At 225 KB per 320x180
  RGBA card that is roughly +2 to 4 MB.
- Unknown: whether textures load at design size or physical size on an HD
  device. Measure instead of guessing: in phase 4, run `r2d2_bitmaps` and
  `chanperf` on the stick's debug console for main vs. the branch on Following
  after scrolling 3 rows.
- Stop: blank tiles while scrolling or a texture total far above main. Then
  report to Jeremy before changing anything.
- If a runtime memory check is ever needed: `GetGeneralMemoryLevel()`, never
  `GetMemoryLimit()` (crashes on device).

## 7. Risk register

| # | Risk | Sev | Likely | Mitigation |
|---|---|---|---|---|
| 1 | Text too small on the stick at 2/3 size | Med | Med | That is the goal (less zoom). Flag specific unreadable labels with screenshots; Jeremy decides. Chat users have the font setting. |
| 2 | Video window not full screen | High | Low | Explicit 1920x1080. Roku: Video `width/height = 0` means full display ([Video](https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md)); explicit sizes kept for the chat split. |
| 3 | Mask offset or clipped (`maskScaleFactor` 1.5 -> 1.0, Chat translation alias) | Med | Med | Stick check in phases 0 and 2. |
| 4 | More cards on screen raise memory on the 512 MB stick | Med | Low | Section 6 measurement in phase 4. |
| 5 | A missed 1280/720 literal leaves a box short of the edge | Med | Med | Phase 5 grep sweep and per-phase screenshots. |
| 6 | Layouts centered on 640 look left-heavy | Low | Med | Case B recentering in phases 1 and 3; flag others from screenshots. |
| 7 | brs-desktop differs from hardware | Med | High | Stick is the source of truth. |
| 8 | `AddInterpolator` animations built in BrightScript crash on device | Med | Low | This plan adds no animations; if needed, declare them in XML. |
| 9 | Main moves during the effort | Low | Med | Rebase before the PR; the diff is small. |

## 8. Open questions

None blocking. Items the stick checks will raise go to Jeremy as screenshots.
