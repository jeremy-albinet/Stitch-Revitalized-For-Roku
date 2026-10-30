' Private roUrlTransfer adapter. Root owns one Task/event loop and a trusted CDN URL.
function nlInputPath() as string
    return "tmp:/stitch-live-fetch-input.bin"
end function

function nativeLiveInputCleanup() as boolean
    try
        fs = CreateObject("roFileSystem")
        path = nlInputPath()
        if not fs.Exists(path) then return true
        stat = fs.Stat(path)
        if Type(stat) <> "roAssociativeArray" then return false
        if stat.type <> "file" then return false
        if not fs.Delete(path) then return false
        return not fs.Exists(path)
    catch e
        return false
    end try
end function

function nlFullRange(text as string, limit as integer) as integer
    nlCheck(CreateObject("roRegex", "^bytes 0-[0-9]{1,10}/[0-9]{1,10}$", "").IsMatch(text), "Content-Range malformed")
    range = text.Mid(8).Split("/")
    last = nlNatural(range[0], 4294967295&)
    total = nlNatural(range[1], limit + 0&)
    nlCheck(total > 0& and last = total - 1&, "incomplete or mismatched Content-Range")
    nlCheck(text = "bytes 0-" + last.ToStr() + "/" + total.ToStr(), "Content-Range must be canonical")
    return CInt(total)
end function

function nlHeaders(array as object, status as integer, limit as integer, head as boolean, experimental = false as boolean) as integer
    nlCheck(Type(array) = "roArray" and array.Count() <= 64, "response header count bound")
    headers = {}
    total = 0
    for each entry in array
        nlCheck(Type(entry) = "roAssociativeArray" and entry.Count() = 1, "response header shape")
        for each name in entry
            value = entry[name]
            nlCheck(nlString(value) and name.Len() >= 1 and name.Len() <= 128 and value.Len() <= 4096, "response header length bound")
            nlCheck(CreateObject("roRegex", "^[A-Za-z0-9-]+$", "").IsMatch(name), "response header name malformed")
            for i = 0 to value.Len() - 1
                code = Asc(value.Mid(i, 1))
                nlCheck((code >= 32 and code <= 126) or code = 9, "response header character unsupported")
            end for
            total += name.Len() + value.Len()
            nlCheck(total <= 8192, "response header aggregate bound")
            key = LCase(name)
            if key = "content-length" or key = "content-range" or key = "content-encoding" or key = "transfer-encoding"
                nlCheck(not headers.DoesExist(key), "duplicate framing header")
                headers[key] = value.Trim()
            end if
        end for
    end for
    if headers.DoesExist("transfer-encoding")
        nlCheck(experimental and LCase(headers["transfer-encoding"]) = "chunked" and not headers.DoesExist("content-length"), "transfer encoding unsupported")
    end if
    if headers.DoesExist("content-encoding") then nlCheck(LCase(headers["content-encoding"]) = "identity", "compressed response unsupported")
    length = -1&
    if headers.DoesExist("content-length")
        length = nlNatural(headers["content-length"], limit + 0&)
        nlCheck(length > 0&, "empty response unsupported")
    else
        nlCheck(experimental, "Content-Length required")
    end if
    if head
        nlCheck(status = 200 and not headers.DoesExist("content-range"), "HEAD status or range unsupported")
    else if status = 206
        nlCheck(headers.DoesExist("content-range"), "Content-Range required")
        rangeCount = nlFullRange(headers["content-range"], limit)
        nlCheck(length = -1& or length = rangeCount, "incomplete or mismatched Content-Range")
        length = rangeCount
    else
        nlCheck(status = 200 and not headers.DoesExist("content-range"), "GET status or range unsupported")
    end if
    return CInt(length)
end function

function nlCompletedCount(stat as dynamic, framingCount as integer, limit as integer) as integer
    nlCheck(Type(stat) = "roAssociativeArray", "completed input stat unavailable")
    nlCheck(stat.type = "file", "completed input type invalid")
    nlInteger(stat.size, 1&, limit + 0&)
    nlCheck(framingCount = -1 or stat.size = framingCount, "completed input count mismatch")
    return CInt(stat.size)
end function

function nlSafeError(message as string) as string
    if message.Left(13) = "native-live: " or message.Left(14) = "native-demux: " then return message
    return "native-live: native operation failed"
end function

function nlCancelInput(state as object) as boolean
    cancelled = true
    op = state.op
    state.op = invalid
    if op <> invalid
        transfer = op.transfer
        op.transfer = invalid
        if transfer <> invalid
            try
                cancelled = transfer.AsyncCancel()
            catch e
                cancelled = false
            end try
            transfer = invalid ' Dropping the retained native object also stops its operation.
        end if
    end if
    clean = true
    if state.ownInputFile
        clean = nativeLiveInputCleanup()
        if clean then state.ownInputFile = false
    end if
    return cancelled and clean
