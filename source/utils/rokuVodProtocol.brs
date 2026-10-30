' Pure recorded loopback formatting/framing. No socket, cache, fetch or decoder.
function rokuVodSessionId(value as dynamic) as boolean
    if not rokuDemuxString(value) then return false
    return CreateObject("roRegex", "^[0-9a-f]{32}$", "").IsMatch(value)
end function

function rvdpDuration(value as longinteger) as string
    whole = value \ 1000000&
    fraction = value mod 1000000&
    if fraction = 0& then return whole.ToStr()
    suffix = (1000000& + fraction).ToStr().Mid(1)
    while suffix.Right(1) = "0"
        suffix = suffix.Left(suffix.Len() - 1)
    end while
    return whole.ToStr() + "." + suffix
end function

function rvdpItem(records as object, raw as object, rawSize as integer, sourceTarget as integer, entryNo as integer) as dynamic
    offset = entryNo * 24
    record = records.Slice(offset, offset + 24)
    if record.Count() <> 24 then return invalid
    duration = nviRead64(record, 8, 30000000&)
    startUs = nviRead64(record, 16, 172800000000&)
    if duration = invalid or startUs = invalid or duration < 1& or duration > sourceTarget * 1000000& then return invalid
    start = nviRead32(record, 0)
    length = nviRead32(record, 4)
    if length < 1& or length > 2048& or start < 1& or start > rawSize - length then return invalid
    priorByte = raw.Slice(CInt(start) - 1, CInt(start))
    if priorByte.Count() <> 1 or priorByte[0] <> 10 then return invalid
    return { durationUs: duration, startUs: startUs }
end function

function rvdpHeader(index as object, track as string, sessionId as string, target as integer) as string
    prefix = "/vod/" + sessionId + "/"
    shortTrack = "v"
    if track = "audio" then shortTrack = "a"
    nl = Chr(10)
    return "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl + "#EXT-X-TARGETDURATION:" + target.ToStr() + nl + "#EXT-X-PLAYLIST-TYPE:VOD" + nl + "#EXT-X-MEDIA-SEQUENCE:" + index.sequence.ToStr() + nl + "#EXT-X-MAP:URI=" + Chr(34) + prefix + "init/" + shortTrack + ".mp4" + Chr(34) + nl
end function

function rvdpEntryLine(duration as longinteger, entryNo as integer, track as string, sessionId as string) as string
    shortTrack = "v"
    if track = "audio" then shortTrack = "a"
    return "#EXTINF:" + rvdpDuration(duration) + "," + Chr(10) + "/vod/" + sessionId + "/" + shortTrack + "/" + entryNo.ToStr() + ".m4s" + Chr(10)
end function

function rvdpIndexIdentity(index as object) as string
    return index.count.ToStr() + ":" + index.sequence.ToStr() + ":" + index.totalUs.ToStr() + ":" + index.targetDuration.ToStr()
end function

function rokuVodManifestBegin(index as dynamic, track as dynamic, sessionId as dynamic) as dynamic
    try
        if not nviIndexValid(index) or not rokuVodSessionId(sessionId) then return invalid
        if not rokuDemuxString(track) or (track <> "video" and track <> "audio") then return invalid
        maximum = 0&
        total = 0&
        bodyLength = 0
        records = index.records
        raw = index.raw
        entryCount = index.count
        sourceTarget = index.targetDuration
        expectedTotal = index.totalUs
        rawSize = raw.Count()
        lineFixed = "#EXTINF:".Len() + 2 + "/vod/".Len() + sessionId.Len() + 3 + ".m4s".Len() + 1
        for entryNo = 0 to entryCount - 1
            item = rvdpItem(records, raw, rawSize, sourceTarget, entryNo)
            if item = invalid or item.startUs <> total then return invalid
            total += item.durationUs
            if total > 172800000000& then return invalid
            if item.durationUs > maximum then maximum = item.durationUs
            bodyLength += lineFixed + rvdpDuration(item.durationUs).Len() + entryNo.ToStr().Len()
            if bodyLength > 1048576 then return invalid
        end for
        if total <> expectedTotal then return invalid
        target = CInt((maximum + 999999&) \ 1000000&)
        bodyLength += rvdpHeader(index, track, sessionId, target).Len() + "#EXT-X-ENDLIST".Len() + 1
        if bodyLength > 1048576 then return invalid
        return {
            version: 1, track: track, sessionId: sessionId, target: target, length: bodyLength,
            position: 0, lineNo: 0, carry: "", indexIdentity: rvdpIndexIdentity(index), rawHash: rvdpDigest(index.raw), recordHash: rvdpDigest(index.records)
        }
    catch error
        return invalid
    end try
