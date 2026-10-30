sub main()
    try
        request = m.top.contentRequested
        if request = invalid
            respondPlaybackError("Content unavailable", "Select the video again from Browse.")
            return
        end if
        if request.contentType = "CLIP"
            loadClipContent(request)
        else
            loadHlsContent(request)
        end if
    catch e
        captureException(e, "GetTwitchContent/main")
        respondPlaybackError("Unable to load video", "Twitch returned an unexpected response. Try again in a moment.")
    end try
end sub

function playbackRequestContent(request as object) as object
    content = CreateObject("roSGNode", "TwitchContentNode")
    fields = request
    if GetInterface(fields, "ifSGNodeChildren") <> invalid then fields = fields.GetFields()
    fields.Delete("change")
    fields.Delete("focusedChild")
    content.SetFields(fields)
    return content
end function

sub respondPlaybackError(title as string, description as string, code = "" as string)
    content = CreateObject("roSGNode", "TwitchContentNode")
    content.SetFields({ contentType: "ERROR", title: title, description: description, errorCode: code })
    m.top.response = content
end sub

sub loadClipContent(request as object)
    slug = request.clipSlug
    if slug = invalid or slug = "" then slug = request.contentId
    if slug = invalid or slug = ""
        respondPlaybackError("Clip unavailable", "This clip no longer has a playback identifier.")
        return
    end if
    ' Resolve the signed source from Twitch before attempting legacy CDN guesses.
    url = getClipUrlViaGraphQL(slug)
    if url = invalid
        for each fallback in generateClipFallbackUrls(slug)
            if isClipUrlAccessible(fallback)
                url = fallback
                exit for
            end if
        end for
    end if
    if url = invalid
        respondPlaybackError("Clip unavailable", "Twitch could not load this clip. It may have been removed; try again later.")
        return
    end if
    content = playbackRequestContent(request)
    content.SetFields({ url: url, streamFormat: "mp4", StreamUrls: [url], StreamQualities: [true], StreamContentIds: ["Original"], QualityID: "Original", ignoreStreamErrors: false, playbackTransport: "direct", localPlaybackDescriptor: invalid })
    m.top.metadata = []
    m.top.response = content
end sub

