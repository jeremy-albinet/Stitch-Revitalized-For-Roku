function rsClock() as longinteger
    if m.state.Count() > 1
        if m.state[1].Count() > 0 then m.state[0] += m.state[1].Shift()
    end if
    return m.state[0]
end function

' Native Wait/URL-event boundary only. Fetch state machine and Server handlers stay actual.
function rvsPump(delayMs as integer) as boolean
    m.time[0] += delayMs
    rvsCount("pumpCalls", 1&)
    if m.stopAtPump > 0 and m.result.pumpCalls >= m.stopAtPump then m.top.stopRequested = true
    if not rvsActive() then return false
    nowMs = rvsNow()
    if m.fetch <> invalid
        if m.fetch.op <> invalid
            op = m.fetch.op
            if op.intent.kind = "init" or op.intent.kind = "media"
                vfAssert(m.cache.reservation <> invalid and m.cache.reservation.workBytes = 50331648&, "full work reserved BEFORE native input allocation")
            end if
            if op.intent.kind = "master" then m.io[0] = vfBytes(m.master)
            if op.intent.kind = "playlist" then m.io[0] = vfBytes(m.playlist)
            if op.intent.kind = "init" then m.io[0] = m.initBytes
            if op.intent.kind = "media" then m.io[0] = m.mediaBytes
            unused = rokuVodFetchHandleUrlEvent(m.fetch, vfEvent(op.identity, m.io[0].Count()), nowMs)
        end if
        if not rokuVodFetchPump(m.fetch, nowMs, m.top.stopRequested)
            rvsFailure("upstream_failed")
            m.result["fetchReason"] = m.fetch.reason
            return false
        end if
        m.result.fetchCount = m.fetch.totalTransfers
    end if
    return rvsActive()
end function

function isTwitchVariantSupported(variant as object, device = invalid as dynamic) as boolean
    m.decoderCalls++
    return m.decoderAllowed
end function

function rsTopObserve(name as string, port as object) as boolean
    m.observers[0]++
    return true
end function

sub rsTopUnobserve(name as string)
    m.observers[1]++
end sub

function rsAddressSet(value as string) as boolean
    return true
end function

function rsAddressValid() as boolean
    return true
end function

function rsAddressText() as string
    return m.address
end function

function rsAddressPort() as integer
    return 49371
end function

function rsAddress() as object
    return { address: m.boundText, SetAddress: rsAddressSet, IsAddressValid: rsAddressValid, GetAddress: rsAddressText, GetPort: rsAddressPort }
end function

function rsListenerSet(address as object) as boolean
    m.address = address
    return true
end function

function rsListenerAddress() as object
    return m.address
end function

function rsListen(backlog as integer) as boolean
    m.state[0]++
    return true
end function

sub rsListenerNotify(value as boolean)
end sub

sub rsListenerClose()
    m.state[1]++
end sub

function rsListener() as object
    return { state: m.listenState, address: invalid, SetMessagePort: vfPort, SetAddress: rsListenerSet, GetAddress: rsListenerAddress, NotifyReadable: rsListenerNotify, Listen: rsListen, IsListening: vfYes, Close: rsListenerClose }
end function

function rsCount() as integer
    return m.state[0].Count() - m.state[1]
end function

function rsReadable() as boolean
    return true
end function

function rsReceive(bytes as object, offset as integer, limit as integer) as integer
    amount = m.state[0].Count() - m.state[1]
    if amount > limit then amount = limit
    for i = 0 to amount - 1
        bytes[offset + i] = m.state[0][m.state[1] + i]
    end for
    m.state[1] += amount
    m.state[8][0] += m.state[10]
    return amount
end function

function rsWritable() as boolean
    if not m.state[7] then m.state[8][0] += 8000&
    return m.state[7]
end function

function rsSend(bytes as object, offset as integer, length as integer) as integer
    amount = length
    if m.state[5] > 0 and amount > m.state[5] then amount = m.state[5]
    for i = 0 to amount - 1
        m.state[2].Push(bytes[offset + i])
    end for
    m.state[3].Push("send")
    m.state[8][0] += m.state[9]
    return amount
