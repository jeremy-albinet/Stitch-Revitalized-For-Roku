sub main(args as object)
    m.assertions = 0
    m.cases = []
    m.control = args.control
    try
        htHeaders()
        htClassifications()
        htExchanges()
        htFatalAndStop()
        htBoundsAndCleanup()
        rsAdapterCases()
    catch error
        ? "STITCH_ROKU_SERVER_FAIL: "; error.message
        return
    end try
    ? "STITCH_ROKU_SERVER_PASS: __RUN_MARKER__ cases="; m.cases.Count(); " assertions="; m.assertions
end sub

sub htAssert(condition as boolean, label as string)
    m.assertions += 1
    if not condition then throw "http-fixture: " + label
end sub

sub htCase(name as string)
    for each previous in m.cases
        if previous = name then throw "http-fixture: duplicate case"
    end for
    m.cases.Push(name)
    ? "STITCH_ROKU_SERVER_CASE: "; name
end sub

function htClockValue() as dynamic
    return m.state[m.index]
end function

function htCount() as integer
    if m.state[11] <> invalid then return m.state[11]
    return m.state[0].Count() - m.state[1]
end function

function htReadable() as boolean
    return true
end function

function htReceive(buffer as object, start as integer, amount as integer) as integer
    count = amount
    if count > m.state[0].Count() - m.state[1] then count = m.state[0].Count() - m.state[1]
    if m.state[4].Count() > 0 then count = m.state[4].Shift()
    if count > 256 then return count
    if count > 0
        for i = 0 to count - 1
            buffer[start + i] = m.state[0][m.state[1] + i]
        end for
        m.state[1] += count
    else if m.state[12]
        m.state[8][1] = 8000
    end if
    return count
end function

function htWritable() as boolean
    if not m.state[7] then m.state[8][1] = 8000
    return m.state[7]
end function

function htSocketOk() as boolean
    return m.state[6]
end function

function htSend(bytes as object, start as integer, amount as integer) as integer
    m.state[5].Push("send:" + amount.ToStr())
    count = amount
    if m.state[3].Count() > 0 then count = m.state[3].Shift()
    if count > amount then return count
    if count > 0
        for i = 0 to count - 1
            m.state[2].Push(bytes[start + i])
        end for
    else if m.state[12]
        m.state[8][1] = 8000
    end if
    return count
end function

sub htNotifyReadable(value as boolean)
    m.state[5].Push("readable:" + value.ToStr())
end sub

sub htNotifyWritable(value as boolean)
    m.state[5].Push("writable:" + value.ToStr())
end sub

sub htClose()
    m.state[5].Push("close")
    if m.state[13] then throw "controlled close failure"
end sub

function htSocket(state as object) as object
    return { "state": state, "GetCountRcvBuf": htCount, "IsReadable": htReadable,
        "Receive": htReceive, "IsWritable": htWritable, "Send": htSend, "eOK": htSocketOk,
        "NotifyReadable": htNotifyReadable, "NotifyWritable": htNotifyWritable, "Close": htClose }
end function

sub nativeLiveTick(state as object, port as object, nowMs as dynamic)
    m.fixtureTicks += 1
    if m.fixtureThrowTick then throw "controlled helper exception"
    if m.failAtTick > 0 and m.fixtureTicks >= m.failAtTick
        m.fixtureDiagnostics.failed = true
        m.fixtureDiagnostics.phase = "failed"
        m.fixtureDiagnostics.failureCategory = 1
    end if
end sub

function nativeLiveDiagnostics(state as object) as object
    return m.fixtureDiagnostics
end function

function nativeLivePublication(state as object) as dynamic
    return m.fixturePublication
end function

function nativeLiveHandleUrlEvent(state as object, event as object, nowMs as dynamic) as boolean
    return false
end function

sub nativeLiveRetire(state as object, generation as dynamic)
    m.ioState[5].Push("retire:" + generation.ToStr())
end sub

function nativeLiveAcquire(state as object, id as string) as dynamic
    m.ioState[5].Push("acquire:" + id)
    return m.fixtureAsset
end function

sub nativeLiveRelease(state as object, id as string)
    m.ioState[5].Push("release:" + id)
    if m.fixtureReleaseFail then throw "controlled release failure"
