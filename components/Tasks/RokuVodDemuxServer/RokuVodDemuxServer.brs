sub init()
    m.top.functionName = "runServer"
end sub

sub runServer()
    rvsInitialize()
    try
        rvsServe()
    catch error
        rvsFailure("native_operation")
    end try
    rvsCleanup()
    m.top.result = m.result
end sub

sub rvsInitialize()
    m.sessionId = m.top.sessionId
    m.clock = CreateObject("roTimespan")
    m.clockRaw = invalid
    m.clockTotal = 0&
    m.lastNow = 0&
    m.port = invalid
    m.listener = invalid
    m.connection = invalid
    m.fetch = invalid
    m.config = invalid
    m.index = invalid
    m.cache = invalid
    m.tracks = invalid
    m.timing = invalid
    m.input = invalid
    m.conversion = invalid
    m.reservation = invalid
    m.activeLease = invalid
    m.activeBody = invalid
    m.manifestCursor = invalid
    m.quota = invalid
    m.closing = false
    m.result = { ok: false, status: "failed", reason: "not_started", sessionId: m.sessionId, mode: "vod", decoderApproved: false, actualInitValidated: false, requestedDecoderFormat: "", bound: false, listening: false, requests: 0&, completedRequests: 0&, clientErrors: 0&, transmittedBytes: 0&, sendCalls: 0&, receiveCalls: 0&, pumpCalls: 0&, convertedPairs: 0&, cacheBytesPeak: 0&, fetchCount: 0&, cacheBudgetBytes: 25165824&, maxRequestsPerInterval: 256, maxBytesPerInterval: 134217728&, maxSocketCallsPerInterval: 12000, hardPreBodyTransferCapVerified: false, redirectDisableVerified: false, listenerClosed: false, connectionClosed: false, helperClosed: false, cacheReferencesReleased: false, cleanupOk: true }
end sub

' Component-local adapter for the unchanged actual-init gate. No LIVE state is constructed.
sub nlCheck(ok as boolean, reason as string)
    if not ok then throw "vod-server:actual_init_rejected"
end sub

function rvsNow() as longinteger
    raw = m.clock.TotalMilliseconds()
    if not loopbackInteger(raw) or raw < -2147483648& or raw > 4294967295& then throw "vod-server:clock"
    if raw < 0 then raw += 4294967296&
    if m.clockRaw = invalid
        m.clockRaw = raw
    else
        delta = raw - m.clockRaw
        if delta < 0 then delta += 4294967296&
        if delta > 60000& or m.clockTotal > 4294967235000& - delta then throw "vod-server:clock"
        m.clockTotal += delta
        m.clockRaw = raw
    end if
    m.lastNow = m.clockTotal
    return m.lastNow
end function

sub rvsFailure(reason as string)
    if m.result.reason = "not_started" or m.result.reason = "serving"
        m.result.reason = reason
        m.result.ok = false
        m.result.status = "failed"
    end if
end sub

sub rvsCount(name as string, amount as longinteger)
    nextValue = liveCounterNext(m.result[name], amount)
    if nextValue = invalid
        rvsFailure("counter_exhausted")
        throw "vod-server:counter_exhausted"
    end if
    m.result[name] = nextValue
end sub

function rvsActive() as boolean
    if m.closing then return false
    if not rokuVodSessionId(m.top.sessionId) or m.top.sessionId <> m.sessionId
        rvsFailure("stale_owner")
        return false
    end if
    if m.top.stopRequested
        if m.result.reason = "not_started" or m.result.reason = "serving"
            m.result.ok = true
            m.result.status = "stopped"
            m.result.reason = "stopped"
        end if
        return false
    end if
    return m.result.reason = "not_started" or m.result.reason = "serving"
end function

function rvsPump(delayMs as integer) as boolean
    if not rvsActive() then return false
    event = Wait(delayMs, m.port)
    nowMs = rvsNow()
    rvsCount("pumpCalls", 1&)
    if not rvsActive() then return false
    if m.fetch <> invalid
        if Type(event) = "roUrlEvent" then unused = rokuVodFetchHandleUrlEvent(m.fetch, event, nowMs)
        if not rokuVodFetchPump(m.fetch, nowMs, m.top.stopRequested)
            rvsFailure("upstream_failed")
            m.result["fetchReason"] = m.fetch.reason
            return false
        end if
        m.result.fetchCount = m.fetch.totalTransfers
    end if
    return rvsActive()
