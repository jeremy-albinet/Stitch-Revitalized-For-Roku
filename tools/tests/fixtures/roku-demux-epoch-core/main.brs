sub checkEC(ok as boolean, message as string)
    if not ok then throw "epoch-core-fixture: " + message
    m.assertions += 1
end sub

sub caseEC(name as string)
    m.cases += 1
    print "STITCH_EPOCH_CORE_CASE: " + name
end sub

function bytesEC(record as object) as object
    body = CreateObject("roByteArray")
    body.FromHexString(record.hex)
    return body
end function

sub goldenEC(body as object, record as object, label as string)
    checkEC(body.Count() = record.count and nlBodyDigest(body) = record.sha256 and LCase(body.ToHexString()) = record.hex, label + " complete independent binary golden")
    m.goldens += 1
end sub

function newEC(transitions = true as boolean, delay = 0 as integer) as object
    options = { mode: "steady", sessionId: "0123456789abcdef0123456789abcdef" }
    if transitions then options.sourceTransitions = true
    return nativeLiveCreate("https://cdn.example.invalid/live.m3u8", 0&, delay, invalid, true, 16777216&, options)
end function

function rowEC(sequence as integer, mode = "" as string) as object
    name = "content"
    epoch = 0&
    if sequence >= 13 and sequence <= 15
        name = "ad"
        epoch = 1&
    else if sequence >= 16
        epoch = 2&
        if sequence >= 20
            name = ["content", "ad", "other"][(sequence - 20) mod 3]
            epoch += sequence - 20
        end if
    end if
    if mode = "alias" and sequence >= 13
        name = "content-alias"
        epoch = 0&
    end if
    if mode = "pts" then name = "content"
    return { name: name, epoch: epoch }
end function

function playlistEC(first as integer, count as integer, mode = "" as string, ended = false as boolean) as string
    row = rowEC(first, mode)
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:6" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:" + first.ToStr() + Chr(10)
    text += "#EXT-X-DISCONTINUITY-SEQUENCE:" + row.epoch.ToStr() + Chr(10)
    previous = invalid
    for i = 0 to count - 1
        sequence = first + i
        row = rowEC(sequence, mode)
        if previous = invalid or row.name <> previous.name or row.epoch <> previous.epoch
            if previous <> invalid and row.epoch <> previous.epoch then text += "#EXT-X-DISCONTINUITY" + Chr(10)
            text += "#EXT-X-MAP:URI=" + Chr(34) + row.name + ".mp4" + Chr(34) + Chr(10)
        end if
        text += "#EXTINF:2.002000," + Chr(10) + "segment-" + sequence.ToStr() + ".m4s" + Chr(10)
        previous = row
    end for
    if ended then text += "#EXT-X-ENDLIST" + Chr(10)
    return text
end function

' Actual inspection is executed; the native device-support decision is mocked.
sub validateLiveInitOutput(payload as object)
    actual = nativeLiveInspectInitMetadata(payload)
    checkEC(actual.videoCodec = "avc1.4D402A" and actual.audioCodec = "mp4a.40.2" and actual.width = 1920 and actual.height = 1080 and actual.audioSampleRate = 48000 and actual.audioChannels = 2, "actual changed init retains inspectable master configuration")
    if m.rejectGate then throw "native-live: actual init decoder rejected"
    m.gateCalls += 1
    if m.stopDuringGate then m.top.stopRequested = true
end sub

sub retireEC(state as object)
    ids = []
    for each generation in state.generations
        if generation.advertised then ids.Push(generation.id)
    end for
    for each id in ids
        nativeLiveRetire(state, id)
    end for
end sub

sub closeEC(state as object)
    retireEC(state)
    checkEC(nativeLiveClose(state), "actual retired unleased close")
    checkEC(state.closed and state.phase = "stopped" and state.sourceUrl = "" and state.mapUrl = "" and state.input = invalid and state.temporaryVideo = invalid and state.pendingWindow = invalid and state.pendingSegment = invalid and state.tracks = invalid and state.assets.Count() = 0 and state.segments.Count() = 0 and state.initIds.Count() = 0 and state.cacheBytes = 0, "actual close clears all staged source bindings and bytes")
    m.top.stopRequested = false
    m.rejectGate = false
    m.stopDuringGate = false
end sub

