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