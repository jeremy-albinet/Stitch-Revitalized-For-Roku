' Pure completed-recording index. Exact URL pins are not network authorization.
' The raw bytes and 24-byte records are Task-private and immutable after parsing.
function rokuVodIndexParse(bytes as dynamic, sourceUrl as dynamic, approvedOrigin as dynamic) as dynamic
    return nviScan(bytes, sourceUrl, approvedOrigin, true)
end function

function rokuVodIndexValidate(bytes as dynamic, sourceUrl as dynamic, approvedOrigin as dynamic) as boolean
    return nviScan(bytes, sourceUrl, approvedOrigin, false) = true
end function

function nviScan(bytes as dynamic, sourceUrl as dynamic, approvedOrigin as dynamic, buildRecords as dynamic) as dynamic
    try
        modeKind = type(buildRecords, 3)
        if modeKind <> "Boolean" and modeKind <> "roBoolean" then return invalid
        if type(bytes) <> "roByteArray" then return invalid
        size = bytes.Count()
        if size < 1 or size > 262144 then return invalid
        base = nviUrl(sourceUrl)
        origin = nviUrl(approvedOrigin)
        if base = invalid or origin = invalid then return invalid
        if approvedOrigin <> origin.origin or base.origin <> origin.origin then return invalid
        text = bytes.ToAsciiString()
        if text.Len() <> size then return invalid
        if CreateObject("roRegex", "[^" + Chr(9) + Chr(10) + Chr(13) + " -~]", "").IsMatch(text) then return invalid
        newline = Chr(10)
        carriageReturn = Chr(13)
        lineCount = size - text.Replace(newline, "").Len()
        if text.Right(1) <> newline then lineCount++
        if lineCount > 16448 then return invalid
        lineParts = text.Split(newline)
        if lineParts.Count() > 16449 then return invalid
        lineAt = 0
        records = invalid
        if buildRecords
            records = CreateObject("roByteArray")
            records.SetResize(8192 * 24, false)
        end if
        count = 0
        lines = 0
        offset = 0
        totalUs = 0&
        sequence = 0&
        target = 0
        maximumUs = 0&
        pendingUs = invalid
        mapUri = ""
        playlistType = ""
        ended = false
        seen = {}
        while offset < size
            line = lineParts[lineAt]
            finish = offset + line.Len()
            lineAt++
            length = line.Len()
            if length > 0 and line.Right(1) = carriageReturn
                length--
                line = line.Left(length)
            end if
            lines++
            if lines > 16448 or length > 4096 then return invalid
            if line.InStr(carriageReturn) >= 0 then return invalid
            if lines = 1
                if line <> "#EXTM3U" then return invalid
            else if line <> ""
                if line <> line.Trim() or ended then return invalid
                if line.Left(1) <> "#"
                    if pendingUs = invalid or mapUri = "" or target = 0 then return invalid
                    if length < 1 or length > 2048 or count >= 8192 then return invalid
                    if nviResolve(base, line) = invalid then return invalid
                    if pendingUs > target * 1000000& or totalUs > 172800000000& - pendingUs then return invalid
                    if buildRecords
                        at = count * 24
                        nviPut32(records, at, offset + 0&)
                        nviPut32(records, at + 4, length + 0&)
                        nviPut64(records, at + 8, pendingUs)
                        nviPut64(records, at + 16, totalUs)
                    end if
                    totalUs += pendingUs
                    if pendingUs > maximumUs then maximumUs = pendingUs
                    pendingUs = invalid
                    count++
                else if line.Left(8) = "#EXTINF:"
                    if pendingUs <> invalid then return invalid
                    value = line.Mid(8)
                    comma = value.InStr(",")
                    if comma < 1 or value.Len() - comma - 1 > 512 then return invalid
                    pendingUs = nviDuration(value.Left(comma), 30000000&)
                    if pendingUs = invalid or pendingUs = 0& then return invalid
                else if line.Left(4) = "#EXT"
                    if pendingUs <> invalid then return invalid
                    colon = line.InStr(":")
                    tag = line
                    value = ""
                    if colon >= 0
                        tag = line.Left(colon)
                        value = line.Mid(colon + 1)
                    end if
                    if seen.DoesExist(tag) then return invalid
                    seen[tag] = true
                    if tag = "#EXT-X-VERSION"
                        version = nviNatural(value, 7&)
                        if version = invalid or version < 1& then return invalid
                    else if tag = "#EXT-X-TARGETDURATION"
                        targetValue = nviNatural(value, 30&)
                        if targetValue = invalid or targetValue < 1& then return invalid
                        target = CInt(targetValue)
                    else if tag = "#EXT-X-MEDIA-SEQUENCE"
                        if count > 0 then return invalid
                        sequence = nviNatural(value, 4294967295&)
                        if sequence = invalid then return invalid
                    else if tag = "#EXT-X-PLAYLIST-TYPE"
                        if count > 0 or (value <> "VOD" and value <> "EVENT") then return invalid
                        playlistType = value
                    else if tag = "#EXT-X-MAP"
                        if count > 0 or value.Left(5) <> "URI=" + Chr(34) or value.Right(1) <> Chr(34) then return invalid
                        reference = value.Mid(5, value.Len() - 6)
                        if reference.InStr(Chr(34)) >= 0 or reference.Len() > 2048 then return invalid
                        mapUri = nviResolve(base, reference)
                        if mapUri = invalid then return invalid
                    else if tag = "#EXT-X-TWITCH-TOTAL-SECS" or tag = "#EXT-X-TWITCH-ELAPSED-SECS"
                        if nviDuration(value, 172800000000&) = invalid then return invalid
                    else if tag = "#EXT-X-ENDLIST"
                        if colon >= 0 then return invalid
                        ended = true
                    else
                        return invalid
                    end if
                end if
            end if
            offset = finish + 1
        end while
        if not ended or count < 1 or playlistType = "" or mapUri = "" or target = 0 or pendingUs <> invalid then return invalid
        if sequence > 4294967295& - (count - 1) then return invalid
        if maximumUs > target * 1000000& then return invalid
        if not buildRecords then return true
        records.SetResize(count * 24, false)
        if records.Count() <> count * 24 then return invalid
        raw = bytes.Slice(0, size)
        if type(raw) <> "roByteArray" or raw.Count() <> size then return invalid
        return {
            version: 1, raw: raw, records: records, count: count, sequence: sequence,
            totalUs: totalUs, targetDuration: target, mapUri: mapUri,
            sourceUrl: sourceUrl, approvedOrigin: approvedOrigin
        }
    catch error
        return invalid
    end try