sub drainEC(state as object, nowMs as dynamic)
    steps = 0
    while state.phase <> "ready" and state.phase <> "ended"
        checkEC(steps < 80, "bounded local stage drain")
        if state.phase = "init" or state.phase = "init-rotation"
            intent = nlIntent(state, nowMs)
            name = "content"
            for each candidate in ["ad", "other"]
                if intent.url.InStr("/" + candidate + ".mp4") >= 0 then name = candidate
            end for
            previousIds = state.initIds
            previousMap = state.mapUrl
            previousTracks = state.tracks
            record = m.corpus.inits[name]
            input = bytesEC(record.input)
            checkEC(rokuDemuxFeedInput(state, "init", input, nowMs), "actual caller feeds approved init")
            if state.phase = "init-video"
                if previousIds.Count() = 2 then checkEC(state.initIds[0] = previousIds[0] and state.mapUrl = previousMap and FormatJson(state.tracks) = FormatJson(previousTracks), "old pair mapping retained until both split outputs exist")
                nativeLiveAdvance(state, nowMs)
                if previousIds.Count() = 2 then checkEC(state.phase = "init-audio" and state.initIds[0] = previousIds[0] and state.mapUrl = previousMap, "one split output cannot replace old scalar identity")
                nativeLiveAdvance(state, nowMs)
                checkEC(state.input = invalid and state.temporaryVideo = invalid and state.pendingWindow = invalid, "complete pair commits and releases stage")
            end if
            for each pair in [[state.initIds[0], record.video], [state.initIds[1], record.audio]]
                body = nativeLiveAcquire(state, pair[0])
                checkEC(body <> invalid, "actual split init registered")
                goldenEC(body.data, pair[1], "init " + name)
                nativeLiveRelease(state, pair[0])
            end for
            checkEC(nlBodyDigest(input) = record.input.sha256, "input init bytes unchanged")
        else if state.phase = "segment"
            missing = nlMissing(state)
            if missing = invalid
                nativeLiveAdvance(state, nowMs)
            else
                record = m.corpus.media[CInt(missing.sequence - 10&)]
                input = bytesEC(record.input)
                nativeLiveFeed(state, "segment", input, nowMs)
                nativeLiveAdvance(state, nowMs)
                nativeLiveAdvance(state, nowMs)
                saved = state.segments[nlSegmentIndex(state, missing.sequence)]
                checkEC(saved.mapUrl = missing.mapUrl and saved.sourceEpoch = missing.epoch and saved.durationUs = missing.durationUs and saved.initVideoId <> saved.initAudioId, "converted segment bound to its exact approved source init")
                for each pair in [[saved.videoId, record.video], [saved.audioId, record.audio]]
                    body = nativeLiveAcquire(state, pair[0])
                    checkEC(body <> invalid, "bound media remains registered")
                    goldenEC(body.data, pair[1], "media " + missing.sequence.ToStr())
                    nativeLiveRelease(state, pair[0])
                end for
                checkEC(nlBodyDigest(input) = record.input.sha256 and state.input = invalid and state.temporaryVideo = invalid and state.pendingSegment = invalid, "fragment bytes TFDT and scratch identity preserved")
                m.pairs += 1
            end if
        else
            nativeLiveAdvance(state, nowMs)
        end if
        steps += 1
    end while
end sub

function preparedEC() as object
    state = newEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 3), 0&)
    drainEC(state, 0&)
    pub = nativeLivePublication(state)
    checkEC(pub.version = 2 and loopbackPublicationValid(pub) and pub.discontinuitySequence = 0& and state.initPairCount = 1, "opted initial coherent publication is v2")
    return state
end function

sub manifestEC(pub as object, name as string)
    for each track in ["video", "audio"]
        body = loopbackManifest(track, pub)
        checkEC(body <> invalid and body.ToAsciiString() = m.corpus.manifests[name][track], "actual complete manifest golden " + name + " " + track)
        m.manifests += 1
    end for
end sub

function feedErrorEC(state as object, kind as string, payload as dynamic, nowMs as dynamic) as string
    try
        nativeLiveFeed(state, kind, payload, nowMs)
    catch e
        return e.message
    end try
    return ""
end function

