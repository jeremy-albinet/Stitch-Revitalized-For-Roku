' @include source/utils/playbackHls.brs
' @include source/utils/deviceCapabilities.brs
sub main()
    q = Chr(34)
    newline = Chr(13) + Chr(10)
    masterText = "#EXTM3U" + newline
    masterText += "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + q + "audio" + q + ",NAME=" + q + "English, stereo" + q + ",URI=" + q + "../sound/list.m3u8?x=a=b" + q + newline
    masterText += "#EXT-X-STREAM-INF:BANDWIDTH=8500000,RESOLUTION=2560x1440,FRAME-RATE=60.000,CODECS=" + q + "hvc1.1.6.L153.B0,mp4a.40.2" + q + ",AUDIO=" + q + "audio" + q + ",VIDEO=" + q + "chunked" + q + newline
    masterText += "# comment between attributes and URI" + newline + "../video/1440.m3u8?sig=fixture" + newline
    masterText += "#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS=" + q + "avc1.640028,mp4a.40.2" + q + newline
    masterText += "//cdn.example/video/1080.m3u8" + newline
    parsed = parsePlaybackHlsMaster(masterText, "https://cdn.example/live/master.m3u8?token=fixture")
    if not playbackExpect(parsed.variants.Count() = 2, "two video variants") then return
    if not playbackExpect(parsed.media[0]["NAME"] = "English, stereo", "quoted comma retained") then return
    if not playbackExpect(parsed.media[0]["URI"] = "https://cdn.example/sound/list.m3u8?x=a=b", "audio relative URL and equals") then return
    if not playbackExpect(parsed.variants[0]["CODECS"] = "hvc1.1.6.L153.B0,mp4a.40.2", "full HEVC/AAC codecs") then return
    if not playbackExpect(parsed.variants[0]["URL"] = "https://cdn.example/video/1440.m3u8?sig=fixture", "relative variant after comment") then return
    if not playbackExpect(parsed.variants[0]["SEPARATE-AUDIO"] = true, "external audio relationship") then return
    if not playbackExpect(parsed.variants[1]["SEPARATE-AUDIO"] = false, "embedded audio relationship") then return
    if not playbackExpect(parsed.variants[1]["URL"] = "https://cdn.example/video/1080.m3u8", "protocol-relative URL") then return
    if not playbackExpect(resolvePlaybackHlsUrl("https://cdn.example/a/b.m3u8?old=1", "?new=2") = "https://cdn.example/a/b.m3u8?new=2", "query-only resolution") then return
    if not playbackExpect(resolvePlaybackHlsUrl("https://cdn.example/a/b.m3u8", "#part") = "https://cdn.example/a/b.m3u8#part", "fragment-only reference keeps the document path") then return
    if not playbackExpect(resolvePlaybackHlsUrl("https://cdn.example/a/b.m3u8?token=fixture#old", "#new") = "https://cdn.example/a/b.m3u8?token=fixture#new", "fragment replaces only the old fragment and preserves the query") then return
    if not playbackExpect(resolvePlaybackHlsUrl("https://cdn.example/a/b.m3u8?token=fixture", "#t=12:30") = "https://cdn.example/a/b.m3u8?token=fixture#t=12:30", "a colon in a fragment is not a URI scheme") then return
    if not playbackExpect(resolvePlaybackHlsUrl("https://cdn.example/a/b.m3u8?token=fixture#old", "#") = "https://cdn.example/a/b.m3u8?token=fixture#", "an empty fragment preserves path and query") then return
    if not playbackExpect(resolvePlaybackHlsUrl("https://cdn.example/a/b.m3u8", "/v/master.m3u8") = "https://cdn.example/v/master.m3u8", "root resolution") then return
    if not playbackExpect(resolvePlaybackHlsUrl("https://cdn.example/a/b.m3u8", "javascript:unsafe") = "", "reject non-HTTP URL") then return
    if not playbackExpect(playbackQualityLabel(parsed.variants[0]) = "1440p60 (Source) HEVC", "source quality label") then return
    if not playbackExpect(parsePlaybackHlsMaster("<html>offline</html>", "https://cdn.example/master.m3u8").variants.Count() = 0, "invalid manifest yields no playable URL") then return
    mediaMap = "#EXTM3U" + newline + "#EXT-X-MAP:URI=" + q + "init.mp4" + q
    if not playbackExpect(isMuxedPlaybackCmaf(parsed.variants[0], mediaMap) = false, "CMAF with external audio is preserved") then return
    if not playbackExpect(isMuxedPlaybackCmaf(parsed.variants[1], mediaMap) = true, "CMAF combined AVC/AAC rendition requires demux") then return
    if not playbackExpect(isMuxedPlaybackCmaf(parsed.variants[1], "#EXTM3U" + newline + "#EXTINF:2," + newline + "segment.ts") = false, "AVC/AAC TS is not demuxed") then return
    if not playbackExpect(isMuxedPlaybackCmaf(parsed.variants[1], "<html>offline</html>") = invalid, "invalid media response is not labelled native") then return

    proxy = "http://audio.example:8080"
    variant = parsed.variants[0]
    url = buildProxyM3u8Url(proxy, variant["URL"], variant)
    quality = playbackQualityEntry(variant, url, false, true)
    if not playbackExpect(quality.url.InStr("http://audio.example:8080/m3u8?u=") = 0, "proxy URL") then return
    if not playbackExpect(quality.StreamUrls[0] = quality.url and quality.Streams[0].url = quality.url, "manual stream URLs agree") then return
    if not playbackExpect(quality.isProxied and not quality.isTransmux and not quality.ForwardQueryStringParams, "manual quality transport contract") then return
    auto = playbackAutomaticEntry([quality], "https://cdn.example/master.m3u8", proxy, [variant["URL"]], true, true, false, [variant["URL"]])
    if not playbackExpect(auto.url.InStr("&variants=") > 0 and auto.isProxied and not auto.ForwardQueryStringParams, "automatic uses filtered master with proxy flags") then return
    if not playbackExpect(auto.Streams[0].url = auto.url and auto.StreamUrls[0] = auto.url, "automatic stream contracts agree") then return
    if not playbackExpect(auto.url.InStr("&demuxVariants=") > 0, "automatic carries verified muxed variant identity") then return
    native = playbackQualityEntry(parsed.variants[1], parsed.variants[1]["URL"], false, false)
    autoNative = playbackAutomaticEntry([native], "https://cdn.example/master.m3u8", "", [native.url], true, false, false)
    if not playbackExpect(autoNative.url = "https://cdn.example/master.m3u8", "native ABR uses master rather than first child") then return
    filteredTs = playbackAutomaticEntry([native], "https://cdn.example/master.m3u8", proxy, [native.url], false, false, false, [])
    if not playbackExpect(filteredTs.url.InStr("&demuxVariants=%5B%5D") > 0, "filtered native TS explicitly bypasses demux") then return
    groupedAudio = playbackAutomaticEntry([quality], "https://cdn.example/master.m3u8", proxy, [variant["URL"]], true, false, true)
    if not playbackExpect(groupedAudio.url.InStr("&variants=") > 0 and groupedAudio.url.InStr("&demuxVariants=") < 0, "external audio leaves video track inspection to service") then return
    descriptor = playbackSelectionDescriptor(variant, parsed.media)
    selectedManual = buildProxySelectedM3u8Url(proxy, "https://cdn.example/master.m3u8?token=fixture", [descriptor])
    selectedAuto = playbackAutomaticEntry([quality], "https://cdn.example/master.m3u8?token=fixture", proxy, [variant["URL"]], true, true, false, [variant["URL"]], [descriptor])
    if not playbackExpect(selectedManual = selectedAuto.url, "new Automatic and manual grouped selection use the same protocol") then return
    if not playbackExpect(selectedAuto.url.InStr("/m3u8/selected?u=") > 0 and selectedAuto.url.InStr("&selections=") > 0, "new filtered selection uses explicit service endpoint") then return
    if not playbackExpect(selectedAuto.url.InStr("&variants=") < 0 and selectedAuto.url.InStr("&demuxVariants=") < 0, "new filtered selection excludes old URL and transport hints") then return
    if not playbackExpect(selectedAuto.isProxied and not selectedAuto.isTransmux and not selectedAuto.ForwardQueryStringParams, "new Automatic preserves proxy transport flags") then return
    if not playbackExpect(selectedAuto.StreamUrls[0] = selectedAuto.url and selectedAuto.Streams[0].url = selectedAuto.url, "new Automatic preserves every stream URL contract") then return
    if not playbackExpect(playbackAutomaticEntry([quality], "https://cdn.example/master.m3u8", proxy, [variant["URL"]], true, true, false, invalid, []) = invalid, "failed new selection does not fall back to legacy URLs") then return
    if not playbackExpect(playbackAutomaticEntry([], "", "", [], false, false, false) = invalid, "empty automatic ladder fails") then return
    ? "STITCH_TEST_PASS: playback-hls"
end sub

function playbackExpect(condition as boolean, detail as string) as boolean
    if not condition then ? "STITCH_TEST_FAIL: " + detail
    return condition
end function
