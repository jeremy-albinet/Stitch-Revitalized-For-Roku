' Pure recorded-source syntax and corroboration. Neither function authorizes egress.
' A future worker must independently fetch the hardcoded Usher source safely.
function rokuVodDescriptorFromTrustedMaster(master as dynamic, usherUrl as dynamic, selection as dynamic, vodId as dynamic) as dynamic
    try
        if not rvdUsher(usherUrl, vodId) then return invalid
        if not rvdKeys(selection, ["sourceUrl", "qualityId"]) then return invalid
        if not rvdOrigin(selection["sourceUrl"]) then return invalid
        if not rokuDemuxAscii(selection["qualityId"], 1, 128) or selection["qualityId"] = "Automatic" then return invalid
        if not rokuDemuxString(master) or master.Len() < 7 or master.Len() > 262144 then return invalid
        if CreateObject("roRegex", "[^" + Chr(9) + Chr(10) + Chr(13) + " -~]", "").IsMatch(master) then return invalid
        lines = master.Split(Chr(10))
        if lines.Count() > 2048 then return invalid
        pending = invalid
        found = invalid
        matches = 0
        variants = 0
        media = []
        sessionData = []
        for lineNo = 0 to lines.Count() - 1
            line = lines[lineNo]
            if line.Right(1) = Chr(13) then line = line.Left(line.Len() - 1)
            if line.Len() > 8192 or line <> line.Trim() or line.InStr(Chr(13)) >= 0 then return invalid
            if lineNo = 0
                if line <> "#EXTM3U" then return invalid
            else if line <> ""
                if line.Left(18) = "#EXT-X-STREAM-INF:"
                    if pending <> invalid then return invalid
                    pending = rvdAttributes(line.Mid(18), ["BANDWIDTH", "AVERAGE-BANDWIDTH", "CODECS", "RESOLUTION", "FRAME-RATE", "VIDEO", "AUDIO", "PROGRAM-ID", "STABLE-VARIANT-ID", "IVS-NAME", "IVS-VARIANT-SOURCE"])
                    if pending = invalid then return invalid
                    if pending.DoesExist("IVS-NAME")
                        if not rokuDemuxAscii(pending["IVS-NAME"], 1, 128) then return invalid
                        pending.Delete("IVS-NAME")
                    end if
                    if pending.DoesExist("IVS-VARIANT-SOURCE") then pending.Delete("IVS-VARIANT-SOURCE")
                else if line.Left(13) = "#EXT-X-MEDIA:"
                    if pending <> invalid or media.Count() >= 64 then return invalid
                    item = rvdAttributes(line.Mid(13), ["TYPE", "GROUP-ID", "NAME", "DEFAULT", "AUTOSELECT", "URI", "LANGUAGE", "CHANNELS", "STABLE-RENDITION-ID", "IVS-NAME"])
                    if item = invalid or not item.DoesExist("TYPE") or not item.DoesExist("GROUP-ID") then return invalid
                    if item.DoesExist("IVS-NAME")
                        if not rokuDemuxAscii(item["IVS-NAME"], 1, 128) then return invalid
                        item.Delete("IVS-NAME")
                    end if
                    media.Push(item)
                else if line.Left(20) = "#EXT-X-SESSION-DATA:"
                    if pending <> invalid or sessionData.Count() >= 64 then return invalid
                    identity = rvdSessionData(line.Mid(20))
                    if identity = invalid then return invalid
                    for each prior in sessionData
                        if prior.id = identity.id and prior.language = identity.language then return invalid
                    end for
                    sessionData.Push(identity)
                else if line.Left(19) = "#EXT-X-TWITCH-INFO:"
                    if pending <> invalid or line.Len() > 4096 then return invalid
                    if rvdAttributes(line.Mid(19), ["NODE", "MANIFEST-NODE-TYPE", "MANIFEST-NODE", "SERVER-TIME", "TRANSCODESTACK", "SERVING-ID", "CLUSTER", "ABS", "BROADCAST-ID", "USER-IP", "REGION", "COUNTRY", "VIDEO-SESSION-ID", "MANIFEST-CLUSTER"]) = invalid then return invalid
                else if line = "#EXT-X-VERSION:3" or line = "#EXT-X-VERSION:7" or line = "#EXT-X-INDEPENDENT-SEGMENTS"
                    if pending <> invalid then return invalid
                else if line.Left(1) <> "#"
                    if pending = invalid then return invalid
                    variants++
                    if variants > 64 or not rvdOrigin(line) then return invalid
                    if line = selection["sourceUrl"]
                        matches++
                        if matches > 1 then return invalid
                        pending["URL"] = line
                        found = pending
                    end if
                    pending = invalid
                else if line.Left(4) = "#EXT"
                    return invalid
                end if
            end if
        end for
        if pending <> invalid or matches <> 1 or found = invalid then return invalid
        for each item in media
            if item.TYPE = "AUDIO" and found["AUDIO"] <> invalid and item["GROUP-ID"] = found["AUDIO"] and item.DoesExist("URI") then return invalid
        end for
        metadata = rokuDemuxMetadataHints(found)
        if metadata = invalid or playbackQualityLabel(found) <> selection["qualityId"] then return invalid
        origin = nviUrl(selection["sourceUrl"]).origin
        descriptor = {
            "version": 2, "mode": "vod", "vodId": vodId, "usherUrl": usherUrl, "sourceUrl": selection["sourceUrl"],
            "qualityId": selection["qualityId"], "approvedOrigin": origin, "metadata": metadata
        }
        if not rokuVodDescriptorValid(descriptor) then return invalid
        return descriptor
    catch error
        return invalid
    end try
