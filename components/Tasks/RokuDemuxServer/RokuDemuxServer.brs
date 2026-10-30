sub init()
    m.top.functionName = "runServer"
end sub

sub runServer()
    m.clock = CreateObject("roTimespan")
    m.monotonicClock = invalid
    m.lastNowMs = 0&
    m.steadyMode = false
    m.sourceTransitions = false
    m.initMasterMetadata = invalid
    m.initMasterTiming = invalid
    m.sessionId = ""
    if loopbackSteadySessionIdValid(m.top.sessionId) then m.sessionId = m.top.sessionId
    m.listenPort = 0
    m.cacheBudgetBytes = 16777216
    m.httpQuota = invalid
    m.counterExhausted = false
    m.closing = false
    m.listener = invalid
    m.connection = invalid
    m.port = invalid
    m.liveState = invalid
    m.config = invalid
    m.currentPublication = invalid
    m.currentGeneration = 0&
    m.adMetadataEnabled = twitchAdClockBoolean(m.top.enableAdMetadata) and m.top.enableAdMetadata = true
    m.publications = {}
    m.activeBody = invalid
    m.activeLease = ""
    m.validationLease = ""
    m.activeGeneration = 0
    m.lastDiagnostics = invalid
    m.result = {
        "ok": false, "status": "failed", "reason": "not_started",
        "sessionId": m.sessionId, "decoderApproved": false, "actualInitValidated": false,
        "bound": false, "listening": false, "requests": 0&, "completedRequests": 0&,
        "clientErrors": 0&, "errorResponses": 0&, "lastClientReason": "",
        "transmittedBytes": 0&, "sendCalls": 0&, "shortWrites": 0&,
        "receiveCalls": 0&, "retryableReceives": 0&, "bufferLogicalCount": 0&,
        "headerBytesPeak": 0&, "headRequests": 0&, "rangeRequests": 0&,
        "masterRequests": 0&, "videoPlaylistRequests": 0&, "audioPlaylistRequests": 0&,
        "videoBodies": 0&, "audioBodies": 0&, "urlEventsHandled": 0&, "pumpCalls": 0&,
        "publicationsObserved": 0&, "deliveredPublications": 0&, "retiredPublications": 0&,
        "maxPinnedGenerations": 0&, "cacheBytesPeak": 0&, "convertedSegmentPairs": 0&,
        "upstreamFetchCount": 0&, "upstreamPlaylistCount": 0&,
        "listenerClosed": false, "connectionClosed": false, "helperClosed": false,
        "cacheReferencesReleased": false, "cleanupOk": true,
        "hardPreBodyTransferCapVerified": false, "redirectDisableVerified": false,
        "countersComplete": true
    }
    try
        serveBoundedLive()
    catch error
        if not liveFailureRecorded() then m.result.reason = "native_exception"
    end try
    m.closing = true
    closeLiveConnection()
    if m.listener <> invalid
        try
            m.listener.NotifyReadable(false)
            m.listener.Close()
            m.result.listenerClosed = true
        catch error
            m.result.cleanupOk = false
        end try
        m.listener = invalid
    else
        m.result.listenerClosed = true
    end if
    ' No further request can be served: release every advertised generation.
    if m.liveState <> invalid
        try
            keys = []
            for each key in m.publications
                keys.Push(key)
            end for
            for each key in keys
                nativeLiveRetire(m.liveState, m.publications[key].publication.generation)
                liveIncrement("retiredPublications", 1 + 0&)
            end for
            m.publications = {}
            m.currentPublication = invalid
            m.currentGeneration = 0&
            m.result.helperClosed = nativeLiveClose(m.liveState)
            m.lastDiagnostics = loopbackSafeDiagnostics(nativeLiveDiagnostics(m.liveState), m.cacheBudgetBytes, m.steadyMode)
            if not recordLiveInitAliases() then m.result.cleanupOk = false
            if not m.result.helperClosed or m.lastDiagnostics = invalid
                m.result.cleanupOk = false
            else if not m.lastDiagnostics.closed or m.lastDiagnostics.transferActive or m.lastDiagnostics.inputRetained or m.lastDiagnostics.inputFilePresent or m.lastDiagnostics.cacheBytes <> 0 or m.lastDiagnostics.assetCount <> 0
                m.result.cleanupOk = false
            end if
        catch error
            m.result.cleanupOk = false
        end try
    else
        m.result.helperClosed = true
    end if
    if m.port <> invalid
        m.top.UnobserveField("stopRequested")
        m.port = invalid
    end if
    if m.lastDiagnostics <> invalid then m.result["helperDiagnostics"] = m.lastDiagnostics
    m.liveState = invalid
    m.config = invalid
    m.initMasterMetadata = invalid
    m.initMasterTiming = invalid
    m.top.inputDescriptor = invalid
    m.publications = invalid
    m.currentPublication = invalid
    m.activeBody = invalid
    m.lastDiagnostics = invalid
    m.result.cacheReferencesReleased = m.result.helperClosed and m.result.cleanupOk and m.liveState = invalid and m.publications = invalid and m.currentPublication = invalid and m.activeBody = invalid and m.validationLease = "" and m.initMasterMetadata = invalid and m.initMasterTiming = invalid
    try
        m.result["elapsedMs"] = liveServerNow()
    catch error
        m.result["elapsedMs"] = m.lastNowMs
        m.result.ok = false
    end try
    if not m.result.cleanupOk
        m.result.ok = false
        m.result.reason = "cleanup_failed"
    end if
    m.top.result = m.result
