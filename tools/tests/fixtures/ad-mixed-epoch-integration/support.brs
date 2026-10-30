function eiDescriptor() as object
    return {version: 1, sourceUrl: "https://canned.ttvnw.net/live/source.m3u8?token=fixtureSignature", qualityId: "1080p60", approvedOrigins: ["https://canned.ttvnw.net"],
        metadata: {videoCodec: "avc1.4D402A", audioCodec: "mp4a.40.2", width: 1920, height: 1080, frameRate: "60.000", bandwidth: 8042999, isHD: true}}
end function

function eiRequest(path as string, method = "GET" as string, range = "" as string) as string
    crlf = Chr(13) + Chr(10)
    result = method + " " + path + " HTTP/1.1" + crlf + "Host: 127.0.0.1:49371" + crlf
    if range <> "" then result += "Range: " + range + crlf
    return result + crlf
end function

sub eiReset(raw = "" as string, transitions = true as boolean)
    m.events = []
    m.observers = []
    m.top = {sessionId: "0123456789abcdef0123456789abcdef", inputDescriptor: eiDescriptor(), enableSourceTransitions: transitions, experimentalMode: true, cacheBudgetBytes: 16777216, listenPort: 49371, stopRequested: false,
        ObserveField: eiObserve, UnobserveField: eiUnobserve, observers: m.observers}
    m.sessionId = m.top.sessionId
    m.clockValues = [2000, 0]
    m.clock = {values: m.clockValues, index: 0, TotalMilliseconds: eiClock}
    m.requestClock = {values: m.clockValues, index: 1, TotalMilliseconds: eiClock}
    m.monotonicClock = nativeLiveClockCreate(0)
    m.lastNowMs = 0&
    m.steadyMode = true
    m.sourceTransitions = transitions
    m.adMetadataEnabled = true
    m.cacheBudgetBytes = 16777216
    m.listenPort = 49371
    m.httpQuota = liveQuotaCreate(0&)
    m.counterExhausted = false
    m.closing = false
    m.port = CreateObject("roMessagePort")
    incoming = CreateObject("roByteArray")
    incoming.FromAsciiString(raw)
    outgoing = CreateObject("roByteArray")
    m.io = [incoming, 0, outgoing, m.events, [], [false], ""]
    if raw.InStr("/asset/") >= 0 then m.io[6] = raw.Split(" ")[1].Mid(7)
    m.connection = {io: m.io, GetCountRcvBuf: eiReceiveCount, IsReadable: eiReadable, Receive: eiReceive, IsWritable: eiWritable, Send: eiSend, eOK: eiSocketOk, NotifyReadable: eiNotify, NotifyWritable: eiNotify, Close: eiSocketClose}
    m.listener = invalid
    m.liveState = invalid
    m.config = invalid
    m.currentPublication = invalid
    m.currentGeneration = 0&
    m.publications = {}
    m.activeLease = ""
    m.adHeldId = ""
    m.validationLease = ""
    m.activeGeneration = 0&
    m.activeBody = invalid
    m.initMasterMetadata = invalid
    m.initMasterTiming = invalid
    m.lastDiagnostics = invalid
    m.decodeCount = 0
    m.decoderAllowed = true
    m.stopDuringDecode = false
    m.result = {ok: false, status: "failed", reason: "not_started", actualInitValidated: false, decoderApproved: false, cleanupOk: true,
        requests: 1&, completedRequests: 0&, transmittedBytes: 0&, sendCalls: 0&, shortWrites: 0&, receiveCalls: 0&, retryableReceives: 0&, bufferLogicalCount: 0&, headerBytesPeak: 0&,
        headRequests: 0&, rangeRequests: 0&, masterRequests: 0&, videoPlaylistRequests: 0&, audioPlaylistRequests: 0&, videoBodies: 0&, audioBodies: 0&, urlEventsHandled: 0&, pumpCalls: 0&,
        retiredPublications: 0&, publicationsObserved: 0&, deliveredPublications: 0&, maxPinnedGenerations: 0&, cacheBytesPeak: 0&, convertedSegmentPairs: 0&, upstreamFetchCount: 0&, upstreamPlaylistCount: 0&,
        clientErrors: 0&, errorResponses: 0&, lastClientReason: "", countersComplete: true, connectionClosed: false}
end sub

