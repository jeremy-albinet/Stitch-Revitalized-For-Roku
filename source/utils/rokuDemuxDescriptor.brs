' Guarded LIVE eligibility only. Actual init/layout and decoder validation belongs
' to the Task-owned session before publication. Never persist or log this input.
function rokuDemuxString(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "String" or kind = "roString"
end function

function rokuDemuxInteger(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "Integer" or kind = "LongInteger" or kind = "roInt"
end function

function rokuDemuxAscii(value as dynamic, minimum as integer, maximum as integer, url = false as boolean) as boolean
    if not rokuDemuxString(value) then return false
    if value.Len() < minimum or value.Len() > maximum then return false
    ' A native match replaces a per-character Mid() scan that cost seconds per
    ' stream open on a G204X. Chr(92) avoids engine-specific source escapes.
    pattern = "[^ -~]"
    if url then pattern = "[^!-~]|[#" + Chr(92) + Chr(92) + "]"
    return not CreateObject("roRegex", pattern, "").IsMatch(value)
end function

function rokuDemuxCdnOrigin(url as dynamic) as dynamic
    if not rokuDemuxAscii(url, 12, 8192, true) then return invalid
    if url.Left(8) <> "https://" then return invalid
    rest = url.Mid(8)
    finish = rest.Len()
    for each separator in ["/", "?"]
        at = rest.InStr(separator)
        if at >= 0 and at < finish then finish = at
    end for
    host = LCase(rest.Left(finish))
    if host.Len() < 11 or host.Len() > 253 or host.Right(10) <> ".ttvnw.net" then return invalid
    for each label in host.Split(".")
        if label.Len() < 1 or label.Len() > 63 then return invalid
        if label.Left(1) = "-" or label.Right(1) = "-" then return invalid
        for i = 0 to label.Len() - 1
            code = Asc(label.Mid(i, 1))
            if (code < 97 or code > 122) and (code < 48 or code > 57) and code <> 45 then return invalid
        end for
    end for
    return "https://" + host
end function

function rokuDemuxAddOrigin(origins as object, url as string) as boolean
    origin = rokuDemuxCdnOrigin(url)
    if origin = invalid then return false
    for each known in origins
        if known = origin then return true
    end for
    if origins.Count() >= 16 then return false
    origins.Push(origin)
    return true
end function

function rokuDemuxMapReference(text as string) as dynamic
    if text.Len() < 1 or text.Len() > 8192 then return invalid
    uri = invalid
    seen = {}
    quoted = false
    start = 0
    for i = 0 to text.Len()
        char = ","
        if i < text.Len() then char = text.Mid(i, 1)
        if char = Chr(34) then quoted = not quoted
        if char = "," and not quoted
            item = text.Mid(start, i - start)
            equals = item.InStr("=")
            if equals <= 0 then return invalid
            name = item.Left(equals)
            if name <> "URI" and name <> "BYTERANGE" then return invalid
            if seen.DoesExist(name) then return invalid
            seen[name] = true
            value = item.Mid(equals + 1)
            if value.Len() < 2 or value.Left(1) <> Chr(34) or value.Right(1) <> Chr(34) then return invalid
            if name = "URI" then uri = value.Mid(1, value.Len() - 2)
            if name = "BYTERANGE" then return invalid
            start = i + 1
        end if
    end for
    if quoted or uri = invalid then return invalid
    return uri
end function

function rokuDemuxMediaOrigins(playlist as dynamic, sourceUrl as string) as dynamic
    if not rokuDemuxString(playlist) then return invalid
    if playlist.Len() < 7 or playlist.Len() > 262144 then return invalid
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(playlist)
    if bytes.Count() > 262144 then return invalid
    bytes = invalid
    lines = playlist.Split(Chr(10))
    if lines.Count() > 1024 then return invalid
    origins = []
    if not rokuDemuxAddOrigin(origins, sourceUrl) then return invalid
    maps = 0
    fragments = 0
    pending = false
    first = true
    for each rawLine in lines
        line = rawLine
        if line.Right(1) = Chr(13) then line = line.Left(line.Len() - 1)
        if first
            if line <> "#EXTM3U" then return invalid
            first = false
        end if
        maximum = 8192
        if line.Left(17) = "#EXT-X-DATERANGE:" then maximum = 32768
        if line.Len() > maximum or line <> line.Trim() then return invalid
        reference = invalid
        if line.Left(11) = "#EXT-X-MAP:"
            reference = rokuDemuxMapReference(line.Mid(11))
            if reference = invalid then return invalid
            maps += 1
            if maps > 16 then return invalid
        else if line.Left(8) = "#EXTINF:"
            if pending then return invalid
            pending = true
        else if line <> "" and line.Left(1) <> "#"
            if not pending then return invalid
            reference = line
            pending = false
            fragments += 1
            if fragments > 128 then return invalid
        end if
        if reference <> invalid
            if not rokuDemuxAscii(reference, 1, 8192, true) then return invalid
            resolved = resolvePlaybackHlsUrl(sourceUrl, reference)
            if not rokuDemuxAddOrigin(origins, resolved) then return invalid
        end if
    end for
    if pending or maps = 0 or fragments = 0 then return invalid
    return origins
end function

function rokuDemuxNatural(text as dynamic, maximum as integer) as dynamic
    if not rokuDemuxString(text) then return invalid
    if text.Len() < 1 or text.Len() > 10 then return invalid
    value = 0&
    for i = 0 to text.Len() - 1
        digit = Asc(text.Mid(i, 1)) - 48
        if digit < 0 or digit > 9 then return invalid
        if value > (maximum - digit) \ 10& then return invalid
        value = value * 10& + digit
    end for
    if value < 1& or value > maximum then return invalid
    return CInt(value)
end function

function rokuDemuxMetadataHints(variant as object) as dynamic
    if variant["SEPARATE-AUDIO"] = true then return invalid
    codecs = variant["CODECS"]
    if not rokuDemuxAscii(codecs, 1, 64) then return invalid
    parts = codecs.Split(",")
    if parts.Count() <> 2 then return invalid
    video = ""
    audio = ""
    for each raw in parts
        codec = raw.Trim()
        lower = LCase(codec)
        if lower.Left(5) = "avc1." or lower.Left(5) = "avc3."
            if video <> "" or codec.Len() <> 11 then return invalid
            hex = codec.Mid(5)
            profile = playbackHexValue(hex.Left(2))
            if profile <> 66 and profile <> 77 and profile <> 100 then return invalid
            if playbackHexValue(hex.Mid(2, 2)) < 0 or playbackHexValue(hex.Right(2)) < 0 then return invalid
            video = codec
        else if lower = "mp4a.40.2"
            if audio <> "" then return invalid
            audio = codec
        else
            return invalid
        end if
    end for
    if video = "" or audio = "" then return invalid
    resolution = variant["RESOLUTION"]
    if not rokuDemuxString(resolution) then return invalid
    dimensions = resolution.Split("x")
    if dimensions.Count() <> 2 then return invalid
    width = rokuDemuxNatural(dimensions[0], 1920)
    height = rokuDemuxNatural(dimensions[1], 1080)
    bandwidth = rokuDemuxNatural(variant["BANDWIDTH"], 20000000)
    if width = invalid or height = invalid or bandwidth = invalid then return invalid
    fps = variant["FRAME-RATE"]
    if not rokuDemuxAscii(fps, 1, 9) then return invalid
    fpsParts = fps.Split(".")
    if fpsParts.Count() < 1 or fpsParts.Count() > 2 then return invalid
    for each part in fpsParts
        if part.Len() < 1 or part.Len() > 6 then return invalid
        for i = 0 to part.Len() - 1
            code = Asc(part.Mid(i, 1))
            if code < 48 or code > 57 then return invalid
        end for
    end for
    if Val(fps) <= 0 or Val(fps) > 60.01 then return invalid
    return { "videoCodec": video, "audioCodec": audio, "width": width, "height": height, "frameRate": fps, "bandwidth": bandwidth, "isHD": height >= 720 }
end function

function rokuDemuxPlaybackDescriptor(variant as object, qualityId as string, origins as dynamic) as dynamic
    metadata = rokuDemuxMetadataHints(variant)
    if metadata = invalid then return invalid
    if not rokuDemuxAscii(qualityId, 1, 128) or qualityId = "Automatic" then return invalid
    sourceUrl = variant["URL"]
    origin = rokuDemuxCdnOrigin(sourceUrl)
    if origin = invalid or type(origins) <> "roArray" then return invalid
    if origins.Count() < 1 or origins.Count() > 16 then return invalid
    copied = []
    foundSource = false
    for each allowed in origins
        canonical = rokuDemuxCdnOrigin(allowed)
        if canonical = invalid or allowed <> canonical then return invalid
        if canonical = origin then foundSource = true
        for each known in copied
            if known = canonical then return invalid
        end for
        copied.Push(canonical)
    end for
    if not foundSource then return invalid
    descriptor = { "version": 1, "sourceUrl": sourceUrl, "qualityId": qualityId, "approvedOrigins": copied, "metadata": metadata }
    if FormatJSON(descriptor).Len() > 16384 then return invalid
    return descriptor
end function

function rokuDemuxPlaybackEntry(entry as object, descriptor = invalid as dynamic) as object
    result = {}
    result.Append(entry)
    result["playbackTransport"] = "direct"
    result["localPlaybackDescriptor"] = invalid
    if entry.isProxied
        result["playbackTransport"] = "python"
    else if descriptor <> invalid
        result["playbackTransport"] = "roku-demux"
        result["localPlaybackDescriptor"] = descriptor
    end if
    return result
end function

function rokuDemuxDescriptorValid(descriptor as dynamic) as boolean
    if type(descriptor) <> "roAssociativeArray" then return false
    keys = ["version", "sourceUrl", "qualityId", "approvedOrigins", "metadata"]
    if descriptor.Count() <> keys.Count() then return false
    for each key in keys
        if not descriptor.DoesExist(key) then return false
    end for
    if not rokuDemuxInteger(descriptor["version"]) or descriptor["version"] <> 1 then return false
    if not rokuDemuxString(descriptor["sourceUrl"]) or not rokuDemuxString(descriptor["qualityId"]) then return false
    metadata = descriptor["metadata"]
    if type(metadata) <> "roAssociativeArray" then return false
    keys = ["videoCodec", "audioCodec", "width", "height", "frameRate", "bandwidth", "isHD"]
    if metadata.Count() <> keys.Count() then return false
    for each key in keys
        if not metadata.DoesExist(key) then return false
    end for
    for each key in ["videoCodec", "audioCodec", "frameRate"]
        if not rokuDemuxString(metadata[key]) then return false
    end for
    for each key in ["width", "height", "bandwidth"]
        if not rokuDemuxInteger(metadata[key]) then return false
    end for
    kind = type(metadata["isHD"], 3)
    if kind <> "Boolean" and kind <> "roBoolean" then return false
    variant = { "URL": descriptor["sourceUrl"], "CODECS": metadata["videoCodec"] + "," + metadata["audioCodec"], "RESOLUTION": metadata["width"].ToStr() + "x" + metadata["height"].ToStr(), "FRAME-RATE": metadata["frameRate"], "BANDWIDTH": metadata["bandwidth"].ToStr() }
    rebuilt = rokuDemuxPlaybackDescriptor(variant, descriptor["qualityId"], descriptor["approvedOrigins"])
    if rebuilt = invalid then return false
    return metadata["isHD"] = rebuilt["metadata"]["isHD"]
end function

function rokuDemuxAutomaticEntry(metadata as object) as dynamic
    chosen = invalid
    for each entry in metadata
        if entry["playbackTransport"] <> "roku-demux" then continue for
        descriptor = entry["localPlaybackDescriptor"]
        if descriptor = invalid then continue for
        if chosen = invalid then chosen = entry
        if descriptor["metadata"]["height"] <= 720
            chosen = entry
            exit for
        end if
    end for
    if chosen = invalid then return invalid
    result = {}
    result.Append(chosen)
    result.QualityID = "Automatic"
    result.playbackNotice = "Automatic selected a compatible quality for this Roku."
    return result
end function