end sub

sub serveBoundedLive()
    if not prepareRokuDemuxInput() then return
    m.result["sourceDelaySeconds"] = m.config.sourceDelaySeconds
    m.result["generationGraceMs"] = 6000
    meta = m.config.metadata
    variant = {
        "RESOLUTION": meta.width.ToStr() + "x" + meta.height.ToStr(),
        "FRAME-RATE": meta.frameRate, "BANDWIDTH": meta.bandwidth.ToStr(),
        "CODECS": meta.videoCodec + "," + meta.audioCodec
    }
    if not isTwitchVariantSupported(variant)
        m.result.reason = "canonical_decoder_rejected"
        return
    end if
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("stopRequested", m.port)
    if m.top.stopRequested
        acknowledgeLiveStop()
        return
    end if
    ' Explicit experiment only: unknown-framing/pre-body/redirect limits remain.
    options = liveSteadyOptions()
    if options = invalid
        m.result.reason = "invalid_source_transition_policy"
        return
    end if
    m.liveState = nativeLiveCreate(m.config.trustedMediaUrl, liveServerNow(), m.config.sourceDelaySeconds, m.config.approvedOrigins, true, m.cacheBudgetBytes, options)
    m.liveState.adClockEnabled = m.adMetadataEnabled
    ' The player starts at the window's first segment, so its length sets
    ' the delay: 14 s measured ~25 s behind live and 8 s ~17 s on a G204X.
    ' Six seconds ran dry about 20 s in before the parsing stalls were fixed.
    configureLiveLatency(m.liveState)
    m.result["experimentalUnknownFramingTransport"] = true
    ' Drop the signed private input from the harness's config immediately.
    m.config.Delete("trustedMediaUrl")
    m.config.Delete("approvedOrigins")
    while liveServerActive() and (m.steadyMode or m.result.requests < 256)
        if not pumpLiveServer(20) then exit while
        if m.listener = invalid
            if m.currentPublication <> invalid
                if m.currentPublication.segments.Count() >= 3 and m.currentPublication.durationUs >= 6000000
                    if not bindLiveListener() then return
                end if
            end if
            if m.listener = invalid and liveServerNow() >= 40000
                m.result.reason = "live_start_deadline"
                return
            end if
        else if m.listener.IsReadable()
            if not liveCounterFits("requests", 1&) then return
            if not liveSocketPermit(0&, 1&) then return
            m.connection = m.listener.Accept()
            if m.connection <> invalid
                if m.steadyMode
                    if not liveQuotaCharge(m.httpQuota, m.socketAccountingNowMs, 1&, 0&, 0&)
                        m.result.reason = "http_interval_quota"
                        return
                    end if
                end if
                liveIncrement("requests", 1 + 0&)
                m.result.connectionClosed = false
                m.connection.SetMessagePort(m.port)
                m.connection.NotifyReadable(true)
                requestClock = CreateObject("roTimespan")
                served = serveLiveRequest(requestClock)
                if not served then served = tolerateLiveRequestFailure(requestClock)
                closeLiveConnection()
                if not m.result.cleanupOk
                    m.result.reason = "connection_cleanup_failed"
                    return
                end if
                if not served
                    if m.top.stopRequested then acknowledgeLiveStop()
                    return
                end if
            else if not m.listener.eOK()
                m.result.reason = "accept_failed"
                return
            end if
        end if
    end while
    if m.top.stopRequested
        acknowledgeLiveStop()
    else if not m.steadyMode and m.result.requests >= 256
        m.result.reason = "request_cap"
    else if m.result.reason = "not_started"
        m.result.reason = "server_deadline"
    end if
end sub

sub configureLiveLatency(state as object)
    state.windowUs = 14000000&
    state.pollFromRequest = m.top.lowLatency
    if m.top.lowLatency then state.windowUs = 6000000&
end sub

function bindLiveListener() as boolean
    if m.top.stopRequested
        acknowledgeLiveStop()
        return false
    end if
    if m.result.actualInitValidated <> true or m.result.decoderApproved <> true
        m.result.reason = "actual_init_required"
        return false
    end if
    address = CreateObject("roSocketAddress")
    if not address.SetAddress("127.0.0.1:" + m.listenPort.ToStr()) or not address.IsAddressValid()
        m.result.reason = "invalid_loopback_address"
        return false
    end if
    if not loopbackExactAddress(address.GetAddress(), address.GetPort(), m.listenPort)
        m.result.reason = "address_not_exact_loopback"
        return false
    end if
    m.listener = CreateObject("roStreamSocket")
    m.listener.SetMessagePort(m.port)
    if not m.listener.SetAddress(address)
        m.result.reason = "bind_failed"
        return false
    end if
    bound = m.listener.GetAddress()
    if bound = invalid
        m.result.reason = "bound_address_missing"
        return false
    end if
    if not loopbackExactAddress(bound.GetAddress(), bound.GetPort(), m.listenPort)
        m.result.reason = "bound_address_not_loopback"
        return false
    end if
    m.result.bound = true
    m.listener.NotifyReadable(true)
    if not m.listener.Listen(8) or not m.listener.IsListening()
        m.result.reason = "listen_failed"
        return false
    end if
    m.result.listening = true
    ready = liveReadyFields(bound)
    m.top.ready = ready
    return true
