' Actual Core/Bulk/Fetch/gate functions execute; decoder and transfer IO are boundaries.
sub mrCheck(ok as boolean, detail as string)
    if not ok then throw "map-fixture: " + detail
    m.assertions += 1
end sub

sub mrCase(name as string)
    m.cases += 1
    print "STITCH_ROKU_MAP_CASE: " + name
end sub

function mrBytes(hex as string) as object
    data = CreateObject("roByteArray")
    data.FromHexString(hex)
    return data
end function

function isTwitchVariantSupported(variant as object, device = invalid as dynamic) as boolean
    m.decoderCalls += 1
    if m.stopDuringDecode then m.top.stopRequested = true
    return m.decoderAllowed
end function

function twitchVariantVideoFormat(variant as object) as string
    return "h264"
end function

sub nlStart(state as object, intent as object, phase as string, port as object, nowMs as dynamic)
    throw "map-fixture: unexpected network start"
end sub

function mrCancel() as boolean
    m.calls[0] += 1
    return m.succeeds
end function

function mrPlaylist(first as integer, map = "init.mp4" as string, epoch = 0 as integer, mixed = false as boolean, changed = false as boolean) as string
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:2" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:" + first.ToStr() + Chr(10)
    text += "#EXT-X-DISCONTINUITY-SEQUENCE:" + epoch.ToStr() + Chr(10) + "#EXT-X-MAP:URI=" + Chr(34) + map + Chr(34) + Chr(10)
    for offset = 0 to 2
        sequence = first + offset
        if mixed and offset = 1 then text += "#EXT-X-MAP:URI=" + Chr(34) + "mixed.mp4" + Chr(34) + Chr(10)
        text += "#EXTINF:2.000000," + Chr(10) + "segment-" + sequence.ToStr() + ".m4s"
        if changed and offset = 0 then text += "?new=1"
        text += Chr(10)
    end for
    return text
end function

sub mrGolden(data as object, expected as object, label as string)
    mrCheck(data.Count() = expected.count and nlBodyDigest(data) = expected.sha256 and LCase(data.ToHexString()) = expected.hex, label + " exact Python golden")
end sub

sub mrPair(state as object, sequence as integer, nowMs as longinteger)
    item = m.corpus.media[sequence - 10]
    input = mrBytes(item.input.hex)
    mrCheck(rokuDemuxFeedInput(state, "segment", input, nowMs), "normal fragment feed allowed")
    nativeLiveAdvance(state, nowMs)
    nativeLiveAdvance(state, nowMs)
    saved = state.segments[nlSegmentIndex(state, sequence)]
    for each pair in [[saved.videoId, item.video], [saved.audioId, item.audio]]
        acquired = nativeLiveAcquire(state, pair[0])
        mrGolden(acquired.data, pair[1], "continued fragment")
        nativeLiveRelease(state, pair[0])
    end for
    mrCheck(nlBodyDigest(input) = item.input.sha256 and state.input = invalid and state.temporaryVideo = invalid, "media input immutable and released")
end sub

function mrPrepared() as object
    m.top = { "stopRequested": false }
    m.config = { "metadata": m.corpus.init.metadata, "sourceDelaySeconds": 0 }
    m.result = { "actualInitValidated": false, "decoderApproved": false }
    m.decoderCalls = 0
    m.decoderAllowed = true
    m.stopDuringDecode = false
    state = nativeLiveCreate("https://cdn.example.invalid/live.m3u8?fixtureSigned=initial", 0&, 0, invalid, true, 16777216&, { "mode": "steady", "sessionId": "0123456789abcdef0123456789abcdef" })
    mrCheck(rokuDemuxFeedInput(state, "playlist", mrPlaylist(10), 0&), "initial playlist fed")
    mrCheck(rokuDemuxFeedInput(state, "init", mrBytes(m.corpus.init.input.hex), 0&), "actual initial inspector and gate fed")
    nativeLiveAdvance(state, 0&)
    nativeLiveAdvance(state, 0&)
    mrCheck(state.initByteCount = m.corpus.init.input.count and state.initDigest = m.corpus.init.input.sha256 and state.input = invalid, "original native digest and size retained without raw input")
    mrCheck(m.decoderCalls = 1 and m.result.actualInitValidated and m.result.decoderApproved and state.initPairCount = 1, "initial actual inspector and decoder gate preceded publication")
    for sequence = 10 to 12
        mrPair(state, sequence, 0&)
    end for
    return state