function rowEI(sequence as integer, mode = "" as string) as object
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

function playlistEI(first as integer, count as integer, mode = "" as string, ended = false as boolean) as string
    row = rowEI(first, mode)
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:6" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:" + first.ToStr() + Chr(10)
    text += "#EXT-X-DISCONTINUITY-SEQUENCE:" + (row.epoch + 27&).ToStr() + Chr(10)
    text += "#EXT-X-DATERANGE:ID=" + Chr(34) + "PRIVATE_CUE" + Chr(34) + ",CLASS=" + Chr(34) + "twitch-stitched-ad" + Chr(34) + ",START-DATE=" + Chr(34) + "2026-01-01T00:00:06.006000Z" + Chr(34) + ",DURATION=6.006000" + Chr(10)
    previous = invalid
    for i = 0 to count - 1
        sequence = first + i
        row = rowEI(sequence, mode)
        if previous = invalid or row.name <> previous.name or row.epoch <> previous.epoch
            if previous <> invalid and row.epoch <> previous.epoch then text += "#EXT-X-DISCONTINUITY" + Chr(10)
            text += "#EXT-X-MAP:URI=" + Chr(34) + row.name + ".mp4" + Chr(34) + Chr(10)
        end if
        text += "#EXT-X-PROGRAM-DATE-TIME:" + m.adDates[sequence - 10] + Chr(10)
        text += "#EXTINF:2.002000," + Chr(10) + "segment-" + sequence.ToStr() + ".m4s" + Chr(10)
        previous = row
    end for
    if ended then text += "#EXT-X-ENDLIST" + Chr(10)
    return text
end function

function bytesEI(record as object) as object
    body = CreateObject("roByteArray")
    body.FromHexString(record.hex)
    return body
end function

sub checkEI(ok as boolean, message as string)
    m.assertions += 1
    if not ok then throw "epoch-integration-fixture: " + message
end sub

sub caseEI(name as string)
    m.cases.Push(name)
    print "STITCH_EPOCH_INTEGRATION_CASE: " + name
end sub

sub createEI(transitions = true as boolean)
    eiReset("", transitions)
    m.clockValues[0] = 0&
    checkEI(prepareRokuDemuxInput(), "typed Task policy validates actual descriptor")
    options = liveSteadyOptions()
    keys = ["mode", "sessionId"]
    if transitions then keys.Push("sourceTransitions")
    checkEI(loopbackKeys(options, keys), "actual policy emits only exact authorized options")
    m.liveState = nativeLiveCreate(m.config.trustedMediaUrl, 0&, 0, m.config.approvedOrigins, true, m.cacheBudgetBytes, options)
    checkEI(m.liveState.sourceTransitions = transitions, "actual Core receives typed policy")
    m.liveState.adClockEnabled = true
end sub

sub feedEI(state as object, kind as string, payload as dynamic, nowMs as dynamic)
    m.liveState = state
    if kind = "playlist"
        adFeedPlaylist(state, payload, nowMs)
        return
    end if
    checkEI(rokuDemuxFeedInput(state, kind, payload, nowMs), "actual Fetch feed accepts approved bytes")
    m.liveState = state
end sub