sub timelineEC()
    caseEC("content-ad-content-with-held-leases")
    state = preparedEC()
    pub = nativeLivePublication(state)
    manifestEC(pub, "initial")
    heldInit = nativeLiveAcquire(state, pub.initVideoId)
    heldMedia = nativeLiveAcquire(state, pub.segments[0].videoId)
    oldInit = pub.initVideoId
    oldGeneration = pub.generation
    previousPub = pub
    for sequence = 13 to 18
        nowMs = (sequence - 12) * 3000&
        nativeLiveFeed(state, "playlist", playlistEC(10, sequence - 9), nowMs)
        if sequence = 13 or sequence = 16
            checkEC(state.phase = "init-rotation" and state.pendingWindow.sequence = sequence and state.pendingWindow.epoch = state.epoch + 1&, "genuine boundary stages at first unpublished sequence")
            retained = nativeLivePublication(state)
            checkEC(FormatJson(retained) = FormatJson(previousPub), "old publication stays usable during new init stage")
        end if
        drainEC(state, nowMs)
        pub = nativeLivePublication(state)
        checkEC(loopbackPublicationValid(pub) and pub.mediaSequence = sequence - 2 and pub.segments[2].sequence = sequence, "actual rolling v2 publication is contiguous")
        for each segment in pub.segments
            saved = state.segments[nlSegmentIndex(state, segment.sequence)]
            checkEC(segment.epoch = saved.localEpoch and segment.initVideoId = saved.initVideoId and segment.initAudioId = saved.initAudioId, "publication uses exact per-segment pair")
        end for
        if sequence = 13 then manifestEC(pub, "first-ad")
        if sequence = 16 then manifestEC(pub, "return")
        if sequence = 18 then manifestEC(pub, "rolled")
        checkEC(state.nextPoll = nowMs + 3000& and pub.targetDuration = 2, "source target6 polling and output target2 stay distinct")
        previousPub = pub
    end for
    checkEC(state.initPairCount = 3 and state.initAliasCount = 0 and state.segmentPairCount = 9 and state.localEpoch = 2&, "no missing or duplicated content/ad/return conversion")
    checkEC(nlAssetIndex(state, oldInit) >= 0 and nlBodyDigest(heldInit.data) = m.corpus.inits.content.video.sha256, "old leased init still byte-identical after real transition")
    retireEC(state)
    checkEC(nlAssetIndex(state, heldMedia.id) >= 0 and nlAssetIndex(state, heldInit.id) >= 0 and not nativeLiveClose(state), "retired leased old generation prevents close")
    nativeLiveRelease(state, heldMedia.id)
    nativeLiveRelease(state, heldInit.id)
    checkEC(nlAssetIndex(state, oldInit) < 0, "expired unleased old init is pruned")
    closeEC(state)
    state = preparedEC()
    calls = m.gateCalls
    oldIds = state.initIds
    nativeLiveFeed(state, "playlist", playlistEC(10, 4, "pts"), 3000&)
    checkEC(state.phase = "segment" and state.pendingWindow = invalid and state.localEpoch = 1& and state.initIds[0] = oldIds[0], "same approved MAP genuine PTS epoch needs no invented init download")
    nativeLiveFeed(state, "segment", bytesEC(m.corpus.ptsMedia.input), 3000&)
    nativeLiveAdvance(state, 3000&)
    nativeLiveAdvance(state, 3000&)
    pub = nativeLivePublication(state)
    checkEC(loopbackPublicationValid(pub) and pub.segments[2].epoch = 1& and pub.segments[2].initVideoId = pub.initVideoId and state.initPairCount = 1 and m.gateCalls = calls, "same-pair discontinuity retains approved init with actual reset fragment")
    for each pair in [[pub.segments[2].videoId, m.corpus.ptsMedia.video], [pub.segments[2].audioId, m.corpus.ptsMedia.audio]]
        asset = nativeLiveAcquire(state, pair[0])
        goldenEC(asset.data, pair[1], "same-pair reset fragment")
        nativeLiveRelease(state, pair[0])
    end for
    closeEC(state)
end sub