end function

sub nlStart(state as object, intent as object, phase as string, port as object, nowMs as dynamic)
    nlCheck(state.op = invalid and state.input = invalid, "upstream operation overlaps conversion")
    approved = nlHttps(intent.url)
    permitted = false
    for each origin in state.approvedOrigins
        if origin = approved.origin then permitted = true
    end for
    nlCheck(permitted, "request origin not approved")
    nlUseWork(state, "transfer", nowMs, false)
    fs = CreateObject("roFileSystem")
    nlCheck(not fs.Exists(nlInputPath()), "input file already owned")
    transfer = CreateObject("roUrlTransfer")
    nlCheck(transfer <> invalid, "transfer API unavailable")
    transfer.SetMessagePort(port)
    nlCheck(transfer.SetCertificatesFile("common:/certs/ca-bundle.crt"), "CA bundle unavailable")
    nlCheck(transfer.EnablePeerVerification(true) and transfer.EnableHostVerification(true), "TLS verification unavailable")
    nlCheck(transfer.EnableEncodings(false) and transfer.EnableResume(false), "transfer options unavailable")
    nlCheck(transfer.SetMinimumTransferRate(1, 2), "transfer rate bound unavailable")
    headers = { "Accept-Encoding": "identity" }
    if phase = "get" then headers.Range = "bytes=0-" + (intent.limit - 1).ToStr()
    nlCheck(transfer.SetHeaders(headers), "request headers unavailable")
    transfer.SetUrl(intent.url)
    ' A hung transfer is retried once (see nlTimeout) within the upstream
    ' progress bound; a short low-latency buffer may run dry sooner.
    op = { transfer: transfer, identity: transfer.GetIdentity(), kind: intent.kind, url: intent.url, limit: intent.limit, phase: phase, deadline: nowMs + 6000& }
    state.op = op ' Retain exactly one native object before starting it.
    nlUseWork(state, "transfer", nowMs)
    if phase = "head"
        nlCheck(transfer.AsyncHead(), "HEAD could not start")
    else
        state.ownInputFile = true
        nlCheck(transfer.AsyncGetToFile(nlInputPath()), "GET could not start")
        if intent.kind = "playlist" then nativeLivePlaylistStarted(state, nowMs)
    end if
end sub

sub nlTimeout(state as object)
    op = state.op
    ' Retry one hung transfer for the same intent regardless of dispatch order.
    ' A second timeout on that URL is fatal.
    retried = false
    if state.DoesExist("timedOutUrl") then retried = state.timedOutUrl = op.url
    nlCheck(not retried and nlString(op.url), "upstream operation deadline")
    state.timedOutUrl = op.url
    nlCheck(nlCancelInput(state), "cancellation or input cleanup failed")
end sub

function nativeLiveTick(state as object, port as object, nowMs as dynamic) as object
    if state.closed or state.phase = "failed" then return nativeLiveStatus(state)
    try
        nlTime(state, nowMs)
        nlUseWork(state, "tick", nowMs)
        if state.op <> invalid
            op = state.op
            if nowMs >= op.deadline
                nlTimeout(state)
                return nativeLiveStatus(state)
            end if
            if op.phase = "get"
                fs = CreateObject("roFileSystem")
                if fs.Exists(nlInputPath())
                    stat = fs.Stat(nlInputPath())
                    nlCheck(Type(stat) = "roAssociativeArray", "input stat unavailable")
                    nlCheck(stat.type = "file", "in-flight input type invalid")
                    nlInteger(stat.size, 0&, op.limit + 0&)
                end if
            end if
        else
            nativeLiveAdvance(state, nowMs) ' At most one track conversion per Tick.
            intent = nlIntent(state, nowMs)
            if intent <> invalid
                phase = "head"
                if state.trustedExperimentalTransport then phase = "get"
                nlStart(state, intent, phase, port, nowMs)
            end if
        end if
    catch e
        clean = nlCancelInput(state)
        reason = nlSafeError(e.message)
        if not clean then reason = "native-live: cancellation or input cleanup failed"
        nlAbort(state, reason)
    end try
    return nativeLiveStatus(state)
end function