end function

function rvsFetch(kind as string, entryNo as integer, deadline as longinteger) as dynamic
    if not rvsActive() or rvsNow() >= deadline then return invalid
    if not rokuVodFetchBegin(m.fetch, kind, entryNo, m.port, rvsNow())
        rvsFailure("upstream_failed")
        m.result["fetchReason"] = m.fetch.reason
        return invalid
    end if
    while rvsActive() and rvsNow() < deadline
        if not rvsPump(20) then return invalid
        if not rvsWithin(deadline) then return invalid
        if m.fetch.phase = "ready"
            output = rokuVodFetchTake(m.fetch)
            if output = invalid or output.kind <> kind or output.entryNo <> entryNo
                rvsFailure("upstream_identity")
                return invalid
            end if
            return output.data
        end if
    end while
    if rvsActive() then rvsFailure("acquisition_deadline")
    return invalid
end function

function rvsPrepare() as boolean
    if not rokuVodSessionId(m.sessionId) or not loopbackBoolean(m.top.experimentalMode) or not m.top.experimentalMode
        rvsFailure("invalid_owner")
        return false
    end if
    if not loopbackInteger(m.top.cacheBudgetBytes) or m.top.cacheBudgetBytes <> 25165824 or not loopbackInteger(m.top.listenPort)
        rvsFailure("invalid_config")
        return false
    end if
    if m.top.listenPort <> 0 and not loopbackPortValid(m.top.listenPort)
        rvsFailure("invalid_port")
        return false
    end if
    if not rokuVodDescriptorValid(m.top.inputDescriptor)
        rvsFailure("invalid_descriptor")
        return false
    end if
    m.config = ParseJson(FormatJson(m.top.inputDescriptor))
    m.fetch = rokuVodFetchCreate(m.config, m.sessionId)
    if m.fetch = invalid then return false
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("stopRequested", m.port)
    m.quota = liveQuotaCreate(rvsNow())
    deadline = rvsNow() + 45000&
    if rvsFetch("master", -1, deadline) <> true then return false
    m.index = rvsFetch("playlist", -1, deadline)
    if m.index = invalid then return false
    m.cache = rokuVodCacheCreate(m.sessionId, m.index)
    if m.cache = invalid
        rvsFailure("index_budget")
        return false
    end if
    if not rvsConvert(-1, deadline) then return false
    return rvsWithin(deadline) and m.result.actualInitValidated and m.result.decoderApproved
end function

function rvsConvert(entryNo as integer, outerDeadline as longinteger) as boolean
    deadline = rvsNow() + 15000&
    if outerDeadline < deadline then deadline = outerDeadline
    m.reservation = rokuVodReserve(m.cache, entryNo, m.sessionId)
    if m.reservation = invalid
        rvsFailure("work_reservation")
        return false
    end if
    kind = "media"
    if entryNo = -1 then kind = "init"
    m.input = rvsFetch(kind, entryNo, deadline)
    if m.input = invalid then return false
    pair = invalid
    if entryNo = -1
        if not rvsActive() or rvsNow() >= deadline then return false
        actual = nativeLiveInspectInitMetadata(m.input)
        if not rvsWithin(deadline) then return false
        if actual = invalid or actual.width > m.config["metadata"].width or actual.height > m.config["metadata"].height
            rvsFailure("init_envelope")
            return false
        end if
        validateLiveInitOutput(m.input)
        if not rvsWithin(deadline) or not m.result.actualInitValidated or not m.result.decoderApproved then return false
        m.tracks = nativeDemuxBulkInspectInit(m.input)
        m.timing = rokuVodInitTiming(m.input)
        if m.tracks = invalid or m.timing = invalid
            rvsFailure("init_timing")
            return false
        end if
        ' Each expensive native split is bounded and has an independent stop/deadline check.
        video = nativeDemuxBulkInit(m.input, "video")
        if not rvsPump(1) or rvsNow() >= deadline then return false
        audio = nativeDemuxBulkInit(m.input, "audio")
        if not rvsActive() or rvsNow() >= deadline then return false
        pair = { video: video, audio: audio }
        m.input = invalid
    else
        plan = rokuVodChunkPlan(m.input, m.tracks, m.timing)
        if not rvsWithin(deadline) then return false
        if plan = invalid
            rvsFailure("chunk_plan")
            return false
        end if
        m.conversion = rokuVodChunkBegin(m.input, m.tracks, plan)
        m.input = invalid
        if m.conversion = invalid or not rvsWithin(deadline) then return false
        while rvsActive() and rvsNow() < deadline
            if not rvsPump(1) then return false
            if not rvsWithin(deadline) then return false
            progress = rokuVodChunkStep(m.conversion, m.top.stopRequested)
            if not rvsActive() or rvsNow() >= deadline then return false
            if progress.phase = "complete"
                pair = progress.pair
                exit while
            else if progress.phase = "failed" or progress.phase = "cancelled"
                rvsFailure("chunk_conversion")
                return false
            end if
        end while
        if pair = invalid
            if rvsActive() then rvsFailure("conversion_deadline")
            return false
        end if
        if not rokuVodChunkClose(m.conversion)
            rvsFailure("conversion_cleanup")
            return false
        end if
        m.conversion = invalid
    end if
    if not rvsActive() or rvsNow() >= deadline then return false
    ' All input/chunk work has been released before the atomic reservation is consumed.
    reservation = m.reservation
    if not rokuVodStore(m.cache, reservation.id, m.sessionId, entryNo, pair)
        pair = invalid
        rvsFailure("pair_store")
        return false
    end if
    pair = invalid
    m.reservation = invalid
    if m.cache.cacheBytes > m.result.cacheBytesPeak then m.result.cacheBytesPeak = m.cache.cacheBytes
    rvsCount("convertedPairs", 1&)
    return rvsWithin(deadline)