end function

function rokuVodIndexEntry(index as dynamic, entryNo as dynamic) as dynamic
    try
        if not nviIndexValid(index) or not nviInteger(entryNo) then return invalid
        if entryNo < 0 or entryNo >= index.count then return invalid
        recordOffset = entryNo * 24
        start = nviRead32(index.records, recordOffset)
        length = nviRead32(index.records, recordOffset + 4)
        duration = nviRead64(index.records, recordOffset + 8, 30000000&)
        position = nviRead64(index.records, recordOffset + 16, 172800000000&)
        if duration = invalid or position = invalid or duration < 1& then return invalid
        if length < 1& or length > 2048& or start > index.raw.Count() - length then return invalid
        if position > index.totalUs - duration then return invalid
        if entryNo = 0
            if position <> 0& then return invalid
        else
            priorPosition = nviRead64(index.records, recordOffset - 8, 172800000000&)
            priorDuration = nviRead64(index.records, recordOffset - 16, 30000000&)
            if priorPosition = invalid or priorDuration = invalid or priorPosition + priorDuration <> position then return invalid
        end if
        if entryNo = index.count - 1
            if position + duration <> index.totalUs then return invalid
        else
            nextPosition = nviRead64(index.records, recordOffset + 40, 172800000000&)
            if nextPosition = invalid or nextPosition <> position + duration then return invalid
        end if
        reference = index.raw.Slice(CInt(start), CInt(start + length)).ToAsciiString()
        base = nviUrl(index.sourceUrl)
        uri = nviResolve(base, reference)
        if uri = invalid then return invalid
        return { uri: uri, durationUs: duration, startUs: position }
    catch error
        return invalid
    end try
