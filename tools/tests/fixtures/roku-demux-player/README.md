This package executes the tracked `VideoPlayer.brs` and `RokuPlayback.brs`
unchanged, with the tracked SceneGraph XML plus inspection exports. Actual
production wrappers, content node, chat UI and error handlers are copied into
a fresh temporary package. The engine's keyboard focus dispatch chooses the
real dialogs. The added probe only reads state or calls existing handlers.

The `SessionBoundary` is an explicit IO boundary, not a manager implementation.
It records start descriptors, IDs and attach-time wrapper state. Only the
fixture supplies ready/failed events and the cleanup acknowledgment (`busy =
false`). It cannot prove task ownership, socket/file cleanup or physical
playback. Content/bookmark/chat/history tasks and persistent registry are inert
boundaries. Fixtures use reserved `.invalid` URLs and make no upstream requests.

brs-node 2.6.0 reports type mismatches assigning native ContentNode `Streams`
and `StreamQualities`. The test admits only the exact error lines for those two
fields; every other engine error still fails. Their array storage and decoder
behavior are not claimed. Actual local URL, supported `StreamUrls`, retained
descriptor/quality, proxy flags, wrapper state and attach-before-play order are
asserted without changing production code. brs-node also treats `getScene()`
on a detached node as the current scene, so late binding is checked by creating
the actual player while the host owner is absent, then providing the owner and
attaching before its real content-request callback.

Run `node --test tools/tests/roku-demux-player.test.js`. Each run uses a fresh
UUID marker, a finite child timeout and output cap. Production snapshot hashes
must remain identical through the run. Temp cleanup checks the absolute parent
and fixture prefix. A genuine BrightScript assertion failure (despite exit 0),
stale package marker, failure output, timeout, output overflow and nonzero exit
are rejected by executable controls. Assertion counts are reported, not pinned.
