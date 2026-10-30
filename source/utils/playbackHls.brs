' RFC 8216 attribute lists contain quoted commas (CODECS, NAME, URI).
function parsePlaybackHlsAttributes(text as string) as object
    attributes = {}
    quoted = false
    start = 0
    for index = 0 to text.Len()
        char = ","
        if index < text.Len() then char = text.Mid(index, 1)
        if char = Chr(34) then quoted = not quoted
        if char = "," and not quoted
            item = text.Mid(start, index - start).Trim()
            equals = item.InStr("=")
            if equals > 0
                key = UCase(item.Left(equals).Trim())
                value = item.Mid(equals + 1).Trim()
                if value.Len() >= 2 and value.Left(1) = Chr(34) and value.Right(1) = Chr(34)
                    value = value.Mid(1, value.Len() - 2)
                end if
                attributes[key] = value
            end if
            start = index + 1
        end if
    end for
    return attributes
end function

function resolvePlaybackHlsUrl(base as string, reference as string) as string
    reference = reference.Trim()
    lower = LCase(reference)
    if lower.Left(8) = "https://" or lower.Left(7) = "http://" then return reference
    if reference = "" then return ""
    schemeEnd = base.InStr("://")
    if schemeEnd < 0 then return ""
    if reference.Left(2) = "//" then return base.Left(schemeEnd) + ":" + reference
    ' Same-document fragments inherit the complete path and query.
    if reference.Left(1) = "#" then return base.Split("#")[0] + reference
    if reference.InStr(":") >= 0 and reference.Split("/")[0].InStr(":") >= 0 then return ""
    withoutQuery = base.Split("?")[0].Split("#")[0]
    authorityEnd = withoutQuery.Mid(schemeEnd + 3).InStr("/")
    if authorityEnd < 0
        origin = withoutQuery
        path = "/"
    else
        authorityEnd += schemeEnd + 3
        origin = withoutQuery.Left(authorityEnd)
        path = withoutQuery.Mid(authorityEnd)
    end if
    if reference.Left(1) = "?" then return withoutQuery + reference
    if reference.Left(1) = "/"
        path = reference
    else
        parts = path.Split("/")
        parts.Pop()
        path = parts.Join("/") + "/" + reference
    end if
    suffix = ""
    marker = path.InStr("?")
    if marker < 0 then marker = path.InStr("#")
    if marker >= 0
        suffix = path.Mid(marker)
        path = path.Left(marker)
    end if
    normalized = []
    for each part in path.Split("/")
        if part = ".."
            if normalized.Count() > 0 then normalized.Pop()
        else if part <> "." and part <> ""
            normalized.Push(part)
        end if
    end for
    return origin + "/" + normalized.Join("/") + suffix
end function

function parsePlaybackHlsMaster(text as string, url as string) as object
    master = { variants: [], media: [], isTransmux: false }
    pending = invalid
    for each rawLine in text.Split(Chr(10))
        line = rawLine.Trim()
        if line.Left(18) = "#EXT-X-STREAM-INF:"
            pending = parsePlaybackHlsAttributes(line.Mid(18))
        else if line.Left(13) = "#EXT-X-MEDIA:"
            media = parsePlaybackHlsAttributes(line.Mid(13))
            if media["URI"] <> invalid then media["URI"] = resolvePlaybackHlsUrl(url, media["URI"])
            master.media.Push(media)
        else if line.Left(19) = "#EXT-X-TWITCH-INFO:"
            info = parsePlaybackHlsAttributes(line.Mid(19))
            if info["TRANSCODESTACK"] <> invalid and info["TRANSCODESTACK"].InStr("transmux") >= 0 then master.isTransmux = true
        else if line <> "" and line.Left(1) <> "#" and pending <> invalid
            pending["URL"] = resolvePlaybackHlsUrl(url, line)
            if pending["URL"] <> "" then master.variants.Push(pending)
            pending = invalid
        end if
    end for
    for each variant in master.variants
        variant["SEPARATE-AUDIO"] = false
        if variant["AUDIO"] <> invalid
            for each media in master.media
                if media["TYPE"] = "AUDIO" and media["GROUP-ID"] = variant["AUDIO"] and media["URI"] <> invalid
                    variant["SEPARATE-AUDIO"] = true
                end if
            end for
        end if
    end for
    return master
