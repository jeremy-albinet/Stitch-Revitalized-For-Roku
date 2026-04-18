# AGENTS.md

## Project Overview

Stitch Revitalized is a Roku channel (BrightScript/SceneGraph) providing a Twitch viewing experience.
Language: BrightScript (`.brs`) and BrighterScript (`.bs`). UI layout via SceneGraph XML.

## Build, Lint & Format Commands

```bash
npm run build        # Compile with BrighterScript (no package)
npm run watch        # Build with file watching
npm run package      # Create deployable .zip in out/
npm run lint         # Run bslint
npm run lint:fix     # Run bslint with auto-fix
npm run fmt          # Format all .brs/.bs files in-place
npm run fmt:check    # Check formatting (fails on diff)
```

CI runs on PRs: `lint` → `fmt:check` → `package`. All three must pass.

```bash
npm test                                         # Run Rooibos tests on simulator (default)
ROKU_HOST=192.168.x.x ROKU_PASSWORD=pw npm test  # Run on physical TV
```

Tests live in `source/tests/` as `*.spec.bs` files. Build config: `bsconfig.test.json`.

## Project Structure
```
source/                    # BrightScript utilities and entry point
  main.brs                 # App entry point (roSGScreen bootstrap)
  constants.brs            # Global constants, design tokens, color palettes
  utils/                   # Shared utility functions
    array.brs              # Array utility functions
    config.brs             # Registry (persistent storage) accessors
    deviceCapabilities.brs # Device/codec detection (HEVC, AV1, HDR, bitrate)
    globals.brs            # Simple key-value global state
    http.brs               # HTTP request wrapper
    misc.brs               # Helper functions (isValid, formatting, etc.)
components/                # SceneGraph components (XML + BRS pairs)
  heroScene.brs/.xml       # Main scene (extends SceneManagerScene), manages auth, nav, scene stack
  SceneManager/            # Scene management framework
    SceneManager.brs/.xml  # Base scene manager
    Group/                 # SceneManagerGroup
    MessageDialog/         # SceneManagerMessageDialog
    Overhang/              # SceneManagerOverhang
    Scene/                 # SceneManagerScene (base class for heroScene)
    Screen/                # SceneManagerScreen
    Scripts/               # SceneManagerConfig, SceneManagerUtils
  Scenes/                  # Full-screen views
    Following/             # Followed streams grid (default home)
    Discover/              # Browse/discover content
    LiveChannels/          # Live channel listings
    Categories/            # Game/category browser
    Search/                # Search interface
    Settings/              # User settings screen
    ChannelPage/           # Individual channel view
    GamePage/              # Game/category detail page
    StreamerChannelPage/   # Streamer profile page
    VideoPlayer/           # Video playback scene
    LoginPage/             # OAuth device code login flow
  Modules/                 # Reusable UI components
    MenuBar/               # Top horizontal menu bar (Following, Discover, LiveChannels, Categories)
    FollowedStreamsBar/    # Left sidebar showing followed live streams (with SidebarItem)
    VideoItem/             # Stream/VOD/clip card with thumbnail, labels, badges
    Chat/                  # Twitch chat overlay (IRC-based, with ChatJob + EmoteJob)
    CirclePoster/          # Circular avatar component
    EmojiLabel/            # Label with inline emoji rendering via regex
    ChannelMenu/           # Channel action menu overlay
    StitchVideo/           # Video player wrapper
    CustomVideo/           # Custom video node extensions
    VideoErrorHandler/     # User-friendly video error messages
    GIFPlayer/             # Animated GIF decoder + player (with GIFAnimator, GIFDecoder)
    TwitchContentNode/     # Extended ContentNode for Twitch data
  Tasks/                   # Task nodes for async work (API calls, content loading)
    GetTwitchContent/      # Content-fetching task nodes
    httpRequest/           # Generic HTTP task node
    PlayerTask/            # Video player task node
    twitch-api-sdk/        # Twitch GraphQL API client (monolithic TwitchApiTask.bs)
  DeepLinking/             # External launch handling
settings/settings.json     # User-facing settings definitions
manifest                   # Roku channel metadata (v2.2.0)
images/                    # UI assets
fonts/                     # Custom fonts
locale/                    # i18n translation files
```