end function

function rokuVodIndexFind(index as dynamic, positionUs as dynamic) as dynamic
    try
        if not nviIndexValid(index) or not nviInteger(positionUs) then return invalid
        if positionUs < 0& or positionUs >= index.totalUs then return invalid
        low = 0
        high = index.count - 1
        while low <= high
            middle = low + (high - low) \ 2
            item = rokuVodIndexEntry(index, middle)
            if item = invalid then return invalid
            if positionUs < item.startUs
                high = middle - 1
            else if positionUs >= item.startUs + item.durationUs
                low = middle + 1
            else
                return middle
            end if
        end while
    catch error
    end try
    return invalid
end function

function nviInteger(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "Integer" or kind = "LongInteger" or kind = "roInt"
end function

function nviNatural(text as string, maximum as longinteger) as dynamic
    if text.Len() < 1 or text.Len() > 12 then return invalid
    result = 0&
    for i = 0 to text.Len() - 1
        digit = Asc(text.Mid(i, 1)) - 48
        if digit < 0 or digit > 9 then return invalid
        if result > (maximum - digit) \ 10& then return invalid
        result = result * 10& + digit
    end for
    if result > maximum then return invalid
    return result
end function

function nviDuration(text as string, maximum as longinteger) as dynamic
    parts = text.Split(".")
    if parts.Count() < 1 or parts.Count() > 2 then return invalid
    whole = nviNatural(parts[0], maximum \ 1000000&)
    if whole = invalid then return invalid
    fraction = 0&
    if parts.Count() = 2
        if parts[1].Len() < 1 or parts[1].Len() > 6 then return invalid
        fraction = nviNatural(parts[1], 999999&)
        if fraction = invalid then return invalid
        for digits = parts[1].Len() to 5
            fraction *= 10&
        end for
    end if
    result = whole * 1000000& + fraction
    if result > maximum then return invalid
    return result
end function

function nviUrl(value as dynamic) as dynamic
    if type(value) <> "String" and type(value) <> "roString" then return invalid
    if value.Len() < 12 or value.Len() > 8192 or value.Left(8) <> "https://" then return invalid
    if CreateObject("roRegex", "[^!-~]|[\\#]", "").IsMatch(value) then return invalid
    rest = value.Mid(8)
    boundary = rest.Len()
    for each delimiter in ["/", "?"]
        at = rest.InStr(delimiter)
        if at >= 0 and at < boundary then boundary = at
    end for
    host = rest.Left(boundary)
    if host <> LCase(host) or host.Len() < 3 or host.Len() > 253 then return invalid
    if not CreateObject("roRegex", "^[a-z0-9.-]+$", "").IsMatch(host) then return invalid
    if CreateObject("roRegex", "^[0-9.]+$", "").IsMatch(host) or host.InStr(".") < 0 then return invalid
    for each label in host.Split(".")
        if label.Len() < 1 or label.Len() > 63 or label.Left(1) = "-" or label.Right(1) = "-" then return invalid
    end for
    pathQuery = rest.Mid(boundary)
    if pathQuery = "" or pathQuery.Left(1) = "?" then pathQuery = "/" + pathQuery
    query = ""
    question = pathQuery.InStr("?")
    if question >= 0
        query = pathQuery.Mid(question)
        pathQuery = pathQuery.Left(question)
    end if
    if not nviPath(pathQuery) then return invalid
    slash = -1
    for i = 0 to pathQuery.Len() - 1
        if pathQuery.Mid(i, 1) = "/" then slash = i
    end for
    return {
        origin: "https://" + host, path: pathQuery, query: query,
        directory: pathQuery.Left(slash + 1), uriGuard: CreateObject("roRegex", "[^!-~]|[\\#]", "")
    }
end function

function nviPath(value as string) as boolean
    if value.Left(1) <> "/" or value.InStr("%") >= 0 or value.InStr("//") >= 0 then return false
    parts = value.Split("/")
    if parts.Count() > 128 then return false
    for each part in parts
        if part = "." or part = ".." then return false
    end for
    return true
end function

function nviResolve(base as dynamic, reference as dynamic) as dynamic
    if base = invalid or (type(reference) <> "String" and type(reference) <> "roString") then return invalid
    if reference.Len() < 1 or reference.Len() > 2048 then return invalid
    if base.uriGuard.IsMatch(reference) then return invalid
    if reference.Left(8) = "https://"
        absolute = nviUrl(reference)
        if absolute = invalid or absolute.origin <> base.origin then return invalid
        return reference
    end if
    if reference.Left(2) = "//" or reference.Left(1) = "?" then return invalid
    path = reference
    query = ""
    question = path.InStr("?")
    if question >= 0
        query = path.Mid(question)
        path = path.Left(question)
    end if
    if path.InStr(":") >= 0 then return invalid
    if path.Left(1) <> "/"
        path = base.directory + path
    end if
    if not nviPath(path) then return invalid
    result = base.origin + path + query
    if result.Len() > 8192 then return invalid
    return result
end function

sub nviPut32(data as object, offset as integer, value as longinteger)
    data[offset] = CInt((value \ 16777216&) mod 256&)
    data[offset + 1] = CInt((value \ 65536&) mod 256&)
    data[offset + 2] = CInt((value \ 256&) mod 256&)
    data[offset + 3] = CInt(value mod 256&)
end sub

sub nviPut64(data as object, offset as integer, value as longinteger)
    nviPut32(data, offset, value \ 4294967296&)
    nviPut32(data, offset + 4, value mod 4294967296&)
end sub

function nviRead32(data as object, offset as integer) as longinteger
    return data[offset] * 16777216& + data[offset + 1] * 65536& + data[offset + 2] * 256& + data[offset + 3]
end function

function nviRead64(data as object, offset as integer, maximum as longinteger) as dynamic
    high = nviRead32(data, offset)
    if high > maximum \ 4294967296& then return invalid
    result = high * 4294967296& + nviRead32(data, offset + 4)
    if result > maximum then return invalid
    return result
end function

function nviIndexValid(index as dynamic) as boolean
    if type(index) <> "roAssociativeArray" then return false
    keys = ["version", "raw", "records", "count", "sequence", "totalUs", "targetDuration", "mapUri", "sourceUrl", "approvedOrigin"]
    if index.Keys().Count() <> keys.Count() then return false
    for each key in keys
        if not index.DoesExist(key) then return false
    end for
    for each key in ["version", "count", "sequence", "totalUs", "targetDuration"]
        if not nviInteger(index[key]) then return false
    end for
    if index.version <> 1 or index.count < 1 or index.count > 8192 then return false
    if index.sequence < 0& or index.sequence > 4294967295& - (index.count - 1) then return false
    if index.totalUs < 1& or index.totalUs > 172800000000& or index.targetDuration < 1 or index.targetDuration > 30 then return false
    if type(index.raw) <> "roByteArray" or type(index.records) <> "roByteArray" then return false
    if index.raw.Count() < 1 or index.raw.Count() > 262144 or index.records.Count() <> index.count * 24 then return false
    base = nviUrl(index.sourceUrl)
    origin = nviUrl(index.approvedOrigin)
    if base = invalid or origin = invalid then return false
    if index.approvedOrigin <> origin.origin or base.origin <> origin.origin then return false
    map = nviUrl(index.mapUri)
    return map <> invalid and map.origin = origin.origin
end function