end function

sub mrClose(state as object)
    advertised = []
    for each generation in state.generations
        if generation.advertised then advertised.Push(generation.id)
    end for
    for each id in advertised
        nativeLiveRetire(state, id)
    end for
    mrCheck(nativeLiveClose(state), "actual retired/unleased helper closes")
    mrCheck(state.pendingWindow = invalid and state.pendingPlaylistSequence = -1& and state.initDigest = "" and state.initByteCount = 0, "pending map and init identity released")
    mrCheck(Type(state.initAliasCount, 3) = "LongInteger" and state.initAliasCount >= 0&, "successful alias count retained after close")
    mrCheck(state.cacheBytes = 0 and state.assets.Count() = 0 and state.input = invalid and state.closed, "cache and scratch cleared")
end sub

sub mrPending(state as object, map = "init-rotated.mp4?fixtureAlias=one%2Btwo&v=2" as string)
    previous = nativeLivePublication(state)
    previousManifest = loopbackManifest("video", previous)
    window = FormatJson(state.window)
    initIds = FormatJson(state.initIds)
    tracks = FormatJson(state.tracks)
    assets = state.assets.Count()
    cache = state.cacheBytes
    mrCheck(rokuDemuxFeedInput(state, "playlist", mrPlaylist(11, map), 2000&), "same-epoch rotated playlist enters pending init")
    mrCheck(state.phase = "init-rotation" and state.pendingWindow <> invalid and state.mapUrl = "https://cdn.example.invalid/init.mp4", "original map retained pending binary proof")
    diagnostics = nativeLiveDiagnostics(state)
    mrCheck(diagnostics.Count() = 15 and loopbackSafeDiagnostics(diagnostics, state.cacheBudgetBytes, true) <> invalid, "actual strict protocol accepts pending phase without widening diagnostics")
    mrCheck(FormatJson(state.window) = window and state.lastPlaylistSequence = 10& and state.playlistCount = 1, "original window and accepted sequence retained")
    mrCheck(FormatJson(nativeLivePublication(state)) = FormatJson(previous), "pending init never advertises a changed publication")
    pendingManifest = loopbackManifest("video", nativeLivePublication(state))
    mrCheck(pendingManifest <> invalid and pendingManifest.Count() = previousManifest.Count() and nlBodyDigest(pendingManifest) = nlBodyDigest(previousManifest), "actual old advertised media manifest remains byte-exact and serveable pending proof")
    mrCheck(FormatJson(state.initIds) = initIds and FormatJson(state.tracks) = tracks and state.assets.Count() = assets and state.cacheBytes = cache, "pending init retains original tracks/assets/cache")
    intent = nlIntent(state, 2000&)
    mrCheck(intent.kind = "init" and intent.url = "https://cdn.example.invalid/" + map and intent.limit = 2097152, "candidate uses exact approved URI/query and original finite body cap")
    nativeLiveAdvance(state, 2000&)
    mrCheck(state.phase = "init-rotation" and state.segmentPairCount = 3 and state.input = invalid, "pending candidate blocks media conversion")
end sub