end function

sub rsNotify(value as boolean)
end sub

sub rsClose()
    m.state[3].Push("close")
    if m.state[6] then throw "controlled close failure"
    m.state[4]++
end sub

sub rsConnect(raw as string)
    m.socketState = [vfBytes(raw), 0, CreateObject("roByteArray"), [], 0, 0, false, true, m.time, 0&, 0&]
    m.connection = { state: m.socketState, GetCountRcvBuf: rsCount, IsReadable: rsReadable, Receive: rsReceive, IsWritable: rsWritable, Send: rsSend, eOK: vfYes, NotifyReadable: rsNotify, NotifyWritable: rsNotify, Close: rsClose }
end sub

function rsRequest(path as string, method = "GET" as string, range = "" as string) as string
    crlf = Chr(13) + Chr(10)
    raw = method + " " + path + " HTTP/1.1" + crlf + "Host: 127.0.0.1:49371" + crlf
    if range <> "" then raw += "Range: " + range + crlf
    return raw + crlf
end function

sub rsNew()
    m.observers = [0, 0]
    m.top = { sessionId: m.session, inputDescriptor: m.descriptor, experimentalMode: true, cacheBudgetBytes: 25165824, listenPort: 49371, stopRequested: false, ready: invalid, observers: m.observers, ObserveField: rsTopObserve, UnobserveField: rsTopUnobserve }
    rvsInitialize()
    m.time = [0&]
    m.clock = { state: m.time, TotalMilliseconds: rsClock }
    m.io = [vfBytes(m.master), false, true, true, true, true, 0, [], 0, 0, invalid, 0]
    m.listenState = [0, 0]
    m.boundText = "127.0.0.1:49371"
    m.decoderAllowed = true
    m.decoderCalls = 0
    m.stopAtPump = 0
end sub

sub rsPrepared()
    rsNew()
    vfAssert(rvsPrepare(), "actual master/playlist/init startup and decoder gate")
    vfAssert(m.index.count = 24 and m.cache.pairs.Count() = 1 and m.cache.initialized and m.cache.pairs[0].pinned and m.cache.reservation = invalid, "startup pins only the complete init pair and never downloads media")
    vfAssert(m.io[7].Count() = 5 and m.decoderCalls = 1 and m.result.actualInitValidated and m.result.decoderApproved, "exact master GET and two HEAD/GET transactions before actual decoder approval")
    vfAssert(m.input = invalid and m.conversion = invalid and not m.fetch.ownFile and m.fetch.output = invalid, "init work and temp staging released before ready")
    vfAssert(rvsBind() and m.top.ready <> invalid and m.listenState[0] = 1, "actual bound-address handler publishes ready")
    ready = m.top.ready
    vfAssert(rvdKeys(ready, ["sessionId", "boundAddressText", "boundPort", "metadata", "decoderApproved", "actualInitValidated", "requestedDecoderFormat", "mode", "totalDurationUs", "masterPath"]), "exact ten-field scene boundary")
    vfAssert(ready.mode = "vod" and ready.masterPath = "/vod/" + m.session + "/master.m3u8" and ready.totalDurationUs = 240000000&, "truthful immutable full-VOD route and duration")
    vfAssert(rvdKeys(ready.requestedDecoderFormat, ["codec", "profile", "level"]) and ready.requestedDecoderFormat.codec = "mpeg4 avc" and ready.requestedDecoderFormat.profile = "main" and ready.requestedDecoderFormat.level = "4.2", "actual pure formatter derives native AVC profile/level AA")
    m.result.reason = "serving"
end sub