end function

function rvsBind() as boolean
    if not rvsActive() or not m.result.actualInitValidated or not m.result.decoderApproved then return false
    m.listenPort = m.top.listenPort
    if m.listenPort = 0 then m.listenPort = 49152 + (Rnd(16384) - 1)
    address = CreateObject("roSocketAddress")
    if not address.SetAddress("127.0.0.1:" + m.listenPort.ToStr()) or not address.IsAddressValid() then return false
    if not loopbackExactAddress(address.GetAddress(), address.GetPort(), m.listenPort) then return false
    m.listener = CreateObject("roStreamSocket")
    m.listener.SetMessagePort(m.port)
    if not m.listener.SetAddress(address) then return false
    bound = m.listener.GetAddress()
    if bound = invalid or not loopbackExactAddress(bound.GetAddress(), bound.GetPort(), m.listenPort) then return false
    m.result.bound = true
    m.listener.NotifyReadable(true)
    if not m.listener.Listen(8) or not m.listener.IsListening() then return false
    m.result.listening = true
    if not rvsActive() then return false
    m.top.ready = rvsReady(bound)
    return true
end function

function rvsReady(bound as object) as object
    return { "sessionId": m.sessionId, "boundAddressText": bound.GetAddress(), "boundPort": bound.GetPort(), "metadata": m.config["metadata"], "decoderApproved": m.result.decoderApproved, "actualInitValidated": m.result.actualInitValidated, "requestedDecoderFormat": m.result.requestedDecoderFormat, "mode": "vod", "totalDurationUs": m.index.totalUs, "masterPath": "/vod/" + m.sessionId + "/master.m3u8" }
end function

sub rvsServe()
    if not rvsPrepare() then return
    if not rvsBind()
        rvsFailure("bind_failed")
        return
    end if
    m.result.reason = "serving"
    while rvsPump(20)
        if m.listener.IsReadable()
            m.connection = m.listener.Accept()
            if m.connection <> invalid
                m.connection.SetMessagePort(m.port)
                m.connection.NotifyReadable(true)
                m.connection.NotifyWritable(true)
                served = rvsRequest()
                if not rvsCloseConnection() then exit while
                if served then rvsCount("completedRequests", 1&)
            end if
        end if
    end while
end sub

function rvsSocketPermit(bytes = 0& as longinteger, requests = 0& as longinteger) as boolean
    nowMs = rvsNow()
    if not liveQuotaFits(m.quota, nowMs, requests, bytes, 1&) or not liveQuotaCharge(m.quota, nowMs, requests, 0&, 1&)
        rvsFailure("http_interval_quota")
        return false
    end if
    return true
end function

function rvsWithin(deadline as longinteger) as boolean
    return rvsActive() and rvsNow() < deadline
end function

