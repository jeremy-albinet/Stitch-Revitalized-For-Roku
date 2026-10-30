' Execute actual tracked Bulk/Core/Fetch bodies. No URL transfer is started.
sub checkCore(ok as boolean, message as string)
    if not ok then throw "core-fixture: " + message
    m.assertions += 1
end sub

sub caseCore(name as string)
    m.cases += 1
    print "STITCH_ROKU_CORE_CASE: " + name
end sub

function bytesCore(hex as string) as object
    result = CreateObject("roByteArray")
    result.FromHexString(hex)
    return result
end function

sub goldenCore(data as object, expected as object, label as string)
    checkCore(data.Count() = expected.count and nlBodyDigest(data) = expected.sha256 and LCase(data.ToHexString()) = expected.hex, label + " full Python byte golden")
    m.goldens += 1
end sub

function newCore(steady = true as boolean, nowMs = 0& as dynamic, sourceDelaySeconds = 0 as integer) as object
    options = invalid
    if steady then options = { mode: "steady", sessionId: "0123456789abcdef0123456789abcdef" }
    return nativeLiveCreate("https://cdn.example.invalid/live.m3u8", nowMs, sourceDelaySeconds, invalid, steady, 16777216&, options)
end function

function playlistCore(first as longinteger, count = 3 as integer, special = "" as string, duration = "2.000000" as string, target = 2 as integer) as string
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:" + target.ToStr() + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:" + first.ToStr() + Chr(10) + "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34) + Chr(10)
    ' An Integer index avoids brs-node's unrelated LongInteger for-loop gap.
    for offset = 0 to count - 1
        sequence = first + offset
        if special = "map" and sequence = 13 then text += "#EXT-X-MAP:URI=" + Chr(34) + "other.mp4" + Chr(34) + Chr(10)
        if special = "map" and sequence = 15 then text += "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34) + Chr(10)
        if special = "epoch" and (sequence = 13 or sequence = 15) then text += "#EXT-X-DISCONTINUITY" + Chr(10)
        text += "#EXTINF:" + duration + "," + Chr(10) + "segment-" + sequence.ToStr() + ".m4s" + Chr(10)
    end for
    return text
end function

sub pairCore(state as object, sequence as integer, nowMs as dynamic)
    item = m.corpus.media[sequence - 10]
    input = bytesCore(item.input.hex)
    nativeLiveFeed(state, "segment", input, nowMs)
    nativeLiveAdvance(state, nowMs)
    nativeLiveAdvance(state, nowMs)
    saved = state.segments[nlSegmentIndex(state, sequence)]
    for each pair in [[saved.videoId, item.video], [saved.audioId, item.audio]]
        body = nativeLiveAcquire(state, pair[0])
        checkCore(body <> invalid, "new converted body is registered")
        goldenCore(body.data, pair[1], "converted " + body.kind)
        nativeLiveRelease(state, pair[0])
    end for
    checkCore(nlBodyDigest(input) = item.input.sha256 and state.input = invalid and state.temporaryVideo = invalid, "combined input unchanged and scratch buffers released")
    m.pairs += 1
end sub

function preparedCore(steady = true as boolean, duration = "2.000000" as string, target = 2 as integer, count = 3 as integer) as object
    state = newCore(steady)
    nativeLiveFeed(state, "playlist", playlistCore(10&, count, "", duration, target), 0&)
    input = bytesCore(m.corpus.init.input.hex)
    nativeLiveFeed(state, "init", input, 0&)
    nativeLiveAdvance(state, 0&)
    nativeLiveAdvance(state, 0&)
    for each pair in [[state.initIds[0], m.corpus.init.video], [state.initIds[1], m.corpus.init.audio]]
        body = nativeLiveAcquire(state, pair[0])
        goldenCore(body.data, pair[1], "converted init")
        nativeLiveRelease(state, pair[0])
    end for
    checkCore(nlBodyDigest(input) = m.corpus.init.input.sha256, "init input immutable")
    for sequence = 10 to 9 + count
        pairCore(state, sequence, 0&)
    end for
    return state
end function

sub retireCore(state as object)
    advertised = []
    for each generation in state.generations
        if generation.advertised then advertised.Push(generation.id)
    end for
    for each id in advertised
        nativeLiveRetire(state, id)
    end for
end sub

sub closeCore(state as object)
    retireCore(state)
    checkCore(nativeLiveClose(state), "actual helper accepts retired/unleased close")
    checkCore(state.closed and state.assets.Count() = 0 and state.cacheBytes = 0 and state.input = invalid and state.sourceUrl = "", "actual close clears cache/source/scratch")
end sub