sub rsPairAndLease()
    rsPrepared()
    path = "/vod/" + m.session + "/a/23.m4s"
    rsConnect(rsRequest(path, "HEAD", "bytes=1-3"))
    vfAssert(rvsRequest(), "first AUDIO HEAD/range demands and converts the whole indexed pair")
    vfAssert(m.result.convertedPairs = 2 and m.io[7].Count() = 7 and m.cache.pairs.Count() = 2 and m.cache.leases.Count() = 1 and m.activeLease <> invalid, "one paired source fetch and lease retained even for HEAD")
    text = m.socketState[2].ToAsciiString()
    vfAssert(text.InStr("206 Partial Content") >= 0 and text.InStr("Content-Length: 3") >= 0 and text.Right(4) = Chr(13) + Chr(10) + Chr(13) + Chr(10), "HEAD sends truthful range header without body")
    vfAssert(rvsCloseConnection() and m.socketState[4] = 1 and m.cache.leases.Count() = 0 and m.activeBody = invalid, "actual socket Close precedes releasing complete-pair lease")
    path = "/vod/" + m.session + "/v/23.m4s"
    rsConnect(rsRequest(path, "GET", "bytes=0-7"))
    m.socketState[5] = 3
    vfAssert(rvsRequest() and m.io[7].Count() = 7 and m.result.convertedPairs = 2, "paired VIDEO hit needs no extra transfer and supports real short writes")
    out = m.socketState[2]
    vfAssert(LCase(out.Slice(out.Count() - 8, out.Count()).ToHexString()) = m.expected.video.Left(16), "every selected response byte equals independent synthetic golden")
    vfAssert(rvsCloseConnection(), "paired-hit lease released after close")
    m.time[0] += 31001&
    vfAssert(rvsPump(1) and m.cache.pairs.Count() = 2, "pause longer than thirty seconds does not expire session or cache")
    rsConnect(rsRequest(path))
    vfAssert(rvsRequest() and m.io[7].Count() = 7, "full paired hit after long pause")
    out = m.socketState[2]
    split = out.ToAsciiString().InStr(Chr(13) + Chr(10) + Chr(13) + Chr(10)) + 4
    vfAssert(LCase(out.Slice(split, out.Count()).ToHexString()) = m.expected.video, "full video output byte-for-byte golden and absolute timing preservation")
    vfAssert(rvsCloseConnection(), "full send releases lease")
    rsConnect(rsRequest("/vod/" + m.session + "/a/23.m4s"))
    vfAssert(rvsRequest(), "full audio paired hit")
    out = m.socketState[2]
    split = out.ToAsciiString().InStr(Chr(13) + Chr(10) + Chr(13) + Chr(10)) + 4
    vfAssert(LCase(out.Slice(split, out.Count()).ToHexString()) = m.expected.audio, "full audio output byte-for-byte independent timing golden")
    vfAssert(rvsCloseConnection(), "audio lease releases")
    rvsCleanup()
    rsClean("complete pair paths")
end sub

sub rsClean(label as string)
    for each key in ["listenerClosed", "connectionClosed", "helperClosed", "cacheReferencesReleased", "cleanupOk"]
        vfAssert(loopbackBoolean(m.result[key]) and m.result[key], "typed actual cleanup acknowledgement: " + label + ":" + key)
    end for
    vfAssert(m.fetch = invalid and m.cache = invalid and m.index = invalid and m.activeBody = invalid and m.activeLease = invalid and m.reservation = invalid and m.conversion = invalid and m.input = invalid and not m.io[1], "all source/output/socket/lease/work references released")
    vfAssert(m.observers[0] = m.observers[1], "explicit stop observer cleanup")
end sub