sub loadHlsContent(request as object)
    token = invalid
    liveStream = invalid
    if request.contentType = "VOD"
        rsp = TwitchGraphQLRequest({
            query: "query VodPlayerWrapper_Query($videoId: ID!, $platform: String!, $playerType: String!, $skipPlayToken: Boolean!) { video(id: $videoId) @skip(if: $skipPlayToken) { playbackAccessToken(params: {platform: $platform, playerType: $playerType}) { signature value } id } }",
            variables: { "videoId": request.contentId, platform: "web_tv", "playerType": "pulsar", "skipPlayToken": false }
        })
        if rsp <> invalid and rsp.data <> invalid and rsp.data.video <> invalid then token = rsp.data.video.playbackAccessToken
        endpoint = "/vod/v2/" + request.contentId + ".m3u8?nauth="
        signatureParam = "&nauthsig="
    else if request.contentType = "LIVE"
        rsp = TwitchGraphQLRequest({
            query: "query StreamPlayer_Query($login: String!, $playerType: String!, $platform: String!, $skipPlayToken: Boolean!) { user(login: $login) { stream @skip(if: $skipPlayToken) { createdAt game { name displayName boxArtURL } playbackAccessToken(params: {platform: $platform, playerType: $playerType}) { signature value } } } }",
            variables: { login: request.streamerLogin, platform: "web_tv", "playerType": "roku", "skipPlayToken": false }
        })
        if rsp <> invalid and rsp.data <> invalid and rsp.data.user <> invalid and rsp.data.user.stream <> invalid
            liveStream = rsp.data.user.stream
            token = liveStream.playbackAccessToken
        end if
        endpoint = "/api/v2/channel/hls/" + request.streamerLogin + ".m3u8?token="
        signatureParam = "&sig="
    else
        respondPlaybackError("Content unavailable", "This type of content does not support playback.")
        return
    end if
    if token = invalid or token.value = invalid or token.signature = invalid
        respondPlaybackError("Video unavailable", "Twitch could not authorize this video. The stream may be offline or the video may be restricted.", "token_fetch_failed")
        return
    end if

    ' Current Usher names are h264/h265, distinct from HLS avc1/hvc1 strings.
    ' https://github.com/streamlink/streamlink/blob/master/src/streamlink/plugins/twitch.py
    device = CreateObject("roDeviceInfo")
    usherUrl = "https://usher.ttvnw.net" + endpoint + token.value.EncodeUriComponent() + signatureParam + token.signature.EncodeUriComponent()
    usherUrl += "&allow_source=true&playlist_include_framerate=true&multigroup_video=true&supported_codecs=" + getTwitchSupportedCodecs(device).EncodeUriComponent()
    headers = { Accept: "*/*", Origin: "https://android.tv.twitch.tv", Referer: "https://android.tv.twitch.tv/", "User-Agent": "Stitch Roku", "Client-ID": "kimne78kx3ncx6brgo4mv6wki5h1ko" }
    response = HttpRequest({ url: usherUrl, method: "GET", headers: headers, timeout: 15000, retries: 2 }).Send()
    if response = invalid
        respondPlaybackError("Connection problem", "The video playlist did not arrive. Check your connection and try again.")
        return
    end if
    if response.GetResponseCode() <> 200
        code = ""
        message = "Twitch could not load this video. Try again later."
        error = ParseJSON(response.GetString())
        if GetInterface(error, "ifArray") <> invalid and error.Count() > 0
            if error[0].error <> invalid then message = error[0].error
            if error[0].error_code <> invalid then code = error[0].error_code
        end if
        respondPlaybackError("Video unavailable", message, code)
        return
    end if
    rawMaster = response.GetString()
    manifest = parsePlaybackHlsMaster(rawMaster, usherUrl)
    proxyUrl = get_user_setting("proxy.url", "").Trim()
    while proxyUrl.Right(1) = "/"
        proxyUrl = proxyUrl.Left(proxyUrl.Len() - 1)
    end while
    m.rokuDemuxEnabled = false
    m.rokuVodEnabled = request.contentType = "VOD" and rokuVodRuntimeAvailable()
    if m.top.HasField("enableRokuDemux") then m.rokuDemuxEnabled = m.top.enableRokuDemux and (request.contentType = "LIVE" or m.rokuVodEnabled) and proxyUrl = ""
    m.rokuVodEnabled = m.rokuVodEnabled and m.rokuDemuxEnabled
    metadata = []
    nativeMetadata = []
    allowedUrls = []
    selections = []
    hasMuxedVariants = false
    hasSeparateAudio = false
    allVariantsSupported = true
    m.playbackProbeCount = 0
    m.playbackProbeCache = {}
    m.playbackProbeOrigins = {}
    m.playbackProbeVodComplete = {}
    m.playbackProbeFailed = false
    m.proxySelectionChecked = invalid
    m.playbackProbeClock = CreateObject("roTimeSpan")
    m.playbackProbeClock.Mark()
    for each variant in manifest.variants
        if variant["RESOLUTION"] = invalid then continue for
        if not isTwitchVariantSupported(variant, device)
            allVariantsSupported = false
            continue for
        end if
        separateAudio = variant["SEPARATE-AUDIO"]
        hasSeparateAudio = hasSeparateAudio or separateAudio
        transmux = false
        if not separateAudio
            transmux = isMuxedCmafVariant(variant, headers)
            if transmux = invalid
                if manifest.isTransmux
                    transmux = true
                else
                    allVariantsSupported = false
                    continue for
                end if
            end if
        end if
        hasMuxedVariants = hasMuxedVariants or transmux
        selection = playbackSelectionDescriptor(variant, manifest.media)
        if allowedUrls.Count() < 32
            allowedUrls.Push(variant["URL"])
            selections.Push(selection)
        end if
        url = variant["URL"]
        proxied = false
        if proxyUrl <> "" and (transmux or separateAudio)
            if separateAudio
                if not ensureProxySelectionSupport(proxyUrl) then return
                url = buildProxySelectedM3u8Url(proxyUrl, usherUrl, [selection])
                if url = invalid
                    respondPlaybackError("Playlist selection unavailable", "The stream's quality metadata could not be safely selected. Reopen the video to refresh it.")
                    return
                end if
            else
                url = buildProxyM3u8Url(proxyUrl, url, variant)
            end if
            proxied = true
        else if separateAudio
            ' A child video playlist alone omits its external audio. Retain
            ' the complete native master; manual selection requires hosting
            ' a filtered master through the optional service.
            continue for
        end if
        entry = playbackQualityEntry(variant, url, transmux and not proxied, proxied)
        descriptor = invalid
        if m.rokuDemuxEnabled and transmux and not separateAudio
            if m.rokuVodEnabled
                if m.playbackProbeVodComplete[variant["URL"]] = true then descriptor = rokuVodDescriptorFromTrustedMaster(rawMaster, usherUrl, { "sourceUrl": variant["URL"], "qualityId": entry.QualityID }, request.contentId)
            else
                descriptor = rokuDemuxPlaybackDescriptor(variant, entry.QualityID, m.playbackProbeOrigins[variant["URL"]])
            end if
        end if
        entry = rokuDemuxPlaybackEntry(entry, descriptor)
        metadata.Push(entry)
        if not transmux then nativeMetadata.Push(entry)
    end for
    if proxyUrl = "" and nativeMetadata.Count() > 0
        retainedMetadata = []
        for each entry in metadata
            if not entry.isTransmux or (entry.playbackTransport = "roku-demux" and entry.localPlaybackDescriptor <> invalid)
                retainedMetadata.Push(entry)
            end if
        end for
        metadata = retainedMetadata
    end if
    if metadata.Count() = 0
        if allVariantsSupported and hasSeparateAudio and not hasMuxedVariants
            ' All renditions have external audio; preserve the upstream master.
            variant = invalid
            for each candidate in manifest.variants
                if candidate["RESOLUTION"] <> invalid
                    variant = candidate
                    exit for
                end if
            end for
            entry = playbackQualityEntry(variant, usherUrl, false, false)
            entry.QualityID = "Automatic"
            entry.playbackNotice = "Automatic preserves this stream's separate audio. Configure the audio service to choose a manual quality."
            entry = rokuDemuxPlaybackEntry(entry)
            metadata.Push(entry)
        else
            if m.playbackProbeFailed
                respondPlaybackError("Video transport unavailable", "Twitch's video playlists could not be inspected within the connection deadline. Check your connection and try again.")
                return
            end if
            if hasSeparateAudio and proxyUrl = ""
                respondPlaybackError("Audio service needed for quality filtering", "This Roku supports part of the video ladder, but the video uses separate audio. Configure the optional audio service in Settings to select compatible qualities while preserving sound.")
                return
            end if
            respondPlaybackError("No compatible quality", "Twitch did not offer a video quality this Roku can decode. Try another stream or a lower quality broadcast.")
            return
        end if
    end if
    sortPlaybackMetadata(metadata)
    if metadata[0].QualityID <> "Automatic"
        automatic = invalid
        automaticMetadata = metadata
        if proxyUrl = "" and nativeMetadata.Count() > 0
            ' Keep native Automatic while retaining eligible local manual choices.
            sortPlaybackMetadata(nativeMetadata)
            automaticMetadata = nativeMetadata
        else if m.rokuDemuxEnabled
            automatic = rokuDemuxAutomaticEntry(metadata)
        end if
        if automatic = invalid
            if proxyUrl <> "" and (hasMuxedVariants or hasSeparateAudio or not allVariantsSupported)
                if not ensureProxySelectionSupport(proxyUrl) then return
            end if
            automatic = playbackAutomaticEntry(automaticMetadata, usherUrl, proxyUrl, allowedUrls, allVariantsSupported, hasMuxedVariants, hasSeparateAudio, invalid, selections)
            if automatic <> invalid then automatic = rokuDemuxPlaybackEntry(automatic)
        end if
        if automatic = invalid
            respondPlaybackError("Playlist selection unavailable", "The stream's quality metadata could not be safely selected. Reopen the video to refresh it.")
            return
        end if
        ' SceneGraph ignores legacy StreamUrls for HLS ABR. A real master URL
        ' enables adaptation, provided every offered variant is safe/native.
        metadata.Unshift(automatic)
    end if
    preference = get_user_setting("playback.video.quality", "auto")
    index = playbackPreferredQualityIndex(metadata, preference)
    content = playbackRequestContent(request)
    content.SetFields(metadata[index])
    if liveStream <> invalid
        if GetInterface(liveStream.createdAt, "ifString") <> invalid then content.createdAt = liveStream.createdAt
        if GetInterface(liveStream.game, "ifAssociativeArray") <> invalid
            if GetInterface(liveStream.game.name, "ifString") <> invalid then content.gameName = liveStream.game.name
            if GetInterface(liveStream.game.displayName, "ifString") <> invalid then content.gameDisplayName = liveStream.game.displayName
            if GetInterface(liveStream.game.boxArtURL, "ifString") <> invalid then content.gameBoxArtUrl = liveStream.game.boxArtURL.Replace("{width}", "188").Replace("{height}", "250")
        end if
    end if
    content.live = request.contentType = "LIVE"
    m.top.metadata = metadata
    m.top.response = content
