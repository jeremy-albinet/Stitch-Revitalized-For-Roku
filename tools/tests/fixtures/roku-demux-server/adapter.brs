' The server functions and init inspector execute; sockets, decoder and Core feed
' use explicit boundary objects. This fixture is not native transport evidence.
function rsDescriptor() as object
    return { "version": 1, "sourceUrl": "https://canned.ttvnw.net/live/playlist.m3u8?token=fixture%2Btoken&sig=fixtureSignature", "qualityId": "1080p60", "approvedOrigins": ["https://canned.ttvnw.net"],
        "metadata": { "videoCodec": "avc1.4D402A", "audioCodec": "mp4a.40.2", "width": 1920, "height": 1080, "frameRate": "60.000", "bandwidth": 8042999, "isHD": true } }
end function

sub rsObserve(field as string, port as object)
    m.fixtureObservers.Push("observe:" + field)
end sub

sub rsUnobserve(field as string)
    m.fixtureObservers.Push("unobserve:" + field)
end sub

sub rsReset()
    htReset("")
    m.creationCapture = invalid
    m.allowCreateCapture = false
    m.top = { "sessionId": m.sessionId, "inputDescriptor": rsDescriptor(), "stopRequested": false, "experimentalMode": true, "cacheBudgetBytes": 16777216, "listenPort": 0,
        "fixtureObservers": [], "ObserveField": rsObserve, "UnobserveField": rsUnobserve }
end sub

function rsBoundText() as string
    return "127.0.0.1:-16165"
end function

function rsBoundPort() as integer
    return 49371
end function

sub rsCleanResult(reason as string)
    result = m.top.result
    htAssert(result.reason = reason and result.sessionId = "0123456789abcdef0123456789abcdef", "result retains known namespace and exact refusal")
    htAssert(result.cleanupOk and result.listenerClosed and result.connectionClosed and result.helperClosed and result.cacheReferencesReleased, "actual runServer released all owned references")
    htAssert(not result.DoesExist("failureCategory") and result.actualInitValidated = false and result.decoderApproved = false, "no synthetic failure category or init proof")
    htAssert(m.top.inputDescriptor = invalid and m.config = invalid and m.liveState = invalid, "descriptor and helper references discarded")
    wire = FormatJson(result)
    htAssert(wire.InStr(Chr(34) + "sessionId" + Chr(34)) >= 0 and wire.InStr("fixtureSignature") < 0 and wire.InStr("fixture%2Btoken") < 0 and wire.InStr("canned.ttvnw.net") < 0, "exact native result key and secret-free result")
end sub