sub rsManifestAndRoutes()
    rsPrepared()
    for each track in ["video", "audio"]
        rsConnect(rsRequest("/vod/" + m.session + "/" + track + ".m3u8"))
        vfAssert(rvsRequest(), "actual full bounded manifest serving")
        out = m.socketState[2].ToAsciiString()
        vfAssert(out.InStr("#EXT-X-ENDLIST") > 0 and out.InStr("#EXT-X-PLAYLIST-TYPE:VOD") > 0 and out.InStr("/23.m4s") > 0 and out.InStr("#EXT-X-MEDIA-SEQUENCE:95") > 0, "truthful whole VOD timeline without LIVE-window rewriting")
        vfAssert(m.io[7].Count() = 5 and m.activeBody = invalid and m.manifestCursor <> invalid, "manifest streaming does not download media or retain full text")
        vfAssert(rvsCloseConnection() and m.manifestCursor = invalid, "streaming cursor released on close")
    end for
    rsConnect(rsRequest("/vod/" + m.session + "/video.m3u8", "GET", "bytes=10-29"))
    vfAssert(rvsRequest(), "bounded ranged manifest streaming")
    out = m.socketState[2]
    split = out.ToAsciiString().InStr(Chr(13) + Chr(10) + Chr(13) + Chr(10)) + 4
    vfAssert(out.Count() - split = 20, "ranged manifest sends exactly advertised length")
    vfAssert(rvsCloseConnection(), "ranged manifest close")
    for each path in ["/vod/" + m.session + "/v/24.m4s", "/vod/" + m.other + "/v/0.m4s", "/vod/" + m.session + "/v/00.m4s", "/vod/" + m.session + "/../master.m3u8", "https://foreign.invalid/media"]
        rsConnect(rsRequest(path))
        vfAssert(not rvsRequest() and m.io[7].Count() = 5 and m.activeLease = invalid and m.cache.reservation = invalid, "unindexed or foreign route cannot trigger network or work")
        vfAssert(rvsCloseConnection(), "refused client closes")
    end for
    rvsCleanup()
    rsClean("finite full manifests")
end sub

sub rsEvictionRefetch()
    rsPrepared()
    for each entryNo in [23, 1, 22, 2, 21, 3, 20, 4, 19, 5, 18, 6, 17, 7, 16, 8]
        rsConnect(rsRequest("/vod/" + m.session + "/a/" + entryNo.ToStr() + ".m4s", "HEAD"))
        vfAssert(rvsRequest() and m.activeLease <> invalid, "sparse seek converts only each requested pair")
        vfAssert(rvsCloseConnection(), "sparse seek actual lease close")
        vfAssert(m.cache.pairs.Count() <= 16 and m.cache.pairs[0].pinned and m.cache.cacheBytes <= 25165824&, "bounded whole-pair LRU preserves init pins")
    end for
    vfAssert(nvcPairAt(m.cache, 23) = -1 and m.cache.evictions > 0 and m.io[7].Count() = 37, "old unleased pair evicted without losing full-index authority")
    rsConnect(rsRequest("/vod/" + m.session + "/v/23.m4s", "HEAD"))
    vfAssert(rvsRequest() and m.io[7].Count() = 39 and m.result.convertedPairs = 18, "evicted authorized pair refetched exactly once on demand")
    vfAssert(rvsCloseConnection(), "refetch lease closes")
    rsConnect(rsRequest("/vod/" + m.session + "/a/23.m4s", "HEAD"))
    vfAssert(rvsRequest() and m.io[7].Count() = 39, "refetched opposite-track paired hit")
    vfAssert(rvsCloseConnection(), "refetched paired hit closes")
    rvsCleanup()
    rsClean("sparse eviction and refetch")
end sub