function nativeLiveHandleUrlEvent(state as object, event as object, nowMs as dynamic) as boolean
    if Type(event) <> "roUrlEvent" or state.op = invalid then return false
    op = state.op
    if event.GetSourceIdentity() <> op.identity then return false
    responseStatus = invalid
    responseHeaders = invalid
    try
        nlTime(state, nowMs)
        if nowMs >= op.deadline
            nlTimeout(state)
            return true
        end if
        nlCheck(event.GetInt() = 1, "URL completion or deadline invalid")
        responseStatus = event.GetResponseCode()
        responseHeaders = event.GetResponseHeadersArray()
        count = nlHeaders(responseHeaders, responseStatus, op.limit, op.phase = "head", state.trustedExperimentalTransport)
        if op.phase = "head"
            port = op.transfer.GetMessagePort()
            intent = { kind: op.kind, url: op.url, limit: op.limit }
            state.op = invalid
            op.transfer = invalid
            nlStart(state, intent, "get", port, nowMs)
        else
            fs = CreateObject("roFileSystem")
            nlCheck(fs.Exists(nlInputPath()), "completed input file missing")
            stat = fs.Stat(nlInputPath())
            count = nlCompletedCount(stat, count, op.limit)
            if op.kind = "playlist"
                payload = ReadAsciiFile(nlInputPath())
                nlCheck(payload.Len() = count and payload.Len() <= 262144, "playlist decoded count mismatch")
            else
                payload = CreateObject("roByteArray")
                nlCheck(payload.ReadFile(nlInputPath(), 0, count), "binary input read failed")
                nlCheck(payload.Count() = count, "binary input read count mismatch")
            end if
            state.op = invalid
            op.transfer = invalid
            nlCheck(nativeLiveInputCleanup(), "completed input cleanup failed")
            state.ownInputFile = false
            state.timedOutUrl = ""
            rokuDemuxFeedInput(state, op.kind, payload, nowMs)
            if twitchAdClockBoolean(state.adClockEnabled) and state.adClockEnabled = true
                twitchAdClockCapture(state, op.kind, payload, op.url)
            end if
        end if
    catch e
        ' Keep only bounded metadata before cancellation releases the request.
        ' Never retain the signed URL, raw headers or response body.
        if responseStatus <> invalid
            context = { status: responseStatus, kind: op.kind, phase: op.phase }
            if Type(responseHeaders) = "roArray"
                hasRange = false
                inspectable = true
                for each header in responseHeaders
                    if Type(header) <> "roAssociativeArray"
                        inspectable = false
                        exit for
                    end if
                    for each name in header
                        if LCase(name) = "content-range" then hasRange = true
                    end for
                end for
                if inspectable then context.hasContentRange = hasRange
            end if
            state.httpFailure = context
        end if
        clean = nlCancelInput(state)
        reason = nlSafeError(e.message)
        if not clean then reason = "native-live: cancellation or input cleanup failed"
        nlAbort(state, reason)
    end try
    return true
end function

function nativeLiveDiagnostics(state as object) as object
    return { phase: state.phase, failed: state.phase = "failed", failureCategory: state.failureCategory, generation: state.latest, cacheBytes: state.cacheBytes, peakCacheBytes: state.peakCacheBytes, assetCount: state.assets.Count(), fetchCount: state.transfers, playlistCount: state.playlistCount, initPairCount: state.initPairCount, segmentPairCount: state.segmentPairCount, transferActive: state.op <> invalid, inputRetained: state.input <> invalid, inputFilePresent: CreateObject("roFileSystem").Exists(nlInputPath()), closed: state.closed }
end function

function nativeLiveClose(state as object) as boolean
    clean = nlCancelInput(state)
    for each generation in state.generations
        if generation.advertised then return false
    end for
    for each asset in state.assets
        if asset.leases > 0 then return false
    end for
    if not clean then return false
    nlClearPlaylistPoll(state)
    state.input = invalid
    state.temporaryVideo = invalid
    state.pendingSegment = invalid
    state.pendingWindow = invalid
    state.pendingPlaylistSequence = -1&
    state.initDigest = ""
    state.initByteCount = 0
    state.tracks = invalid
    state.window = invalid
    state.assets = []
    state.segments = []
    state.generations = []
    state.initIds = []
    state.sourceUrl = ""
    state.origin = ""
    state.approvedOrigins = []
    state.mapUrl = ""
    state.trustedExperimentalTransport = false
    state.cacheBytes = 0
    state.phase = "stopped"
    state.closed = true
    return not CreateObject("roFileSystem").Exists(nlInputPath())
end function

' The completed staging file is already removed before this source-scoped gate.
function rokuDemuxFeedInput(state as object, kind as string, payload as dynamic, nowMs as dynamic) as boolean
    if m.top.stopRequested then return false
    if kind = "init"
        ' Reject changed bytes before the gate can replace the approved metadata.
        if state.phase = "init-rotation" then unused = nlInitDigest(state, payload)
        validateLiveInitOutput(payload)
        if m.top.stopRequested then return false
    end if
    nativeLiveFeed(state, kind, payload, nowMs)
    return true
end function