end function

sub acknowledgeLiveStop()
    if liveFailureRecorded() then return
    m.result.ok = true
    m.result.status = "cancelled"
    m.result.reason = "stop_requested"
end sub

function liveClientErrorStatus(reason as string) as integer
    if reason = "client_closed_before_headers" or reason = "receive_failed" or reason = "send_failed" then return 0
    if reason = "header_deadline_or_stop" or reason = "send_deadline_or_stop" then return 0
    if reason = "header_cap" or reason = "non_ascii_request" or reason = "request_body_or_pipeline" or reason = "request_method_path_headers_or_range" then return 400
    if reason = "unknown_request_path" or reason = "asset_not_advertised" then return 404
    if reason = "invalid_request_range" then return 416
    return -1
end function

function liveFailureRecorded() as boolean
    if not m.result.cleanupOk then return true
    if m.result.DoesExist("failureCategory") then return true
    if m.lastDiagnostics <> invalid
        if m.lastDiagnostics.failed then return true
    end if
    reason = m.result.reason
    return reason <> "not_started" and reason <> "stop_requested" and liveClientErrorStatus(reason) < 0
end function

function liveClientErrorHeader(status as integer, rangeBytes as integer) as dynamic
    phrase = ""
    if status = 400 then phrase = "400 Bad Request"
    if status = 404 then phrase = "404 Not Found"
    if status = 416 then phrase = "416 Range Not Satisfiable"
    if phrase = "" then return invalid
    crlf = Chr(13) + Chr(10)
    text = "HTTP/1.1 " + phrase + crlf + "Content-Length: 0" + crlf
    text += "Connection: close" + crlf + "Cache-Control: no-store" + crlf
    if status = 416
        if rangeBytes < 1 or rangeBytes > 4194304 then return invalid
        text += "Content-Range: bytes */" + rangeBytes.ToStr() + crlf
    end if
    bytes = loopbackAsciiBuffer(text + crlf)
    if bytes = invalid then return invalid
    if bytes.Count() > 512 then return invalid
    return bytes
end function

function tolerateLiveRequestFailure(requestClock as object) as boolean
    if liveFailureRecorded() then return false
    reason = m.result.reason
    status = liveClientErrorStatus(reason)
    if status < 0 then return false
    if not liveServerActive()
        if not m.top.stopRequested then m.result.reason = "server_deadline"
        return false
    end if
    if not pumpLiveServer(1)
        if not liveServerActive() and not m.top.stopRequested and not liveFailureRecorded() then m.result.reason = "server_deadline"
        return false
    end if
    if status > 0 and liveRequestActive(requestClock) and m.connection <> invalid
        m.connection.NotifyReadable(false)
        m.connection.NotifyWritable(true)
        if m.connection.eOK() and m.connection.IsWritable()
            bytes = liveClientErrorHeader(status, m.rangeErrorBytes)
            if bytes = invalid
                m.result.reason = "invalid_error_header"
                return false
            end if
            if sendLiveSpan(bytes, 0, bytes.Count(), requestClock)
                liveIncrement("errorResponses", 1 + 0&)
            else if liveFailureRecorded()
                return false
            end if
        end if
    end if
    if not liveServerActive()
        if not m.top.stopRequested and not liveFailureRecorded() then m.result.reason = "server_deadline"
        return false
    end if
    if not pumpLiveServer(1)
        if not liveServerActive() and not m.top.stopRequested and not liveFailureRecorded() then m.result.reason = "server_deadline"
        return false
    end if
    liveIncrement("clientErrors", 1 + 0&)
    m.result.lastClientReason = reason
    m.result.reason = "not_started"
    return true
end function

function liveServerActive() as boolean
    nowMs = liveServerNow()
    if m.top.stopRequested or m.counterExhausted then return false
    if m.steadyMode
        if not liveQuotaRefresh(m.httpQuota, nowMs)
            m.result.reason = "invalid_http_quota"
            return false
        end if
        return true
    end if
    return nowMs < 120000&
end function

function liveRequestActive(requestClock as object) as boolean
    return liveServerActive() and requestClock.TotalMilliseconds() < 8000
end function

sub retireExpiredPublications(nowMs as longinteger)
    keys = []
    for each key in m.publications
        entry = m.publications[key]
        if entry.publication.generation <> m.currentGeneration and entry.activeRequests = 0 and entry.holdUntilMs <= nowMs then keys.Push(key)
    end for
    for each key in keys
        nativeLiveRetire(m.liveState, m.publications[key].publication.generation)
        m.publications.Delete(key)
        liveIncrement("retiredPublications", 1 + 0&)
    end for
end sub