end function

function isMuxedPlaybackCmaf(variant as object, playlist as string) as dynamic
    if playlist.Trim().Left(7) <> "#EXTM3U" then return invalid
    if playlist.InStr("#EXT-X-MAP:") < 0 then return false
    if variant["SEPARATE-AUDIO"] = true then return false
    codecs = variant["CODECS"]
    if codecs = invalid then return invalid
    ' The media uses fMP4 and its combined rendition declares video and AAC,
    ' with no external audio URI. MAP alone is not evidence of muxed audio.
    if LCase(codecs).InStr("mp4a") >= 0 then return true
    return invalid
end function

function playbackQualityLabel(variant as object) as string
    label = variant["RESOLUTION"].Split("x")[1] + "p"
    if variant["FRAME-RATE"] <> invalid
        fps = Int(Val(variant["FRAME-RATE"]))
        if fps > 30 then label += fps.ToStr()
    end if
    name = variant["VIDEO"]
    if name = invalid then name = variant["STABLE-VARIANT-ID"]
    if name <> invalid and (name = "chunked" or name.InStr("source") >= 0) then label += " (Source)"
    if variant["CODECS"] <> invalid
        if variant["CODECS"].InStr("hvc1") >= 0 or variant["CODECS"].InStr("hev1") >= 0 then label += " HEVC"
    end if
    return label
end function

' Metadata is decoder-filtered and bitrate-sorted; manual choices can still need a service.
function playbackPreferredQualityIndex(metadata as object, preference as dynamic) as integer
    if GetInterface(metadata, "ifArray") = invalid then return 0
    if metadata.Count() = 0 then return 0
    if GetInterface(preference, "ifString") = invalid then return 0
    if preference = "highest"
        if metadata.Count() > 1 then return 1
        return 0
    end if
    if preference = "lowest" then return metadata.Count() - 1
    heights = { "2160p": 2160, "1440p": 1440, "1080p": 1080, "720p": 720, "480p": 480, "360p": 360, "160p": 160 }
    if not heights.DoesExist(preference) then return 0
    target = heights[preference]
    labelPattern = CreateObject("roRegex", "^[1-9][0-9]{1,3}p", "")
    selected = -1
    selectedHeight = 0
    lowest = -1
    lowestHeight = 10000
    for index = 0 to metadata.Count() - 1
        entry = metadata[index]
        if GetInterface(entry, "ifAssociativeArray") = invalid then continue for
        if entry.isTransmux = true and entry.isProxied <> true
            if entry.playbackTransport <> "roku-demux" or entry.localPlaybackDescriptor = invalid then continue for
        end if
        label = entry.QualityID
        if GetInterface(label, "ifString") = invalid then continue for
        if not labelPattern.IsMatch(label) then continue for
        height = CInt(Val(label))
        if height < lowestHeight
            lowest = index
            lowestHeight = height
        end if
        if height <= target and height > selectedHeight
            selected = index
            selectedHeight = height
        end if
    end for
    if selected >= 0 then return selected
    if lowest >= 0 then return lowest
    ' A master-only audio relationship has no safe concrete rendition to select.
    return 0
end function

function buildProxyM3u8Url(proxyUrl as string, streamUrl as string, hints as dynamic) as string
    url = proxyUrl + "/m3u8?u=" + streamUrl.EncodeUriComponent()
    if hints = invalid then return url
    for each pair in [["CODECS", "codecs"], ["BANDWIDTH", "bw"], ["RESOLUTION", "res"]]
        value = hints[pair[0]]
        if value <> invalid and value <> "" then url += "&" + pair[1] + "=" + value.EncodeUriComponent()
    end for
    return url