end sub

function nativeLiveCreate(url as string, nowMs as dynamic, delaySeconds as integer, origins as object, experimental as boolean, cacheBudget = 16777216 as dynamic, steadyOptions = invalid as dynamic) as dynamic
    if m.allowCreateCapture
        m.creationCapture = { "url": url, "now": nowMs, "delay": delaySeconds, "origins": origins, "trusted": experimental, "cache": cacheBudget, "options": steadyOptions }
        throw "deliberate network boundary"
    end if
    throw "fixture forbids helper creation"
end function

function nativeLiveClose(state as object) as boolean
    throw "fixture forbids transport cleanup"
end function

function isTwitchVariantSupported(variant as object, device = invalid as dynamic) as boolean
    m.decoderVariant = variant
    if m.stopDuringDecode then m.top.stopRequested = true
    return m.decoderAllowed
end function

function twitchVariantVideoFormat(variant as object) as dynamic
    return variant
end function

function htPublication(generation as integer, firstId as integer) as object
    segments = []
    for i = 0 to 2
        segments.Push({ "sequence": i, "duration": "2.000", "durationUs": 2000000,
            "videoId": "live-0123456789abcdef0123456789abcdef-" + (firstId + 2 + i * 2).ToStr(), "audioId": "live-0123456789abcdef0123456789abcdef-" + (firstId + 3 + i * 2).ToStr() })
    end for
    return { "generation": generation, "mediaSequence": 0, "targetDuration": 2,
        "initVideoId": "live-0123456789abcdef0123456789abcdef-" + firstId.ToStr(), "initAudioId": "live-0123456789abcdef0123456789abcdef-" + (firstId + 1).ToStr(),
        "durationUs": 6000000, "sourceOffsetUs": 0, "ended": false, "segments": segments }
end function

sub htReset(raw as string)
    m.top = { "stopRequested": false, "listenPort": 49371, "sessionId": "0123456789abcdef0123456789abcdef", "experimentalMode": true, "cacheBudgetBytes": 16777216 }
    m.fixtureClock = [2000, 1000]
    m.monotonicClock = nativeLiveClockCreate(0)
    m.lastNowMs = 0&
    m.steadyMode = true
    m.adMetadataEnabled = false
    m.sessionId = "0123456789abcdef0123456789abcdef"
    m.listenPort = 49371
    m.cacheBudgetBytes = 16777216
    m.httpQuota = liveQuotaCreate(0&)
    m.counterExhausted = false
    m.closing = false
    m.fixturePublication = invalid
    m.clock = { "state": m.fixtureClock, "index": 0, "TotalMilliseconds": htClockValue }
    m.requestClock = { "state": m.fixtureClock, "index": 1, "TotalMilliseconds": htClockValue }
    m.port = CreateObject("roMessagePort")
    incoming = CreateObject("roByteArray")
    incoming.FromAsciiString(raw)
    outgoing = CreateObject("roByteArray")
    m.ioState = [incoming, 0, outgoing, [], [], [], true, true, m.fixtureClock, invalid, invalid, invalid, false, false]
    m.connection = htSocket(m.ioState)
    m.liveState = {}
    m.currentPublication = htPublication(1, 1)
    m.currentGeneration = 1
    m.publications = { "1": { "publication": m.currentPublication, "holdUntilMs": 0, "activeRequests": 0, "delivered": false } }
    m.config = { "sourceDelaySeconds": 0, "metadata": { "videoCodec": "avc1.4D402A", "audioCodec": "mp4a.40.2",
        "width": 1920, "height": 1080, "frameRate": "60.000", "bandwidth": 8042999, "isHD": true } }
    m.result = { "ok": false, "status": "failed", "reason": "not_started", "cleanupOk": true,
        "requests": 1, "completedRequests": 0, "transmittedBytes": 0, "sendCalls": 0, "shortWrites": 0,
        "receiveCalls": 0, "retryableReceives": 0, "headerBytesPeak": 0, "bufferLogicalCount": 0,
        "cacheBytesPeak": 0, "convertedSegmentPairs": 0, "upstreamFetchCount": 0, "upstreamPlaylistCount": 0,
        "urlEventsHandled": 0, "pumpCalls": 0, "retiredPublications": 0, "publicationsObserved": 0,
        "maxPinnedGenerations": 0, "deliveredPublications": 0, "masterRequests": 0, "videoPlaylistRequests": 0,
        "audioPlaylistRequests": 0, "videoBodies": 0, "audioBodies": 0, "headRequests": 0, "rangeRequests": 0,
        "clientErrors": 0, "errorResponses": 0, "lastClientReason": "", "connectionClosed": false }
    m.fixtureDiagnostics = { "phase": "ready", "failed": false, "failureCategory": 0,
        "generation": 1, "cacheBytes": 4, "peakCacheBytes": 4, "assetCount": 8,
        "fetchCount": 1, "playlistCount": 1, "initPairCount": 1, "segmentPairCount": 3,
        "transferActive": false, "inputRetained": false, "inputFilePresent": false, "closed": false }
    m.lastDiagnostics = invalid
    data = CreateObject("roByteArray")
    data.FromHexString("10203040")
    m.fixtureAsset = { "id": "live-0123456789abcdef0123456789abcdef-3", "mime": "video/mp4", "kind": "video", "size": 4, "data": data }
    m.activeLease = ""
    m.activeGeneration = 0
    m.activeBody = invalid
    m.fixtureTicks = 0
    m.failAtTick = 0
    m.fixtureThrowTick = false
    m.fixtureReleaseFail = false
    m.rangeErrorBytes = 4
    m.listener = invalid
    m.decoderAllowed = true
    m.stopDuringDecode = false
    m.decoderVariant = invalid
    m.feedCount = 0
    m.result["actualInitValidated"] = false
    m.result["decoderApproved"] = false
