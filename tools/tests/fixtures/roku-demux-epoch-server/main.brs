sub main(args as object)
    m.assertions = 0
    m.cases = []
    m.corpus = ParseJson(ReadAsciiFile("pkg:/corpus.json"))
    try
        esInputPolicy()
        esInitCases()
        esPublicationCases()
        esRequestCases()
    catch error
        print "STITCH_EPOCH_SERVER_FAIL: __MARKER__ "; error.message
        return
    end try
    print "STITCH_EPOCH_SERVER_PASS: __MARKER__ "; FormatJson({assertions: m.assertions, cases: m.cases.Count()})
end sub

sub esAssert(ok as boolean, message as string)
    m.assertions += 1
    if not ok then throw "epoch-server-fixture: " + message
end sub

sub esCase(name as string)
    for each previous in m.cases
        if previous = name then throw "epoch-server-fixture: duplicate case"
    end for
    m.cases.Push(name)
    print "STITCH_EPOCH_SERVER_CASE: " + name
end sub

function esId(value as integer) as string
    return "live-0123456789abcdef0123456789abcdef-" + value.ToStr()
end function

function esDescriptor() as object
    return {version: 1, sourceUrl: "https://canned.ttvnw.net/live/source.m3u8?token=fixtureSignature", qualityId: "1080p60", approvedOrigins: ["https://canned.ttvnw.net"],
        metadata: {videoCodec: "avc1.4D402A", audioCodec: "mp4a.40.2", width: 1920, height: 1080, frameRate: "60.000", bandwidth: 8042999, isHD: true}}
end function

function esRequest(path as string, method = "GET" as string, range = "" as string) as string
    crlf = Chr(13) + Chr(10)
    result = method + " " + path + " HTTP/1.1" + crlf + "Host: 127.0.0.1:49371" + crlf
    if range <> "" then result += "Range: " + range + crlf
    return result + crlf
end function

sub esReset(raw = "" as string, transitions = true as boolean)
    m.events = []
    m.observers = []
    m.top = {sessionId: "0123456789abcdef0123456789abcdef", inputDescriptor: esDescriptor(), enableSourceTransitions: transitions, experimentalMode: true, cacheBudgetBytes: 16777216, listenPort: 49371, stopRequested: false,
        ObserveField: esObserve, UnobserveField: esUnobserve, observers: m.observers}
    m.sessionId = m.top.sessionId
    m.clockValues = [2000, 0]
    m.clock = {values: m.clockValues, index: 0, TotalMilliseconds: esClock}
    m.requestClock = {values: m.clockValues, index: 1, TotalMilliseconds: esClock}
    m.monotonicClock = nativeLiveClockCreate(0)
    m.lastNowMs = 0&
    m.steadyMode = true
    m.sourceTransitions = transitions
    m.cacheBudgetBytes = 16777216
    m.listenPort = 49371
    m.httpQuota = liveQuotaCreate(0&)
    m.counterExhausted = false
    m.closing = false
    m.port = CreateObject("roMessagePort")
    m.cache = []
    incoming = CreateObject("roByteArray")
    incoming.FromAsciiString(raw)
    outgoing = CreateObject("roByteArray")
    m.io = [incoming, 0, outgoing, m.events, m.cache, [false], ""]
    if raw.InStr("/asset/") >= 0 then m.io[6] = raw.Split(" ")[1].Mid(7)
    m.connection = {io: m.io, GetCountRcvBuf: esReceiveCount, IsReadable: esReadable, Receive: esReceive, IsWritable: esWritable, Send: esSend, eOK: esSocketOk, NotifyReadable: esNotify, NotifyWritable: esNotify, Close: esSocketClose}
    m.listener = invalid
    m.liveState = {sessionId: m.sessionId, steadyMode: true, sourceTransitions: transitions, trustedExperimentalTransport: true, phase: "init", initIds: [], epoch: 0&, pendingWindow: invalid}
    m.config = {metadata: esDescriptor().metadata, sourceDelaySeconds: 0}
    m.currentPublication = invalid
    m.currentGeneration = 0&
    m.publications = {}
    m.nextPublication = invalid
    m.activeLease = ""
    m.validationLease = ""
    m.activeGeneration = 0&
    m.activeBody = invalid
    m.initMasterMetadata = invalid
    m.initMasterTiming = invalid
    m.lastDiagnostics = invalid
    m.createCount = 0
    m.createOptions = invalid
    m.feedCount = 0
    m.decodeCount = 0
    m.decoderAllowed = true
    m.stopDuringDecode = false
    m.stopOnAcquire = false
    m.corruptAsset = ""
    m.coreClosed = false
    m.tickCount = 0
    m.result = {ok: false, status: "failed", reason: "not_started", actualInitValidated: false, decoderApproved: false, cleanupOk: true,
        requests: 1&, completedRequests: 0&, transmittedBytes: 0&, sendCalls: 0&, shortWrites: 0&, receiveCalls: 0&, retryableReceives: 0&, bufferLogicalCount: 0&, headerBytesPeak: 0&,
        headRequests: 0&, rangeRequests: 0&, masterRequests: 0&, videoPlaylistRequests: 0&, audioPlaylistRequests: 0&, videoBodies: 0&, audioBodies: 0&, urlEventsHandled: 0&, pumpCalls: 0&,
        retiredPublications: 0&, publicationsObserved: 0&, deliveredPublications: 0&, maxPinnedGenerations: 0&, cacheBytesPeak: 0&, convertedSegmentPairs: 0&, upstreamFetchCount: 0&, upstreamPlaylistCount: 0&,
        clientErrors: 0&, errorResponses: 0&, lastClientReason: "", countersComplete: true, connectionClosed: false}