function pumpLiveServer(delayMs as integer) as boolean
    if not liveServerActive() then return false
    nowMs = liveServerNow()
    retireExpiredPublications(nowMs)
    event = wait(delayMs, m.port)
    nowMs = liveServerNow()
    if type(event) = "roUrlEvent"
        if nativeLiveHandleUrlEvent(m.liveState, event, nowMs) then liveIncrement("urlEventsHandled", 1 + 0&)
    end if
    if not liveServerActive() then return false
    nativeLiveTick(m.liveState, m.port, nowMs)
    liveIncrement("pumpCalls", 1 + 0&)
    diagnostics = loopbackSafeDiagnostics(nativeLiveDiagnostics(m.liveState), m.cacheBudgetBytes, m.steadyMode)
    if diagnostics = invalid
        m.result.reason = "invalid_helper_diagnostics"
        return false
    end if
    m.lastDiagnostics = diagnostics
    if diagnostics.cacheBytes > m.result.cacheBytesPeak then m.result.cacheBytesPeak = diagnostics.cacheBytes
    if diagnostics.peakCacheBytes > m.result.cacheBytesPeak then m.result.cacheBytesPeak = diagnostics.peakCacheBytes
    m.result.convertedSegmentPairs = diagnostics.segmentPairCount
    m.result.upstreamFetchCount = diagnostics.fetchCount
    m.result.upstreamPlaylistCount = diagnostics.playlistCount
    initAliasesValid = recordLiveInitAliases()
    if diagnostics.failed
        m.result.reason = "live_helper_failed"
        m.result["failureCategory"] = diagnostics.failureCategory
        recordSafeLiveFailure()
        return false
    end if
    if not initAliasesValid
        m.result.reason = "invalid_init_alias_count"
        return false
    end if
    publication = nativeLivePublication(m.liveState)
    if publication <> invalid
        ' Remember every advertised generation before validation, for cleanup.
        if type(publication) <> "roAssociativeArray"
            m.result.reason = "invalid_live_publication"
            return false
        end if
        maxGeneration = 256&
        if m.steadyMode then maxGeneration = 4294967295&
        if not loopbackInteger(publication.generation) or publication.generation < 1 or publication.generation > maxGeneration
            m.result.reason = "invalid_live_publication"
            return false
        end if
        key = publication.generation.ToStr()
        newGeneration = not m.publications.DoesExist(key)
        if not m.publications.DoesExist(key)
            m.publications[key] = { "publication": publication, "holdUntilMs": 0&, "activeRequests": 0&, "delivered": false }
            if m.adMetadataEnabled
                entry = m.publications[key]
                entry.adProjection = twitchAdClockServerPublication(m.liveState, publication)
                entry.adProjectionSeal = FormatJson(entry.adProjection)
                m.publications[key] = entry
            end if
            liveIncrement("publicationsObserved", 1 + 0&)
        end if
        if m.steadyMode
            if loopbackAssetSession(publication.initVideoId) <> m.sessionId or loopbackAssetSession(publication.initAudioId) <> m.sessionId
                m.result.reason = "publication_session_mismatch"
                return false
            end if
        end if
        assets = livePublicationAssets(publication)
        if assets = invalid then return false
        if FormatJson(m.publications[key].publication) <> FormatJson(publication)
            m.result.reason = "publication_generation_mutated"
            return false
        end if
        if publication.generation < m.currentGeneration
            m.result.reason = "publication_generation_regressed"
            return false
        end if
        if publication.DoesExist("version") and newGeneration
            if not validateLivePublicationCache(assets, publication) then return false
        end if
        m.currentPublication = publication
        m.currentGeneration = publication.generation
        retireExpiredPublications(nowMs)
        if m.publications.Count() > 12
            m.result.reason = "publication_pin_cap"
            return false
        end if
        if m.publications.Count() > m.result.maxPinnedGenerations then m.result.maxPinnedGenerations = m.publications.Count()
    end if
    return liveServerActive()
end function

sub liveRequestBackoff(requestClock as object)
    remaining = 8000 - requestClock.TotalMilliseconds()
    if not m.steadyMode
        wholeRemaining = 120000& - liveServerNow()
        if wholeRemaining < remaining then remaining = wholeRemaining
    end if
    delay = 10
    if remaining < delay then delay = remaining
    if delay > 0 then pumpLiveServer(CInt(delay))
end sub

function readLiveHeaders(requestClock as object) as dynamic
    buffer = loopbackReceiveBuffer()
    m.result.bufferLogicalCount = buffer.Count()
    if buffer.Count() <> 256
        m.result.reason = "invalid_logical_buffer_size"
        return invalid
    end if
    request = ""
    delimiter = Chr(13) + Chr(10) + Chr(13) + Chr(10)
    while liveRequestActive(requestClock)
        if not pumpLiveServer(10) then return invalid
        buffered = m.connection.GetCountRcvBuf()
        if buffered < 0
            m.result.reason = "invalid_receive_buffer_count"
            return invalid
        end if
        if buffered > 0 or m.connection.IsReadable()
            if buffer.Count() < 256
                m.result.reason = "invalid_receive_argument_bounds"
                return invalid
            end if
            if not liveCounterFits("receiveCalls", 1&) or not liveSocketPermit() then return invalid
            received = m.connection.Receive(buffer, 0, 256)
            liveIncrement("receiveCalls", 1 + 0&)
            if received = 0
                m.result.reason = "client_closed_before_headers"
                return invalid
            else if received < 0
                if not m.connection.eOK()
                    m.result.reason = "receive_failed"
                    return invalid
                end if
                liveIncrement("retryableReceives", 1 + 0&)
                liveRequestBackoff(requestClock)
            else
                if received > 256
                    m.result.reason = "invalid_receive_count"
                    return invalid
                else if request.Len() + received > 2048
                    m.result.reason = "header_cap"
                    return invalid
                end if
                for i = 0 to received - 1
                    code = buffer[i]
                    if (code < 32 and code <> 13 and code <> 10) or code > 126
                        m.result.reason = "non_ascii_request"
                        return invalid
                    end if
                    request += Chr(code)
                end for
                if request.Len() > m.result.headerBytesPeak then m.result.headerBytesPeak = request.Len()
                if request.InStr(delimiter) >= 0
                    if request.InStr(delimiter) + 4 <> request.Len()
                        m.result.reason = "request_body_or_pipeline"
                        return invalid
                    end if
                    return request
                end if
            end if
        end if
    end while
    if not liveFailureRecorded() then m.result.reason = "header_deadline_or_stop"
    return invalid