end function

function rokuVodDescriptorValid(descriptor as dynamic) as boolean
    try
        if not rvdKeys(descriptor, ["version", "mode", "vodId", "usherUrl", "sourceUrl", "qualityId", "approvedOrigin", "metadata"]) then return false
        if not rokuDemuxInteger(descriptor.version) or descriptor.version <> 2 or not rokuDemuxString(descriptor.mode) or descriptor.mode <> "vod" then return false
        if not rvdUsher(descriptor["usherUrl"], descriptor["vodId"]) or not rvdOrigin(descriptor["sourceUrl"]) then return false
        if not rokuDemuxAscii(descriptor["qualityId"], 1, 128) or descriptor["qualityId"] = "Automatic" then return false
        if not rokuDemuxString(descriptor["approvedOrigin"]) or descriptor["approvedOrigin"] <> nviUrl(descriptor["sourceUrl"]).origin then return false
        if not rvdMetadata(descriptor.metadata) then return false
        return FormatJSON(descriptor).Len() <= 16384
    catch error
        return false
    end try
end function

function rokuVodDescriptorMatchesMaster(descriptor as dynamic, master as dynamic) as boolean
    try
        if not rokuVodDescriptorValid(descriptor) then return false
        rebuilt = rokuVodDescriptorFromTrustedMaster(master, descriptor["usherUrl"], { "sourceUrl": descriptor["sourceUrl"], "qualityId": descriptor["qualityId"] }, descriptor["vodId"])
        if rebuilt = invalid then return false
        for each key in ["videoCodec", "audioCodec", "width", "height", "frameRate", "bandwidth", "isHD"]
            if descriptor.metadata[key] <> rebuilt.metadata[key] then return false
        end for
        return descriptor["approvedOrigin"] = rebuilt["approvedOrigin"]
    catch error
        return false
    end try
end function

function rvdKeys(value as dynamic, keys as object) as boolean
    if type(value) <> "roAssociativeArray" then return false
    if value.Keys().Count() <> keys.Count() then return false
    for each key in keys
        if not value.DoesExist(key) then return false
    end for
    return true
end function

function rvdUsher(url as dynamic, vodId as dynamic) as boolean
    if not rokuDemuxAscii(vodId, 1, 20) then return false
    if not CreateObject("roRegex", "^[1-9][0-9]{0,19}$", "").IsMatch(vodId) then return false
    parsed = nviUrl(url)
    if parsed = invalid then return false
    return parsed.origin = "https://usher.ttvnw.net" and parsed.path = "/vod/v2/" + vodId + ".m3u8"