function rvsHeaders(deadline as longinteger) as dynamic
    buffer = loopbackReceiveBuffer()
    if buffer.Count() <> 256 then return invalid
    raw = ""
    delimiter = Chr(13) + Chr(10) + Chr(13) + Chr(10)
    while rvsActive() and rvsNow() < deadline
        if not rvsPump(10) then return invalid
        if not rvsWithin(deadline) then return invalid
        buffered = m.connection.GetCountRcvBuf()
        if buffered < 0 then return invalid
        if buffered > 0 or m.connection.IsReadable()
            if not rvsSocketPermit() then return invalid
            if not rvsWithin(deadline) then return invalid
            received = m.connection.Receive(buffer, 0, 256)
            rvsCount("receiveCalls", 1&)
            if not rvsWithin(deadline) then return invalid
            if received = 0 or received > 256 then return invalid
            if received < 0
                if not m.connection.eOK() then return invalid
            else
                if raw.Len() + received > 8192 then return invalid
                for i = 0 to received - 1
                    code = buffer[i]
                    if (code < 32 and code <> 13 and code <> 10) or code > 126 then return invalid
                    raw += Chr(code)
                end for
                if raw.InStr(delimiter) >= 0
                    if raw.InStr(delimiter) + 4 <> raw.Len() then return invalid
                    if not rvsWithin(deadline) then return invalid
                    return raw
                end if
            end if
        end if
    end while
    return invalid
end function

function rvsResponse(request as object, deadline as longinteger) as dynamic
    if not rvsWithin(deadline) then return invalid
    route = rokuVodRoute(request.path, m.sessionId, m.index.count)
    if route = invalid or FormatJson(route) <> FormatJson(request.route) then return invalid
    size = 0
    if route.kind = "manifest"
        if route.track = "master"
            m.activeBody = rokuVodMasterManifest(m.config["metadata"], m.sessionId)
            if m.activeBody = invalid then return invalid
            size = m.activeBody.Count()
        else
            m.manifestCursor = rokuVodManifestBegin(m.index, route.track, m.sessionId)
            if m.manifestCursor = invalid then return invalid
            size = m.manifestCursor.length
        end if
    else
        if not rokuVodCacheAuthorize(m.cache, m.sessionId, route.track, route.entryNo) then return invalid
        m.activeLease = rokuVodAcquire(m.cache, route.track, route.entryNo, m.sessionId)
        if m.activeLease = invalid
            if m.cache.reason <> "cache_miss" then return invalid
            if not rvsConvert(route.entryNo, deadline) then return invalid
            m.activeLease = rokuVodAcquire(m.cache, route.track, route.entryNo, m.sessionId)
        end if
        if m.activeLease = invalid then return invalid
        m.activeBody = m.activeLease.data
        size = m.activeLease.size
    end if
    if not rvsWithin(deadline) then return invalid
    response = rokuVodResponseHeader(request, m.sessionId, m.index.count, size)
    if not rvsWithin(deadline) then return invalid
    return response
end function

function rvsSend(bytes as object, start as integer, length as integer, deadline as longinteger) as boolean
    if Type(bytes) <> "roByteArray" or start < 0 or length < 1 or start + length > bytes.Count() then return false
    offset = start
    finish = start + length
    while rvsActive() and rvsNow() < deadline and offset < finish
        if not rvsPump(1) then return false
        if not rvsWithin(deadline) then return false
        if m.connection.IsWritable()
            amount = finish - offset
            if amount > 16384 then amount = 16384
            if not rvsSocketPermit(amount + 0&) then return false
            if not rvsWithin(deadline) then return false
            sent = m.connection.Send(bytes, offset, amount)
            rvsCount("sendCalls", 1&)
            if sent > amount then return false
            if sent > 0
                if not liveQuotaCharge(m.quota, rvsNow(), 0&, sent + 0&, 0&) then return false
                rvsCount("transmittedBytes", sent + 0&)
                offset += sent
            else if not m.connection.eOK()
                return false
            end if
            if not rvsWithin(deadline) then return false
        end if
    end while
    return offset = finish and rvsWithin(deadline)
end function