end function

function parseLiveRequest(request as string) as dynamic
    lines = request.Split(Chr(13) + Chr(10))
    if lines.Count() < 3 or lines.Count() > 40 then return invalid
    first = lines[0].Split(" ")
    if first.Count() <> 3 then return invalid
    if first[0] <> "GET" and first[0] <> "HEAD" then return invalid
    if first[2] <> "HTTP/1.1" and first[2] <> "HTTP/1.0" then return invalid
    route = first[1]
    track = ""
    id = ""
    unknownRoute = false
    if route = "/master.m3u8" then track = "master"
    if route = "/video.m3u8" then track = "video"
    if route = "/audio.m3u8" then track = "audio"
    if track = ""
        if route.Left(7) <> "/asset/"
            unknownRoute = true
        else
            id = route.Right(route.Len() - 7)
            if not loopbackAssetId(id) then return invalid
            session = loopbackAssetSession(id)
            if (m.steadyMode and session <> m.sessionId) or (not m.steadyMode and session <> "")
                m.result.reason = "asset_not_advertised"
                return invalid
            end if
        end if
    end if
    hostSeen = false
    rangeSeen = false
    range = ""
    for i = 1 to lines.Count() - 1
        line = lines[i]
        if line <> ""
            colon = line.InStr(":")
            if colon <= 0 then return invalid
            name = LCase(line.Left(colon))
            for j = 1 to name.Len()
                code = Asc(Mid(name, j, 1))
                if (code < 97 or code > 122) and (code < 48 or code > 57) and code <> 45 then return invalid
            end for
            value = line.Right(line.Len() - colon - 1).Trim()
            if name = "host"
                if hostSeen then return invalid
                hostSeen = true
                if value <> "127.0.0.1:" + m.listenPort.ToStr() then return invalid
            else if name = "range"
                if rangeSeen then return invalid
                rangeSeen = true
                range = value
            else if name = "content-length" or name = "transfer-encoding" or name = "authorization" or name = "cookie" or name = "if-range"
                return invalid
            else if name = "x-stitch-run"
                if value <> m.sessionId then return invalid
            end if
        end if
    end for
    if not hostSeen or (rangeSeen and range = "") then return invalid
    if unknownRoute
        m.result.reason = "unknown_request_path"
        return invalid
    end if
    return { "track": track, "assetId": id, "head": first[0] = "HEAD", "range": range }
end function

function advertisedAssetTrack(id as string) as string
    match = ""
    for each key in m.publications
        entry = m.publications[key]
        if entry.publication.generation = m.currentGeneration or entry.activeRequests > 0 or entry.holdUntilMs > liveServerNow()
            assets = livePublicationAssets(entry.publication)
            if assets = invalid then return ""
            for each asset in assets
                if asset.id = id
                    if match <> "" and match <> asset.track
                        m.result.reason = "asset_track_conflict"
                        return ""
                    end if
                    match = asset.track
                end if
            end for
        end if
    end for
    return match
end function

function livePublicationAssets(publication as dynamic) as dynamic
    assets = loopbackPublicationAssets(publication)
    if assets = invalid
        m.result.reason = "invalid_live_publication"
        return invalid
    end if
    if publication.DoesExist("version")
        if not loopbackBoolean(m.sourceTransitions) or m.sourceTransitions <> true or not m.steadyMode
            m.result.reason = "source_transitions_not_enabled"
            return invalid
        end if
        if m.result.actualInitValidated <> true or m.result.decoderApproved <> true
            m.result.reason = "actual_init_required"
            return invalid
        end if
    end if
    session = ""
    if m.steadyMode then session = m.sessionId
    for each asset in assets
        if loopbackAssetSession(asset.id) <> session
            m.result.reason = "publication_session_mismatch"
            return invalid
        end if
    end for
    return assets
end function

function liveCachedAssetValid(asset as dynamic, id as string, track as string) as boolean
    if not loopbackKeys(asset, ["id", "mime", "kind", "size", "data"]) then return false
    if asset.id <> id or asset.kind <> track or asset.mime <> track + "/mp4" then return false
    if not loopbackInteger(asset.size) or asset.size < 1 or asset.size > 4194304 then return false
    if type(asset.data) <> "roByteArray" then return false
    return asset.data.Count() = asset.size
end function