sub mrEquivalent()
    state = mrPrepared()
    old = nativeLivePublication(state)
    held = nativeLiveAcquire(state, old.segments[0].videoId)
    mrPending(state)
    initIds = FormatJson(state.initIds)
    tracks = FormatJson(state.tracks)
    serial = state.serial
    cache = state.cacheBytes
    mrCheck(rokuDemuxFeedInput(state, "init", mrBytes(m.corpus.init.input.hex), 2100&), "equivalent init passes real gate and core acceptance")
    mrCheck(m.decoderCalls = 2 and state.phase = "segment" and state.pendingWindow = invalid and state.pendingPlaylistSequence = -1&, "candidate actual gate runs before pending commit")
    mrCheck(state.initAliasCount = 1& and Type(state.initAliasCount, 3) = "LongInteger", "successful verified alias increments once")
    mrCheck(state.mapUrl = "https://cdn.example.invalid/init-rotated.mp4?fixtureAlias=one%2Btwo&v=2" and state.lastPlaylistSequence = 11& and state.playlistCount = 2, "verified alias commits exact URI/window/sequence")
    mrCheck(FormatJson(state.initIds) = initIds and FormatJson(state.tracks) = tracks and state.serial = serial and state.cacheBytes = cache and state.initPairCount = 1 and state.input = invalid, "alias allocates no replacement init/cache assets")
    mrCheck(FormatJson(nativeLivePublication(state)) = FormatJson(old), "old generation remains until new media is converted")
    mrPair(state, 13, 2100&)
    current = nativeLivePublication(state)
    mrCheck(current.generation = old.generation + 1& and current.mediaSequence = 11& and current.initVideoId = old.initVideoId and current.initAudioId = old.initAudioId, "continued generation uses original approved init IDs")
    mrGolden(held.data, m.corpus.media[0].video, "held original body")
    for each pair in [[current.initVideoId, m.corpus.init.video], [current.initAudioId, m.corpus.init.audio]]
        body = nativeLiveAcquire(state, pair[0])
        mrGolden(body.data, pair[1], "retained original init")
        nativeLiveRelease(state, pair[0])
    end for
    nativeLiveRetire(state, old.generation)
    nativeLiveRetire(state, current.generation)
    mrCheck(not nativeLiveClose(state) and state.pendingWindow = invalid and not state.closed, "held lease still prevents premature cleanup")
    nativeLiveRelease(state, held.id)
    mrClose(state)
    mrCase("equivalent-map-pending-gate-media-and-held-lease")
end sub

sub mrRefused()
    for each candidate in m.corpus.changed
        state = mrPrepared()
        mrPending(state)
        previous = FormatJson(nativeLivePublication(state))
        metadata = FormatJson(m.config.metadata)
        reason = ""
        payload = mrBytes(candidate.hex)
        ' Both valid mutations keep the same decoder layout, so rejection proves binary identity.
        if candidate.valid then unused = nativeLiveInspectInitMetadata(payload)
        try
            rokuDemuxFeedInput(state, "init", payload, 2100&)
        catch error
            reason = error.message
        end try
        mrCheck(reason = "native-live: selected map initialization changed", "changed binary rejected " + candidate.name)
        mrCheck(m.decoderCalls = 1 and FormatJson(m.config.metadata) = metadata, "changed candidate never reaches decoder gate or replaces approved metadata")
        mrCheck(state.mapUrl = "https://cdn.example.invalid/init.mp4" and state.phase = "init-rotation" and state.playlistCount = 1 and state.segmentPairCount = 3, "changed bytes cannot commit map/window/media")
        mrCheck(state.initAliasCount = 0&, "changed candidate never counts as an accepted alias")
        mrCheck(FormatJson(nativeLivePublication(state)) = previous and nlBodyDigest(payload) = candidate.sha256, "old publication and rejected input remain unchanged")
        nlAbort(state, reason)
        mrCheck(state.pendingWindow = invalid and state.phase = "failed" and state.failureCategory = 1, "actual failure drops pending state while retaining old assets")
        mrClose(state)
        mrCase("binary-refusal-" + candidate.name)
    end for
end sub