end function

' Selection identities retain declared metadata, never expiring media URLs.
function playbackSelectionAttributes(source as dynamic, omitted as object) as dynamic
    if GetInterface(source, "ifAssociativeArray") = invalid then return invalid
    attributes = {}
    names = CreateObject("roRegex", "^[A-Z0-9-]{1,128}$", "")
    for each key in source
        if omitted.DoesExist(key) then continue for
        if key = "URL" or key = "URI" or key = "SEPARATE-AUDIO" then return invalid
        if not names.IsMatch(key) then return invalid
        value = source[key]
        if GetInterface(value, "ifString") = invalid then return invalid
        if value.Len() > 4096 then return invalid
        attributes[key] = value
        if attributes.Count() > 64 then return invalid
    end for
    return attributes
end function

function playbackSelectionDescriptor(variant as object, media as object) as dynamic
    attributes = playbackSelectionAttributes(variant, { "URL": true, "SEPARATE-AUDIO": true })
    if attributes = invalid or GetInterface(media, "ifArray") = invalid then return invalid
    groups = []
    for each groupType in ["AUDIO", "VIDEO", "SUBTITLES", "CLOSED-CAPTIONS"]
        groupId = attributes[groupType]
        if groupId = invalid or groupId = "NONE" then continue for
        for each member in media
            if GetInterface(member, "ifAssociativeArray") = invalid then return invalid
            if member["TYPE"] = groupType and member["GROUP-ID"] = groupId
                groupAttributes = playbackSelectionAttributes(member, { "URI": true })
                if groupAttributes = invalid then return invalid
                ' Quote mixed-case JSON keys: native BrightScript lowercases identifiers.
                groups.Push({ "attributes": groupAttributes, "hasUri": member.DoesExist("URI") })
                if groups.Count() > 64 then return invalid
            end if
        end for
    end for
    return { "attributes": attributes, "groups": groups }
end function

function playbackSelectionAttributeBytes(attributes as object, remaining as integer) as integer
    bytes = CreateObject("roByteArray")
    total = 0
    for each key in attributes
        bytes.FromAsciiString(FormatJSON(key))
        total += bytes.Count()
        bytes.FromAsciiString(FormatJSON(attributes[key]))
        total += bytes.Count()
        if total > remaining then exit for
    end for
    return total
end function

function playbackSelectionJson(selections as dynamic) as dynamic
    if GetInterface(selections, "ifArray") = invalid then return invalid
    if selections.Count() < 1 or selections.Count() > 32 then return invalid
    minimumBytes = 0
    for each selection in selections
        if GetInterface(selection, "ifAssociativeArray") = invalid then return invalid
        if selection.Count() <> 2 then return invalid
        for each key in selection
            if key <> "attributes" and key <> "groups" then return invalid
        end for
        attributes = playbackSelectionAttributes(selection.attributes, {})
        if attributes = invalid then return invalid
        ' Bound encoded leaf bytes before allocating the complete JSON array.
        ' This is a lower bound; the exact final check also includes punctuation.
        minimumBytes += playbackSelectionAttributeBytes(attributes, 32768 - minimumBytes)
        if minimumBytes > 32768 then return invalid
        if GetInterface(selection.groups, "ifArray") = invalid then return invalid
        if selection.groups.Count() > 64 then return invalid
        for each member in selection.groups
            if GetInterface(member, "ifAssociativeArray") = invalid then return invalid
            if member.Count() <> 2 then return invalid
            for each key in member
                if key <> "attributes" and key <> "hasUri" then return invalid
            end for
            attributes = playbackSelectionAttributes(member.attributes, {})
            if attributes = invalid then return invalid
            minimumBytes += playbackSelectionAttributeBytes(attributes, 32768 - minimumBytes)
            if minimumBytes > 32768 then return invalid
            if GetInterface(member["hasUri"], "ifBoolean") = invalid then return invalid
        end for
    end for
    json = FormatJSON(selections)
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(json) ' Documented UTF-8 conversion, despite the method name.
    if bytes.Count() > 32768 then return invalid
    return json