end sub

function esBytes(name as string) as object
    bytes = CreateObject("roByteArray")
    bytes.FromHexString(m.corpus[name])
    return bytes
end function

sub esFirstInit()
    esAssert(rokuDemuxFeedInput(m.liveState, "init", esBytes("base"), 2000&), "first real init is gated before feed")
    esAssert(m.feedCount = 1 and m.result.actualInitValidated and m.result.decoderApproved, "actual bytes and mocked native decoder establish first gate proof")
    esAssert(m.initMasterTiming.videoTimescale = 90000& and m.initMasterTiming.audioTimescale = 48000&, "actual mdhd timescales inspected")
end sub

sub esRotation()
    state = m.liveState
    state.phase = "init-rotation"
    state.initIds = [esId(1), esId(2)]
    state.pendingWindow = {mapUrl: "https://canned.ttvnw.net/init.mp4", epoch: 1&, localEpoch: 1&, sequence: 103&}
    state.initDigest = nbBulkDigest(esBytes("base"))
    state.initByteCount = esBytes("base").Count()
    m.liveState = state
end sub

function esHasEvent(text as string) as integer
    for i = 0 to m.events.Count() - 1
        if m.events[i] = text then return i
    end for
    return -1
end function

function esLastEvent(text as string) as integer
    for i = m.events.Count() - 1 to 0 step -1
        if m.events[i] = text then return i
    end for
    return -1
end function

sub esInputPolicy()
    for each enabled in [false, true]
        esReset("", enabled)
        runServer()
        esAssert(m.createCount = 1 and m.createOptions <> invalid, "typed flag reaches only explicit mocked Core creation boundary")
        keys = ["mode", "sessionId"]
        if enabled then keys.Push("sourceTransitions")
        esAssert(loopbackKeys(m.createOptions, keys) and m.createOptions.mode = "steady" and m.createOptions.sessionId = m.sessionId, "exact legacy or enabled steady options")
        if enabled then esAssert(m.createOptions.sourceTransitions = true, "only enabled options add true Boolean")
        esAssert(m.top.result.cleanupOk and m.top.result.listenerClosed and m.top.result.connectionClosed and m.top.result.helperClosed and m.top.result.cacheReferencesReleased, "creation failure retains five typed cleanup contracts")
        esAssert(m.liveState = invalid and m.config = invalid and m.initMasterMetadata = invalid and m.initMasterTiming = invalid, "creation failure releases owner and gate snapshots")
        esCase("input-typed-" + enabled.ToStr())
    end for
    for each flag in [invalid, 0, 1, "true", [], {}]
        esReset()
        m.top.enableSourceTransitions = flag
        runServer()
        esAssert(m.createCount = 0 and m.top.result.reason = "invalid_source_transition_policy" and m.top.result.cacheReferencesReleased, "nonboolean flag rejected before provider state")
        esCase("input-refusal-" + m.cases.Count().ToStr())
    end for
    esReset()
    m.top.Delete("enableSourceTransitions")
    runServer()
    esAssert(m.createOptions.Count() = 2 and not m.createOptions.DoesExist("sourceTransitions"), "truly absent AA field preserves default off")
    esCase("input-absent-default-off")
    esReset()
    m.steadyMode = false
    esAssert(liveSteadyOptions() = invalid, "nonsteady policy cannot opt into transitions")
    m.steadyMode = true
    m.sessionId = "wrong"
    esAssert(liveSteadyOptions() = invalid, "invalid owner cannot create transition options")
    esCase("input-owner-steady-refusal")