sub mrStopAndDecoder()
    for each mode in ["before", "during", "decoder-refusal"]
        state = mrPrepared()
        mrPending(state)
        previous = FormatJson(nativeLivePublication(state))
        metadata = FormatJson(m.config.metadata)
        if mode = "before" then m.top.stopRequested = true
        if mode = "during" then m.stopDuringDecode = true
        if mode = "decoder-refusal" then m.decoderAllowed = false
        reason = ""
        accepted = false
        try
            accepted = rokuDemuxFeedInput(state, "init", mrBytes(m.corpus.init.input.hex), 2100&)
        catch error
            reason = error.message
        end try
        if mode = "decoder-refusal"
            mrCheck(reason = "native-live: actual init decoder rejected", "equivalent bytes cannot bypass current canonical gate")
            nlAbort(state, reason)
        else
            mrCheck(not accepted and reason = "" and m.top.stopRequested, "cooperative stop skips candidate commit")
        end if
        mrCheck(state.mapUrl = "https://cdn.example.invalid/init.mp4" and state.playlistCount = 1 and state.segmentPairCount = 3, "stop/refusal keeps approved map and media count")
        mrCheck(state.initAliasCount = 0&, "stop or decoder refusal does not increment aliases")
        mrCheck(FormatJson(nativeLivePublication(state)) = previous and FormatJson(m.config.metadata) = metadata and state.initPairCount = 1, "stop/refusal preserves publication/init/config")
        mrClose(state)
        mrCase("pending-" + mode)
    end for
end sub

sub mrStructural()
    cases = [
        { name: "epoch", map: "other.mp4", epoch: 1, mixed: false, changed: false, reason: "selected discontinuity change unsupported" },
        { name: "mixed-map", map: "other.mp4", epoch: 0, mixed: true, changed: false, reason: "selected window crosses map or discontinuity" },
        { name: "cached-media-uri", map: "other.mp4", epoch: 0, mixed: false, changed: true, reason: "cached segment identity changed" },
        { name: "unapproved-origin", map: "https://unapproved.example.invalid/init.mp4", epoch: 0, mixed: false, changed: false, reason: "URL origin not approved" }
    ]
    for each item in cases
        state = mrPrepared()
        previous = FormatJson(nativeLivePublication(state))
        reason = ""
        try
            rokuDemuxFeedInput(state, "playlist", mrPlaylist(11, item.map, item.epoch, item.mixed, item.changed), 2000&)
        catch error
            reason = error.message
        end try
        mrCheck(reason = "native-live: " + item.reason and state.pendingWindow = invalid and state.mapUrl = "https://cdn.example.invalid/init.mp4", "source invariant remains fail closed " + item.name)
        mrCheck(state.playlistCount = 1 and FormatJson(nativeLivePublication(state)) = previous, "rejected source never updates publication")
        mrClose(state)
        mrCase("source-refusal-" + item.name)
    end for
end sub

sub mrTransport()
    for each mode in ["deadline-retry", "deadline", "work-quota", "cancel-failure", "healthy-pending"]
        state = mrPrepared()
        mrPending(state)
        previous = FormatJson(nativeLivePublication(state))
        calls = [0]
        transfer = { "calls": calls, "succeeds": mode <> "cancel-failure", "AsyncCancel": mrCancel }
        state.op = { "transfer": transfer, "kind": "init", "url": "https://cdn.example.invalid/init.mp4", "phase": "get", "limit": 2097152, "deadline": 7000& }
        ' A second timeout on the same URL is fatal; the first one retries.
        if mode = "deadline" or mode = "cancel-failure" then state.timedOutUrl = state.op.url
        nowMs = 7000&
        if mode = "work-quota"
            state.quotaSteps = 12000
            nowMs = 2100&
        else if mode = "healthy-pending"
            nowMs = 6999&
        end if
        status = nativeLiveTick(state, invalid, nowMs)
        if mode = "deadline-retry"
            mrCheck(status.phase = "init-rotation" and status.error = "" and state.op = invalid and calls[0] = 1 and state.timedOutUrl = "https://cdn.example.invalid/init.mp4", "first hung transfer is cancelled for one fresh retry")
        else if mode = "healthy-pending"
            mrCheck(status.phase = "init-rotation" and calls[0] = 0 and state.op <> invalid, "within deadline pending request retains sole transfer")
        else
            reason = "native-live: upstream operation deadline"
            if mode = "work-quota" then reason = "native-live: steady work interval bound"
            if mode = "cancel-failure" then reason = "native-live: cancellation or input cleanup failed"
            mrCheck(status.error = reason and status.phase = "failed" and state.pendingWindow = invalid and state.op = invalid and calls[0] = 1, "actual Tick cancellation and fatal reason " + mode)
        end if
        mrCheck(FormatJson(nativeLivePublication(state)) = previous and state.initPairCount = 1 and state.segmentPairCount = 3, "transport failure/pending keeps advertised original init/media")
        mrClose(state)
        if mode = "healthy-pending" then mrCheck(calls[0] = 1, "pending close cooperatively cancels sole transfer")
        mrCase("transport-" + mode)
    end for