end function

function rokuVodManifestLength(index as dynamic, track as dynamic, sessionId as dynamic) as dynamic
    cursor = rokuVodManifestBegin(index, track, sessionId)
    if cursor = invalid then return invalid
    return cursor.length
end function

function rvdpDigest(bytes as object) as string
    digest = CreateObject("roEVPDigest")
    if digest.Setup("sha256") <> 0 then return ""
    return LCase(digest.Process(bytes))
end function

function rokuVodManifestSpan(index as dynamic, track as dynamic, sessionId as dynamic, cursor as dynamic, maxBytes as dynamic) as dynamic
    try
        if not nviInteger(maxBytes) or maxBytes < 1 or maxBytes > 16384 then return invalid
        if not nviIndexValid(index) or not rokuVodSessionId(sessionId) then return invalid
        if not rvdKeys(cursor, ["version", "track", "sessionId", "target", "length", "position", "lineNo", "carry", "indexIdentity", "rawHash", "recordHash"]) then return invalid
        for each field in ["version", "target", "length", "position", "lineNo"]
            if not nviInteger(cursor[field]) then return invalid
        end for
        if cursor.version <> 1 or cursor.track <> track or cursor.sessionId <> sessionId then return invalid
        if track <> "video" and track <> "audio" then return invalid
        if cursor.target < 1 or cursor.target > 30 or cursor.length < 1 or cursor.length > 1048576 then return invalid
        if cursor.position < 0 or cursor.position > cursor.length or cursor.lineNo < 0 or cursor.lineNo > index.count + 2 then return invalid
        if not rokuDemuxString(cursor.carry) or cursor.carry.Len() > 256 then return invalid
        if not rokuDemuxString(cursor.indexIdentity) or cursor.indexIdentity <> rvdpIndexIdentity(index) then return invalid
        if not rokuDemuxString(cursor.rawHash) or cursor.rawHash.Len() <> 64 or cursor.rawHash <> rvdpDigest(index.raw) then return invalid
        if not rokuDemuxString(cursor.recordHash) or cursor.recordHash.Len() <> 64 or cursor.recordHash <> rvdpDigest(index.records) then return invalid
        nextCursor = {}
        nextCursor.Append(cursor)
        text = ""
        records = index.records
        entryCount = index.count
        while text.Len() < maxBytes
            if nextCursor.carry = ""
                if nextCursor.lineNo = entryCount + 2 then exit while
                line = invalid
                if nextCursor.lineNo = 0
                    line = rvdpHeader(index, track, sessionId, nextCursor.target)
                else if nextCursor.lineNo = entryCount + 1
                    line = "#EXT-X-ENDLIST" + Chr(10)
                else
                    entryNo = nextCursor.lineNo - 1
                    ' Begin validated every record; hashes bind this second pass.
                    packed = records.Slice(entryNo * 24 + 12, entryNo * 24 + 16)
                    if packed.Count() <> 4 then return invalid
                    duration = nviRead32(packed, 0)
                    line = rvdpEntryLine(duration, entryNo, track, sessionId)
                end if
                if line = invalid or line.Len() > 256 then return invalid
                nextCursor.carry = line
                nextCursor.lineNo++
            end if
            take = maxBytes - text.Len()
            if take > nextCursor.carry.Len() then take = nextCursor.carry.Len()
            text += nextCursor.carry.Left(take)
            nextCursor.carry = nextCursor.carry.Mid(take)
        end while
        nextCursor.position += text.Len()
        done = nextCursor.lineNo = entryCount + 2 and nextCursor.carry = ""
        if nextCursor.position > nextCursor.length or (done and nextCursor.position <> nextCursor.length) then return invalid
        if text = "" and not done then return invalid
        bytes = CreateObject("roByteArray")
        bytes.FromAsciiString(text)
        if bytes.Count() <> text.Len() or bytes.Count() > maxBytes then return invalid
        return { bytes: bytes, cursor: nextCursor, done: done }
    catch error
        return invalid
    end try
