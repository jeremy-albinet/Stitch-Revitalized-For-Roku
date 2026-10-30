' Separate finite recorded-source transfer owner. Descriptor syntax is not egress approval.
function rokuVodFetchCreate(descriptor as dynamic, sessionId as dynamic) as dynamic
    if not rokuVodDescriptorValid(descriptor) or not rokuVodSessionId(sessionId) then return invalid
    copy = ParseJson(FormatJson(descriptor))
    return { descriptor: copy, descriptorHash: FormatJson(copy), sessionId: sessionId, path: "tmp:/stitch-vod-" + sessionId + ".bin", trusted: false, index: invalid, indexHash: "", op: invalid, output: invalid, ownFile: false, phase: "idle", reason: "", cleanupBlocked: false, closed: false, lastNow: 0&, intervalStart: 0&, ticks: 0&, transfers: 0&, totalTransfers: 0& }
end function

function rvfFileSystem() as object
    return CreateObject("roFileSystem")
end function

function rvfTransfer() as object
    return CreateObject("roUrlTransfer")
end function

' A fresh native transfer starts with cookies/auth disabled; never enable either.
' Redirects may already be followed by Roku. Retained Location is refused at completion,
' before input acceptance; this is not network-egress prevention or an effective-URL API.
function rvfConfigureTransport(transfer as object, url as string) as boolean
    try
        if nviUrl(url) = invalid then return false
        return transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") and transfer.EnablePeerVerification(true) and transfer.EnableHostVerification(true) and transfer.EnableEncodings(false) and transfer.EnableResume(false) and transfer.SetMinimumTransferRate(1, 2)
    catch error
        return false
    end try
end function

function rvfUrlEvent(event as dynamic) as boolean
    return Type(event) = "roUrlEvent"
end function

function rvfReadFile(path as string, count as integer) as dynamic
    bytes = CreateObject("roByteArray")
    if not bytes.ReadFile(path, 0, count) or bytes.Count() <> count then return invalid
    return bytes
end function

function rvfOwnPath(state as object) as boolean
    return rokuVodSessionId(state.sessionId) and state.path = "tmp:/stitch-vod-" + state.sessionId + ".bin"
end function

sub rvfCheck(value as boolean, reason as string)
    if not value then throw "vod-fetch:" + reason
end sub

function rvfInteger(value as dynamic, minimum as longinteger, maximum as longinteger) as boolean
    if not nviInteger(value) then return false
    return value >= minimum and value <= maximum
end function

function rvfNatural(value as dynamic, maximum as longinteger) as longinteger
    rvfCheck(rokuDemuxString(value), "framing_integer")
    rvfCheck(CreateObject("roRegex", "^(0|[1-9][0-9]{0,10})$", "").IsMatch(value), "framing_integer")
    number = nviNatural(value, maximum)
    rvfCheck(number <> invalid, "framing_integer")
    rvfCheck(number >= 0& and number <= maximum and number.ToStr() = value, "framing_integer")
    return number
end function

function rvfFullRange(value as string, limit as integer) as integer
    rvfCheck(CreateObject("roRegex", "^bytes 0-[0-9]{1,10}/[0-9]{1,10}$", "").IsMatch(value), "content_range")
    fields = value.Mid(8).Split("/")
    last = rvfNatural(fields[0], 4294967295&)
    total = rvfNatural(fields[1], limit + 0&)
    rvfCheck(total > 0& and last = total - 1& and value = "bytes 0-" + last.ToStr() + "/" + total.ToStr(), "content_range")
    return CInt(total)
end function

' Same strict framing semantics as nlHeaders; experimental unknown framing is not enabled.
function rvfHeaders(entries as dynamic, status as integer, limit as integer, head as boolean) as integer
    rvfCheck(Type(entries) = "roArray" and entries.Count() <= 64, "header_count")
    headers = {}
    total = 0
    for each entry in entries
        rvfCheck(Type(entry) = "roAssociativeArray" and entry.Count() = 1, "header_shape")
        for each name in entry
            value = entry[name]
            rvfCheck(rokuDemuxString(value) and name.Len() >= 1 and name.Len() <= 128 and value.Len() <= 4096, "header_length")
            rvfCheck(CreateObject("roRegex", "^[A-Za-z0-9-]+$", "").IsMatch(name), "header_name")
            for i = 0 to value.Len() - 1
                code = Asc(value.Mid(i, 1))
                rvfCheck((code >= 32 and code <= 126) or code = 9, "header_character")
            end for
            total += name.Len() + value.Len()
            rvfCheck(total <= 8192, "header_aggregate")
            key = LCase(name)
            if key = "content-length" or key = "content-range" or key = "content-encoding" or key = "transfer-encoding" or key = "location"
                rvfCheck(not headers.DoesExist(key), "duplicate_header")
                headers[key] = value.Trim()
            end if
        end for
    end for
    rvfCheck(not headers.DoesExist("location") and not headers.DoesExist("transfer-encoding"), "redirect_or_framing")
    if headers.DoesExist("content-encoding") then rvfCheck(LCase(headers["content-encoding"]) = "identity", "compressed_response")
    rvfCheck(headers.DoesExist("content-length"), "length_required")
    length = rvfNatural(headers["content-length"], limit + 0&)
    rvfCheck(length > 0&, "empty_response")
    if head
        rvfCheck(status = 200 and not headers.DoesExist("content-range"), "head_status")
    else if status = 206
        rvfCheck(headers.DoesExist("content-range"), "range_required")
        rvfCheck(length = rvfFullRange(headers["content-range"], limit), "range_count")
    else
        rvfCheck(status = 200 and not headers.DoesExist("content-range"), "get_status")
    end if
    return CInt(length)