end function

function proxySupportsSelectedMaster(health as dynamic) as boolean
    if GetInterface(health, "ifAssociativeArray") = invalid then return false
    if GetInterface(health.status, "ifString") = invalid then return false
    if health.status <> "ok" then return false
    ' Released 0.3.0 already implements this route, before capability advertising.
    if GetInterface(health.version, "ifString") <> invalid
        if health.version = "0.3.0" then return true
    end if
    if GetInterface(health.selected_master_version, "ifInt") = invalid then return false
    return health.selected_master_version = 1
end function

function buildProxySelectedM3u8Url(proxyUrl as string, masterUrl as string, selections as dynamic) as dynamic
    json = playbackSelectionJson(selections)
    if json = invalid then return invalid
    return proxyUrl + "/m3u8/selected?u=" + masterUrl.EncodeUriComponent() + "&selections=" + json.EncodeUriComponent()
end function

' A quality entry is a complete playback contract, not just a display label.
function playbackQualityEntry(variant as object, url as string, isTransmux as boolean, isProxied as boolean) as object
    quality = playbackQualityLabel(variant)
    bitrate = 0
    if variant["BANDWIDTH"] <> invalid then bitrate = Int(Val(variant["BANDWIDTH"]) / 1000)
    hd = Val(variant["RESOLUTION"].Split("x")[1]) >= 720
    return {
        QualityID: quality,
        url: url,
        streamFormat: "hls",
        StreamUrls: [url],
        Streams: [{ url: url, stickyredirects: false, quality: hd, contentid: quality, bitrate: bitrate }],
        StreamQualities: [hd],
        StreamContentIds: [quality],
        StreamBitrates: [bitrate],
        StreamStickyHttpRedirects: [false],
        isTransmux: isTransmux,
        isProxied: isProxied,
        playbackNotice: "",
        ForwardQueryStringParams: not isProxied
    }
end function

function playbackAutomaticEntry(metadata as object, masterUrl as string, proxyUrl as string, allowedUrls as object, allSupported as boolean, hasMuxed as boolean, hasSeparateAudio as boolean, demuxUrls = invalid as dynamic, selections = invalid as dynamic) as dynamic
    if metadata.Count() = 0 then return invalid
    entry = {}
    entry.Append(metadata[0])
    entry.QualityID = "Automatic"
    if proxyUrl <> "" and (hasMuxed or hasSeparateAudio or not allSupported)
        if selections <> invalid
            selectedUrl = buildProxySelectedM3u8Url(proxyUrl, masterUrl, selections)
            if selectedUrl = invalid then return invalid
            entry.url = selectedUrl
        else
            ' Compatibility for older helper callers; the task always supplies selections.
            entry.url = buildProxyM3u8Url(proxyUrl, masterUrl, invalid) + "&variants=" + FormatJSON(allowedUrls).EncodeUriComponent()
            if demuxUrls <> invalid then entry.url += "&demuxVariants=" + FormatJSON(demuxUrls).EncodeUriComponent()
        end if
        entry.StreamUrls = [entry.url]
        entry.isTransmux = false
        entry.isProxied = true
        entry.ForwardQueryStringParams = false
    else if allSupported and not hasMuxed
        entry.url = masterUrl
        entry.StreamUrls = [masterUrl]
    end if
    entry.Streams = [{ url: entry.url, stickyredirects: false, quality: entry.StreamQualities[0], contentid: "Automatic", bitrate: entry.StreamBitrates[0] }]
    if proxyUrl = "" and (not allSupported or hasMuxed)
        entry.playbackNotice = "Automatic selected a compatible quality for this Roku. Configure the audio service to adapt across a filtered quality ladder."
    else if proxyUrl = "" and hasSeparateAudio
        entry.playbackNotice = "Automatic preserves this stream's separate audio. Configure the audio service to choose a manual quality."
    end if
    return entry
end function