end function

function rokuVodMasterManifest(metadata as dynamic, sessionId as dynamic) as dynamic
    try
        if not rokuVodSessionId(sessionId) or not rvdMetadata(metadata) then return invalid
        nl = Chr(10)
        prefix = "/vod/" + sessionId + "/"
        text = "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl
        text += "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + Chr(34) + "audio" + Chr(34) + ",NAME=" + Chr(34) + "Audio" + Chr(34) + ",DEFAULT=YES,AUTOSELECT=YES,URI=" + Chr(34) + prefix + "audio.m3u8" + Chr(34) + nl
        text += "#EXT-X-STREAM-INF:BANDWIDTH=" + metadata.bandwidth.ToStr() + ",RESOLUTION=" + metadata.width.ToStr() + "x" + metadata.height.ToStr() + ",FRAME-RATE=" + metadata["frameRate"] + ",CODECS=" + Chr(34) + metadata["videoCodec"] + "," + metadata["audioCodec"] + Chr(34) + ",AUDIO=" + Chr(34) + "audio" + Chr(34) + nl + prefix + "video.m3u8" + nl
        return loopbackAsciiBuffer(text)
    catch error
        return invalid
    end try
end function

function rokuVodRoute(path as dynamic, sessionId as dynamic, entryCount as dynamic) as dynamic
    try
        if not rokuVodSessionId(sessionId) or not nviInteger(entryCount) or entryCount < 1 or entryCount > 8192 then return invalid
        if not rokuDemuxAscii(path, 1, 96, true) then return invalid
        prefix = "/vod/" + sessionId + "/"
        if path.Left(prefix.Len()) <> prefix then return invalid
        tail = path.Mid(prefix.Len())
        for each name in ["master", "video", "audio"]
            if tail = name + ".m3u8" then return { kind: "manifest", track: name, entryNo: -1 }
        end for
        for each pair in [["v", "video"], ["a", "audio"]]
            if tail = "init/" + pair[0] + ".mp4" then return { kind: "init", track: pair[1], entryNo: -1 }
            if tail.Left(2) = pair[0] + "/" and tail.Right(4) = ".m4s"
                number = tail.Mid(2, tail.Len() - 6)
                if number.Len() < 1 or (number.Len() > 1 and number.Left(1) = "0") then return invalid
                entryNo = nviNatural(number, entryCount - 1 + 0&)
                if entryNo = invalid then return invalid
                return { kind: "media", track: pair[1], entryNo: CInt(entryNo) }
            end if
        end for
    catch error
    end try
    return invalid
end function

function rokuVodRequest(header as dynamic, sessionId as dynamic, entryCount as dynamic, port as dynamic) as dynamic
    try
        if not nviInteger(port) or port < 49152 or port > 65535 then return invalid
        if not rokuDemuxString(header) or header.Len() < 16 or header.Len() > 8192 then return invalid
        if header.Right(4) <> Chr(13) + Chr(10) + Chr(13) + Chr(10) then return invalid
        lines = header.Split(Chr(13) + Chr(10))
        if lines.Count() < 4 or lines.Count() > 35 then return invalid
        request = lines[0].Split(" ")
        if request.Count() <> 3 or (request[0] <> "GET" and request[0] <> "HEAD") or request[2] <> "HTTP/1.1" then return invalid
        route = rokuVodRoute(request[1], sessionId, entryCount)
        if route = invalid then return invalid
        seen = {}
        range = ""
        for lineNo = 1 to lines.Count() - 3
            line = lines[lineNo]
            if not rokuDemuxAscii(line, 3, 1024) or line.Left(1) = " " then return invalid
            colon = line.InStr(":")
            if colon < 1 then return invalid
            name = LCase(line.Left(colon))
            if not CreateObject("roRegex", "^[a-z0-9-]+$", "").IsMatch(name) or seen.DoesExist(name) then return invalid
            value = line.Mid(colon + 1).Trim()
            if value = "" then return invalid
            seen[name] = value
            if name = "content-length" or name = "transfer-encoding" or name = "expect" then return invalid
            if name = "range"
                if rokuVodRange(value, 16777216) = invalid then return invalid
                range = value
            end if
        end for
        if seen["host"] <> "127.0.0.1:" + port.ToStr() then return invalid
        return { method: request[0], path: request[1], route: route, range: range }
    catch error
        return invalid
    end try