end sub

function htRequest(path as string, method = "GET" as string, headers = "" as string) as string
    crlf = Chr(13) + Chr(10)
    return method + " " + path + " HTTP/1.1" + crlf + "Host: 127.0.0.1:49371" + crlf + headers + crlf
end function

function htError(status as integer, size = 4 as integer) as string
    crlf = Chr(13) + Chr(10)
    phrase = "400 Bad Request"
    if status = 404 then phrase = "404 Not Found"
    if status = 416 then phrase = "416 Range Not Satisfiable"
    result = "HTTP/1.1 " + phrase + crlf + "Content-Length: 0" + crlf + "Connection: close" + crlf + "Cache-Control: no-store" + crlf
    if status = 416 then result += "Content-Range: bytes */" + size.ToStr() + crlf
    return result + crlf
end function

function htIndex(values as object, value as string) as integer
    for i = 0 to values.Count() - 1
        if values[i] = value then return i
    end for
    return -1
end function

function htHex(text as string) as string
    data = CreateObject("roByteArray")
    data.FromAsciiString(text)
    return data.ToHexString()
end function

function htFinish() as boolean
    served = serveLiveRequest(m.requestClock)
    if not served then served = tolerateLiveRequestFailure(m.requestClock)
    closeLiveConnection()
    if not m.result.cleanupOk
        m.result.reason = "connection_cleanup_failed"
        return false
    end if
    if not served and m.top.stopRequested then acknowledgeLiveStop()
    return served
end function

sub htHeaders()
    for each status in [400, 404, 416]
        expected = htError(status)
        if m.control = "header" and status = 400 then expected += "x"
        bytes = liveClientErrorHeader(status, 4)
        htAssert(bytes <> invalid, "error header available")
        htAssert(bytes.Count() <= 512, "error header bound")
        htAssert(bytes.ToHexString() = htHex(expected), "header-" + status.ToStr() + " complete bytes")
        htCase("header-" + status.ToStr())
    end for
    htAssert(liveClientErrorHeader(200, 4) = invalid, "reject unsupported error status")
    htAssert(liveClientErrorHeader(416, 0) = invalid, "reject zero range size")
    htAssert(liveClientErrorHeader(416, 4194305) = invalid, "reject excessive range size")
    htAssert(liveClientErrorHeader(416, 4194304).ToHexString() = htHex(htError(416, 4194304)), "maximum bounded error range")
    htCase("header-validation-bounds")
end sub