end function

function rvfCompletedCount(stat as dynamic, count as integer, limit as integer) as integer
    rvfCheck(Type(stat) = "roAssociativeArray" and stat.type = "file", "file_stat")
    rvfCheck(rvfInteger(stat.size, 1&, limit + 0&) and stat.size = count, "file_count")
    return CInt(stat.size)
end function

function rvfTime(state as object, nowMs as dynamic) as boolean
    if not rvfInteger(nowMs, state.lastNow, 4294967235000&) then return false
    state.lastNow = nowMs
    if nowMs - state.intervalStart >= 60000&
        state.intervalStart = nowMs
        state.ticks = 0&
        state.transfers = 0&
    end if
    return true
end function

function rvfIndexHash(index as object) as string
    return rvdpIndexIdentity(index) + ":" + rvdpDigest(index.raw) + ":" + rvdpDigest(index.records)
end function

function rvfIntent(state as object, kind as dynamic, entryNo as dynamic) as dynamic
    if not rokuDemuxString(kind) or not rvfInteger(entryNo, -1&, 8191&) then return invalid
    if not rokuVodDescriptorValid(state.descriptor) or FormatJson(state.descriptor) <> state.descriptorHash then return invalid
    if kind = "master" and entryNo = -1 and not state.trusted and state.index = invalid then return { kind: kind, entryNo: -1, url: state.descriptor["usherUrl"], limit: 262144 }
    if not state.trusted then return invalid
    if kind = "playlist" and entryNo = -1 and state.index = invalid then return { kind: kind, entryNo: -1, url: state.descriptor["sourceUrl"], limit: 262144 }
    if state.index = invalid or not nviIndexValid(state.index) or rvfIndexHash(state.index) <> state.indexHash then return invalid
    if kind = "init" and entryNo = -1 then return { kind: kind, entryNo: -1, url: state.index.mapUri, limit: 2097152 }
    if kind = "media" and entryNo >= 0
        item = rokuVodIndexEntry(state.index, entryNo)
        if item <> invalid then return { kind: kind, entryNo: entryNo, url: item.uri, limit: 12582912 }
    end if
    return invalid
end function

sub rvfStart(state as object, intent as object, phase as string, port as object, nowMs as longinteger, headCount = -1 as integer)
    rvfCheck(state.op = invalid and state.output = invalid and not state.ownFile, "overlap")
    rvfCheck(rvfOwnPath(state), "input_owner")
    rvfCheck(state.transfers < 256& and state.totalTransfers < 4294967295&, "transfer_quota")
    fs = rvfFileSystem()
    rvfCheck(not fs.Exists(state.path), "path_already_present")
    transfer = rvfTransfer()
    rvfCheck(transfer <> invalid, "transfer_unavailable")
    rvfCheck(rvfConfigureTransport(transfer, intent.url), "transport_configuration")
    transfer.SetMessagePort(port)
    headers = { "Accept-Encoding": "identity" }
    if phase = "get" and (intent.kind = "init" or intent.kind = "media") then headers.Range = "bytes=0-" + (intent.limit - 1).ToStr()
    rvfCheck(transfer.SetHeaders(headers), "request_headers")
    transfer.SetUrl(intent.url)
    state.op = { transfer: transfer, identity: transfer.GetIdentity(), intent: intent, phase: phase, headCount: headCount, deadline: nowMs + 5000& }
    state.transfers++
    state.totalTransfers++
    if phase = "head"
        rvfCheck(transfer.AsyncHead(), "head_start")
    else
        state.ownFile = true
        rvfCheck(transfer.AsyncGetToFile(state.path), "get_start")
    end if
    state.phase = "fetching"
end sub

function rokuVodFetchBegin(state as object, kind as dynamic, entryNo as dynamic, port as object, nowMs as dynamic) as boolean
    if state.closed or state.phase <> "idle" then return false
    try
        rvfCheck(rvfTime(state, nowMs), "clock")
        intent = rvfIntent(state, kind, entryNo)
        rvfCheck(intent <> invalid, "unauthorized_intent")
        phase = "head"
        if intent.kind = "master" then phase = "get"
        rvfStart(state, intent, phase, port, nowMs)
        return true
    catch error
        rvfFail(state, error)
        return false
    end try
end function