sub drainEI(state as object, nowMs as dynamic)
    steps = 0
    while state.phase <> "ready" and state.phase <> "ended"
        checkEI(steps < 60, "finite exact production stage drain")
        if state.phase = "init" or state.phase = "init-rotation"
            intent = nlIntent(state, nowMs)
            name = "content"
            if intent.url.InStr("/ad.mp4") >= 0 then name = "ad"
            oldPair = state.initIds
            oldTracks = FormatJson(state.tracks)
            oldMaster = FormatJson(m.config.metadata)
            oldCalls = m.decodeCount
            record = m.corpus.inits[name]
            feedEI(state, "init", bytesEI(record.input), nowMs)
            checkEI(m.decodeCount = oldCalls + 1 and m.result.actualInitValidated and m.result.decoderApproved, "actual byte/device gate precedes real Core init staging")
            checkEI(state.phase = "init-video" and state.input <> invalid, "approved actual Core init stages conversion")
            if oldPair.Count() = 2
                checkEI(FormatJson(state.initIds) = FormatJson(oldPair) and FormatJson(state.tracks) = oldTracks and FormatJson(m.config.metadata) = oldMaster, "old init and immutable master retained before atomic split")
            end if
            nativeLiveAdvance(state, nowMs)
            if oldPair.Count() = 2 then checkEI(FormatJson(state.initIds) = FormatJson(oldPair), "one output cannot install changed pair")
            nativeLiveAdvance(state, nowMs)
            m.liveState = state
            for each pair in [[state.initIds[0],record.video],[state.initIds[1],record.audio]]
                body = nativeLiveAcquire(state,pair[0])
                checkEI(body <> invalid and nlBodyDigest(body.data) = pair[1].sha256 and LCase(body.data.ToHexString()) = pair[1].hex, "complete independent initialization split golden")
                nativeLiveRelease(state,pair[0])
                m.goldens += 1
            end for
            checkEI(state.input = invalid and state.pendingWindow = invalid and state.temporaryVideo = invalid, "atomic pair releases staging scratch")
        else if state.phase = "segment"
            missing = nlMissing(state)
            if missing = invalid
                nativeLiveAdvance(state,nowMs)
            else
                record = m.corpus.media[CInt(missing.sequence-10&)]
                feedEI(state,"segment",bytesEI(record.input),nowMs)
                nativeLiveAdvance(state,nowMs)
                nativeLiveAdvance(state,nowMs)
                saved = state.segments[nlSegmentIndex(state,missing.sequence)]
                for each pair in [[saved.videoId,record.video],[saved.audioId,record.audio]]
                    body = nativeLiveAcquire(state,pair[0])
                    checkEI(body <> invalid and nlBodyDigest(body.data) = pair[1].sha256 and LCase(body.data.ToHexString()) = pair[1].hex, "complete independent media/TFDT split golden")
                    nativeLiveRelease(state,pair[0])
                    m.goldens += 1
                end for
                m.pairs += 1
            end if
        else
            nativeLiveAdvance(state,nowMs)
        end if
        steps += 1
    end while
    m.liveState = state
end sub

sub admitEI(state as object, nowMs as dynamic)
    m.clockValues[0] = nowMs
    m.liveState = state
    checkEI(pumpLiveServer(1), "actual Server accepts actual Core generation and cached bodies")
    checkEI(m.currentGeneration = state.latest and loopbackPublicationValid(m.currentPublication), "same validated actual current generation")
    for each asset in state.assets
        checkEI(asset.leases = 0 or asset.id = m.activeLease or asset.id = m.adHeldId, "temporary validation leases released with actual held leases preserved")
    end for
    checkEI(state.op = invalid and state.transfers = 0, "offline fixture does not initiate a network transfer")
    m.admissions += 1
end sub

function preparedEI(transitions = true as boolean) as object
    createEI(transitions)
    state = m.liveState
    feedEI(state,"playlist",playlistEI(10,3),0&)
    drainEI(state,0&)
    admitEI(state,0&)
    return state
end function

sub closeEI(state as object)
    m.liveState = state
    closeLiveConnection()
    ids=[]
    for each generation in state.generations
        if generation.advertised then ids.Push(generation.id)
    end for
    for each id in ids
        nativeLiveRetire(state,id)
    end for
    checkEI(m.result.cleanupOk and nativeLiveClose(state), "actual Fetch/Core close after generation and socket cleanup")
    checkEI(state.closed and state.assets.Count() = 0 and state.segments.Count() = 0 and state.cacheBytes = 0 and state.input = invalid and state.pendingWindow = invalid and state.op = invalid and m.activeLease = "" and m.validationLease = "" and m.activeBody = invalid and m.connection = invalid, "actual typed cleanup clears all source/cache/request state")
end sub

sub socketEI(state as object, id as string, method="GET" as string)
    incoming=CreateObject("roByteArray")
    incoming.FromAsciiString(eiRequest("/asset/"+id,method,"bytes=0-3"))
    outgoing=CreateObject("roByteArray")
    m.io=[incoming,0,outgoing,m.events,state.assets,[false],id]
    m.connection={io:m.io,GetCountRcvBuf:eiReceiveCount,IsReadable:eiReadable,Receive:eiReceive,IsWritable:eiWritable,Send:eiSend,eOK:eiSocketOk,NotifyReadable:eiNotify,NotifyWritable:eiNotify,Close:eiSocketClose}
    m.result.reason="not_started"
    m.result.connectionClosed=false
end sub