end function

' VOD-only copy of shared range semantics with the recorded media bound.
function rvdpMediaRange(value as string, size as integer) as object
    bad = { "ok": false, "status": 416, "start": 0, "length": 0, "range": false }
    if size < 1 or size > 16777216 then return bad
    if value = "" then return { "ok": true, "status": 200, "start": 0, "length": size, "range": false }
    if value.Len() > 48 or value.Left(6) <> "bytes=" then return bad
    span = value.Right(value.Len() - 6)
    dash = span.InStr("-")
    if dash < 0 then return bad
    first = span.Left(dash)
    last = span.Right(span.Len() - dash - 1)
    if first = ""
        suffix = loopbackUnsigned(last, 16777216)
        if suffix <= 0 then return bad
        if suffix > size then suffix = size
        return { "ok": true, "status": 206, "start": size - suffix, "length": suffix, "range": true }
    end if
    start = loopbackUnsigned(first, 16777216)
    if start < 0 or start >= size then return bad
    finish = size - 1
    if last <> ""
        finish = loopbackUnsigned(last, 16777216)
        if finish < start then return bad
        if finish >= size then finish = size - 1
    end if
    return { "ok": true, "status": 206, "start": start, "length": finish - start + 1, "range": true }
end function

function rokuVodRange(header as dynamic, size as dynamic) as dynamic
    try
        if not nviInteger(size) or size < 1 or size > 16777216 then return invalid
        if not rokuDemuxString(header) or header.Len() > 128 then return invalid
        if header <> "" and not rokuDemuxAscii(header, 1, 128, true) then return invalid
        range = rvdpMediaRange(header, CInt(size))
        if not range.ok then return invalid
        return range
    catch error
        return invalid
    end try
end function

function rokuVodResponseHeader(request as dynamic, sessionId as dynamic, entryCount as dynamic, size as dynamic) as dynamic
    try
        if not rvdKeys(request, ["method", "path", "route", "range"]) then return invalid
        if not rokuDemuxString(request.method) or (request.method <> "GET" and request.method <> "HEAD") then return invalid
        route = rokuVodRoute(request.path, sessionId, entryCount)
        if route = invalid or not rvdKeys(request.route, ["kind", "track", "entryNo"]) then return invalid
        if not rokuDemuxString(request.route.kind) or not rokuDemuxString(request.route.track) or not nviInteger(request.route.entryNo) then return invalid
        for each key in ["kind", "track", "entryNo"]
            if request.route[key] <> route[key] then return invalid
        end for
        slice = rokuVodRange(request.range, size)
        if slice = invalid then return invalid
        if route.kind = "manifest" and size > 1048576 then return invalid
        if route.kind = "init" and size > 2097152 then return invalid
        mime = "video/mp4"
        if route.track = "audio" then mime = "audio/mp4"
        if route.kind = "manifest" then mime = "application/vnd.apple.mpegurl"
        status = "200 OK"
        if slice.range then status = "206 Partial Content"
        crlf = Chr(13) + Chr(10)
        text = "HTTP/1.1 " + status + crlf + "Content-Type: " + mime + crlf
        text += "Content-Length: " + slice.length.ToStr() + crlf + "Accept-Ranges: bytes" + crlf
        text += "Connection: close" + crlf + "Cache-Control: no-store" + crlf
        if slice.range
            finish = slice.start + slice.length - 1
            text += "Content-Range: bytes " + slice.start.ToStr() + "-" + finish.ToStr() + "/" + size.ToStr() + crlf
        end if
        text += crlf
        bytes = loopbackAsciiBuffer(text)
        if bytes = invalid or bytes.Count() > 512 then return invalid
        return { bytes: bytes, range: slice, head: request.method = "HEAD" }
    catch error
        return invalid
    end try
end function