sub manifestDurationCore(pub as object, duration as string)
    for each track in ["video", "audio"]
        body = loopbackManifest(track, pub)
        checkCore(body <> invalid, "accepted fractional publication renders " + track + " manifest")
        text = body.ToAsciiString()
        lines = text.Split(Chr(10))
        targets = 0
        durations = 0
        for each line in lines
            if line.Left(22) = "#EXT-X-TARGETDURATION:"
                checkCore(line = "#EXT-X-TARGETDURATION:2", "local target2 remains constant across tracks and generations")
                targets += 1
            end if
            if line.Left(8) = "#EXTINF:"
                checkCore(line = "#EXTINF:" + duration + ",", "exact fractional EXTINF is preserved")
                durations += 1
            end if
        end for
        checkCore(targets = 1 and durations = pub.segments.Count(), "one local target and every exact duration advertised")
        checkCore(text.InStr("#EXT-X-MEDIA-SEQUENCE:" + pub.mediaSequence.ToStr() + Chr(10)) >= 0, "actual generation sequence rendered")
    end for
end sub

sub publicationDurationCore()
    for each item in [{ duration: "2.002", micros: 2002000, target: 6, count: 3 }, { duration: "2.499999", micros: 2499999, target: 2, count: 3 }, { duration: "1.499999", micros: 1499999, target: 1, count: 5 }]
        state = preparedCore(true, item.duration, item.target, item.count)
        first = nativeLivePublication(state)
        checkCore(loopbackDurationUs(item.duration) = item.micros and loopbackPublicationValid(first), "actual fractional Core publication accepted " + item.duration)
        checkCore(first.targetDuration = item.target and first.durationUs = item.micros * item.count and first.segments.Count() = item.count and not first.ended, "actual fractional aggregate retains live readiness floor")
        for each segment in first.segments
            checkCore(segment.duration = item.duration and segment.durationUs = item.micros, "producer exact decimal and microseconds agree")
        end for
        manifestDurationCore(first, item.duration)
        nowMs = item.target * 1000&
        nativeLiveFeed(state, "playlist", playlistCore(11&, item.count, "", item.duration, item.target), nowMs)
        pairCore(state, 10 + item.count, nowMs)
        nextPub = nativeLivePublication(state)
        checkCore(loopbackPublicationValid(nextPub) and nextPub.generation = first.generation + 1& and nextPub.mediaSequence = first.mediaSequence + 1&, "actual fractional next generation remains contiguous")
        manifestDurationCore(nextPub, item.duration)
        closeCore(state)
    end for
    for each item in [{ duration: "2.500000", target: 6, count: 3, label: "local half-second boundary" }, { duration: "2.500001", target: 6, count: 3, label: "local above-half boundary" }, { duration: "3.000000", target: 6, count: 3, label: "local longer segment" }, { duration: "1.500000", target: 1, count: 4, label: "source half-second boundary" }, { duration: "1.500001", target: 1, count: 4, label: "source above-half boundary" }]
        state = preparedCore(true, item.duration, item.target, item.count)
        pub = nativeLivePublication(state)
        checkCore(pub.durationUs >= 6000000 and loopbackDurationUs(item.duration) > 0, "rejected duration has valid live window and decimal")
        checkCore(not loopbackPublicationValid(pub), "publication rejects " + item.label)
        checkCore(loopbackManifest("video", pub) = invalid and loopbackManifest("audio", pub) = invalid, "rejected duration never reaches either manifest")
        closeCore(state)
    end for
    state = preparedCore(true, "2.002", 6)
    pub = nativeLivePublication(state)
    for each label in ["malformed", "precision", "mismatched micros", "sum", "sequence", "live floor", "source target cap"]
        bad = nativeLivePublication(state)
        checkCore(loopbackPublicationValid(bad), "actual negative-control baseline is valid " + label)
        segments = bad.segments
        segment = segments[0]
        if label = "malformed"
            segment.duration = "2.002x"
        else if label = "precision"
            segment.duration = "2.0020000"
        else if label = "mismatched micros"
            segment.durationUs += 1
            bad.durationUs += 1
        else if label = "sum"
            bad.durationUs += 1
        else if label = "sequence"
            segment.sequence += 1
        else if label = "live floor"
            for index = 0 to segments.Count() - 1
                shorter = segments[index]
                shorter.duration = "1.999999"
                shorter.durationUs = 1999999
                segments[index] = shorter
            end for
            segment = segments[0]
            bad.durationUs = 5999997
        else if label = "source target cap"
            bad.targetDuration = 11
        end if
        segments[0] = segment
        bad.segments = segments
        checkCore(not loopbackPublicationValid(bad), "fractional publication retains " + label + " rejection")
        checkCore(loopbackManifest("video", bad) = invalid and loopbackManifest("audio", bad) = invalid, "invalid fractional publication emits no manifests " + label)
    end for
    shortPub = nativeLivePublication(state)
    segments = shortPub.segments
    shortPub.segments = [segments[0]]
    shortPub.durationUs = segments[0].durationUs
    checkCore(not loopbackPublicationValid(shortPub), "short fractional live publication remains rejected")
    shortPub.ended = true
    checkCore(loopbackPublicationValid(shortPub), "short ended fractional publication remains accepted")
    for each track in ["video", "audio"]
        body = loopbackManifest(track, shortPub)
        checkCore(body <> invalid, "short ended fractional manifest is produced")
        text = body.ToAsciiString()
        checkCore(text.InStr("#EXTINF:2.002," + Chr(10)) >= 0 and text.Right(15) = "#EXT-X-ENDLIST" + Chr(10), "short ended manifest retains exact duration and ENDLIST")
    end for
    closeCore(state)
    caseCore("rounded-publication-duration-and-stable-manifests")