end sub

sub esInitCases()
    esReset()
    esFirstInit()
    originalMaster = FormatJson(m.config.metadata)
    esRotation()
    esAssert(rokuDemuxFeedInput(m.liveState, "init", esBytes("changed"), 2001&), "genuine changed IDs timescales and bounded dimensions accepted after actual gate")
    esAssert(m.feedCount = 2 and FormatJson(m.config.metadata) = originalMaster and m.config.metadata.width = 1920 and m.config.metadata.height = 1080, "initial master envelope remains immutable")
    actual = nativeLiveInspectInitMetadata(esBytes("changed"))
    timing = liveInitTrackConfiguration(esBytes("changed"), actual)
    esAssert(actual.videoTrackId = 17& and actual.audioTrackId = 18& and timing.videoTimescale = 45000& and timing.audioTimescale = 44100&, "changed actual IDs and v1 mdhd scales are inspected rather than invented")
    esAssert(esHasEvent("decoder") >= 0 and esHasEvent("feed") > esHasEvent("decoder"), "first actual init approval precedes feed")
    esCase("init-genuine-compatible")
    ' Ads and encoder restarts change these; the decoder gate still applies.
    for each name in ["profile", "audio", "rate", "larger"]
        esReset()
        esFirstInit()
        originalMaster = FormatJson(m.config.metadata)
        esRotation()
        esAssert(rokuDemuxFeedInput(m.liveState, "init", esBytes(name), 2001&) and m.feedCount = 2, "decoder-approved changed init is fed " + name)
        esAssert(FormatJson(m.config.metadata) = originalMaster, "accepted later init leaves the advertised master unchanged " + name)
        esCase("init-accepted-" + name)
    end for
    for each name in ["zeroScale", "missingTiming", "flags", "reserved"]
        esReset()
        esFirstInit()
        originalMaster = FormatJson(m.config.metadata)
        esRotation()
        refused = false
        try
            rokuDemuxFeedInput(m.liveState, "init", esBytes(name), 2001&)
        catch error
            refused = error.message.Left("native-live: ".Len()) = "native-live: " or error.message.Left("native-init-metadata: ".Len()) = "native-init-metadata: "
        end try
        esAssert(refused and m.feedCount = 1, "gate refusal before changed init feed " + name)
        esAssert(FormatJson(m.config.metadata) = originalMaster and m.currentPublication = invalid, "refused init cannot mutate approved master or publication")
        esCase("init-refusal-" + name)
    end for
    esReset()
    esFirstInit()
    esRotation()
    m.decoderAllowed = false
    refused = false
    try
        rokuDemuxFeedInput(m.liveState, "init", esBytes("changed"), 2001&)
    catch error
        refused = error.message = "native-live: actual init decoder rejected"
    end try
    esAssert(refused and m.feedCount = 1, "native decoder refusal occurs before changed init feed")
    esCase("init-native-decoder-refusal")
    esReset()
    esFirstInit()
    esRotation()
    m.stopDuringDecode = true
    esAssert(not rokuDemuxFeedInput(m.liveState, "init", esBytes("changed"), 2001&) and m.feedCount = 1, "stop during actual gate prevents staging feed")
    closeLiveConnection()
    esAssert(m.activeBody = invalid and m.activeLease = "" and m.validationLease = "" and m.connection = invalid, "stop during gate has no retained response or lease")
    esCase("init-stop-during-gate")
    esReset()
    esFirstInit()
    esRotation()
    state = m.liveState
    state.sessionId = "ffffffffffffffffffffffffffffffff"
    m.liveState = state
    refused = false
    try
        rokuDemuxFeedInput(m.liveState, "init", esBytes("changed"), 2001&)
    catch error
        refused = error.message = "native-live: actual init owner or phase invalid"
    end try
    esAssert(refused and m.feedCount = 1, "wrong current init owner cannot feed")
    esCase("init-wrong-owner")
    esReset()
    esFirstInit()
    esRotation()
    state = m.liveState
    pending = state.pendingWindow
    pending.epoch = 0&
    state.pendingWindow = pending
    m.liveState = state
    refused = false
    try
        rokuDemuxFeedInput(m.liveState, "init", esBytes("changed"), 2001&)
    catch error
        refused = error.message = "native-live: selected map initialization changed"
    end try
    esAssert(refused and m.feedCount = 1, "same epoch alias changed bytes refused before new metadata gate")
    esAssert(rokuDemuxFeedInput(m.liveState, "init", esBytes("base"), 2001&), "same binary alias retains legacy actual gate")
    esCase("init-alias-identity")
    esReset()
    esAssert(rokuDemuxFeedInput(m.liveState, "init", esBytes("maxScale"), 2000&), "actual UInt32 timescale maximum admitted")
    esAssert(m.initMasterTiming.videoTimescale = 4294967295& and m.initMasterTiming.audioTimescale = 4294967295&, "timescale never narrowed to signed integer")
    esCase("init-timescale-endpoint")