sub htClassifications()
    transients = ["client_closed_before_headers", "receive_failed", "send_failed", "header_deadline_or_stop", "send_deadline_or_stop",
        "header_cap", "non_ascii_request", "request_body_or_pipeline", "request_method_path_headers_or_range", "unknown_request_path", "asset_not_advertised", "invalid_request_range"]
    statuses = [0, 0, 0, 0, 0, 400, 400, 400, 400, 404, 404, 416]
    for i = 0 to transients.Count() - 1
        htReset("")
        m.result.reason = transients[i]
        htAssert(liveClientErrorStatus(transients[i]) = statuses[i], "explicit transient status")
        htAssert(tolerateLiveRequestFailure(m.requestClock), "healthy transient continues")
        htAssert(m.result.reason = "not_started" and m.result.lastClientReason = transients[i], "transient reason retained separately")
        htAssert(m.result.clientErrors = 1 and not m.result.ok, "transient is not terminal success")
        if statuses[i] > 0
            htAssert(m.ioState[2].ToHexString() = htHex(htError(statuses[i])), "classification complete response")
            htAssert(m.result.errorResponses = 1, "classification error response count")
        else
            htAssert(m.ioState[2].Count() = 0, "abandoned exchange writes no response")
        end if
        htCase("transient-" + transients[i])
    end for
    fatals = ["live_helper_failed", "invalid_helper_diagnostics", "invalid_live_publication", "publication_generation_mutated",
        "publication_generation_regressed", "publication_pin_cap", "native_exception", "cleanup_failed", "connection_cleanup_failed",
        "invalid_cached_asset", "advertised_asset_missing", "asset_track_conflict", "invalid_manifest_response", "response_header_cap",
        "invalid_logical_buffer_size", "invalid_receive_buffer_count", "invalid_receive_argument_bounds", "invalid_receive_count",
        "invalid_send_span_bounds", "invalid_send_argument_bounds", "invalid_send_count", "transmitted_byte_cap", "invalid_error_header",
        "server_deadline", "request_cap", "not_started", "unrecognized_future_failure"]
    for each reason in fatals
        htReset("")
        m.result.reason = reason
        htAssert(liveClientErrorStatus(reason) = -1, "fatal allowlist default")
        htAssert(not tolerateLiveRequestFailure(m.requestClock), "fatal does not continue")
        htAssert(m.result.reason = reason and m.result.clientErrors = 0 and m.ioState[2].Count() = 0, "fatal diagnostic and no bytes")
        htCase("fatal-" + reason)
    end for
end sub

sub htExpectedError(raw as string, status as integer, name as string)
    htReset(raw)
    htAssert(htFinish(), "client exchange tolerated " + name)
    htAssert(m.ioState[2].ToHexString() = htHex(htError(status)), "wire error complete " + name)
    htAssert(m.result.transmittedBytes = m.ioState[2].Count(), "exact accounting " + name)
    htAssert(m.connection = invalid and m.activeBody = invalid and m.activeLease = "" and m.activeGeneration = 0, "connection release " + name)
    htAssert(m.result.connectionClosed and m.result.cleanupOk and m.result.completedRequests = 0, "error cleanup and no success " + name)
    htCase("exchange-" + name)
end sub