end sub

function ensureProxySelectionSupport(proxyUrl as string) as boolean
    if m.proxySelectionChecked <> invalid then return m.proxySelectionChecked
    m.proxySelectionChecked = false
    response = HttpRequest({ url: proxyUrl + "/health", method: "GET", timeout: 3000, retries: 1 }).Send()
    health = invalid
    if response <> invalid
        if response.GetResponseCode() = 200 then health = ParseJSON(response.GetString())
    end if
    validHealth = false
    if GetInterface(health, "ifAssociativeArray") <> invalid
        if GetInterface(health.status, "ifString") <> invalid then validHealth = health.status = "ok"
    end if
    if not validHealth
        respondPlaybackError("Audio service unavailable", "Could not check the configured audio service. Check its address and connection, or clear its URL in Settings to use supported playback on this Roku.", "proxy_health_failed")
        return false
    end if
    m.proxySelectionChecked = proxySupportsSelectedMaster(health)
    if not m.proxySelectionChecked
        respondPlaybackError("Update the audio service", "Update the configured audio service to version 0.3.0 or later. You can also clear its URL in Settings to use supported playback on this Roku.", "proxy_upgrade_required")
    end if
    return m.proxySelectionChecked
end function

function isMuxedCmafVariant(variant as object, headers as object) as dynamic
    url = variant["URL"]
    if m.playbackProbeCache[url] <> invalid then return m.playbackProbeCache[url]
    remaining = 15000 - m.playbackProbeClock.TotalMilliseconds()
    if remaining <= 0 or m.playbackProbeCount >= 8
        m.playbackProbeFailed = true
        return invalid
    end if
    timeout = 3000
    if remaining < timeout then timeout = remaining
    m.playbackProbeCount++
    response = HttpRequest({ url: url, method: "GET", headers: headers, timeout: timeout, retries: 1 }).Send()
    isMuxed = invalid
    if response <> invalid and response.GetResponseCode() = 200
        playlist = response.GetString()
        isMuxed = isMuxedPlaybackCmaf(variant, playlist)
        if m.rokuDemuxEnabled and isMuxed = true
            if m.rokuVodEnabled
                cache = m.playbackProbeVodComplete
                completed = rokuVodPlaylistCompleted(playlist, url)
                if m.playbackProbeClock.TotalMilliseconds() >= 15000
                    m.playbackProbeFailed = true
                    return invalid
                end if
                cache[url] = completed
                m.playbackProbeVodComplete = cache
            else
                origins = rokuDemuxMediaOrigins(playlist, url)
                if origins <> invalid
                    cache = m.playbackProbeOrigins
                    cache[url] = origins
                    m.playbackProbeOrigins = cache
                end if
            end if
        end if
    end if
    if isMuxed = invalid then m.playbackProbeFailed = true
    m.playbackProbeCache[url] = isMuxed
    return isMuxed