end sub

function esPub(generation as integer, first as integer, epochs as object, maps as object) as object
    segments = []
    for i = 0 to epochs.Count() - 1
        base = maps[i]
        segments.Push({sequence: first + i, duration: "2.000", durationUs: 2000000, videoId: esId(100 + (first + i) * 2), audioId: esId(101 + (first + i) * 2), epoch: epochs[i], initVideoId: esId(base), initAudioId: esId(base + 1)})
    end for
    return {version: 2, discontinuitySequence: epochs[0], generation: generation, mediaSequence: first, targetDuration: 2, initVideoId: esId(maps[0]), initAudioId: esId(maps[0] + 1), durationUs: epochs.Count() * 2000000, sourceOffsetUs: 0, ended: false, segments: segments}
end function

sub esCachePublication(publication as object)
    assets = loopbackPublicationAssets(publication)
    esAssert(assets <> invalid, "synthetic publication is valid independent of Server")
    for each asset in assets
        if esFind(asset.id) = invalid
            data = CreateObject("roByteArray")
            data.FromHexString("10203040")
            m.cache.Push([asset.id, asset.track, data, 0])
        end if
    end for
end sub

sub esAdmit(publication as object)
    esCachePublication(publication)
    m.nextPublication = publication
    esAssert(pumpLiveServer(1) and m.currentGeneration = publication.generation, "complete v2 generation is admitted")
    for each record in m.cache
        esAssert(record[3] = 0, "admission's temporary body lease released")
    end for
end sub