end sub

function startupPlaylistCore(first as longinteger, count as integer, boundary as longinteger, kind as string, ended = false as boolean) as string
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:6" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:" + first.ToStr() + Chr(10) + "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34) + Chr(10)
    for offset = 0 to count - 1
        sequence = first + offset
        if sequence = boundary
            if kind = "map" or kind = "both" then text += "#EXT-X-MAP:URI=" + Chr(34) + "new-init.mp4" + Chr(34) + Chr(10)
            if kind = "epoch" or kind = "both" then text += "#EXT-X-DISCONTINUITY" + Chr(10)
        end if
        text += "#EXTINF:2.002," + Chr(10) + "segment-" + sequence.ToStr() + ".m4s" + Chr(10)
    end for
    if ended then text += "#EXT-X-ENDLIST" + Chr(10)
    return text
end function

function feedReasonCore(state as object, text as string, nowMs as dynamic) as string
    reason = ""
    try
        nativeLiveFeed(state, "playlist", text, nowMs)
    catch e
        reason = e.message
    end try
    return reason
end function

sub startupEmptyCore(state as object)
    checkCore(state.phase = "playlist" and state.window = invalid and nativeLivePublication(state) = invalid, "mixed startup waits without assigning a window or publication")
    checkCore(state.mapUrl = "" and state.epoch = -1& and state.tracks = invalid and state.initIds.Count() = 0, "mixed startup retains uninitialized timeline")
    checkCore(state.assets.Count() = 0 and state.segments.Count() = 0 and state.generations.Count() = 0 and state.cacheBytes = 0 and state.latest = 0, "mixed startup allocates no converted assets or generations")
    checkCore(state.input = invalid and state.temporaryVideo = invalid and state.pendingWindow = invalid and state.pendingSegment = invalid and state.pendingPlaylistSequence = -1&, "mixed startup retains no input or pending initialization")
    checkCore(not state.started and state.publishedLast = -1& and state.initPairCount = 0 and state.segmentPairCount = 0, "mixed startup never claims readiness or conversion")
    checkCore(state.deadline = 45000&, "startup wait keeps absolute deadline")
end sub