sub rsFailures()
    rsNew()
    m.io[2] = false
    vfAssert(not rvsPrepare() and m.top.ready = invalid and m.io[7].Count() = 0, "native transport refusal before publication and all upstream requests")
    rvsCleanup()
    rsClean("transport gated")
    rsPrepared()
    m.top.sessionId = m.other
    vfAssert(not rvsActive() and m.result.reason = "stale_owner", "replaced scene owner cannot continue upstream, Ready or send")
    rvsCleanup()
    rsClean("stale scene owner")
    rsNew()
    m.decoderAllowed = false
    rejected = false
    try
        unused = rvsPrepare()
    catch error
        rejected = true
    end try
    vfAssert(rejected and m.top.ready = invalid and not m.result.actualInitValidated and m.cache.pairs.Count() = 0 and m.reservation <> invalid, "actual decoder gate refusal precedes init publication")
    rvsCleanup()
    rsClean("decoder gate refused")
    rsPrepared()
    rsConnect(rsRequest("/vod/" + m.session + "/v/0.m4s"))
    request = rokuVodRequest(rsRequest("/vod/" + m.session + "/v/0.m4s"), m.session, m.index.count, m.listenPort)
    vfAssert(rvsResponse(request, rvsNow() + 15000&) <> invalid and m.activeLease <> invalid, "cleanup-block lease acquired through actual response handler")
    m.socketState[6] = true
    vfAssert(not rvsCloseConnection() and m.activeLease <> invalid and m.cache.leases.Count() = 1 and m.connection <> invalid, "failed socket close cannot release lease")
    rvsCleanup()
    vfAssert(not m.result.cleanupOk and not m.result.connectionClosed and not m.result.cacheReferencesReleased and not m.result.helperClosed, "unresolved socket owner produces truthful cleanupBlocked acknowledgements")
    m.socketState[6] = false
    vfAssert(rvsCloseConnection() and m.cache.leases.Count() = 0, "later actual close permits exact lease release")
    ' The failure verdict stays false even after resource recovery.
    rvsCleanup()
    vfAssert(m.result.listenerClosed and m.result.connectionClosed and m.result.helperClosed and m.result.cacheReferencesReleased and not m.result.cleanupOk, "blocked verdict never silently becomes success")
    rsPrepared()
    m.stopAtPump = m.result.pumpCalls + 2
    vfAssert(not rvsConvert(4, rvsNow() + 15000&) and m.reservation <> invalid and m.top.stopRequested, "stop during fetch retains reservation until real cancellation")
    rvsCleanup()
    rsClean("stop during source acquisition")
    rsPrepared()
    m.stopAtPump = m.result.pumpCalls + 4
    vfAssert(not rvsConvert(4, rvsNow() + 15000&) and m.top.stopRequested, "stop during bounded chunk-track conversion")
    rvsCleanup()
    rsClean("stop during conversion")
    rsPrepared()
    rsConnect(rsRequest("/vod/" + m.session + "/v/0.m4s"))
    m.stopAtPump = m.result.pumpCalls + 5
    vfAssert(not rvsRequest() and m.top.stopRequested, "stop during send forbids late response completion")
    rvsCleanup()
    rsClean("stop during send")
    rsPrepared()
    m.index.records[0] = 99
    rsConnect(rsRequest("/vod/" + m.session + "/v/0.m4s"))
    vfAssert(not rvsRequest() and m.io[7].Count() = 5, "immutable index mutation refuses authorized acquisition")
    vfAssert(rvsCloseConnection(), "mutated-index client closes")
    rvsCleanup()
    rsClean("mutated index refused and safely released")
end sub