sub mixedEC()
    caseEC("several-short-mixed-boundaries-and-source-delay")
    state = preparedEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 10), 3000&)
    drainEC(state, 3000&)
    previous = nativeLivePublication(state)
    checkEC(previous.mediaSequence = 13 and previous.segments.Count() = 7 and state.publishedLast = 19&, "all seven unpublished continuity segments kept")
    nativeLiveRetire(state, 1&)
    nativeLiveFeed(state, "playlist", playlistEC(20, 3), 6000&)
    drainEC(state, 6000&)
    pub = nativeLivePublication(state)
    checkEC(pub.mediaSequence = 20 and pub.segments.Count() = 3 and pub.discontinuitySequence = 2& and pub.segments[1].epoch = 3& and pub.segments[2].epoch = 4&, "several genuine boundaries retain all local labels")
    for each segment in pub.segments
        checkEC(nlAssetIndex(state, segment.initVideoId) >= 0 and nlAssetIndex(state, segment.initAudioId) >= 0, "intermediate epoch init survives later stage pruning")
    end for
    checkEC(state.segmentPairCount = 13 and state.initPairCount = 5, "each selected mixed segment converted exactly once")
    closeEC(state)
    state = newEC(true, 2)
    m.config = { sourceDelaySeconds: 2 }
    nativeLiveFeed(state, "playlist", playlistEC(10, 4), 0&)
    drainEC(state, 0&)
    unused = nativeLivePublication(state)
    nativeLiveFeed(state, "playlist", playlistEC(10, 5), 3000&)
    drainEC(state, 3000&)
    pub = nativeLivePublication(state)
    checkEC(pub.sourceOffsetUs = 2002000& and pub.mediaSequence = 11& and pub.segments[2].sequence = 13&, "source delay floor keeps exact excluded tail and ad sequence")
    closeEC(state)
    m.config = { sourceDelaySeconds: 0 }
end sub

sub optionsEC()
    caseEC("explicit-opt-in-and-legacy-startup-policy")
    for each options in [{ mode: "steady", sessionId: "0123456789abcdef0123456789abcdef", sourceTransitions: false }, { mode: "steady", sessionId: "0123456789abcdef0123456789abcdef", sourceTransitions: "true" }, { mode: "steady", sessionId: "0123456789abcdef0123456789abcdef", sourceTransitions: 1 }, { mode: "steady", sessionId: "0123456789abcdef0123456789abcdef", unrelated: true }, { mode: "steady", sessionId: "0123456789abcdef0123456789abcdef", sourceTransitions: true, unrelated: true }]
        reason = ""
        try
            unused = nativeLiveCreate("https://cdn.example.invalid/live.m3u8", 0&, 0, invalid, true, 16777216&, options)
        catch e
            reason = e.message
        end try
        checkEC(reason.Left(13) = "native-live: ", "malformed opt-in options refused")
    end for
    state = newEC(false)
    checkEC(not state.sourceTransitions, "legacy two-key steady remains default false")
    nativeLiveFeed(state, "playlist", playlistEC(10, 3), 0&)
    ' Same native conversion path, but retain the original public five-field segments.
    payload = bytesEC(m.corpus.inits.content.input)
    nativeLiveFeed(state, "init", payload, 0&)
    nativeLiveAdvance(state, 0&)
    nativeLiveAdvance(state, 0&)
    for sequence = 10 to 12
        nativeLiveFeed(state, "segment", bytesEC(m.corpus.media[sequence - 10].input), 0&)
        nativeLiveAdvance(state, 0&)
        nativeLiveAdvance(state, 0&)
    end for
    pub = nativeLivePublication(state)
    checkEC(not pub.DoesExist("version") and pub.Count() = 9 and pub.segments[0].Count() = 5, "legacy v1 shape remains exact")
    checkEC(feedErrorEC(state, "playlist", playlistEC(10, 4), 3000&) = "native-live: selected window crosses map or discontinuity", "legacy steady mixed refusal stays unchanged")
    closeEC(state)
    state = newEC()
    nativeLiveFeed(state, "playlist", playlistEC(12, 3), 0&)
    checkEC(state.phase = "playlist" and not state.started and state.pendingWindow = invalid and state.initIds.Count() = 0 and state.nextPoll = 3000& and nativeLivePublication(state) = invalid, "uninitialized mixed startup still waits without fake readiness")
    closeEC(state)
end sub