sub htExchanges()
    crlf = Chr(13) + Chr(10)
    htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-99"), 404, "unknown-asset")
    htAssert(htIndex(m.ioState[5], "acquire:live-0123456789abcdef0123456789abcdef-99") = -1, "unknown path never acquires replacement bytes")
    htExpectedError(htRequest("/unknown"), 404, "unknown-route")
    htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", "POST"), 400, "invalid-method")
    htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", "GET", "Host: other" + crlf), 400, "duplicate-host")
    htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", "GET", "Authorization: private" + crlf), 400, "forbidden-header")
    htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3") + "x", 400, "body-or-pipeline")
    htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", "GET", "X-Test: " + Chr(1) + crlf), 400, "non-ascii")
    text = ""
    for i = 0 to 2050
        text += "a"
    end for
    htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", "GET", "X-Test: " + text + crlf), 400, "header-cap")
    for each range in ["bytes=4-", "bytes=3-1", "bytes=-0", "bytes=0-1,2-3", "items=0-1", "bytes=a-b"]
        htExpectedError(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", "GET", "Range: " + range + crlf), 416, "range-" + range)
        htAssert(htIndex(m.ioState[5], "close") < htIndex(m.ioState[5], "release:live-0123456789abcdef0123456789abcdef-3"), "range close precedes lease release")
    end for
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    old = m.currentPublication
    m.currentPublication = htPublication(2, 9)
    m.currentGeneration = 2
    m.publications = { "1": { "publication": old, "holdUntilMs": 1000, "activeRequests": 0, "delivered": true },
        "2": { "publication": m.currentPublication, "holdUntilMs": 0, "activeRequests": 0, "delivered": false } }
    htAssert(htFinish(), "retired asset client tolerance")
    htAssert(m.ioState[2].ToHexString() = htHex(htError(404)), "retired asset exact404 no stale body")
    htAssert(htIndex(m.ioState[5], "retire:1") >= 0 and htIndex(m.ioState[5], "acquire:live-0123456789abcdef0123456789abcdef-3") = -1, "retired lease never acquired")
    htCase("exchange-retired-asset")

    for each method in ["GET", "HEAD"]
        htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", method))
        htAssert(htFinish(), "valid method continues")
        expected = "HTTP/1.1 200 OK" + crlf + "Content-Type: video/mp4" + crlf + "Content-Length: 4" + crlf + "Accept-Ranges: bytes" + crlf
        expected += "Connection: close" + crlf + "Cache-Control: no-store" + crlf + crlf
        hex = htHex(expected)
        if method = "GET" then hex += "10203040"
        htAssert(m.ioState[2].ToHexString() = hex, "valid exact header and body")
        htAssert(m.result.completedRequests = 1 and m.result.clientErrors = 0, "valid completion unaffected")
        htAssert(htIndex(m.ioState[5], "close") < htIndex(m.ioState[5], "release:live-0123456789abcdef0123456789abcdef-3"), "valid close precedes lease release")
        htCase("exchange-valid-" + method)
    end for
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3", "GET", "Range: bytes=1-2" + crlf))
    htAssert(htFinish(), "valid range continues")
    expected = "HTTP/1.1 206 Partial Content" + crlf + "Content-Type: video/mp4" + crlf + "Content-Length: 2" + crlf + "Accept-Ranges: bytes" + crlf
    expected += "Connection: close" + crlf + "Cache-Control: no-store" + crlf + "Content-Range: bytes 1-2/4" + crlf + crlf
    htAssert(m.ioState[2].ToHexString() = htHex(expected) + "2030" and m.result.rangeRequests = 1, "valid ranged bytes unchanged")
    htCase("exchange-valid-range")

    for each mode in ["closed", "receive-error", "header-timeout"]
        htReset("")
        m.ioState[4] = [0]
        if mode = "receive-error"
            m.ioState[4] = [-1]
            m.ioState[6] = false
        else if mode = "header-timeout"
            m.ioState[4] = [-1]
            m.ioState[12] = true
        end if
        htAssert(htFinish(), "abandoned client continues")
        htAssert(m.ioState[2].Count() = 0 and m.result.clientErrors = 1 and m.result.connectionClosed, "abandoned client no bytes and closed")
        htCase("exchange-" + mode)
    end for
    htReset(htRequest("/unknown"))
    m.ioState[3] = [1, 3, 8]
    htAssert(htFinish(), "short error sends continue")
    htAssert(m.ioState[2].ToHexString() = htHex(htError(404)), "partial sends complete exact error bytes")
    htAssert(m.result.shortWrites = 3 and m.result.transmittedBytes = m.ioState[2].Count() and m.result.sendCalls = 4, "partial writes exact counters")
    htCase("exchange-error-partial-sends")
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.ioState[3] = [-1]
    m.ioState[6] = false
    htAssert(htFinish() and m.result.lastClientReason = "send_failed", "client abandonment during Send tolerable")
    htAssert(m.ioState[2].Count() = 0 and m.result.transmittedBytes = 0 and m.result.completedRequests = 0, "abandoned send never counts unsent bytes")
    htCase("exchange-send-abandoned")
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.ioState[3] = [0]
    m.ioState[12] = true
    htAssert(htFinish() and m.result.lastClientReason = "send_deadline_or_stop", "healthy send deadline tolerable")
    htAssert(m.fixtureClock[1] = 8000 and m.ioState[2].Count() = 0, "send deadline not extended for error response")
    htCase("exchange-send-timeout")
    htReset(htRequest("/unknown"))
    m.ioState[7] = false
    htAssert(htFinish() and m.result.clientErrors = 1 and m.result.errorResponses = 0, "unwritable client disposed without error body")
    htAssert(m.ioState[2].Count() = 0 and m.connection = invalid, "unwritable client no substituted bytes")
    htCase("exchange-error-unwritable")
    htReset(htRequest("/unknown"))
    htAssert(htFinish(), "first client error permits subsequent exchange")
    firstWire = m.ioState[2].ToHexString()
    nextRequest = CreateObject("roByteArray")
    nextRequest.FromAsciiString(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.ioState[0] = nextRequest
    m.ioState[1] = 0
    m.connection = htSocket(m.ioState)
    m.result.requests += 1
    htAssert(htFinish(), "next valid request uses same healthy helper publication")
    expected = "HTTP/1.1 200 OK" + crlf + "Content-Type: video/mp4" + crlf + "Content-Length: 4" + crlf + "Accept-Ranges: bytes" + crlf
    expected += "Connection: close" + crlf + "Cache-Control: no-store" + crlf + crlf
    htAssert(m.ioState[2].ToHexString() = firstWire + htHex(expected) + "10203040", "sequential error and valid response exact bytes")
    htAssert(m.result.requests = 2 and m.result.clientErrors = 1 and m.result.completedRequests = 1, "sequential exchange counters retained")
    htAssert(m.currentGeneration = 1 and m.result.reason = "not_started" and m.result.cleanupOk, "sequential exchange healthy state retained")
    htCase("exchange-next-valid-after-error")
end sub

sub htFatalAndStop()
    htReset(htRequest("/unknown"))
    m.fixtureDiagnostics.failed = true
    m.fixtureDiagnostics.phase = "failed"
    m.fixtureDiagnostics.failureCategory = 1
    continued = htFinish()
    expected = false
    if m.control = "fatal" then expected = true
    htAssert(continued = expected, "helper failure remains fatal")
    htAssert(m.result.reason = "live_helper_failed" and m.result.failureCategory = 1 and m.ioState[2].Count() = 0, "helper failure diagnostics and no error response")
    acknowledgeLiveStop()
    htAssert(not m.result.ok and m.result.reason = "live_helper_failed" and m.result.failureCategory = 1, "stop preserves helper failure")
    htCase("helper-failure-and-stop")

    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.fixtureAsset = invalid
    htAssert(not htFinish() and m.result.reason = "advertised_asset_missing", "advertised missing asset fatal")
    htAssert(m.ioState[2].Count() = 0, "missing advertised asset no substitute bytes")
    htCase("cache-missing-advertised-asset")
    for each field in ["id", "kind", "mime", "size", "data"]
        htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
        if field = "id" then m.fixtureAsset.id = "live-0123456789abcdef0123456789abcdef-99"
        if field = "kind" then m.fixtureAsset.kind = "audio"
        if field = "mime" then m.fixtureAsset.mime = "audio/mp4"
        if field = "size" then m.fixtureAsset.size = 5
        if field = "data" then m.fixtureAsset.data = []
        htAssert(not htFinish() and m.result.reason = "invalid_cached_asset", "malformed advertised asset fatal")
        htAssert(m.ioState[2].Count() = 0 and htIndex(m.ioState[5], "release:live-0123456789abcdef0123456789abcdef-3") >= 0, "malformed asset no bytes and lease released")
        htCase("cache-corrupt-" + field)
    end for
    htReset(htRequest("/unknown"))
    m.fixtureThrowTick = true
    threw = false
    try
        tolerateLiveRequestFailure(m.requestClock)
        m.result.reason = "header_cap"
        tolerateLiveRequestFailure(m.requestClock)
    catch error
        threw = error.message = "controlled helper exception"
    end try
    htAssert(threw and m.ioState[2].Count() = 0, "helper exception propagates and is not transient")
    htCase("helper-exception-propagation")

    htReset(htRequest("/unknown"))
    m.ioState[3] = [1]
    m.failAtTick = 4
    htAssert(not htFinish(), "helper failure during partial response fatal")
    htAssert(m.result.reason = "live_helper_failed" and m.result.failureCategory = 1, "partial response helper diagnostic preserved")
    htAssert(m.ioState[2].Count() = 1 and m.result.transmittedBytes = 1 and m.result.errorResponses = 0, "partial failed response counts exact")
    acknowledgeLiveStop()
    htAssert(not m.result.ok and m.result.reason = "live_helper_failed", "late stop retains partial-send failure")
    htCase("helper-failure-during-error-send")
    for each reason in ["native_exception", "cleanup_failed", "invalid_cached_asset", "request_cap", "server_deadline"]
        htReset("")
        m.result.reason = reason
        acknowledgeLiveStop()
        htAssert(not m.result.ok and m.result.reason = reason and m.result.status = "failed", "stop preserves fatal outcome")
        htCase("stop-preserves-" + reason)
    end for
    htReset("")
    m.result["failureCategory"] = 0
    acknowledgeLiveStop()
    htAssert(not m.result.ok and m.result.reason = "not_started" and m.result.failureCategory = 0, "stop preserves existing category even zero")
    htCase("stop-preserves-existing-category")
    htReset("")
    m.lastDiagnostics = m.fixtureDiagnostics
    m.lastDiagnostics.failed = true
    acknowledgeLiveStop()
    htAssert(not m.result.ok and m.result.reason = "not_started", "stop does not mask recorded failed diagnostics")
    htCase("stop-preserves-failed-diagnostics")
    htReset("")
    acknowledgeLiveStop()
    htAssert(m.result.ok and m.result.reason = "stop_requested" and m.result.status = "cancelled", "healthy stop acknowledged")
    htCase("stop-healthy-acknowledgment")
    htReset("")
    m.result.reason = "client_closed_before_headers"
    acknowledgeLiveStop()
    htAssert(m.result.ok and m.result.reason = "stop_requested", "healthy transient and cooperative stop")
    htCase("stop-healthy-transient")
end sub

sub htBoundsAndCleanup()
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.ioState[3] = [1000]
    htAssert(not htFinish() and m.result.reason = "invalid_send_count", "invalid socket send count fatal")
    htAssert(m.result.transmittedBytes = 0, "invalid send counts no bytes")
    htCase("invalid-send-count")
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.ioState[4] = [257]
    htAssert(not htFinish() and m.result.reason = "invalid_receive_count", "invalid socket receive count fatal")
    htAssert(m.result.clientErrors = 0 and m.ioState[2].Count() = 0, "invalid count not400 transient")
    htCase("invalid-receive-count")
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.ioState[13] = true
    htAssert(not htFinish() and not m.result.cleanupOk and m.result.reason = "connection_cleanup_failed", "close failure fatal")
    htCase("connection-close-failure")
    htReset(htRequest("/asset/live-0123456789abcdef0123456789abcdef-3"))
    m.fixtureReleaseFail = true
    htAssert(not htFinish() and not m.result.cleanupOk and m.result.reason = "connection_cleanup_failed", "lease-release failure fatal")
    htCase("lease-release-failure")
    htReset(htRequest("/video.m3u8"))
    htAssert(htFinish() and m.publications["1"].activeRequests = 0, "manifest active pin released")
    htAssert(m.result.videoPlaylistRequests = 1 and m.publications["1"].delivered and m.publications["1"].holdUntilMs = 8000, "manifest delivered grace unchanged")
    htCase("manifest-pin-cleanup-order")
    htReset("")
    m.top.stopRequested = true
    htAssert(not htFinish() and m.result.ok and m.result.reason = "stop_requested", "cooperative stop closes without response")
    htAssert(m.ioState[2].Count() = 0 and m.connection = invalid, "stop connection disposed")
    htCase("cooperative-stop")
end sub

function nativeLiveStatus(state as object) as object
    return { "error": "native-live: fixture helper failure" }
end function

sub nativeLiveFeed(state as object, kind as string, payload as dynamic, nowMs as dynamic)
    m.feedCount += 1
    m.feedKind = kind
    m.feedNow = nowMs
end sub