sub rsAdapterCases()
    rsReset()
    m.top.experimentalMode = false
    runServer()
    rsCleanResult("experimental_mode_required")
    htAssert(m.creationCapture = invalid and m.top.fixtureObservers.Count() = 0, "default off performs no IO or observation")
    htCase("adapter-default-off")
    rsReset()
    m.top.stopRequested = true
    m.top.experimentalMode = false
    m.top.inputDescriptor = invalid
    runServer()
    rsCleanResult("stop_requested")
    htAssert(m.top.result.ok and m.top.result.status = "cancelled" and m.creationCapture = invalid, "stop before init is cooperative and finite")
    htCase("adapter-stop-before-init")
    for each bad in ["", "0123456789ABCDEF0123456789abcdef", "0123456789abcdef0123456789abcdef0"]
        rsReset()
        m.top.sessionId = bad
        runServer()
        htAssert(m.top.result.reason = "invalid_session_id" and m.top.result.sessionId = "" and m.top.result.cleanupOk, "invalid namespace refuses without echoing arbitrary input")
        htAssert(m.creationCapture = invalid and m.top.inputDescriptor = invalid, "invalid namespace has no helper and retains no descriptor")
        htCase("adapter-invalid-session-" + bad.Len().ToStr())
    end for
    for each cap in [0, 16777215, 16777217, 67108864]
        rsReset()
        m.top.cacheBudgetBytes = cap
        runServer()
        rsCleanResult("invalid_cache_budget")
        htAssert(m.creationCapture = invalid, "invalid cache policy refuses before IO")
        htCase("adapter-refused-cache-" + cap.ToStr())
    end for
    for each cap in [16777216, 25165824, 33554432]
        rsReset()
        m.top.cacheBudgetBytes = cap
        htAssert(prepareRokuDemuxInput() and m.cacheBudgetBytes = cap and m.steadyMode, "explicit approved cache accepted")
        htAssert(m.result.decoderApproved = false and m.result.actualInitValidated = false and m.top.inputDescriptor = invalid, "master hints alone do not establish init proof")
        htCase("adapter-approved-cache-" + cap.ToStr())
    end for
    for each port in [1, 49151, 65536, -1]
        rsReset()
        m.top.listenPort = port
        runServer()
        rsCleanResult("invalid_loopback_port")
        htCase("adapter-refused-port-" + port.ToStr())
    end for
    for each port in [0, 49152, 65535]
        rsReset()
        m.top.listenPort = port
        htAssert(prepareRokuDemuxInput(), "finite approved high port accepted")
        expected = port
        if port = 0 then expected = 49371
        htAssert(m.listenPort = expected, "omitted port chooses exactly one bounded port")
        htCase("adapter-approved-port-" + port.ToStr())
    end for
    for each missing in ["version", "sourceUrl", "qualityId", "approvedOrigins", "metadata"]
        rsReset()
        bad = rsDescriptor()
        bad.Delete(missing)
        m.top.inputDescriptor = bad
        runServer()
        rsCleanResult("invalid_input_descriptor")
        htCase("adapter-descriptor-missing-" + missing)
    end for
    rsReset()
    bad = rsDescriptor()
    bad["extra"] = "secret input must never be logged"
    m.top.inputDescriptor = bad
    runServer()
    rsCleanResult("invalid_input_descriptor")
    htCase("adapter-descriptor-extra-key")
    rsReset()
    bad = rsDescriptor()
    hints = bad["metadata"]
    hints["width"] = "1920"
    bad["metadata"] = hints
    m.top.inputDescriptor = bad
    runServer()
    rsCleanResult("invalid_input_descriptor")
    htCase("adapter-descriptor-primitive-refusal")
    rsReset()
    expected = rsDescriptor()
    m.allowCreateCapture = true
    runServer()
    rsCleanResult("native_exception")
    captured = m.creationCapture
    htAssert(captured <> invalid and captured["url"] = expected["sourceUrl"] and captured["origins"][0] = expected["approvedOrigins"][0], "actual Create boundary retains signed query and origins exactly")
    htAssert(captured["cache"] = 16777216 and captured["delay"] = 0 and captured["trusted"] = true and captured["options"]["sessionId"] = m.sessionId and captured["options"]["mode"] = "steady", "actual Create receives explicit experimental steady policy")
    htAssert(m.top.fixtureObservers.Count() = 2 and m.top.fixtureObservers[0] = "observe:stopRequested" and m.top.fixtureObservers[1] = "unobserve:stopRequested", "actual observer pair survives initialization failure")
    htCase("adapter-signed-query-and-initialization-failure")

    corpus = ParseJson(ReadAsciiFile("pkg:/init-corpus.json"))
    bytes = CreateObject("roByteArray")
    bytes.FromHexString(corpus[0].hex)
    rsReset()
    htAssert(prepareRokuDemuxInput(), "valid adapter metadata ready for gate")
    m.result["decoderApproved"] = false
    m.result["actualInitValidated"] = false
    htAssert(rokuDemuxFeedInput({}, "init", bytes, 2000&), "actual init gate feeds approved init")
    htAssert(m.feedCount = 1 and m.feedKind = "init" and m.result.actualInitValidated and m.result.decoderApproved, "proof flags follow actual inspector and canonical boundary")
    htAssert(m.decoderVariant["CODECS"] = "avc1.4D402A,mp4a.40.2" and m.decoderVariant["RESOLUTION"] = "1920x1080", "actual bytes authorize Main4.2 geometry, not master invention")
    htAssert(m.config["metadata"]["videoCodec"] = "avc1.4D402A" and m.config["metadata"].Count() = 7, "actual init hints replace metadata with exact seven-key struct")
    bound = { "GetAddress": rsBoundText, "GetPort": rsBoundPort }
    ready = liveReadyFields(bound)
    htAssert(ready.sessionId = m.sessionId and ready.actualInitValidated and ready.decoderApproved and ready.boundPort = 49371 and ready.boundAddressText = "127.0.0.1:-16165", "real ready builder carries actual-init proof and namespace/native port")
    wire = FormatJson(ready)
    htAssert(wire.InStr(Chr(34) + "sessionId" + Chr(34)) >= 0 and wire.InStr(Chr(34) + "actualInitValidated" + Chr(34)) >= 0 and wire.InStr("fixtureSignature") < 0 and wire.InStr("canned.ttvnw.net") < 0, "ready preserves native casing and excludes signed input")
    htCase("adapter-actual-init-and-ready-gate")
    rsReset()
    htAssert(prepareRokuDemuxInput(), "valid stop fixture")
    m.top.stopRequested = true
    htAssert(not rokuDemuxFeedInput({}, "init", bytes, 2000&) and m.feedCount = 0 and not m.result.actualInitValidated, "stop before init prevents inspect/feed and proof")
    htCase("adapter-stop-at-init-feed-boundary")
    rsReset()
    htAssert(prepareRokuDemuxInput(), "valid stop-during-init fixture")
    m.stopDuringDecode = true
    htAssert(not rokuDemuxFeedInput({}, "init", bytes, 2000&) and m.feedCount = 0 and not m.result.actualInitValidated, "stop during decoder boundary prevents feed and proof")
    acknowledgeLiveStop()
    htAssert(m.result.ok and m.result.reason = "stop_requested", "stop during init remains cooperative")
    htCase("adapter-stop-during-init-validation")
    rsReset()
    htAssert(prepareRokuDemuxInput(), "valid decoder-refusal fixture")
    m.decoderAllowed = false
    failed = false
    try
        rokuDemuxFeedInput({}, "init", bytes, 2000&)
    catch error
        failed = error.message = "native-live: actual init decoder rejected"
    end try
    htAssert(failed and m.feedCount = 0 and not m.result.actualInitValidated and not m.result.decoderApproved, "canonical refusal cannot publish or set proof")
    htCase("adapter-actual-decoder-refusal")
    rsReset()
    htAssert(prepareRokuDemuxInput(), "valid unsupported-layout fixture")
    bytes.FromHexString(corpus[1].hex)
    failed = false
    try
        rokuDemuxFeedInput({}, "init", bytes, 2000&)
    catch error
        failed = error.message.Left("native-init-metadata: ".Len()) = "native-init-metadata: "
    end try
    htAssert(failed and m.feedCount = 0 and not m.result.actualInitValidated, "brand-only AVC cannot authorize actual HEVC init")
    htCase("adapter-unsupported-actual-init-refusal")
    rsReset()
    m.result["decoderApproved"] = true
    htAssert(not bindLiveListener() and m.result.reason = "actual_init_required" and m.listener = invalid, "master approval cannot create a listener without actual init proof")
    htCase("adapter-master-only-bind-refusal")

    quota = liveQuotaCreate(0&)
    htAssert(liveQuotaCharge(quota, 59999&, 256&, 134217728&, 12000&), "exact bounded interval admitted")
    htAssert(not liveQuotaFits(quota, 59999&, 1&, 0&, 0&) and not liveQuotaFits(quota, 59999&, 0&, 1&, 0&) and not liveQuotaFits(quota, 59999&, 0&, 0&, 1&), "same interval excess refused")
    htAssert(liveQuotaCharge(quota, 60000&, 1&, 1&, 1&), "new interval accepts cumulative beyond old lifetime caps")
    htCase("adapter-steady-quota-boundaries")
    htReset("")
    m.fixtureClock[0] = 60000
    nowMs = liveServerNow()
    m.fixtureClock[0] = 120000
    nowMs = liveServerNow()
    m.fixtureClock[0] = 180000
    htAssert(liveServerActive() and pumpLiveServer(1), "steady adapter healthy beyond old server deadline")
    m.result.transmittedBytes = 134217728&
    bytes = loopbackAsciiBuffer("abcd")
    htAssert(sendLiveSpan(bytes, 0, 4, m.requestClock) and m.result.transmittedBytes = 134217732&, "actual send beyond old lifetime byte total")
    htCase("adapter-steady-clock-and-lifetime-send")
    htReset("")
    m.monotonicClock = nativeLiveClockCreate(4294967290&)
    m.fixtureClock[0] = 4
    htAssert(liveServerNow() = 10& and type(m.lastNowMs, 3) = "LongInteger", "actual clock helper handles raw32 wrap")
    htCase("adapter-clock-wrap-preserved")
    htReset("")
    m.result.transmittedBytes = 9007199254740991&
    htAssert(not sendLiveSpan(bytes, 0, 1, m.requestClock) and m.result.reason = "http_counter_exhausted" and not m.result.countersComplete and m.ioState[2].Count() = 0, "counter exhaustion preserves finite exact IO accounting")
    htCase("adapter-cumulative-counter-exhaustion")
end sub