sub esPublicationCases()
    esReset()
    esFirstInit()
    first = esPub(1, 100, [0, 1, 2], [1, 3, 1])
    esAdmit(first)
    for each record in loopbackPublicationAssets(first)
        esAssert(advertisedAssetTrack(record.id) = record.track, "every content-ad-content init/media track is advertised")
    end for
    esAssert(advertisedAssetTrack(esId(3)) = "video" and advertisedAssetTrack(esId(4)) = "audio", "later epoch init pair is advertised")
    esCase("publication-content-ad-content-assets")
    esReset()
    publication = esPub(1, 100, [0, 1, 2], [1, 3, 1])
    esCachePublication(publication)
    m.nextPublication = publication
    esAssert(not pumpLiveServer(1) and m.result.reason = "actual_init_required" and m.currentGeneration = 0&, "pure publication metadata cannot approve a decoder")
    esCase("publication-no-native-proof")
    esReset("", false)
    m.result.actualInitValidated = true
    m.result.decoderApproved = true
    m.nextPublication = esPub(1, 100, [0, 1, 2], [1, 3, 1])
    esAssert(not pumpLiveServer(1) and m.result.reason = "source_transitions_not_enabled", "v2 cannot leak through default-off legacy mode")
    esCase("publication-default-off")
    for each mode in ["missing", "corrupt", "malformed", "foreign", "stop"]
        esReset()
        esFirstInit()
        old = esPub(1, 100, [0, 0, 0], [1, 1, 1])
        esAdmit(old)
        newPub = esPub(2, 103, [1, 1, 1], [3, 3, 3])
        esCachePublication(newPub)
        if mode = "missing"
            for i = m.cache.Count() - 1 to 0 step -1
                if m.cache[i][0] = esId(4) then m.cache.Delete(i)
            end for
        else if mode = "corrupt"
            m.corruptAsset = esId(4)
        else if mode = "malformed"
            newPub.extra = true
        else if mode = "foreign"
            newPub.initVideoId = "live-ffffffffffffffffffffffffffffffff-3"
        else
            m.stopOnAcquire = true
        end if
        m.nextPublication = newPub
        esAssert(not pumpLiveServer(1) and m.currentGeneration = 1& and FormatJson(m.currentPublication) = FormatJson(old), "invalid or stopped admission preserves prior publication " + mode)
        closeLiveConnection()
        for each record in m.cache
            esAssert(record[3] = 0, "failed or stopped admission releases every temporary lease")
        end for
        esCase("publication-refusal-" + mode)
    end for
    esReset()
    esFirstInit()
    old = esPub(1, 100, [0, 0, 0], [1, 1, 1])
    esAdmit(old)
    oldWire = FormatJson(old)
    changed = esPub(1, 100, [0, 1, 2], [1, 3, 1])
    m.nextPublication = changed
    esAssert(not pumpLiveServer(1) and m.result.reason = "publication_generation_mutated" and FormatJson(m.currentPublication) = oldWire, "same generation mutation remains refused")
    esCase("publication-generation-mutation")
    esReset()
    esFirstInit()
    esAdmit(esPub(2, 100, [0, 0, 0], [1, 1, 1]))
    m.nextPublication = esPub(1, 100, [0, 0, 0], [1, 1, 1])
    esAssert(not pumpLiveServer(1) and m.result.reason = "publication_generation_regressed", "generation rollback remains refused")
    esCase("publication-generation-rollback")
    for each mode in ["track", "role", "pair"]
        esReset()
        esFirstInit()
        old = esPub(1, 100, [0, 0, 0], [1, 1, 1])
        esAdmit(old)
        if mode = "track"
            ' Individually valid new init video ID reuses the old audio ID.
            changed = esPub(2, 103, [1, 1, 1], [2, 2, 2])
        else if mode = "role"
            ' Same-track IDs cannot change from retained media to a new init.
            changed = esPub(2, 103, [1, 1, 1], [300, 300, 300])
        else
            ' A shared init video cannot silently be paired with different audio.
            changed = esPub(2, 103, [1, 1, 1], [1, 1, 1])
            changed.initAudioId = esId(3)
            segments = changed.segments
            for i = 0 to segments.Count() - 1
                segment = segments[i]
                segment.initAudioId = esId(3)
                segments[i] = segment
            end for
            changed.segments = segments
        end if
        esCachePublication(changed)
        m.nextPublication = changed
        esAssert(not pumpLiveServer(1) and m.result.reason = "asset_" + mode + "_conflict" and m.currentGeneration = 1&, "cross-generation asset " + mode + " conflict is refused before admission")
        esAssert(FormatJson(m.currentPublication) = FormatJson(old), "cross-generation conflict preserves prior immutable publication")
        closeLiveConnection()
        for each record in m.cache
            esAssert(record[3] = 0, "cross-generation conflict leaves no temporary lease")
        end for
        esCase("publication-" + mode + "-conflict")
    end for