' Check one temporarily acquired body at a time before the new generation is
' made current. Core retains the advertised generation while these leases close.
function validateLivePublicationCache(assets as object, publication as object) as boolean
    for each record in assets
        if m.top.stopRequested then return false
        previousTrack = advertisedAssetTrack(record.id)
        if liveFailureRecorded() then return false
        if previousTrack <> "" and previousTrack <> record.track
            m.result.reason = "asset_track_conflict"
            return false
        end if
        for each key in m.publications
            entry = m.publications[key]
            if entry.publication.generation = m.currentGeneration or entry.activeRequests > 0 or entry.holdUntilMs > liveServerNow()
                oldRole = liveAssetRole(entry.publication, record.id)
                if oldRole <> ""
                    newRole = liveAssetRole(publication, record.id)
                    if oldRole <> newRole
                        m.result.reason = "asset_role_conflict"
                        return false
                    end if
                    if oldRole = "init" and liveInitPartner(entry.publication, record.id) <> liveInitPartner(publication, record.id)
                        m.result.reason = "asset_pair_conflict"
                        return false
                    end if
                end if
            end if
        end for
        asset = nativeLiveAcquire(m.liveState, record.id)
        if asset = invalid
            m.result.reason = "advertised_asset_missing"
            return false
        end if
        m.validationLease = record.id
        valid = liveCachedAssetValid(asset, record.id, record.track)
        asset = invalid
        nativeLiveRelease(m.liveState, m.validationLease)
        m.validationLease = ""
        if not valid
            m.result.reason = "invalid_cached_asset"
            return false
        end if
        if m.top.stopRequested then return false
    end for
    return true
end function

function liveAssetRole(publication as object, id as string) as string
    if id = publication.initVideoId or id = publication.initAudioId then return "init"
    for each segment in publication.segments
        if publication.DoesExist("version")
            if id = segment.initVideoId or id = segment.initAudioId then return "init"
        end if
        if id = segment.videoId or id = segment.audioId then return "media"
    end for
    return ""
end function

function liveInitPartner(publication as object, id as string) as string
    if id = publication.initVideoId then return publication.initAudioId
    if id = publication.initAudioId then return publication.initVideoId
    if publication.DoesExist("version")
        for each segment in publication.segments
            if id = segment.initVideoId then return segment.initAudioId
            if id = segment.initAudioId then return segment.initVideoId
        end for
    end if
    return ""
end function

function prepareLiveResponse(request as object) as dynamic
    if request.track <> ""
        publication = m.currentPublication
        if request.track <> "master"
            if publication = invalid
                m.result.reason = "invalid_live_publication"
                return invalid
            end if
            key = publication.generation.ToStr()
            entry = m.publications[key]
            entry.activeRequests += 1
            m.publications[key] = entry
            m.activeGeneration = publication.generation
        end if
        bytes = loopbackManifest(request.track, publication)
        if m.adMetadataEnabled and request.track <> "master"
            projection = entry.adProjection
            if FormatJson(projection) = entry.adProjectionSeal then bytes = twitchAdClockManifest(request.track, publication, projection)
        end if
        if bytes = invalid
            m.result.reason = "invalid_manifest_response"
            return invalid
        end if
        return { "data": bytes, "bytes": bytes.Count(), "mime": "application/vnd.apple.mpegurl", "track": request.track }
    end if
    track = advertisedAssetTrack(request.assetId)
    if track = ""
        if m.result.reason = "not_started" then m.result.reason = "asset_not_advertised"
        return invalid
    end if
    asset = nativeLiveAcquire(m.liveState, request.assetId)
    if asset = invalid
        m.result.reason = "advertised_asset_missing"
        return invalid
    end if
    m.activeLease = request.assetId
    m.result.reason = "invalid_cached_asset"
    if not liveCachedAssetValid(asset, request.assetId, track) then return invalid
    m.result.reason = "not_started"
    return { "data": asset.data, "bytes": asset.size, "mime": asset.mime, "track": track }
end function

function sendLiveSpan(bytes as object, start as integer, length as integer, requestClock as object) as boolean
    if type(bytes) <> "roByteArray" or start < 0 or length < 1 or start + length > bytes.Count()
        m.result.reason = "invalid_send_span_bounds"
        return false
    end if
    offset = start
    finish = start + length
    while offset < finish and liveRequestActive(requestClock)
        if not pumpLiveServer(1) then return false
        if m.connection.IsWritable()
            amount = finish - offset
            if amount > 16384 then amount = 16384
            if not m.steadyMode and amount > 134217728& - m.result.transmittedBytes
                m.result.reason = "transmitted_byte_cap"
                return false
            end if
            if amount < 1 or offset + amount > bytes.Count()
                m.result.reason = "invalid_send_argument_bounds"
                return false
            end if
            if not liveCounterFits("sendCalls", 1&) or not liveCounterFits("transmittedBytes", amount + 0&) then return false
            if not liveSocketPermit(amount + 0&) then return false
            sent = m.connection.Send(bytes, offset, amount)
            liveIncrement("sendCalls", 1 + 0&)
            if sent > amount
                m.result.reason = "invalid_send_count"
                return false
            else if sent > 0
                if m.steadyMode
                    if not liveQuotaCharge(m.httpQuota, m.socketAccountingNowMs, 0&, sent + 0&, 0&)
                        m.result.reason = "http_interval_quota"
                        return false
                    end if
                end if
                offset += sent
                liveIncrement("transmittedBytes", sent + 0&)
                if sent < amount then liveIncrement("shortWrites", 1 + 0&)
            else
                if not m.connection.eOK()
                    m.result.reason = "send_failed"
                    return false
                end if
                liveRequestBackoff(requestClock)
            end if
        end if
    end while
    if offset <> finish
        if not liveFailureRecorded() then m.result.reason = "send_deadline_or_stop"
        return false
    end if
    return true
end function