function rokuVodFetchPump(state as object, nowMs as dynamic, stopRequested as boolean) as boolean
    if state.closed or state.phase = "failed" then return false
    try
        rvfCheck(rvfTime(state, nowMs), "clock")
        rvfCheck(not stopRequested, "stopped")
        rvfCheck(state.ticks < 12000&, "tick_quota")
        state.ticks++
        if state.op <> invalid
            op = state.op
            rvfCheck(nowMs < op.deadline, "operation_deadline")
            if state.ownFile
                rvfCheck(rvfOwnPath(state), "input_owner")
                fs = rvfFileSystem()
                if fs.Exists(state.path)
                    stat = fs.Stat(state.path)
                    rvfCheck(Type(stat) = "roAssociativeArray" and stat.type = "file", "inflight_stat")
                    rvfCheck(rvfInteger(stat.size, 0&, op.intent.limit + 0&), "inflight_size")
                end if
            end if
        end if
        return true
    catch error
        rvfFail(state, error)
        return false
    end try
end function

function rokuVodFetchHandleUrlEvent(state as object, event as dynamic, nowMs as dynamic) as boolean
    if state.closed or state.phase <> "fetching" or state.op = invalid or not rvfUrlEvent(event) then return false
    op = state.op
    if event.GetSourceIdentity() <> op.identity then return false
    try
        rvfCheck(rvfTime(state, nowMs), "clock")
        rvfCheck(event.GetInt() = 1 and nowMs < op.deadline, "completion_deadline")
        count = rvfHeaders(event.GetResponseHeadersArray(), event.GetResponseCode(), op.intent.limit, op.phase = "head")
        if op.phase = "head"
            port = op.transfer.GetMessagePort()
            state.op = invalid
            op.transfer = invalid
            rvfStart(state, op.intent, "get", port, nowMs, count)
        else
            if op.intent.kind <> "master" or op.headCount <> -1
                rvfCheck(count = op.headCount, "head_get_count")
            end if
            rvfCheck(rvfOwnPath(state), "input_owner")
            fs = rvfFileSystem()
            rvfCheck(fs.Exists(state.path), "completed_file_missing")
            count = rvfCompletedCount(fs.Stat(state.path), count, op.intent.limit)
            payload = rvfReadFile(state.path, count)
            rvfCheck(Type(payload) = "roByteArray" and payload.Count() = count, "read_count")
            state.op = invalid
            op.transfer = invalid
            rvfCheck(rvfDeleteInput(state), "completed_cleanup")
            if op.intent.kind = "master"
                rvfCheck(rokuVodDescriptorMatchesMaster(state.descriptor, payload.ToAsciiString()), "master_mismatch")
                state.trusted = true
                payload = true
            else if op.intent.kind = "playlist"
                parsed = rokuVodIndexParse(payload, state.descriptor["sourceUrl"], state.descriptor["approvedOrigin"])
                rvfCheck(parsed <> invalid, "playlist_invalid")
                state.index = parsed
                state.indexHash = rvfIndexHash(parsed)
                payload = parsed
            end if
            state.output = { kind: op.intent.kind, entryNo: op.intent.entryNo, data: payload }
            state.phase = "ready"
        end if
    catch error
        rvfFail(state, error)
    end try
    return true
end function

function rokuVodFetchTake(state as object) as dynamic
    if state.closed or state.phase <> "ready" or state.output = invalid then return invalid
    output = state.output
    state.output = invalid
    state.phase = "idle"
    return output
end function

function rvfDeleteInput(state as object) as boolean
    if not state.ownFile then return true
    if not rvfOwnPath(state) then return false
    try
        fs = rvfFileSystem()
        if fs.Exists(state.path)
            stat = fs.Stat(state.path)
            if Type(stat) <> "roAssociativeArray" or stat.type <> "file" then return false
            if not fs.Delete(state.path) or fs.Exists(state.path) then return false
        end if
        state.ownFile = false
        return true
    catch error
        return false
    end try
end function

function rokuVodFetchCancel(state as object) as boolean
    if state.op <> invalid
        try
            if not state.op.transfer.AsyncCancel() then
                state.cleanupBlocked = true
                return false
            end if
            state.op = invalid
        catch error
            state.cleanupBlocked = true
            return false
        end try
    end if
    clean = rvfDeleteInput(state)
    if clean then state.output = invalid
    state.cleanupBlocked = not clean
    return clean
end function

sub rvfFail(state as object, error as object)
    reason = "native_operation"
    if rokuDemuxString(error.message)
        if CreateObject("roRegex", "^vod-fetch:[a-z_]{1,40}$", "").IsMatch(error.message) then reason = error.message.Mid(10)
    end if
    if not rokuVodFetchCancel(state) then reason = "cleanup_blocked"
    state.reason = reason
    state.phase = "failed"
end sub

function rokuVodFetchClose(state as object) as boolean
    if state.closed then return true
    if not rokuVodFetchCancel(state) then return false
    state.descriptor = invalid
    state.descriptorHash = ""
    state.index = invalid
    state.indexHash = ""
    state.trusted = false
    state.path = ""
    state.phase = "closed"
    state.closed = true
    return true
end function