end sub

sub mrAliasTelemetry()
    state = mrPrepared()
    m.liveState = state
    mrCheck(recordLiveInitAliases() and m.result.initAliasCount = 0& and Type(m.result.initAliasCount, 3) = "LongInteger", "real zero count remains distinguishable from absent telemetry")
    mrPending(state)
    mrCheck(rokuDemuxFeedInput(state, "init", mrBytes(m.corpus.init.input.hex), 2100&), "telemetry fixture validates candidate")
    mrCheck(recordLiveInitAliases() and m.result.initAliasCount = 1&, "actual server helper records verified alias count")
    mrCheck(FormatJson(m.result).InStr(Chr(34) + "initAliasCount" + Chr(34)) >= 0, "safe result counter has exact native JSON casing")
    mrClose(state)
    mrCheck(recordLiveInitAliases() and m.result.initAliasCount = 1&, "server retains real successful count after Core close")
    m.liveState = {}
    m.result = {}
    mrCheck(recordLiveInitAliases() and not m.result.DoesExist("initAliasCount"), "legacy missing count cannot fabricate alias proof")
    for each bad in ["1", 1.0, -1&, 4294967296&]
        m.liveState = { initAliasCount: bad }
        mrCheck(not recordLiveInitAliases() and not m.result.DoesExist("initAliasCount"), "malformed count refused without synthesized value")
    end for
    m.liveState = { initAliasCount: 4294967295& }
    mrCheck(recordLiveInitAliases() and m.result.initAliasCount = 4294967295&, "maximum Long counter is exported exactly")
    m.liveState = {}
    mrCheck(not recordLiveInitAliases(), "previously observed count cannot disappear silently")
    state = mrPrepared()
    mrPending(state)
    state.initAliasCount = 4294967295&
    reason = ""
    try
        rokuDemuxFeedInput(state, "init", mrBytes(m.corpus.init.input.hex), 2100&)
    catch error
        reason = error.message
    end try
    mrCheck(reason = "native-live: integer bound" and state.initAliasCount = 4294967295& and state.mapUrl = "https://cdn.example.invalid/init.mp4" and state.playlistCount = 1, "alias exhaustion fails before pending commit without saturation")
    nlAbort(state, reason)
    mrClose(state)
    mrCase("successful-only-safe-alias-telemetry-and-exhaustion")
end sub

sub main()
    m.assertions = 0
    m.cases = 0
    try
        m.corpus = ParseJson(ReadAsciiFile("pkg:/corpus.json"))
        mrEquivalent()
        mrRefused()
        mrStopAndDecoder()
        mrStructural()
        mrTransport()
        mrAliasTelemetry()
        print "STITCH_ROKU_MAP_PASS: __MARKER__ cases="; m.cases; " assertions="; m.assertions
    catch error
        print "STITCH_ROKU_MAP_FAIL: " + error.message
    end try
end sub