function serveLiveRequest(requestClock as object) as boolean
    m.rangeErrorBytes = 0
    raw = readLiveHeaders(requestClock)
    if raw = invalid then return false
    request = parseLiveRequest(raw)
    raw = invalid
    if request = invalid
        if m.result.reason = "not_started" then m.result.reason = "request_method_path_headers_or_range"
        return false
    end if
    response = prepareLiveResponse(request)
    if response = invalid
        return false
    end if
    m.activeBody = response.data
    m.rangeErrorBytes = response.bytes
    slice = loopbackRange(request.range, response.bytes)
    if not slice.ok
        m.result.reason = "invalid_request_range"
        return false
    end if
    crlf = Chr(13) + Chr(10)
    status = "200 OK"
    if slice.range then status = "206 Partial Content"
    header = "HTTP/1.1 " + status + crlf + "Content-Type: " + response.mime + crlf
    header += "Content-Length: " + slice.length.ToStr() + crlf + "Accept-Ranges: bytes" + crlf
    header += "Connection: close" + crlf + "Cache-Control: no-store" + crlf
    if slice.range
        lastByte = slice.start + slice.length - 1
        header += "Content-Range: bytes " + slice.start.ToStr() + "-" + lastByte.ToStr() + "/" + response.bytes.ToStr() + crlf
    end if
    header += crlf
    bytes = loopbackAsciiBuffer(header)
    if bytes = invalid or bytes.Count() > 512
        m.result.reason = "response_header_cap"
        return false
    end if
    m.connection.NotifyReadable(false)
    m.connection.NotifyWritable(true)
    if not sendLiveSpan(bytes, 0, bytes.Count(), requestClock) then return false
    bytes = invalid
    if not request.head
        if not sendLiveSpan(m.activeBody, slice.start, slice.length, requestClock) then return false
        if request.track = "master" then liveIncrement("masterRequests", 1 + 0&)
        if request.track = "video" then liveIncrement("videoPlaylistRequests", 1 + 0&)
        if request.track = "audio" then liveIncrement("audioPlaylistRequests", 1 + 0&)
        if request.track = "" and response.track = "video" then liveIncrement("videoBodies", 1 + 0&)
        if request.track = "" and response.track = "audio" then liveIncrement("audioBodies", 1 + 0&)
        if m.activeGeneration > 0
            key = m.activeGeneration.ToStr()
            entry = m.publications[key]
            entry.holdUntilMs = liveServerNow() + 6000
            if not entry.delivered then liveIncrement("deliveredPublications", 1 + 0&)
            entry.delivered = true
            m.publications[key] = entry
        end if
    else
        liveIncrement("headRequests", 1 + 0&)
    end if
    if slice.range then liveIncrement("rangeRequests", 1 + 0&)
    liveIncrement("completedRequests", 1 + 0&)
    return true
end function

sub closeLiveConnection()
    if m.connection <> invalid
        try
            m.connection.NotifyReadable(false)
            m.connection.NotifyWritable(false)
            m.connection.Close()
            m.result.connectionClosed = true
        catch error
            m.result.cleanupOk = false
        end try
        m.connection = invalid
    else
        m.result.connectionClosed = true
    end if
    if m.activeLease <> ""
        try
            nativeLiveRelease(m.liveState, m.activeLease)
        catch error
            m.result.cleanupOk = false
        end try
        m.activeLease = ""
    end if
    if loopbackString(m.validationLease)
        if m.validationLease <> ""
            try
                nativeLiveRelease(m.liveState, m.validationLease)
            catch error
                m.result.cleanupOk = false
            end try
            m.validationLease = ""
        end if
    end if
    if m.activeGeneration > 0
        key = m.activeGeneration.ToStr()
        if m.publications.DoesExist(key)
            entry = m.publications[key]
            entry.activeRequests -= 1
            if entry.activeRequests < 0 then m.result.cleanupOk = false
            m.publications[key] = entry
        else
            m.result.cleanupOk = false
        end if
        m.activeGeneration = 0
    end if
    m.activeBody = invalid
end sub

function liveReadyFields(bound as object) as object
    ready = {
        "sessionId": m.sessionId, "boundAddressText": bound.GetAddress(), "boundPort": bound.GetPort(),
        "metadata": m.config.metadata,
        "decoderApproved": m.result.decoderApproved, "actualInitValidated": m.result.actualInitValidated, "requestedDecoderFormat": m.result.requestedDecoderFormat,
        "sourceDelaySeconds": m.config.sourceDelaySeconds, "generationGraceMs": 6000,
        "generation": m.currentGeneration, "mediaSequence": m.currentPublication.mediaSequence,
        "segments": m.currentPublication.segments.Count(), "durationUs": m.currentPublication.durationUs,
        "maxCacheBytes": 16777216, "wholeDeadlineMs": 120000, "maxRequests": 256
    }
    if m.steadyMode
        ready.Delete("wholeDeadlineMs")
        ready.Delete("maxRequests")
        ready["sessionId"] = m.sessionId
        ready["steadyMode"] = true
        ready["maxCacheBytes"] = m.cacheBudgetBytes
        ready["httpQuotaIntervalMs"] = 60000
        ready["maxRequestsPerInterval"] = 256
        ready["maxBytesPerInterval"] = 134217728
        ready["maxSocketCallsPerInterval"] = 12000
    end if
    return ready
end function

' All absolute server timestamps use the validated Core clock; request clocks are relative.
function liveServerNow() as longinteger
    try
        rawMs = m.clock.TotalMilliseconds()
        if m.monotonicClock = invalid then m.monotonicClock = nativeLiveClockCreate(rawMs)
        nowMs = nativeLiveClockAdvance(m.monotonicClock, rawMs)
    catch error
        if not liveFailureRecorded() then m.result.reason = "invalid_server_clock"
        throw "invalid server clock"
    end try
    m.lastNowMs = nowMs
    return nowMs