sub aliasesEC()
    caseEC("byte-alias-distinct-from-genuine-stage-and-gate-refusal")
    state = preparedEC()
    oldPub = nativeLivePublication(state)
    nativeLiveFeed(state, "playlist", playlistEC(10, 4, "alias"), 3000&)
    checkEC(state.phase = "init-rotation" and state.pendingWindow.epoch = state.epoch, "same-source-epoch alias stage remains distinct")
    checkEC(rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.content.input), 3000&), "actual caller approves byte-identical alias")
    checkEC(state.phase = "segment" and state.initAliasCount = 1& and state.initPairCount = 1 and state.localEpoch = 0&, "alias reuses complete pair without fake epoch")
    checkEC(FormatJson(nativeLivePublication(state)) = FormatJson(oldPub), "alias does not prematurely change publication")
    closeEC(state)
    state = preparedEC()
    oldPub = nativeLivePublication(state)
    nativeLiveFeed(state, "playlist", playlistEC(10, 4, "alias"), 3000&)
    calls = m.gateCalls
    reason = ""
    try
        unused = rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&)
    catch e
        reason = e.message
    end try
    checkEC(reason = "native-live: selected map initialization changed" and m.gateCalls = calls, "same-epoch changed bytes refused before device gate mutation")
    nlAbort(state, reason)
    checkEC(state.input = invalid and state.pendingWindow = invalid and FormatJson(nativeLivePublication(state)) = FormatJson(oldPub), "failed alias clears stage and preserves old publication")
    closeEC(state)
    state = preparedEC()
    oldPub = nativeLivePublication(state)
    nativeLiveFeed(state, "playlist", playlistEC(10, 4), 3000&)
    m.rejectGate = true
    reason = ""
    try
        unused = rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&)
    catch e
        reason = e.message
    end try
    checkEC(reason = "native-live: actual init decoder rejected" and state.input = invalid and state.initPairCount = 1 and state.pendingWindow <> invalid, "actual caller gate refusal never feeds changed bytes")
    nlAbort(state, reason)
    checkEC(FormatJson(nativeLivePublication(state)) = FormatJson(oldPub), "decoder refusal leaves old generation usable")
    closeEC(state)
    state = preparedEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 4), 3000&)
    pending = state.pendingWindow
    pending.sequence = 99&
    state.pendingWindow = pending
    checkEC(feedErrorEC(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&) = "native-live: pending epoch initialization invalid", "stale pending init cannot commit")
    closeEC(state)
    state = preparedEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 4), 3000&)
    checkEC(rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&), "staged identity baseline inspected")
    nativeLiveAdvance(state, 3000&)
    pending = state.pendingWindow
    pending.tracks = [[7&, "video"], [8&, "audio"]]
    state.pendingWindow = pending
    serial = state.serial
    reason = ""
    try
        nativeLiveAdvance(state, 3000&)
    catch e
        reason = e.message
    end try
    checkEC(reason = "native-live: staged initialization identity changed" and state.serial = serial and state.initPairCount = 1, "wrong staged track map refused before atomic admission")
    nlAbort(state, reason)
    closeEC(state)
end sub