end function

function rvdOrigin(url as dynamic) as boolean
    parsed = nviUrl(url)
    if parsed = invalid then return false
    host = parsed.origin.Mid(8)
    if host.Len() > 10 and host.Right(10) = ".ttvnw.net" then return true
    return CreateObject("roRegex", "^d[a-z0-9]+\.cloudfront\.net$", "").IsMatch(host)
end function

function rvdMetadata(value as dynamic) as boolean
    if not rvdKeys(value, ["videoCodec", "audioCodec", "width", "height", "frameRate", "bandwidth", "isHD"]) then return false
    for each key in ["videoCodec", "audioCodec", "frameRate"]
        if not rokuDemuxString(value[key]) then return false
    end for
    for each key in ["width", "height", "bandwidth"]
        if not rokuDemuxInteger(value[key]) then return false
    end for
    kind = type(value["isHD"], 3)
    if kind <> "Boolean" and kind <> "roBoolean" then return false
    hinted = rokuDemuxMetadataHints({
        "CODECS": value["videoCodec"] + "," + value["audioCodec"],
        "RESOLUTION": value.width.ToStr() + "x" + value.height.ToStr(), "FRAME-RATE": value["frameRate"], "BANDWIDTH": value.bandwidth.ToStr()
    })
    if hinted = invalid then return false
    return value["isHD"] = hinted["isHD"]
end function

function rvdSessionData(text as string) as dynamic
    result = {}
    quoted = false
    start = 0
    for i = 0 to text.Len()
        char = ","
        if i < text.Len() then char = text.Mid(i, 1)
        if char = Chr(34) then quoted = not quoted
        if char = "," and not quoted
            item = text.Mid(start, i - start)
            equals = item.InStr("=")
            if equals < 1 then return invalid
            key = item.Left(equals)
            minimum = 1
            maximum = 4096
            if key = "DATA-ID"
                maximum = 256
            else if key = "VALUE"
                minimum = 0
            else if key = "LANGUAGE"
                maximum = 64
            else if key <> "URI"
                return invalid
            end if
            if result.DoesExist(key) then return invalid
            value = item.Mid(equals + 1)
            if value.Len() < 2 or value.Left(1) <> Chr(34) or value.Right(1) <> Chr(34) then return invalid
            value = value.Mid(1, value.Len() - 2)
            if not rokuDemuxAscii(value, minimum, maximum) or value.InStr(Chr(34)) >= 0 then return invalid
            result[key] = value
            start = i + 1
        end if
    end for
    if quoted or not result.DoesExist("DATA-ID") then return invalid
    if result.DoesExist("VALUE") = result.DoesExist("URI") then return invalid
    language = ""
    if result.DoesExist("LANGUAGE") then language = result["LANGUAGE"]
    return { id: result["DATA-ID"], language: language }
end function

function rvdAttributes(text as string, allowed as object) as dynamic
    result = {}
    quoted = false
    start = 0
    for i = 0 to text.Len()
        char = ","
        if i < text.Len() then char = text.Mid(i, 1)
        if char = Chr(34) then quoted = not quoted
        if char = "," and not quoted
            item = text.Mid(start, i - start)
            equals = item.InStr("=")
            if equals < 1 then return invalid
            key = item.Left(equals)
            known = false
            for each name in allowed
                if key = name then known = true
            end for
            if not known or result.DoesExist(key) then return invalid
            value = item.Mid(equals + 1)
            if key = "IVS-VARIANT-SOURCE"
                if value <> Chr(34) + "source" + Chr(34) and value <> Chr(34) + "transcode" + Chr(34) then return invalid
            end if
            if value.Left(1) = Chr(34)
                if value.Len() < 2 or value.Right(1) <> Chr(34) then return invalid
                value = value.Mid(1, value.Len() - 2)
            end if
            if not rokuDemuxAscii(value, 1, 1024) or value.InStr(Chr(34)) >= 0 then return invalid
            result[key] = value
            start = i + 1
        end if
    end for
    if quoted or result.Keys().Count() < 1 then return invalid
    return result
end function