function rvsManifest(request as object, slice as object, deadline as longinteger) as boolean
    first = slice.start
    last = first + slice.length
    position = 0
    while rvsActive() and rvsNow() < deadline
        span = rokuVodManifestSpan(m.index, request.route.track, m.sessionId, m.manifestCursor, 16384)
        if not rvsWithin(deadline) then return false
        if span = invalid then return false
        m.manifestCursor = span.cursor
        length = span.bytes.Count()
        from = 0
        if first > position then from = first - position
        spanEnd = length
        if last < position + length then spanEnd = last - position
        if spanEnd > from and from >= 0
            if not rvsSend(span.bytes, from, spanEnd - from, deadline) then return false
        end if
        position += length
        if position >= last then return rvsWithin(deadline)
        if span.done then return false
        if not rvsPump(1) then return false
    end while
    return false
end function

function rvsRequest() as boolean
    if not rvsSocketPermit(0&, 1&) then return false
    rvsCount("requests", 1&)
    raw = rvsHeaders(rvsNow() + 8000&)
    if raw = invalid then return rvsClientFailure()
    request = rokuVodRequest(raw, m.sessionId, m.index.count, m.listenPort)
    if request = invalid then return rvsClientFailure()
    response = rvsResponse(request, rvsNow() + 15000&)
    if response = invalid then return rvsClientFailure()
    deadline = rvsNow() + 8000&
    if not rvsSend(response.bytes, 0, response.bytes.Count(), deadline) then return rvsClientFailure()
    if response.head then return true
    if m.activeBody <> invalid then return rvsSend(m.activeBody, response.range.start, response.range.length, deadline)
    return rvsManifest(request, response.range, deadline)
end function

function rvsClientFailure() as boolean
    rvsCount("clientErrors", 1&)
    return false
end function

function rvsCloseConnection() as boolean
    clean = true
    if m.connection <> invalid
        try
            m.connection.NotifyReadable(false)
            m.connection.NotifyWritable(false)
            m.connection.Close()
            m.connection = invalid
        catch error
            clean = false
        end try
    end if
    ' Never release a body lease while its socket still owns an active send.
    if clean and m.activeLease <> invalid
        clean = rokuVodRelease(m.cache, m.activeLease.id, m.sessionId)
        if clean then m.activeLease = invalid
    end if
    if clean
        m.activeBody = invalid
        m.manifestCursor = invalid
    else
        m.result.cleanupOk = false
        rvsFailure("cleanup_blocked")
    end if
    m.result.connectionClosed = clean and m.connection = invalid
    return clean
end function

sub rvsCleanup()
    m.closing = true
    connectionClean = rvsCloseConnection()
    listenerClean = true
    if m.listener <> invalid
        try
            m.listener.NotifyReadable(false)
            m.listener.Close()
            m.listener = invalid
        catch error
            listenerClean = false
        end try
    end if
    m.result.listenerClosed = listenerClean and m.listener = invalid
    fetchClean = true
    if m.fetch <> invalid then fetchClean = rokuVodFetchClose(m.fetch)
    if fetchClean then m.fetch = invalid
    conversionClean = true
    if m.conversion <> invalid
        try
            conversionClean = rokuVodChunkClose(m.conversion)
            if conversionClean then m.conversion = invalid
        catch error
            conversionClean = false
        end try
    end if
    if conversionClean and fetchClean then m.input = invalid
    reservationClean = true
    if m.reservation <> invalid
        reservationClean = conversionClean and fetchClean and m.input = invalid
        reservationClean = rokuVodCancelReservation(m.cache, m.reservation.id, reservationClean, m.sessionId)
        if reservationClean then m.reservation = invalid
    end if
    cacheClean = true
    if m.cache <> invalid then cacheClean = rokuVodCacheClose(m.cache)
    m.result.helperClosed = fetchClean and conversionClean and reservationClean and cacheClean
    if m.result.helperClosed
        m.cache = invalid
        m.index = invalid
        m.tracks = invalid
        m.timing = invalid
        m.config = invalid
    end if
    if m.port <> invalid
        m.top.UnobserveField("stopRequested")
        m.port = invalid
    end if
    m.top.inputDescriptor = invalid
    m.result.cacheReferencesReleased = cacheClean and m.cache = invalid and m.index = invalid and m.activeBody = invalid and m.activeLease = invalid and m.manifestCursor = invalid
    m.result.cleanupOk = m.result.cleanupOk and connectionClean and listenerClean and m.result.helperClosed and m.result.cacheReferencesReleased
    if not m.result.cleanupOk
        m.result.ok = false
        m.result.status = "failed"
        m.result.reason = "cleanup_blocked"
    end if
end sub