sub identityEC()
    caseEC("shared-source-identity-gap-epoch-and-track-refusals")
    for each field in ["uri", "duration", "map", "epoch", "rollback", "gap", "epoch-jump", "history-bound"]
        state = preparedEC()
        text = playlistEC(10, 4)
        expected = "native-live: cached epoch segment identity changed"
        if field = "uri" then text = text.Replace("segment-10.m4s", "changed-10.m4s")
        if field = "duration" then text = text.Replace("#EXTINF:2.002000,", "#EXTINF:2.003000,")
        if field = "map" then text = text.Replace("content.mp4", "content-alias.mp4")
        if field = "epoch" then text = text.Replace("#EXT-X-DISCONTINUITY-SEQUENCE:0", "#EXT-X-DISCONTINUITY-SEQUENCE:1")
        if field = "rollback"
            text = playlistEC(9, 3)
            expected = "native-live: playlist sequence moved backwards"
        end if
        if field = "gap"
            text = playlistEC(14, 3)
            expected = "native-live: continuity history unavailable"
        end if
        if field = "epoch-jump"
            text = text.Replace("#EXT-X-DISCONTINUITY" + Chr(10), "#EXT-X-DISCONTINUITY" + Chr(10) + "#EXT-X-DISCONTINUITY" + Chr(10))
            expected = "native-live: source epoch progression invalid"
        end if
        if field = "history-bound"
            text = playlistEC(10, 13)
            expected = "native-live: continuity window segment bound"
        end if
        checkEC(feedErrorEC(state, "playlist", text, 3000&) = expected, "exact source identity refusal " + field)
        closeEC(state)
    end for
    state = preparedEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 4), 3000&)
    checkEC(rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&), "genuine ad init approved before split")
    nativeLiveAdvance(state, 3000&)
    nativeLiveAdvance(state, 3000&)
    reason = ""
    try
        nativeLiveFeed(state, "segment", bytesEC(m.corpus.media[0].input), 3000&)
        nativeLiveAdvance(state, 3000&)
    catch e
        reason = e.message
    end try
    checkEC(reason = "native-demux: fragment track absent from init", "actual changed track map rejects old-track fragment")
    nlAbort(state, reason)
    closeEC(state)
    state = preparedEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 4), 3000&)
    ' Simulate an internal stale binding without accepting new init bytes.
    state.phase = "segment"
    reason = feedErrorEC(state, "segment", bytesEC(m.corpus.media[3].input), 3000&)
    checkEC(reason = "native-live: segment initialization binding invalid", "unvalidated segment binding is refused before conversion")
    nlAbort(state, reason)
    closeEC(state)
    state = preparedEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 10), 3000&)
    drainEC(state, 3000&)
    unused = nativeLivePublication(state)
    text = playlistEC(20, 3).Replace("#EXT-X-DISCONTINUITY-SEQUENCE:2" + Chr(10), "")
    checkEC(feedErrorEC(state, "playlist", text, 6000&) = "native-live: next source epoch invalid", "unknown relative epoch reset is never normalized")
    nlAbort(state, "native-live: test-stop")
    closeEC(state)
    for each item in [{ target: "1", duration: "1.500000", expected: "native-live: epoch source duration unsupported" }, { target: "6", duration: "2.500000", expected: "native-live: epoch source duration unsupported" }]
        state = newEC()
        text = playlistEC(10, 5, "pts").Replace("#EXT-X-DISCONTINUITY" + Chr(10), "").Replace("#EXT-X-TARGETDURATION:6", "#EXT-X-TARGETDURATION:" + item.target).Replace("2.002000", item.duration)
        checkEC(feedErrorEC(state, "playlist", text, 0&) = item.expected, "fixed target2 never loosens source rounded or local duration bound")
        closeEC(state)
    end for
    ' Continuity prepends older segments after a stall; they meet the same bound.
    for each item in [{ duration: "2.499999", expected: "" }, { duration: "2.600000", expected: "native-live: epoch source duration unsupported" }]
        state = preparedEC()
        text = playlistEC(13, 6).Replace("#EXTINF:2.002000," + Chr(10) + "segment-14.m4s", "#EXTINF:" + item.duration + "," + Chr(10) + "segment-14.m4s")
        checkEC(feedErrorEC(state, "playlist", text, 3000&) = item.expected, "continuity-prepended segment duration is checked at feed " + item.duration)
        if item.expected = "" then checkEC(state.window.segments[0].sequence = 13 and state.window.segments[1].durationUs = 2499999&, "continuity keeps the prepended unpublished segment")
        nlAbort(state, "native-live: test-stop")
        closeEC(state)
    end for
end sub

sub admissionEC()
    caseEC("atomic-pair-slot-pressure-and-old-lease-cleanup")
    state = preparedEC()
    oldIds = state.initIds
    held = []
    body = CreateObject("roByteArray")
    body.Push(1)
    for i = 0 to 27
        ids = nlStorePair(state, body, body)
        for each id in ids
            checkEC(nativeLiveAcquire(state, id) <> invalid, "actual near-cap filler lease admitted")
            held.Push(id)
        end for
    end for
    checkEC(state.assets.Count() = 64, "actual registered assets reach unchanged64 ceiling")
    nativeLiveFeed(state, "playlist", playlistEC(10, 4), 3000&)
    checkEC(rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&), "near-cap actual init inspected")
    nativeLiveAdvance(state, 3000&)
    serial = state.serial
    reason = ""
    try
        nativeLiveAdvance(state, 3000&)
    catch e
        reason = e.message
    end try
    checkEC(reason = "native-live: cache asset count bound" and state.serial = serial and state.initIds[0] = oldIds[0] and state.assets.Count() = 64 and state.initPairCount = 1, "failed pair admission never swaps scalar identity or admits one track")
    nlAbort(state, reason)
    for each id in held
        nativeLiveRelease(state, id)
    end for
    checkEC(state.assets.Count() = 8, "released filler assets retire without touching old publication")
    closeEC(state)
end sub

