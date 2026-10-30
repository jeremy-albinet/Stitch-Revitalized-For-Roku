' Lower live latency. Roku starts a live playlist at its first segment and
' ignores PlayStart (measured on a G204X), so the relay serves only Twitch's
' newest segments. Segment URLs stay Twitch's own. Twitch's low-latency
' prefetch segments download at broadcast speed; Roku then waits longer to
' start and lowers quality, so they are not used.

' Rewrites each variant URI to a relay path. Alternate renditions with their
' own URIs (separate audio) are refused; those streams play directly.
function lowLatencyMaster(text as dynamic, baseUrl as string) as dynamic
    if GetInterface(text, "ifString") = invalid then return invalid
    if text.Len() < 7 or text.Len() > 262144 then return invalid
    lines = text.Split(Chr(10))
    if lines.Count() > 4096 or lines[0].Trim() <> "#EXTM3U" then return invalid
    out = []
    variants = []
    pending = false
    for each raw in lines
        line = raw.Trim()
        if line = ""
        else if line.Left(1) <> "#"
            if not pending or variants.Count() >= 32 then return invalid
            url = lowLatencyResolve(baseUrl, line)
            if url = "" then return invalid
            variants.Push(url)
            out.Push("/v/" + (variants.Count() - 1).ToStr() + ".m3u8")
            pending = false
        else if line.Left(18) = "#EXT-X-STREAM-INF:"
            if pending then return invalid
            out.Push(line)
            pending = true
        else if line.Left(13) = "#EXT-X-MEDIA:" and line.InStr("URI=") >= 0
            return invalid
        else if line.Left(26) <> "#EXT-X-I-FRAME-STREAM-INF:"
            out.Push(line)
        end if
    end for
    if pending or variants.Count() = 0 then return invalid
    return { text: out.Join(Chr(10)) + Chr(10), variants: variants }
end function

function lowLatencyResolve(baseUrl as string, reference as string) as string
    if CreateObject("roRegex", "[^!-~]", "").IsMatch(reference) then return ""
    if reference.Left(8) = "https://" then return reference
    if reference.Left(7) = "http://" or reference.Left(2) = "//" then return ""
    if reference.Left(1) = "/"
        origin = CreateObject("roRegex", "^https://[^/?#]+", "").Match(baseUrl)
        if origin.Count() <> 1 then return ""
        return origin[0] + reference
    end if
    directory = CreateObject("roRegex", "^https://[^?#]*/", "").Match(baseUrl)
    if directory.Count() <> 1 then return ""
    return directory[0] + reference
end function