end function

sub sortPlaybackMetadata(metadata as object)
    for index = 0 to metadata.Count() - 2
        for other = index + 1 to metadata.Count() - 1
            if metadata[index].StreamBitrates[0] < metadata[other].StreamBitrates[0]
                temp = metadata[index]
                metadata[index] = metadata[other]
                metadata[other] = temp
            end if
        end for
    end for
end sub

function getClipUrlViaGraphQL(slug as string) as dynamic
    rsp = TwitchGraphQLRequest({
        query: "query ClipAccessToken($slug: ID!) { clip(slug: $slug) { playbackAccessToken(params: {platform: " + Chr(34) + "web" + Chr(34) + ", playerType: " + Chr(34) + "site" + Chr(34) + "}) { signature value } videoQualities { frameRate quality sourceURL } } }",
        variables: { slug: slug }
    })
    if rsp = invalid or rsp.data = invalid or rsp.data.clip = invalid then return invalid
    clip = rsp.data.clip
    if GetInterface(clip.videoQualities, "ifArray") = invalid then return invalid
    best = invalid
    lowest = invalid
    for each quality in clip.videoQualities
        if quality.sourceURL <> invalid and quality.sourceURL <> ""
            if lowest = invalid
                lowest = quality
            else if Val(quality.quality) < Val(lowest.quality)
                lowest = quality
            end if
            if Val(quality.quality) <= 1080
                if best = invalid
                    best = quality
                else if Val(quality.quality) > Val(best.quality)
                    best = quality
                end if
            end if
        end if
    end for
    if best = invalid then best = lowest
    if best = invalid then return invalid
    url = best.sourceURL
    token = clip.playbackAccessToken
    if token <> invalid and token.value <> invalid and token.signature <> invalid
        separator = "?"
        if url.InStr("?") >= 0 then separator = "&"
        url += separator + "token=" + token.value.EncodeUriComponent() + "&sig=" + token.signature.EncodeUriComponent()
    end if
    return url
end function

function generateClipFallbackUrls(slug as string) as object
    ' Retain two legacy endpoints for old clips, with a six-second total budget.
    return ["https://clips-media-assets2.twitch.tv/" + slug.EncodeUriComponent() + ".mp4", "https://clips-media-assets.twitch.tv/" + slug.EncodeUriComponent() + ".mp4"]
end function

function isClipUrlAccessible(url as string) as boolean
    response = HttpRequest({ url: url, method: "GET", headers: { Range: "bytes=0-1023", Accept: "video/mp4" }, timeout: 3000, retries: 1 }).Send()
    return response <> invalid and (response.GetResponseCode() = 200 or response.GetResponseCode() = 206)
end function