## Architecture Patterns

### SceneGraph Component Pattern
Every component is an XML + BRS pair. The XML declares the interface, children, and script imports:

```xml
<component name="MyComponent" extends="Group">
  <interface>
    <field id="myField" type="string" />
  </interface>
  <children>
    <!-- Child nodes -->
  </children>
  <script type="text/brightscript" uri="MyComponent.brs" />
  <script type="text/brightscript" uri="pkg:/source/utils/config.brs" />
</component>
```

Script dependencies are explicit `<script>` includes in XML — there is no module/import system.

### Task Nodes (Async)
All network I/O and expensive work runs in Task nodes. Pattern:
1. Create task: `m.task = CreateObject("roSGNode", "TwitchApiTask")`
2. Observe response: `m.task.observeField("response", "onResponse")`
3. Set function + run: `m.task.functionName = "myFunc"` then `m.task.control = "run"`

### Navigation
Uses a lightweight scene stack in heroScene (`m.footprints`) for back-navigation.
Scenes are created via `buildNode(name)` and appended/removed from the scene tree.
Top-level tab switching is handled by `MenuBar` (horizontal menu: Following, Discover, LiveChannels, Categories) via `onMenuSelection()`.
`FollowedStreamsBar` provides a left sidebar showing live followed streams for quick channel access.

### State Management
- `m.global` — read-only global node (constants, emote caches, app info)
- `m.top` — current component's interface fields
- `m.` — component-scoped variables (set in `init()`, used across subs)
- Registry (`get_setting()`, `set_setting()`, `get_user_setting()`) — persistent key-value storage

### Observer Cleanup

Every `observeField` call must have a corresponding `unobserveField` in `sub onDestroy()`. SceneGraph calls `onDestroy()` automatically when a component is removed from the scene tree. Without cleanup, observers accumulate across scene transitions and timers keep firing after their component is gone.

Rules:
- `unobserveField("fieldName")` takes **only the field name** — there is no callback parameter
- `unobserveFieldScoped("fieldName")` is the correct pair for `observeFieldScoped()`
- Always nil-check nodes before accessing them in `onDestroy()` — conditional nodes (created on-demand, not in `init()`) may never have been created
- **Timers**: stop before unobserving — `m.timer.control = "stop"` then `m.timer.unobserveField("fire")`. If you unobserve first, the timer may fire one last callback during teardown before the stop takes effect.
- **Tasks**: always use `destroyTask(m.task, "fieldName")` — never call `unobserveField` on a task manually. `destroyTask` unobserves then stops the task and returns `invalid`. The unobserve-first order is intentional: once unobserved, any in-flight response callback is suppressed regardless of when the thread actually halts. Import `taskFactory.brs` in the component's XML if not already present.

Canonical pattern:

```brightscript
sub onDestroy()
    ' Unobserve all fields observed in init()
    if m.someNode <> invalid
        m.someNode.unobserveField("fieldName")
    end if
    ' Stop timers
    if m.timer <> invalid
        m.timer.control = "stop"
        m.timer.unobserveField("fire")
    end if
    ' Destroy tasks
    m.task = destroyTask(m.task, "response")
end sub
```

Note: nodes created from XML `<children>` and accessed via `findNode()` in `init()` are always present — no nil-check needed. Nodes created conditionally (e.g., in a `showMessage()` helper) must be nil-checked.

## Code Style

### Naming
- **Components**: PascalCase — `VideoPlayer`, `ChannelPage`, `TwitchApiTask`
- **Functions/Subs**: camelCase — `handleContent()`, `onResponse()`, `buildNode()`
  - Some legacy utility functions use snake_case: `get_setting()`, `set_user_setting()`
  - Callbacks: `on` prefix — `onMenuSelection()`, `onBackPressed()`, `onEnterChannel()`