' The first response keeps the newest startCount segments. Later responses
' keep that first segment so a short stall never loses what the player is
' fetching, growing to at most maxCount segments. state.anchor (-1 = unset)
' is shared by all variants, which use Twitch's common media sequence numbers.
function lowLatencyMedia(text as dynamic, state as object, startCount as integer, maxCount as integer) as dynamic
    if GetInterface(text, "ifString") = invalid then return invalid
    if text.Len() < 7 or text.Len() > 262144 then return invalid
    lines = text.Split(Chr(10))
    if lines.Count() > 8192 or lines[0].Trim() <> "#EXTM3U" then return invalid
    header = []
    dateRanges = []
    blocks = []
    block = []
    sequence = -1&
    discontinuities = 0&
    hasDiscontinuities = false
    ended = false
    duration = ""
    map = ""
    unsafe = CreateObject("roRegex", "[^!-~]", "")
    for index = 1 to lines.Count() - 1
        line = lines[index].Trim()
        if line = ""
        else if line.Left(1) <> "#"
            if duration = "" or line.Left(8) <> "https://" or unsafe.IsMatch(line) then return invalid
            block.Push(line)
            blocks.Push({ lines: block, duration: duration, map: map })
            block = []
            duration = ""
        else if line.Left(8) = "#EXTINF:"
            comma = line.InStr(",")
            if comma < 0 then comma = line.Len()
            duration = line.Mid(8, comma - 8)
            if Val(duration) <= 0 then return invalid
            block.Push(line)
        else if line.Left(22) = "#EXT-X-MEDIA-SEQUENCE:"
            sequence = lowLatencyNatural(line.Mid(22))
        else if line.Left(30) = "#EXT-X-DISCONTINUITY-SEQUENCE:"
            discontinuities = lowLatencyNatural(line.Mid(30))
            if discontinuities < 0 then return invalid
            hasDiscontinuities = true
        else if line.Left(22) = "#EXT-X-TARGETDURATION:" or line.Left(23) = "#EXT-X-TWITCH-PREFETCH:"
            ' The target is rewritten from the kept segments; prefetch is unused.
        else if line = "#EXT-X-ENDLIST"
            ended = true
        else if line.Left(17) = "#EXT-X-DATERANGE:"
            ' Kept whole: ad cues stay readable after their segments are trimmed.
            dateRanges.Push(line)
        else if line.Left(17) = "#EXT-X-BYTERANGE:" or line.Left(11) = "#EXT-X-KEY:"
            return invalid
        else if line.Left(11) = "#EXT-X-MAP:"
            map = line
            block.Push(line)
        else if blocks.Count() = 0 and block.Count() = 0 and not lowLatencySegmentTag(line)
            header.Push(line)
        else
            block.Push(line)
        end if
    end for
    if sequence < 0 or blocks.Count() = 0 or block.Count() > 0 then return invalid
    total = blocks.Count()
    newest = sequence + total - 1
    start = total - startCount
    anchor = state.anchor
    if anchor >= sequence and anchor <= newest
        start = CInt(anchor - sequence)
    else if anchor >= 0 and anchor < sequence
        start = 0
    end if
    if total - start > maxCount then start = total - maxCount
    if start < 0 then start = 0
    if anchor < 0 then state.anchor = sequence + start
    target = 1
    for index = start to total - 1
        rounded = Int(Val(blocks[index].duration) + 0.5)
        if rounded > target then target = rounded
    end for
    for index = 0 to start
        for each line in blocks[index].lines
            if line = "#EXT-X-DISCONTINUITY" then discontinuities += 1
        end for
    end for
    out = ["#EXTM3U"]
    out.Append(header)
    out.Push("#EXT-X-TARGETDURATION:" + target.ToStr())
    out.Push("#EXT-X-MEDIA-SEQUENCE:" + (sequence + start).ToStr())
    if hasDiscontinuities or discontinuities > 0 then out.Push("#EXT-X-DISCONTINUITY-SEQUENCE:" + discontinuities.ToStr())
    out.Append(dateRanges)
    first = blocks[start]
    if first.map <> "" and not lowLatencyHas(first.lines, first.map) then out.Push(first.map)
    for index = start to total - 1
        for each line in blocks[index].lines
            if index > start or line <> "#EXT-X-DISCONTINUITY" then out.Push(line)
        end for
    end for
    if ended then out.Push("#EXT-X-ENDLIST")
    return out.Join(Chr(10)) + Chr(10)
end function

function lowLatencySegmentTag(line as string) as boolean
    for each tag in ["#EXT-X-PROGRAM-DATE-TIME:", "#EXT-X-DISCONTINUITY", "#EXT-X-GAP", "#EXT-X-BITRATE:", "#EXT-X-CUE"]
        if line.Left(tag.Len()) = tag then return true
    end for
    return false
end function

function lowLatencyHas(lines as object, value as string) as boolean
    for each line in lines
        if line = value then return true
    end for
    return false
end function

function lowLatencyNatural(text as string) as longinteger
    if not CreateObject("roRegex", "^[0-9]{1,10}$", "").IsMatch(text) then return -1&
    value = 0&
    for index = 1 to text.Len()
        value = value * 10& + Asc(Mid(text, index, 1)) - 48
    end for
    if value > 4294967295& then return -1&
    return value
end function