sub rsDeadlineBoundaries()
    rsPrepared()
    raw = rsRequest("/vod/" + m.session + "/master.m3u8")
    rsConnect(raw)
    deadline = rvsNow() + 10&
    vfAssert(rvsHeaders(deadline) = invalid and m.result.receiveCalls = 0 and m.socketState[1] = 0, "header pump consuming deadline forbids native Receive")
    vfAssert(rvsCloseConnection(), "before-Receive deadline close")
    rsConnect(raw)
    m.socketState[10] = 100&
    deadline = rvsNow() + 50&
    vfAssert(rvsHeaders(deadline) = invalid and m.result.receiveCalls = 1 and m.socketState[1] > 0, "late final native Receive cannot accept complete headers")
    vfAssert(rvsCloseConnection(), "after-Receive deadline close")
    rsConnect(raw)
    deadline = rvsNow() + 50&
    m.time.Push([0&, 0&, 0&, 0&, 0&, 0&, 50&])
    vfAssert(rvsHeaders(deadline) = invalid and m.result.receiveCalls = 2, "final complete-header parsing cannot return after deadline")
    m.time[1] = []
    vfAssert(rvsCloseConnection(), "final-header parsing deadline close")
    rsConnect(raw)
    bytes = vfBytes("abc")
    deadline = rvsNow() + 1&
    vfAssert(not rvsSend(bytes, 0, 3, deadline) and m.socketState[2].Count() = 0, "send pump consuming deadline forbids native Send")
    vfAssert(rvsCloseConnection(), "before-Send deadline close")
    rsConnect(raw)
    m.socketState[9] = 50&
    deadline = rvsNow() + 50&
    vfAssert(not rvsSend(bytes, 0, 3, deadline) and m.socketState[2].Count() = 3 and m.result.transmittedBytes = 3&, "late last-byte Send is accounted but never returned as success")
    vfAssert(rvsCloseConnection(), "after-Send deadline close")
    request = rokuVodRequest(raw, m.session, m.index.count, m.listenPort)
    vfAssert(rvsResponse(request, rvsNow()) = invalid and m.activeBody = invalid, "expired cached/master acquisition refuses at entry")
    m.time[1] = [0&, 20&]
    deadline = m.lastNow + 10&
    vfAssert(rvsResponse(request, deadline) = invalid, "pure master preparation cannot return after acquisition deadline")
    m.time[1] = []
    vfAssert(rvsCloseConnection(), "late master response releases temporary body")
    request = rokuVodRequest(rsRequest("/vod/" + m.session + "/video.m3u8"), m.session, m.index.count, m.listenPort)
    deadline = rvsNow() + 10&
    m.time[1] = [0&, 0&, 20&]
    vfAssert(rvsResponse(request, deadline) = invalid and m.manifestCursor <> invalid, "pure response header cannot return after acquisition deadline")
    m.time[1] = []
    vfAssert(rvsCloseConnection(), "late response header releases streamed cursor")
    rsConnect(raw)
    response = rvsResponse(request, rvsNow() + 15000&)
    vfAssert(response <> invalid, "deadline manifest cursor prepared within separate acquisition budget")
    deadline = rvsNow() + 10&
    m.time[1] = [0&, 20&]
    vfAssert(not rvsManifest(request, response.range, deadline) and m.socketState[2].Count() = 0, "late manifest helper cannot send or declare completion")
    m.time[1] = []
    vfAssert(rvsCloseConnection(), "late span cursor releases")
    rvsCleanup()
    rsClean("fresh after-pump/native/helper deadline controls")
end sub

sub main()
    m.assertions = 0
    m.session = "0123456789abcdef0123456789abcdef"
    m.other = "fedcba9876543210fedcba9876543210"
    m.master = ReadAsciiFile("pkg:/master.m3u8")
    m.playlist = ReadAsciiFile("pkg:/index.m3u8")
    m.expected = ParseJson(ReadAsciiFile("pkg:/expected.json"))
    m.initBytes = CreateObject("roByteArray")
    m.mediaBytes = CreateObject("roByteArray")
    unused = m.initBytes.ReadFile("pkg:/init.bin")
    unused = m.mediaBytes.ReadFile("pkg:/media.bin")
    try
        m.descriptor = rokuVodDescriptorFromTrustedMaster(m.master, "https://usher.ttvnw.net/vod/v2/123.m3u8?fixture=synthetic", { sourceUrl: "https://dsynthetic.cloudfront.net/archive/index.m3u8?fixture=synthetic", qualityId: "1080p60" }, "123")
        vfAssert(m.descriptor <> invalid, "actual descriptor fixture")
        rsPairAndLease()
        rsManifestAndRoutes()
        rsEvictionRefetch()
        rsFailures()
        rsDeadlineBoundaries()
        print "STITCH_VOD_SERVER_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 0})
    catch error
        print "STITCH_VOD_SERVER_FAIL: __MARKER__ " + error.message
        print "STITCH_VOD_SERVER_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 1})
    end try
end sub