- **Variables**: camelCase — `contentCollection`, `rowItem`, `tokenValid`
- **Constants/Colors**: Nested associative arrays on `m.global.constants`
- **Fields (XML)**: camelCase — `contentSelected`, `backPressed`, `exitApp`

### Functions vs Subs
- `sub` for procedures that return nothing
- `function` for anything that returns a value
- Entry points use `sub init()` (called automatically by SceneGraph)

### Null Handling
BrightScript has no null — use `invalid`. Check before access:
```brightscript
if m.task <> invalid
    response = m.task.response
end if
```
Use optional chaining where available (BrighterScript): `rsp?.status`

### Comments
- Single-line: `' This is a comment`
- `?` is shorthand for `print` (used for debug logging throughout)
- Prefer self-documenting code; comment only for non-obvious logic

### Formatting
- Formatter: `brighterscript-formatter` with default config (`bsfmt.json` is empty)
- 4-space indentation
- No trailing whitespace
- Run `npm run fmt` before committing

### Error Handling
- Use `try/catch` for operations that may fail (API parsing, etc.)
- Always check for `invalid` before accessing nested fields
- Task nodes should set `m.top.control = "STOP"` when done
- Video errors use dedicated `VideoErrorHandler` module with user-friendly messages

## Twitch API

- All Twitch communication goes through `TwitchApiTask.bs` via GraphQL
- Client ID: `ue6666qo983tsx6so1t0vnawi233wa`
- Auth: Device code flow → OAuth token stored in registry
- Base URL: `https://gql.twitch.tv/gql` (POST, JSON body with `query` field)
- Always include `Client-Id` and `Device-ID` headers

### Auth Tiers

The app has two independent auth levels:

| Credential | Registry key | Meaning |
|---|---|---|
| `device_code` | `get_user_setting("device_code")` | Twitch-issued device identifier, obtained on first launch via `getRendezvouzToken()`. Required for all GQL requests. **Independent of login.** |
| `access_token` | `get_user_setting("access_token")` | OAuth token. Only present when the user has logged in. Enables authenticated features (following, posting to chat, etc.). |

`active_user = "$default$"` means no Twitch account is logged in — but the device still has a `device_code` and can make GQL requests. Anonymous users can browse and watch most public streams and VODs without an `access_token`.

**Never assume login is required for playback.** `TwitchGraphQLRequest` in `shared.bs` blocks when `device_code` is missing (first-launch only, very brief window) — not when `access_token` is missing.

### Query Function Contract (TwitchApiTask.bs)

There are two distinct function classes in `TwitchApiTask.bs`. **Never mix them.**

**Raw pass-through** — returns the raw GraphQL response object to the caller. The caller is responsible for deep dot-chain parsing. On failure, set `m.top.response = { "response": invalid }`. Examples: `getHomePageQuery`, `getCategoryQuery`, `getSearchQuery`, and most others.

**Boundary-layer** — parses internally, returns a flat typed struct to the caller. The caller receives clean fields with no deep access needed. On failure, set `m.top.response = invalid`. Examples: `getChannelHomeQuery`, `getFollowingPageQuery`.

Rules for boundary-layer functions:
- Failure **must** be `m.top.response = invalid` — not `{ "response": invalid }`, not empty arrays
- Callers **must** guard with `if rsp = invalid then return` at the top of their handler
- This makes "error" (`invalid`) unambiguously distinct from "valid but empty" (`{ shelves: [], ... }`)
- Do not add an `error` flag to the success shape — use `invalid` for the whole response instead

When adding a new query function, decide upfront which class it belongs to and follow the corresponding pattern exactly. Mixing patterns (e.g., boundary-layer function returning `{ "response": invalid }`) causes review churn and fragile callers.

## Git Conventions

- Conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`, `perf:`, `docs:`
- Concise subject line (imperative mood, no period)
- Never mention AI tooling in commits
- Never commit `DEV.md`
- Do not commit automatically — wait for explicit instruction

## Development Principles

- KISS — keep changes minimal and focused
- Always prefer clean new code following current Roku/BrightScript/SceneGraph best practices over preserving legacy patterns
- When prior code conflicts with modern conventions, rewrite rather than copy
- Work one feature/improvement at a time
- Bugfixes: fix minimally, never refactor while fixing
- When you spot something to improve, add it to `TODO.md` with priority

## Key Files to Know

| File | Purpose |
|---|---|
| `source/main.brs` | App entry point |
| `components/heroScene.brs` | Main scene (auth, nav, menu) |
| `components/Tasks/twitch-api-sdk/TwitchApiTask.bs` | All Twitch API calls |
| `source/utils/config.brs` | Registry read/write helpers |
| `source/utils/misc.brs` | Shared utility functions |
| `source/utils/http.brs` | HTTP request wrapper |
| `source/constants.brs` | Global constants initialization |
| `settings/settings.json` | User-facing settings schema |
| `manifest` | Roku channel metadata and version |
| `bsconfig.json` | BrighterScript compiler config (gitignored, device-specific — do not commit) |
| `bsconfig.test.json` | Test build config (extends bsconfig.json, adds rooibos plugin) |

## QA & Debugging

**Default target: local simulator (brs-desktop).** Only deploy to the physical TV when explicitly asked.

### Local Simulator (brs-desktop)

BrightScript Simulator (Electron app) running locally. Supports SceneGraph rendering, ECP, debug console, and HTTP sideloading.

- **Sideload port**: 8888 (Digest auth, `rokudev` / `rokudev`)
- **ECP port**: 8060 (no auth)
- **Debug console port**: 8085

**Limitations**: Video stream playback may not work (HLS auth/DRM). Not pixel-perfect vs real Roku hardware. Task node limit: 10 concurrent. `StandardMessageDialog` and `SimpleLabel` may render as generic nodes. See **Known brs-engine Quirks** below for additional compatibility issues and required workarounds.

#### Deploy to Simulator

```bash
# Build, package, and sideload to local simulator
npm run package && curl -s --max-time 30 --digest -u rokudev:rokudev \
  -F 'mysubmit=Install' -F 'archive=@out/Stitch-Revitalized-For-Roku.zip' \
  'http://localhost:8888/plugin_install' -o /dev/null
```

#### Screenshot Capture (Simulator)

```bash
# 1. Trigger screenshot
curl -s --max-time 10 --digest -u rokudev:rokudev \
  -X POST 'http://localhost:8888/plugin_inspect' \
  -F 'mysubmit=Screenshot' -o /dev/null

# 2. Download the screenshot
curl -s --max-time 10 --digest -u rokudev:rokudev \
  -o /tmp/roku_screenshot.png 'http://localhost:8888/pkgs/dev.png'
```

Use `mcp_look_at` to analyze the screenshot in-agent.

#### Debug Console (Simulator)

```bash
# Read current debugger output
(echo ''; sleep 1) | nc -w 3 localhost 8085 2>&1

# Send debugger commands
echo 'bt' | nc -w 3 localhost 8085 2>&1
echo 'var' | nc -w 3 localhost 8085 2>&1
echo 'cont' | nc -w 3 localhost 8085 2>&1
```

#### ECP (Simulator)

```bash
# Device info
curl -s http://localhost:8060/query/device-info