end function

function liveCounterFits(field as string, amount as longinteger) as boolean
    if liveCounterNext(m.result[field], amount) <> invalid then return true
    m.counterExhausted = true
    m.result["countersComplete"] = false
    m.result["counterFailureField"] = field
    m.result.ok = false
    if not liveFailureRecorded() then m.result.reason = "http_counter_exhausted"
    return false
end function

sub liveIncrement(field as string, amount as longinteger)
    if not liveCounterFits(field, amount)
        ' Cleanup must release all resources even if telemetry is exhausted.
        if not m.closing then throw "HTTP counter exhausted"
        return
    end if
    m.result[field] = liveCounterNext(m.result[field], amount)
end sub

function liveSocketPermit(bytes = 0& as longinteger, requests = 0& as longinteger) as boolean
    if not m.steadyMode then return true
    nowMs = liveServerNow()
    if not liveQuotaFits(m.httpQuota, nowMs, requests, bytes, 1&)
        m.result.reason = "http_interval_quota"
        return false
    end if
    if not liveQuotaCharge(m.httpQuota, nowMs, 0&, 0&, 1&)
        m.result.reason = "invalid_http_quota"
        return false
    end if
    m.socketAccountingNowMs = nowMs
    return true
end function

sub recordSafeLiveFailure()
    status = nativeLiveStatus(m.liveState)
    if type(status) <> "roAssociativeArray" then return
    reason = status.error
    if not loopbackString(reason) then return
    if not CreateObject("roRegex", "^native-(live|demux): [A-Za-z0-9 /_.-]{1,150}$", "").IsMatch(reason) then return
    m.result["helperFailureReason"] = reason
    context = m.liveState.httpFailure
    if type(context) <> "roAssociativeArray" then return
    if loopbackInteger(context.status)
        if context.status >= -1000 and context.status <= 599 then m.result["upstreamStatus"] = context.status
    end if
    if loopbackString(context.kind)
        if context.kind = "playlist" or context.kind = "init" or context.kind = "segment" then m.result["upstreamKind"] = context.kind
    end if
    if loopbackString(context.phase)
        if context.phase = "head" or context.phase = "get" then m.result["upstreamPhase"] = context.phase
    end if
    if loopbackBoolean(context.hasContentRange) then m.result["upstreamHasRange"] = context.hasContentRange
end sub

' Optional on legacy fixture states; never fabricate an observed successful alias.
function recordLiveInitAliases() as boolean
    if m.liveState = invalid then return true
    if not m.liveState.DoesExist("initAliasCount") then return not m.result.DoesExist("initAliasCount")
    count = m.liveState.initAliasCount
    if not loopbackInteger(count) then return false
    if count < 0 or count > 4294967295& then return false
    m.result["initAliasCount"] = count + 0&
    return true
end function

' Validate primitive Task inputs before socket/network work; never log the descriptor.
function prepareRokuDemuxInput() as boolean
    if m.sessionId = ""
        m.result.reason = "invalid_session_id"
        return false
    end if
    if m.top.stopRequested
        acknowledgeLiveStop()
        return false
    end if
    if not loopbackBoolean(m.top.experimentalMode) or m.top.experimentalMode <> true
        m.result.reason = "experimental_mode_required"
        return false
    end if
    transitions = m.top.enableSourceTransitions
    if type(m.top) = "roAssociativeArray"
        if not m.top.DoesExist("enableSourceTransitions") then transitions = false
    end if
    if not loopbackBoolean(transitions)
        m.result.reason = "invalid_source_transition_policy"
        return false
    end if
    if not rokuDemuxCacheBudgetValid(m.top.cacheBudgetBytes)
        m.result.reason = "invalid_cache_budget"
        return false
    end if
    port = m.top.listenPort
    if not loopbackInteger(port)
        m.result.reason = "invalid_loopback_port"
        return false
    end if
    if port = 0 then port = 49371
    if port < 49152 or port > 65535
        m.result.reason = "invalid_loopback_port"
        return false
    end if
    descriptor = m.top.inputDescriptor
    m.top.inputDescriptor = invalid
    if not rokuDemuxDescriptorValid(descriptor)
        m.result.reason = "invalid_input_descriptor"
        return false
    end if
    m.listenPort = CInt(port)
    m.steadyMode = true
    m.sourceTransitions = transitions
    m.cacheBudgetBytes = m.top.cacheBudgetBytes
    m.httpQuota = liveQuotaCreate(liveServerNow())
    m.config = { "trustedMediaUrl": descriptor["sourceUrl"], "approvedOrigins": descriptor["approvedOrigins"], "metadata": descriptor["metadata"], "sourceDelaySeconds": 0 }
    descriptor = invalid
    m.result["steadyMode"] = true
    return true
end function

function liveSteadyOptions() as dynamic
    if not loopbackBoolean(m.steadyMode) or m.steadyMode <> true or not loopbackSteadySessionIdValid(m.sessionId) then return invalid
    if not loopbackBoolean(m.sourceTransitions) then return invalid
    options = { "mode": "steady", "sessionId": m.sessionId }
    if m.sourceTransitions then options["sourceTransitions"] = true
    return options
end function
