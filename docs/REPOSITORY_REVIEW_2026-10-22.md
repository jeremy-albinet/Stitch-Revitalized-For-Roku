# Stitch repository review

Reviewed October 22, 2026, on `main` at `57f7b25a05facc12fafad381a0e44e187df0aa13`. The working tree was clean when the review began. The original review left production code, dependencies, settings and workflows unchanged. The authorized follow-up below records subsequent verification and repairs; the original findings and check results refer to that baseline.

**Follow-up status:** All seven original findings were independently confirmed and repaired, along with the recorded-chunk test timeout and both release-check gaps. Physical testing found two additional defects in Browse row metadata and Retry focus; both are repaired and independently reviewed. The local suite passed **9 offline suites and 166 Node tests**, with **309 Python tests** also passing; final validation is recorded below. Native controlled checks and watched TheBurntPeanut playback have passed their stated boundaries. Broader device acceptance and GitHub workflow execution remain open; details are in the [follow-up](#authorized-follow-up).

**Subsequent playback incident:** The user reported that the restored stream stopped. Preserved native logs confirm a failure after 3,602.015 seconds with `live_helper_failed` / `GET_status_or_range_unsupported`, despite clean resource teardown. The exact HTTP status was not retained. Recovery handling is under review; the earlier bounded successful checks do not establish sustained playback acceptance.

At the original review baseline, the app compiled, packaged and passed lint and formatting checks. The Python service passed all 309 tests. The review found reproducible navigation and account-state defects, an API failure-handling problem, and a blocking delay in a UI callback. Two additional concerns were supported by source tracing: chat ignored moderation deletions, and VOD resume depended on the order of two independent requests. The complete local `npm test` command **failed** because recorded-chunk fixtures exceeded their child deadline. See the [authorized follow-up](#authorized-follow-up) for subsequent verification, fixes and current validation.

These findings call for targeted repairs. They do not justify replacing the playback architecture or broad refactoring. No confirmed critical security defect was established by this review.

## Scope and evidence

The inventory covered 547 tracked files, including 106 production BrightScript/BrighterScript files, 46 production component XML files, 11 Python service modules, 46 Node test files, offline fixtures, GraphQL documents, settings, assets, localization, build configuration, release automation and project documentation. Generated output, installed dependency source and private developer configuration were outside the source-review scope, except where needed to run or diagnose checks.

Deep tracing focused on startup and anonymous identity, OAuth and account changes, scene retention and disposal, browse/search/channel navigation, playback selection and recovery, local live/VOD server ownership, chat transport and rendering, ad metadata, proxy validation and caching, and release/test tooling. Large binary and playlist helpers also received parser/bounds inspection and their existing regression checks. Assets received a literal package-reference check; translations received structural inspection, not a native-language or television-layout review.

Evidence labels below distinguish **reproduced** behavior from **source traced** behavior. Temporary probes used the current production handlers with controlled I/O boundaries. They did not contact Twitch, modify real account storage or deploy to a television. This is a repository-wide engineering review, not a guarantee that every reachable state or every line is defect-free.

Priority meanings: **P1** deserves attention before relying on validation or publishing affected artifacts; **P2** is a user-visible correctness or responsiveness issue to schedule for a focused fix; **P3** is lower-impact maintenance.

## Findings

### F1 Following retains direct playback state after returning from a live stream

**P2 · Reproduced · Navigation**

In [Following.brs](../components/Scenes/Following/Following.brs), `handleLiveItemSelected()` sets `m.top.playContent = true` at line 248. The non-live branch of `handleItemSelected()` at lines 237–239 publishes a new selection without clearing it. Following remains alive on the back stack, so that flag survives the return from the player.

Reproduction: sign in, select a live followed channel, return to Following, then select an offline followed channel. [heroScene.brs](../components/heroScene.brs), lines 436–449, lets `playContent` override the normal channel-page route. The offline `USER` item therefore opens VideoPlayer, where `loadHlsContent()` rejects it as unsupported content.

The actual-handler probe observed `contentSelected.contentType = "USER"` and `playContent = true` after a live selection followed by an offline selection on the same page.

**Suggested repair:** assign the playback intent for every selection, before publishing `contentSelected`. Add a retained-page regression for LIVE → Back → USER, including a second live selection afterward.

### F2 A channel that has gone live can expose an unplayable Live now card

**P2 · Reproduced · Channel playback**

In [ChannelPage.brs](../components/Scenes/ChannelPage/ChannelPage.brs), `buildContentNodeFromShelves()` at lines 108–115 reuses `m.top.contentRequested` as the Live now card whenever the fresh channel response says `isLive = true`. It does not change an incoming `USER` item into a `LIVE` item. The selection handler at lines 182–189 then requests immediate playback of that stale type.

Reproduction: select an offline channel card after the broadcaster has started streaming. The channel query correctly reports that the channel is live, but selecting Live now sends a `USER` item to playback and produces the unsupported-content error. This can happen independently of F1, including from an older Search result.

Independent verification found a second trigger: opening ChannelPage from a Search VOD result while its broadcaster is live. The same reuse puts the recording into the Live now row, so selecting it plays the old VOD instead of the live stream.

The probe supplied a `USER` request and a fresh `{ isLive: true }` response. Both the displayed live-row item and the emitted playback selection retained `contentType = "USER"`.

**Suggested repair:** construct a separate live-playback content node from the channel identity, with `contentType = "LIVE"`. Preserve the original navigation request. Test an offline-to-live transition, rather than only opening ChannelPage with an already-live item.

### F3 GraphQL operation failures become successful empty results

**P2 · Reproduced · API boundaries and recovery**

[shared.bs](../components/Tasks/twitch-api-sdk/shared.bs), `TwitchGraphQLRequest()`, accepts any successfully decoded HTTP response. Several boundary functions subsequently treat a non-`invalid` object as success and default absent data to empty arrays or offline values:

- [home.bs](../components/Tasks/twitch-api-sdk/home.bs), lines 24–46, converts a failed Following query into empty follows and shelves. The home query has the same empty-shelf behavior, although it also retains an errors array.
- [browse.bs](../components/Tasks/twitch-api-sdk/browse.bs), lines 13–18 and 34–39, converts failed live/category operations into empty results with pagination disabled.
- [channel.bs](../components/Tasks/twitch-api-sdk/channel.bs), lines 16–22, turns a missing channel result into an offline channel with no videos.
- [game.bs](../components/Tasks/twitch-api-sdk/game.bs), lines 32–54, turns a missing directory result into an empty edge list.

An errors-only GraphQL object is a valid failure response; successful HTTP decoding does not establish successful operation execution. GraphQL also permits partial data, so rejecting every response containing an error would be too broad. See the [GraphQL response documentation](https://graphql.org/learn/response/).

The probe passed `{ errors: [{ message: "synthetic GraphQL operation failed" }] }` through the compiled production query functions. Following, live Browse, ChannelPage and GamePage all returned success-shaped empty objects. Callers consequently show messages such as no followed channels or nothing to watch, rather than their error/retry state. Browse also sets the affected pagination section to exhausted.

**Suggested repair:** validate each operation's required data root before constructing its success shape. Return whole-response `invalid` when that operation failed; retain valid empty data and usable partial responses. Test errors-only, `data: null`, failed required roots, genuine empty success and partial success. Preserve anonymous playback and the existing raw-pass-through contracts.

### F4 A pending account lookup can write into the profile selected after sign-out

**P2 · Reproduced · Account state and task ownership**

In [MenuBar.brs](../components/Modules/MenuBar/MenuBar.brs), `handleUserLogin()` at lines 420–438 leaves `m.loginIconTask` observed when it switches to the anonymous icon. `handleUserLoginResponse()` at lines 402–415 neither verifies the account that initiated the request nor checks the current sign-in state. It writes the returned ID, display name and avatar using `set_user_setting()`, which resolves the active profile at callback time.

Reproduction: delay a signed-in account metadata request, sign out, then deliver the request's successful response. The old avatar replaces the anonymous icon. In production, the same callback also writes the old account's metadata into the now-active `$default$` registry section. Replacing an in-flight lookup likewise overwrites the retained task reference without destroying the preceding task.

The avatar can persist across anonymous launches because `buildIcon()` reads that stored metadata. A response arriving after switching to another signed-in profile can also write into the second profile. The repair must handle both pending responses and already-contaminated anonymous avatar metadata.

The actual MenuBar probe reproduced the avatar overwrite after switching its controlled account boundary to signed out. The cross-profile registry write follows directly from the production `set_user_setting()` implementation. This finding does not establish token disclosure or access to another account.

**Suggested repair:** destroy the prior lookup on replacement and on sign-out. Bind each lookup to its initiating profile and ignore a response if that profile is no longer active. Cover late responses after sign-out and account replacement.

### F5 Focusing a long title blocks the UI callback for 200 milliseconds

**P2 · Reproduced callback delay · Responsiveness**

[VideoItem.brs](../components/Modules/VideoItem/VideoItem.brs), lines 297–305, enables scrolling by changing the EmojiLabel's `repeatCount` when a long title gains focus. The observer calls `doScroll()` in [EmojiLabel.brs](../components/Modules/EmojiLabel/EmojiLabel.brs), lines 44–57, which executes `sleep(200)` before starting the animation.

This callback runs in the SceneGraph component, so the reading delay also delays the shared render thread. It can add a noticeable pause to navigation through long stream titles. Roku documents that the [render thread performs the application's rendering](https://developer.roku.com/dev/docs/threads).

A probe executing the unchanged `doScroll()` body with inert node boundaries measured **204 ms** for one activation. This confirms the synchronous delay; it is not a native frame-time measurement.

**Suggested repair:** use a one-shot Timer for the initial reading pause, then start the scrolling animation from its callback. Cancel the pending start on focus loss, text replacement and disposal. Preserve the existing readable pause without sleeping in the field observer.

### F6 Chat ignores message deletions and user or room purges

**P2 · Source traced · Chat correctness**

The command dispatch in [ChatJob.brs](../components/Modules/Chat/ChatJob/ChatJob.brs), lines 162–184, handles keepalive, reconnect, welcome, authentication notices and `PRIVMSG`. It drops `CLEARMSG` and `CLEARCHAT`. [Chat.brs](../components/Modules/Chat/Chat.brs), particularly lines 416–435, retains rendered groups without indexing them by Twitch message ID or sender ID. There is no corresponding removal path elsewhere in the current chat implementation.

As a result, a message already displayed remains visible until it scrolls away after a moderator deletes it, times out its author or clears the room. A message still waiting in the delay queue can also be displayed after deletion. Twitch documents these events as deletion and purge notifications in its [IRC command reference](https://dev.twitch.tv/docs/chat/irc/#clearchat-command).

**Suggested repair:** propagate these control events promptly, remove matching queued messages, and retain enough message/sender identity to remove rendered groups. Test single-message deletion, user purge and full-room clear with messages both queued and visible. Keep the anonymous transport's existing credential protections.

### F7 VOD resume reads bookmarks before their independent load has completed

**P3 after independent verification · Source traced timing defect · Recorded playback**

[VideoPlayer.xml](../components/Scenes/VideoPlayer/VideoPlayer.xml), lines 40–44, starts `bookmarksTask` independently of the content request. In [VideoPlayer.brs](../components/Scenes/VideoPlayer/VideoPlayer.brs), line 311 reads the existing `VideoBookmarks` registry value once; lines 347–353 use that snapshot to choose `PlayStart`. The player does not observe bookmark completion. [user.bs](../components/Tasks/twitch-api-sdk/user.bs), lines 52–73, writes newly fetched bookmarks only to the registry.

If content resolution finishes first, playback starts with an absent or older bookmark even when the later query successfully returns a newer resume position. The late write does not update that playback attempt. This matters on a first launch on the device and when a recording was watched farther on another device.

The same ordering also affects same-device resumes: CustomVideo saves positions remotely, and this independent fetch refreshes the local bookmark store. Content normally requires more sequential requests than bookmarks, so the defect is intermittent; Opus recommended P3.

**Suggested repair:** coordinate bookmark readiness with the initial VOD start under a finite deadline, and keep the existing explicit retry/resume position authoritative. Define a fallback for failed bookmark loading. Test both request orderings and ensure a late result cannot unexpectedly seek a video the viewer has already started watching. Native bookmark acceptance is already open in the verification record; the unsynchronized request ordering is the specific source concern identified here.

## Validation findings

### V1 The complete local test command fails in recorded chunk fixtures

**P1 for validation · Observed in this Windows environment**

`npm test` passed all nine offline fixture suites, then ran the isolated Core/recorded-chunk batch. That batch finished with **8 tests, 6 passed and 2 failed**. Both failures were `finite child deadline` assertions in [roku-vod-chunks.test.js](../tools/tests/roku-vod-chunks.test.js), line 44:

- `actual recorded chunk caller preserves every byte/time across 95 pairs and rejects unsafe whole inputs`
- `metadata, absolute timing, pair cap and aggregate-output mutations cannot pass actual assertions`

Both children exceeded approximately 40 seconds with `STITCH_VOD_CHUNKS_CASE: init-timing-defaults-and-refusals` as the last flushed case marker. That marker does not identify where execution spent its time; later markers flush at exit. Their output also contains a missing `wmic` gateway-discovery warning. Follow-up measurement below established the indexed-byte-read cost as the cause.

[run-node-tests.js](../tools/run-node-tests.js), lines 20–30, stops after this batch fails. Consequently, the ordinary command did not execute the remaining 44 Node test files. Those files were launched separately at the runner's normal maximum concurrency of two to establish their independent results.

A focused repeat of the first failing test also exceeded the child deadline at **40.4 seconds**, with the same last case marker. The separate remaining batch completed successfully: **151 tests passed, 0 failed**, across the other 44 Node test files. Across the original isolated batch and the remaining batch, **157 Node tests passed and 2 failed**. The normal `npm test` command remains a failure; the separate invocation establishes coverage of the files it skipped.

**Suggested investigation:** measure the fixture stages under the pinned `brs-node` version. Its full-buffer indexed-read cost is already acknowledged by the isolated adapter in `tools/tests/fixtures/roku-vod-large/engine.js`; check whether the ordinary-CLI golden path is affected before attributing the timeout to production conversion. Preserve complete byte/timing assertions, mutation controls, fresh markers and bounded deadlines. Do not turn a timeout into a pass by accepting incomplete output.

### Checks executed

Environment: Windows PowerShell, Node **24.22.1**, npm **11.19.1**, Python **3.12.10**, existing project virtual environment with aiohttp **3.14.4**, pytest **9.0.3** and Ruff **0.15.11**.

- `npm run lint` — passed.
- `npm run fmt:check` — passed.
- `npm run test:compile` — passed; created the Rooibos test ZIP. This compiles tests; it does not execute them on a device.
- `npm run package` — passed; created the production ZIP.
- `npm run audit` — passed the repository policy. Raw output reported **9 high, 0 critical and 0 moderate** findings. All nine high classifications were accepted through the existing exact development-tool exception; this is not a clean vulnerability graph.
- `npm test` — failed as described in V1, after all nine offline suites passed.
- Remaining Node files, invoked with `node --test --test-concurrency=2` and the original Core/chunk files excluded — **151 passed, 0 failed**. No fixtures or production bodies were changed for this run.
- Focused repeat with `node --test --test-concurrency=1 --test-name-pattern '^actual recorded chunk caller preserves' tools/tests/roku-vod-chunks.test.js` — failed at the same finite child deadline.
- Python `pytest -q` — **309 passed**.
- Python `ruff check src/ tests/` — passed.
- Python `ruff format --check src/ tests/` — passed; 22 files already formatted.
- Focused UI/account probe — **100 assertions passed**, using actual component handlers and explicit I/O boundaries; reproduced F1, F2 and F4.
- Focused query probe — four current compiled query functions returned success-shaped empty results for an errors-only GraphQL response, reproducing F3.
- Focused scrolling probe — unchanged `doScroll()` callback took 204 ms, corroborating F5.
- Literal package-reference scan — checked 386 references. The only missing literal assets found were `images/heart.png` and `images/heart-0.png` in the unused ChannelMenu module, already documented in TODO.
- Component dependencies and XML — all 208 active script references resolved; all 49 production component/localization XML documents parsed.

No production source was formatted or fixed during the review. No commit, device deployment, release, account change or real-registry write was performed. Docker smoke checks, the Python runtime dependency audit, Linux execution and physical Roku acceptance were not rerun in this session.

Local evidence is retained in the ignored `out/repository-review-2026-10-22/` directory: `test.log`, `vod-chunks-repeat.log`, `node-remaining.log`, `account-review.log`, `query-review.log`, `scroll-review.log`, the other check logs, and the synthetic probe sources/package. These files are available only in the review workspace and are not tracked release assets. The commands, results and reproduction details needed to assess the findings are included in this report; the regression fixtures included with these changes make the repaired behavior reproducible from a fresh checkout.

## Existing risks and maintenance follow-ups

These are separate from the new code findings and should retain their existing scope in [TODO.md](../TODO.md) and [DEVICE_VERIFICATION.md](DEVICE_VERIFICATION.md).

**At review baseline, release checks did not gate the exact artifact commit.** [release.yml](../.github/workflows/release.yml), originally lines 25–29, installed dependencies and packaged on a `v*` tag without running lint, the dependency policy or tests. Main CI covered pushes to main and PRs, not that tag workflow. The proxy publishing workflow had a related gap: [docker-publish.yml](../.github/workflows/docker-publish.yml), originally lines 44–47, depended only on container build/health validation, not Python tests/audit. A publish could proceed while the independent proxy CI failed; a `proxy-v*` tag did not itself trigger proxy-ci's test job. The authorized follow-up repairs both source gates; observing their GitHub execution remains open.

**The dependency exception expires November 6, 2026.** [npm-audit-policy.json](../security/npm-audit-policy.json) and [SECURITY.md](SECURITY.md) document the accepted build-tool risk and expiry. The review's audit succeeded under that policy. Keep the expiry visible and remove the exception when its compatible fix is available; do not silently extend it.

**Native playback acceptance remains bounded.** Existing records establish useful observations on one Roku, with source-transition, sustained memory, broader devices/codecs, signed-in secure chat, real ad countdowns, recorded seek/bookmarks and latency acceptance still qualified. The synthetic regression suite does not close these gates. The exact historical records should remain the authority for what has actually been watched and heard.

**Input launch is advertised without content dispatch.** `manifest` sets `supports_input_launch=1`, while Main does not dispatch launch content or subsequent input events. This is already tracked. Decide whether to implement the advertised contract or change the declaration when addressing that task.

**The unused generic HTTP task is unsafe to reuse.** [httpRequest.brs](../components/Tasks/httpRequest/httpRequest.brs), lines 17–27, calls `req.send().getString()` without checking for `invalid` and wraps it in an unbounded loop. No current production caller was found. Treat this as P3 dormant maintenance: remove it after confirming callers, or apply the shared finite request/error contract before reusing it.

**Documentation mixes historical gates with current behavior.** The modernization and verification documents intentionally retain previous checkpoints, including former default-off/consent behavior. Current playback automatically chooses eligible local splitting. Keep historical evidence, but add a short current-state summary so old instructions such as keeping source transitions off are not mistaken for current code configuration.

## What is working well

The current implementation has explicit permanent disposal, retained scene ownership, bounded recovery, and cooperative local-server cleanup. Playback metadata carries transport identity through quality changes. Actual initialization bytes receive decoder checks before local publication. These are useful invariants to preserve while making small fixes.

The Python service validates upstream hosts and actual DNS results, validates redirects, bounds fetches/cache/admission, coalesces shared work and suppresses signed URLs in its normal access logs. Its regression coverage includes malformed fragments, exact init identity, ranges and selected master playlists. No additional confirmed Python production defect emerged from this review.

The existing test infrastructure checks fresh run markers, complete output and deliberately broken implementations. The newly reproduced navigation/account cases nevertheless show that green single-action tests do not cover every retained-page or late-response sequence. Add those specific sequences rather than expanding tests that merely restate implementation details.

## Recommended order

1. Diagnose V1 and obtain a reliable full test run; preserve its failure evidence until then.
2. Repair F1 and F2 with focused navigation-sequence regressions.
3. Repair F3 and F4 at their response/ownership boundaries.
4. Replace the synchronous delay in F5, then address F6 and the VOD startup coordination in F7.
5. Gate tag and container publication on checks for the artifact commit, and complete the already documented hardware acceptance work.

The original review ended with this report and prioritized TODO entries. Subsequent verification and repairs are recorded below.

## Authorized follow-up

The user authorized independent verification with **Opus 5.5 at xhigh**, followed by repairs of valid findings. Opus confirmed F1–F7 and both release-check gaps. It broadened F2 to include replaying the wrong VOD and F4 to include persistent anonymous avatars and account-to-account metadata writes. It recommended P3 for the intermittent bookmark race. Its complete verification notes are retained only in the local workspace at `out/repository-fixes-2026-10-22/opus-verification.md`; the relevant conclusions are recorded here.

All seven code findings have targeted fixes in the working tree:

| Finding | Implemented behavior | Regression evidence |
|---|---|---|
| F1 | Following assigns playback intent before each selection | Retained LIVE → USER → LIVE sequence |
| F2 | Non-LIVE channel requests produce a separate LIVE card with channel identity and live thumbnail | USER and VOD requests, no recording ID leakage, original request preserved, existing LIVE identity retained |
| F3 | Typed queries validate their required roots and attribute nulls to GraphQL error paths | 59 compiled SDK cases, including bookmark completion; 13 error-attribution mutation cases fail as expected |
| F4 | Account lookups are cancelled on replacement/sign-out and bound to their initiating profile; anonymous icons ignore stale stored avatars | Late sign-out, replacement, account A → B, current-account success and contaminated anonymous launch |
| F5 | A cancellable one-shot Timer replaces the render-thread sleep | Delayed activation, focus loss, text replacement, already-queued timer fire and disposal |
| F6 | CLEARMSG/CLEARCHAT remove matching delayed and displayed messages; a bounded sequence window handles coalesced updates and in-flight messages | 11 transport tests including four moderation mutation controls, plus 23 renderer assertions |
| F7 | Initial signed-in VOD playback waits for bookmark completion for at most 2.5 seconds, then uses the cached position | Both response orderings, failed load, timeout, explicit resume precedence, bypasses, no late seek, content replacement, Back and disposal; 52 player assertions including existing retry cases |

F3 preserves valid empty/not-found and usable partial results, raw pass-through contracts and anonymous device identity. Browse explicitly requires shelves from the home query; sign-in can still use its account result if shelves fail. F6 preserves the anonymous transport credential restrictions and existing queue/render bounds. F7 publishes completion on success or failure, checks the initiating profile before saving bookmarks, and does not delay anonymous VODs, live streams, clips or an explicit retry position.

V1 was a load-sensitive test-tooling deadline. Opus checked passing Windows and Ubuntu CI runs at the reviewed commit. Locally, the ordinary golden child took 28–34 seconds idle and 43 seconds under contention against a 40-second deadline. `brs-node` copies the full byte buffer on every indexed read. The existing isolated byte-read adapter reduces that fixture to roughly 4–5 seconds without changing production helpers, complete bytes/timing checks, mutation controls, fresh worker markers, the 40-second deadline or the output ceiling. All four focused chunk tests pass; adapter equivalence remains covered by the existing large-fixture controls. This is offline correctness evidence, not a native playback or throughput measurement.

Channel tag releases now run audit, lint, formatting, the full tests and device-test compilation before creating their package. Proxy publication now depends on the reusable Python lint/test/audit workflow and container health validation at the same commit. All three changed workflows parse as YAML; they have not been executed or published from this working tree.

Final follow-up validation: formatting, formatting check, lint, device-test compilation, production packaging and the repository dependency-audit policy pass. The audit still uses the existing temporary development-tool exception for nine high advisories; no exception was changed. Python lint and formatting pass, with **309 tests passed**. The final complete `npm test` run passed **all 9 offline suites and 166 Node tests across 47 files**, with **0 failed, cancelled or skipped**, in **1,067.11 seconds**. Its two Node batches passed 8 and 158 tests respectively. This resolves the baseline V1 failure and exercises the formerly skipped files through the normal command. The final raw run log remains local at `out/repository-fixes-2026-10-22/native/final-test.log`; the earlier 836.88-second passing run is retained separately.

The full run includes **111 UI assertions**, **41 label/contrast assertions**, **52 retry/bookmark player assertions**, **23 moderation renderer assertions** and the compiled SDK/transport cases listed above. The temporary-directory cleanup guard received a separate passing SDK regression run after its addition. After the final native focus repair below, the ordinary 111-assertion UI regression, formatting/check, lint, test compilation and production packaging passed again.

Opus completed the independent verification and the initial API implementation. Its chat/bookmark implementation sessions then hit the provider's rate limit; the parent completed those edits and runnable regressions. A fresh Opus review of the combined fixes was attempted and also rate-limited, so no post-fix Opus approval is claimed.

The user subsequently waived further Opus use and requested reviews by the primary agent's own subagents. Three independent read-only reviews covered (1) navigation, GraphQL contracts and account ownership; (2) scroll timing and chat moderation; and (3) bookmarks, binary fixtures, release gates and documentation. They found **no code blockers**. Independent focused rechecks passed seven chat/UI tests (including 48 transport/parser assertions, 41 label/contrast assertions, 23 moderation renderer assertions and four mutation controls), the 52-assertion player regression, and all four chunk tests including their golden-byte and mutation checks. The documentation review identified local-only evidence links and obsolete review-status text; both were corrected for PR portability. Those reviews preceded the physical follow-up below; both subsequent production repairs received separate independent review.

One additional dormant maintenance issue was verified during follow-up: `getCategoriesQuery()` in [game.bs](../components/Tasks/twitch-api-sdk/game.bs) reads `data.directoriesWithTags`, while [GamesDirectory_Query.gql](../source/graphql/GamesDirectory_Query.gql) requests `games`. No current caller was found. This remains P3 in TODO alongside the unused generic HTTP task, rather than changing unused APIs during the active-path repairs.

### October 22 physical Roku follow-up

The user explicitly authorized physical testing and selected TheBurntPeanut because it had failed before modernization. The device was a G204X / 6Series-58 TV running Roku OS 15.3.4 build 2303. Credentials and raw device logs remain private and are excluded from this report.

A newly compiled Rooibos package passed **120 tests** after installation, with its unique run marker checked before accepting the result. Separate freshly marked native packages passed **59 SDK response contracts**, **41 label/scroll assertions**, **23 moderation renderer assertions**, and **52 retry/bookmark assertions**. These run real component handlers on Roku with synthetic HTTP, registry, task and chat inputs. The retry package uses an inert video boundary to control state and position. They establish native callback, observer, timer and response behavior; they do not establish real moderator delivery, account switching against Twitch or VOD decoder/resume acceptance.

The final native navigation/API/account UI package passed **112 assertions**. Its driver creates an independent VOD request, matching actual navigation, and reads focus on the render thread after it settles. The menu assertion checks the Scene's active focus path and hidden row feedback: the native RowList retains internal focus flags after its parent leaves that path. No manual focus command is inserted before the automatic Retry assertion.

**F8 — Browse appended rows can lose matching geometry on Roku (P2, repaired).** The physical UI fixture reproduced `roArray.Append` refusing to resize arrays read from SceneGraph fields. Content grew to two rows while `rowItemSize`, `showRowLabel` and `rowHeights` remained at one entry. [Browse.appendRows()](../components/Scenes/Browse/Browse.brs) now copies existing metadata into fresh arrays before appending new metadata and assigning the fields back. The native rerun showed two content rows and two entries in each metadata array. The regular app also loaded multiple real Browse shelves with correctly sized cards. A separate source review confirmed ordering, nested size pairs and initial-load behavior are preserved.

The regular production app opened TheBurntPeanut through Following. Native playback reported AVC video, AAC audio, advancing position and no player error. The user confirmed that picture and audio looked good on the TV. After **289.836 seconds**, Back returned through normal navigation and the worker reported **146 converted segment pairs**, **705 completed requests**, **zero client errors**, and an **8,130,698-byte cache peak**. All five cleanup acknowledgements were true: connection, listener and helper closed, cache references released, and aggregate cleanup successful. No external service was configured for this Roku-only playback run. These are bounded observations on one device, without a confirmed ad or encoder transition, quality-switch test or sustained-session claim.

**F9 — Retry can lose all focus when its buttons disappear (P2, repaired).** The native UI test showed that switching an actionable error/empty panel to loading cleared the Scene's focused child and left page, panel and row unfocused, still unchanged after one second. [StatusPanelHost.setPageStatus()](../components/Modules/StatusPanel/StatusPanelHost.brs) checked whether the panel owned focus only after updating its actions and state; hiding the native buttons had already cleared it. The two-line repair captures ownership before those writes and uses that value to transfer focus to content. The unchanged automatic-Retry contract then passed on Roku as part of the 112 assertions. Independent review confirmed the production helper exactly matches that passing candidate and preserves both nil guards and the restriction against stealing focus from another owner. The ordinary offline UI regression also passed all 111 assertions after the repair.

Initial native fixture failures and diagnostics are retained separately. Fresh-node navigation and active Scene focus ownership resolve the harness assumptions; the Browse and automatic-Retry failures required production repairs. Real full-app Up navigation independently moved focus from Following to MenuBar and removed the row focus underline correctly.

The final regular package, including both native-discovered repairs, was restored successfully and reopened TheBurntPeanut through Following. Thirteen samples over one minute all reported playing without error, with position advancing from 40.538 to 101.538 seconds. A final spot check still reported playing without error at 342.038 seconds. Private test and console helpers have ended; the regular app remains playing the stream. Package identities and observation boundaries are recorded in [the device verification record](DEVICE_VERIFICATION.md#october-22-repository-fixes-and-theburntpeanut).

Evidence is retained locally in `out/repository-fixes-2026-10-22/`, with physical logs and screenshots under `native/`. No commit, push, release or publication has been performed. GitHub workflow execution, Python 3.14/runtime dependency audit, Docker smoke validation and broader device/account/moderation/VOD acceptance remain open in TODO. The original review logs remain unchanged.

### October 22 remote Back and latency follow-up

The user reported that remote Back did not close menus and that low-latency playback appeared slower. Native reproduction confirmed that the player quality picker stayed visible after Back. It was an XML child dialog outside `Scene.dialog`; it now uses a runtime modal and observes `wasClosed` to restore the controls, cancel without changing quality, and release its owned dialog on disposal. A replacement modal retains ownership and focus. An additional top-navigation Back shortcut was verified on the dev Roku at this stage, then removed after the whole-Hero CI failures described in the PR 136 follow-up below.

The beta label correctly identified an active low-latency session. A controlled TheBurntPeanut comparison on the same device measured about 15.0 seconds behind Twitch's frame timestamps with the eight-second native window, 13.4 seconds with a six-second candidate, and 12.5 seconds after a fresh candidate restart. The five-minute candidate run and one-minute restart had zero worker client errors and successful cleanup. The opted-in native window now selects the newest complete six seconds, preserving the three-segment minimum, the default fourteen-second window and all source reload floors. These bounded measurements do not establish natural-ad, slower-network or fleet acceptance. The full method and native evidence are recorded in [the device verification record](DEVICE_VERIFICATION.md#october-22-menu-back-and-lower-latency-follow-up).

The focused UI checks passed 113 navigation/account assertions and 59 player-wrapper assertions, including Back, native dialog dismissal, reopening, replacement by an error modal and disposal. The actual Fetch/Core polling fixture passed 374 assertions and its six mutation controls. All 12 final player/server tests passed, including quality/recovery mutation controls and 130 server cases / 451 assertions. Session/retry/chat regressions also passed. Formatting/check, lint, production packaging and Rooibos compilation pass. Independent review found no remaining blocker in the menu or six-second-window changes. The complete 166-test run above predates this follow-up; the new behavior is verified with focused suites and native playback. The final regular package was restored and initially left playing TheBurntPeanut without an observed player error.

The earlier one-hour failure reported a rejected upstream GET without retaining its HTTP status. An eligible ready worker with successful cleanup now routes that exact failure through the existing bounded fresh-session recovery path, preserving the HTTP/range rejection. Diagnostic fields retain only bounded status, request kind/phase and the presence of a range header. The session regression covers the classification, prefix/suffix refusals, cleanup gates and callback ordering. The one-hour failure has not repeated under observation, so sustained recovery acceptance remains open in TODO.

After TheBurntPeanut went offline, the user requested a new stream. Jynxzi opened through Following on the same package, and all 13 samples over one minute reported playing without error with advancing position. Back closed its quality picker correctly. The user confirmed good picture and audio. Jynxzi uses direct multiplexed HLS, with the low-latency tag visible and Roku-reported segment latency near 9.5 seconds; this is separate from the native splitter's timestamp comparison. The device verification record contains the observation boundaries.

### PR 136 review and CI follow-up

Review identified three corrections. The six-second opt-in window still used the default native `PlayStart = 4`, which could leave only one segment ahead on devices honoring that request. It now requests zero for opted-in native LIVE playback, retaining the complete selected window; default native playback keeps four. The G204X had previously ignored `PlayStart`, so the concern is a configuration risk, not an observed two-second buffer or stall. An actual Player/Core regression combines the assigned start with minimum and longer source windows and rejects restoration of the late start. The adjusted request has not received new native acceptance.

Rejected upstream GET recovery now requires missing legacy status, integer 401/403, or 500–599. Known deterministic failures, including 200 with `Content-Range`, other statuses and malformed status values remain terminal. Exact reason, readiness, cleanup and VOD guards remain intact, and rejected response bytes remain rejected. The session matrix covers these distinctions and rejects a mutation restoring broad recovery.

The synthesized Live now card now receives current title, viewer count and category through the typed channel response, with safe optional defaults and an unchanged original USER/VOD request. The existing query fragments already selected viewers and the game's name; the query adds the broadcast title and game display name rather than duplicating viewer selection. Regression checks exercise the compiled boundary, the real card text handlers, complete metadata and fallback behavior.

Both Ubuntu and Windows CI failed the whole-Hero Back fixtures. The extra top-navigation Back branch intercepted escaped player focus before cooperative cleanup and prevented the established root exit sequence. That unrelated branch and its new fixture expectations were removed; the user had clarified that the reported menu was the player quality picker. The existing player cleanup, rail and app-exit tests are preserved, and the quality picker still uses the repaired Scene modal lifecycle.

The complete follow-up `npm test` run passed **nine offline suites and all 167 Node tests**, with zero failures, cancellations or skips, in approximately 13 minutes. This includes the original whole-Hero regressions, the actual Player/Core startup-window check and its late-start mutation, the GET classification matrix and broad-recovery mutation, **60 compiled SDK boundary cases**, and **118 UI assertions** including real live-card text handlers. Formatting/check, lint, production packaging, Rooibos compilation and the dependency-audit policy also passed. An independent read-only review found no actionable blockers. Hosted Python 3.12/3.14 validation and Docker health checks had already passed on `bc2b8fb`; those sources and workflows are unchanged by this follow-up. No device deployment was performed for these changes.