# Simulate remote key presses
curl -s -X POST http://localhost:8060/keypress/Select
curl -s -X POST http://localhost:8060/keypress/Back
curl -s -X POST http://localhost:8060/keypress/Up
curl -s -X POST http://localhost:8060/keypress/Down
curl -s -X POST http://localhost:8060/keypress/Left
curl -s -X POST http://localhost:8060/keypress/Right
```

#### Typical QA Cycle (Simulator)

1. Build + deploy: `npm run package` → sideload via curl to localhost:8888
2. Take screenshot: trigger + download + `mcp_look_at`
3. Check for crashes: `nc` to localhost:8085, read debugger output
4. Navigate: ECP keypress commands to localhost:8060
5. Repeat

#### Running Tests — Stale Package Warning

`npm test` builds a zip, sideloads it, then streams the debug console output. The simulator **keeps the previous package in memory** until the new one fully loads. This means the first 2–3 test runs printed by the console may reflect the old zip, not the freshly built one.

**Rule: always `rm -rf out` before `npm test` when you need a definitive result.** This forces a clean build and eliminates any ambiguity about which package is running.

```bash
rm -rf out && npm test
```

Rooibos loops the test suite multiple times. Treat the first run that shows the correct test names as canonical. If any run shows test names from a previous version of the spec, discard it — the simulator was still loading.

#### Rooibos Test Patterns — brs-engine Limitations

brs-engine **copies AAs on every nested field read**. This breaks the pattern of observing writes through `m.global`:

```brightscript
' BROKEN in brs-engine — write lands on a throwaway copy, task.capture stays invalid
task = { capture: invalid }
m.global = { analyticsTask: task }
trackEvent("foo")              ' writes m.global.analyticsTask.capture = { ... }
? task.capture                 ' invalid — copy-on-read discarded the write
```

**What works in Rooibos tests:**

1. **Guard-clause tests** — verify the helper doesn't crash when `analyticsTask = invalid` or when it is valid. These always pass and cover the only real branching logic in thin wrappers.

2. **Payload shape tests** — if you need to assert the shape of a payload the helper *would* write, construct the expected AA directly in the test and assert its fields. Don't call the helper for this; test the data contract, not the assignment.

3. **Avoid** testing chained writes through `m.global.analyticsTask.*` — no spy, self-referential AA, or `m.*` storage trick reliably works in brs-engine due to copy-on-read semantics.

```brightscript
' CORRECT: guard-clause test
@it("does not crash when analyticsTask is invalid")
sub trackEvent_taskInvalid()
    m.global = { analyticsTask: invalid }
    trackEvent("test_event", { key: "value" })
    m.assertTrue(true)
end sub

' CORRECT: payload shape test (no helper call needed)
@it("capture payload has correct shape")
sub trackEvent_payloadShape()
    payload = { event: "tab_visited", props: { tab: "Discover" } }
    m.assertEqual(payload.event, "tab_visited")
    m.assertEqual(payload.props.tab, "Discover")
end sub
```

#### Known brs-engine Quirks

The brs-desktop simulator uses brs-engine, which has compatibility gaps with real Roku hardware. The app includes defensive workarounds.

**App-side workarounds (in our BrightScript code):**
- **XML `alias` attributes** don't work → use `findNode()` + onChange callbacks instead (see CirclePoster)
- **`findNode()` for Timer/Animation nodes** may return `invalid` during `init()` → always nil-check before `observeField()`
- **`boundingRect()`** can throw during deep call stacks → always wrap in `try/catch`
- **`roRegex` with `\x{HHHH}` Unicode escapes** throws `Range out of order in character class` → wrap in `try/catch`, fall back to plain text
- **Engine-level errors bypass BrightScript `try/catch`** when thrown during field observer dispatch → catch at the field assignment site, not inside the observer

**Defensive coding patterns:**
```brightscript
' Safe assignment to fields with observers that may throw in brs-engine
sub safeSetField(node as object, field as string, value as dynamic)
    try
        node[field] = value
    catch e
    end try
end sub

' Safe boundingRect() access
try
    bounds = node.boundingRect()
catch e
end try

' Safe findNode() with nil-check
m.timer = m.top.findNode("timer")
if m.timer <> invalid then m.timer.observeField("fire", "callback")
```

---

### Physical TV (only when explicitly requested)

Device credentials and all TV deploy/debug/ECP commands are in `DEV.md` (gitignored).