sub startupWindowCore()
    for each kind in ["map", "epoch", "both"]
        for each delay in [0, 4]
            state = newCore(true, 0&, delay)
            count = 4
            if delay > 0 then count += 2
            m.config = { sourceDelaySeconds: delay }
            for pass = 0 to 1
                nowMs = pass * 3000&
                reason = feedReasonCore(state, startupPlaylistCore(10& + pass, count, 13&, kind), nowMs)
                checkCore(reason = "", "validated mixed startup waits for coherent tail")
                startupEmptyCore(state)
                checkCore(state.lastPlaylistSequence = 10& + pass and state.playlistCount = pass + 1 and state.nextPoll = nowMs + 3000&, "waiting source sequence and bounded poll accounting retained")
                checkCore(nlIntent(state, nowMs + 2999&) = invalid, "startup wait suppresses early playlist intent")
                intent = nlIntent(state, nowMs + 3000&)
                checkCore(intent <> invalid and intent.kind = "playlist" and intent.limit = 262144, "startup wait permits exact due playlist intent")
            end for
            nativeLiveFeed(state, "playlist", startupPlaylistCore(12&, count, 13&, kind), 6000&)
            checkCore(state.phase = "init" and state.window.segments.Count() = 3 and state.window.segments[0].sequence = 13& and state.window.segments[2].sequence = 15&, "only coherent delayed latest cohort enters init")
            expectedMap = "https://cdn.example.invalid/init.mp4"
            if kind = "map" or kind = "both" then expectedMap = "https://cdn.example.invalid/new-init.mp4"
            initIntent = nlIntent(state, 6000&)
            checkCore(initIntent.kind = "init" and initIntent.url = expectedMap and state.mapUrl = expectedMap, "fresh initialization uses selected cohort map")
            expectedEpoch = 0&
            if kind = "epoch" or kind = "both" then expectedEpoch = 1&
            checkCore(state.epoch = expectedEpoch and state.initIds.Count() = 0 and state.segmentPairCount = 0, "new epoch owns no converted older media")
            input = bytesCore(m.corpus.init.input.hex)
            nativeLiveFeed(state, "init", input, 6000&)
            nativeLiveAdvance(state, 6000&)
            nativeLiveAdvance(state, 6000&)
            for each pair in [[state.initIds[0], m.corpus.init.video], [state.initIds[1], m.corpus.init.audio]]
                asset = nativeLiveAcquire(state, pair[0])
                goldenCore(asset.data, pair[1], "waiting startup actual fresh init")
                nativeLiveRelease(state, pair[0])
            end for
            for sequence = 13 to 15
                pairCore(state, sequence, 6000&)
            end for
            pub = nativeLivePublication(state)
            expectedOffset = 0&
            if delay > 0 then expectedOffset = 4004000&
            checkCore(loopbackPublicationValid(pub) and pub.mediaSequence = 13& and pub.durationUs = 6006000 and pub.sourceOffsetUs = expectedOffset and pub.segments.Count() = 3, "coherent startup publication preserves delayed source offset")
            checkCore(state.started and state.publishedFirst = 13& and state.publishedLast = 15& and state.segmentPairCount = 3 and state.playlistCount = 3, "only selected fresh sequences publish once")
            for each segment in state.segments
                checkCore(segment.sequence >= 13& and segment.sequence <= 15&, "older coherent media never converted as fallback")
            end for
            manifestDurationCore(pub, "2.002")
            closeCore(state)
        end for
    end for
    m.config = { sourceDelaySeconds: 0 }
    text = startupPlaylistCore(10&, 4, 13&, "both")
    for each mode in ["finite", "ended", "ready", "started", "published", "initialized"]
        state = newCore(mode <> "finite")
        payload = text
        if mode = "ended" then payload = startupPlaylistCore(10&, 4, 13&, "both", true)
        if mode = "ready" then state = preparedCore()
        if mode = "started" then state.started = true
        if mode = "published" then state.publishedLast = 12&
        if mode = "initialized" then state.initIds = ["live-1", "live-2"]
        nowMs = 3000&
        reason = feedReasonCore(state, payload, nowMs)
        checkCore(reason = "native-live: selected window crosses map or discontinuity", "startup sentinel remains disabled for " + mode)
        closeCore(state)
    end for
    parsed = nativeLiveParsePlaylist(text, "https://cdn.example.invalid/live.m3u8")
    reason = ""
    try
        unused = nlWindow(parsed, 0&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: selected window crosses map or discontinuity", "default window selection retains hard boundary refusal")
    for each item in [{ text: playlistCore(10&, 2), delay: 0, reason: "six-second source window unavailable" }, { text: startupPlaylistCore(10&, 4, 13&, "both"), delay: 60, reason: "requested source delay unavailable" }, { text: playlistCore(10&, 9, "", "0.5"), delay: 0, reason: "window segment bound" }, { text: text + "#EXT-X-UNKNOWN:1" + Chr(10), delay: 0, reason: "HLS tag unsupported" }]
        state = newCore(true, 0&, item.delay)
        reason = feedReasonCore(state, item.text, 0&)
        checkCore(reason = "native-live: " + item.reason, "startup wait retains strict source guard " + item.reason)
        closeCore(state)
    end for
    ' Native character checks keep the original accepted sets.
    for each item in [{ old: "segment-11.m4s", new: "segment-11.m4s?a=b&c=~!$%25'()*+,;@", reason: "" }, { old: "#EXTM3U", new: "#EXTM3U" + Chr(9), reason: "playlist character unsupported" }, { old: "segment-11.m4s", new: "segment-11" + Chr(233) + ".m4s", reason: "playlist character unsupported" }, { old: "segment-11.m4s", new: "segment-11" + Chr(92) + ".m4s", reason: "URL character unsupported" }, { old: "segment-11.m4s", new: "segment-11.m4s#frag", reason: "URL character unsupported" }, { old: "segment-11.m4s", new: "segment 11.m4s", reason: "URL character unsupported" }]
        reason = ""
        try
            unused = nativeLiveParsePlaylist(playlistCore(10&, 3).Replace(item.old, item.new), "https://cdn.example.invalid/live.m3u8")
        catch e
            reason = e.message
        end try
        expected = ""
        if item.reason <> "" then expected = "native-live: " + item.reason
        checkCore(reason = expected, "native character check keeps the accepted set " + item.new)
    end for
    state = newCore()
    for pass = 0 to 14
        nowMs = pass * 3000&
        checkCore(feedReasonCore(state, text, nowMs) = "", "repeated valid mixed startup can wait under original deadline")
        startupEmptyCore(state)
    end for
    reason = ""
    try
        unused = nlIntent(state, 45000&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: finite runtime complete", "repeated startup waits cannot extend45s deadline")
    closeCore(state)
    state = newCore()
    nativeLiveFeed(state, "playlist", text, 0&)
    reason = feedReasonCore(state, startupPlaylistCore(9&, 5, 13&, "both"), 3000&)
    checkCore(reason = "native-live: playlist sequence moved backwards" and state.lastPlaylistSequence = 10&, "waiting source cursor still refuses playlist rollback")
    state.quotaTransfers = 255
    nlUseWork(state, "transfer", 3000&)
    reason = ""
    try
        nlUseWork(state, "transfer", 3000&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: steady work interval bound" and state.quotaTransfers = 256, "waiting startup retains existing transfer quota")
    closeCore(state)
    checkCore(state.closed and nlIntent(state, 3000&) = invalid, "stopped waiting startup cannot initiate another fetch")
    caseCore("bounded-fresh-startup-window-wait")
end sub

sub bulkCore()
    input = bytesCore(m.corpus.init.input.hex)
    tracks = nativeDemuxBulkInspectInit(input)
    checkCore(tracks.Count() = 2 and nbTrackKind(tracks, 7&) = "video" and nbTrackKind(tracks, 8&) = "audio", "actual AVC/AAC init track IDs")
    goldenCore(nativeDemuxBulkInit(input, "video"), m.corpus.init.video, "standalone video init")
    goldenCore(nativeDemuxBulkInit(input, "audio"), m.corpus.init.audio, "standalone audio init")
    checkCore(nlBodyDigest(input) = m.corpus.init.input.sha256, "standalone init immutable")
    for each item in m.corpus.negative
        source = bytesCore(item.input.hex)
        reason = ""
        try
            if item.operation = "init"
                unused = nativeDemuxBulkInit(source, item.keep)
            else
                unused = nativeDemuxBulkFragment(source, tracks, item.keep)
            end if
        catch e
            reason = e.message
        end try
        checkCore(reason = "native-demux: " + item.reason, "strict malformed " + item.name)
        checkCore(nlBodyDigest(source) = item.input.sha256, "rejected binary remains immutable")
    end for
    caseCore("binary-goldens-and-strict-malformed")
end sub

sub rollingCore()
    state = preparedCore()
    previous = nativeLivePublication(state)
    heldId = previous.segments[0].videoId
    held = nativeLiveAcquire(state, heldId)
    seen = {}
    for each asset in state.assets
        seen[asset.id] = true
    end for
    nativeLiveFeed(state, "playlist", playlistCore(10&), 1000&)
    nativeLiveAdvance(state, 1000&)
    repeated = nativeLivePublication(state)
    checkCore(repeated.generation = previous.generation and state.segmentPairCount = 3 and state.lastPublicationProgress = 0&, "repeated playlist never converts or manufactures new publication")
    for index = 3 to m.corpus.media.Count() - 1
        sequence = m.corpus.media[index].sequence
        nowMs = (sequence - 12) * 2000&
        nativeLiveFeed(state, "playlist", playlistCore(sequence - 2&), nowMs)
        pairCore(state, sequence, nowMs)
        current = nativeLivePublication(state)
        tail = current.segments[current.segments.Count() - 1]
        checkCore(loopbackPublicationValid(current) and current.generation = previous.generation + 1& and current.mediaSequence = sequence - 2& and tail.sequence = sequence, "real rolling publication remains contiguous")
        checkCore(not seen.DoesExist(tail.videoId) and not seen.DoesExist(tail.audioId), "new byte identities never reuse an old route")
        seen[tail.videoId] = true
        seen[tail.audioId] = true
        nativeLiveRetire(state, previous.generation)
        checkCore(state.assets.Count() <= 11 and state.generations.Count() = 1 and state.cacheBytes <= state.cacheBudgetBytes, "retirement bounds real registry/generations/cache")
        previous = current
    end for
    checkCore(seen.Count() > 256 and previous.generation > 256 and nowMs > 45000& and state.segmentPairCount = m.corpus.media.Count(), "actual binary pipeline exceeds old ID/generation/time limits")
    checkCore(nlBodyDigest(held.data) = m.corpus.media[0].video.sha256, "acquired old body stays exact through rolling retirement")
    checkCore(nativeLiveAcquire(state, "live-1") = invalid, "legacy route cannot alias a steady session")
    retireCore(state)
    checkCore(not nativeLiveClose(state) and not state.closed and nlAssetIndex(state, heldId) >= 0, "retired active lease alone prevents close")
    nativeLiveRelease(state, heldId)
    checkCore(nativeLiveAcquire(state, heldId) = invalid, "released expired ID never resolves to newer bytes")
    m.uniqueIds = seen.Count()
    m.generations = previous.generation
    m.elapsedMs = nowMs
    closeCore(state)
    caseCore("rolling-past-finite-limits-with-held-lease")
end sub

sub continuityCore()
    for each count in [7, 8, 11]
        state = preparedCore()
        first = nativeLivePublication(state)
        nativeLiveFeed(state, "playlist", playlistCore(10&, count), 2000&)
        checkCore(state.window.segments[0].sequence = 13 and state.window.segments.Count() <= 8, "poll gap extends exactly to first unpublished sequence")
        finalSequence = 10 + count - 1
        for sequence = 13 to finalSequence
            pairCore(state, sequence, 2000&)
        end for
        current = nativeLivePublication(state)
        checkCore(current.mediaSequence = 13 and current.segments.Count() = count - 3 and state.segmentPairCount = count, "every intervening pair converted before contiguous publication")
        nativeLiveRetire(state, first.generation)
        closeCore(state)
    end for
    for each item in [{ first: 10&, count: 12, special: "", reason: "continuity window segment bound" }, { first: 14&, count: 5, special: "", reason: "continuity history unavailable" }, { first: 10&, count: 8, special: "map", reason: "continuity window crosses map or discontinuity" }, { first: 10&, count: 8, special: "epoch", reason: "continuity window crosses map or discontinuity" }]
        state = preparedCore()
        unused = nativeLivePublication(state)
        reason = ""
        try
            nativeLiveFeed(state, "playlist", playlistCore(item.first, item.count, item.special), 2000&)
        catch e
            reason = e.message
        end try
        checkCore(reason = "native-live: " + item.reason and state.segmentPairCount = 3, "missing/oversize/cross-epoch history never skips source")
        closeCore(state)
    end for
    caseCore("poll-gaps-contiguous-and-fail-closed")
end sub

sub admissionCore()
    ' Exact arithmetic checks, not a claim that multi-MiB allocation occurred.
    for each cap in [16777216&, 25165824&, 33554432&]
        nlCheckPairCacheBudget(cap - 2&, 2&, cap)
        reason = ""
        try
            nlCheckPairCacheBudget(cap - 1&, 2&, cap)
        catch e
            reason = e.message
        end try
        checkCore(reason = "native-live: cache byte budget exceeded", "pair admission rejects first byte above explicit cap")
    end for
    state = newCore()
    acquired = []
    for index = 1 to 32
        ids = nlStorePair(state, bytesCore("10"), bytesCore("20"))
        for each id in ids
            unused = nativeLiveAcquire(state, id)
            acquired.Push(id)
        end for
    end for
    before = { serial: state.serial, bytes: state.cacheBytes, count: state.assets.Count() }
    reason = ""
    try
        unused = nlStorePair(state, bytesCore("30"), bytesCore("40"))
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: cache asset count bound" and state.serial = before.serial and state.cacheBytes = before.bytes and state.assets.Count() = before.count, "actual registered64 pair admission is atomic")
    checkCore(not nativeLiveClose(state), "real acquired registry prevents close")
    for each id in acquired
        nativeLiveRelease(state, id)
    end for
    closeCore(state)
    state = preparedCore()
    pub = nativeLivePublication(state)
    id = pub.initVideoId
    body = nativeLiveAcquire(state, id)
    saved = body.data[0]
    body.data[0] = (saved + 1) mod 256
    reason = ""
    try
        unused = nativeLiveAcquire(state, id)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: cached asset mutated", "actual returned body mutation fails SHA guard before another lease")
    body.data[0] = saved
    nativeLiveRelease(state, id)
    reason = ""
    try
        nativeLiveRelease(state, id)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: release without lease", "double release cannot fabricate cleanup")
    for index = 1 to 8
        unused = nativeLiveAcquire(state, id)
    end for
    reason = ""
    try
        unused = nativeLiveAcquire(state, id)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: asset lease bound", "ninth actual acquired lease is rejected")
    for index = 1 to 8
        nativeLiveRelease(state, id)
    end for
    closeCore(state)
    caseCore("actual-cache-leases-and-atomic-admission")
end sub

sub generationPinsCore()
    state = preparedCore()
    first = nativeLivePublication(state)
    for sequence = 13 to 23
        nowMs = (sequence - 12) * 2000&
        nativeLiveFeed(state, "playlist", playlistCore(sequence - 2&), nowMs)
        pairCore(state, sequence, nowMs)
        unused = nativeLivePublication(state)
    end for
    checkCore(state.generations.Count() = 12 and state.latest = 12 and nlAssetIndex(state, first.segments[0].videoId) >= 0, "twelve advertised generations retain their real old bodies")
    nativeLiveFeed(state, "playlist", playlistCore(22&), 24000&)
    reason = ""
    try
        pairCore(state, 24, 24000&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: publication generation bound" and state.generations.Count() = 12 and state.latest = 12, "thirteenth live generation cannot overwrite advertised publication")
    checkCore(not nativeLiveClose(state), "advertised generations prevent actual close")
    closeCore(state)
    caseCore("active-publication-generation-cap")
end sub

sub clockQuotaCore()
    clock = nativeLiveClockCreate(2147483640&)
    checkCore(nativeLiveClockAdvance(clock, -2147483640&) = 16&, "signed32 transition retains monotonic elapsed")
    clock = nativeLiveClockCreate(4294967290&)
    checkCore(nativeLiveClockAdvance(clock, 5) = 11&, "full32 wrap retains monotonic elapsed")
    for each raw in [99, 60101, 101.0]
        clock = nativeLiveClockCreate(100)
        reason = ""
        try
            unused = nativeLiveClockAdvance(clock, raw)
        catch e
            reason = e.message
        end try
        checkCore(reason.Left(13) = "native-live: " and clock.elapsed = 0& and clock.raw = 100&, "rollback/gap/nonintegral clock rejected without advance")
    end for
    clock = nativeLiveClockCreate(0)
    clock.elapsed = 4294967235000&
    reason = ""
    try
        unused = nativeLiveClockAdvance(clock, 1)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: clock exhausted", "long clock explicitly exhausts")
    state = newCore(true, 2147483640&)
    nlTime(state, 2147483650&)
    checkCore(state.lastNow = 2147483650& and state.deadline = 2147528640&, "steady timestamp does not truncate to Integer")
    closeCore(state)
    state = newCore()
    for index = 1 to 12000
        nlUseWork(state, "tick", 0&)
    end for
    reason = ""
    try
        nlUseWork(state, "tick", 0&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: steady work interval bound" and state.steps = 12000&, "steady work quota denies overuse without cumulative charge")
    nlUseWork(state, "tick", 60000&)
    checkCore(state.steps = 12001& and state.quotaSteps = 1, "bounded interval renewal exceeds old lifetime step limit")
    for index = 1 to 256
        nlUseWork(state, "transfer", 60000&, false)
        nlUseWork(state, "transfer", 60000&)
    end for
    reason = ""
    try
        nlUseWork(state, "transfer", 60000&, false)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: steady work interval bound" and state.transfers = 256&, "precheck does not consume and transfer interval remains bounded")
    nlUseWork(state, "transfer", 120000&)
    checkCore(state.transfers = 257& and state.quotaTransfers = 1, "bounded renewal exceeds old lifetime transfer count")
    state.transfers = 4294967295&
    reason = ""
    try
        nlUseWork(state, "transfer", 120000&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: integer bound" and state.transfers = 4294967295&, "counter exhaustion never wraps or hides evidence")
    state.serial = 4294967293&
    ids = nlStorePair(state, bytesCore("10"), bytesCore("20"))
    checkCore(ids[1].Right(10) = "4294967295" and loopbackAssetId(ids[1]), "terminal long asset identity is valid")
    reason = ""
    try
        unused = nlStorePair(state, bytesCore("10"), bytesCore("20"))
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: cache asset count bound" and state.serial = 4294967295&, "exhausted serial cannot reuse previous route")
    closeCore(state)
    caseCore("monotonic-long-clock-quotas-and-exhaustion")
end sub

sub staleTailCore()
    for each retained in [true, false]
        state = preparedCore()
        initial = nativeLivePublication(state)
        nativeLiveFeed(state, "playlist", playlistCore(10&, 6), 2000&)
        for sequence = 13 to 15
            pairCore(state, sequence, 2000&)
        end for
        current = nativeLivePublication(state)
        if not retained then nativeLiveRetire(state, initial.generation)
        checkCore((nlSegmentIndex(state, 12&) >= 0) = retained, "stale-tail case has requested cache retention")
        beforeWindow = FormatJson(state.window)
        beforeSegments = FormatJson(state.segments)
        beforeBytes = state.cacheBytes
        beforeSerial = state.serial
        beforeGenerations = FormatJson(state.generations)
        nativeLiveFeed(state, "playlist", playlistCore(10&, 5), 4000&)
        nativeLiveAdvance(state, 4000&)
        checkCore(state.phase = "ready" and FormatJson(state.window) = beforeWindow and state.publishedFirst = 13& and state.publishedLast = 15&, "stale tail preserves published window and bounds")
        checkCore(FormatJson(nativeLivePublication(state)) = FormatJson(current) and FormatJson(state.generations) = beforeGenerations and state.nextGeneration = current.generation + 1&, "stale tail preserves publication and generation")
        checkCore(state.lastUpstreamProgress = 2000& and state.lastPublicationProgress = 2000& and state.lastPlaylistSequence = 10&, "stale tail cannot refresh progress")
        checkCore(FormatJson(state.segments) = beforeSegments and state.cacheBytes = beforeBytes and state.serial = beforeSerial and state.segmentPairCount = 6, "stale tail never converts or prunes cached history")
        checkCore(state.nextPoll = 5000& and nlIntent(state, 4999&) = invalid, "stale tail preserves fallback polling floor")
        nativeLiveFeed(state, "playlist", playlistCore(10&, 6), 5000&)
        nativeLiveAdvance(state, 5000&)
        checkCore(state.lastUpstreamProgress = 5000& and state.lastPublicationProgress = 2000& and FormatJson(nativeLivePublication(state)) = FormatJson(current), "unchanged tail still refreshes upstream health without publication")
        nativeLiveFeed(state, "playlist", playlistCore(10&, 7), 6000&)
        pairCore(state, 16, 6000&)
        nextPub = nativeLivePublication(state)
        checkCore(nextPub.generation = current.generation + 1& and nextPub.mediaSequence = 14& and state.publishedLast = 16& and state.segmentPairCount = 7, "forward tail resumes once without replaying stale media")
        closeCore(state)
    end for
    caseCore("shorter-tail-discard-before-cached-history")
end sub

sub finiteLivenessCore()
    state = preparedCore(false)
    pub = nativeLivePublication(state)
    checkCore(not state.steadyMode and state.cacheBudgetBytes = 16777216 and pub.initVideoId = "live-1", "default finite mode and old namespace remain unchanged")
    reason = ""
    try
        nlTime(state, 45000)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: finite runtime complete", "finite default45s guard remains")
    closeCore(state)
    state = preparedCore()
    pub = nativeLivePublication(state)
    for each stamp in [14000&, 28000&]
        nativeLiveFeed(state, "playlist", playlistCore(10&), stamp)
        nativeLiveAdvance(state, stamp)
    end for
    reason = ""
    try
        nlTime(state, 30000&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: publication progress deadline" and state.lastUpstreamProgress = 28000& and state.lastPublicationProgress = 0&, "accepted unchanged playlists cannot hide publication stall")
    closeCore(state)
    state = preparedCore()
    reason = ""
    try
        nlTime(state, 15000&)
    catch e
        reason = e.message
    end try
    checkCore(reason = "native-live: upstream progress deadline", "real upstream-progress deadline remains finite")
    closeCore(state)
    caseCore("finite-default-and-real-progress-deadlines")
end sub

sub main()
    m.assertions = 0
    m.cases = 0
    m.goldens = 0
    m.pairs = 0
    m.uniqueIds = 0
    m.generations = 0
    m.elapsedMs = 0&
    m.config = { sourceDelaySeconds: 0 }
    try
        m.corpus = ParseJSON(ReadAsciiFile("pkg:/corpus.json"))
        bulkCore()
        publicationDurationCore()
        startupWindowCore()
        rollingCore()
        continuityCore()
        admissionCore()
        generationPinsCore()
        clockQuotaCore()
        staleTailCore()
        finiteLivenessCore()
        print "STITCH_ROKU_CORE_PASS: __MARKER__ cases="; m.cases; " assertions="; m.assertions; " pairs="; m.pairs; " goldens="; m.goldens; " ids="; m.uniqueIds; " generations="; m.generations; " elapsedMs="; m.elapsedMs
    catch e
        print "STITCH_ROKU_CORE_FAIL: "; e.message
    end try
end sub