' The native GET boundary is not opened; record its real Core dispatch hook.
sub playlistStartedEC(state as object, nowMs as dynamic)
    checkEC(nlIntent(state, nowMs).kind = "playlist", "stale-tail poll starts only when due")
    state.op = { kind: "playlist", phase: "get", deadline: nowMs + 6000& }
    nativeLivePlaylistStarted(state, nowMs)
    state.op = invalid
end sub

sub staleTailEC()
    caseEC("mixed-shorter-tail-discard-and-health-deadline")
    for each retained in [true, false]
        for each requestPolling in [false, true]
            state = preparedEC()
            nativeLiveFeed(state, "playlist", playlistEC(10, 6), 3000&)
            drainEC(state, 3000&)
            current = nativeLivePublication(state)
            checkEC(current.generation = 2 and current.mediaSequence = 13 and current.discontinuitySequence = 1 and state.publishedLast = 15&, "stale-tail baseline has forward ad publication")
            if not retained then nativeLiveRetire(state, 1&)
            checkEC((nlSegmentIndex(state, 12&) >= 0) = retained, "mixed stale-tail case has requested cache retention")
            held = nativeLiveAcquire(state, current.segments[0].videoId)
            beforeWindow = FormatJson(state.window)
            beforeSegments = FormatJson(state.segments)
            beforeGenerations = FormatJson(state.generations)
            beforeBytes = state.cacheBytes
            beforeSerial = state.serial
            beforeGate = m.gateCalls
            state.pollFromRequest = requestPolling
            if requestPolling then state.playlistSnapshot = playlistEC(10, 6)
            playlistStartedEC(state, 6000&)
            stale = playlistEC(10, 5)
            checkEC(rokuDemuxFeedInput(state, "playlist", stale, 6400&), "actual Fetch caller accepts completed stale snapshot")
            nativeLiveAdvance(state, 6400&)
            checkEC(state.phase = "ready" and FormatJson(state.window) = beforeWindow and state.publishedFirst = 13& and state.publishedLast = 15&, "stale tail preserves published window and bounds")
            checkEC(FormatJson(nativeLivePublication(state)) = FormatJson(current) and FormatJson(state.generations) = beforeGenerations and state.nextGeneration = 3&, "stale tail preserves publication and generation")
            checkEC(state.lastUpstreamProgress = 3000& and state.lastPublicationProgress = 3000& and state.lastPlaylistSequence = 10&, "stale tail cannot refresh progress")
            checkEC(FormatJson(state.segments) = beforeSegments and state.cacheBytes = beforeBytes and state.serial = beforeSerial and state.segmentPairCount = 6 and state.initPairCount = 2 and m.gateCalls = beforeGate and state.pendingWindow = invalid, "mixed stale tail cannot consult missing history or stage old epoch")
            expectedPoll = 9400&
            if requestPolling then expectedPoll = 12000&
            checkEC(state.nextPoll = expectedPoll and nlIntent(state, expectedPoll - 1&) = invalid, "changed stale snapshot keeps source target polling floor")
            playlistStartedEC(state, expectedPoll)
            checkEC(rokuDemuxFeedInput(state, "playlist", playlistEC(10, 6), expectedPoll + 100&), "actual Fetch caller accepts unchanged published tail")
            nativeLiveAdvance(state, expectedPoll + 100&)
            checkEC(state.lastUpstreamProgress = expectedPoll + 100& and state.lastPublicationProgress = 3000& and FormatJson(nativeLivePublication(state)) = FormatJson(current), "unchanged tail still refreshes upstream health without publication")
            nextPoll = state.nextPoll
            playlistStartedEC(state, nextPoll)
            checkEC(rokuDemuxFeedInput(state, "playlist", playlistEC(10, 7), nextPoll + 100&), "actual Fetch caller accepts resumed forward tail")
            drainEC(state, nextPoll + 100&)
            nextPub = nativeLivePublication(state)
            checkEC(loopbackPublicationValid(nextPub) and nextPub.generation = 3 and nextPub.mediaSequence = 14 and state.publishedLast = 16& and state.segmentPairCount = 7 and state.initPairCount = 3, "forward tail resumes once across next genuine epoch")
            retireEC(state)
            checkEC(not nativeLiveClose(state) and nlBodyDigest(held.data) = m.corpus.media[3].video.sha256, "discard and forward recovery preserve held real body until release")
            nativeLiveRelease(state, held.id)
            closeEC(state)
        end for
    end for
    state = preparedEC()
    nativeLiveFeed(state, "playlist", playlistEC(10, 6), 3000&)
    drainEC(state, 3000&)
    current = nativeLivePublication(state)
    state.pollFromRequest = true
    state.playlistSnapshot = playlistEC(10, 6)
    for each stamp in [6000&, 12000&, 15000&]
        playlistStartedEC(state, stamp)
        checkEC(rokuDemuxFeedInput(state, "playlist", playlistEC(10, 5), stamp + 400&), "actual Fetch caller discards repeated stale snapshots")
        expectedPoll = stamp + 3000&
        if stamp = 6000& then expectedPoll = 12000&
        checkEC(state.nextPoll = expectedPoll and state.lastUpstreamProgress = 3000& and state.lastPublicationProgress = 3000&, "repeated stale snapshots keep half target floor without extending health")
    end for
    checkEC(nlIntent(state, 17999&) = invalid, "stale upstream remains bounded just before health deadline")
    reason = ""
    try
        unused = nlIntent(state, 18000&)
    catch error
        reason = error.message
    end try
    checkEC(reason = "native-live: upstream progress deadline" and FormatJson(nativeLivePublication(state)) = FormatJson(current), "stale snapshots fail at original upstream health deadline")
    nlAbort(state, reason)
    checkEC(state.phase = "failed" and not state.DoesExist("playlistSnapshot") and not state.DoesExist("playlistRequestStartedAt") and not state.DoesExist("playlistRequestPending"), "stale health failure releases private polling state")
    closeEC(state)