end sub

sub esRequestCases()
    for each method in ["GET", "HEAD"]
        esReset(esRequest("/asset/" + esId(3), method, "bytes=1-2"))
        esFirstInit()
        publication = esPub(1, 100, [0, 1, 2], [1, 3, 1])
        esAdmit(publication)
        esAssert(serveLiveRequest(m.requestClock), "later init actual request succeeds " + method)
        esAssert(m.activeLease = esId(3) and esLeases(esId(3)) = 1, "later init request lease held after send until close")
        wire = m.io[2].ToAsciiString()
        esAssert(wire.InStr("206 Partial Content") >= 0 and wire.InStr("Content-Range: bytes 1-2/4") >= 0, "later map HEAD/range retains exact bounded transport")
        if method = "HEAD" then esAssert(m.result.headRequests = 1& and m.result.videoBodies = 0&, "HEAD sends no body")
        closeLiveConnection()
        esAssert(esLeases(esId(3)) = 0 and esLastEvent("socket-close") < esLastEvent("release:" + esId(3)), "actual socket close precedes final body release")
        esCase("request-later-map-" + method)
    end for
    esReset()
    esFirstInit()
    old = esPub(1, 100, [0, 0, 0], [1, 1, 1])
    esAdmit(old)
    response = prepareLiveResponse({track: "video", assetId: "", head: false, range: ""})
    esAssert(response <> invalid and m.activeGeneration = 1& and m.publications["1"].activeRequests = 1&, "actual old manifest holds generation request pin")
    newPub = esPub(2, 103, [1, 1, 1], [3, 3, 3])
    esAdmit(newPub)
    m.clockValues[0] = 10000
    retireExpiredPublications(liveServerNow())
    esAssert(m.publications.DoesExist("1") and advertisedAssetTrack(esId(1)) = "video", "active old manifest retains old init across new maps beyond grace")
    closeLiveConnection()
    retireExpiredPublications(liveServerNow())
    esAssert(not m.publications.DoesExist("1") and advertisedAssetTrack(esId(1)) = "", "last old manifest close permits exact retirement")
    esCase("request-active-generation-retention")
    esReset()
    esFirstInit()
    esAdmit(old)
    entry = m.publications["1"]
    entry.holdUntilMs = 8000&
    m.publications["1"] = entry
    esAdmit(newPub)
    response = prepareLiveResponse({track: "", assetId: esId(1), head: false, range: ""})
    esAssert(response <> invalid and esLeases(esId(1)) = 1, "old init acquire is allowed during advertisement grace")
    m.clockValues[0] = 10000
    retireExpiredPublications(liveServerNow())
    esAssert(not m.publications.DoesExist("1") and esLeases(esId(1)) = 1, "acquired old body lease survives generation retirement")
    closeLiveConnection()
    esAssert(esLeases(esId(1)) = 0, "old acquired body released only after close")
    esCase("request-grace-body-lease")
    esReset()
    esFirstInit()
    esAdmit(old)
    response = prepareLiveResponse({track: "", assetId: esId(999), head: false, range: ""})
    esAssert(response = invalid and m.result.reason = "asset_not_advertised" and m.activeLease = "", "unknown ID is not fetched or substituted")
    esCase("request-unknown-asset")
    for each mode in ["stop", "failure"]
        esReset(esRequest("/asset/" + esId(1)))
        esFirstInit()
        esAdmit(old)
        response = prepareLiveResponse({track: "", assetId: esId(1), head: false, range: ""})
        m.activeBody = response.data
        if mode = "stop" then m.top.stopRequested = true
        if mode = "failure" then m.io[5][0] = true
        esAssert(not sendLiveSpan(m.activeBody, 0, 4, m.requestClock), "stop or transport failure prevents late body sends")
        closeLiveConnection()
        esAssert(esLeases(esId(1)) = 0 and m.activeLease = "" and m.activeBody = invalid and m.connection = invalid, "stop or failed send cleans retained body and lease")
        esCase("request-cleanup-" + mode)
    end for
end sub