end sub

sub budgetsEC()
    caseEC("unchanged-deadlines-quotas-local-overflow-and-stop")
    for each mode in ["upstream", "publication", "local-overflow", "quota", "stop"]
        state = preparedEC()
        nativeLiveFeed(state, "playlist", playlistEC(10, 4), 3000&)
        reason = ""
        if mode = "upstream" or mode = "publication"
            nowMs = 18000&
            expected = "native-live: upstream progress deadline"
            if mode = "publication"
                nowMs = 30000&
                state.lastUpstreamProgress = nowMs
                expected = "native-live: publication progress deadline"
            end if
            try
                unused = nlIntent(state, nowMs)
            catch e
                reason = e.message
            end try
            checkEC(reason = expected and state.deadline = 45000& and state.lastPublicationProgress = 0&, "staging cannot extend existing deadline " + mode)
        else if mode = "local-overflow"
            pending = state.pendingWindow
            pending.localEpoch = 4294967296&
            state.pendingWindow = pending
            try
                unused = rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&)
            catch e
                reason = e.message
            end try
            checkEC(reason = "native-live: integer bound" and state.initPairCount = 1, "local label overflow refused before staged pair swap")
        else if mode = "quota"
            state.quotaTransfers = 256
            try
                nlUseWork(state, "transfer", 3000&)
            catch e
                reason = e.message
            end try
            checkEC(reason = "native-live: steady work interval bound" and state.quotaTransfers = 256, "staging keeps original transfer quota")
        else
            m.stopDuringGate = true
            checkEC(not rokuDemuxFeedInput(state, "init", bytesEC(m.corpus.inits.ad.input), 3000&) and state.input = invalid and state.initPairCount = 1, "stop during gate suppresses Core feed")
        end if
        nlAbort(state, "native-live: test-stop")
        closeEC(state)
    end for
end sub

sub main()
    m.assertions = 0
    m.cases = 0
    m.goldens = 0
    m.manifests = 0
    m.pairs = 0
    m.gateCalls = 0
    m.rejectGate = false
    m.stopDuringGate = false
    m.top = { stopRequested: false }
    m.config = { sourceDelaySeconds: 0 }
    try
        m.corpus = ParseJSON(ReadAsciiFile("pkg:/corpus.json"))
        timelineEC()
        mixedEC()
        optionsEC()
        aliasesEC()
        identityEC()
        admissionEC()
        staleTailEC()
        budgetsEC()
        print "STITCH_EPOCH_CORE_PASS: __MARKER__ cases="; m.cases; " assertions="; m.assertions; " goldens="; m.goldens; " manifests="; m.manifests; " pairs="; m.pairs; " gateCalls="; m.gateCalls
    catch e
        print "STITCH_EPOCH_CORE_FAIL: "; e.message
    end try
end sub
