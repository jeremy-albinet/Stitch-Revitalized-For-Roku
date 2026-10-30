sub descriptorAssert(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "STITCH_ROKU_DESCRIPTOR_FAIL: " + label
    end if
end sub

function descriptorVariant(video as string, bandwidth as string, resolution as string, url as string, codec = "avc1.4D401F,mp4a.40.2" as string, fps = "60.000" as string, extra = "" as string) as string
    line = "#EXT-X-STREAM-INF:BANDWIDTH=" + bandwidth + ",RESOLUTION=" + resolution + ",CODECS=" + Chr(34) + codec + Chr(34) + ",VIDEO=" + Chr(34) + video + Chr(34)
    if fps <> "" then line += ",FRAME-RATE=" + fps
    if extra <> "" then line += "," + extra
    return line + Chr(10) + url + Chr(10)
end function

function descriptorPlaylist(extra = "" as string) as string
    return "#EXTM3U" + Chr(10) + extra + "#EXT-X-MAP:URI=" + Chr(34) + "https://fragments.cloudfront.hls.ttvnw.net/canned/init.mp4?sig=map%2Bvalue" + Chr(34) + Chr(10) + "#EXTINF:2.000," + Chr(10) + "https://fragments.cloudfront.hls.ttvnw.net/canned/seg.m4s?token=media%2Bvalue&sig=signed%2526value" + Chr(10)
end function

sub descriptorRun(host as object, master as string, bodies as object, enabled as boolean, proxy = "" as string, preference = "auto" as string, contentType = "LIVE" as string)
    m.cases++
    host.fixtureMaster = master
    host.fixtureBodies = bodies
    host.enableRokuDemux = enabled
    host.fixtureProxy = proxy
    host.fixturePreference = preference
    host.fixtureProbes = 0
    host.fixtureApprovals = 0
    host.metadata = []
    host.response = invalid
    request = { contentType: contentType, contentId: "canned-id", streamerId: "canned-streamer", streamerLogin: "canned", streamerDisplayName: "Canned broadcaster", contentTitle: "Canned title", description: "Caller retained", playbackTransport: "roku-demux", localPlaybackDescriptor: { stale: true } }
    host.callFunc("loadHlsContent", request)
    if host.response.contentType <> "ERROR"
        descriptorAssert(host.response.contentId = request.contentId and host.response.streamerId = request.streamerId and host.response.description = request.description, "original request metadata retained")
        if contentType = "LIVE" then descriptorAssert(host.response.createdAt = "2026-10-27T18:00:00Z" and host.response.gameName = "fresh-category" and host.response.gameDisplayName = "Fresh category" and host.response.gameBoxArtUrl = "https://static-cdn.jtvnw.net/ttv-boxart/fixture-188x250.jpg", "live playback keeps the fresh stream start, category and usable art alongside the selected transport")
    end if
end sub

sub descriptorLocal(host as object, quality as string, url as string)
    content = host.response
    value = content.localPlaybackDescriptor
    descriptorAssert(content.playbackTransport = "roku-demux" and rokuDemuxDescriptorValid(value), "valid typed local descriptor")
    if value = invalid then return
    descriptorAssert(value.Count() = 5 and value["metadata"].Count() = 7, "exact five/seven schema")
    descriptorAssert(value["sourceUrl"] = url and value["qualityId"] = quality, "exact offered fixed identity")
    descriptorAssert(content.url = url and content.StreamUrls.Count() = 1 and content.StreamUrls[0] = url, "fixed child URL arrays preserved")
    ' brs-node ContentNode rejects the inherited Streams field type. Inspect the
    ' actual handler's published AA, without changing the production node shape.
    entry = invalid
    for each item in host.metadata
        if item.QualityID = content.QualityID then entry = item
    end for
    descriptorAssert(entry <> invalid and entry.Streams.Count() = 1 and entry.Streams[0].url = url and entry.Streams[0].contentid = quality, "fixed underlying stream identity preserved")
    descriptorAssert(content.StreamContentIds.Count() = 1 and content.StreamContentIds[0] = quality, "selected child content ID retained")
    descriptorAssert(content.isTransmux and not content.isProxied and content.ForwardQueryStringParams, "combined source facts remain until manager ready")
    descriptorAssert(value["approvedOrigins"].Count() = 2 and value["approvedOrigins"][0] = "https://use14.playlist.ttvnw.net" and value["approvedOrigins"][1] = "https://fragments.cloudfront.hls.ttvnw.net", "bounded exact source and media origins")
    json = FormatJSON(value)
    descriptorAssert(json.InStr("OAUTH_NEVER_EXPORT") < 0 and json.InStr("canned-playback-token") < 0 and json.InStr("headers") < 0, "no credentials or upstream request forwarding")
end sub

sub descriptorLegacy(host as object, transport as string)
    descriptorAssert(host.response.playbackTransport = transport and host.response.localPlaybackDescriptor = invalid, "legacy path clears stale local routing")
end sub

sub descriptorManualLocal(host as object, index as integer, quality as string, url as string)
    if index < 0 or index >= host.metadata.Count()
        descriptorAssert(false, "retained manual quality is missing")
        return
    end if
    entry = host.metadata[index]
    value = entry.localPlaybackDescriptor
    descriptorAssert(entry.QualityID = quality and entry.playbackTransport = "roku-demux" and rokuDemuxDescriptorValid(value), "retained manual quality has valid local identity")
    if value = invalid then return
    descriptorAssert(value["sourceUrl"] = url and value["qualityId"] = quality, "retained manual descriptor keeps exact signed source and quality")
    descriptorAssert(entry.url = url and entry.StreamUrls.Count() = 1 and entry.StreamUrls[0] = url and entry.Streams.Count() = 1 and entry.Streams[0].url = url, "retained manual quality keeps complete URL contract")
    descriptorAssert(entry.StreamContentIds[0] = quality and entry.Streams[0].contentid = quality, "retained manual quality keeps stream content identity")
    descriptorAssert(entry.isTransmux and not entry.isProxied and entry.ForwardQueryStringParams, "retained manual source still requires explicit conversion action")
    descriptorAssert(value["approvedOrigins"].Count() = 2 and value["approvedOrigins"][0] = "https://use14.playlist.ttvnw.net" and value["approvedOrigins"][1] = "https://fragments.cloudfront.hls.ttvnw.net", "retained manual quality keeps approved media origins")
end sub

sub descriptorHelperCases()
    base = "https://use14.playlist.ttvnw.net/path/media.m3u8?token=source%2Bvalue&sig=source%2526value"
    body = descriptorPlaylist()
    origins = rokuDemuxMediaOrigins(body, base)
    descriptorAssert(origins.Count() = 2, "helper gets exact two origins")
    relative = "#EXTM3U" + Chr(10) + "#EXT-X-MAP:URI=" + Chr(34) + "../init.mp4?sig=a%2Fb" + Chr(34) + Chr(10) + "#EXTINF:2," + Chr(10) + "seg.m4s?token=a%2B%2526" + Chr(10)
    origins = rokuDemuxMediaOrigins(relative, base)
    descriptorAssert(origins.Count() = 1 and origins[0] = "https://use14.playlist.ttvnw.net", "relative signed refs inherit exact origin")
    for each bad in ["http://use14.playlist.ttvnw.net/a", "https://evilttvnw.net/a", "https://x.ttvnw.net.evil/a", "https://127.0.0.1/a", "https://[::1]/a", "https://user@x.ttvnw.net/a", "https://x.ttvnw.net:443/a", "https://-x.ttvnw.net/a", "https://x-.ttvnw.net/a", "https://x..ttvnw.net/a", "https://x.ttvnw.net./a", "https://x.ttvnw.net/a#fragment", "https://x.ttvnw.net/a" + Chr(92) + "b", "https://x.ttvnw.net/a b", "https://x.ttvnw.net/" + Chr(9), "https://x.ttvnw.net/" + Chr(233)]
        descriptorAssert(rokuDemuxCdnOrigin(bad) = invalid, "unsafe source URL refused")
    end for
    descriptorAssert(rokuDemuxCdnOrigin("https://USE14.Playlist.TTVNW.NET/path?token=a%2B") = "https://use14.playlist.ttvnw.net", "only origin hostname canonicalized")
    descriptorAssert(rokuDemuxCdnOrigin("https://x.ttvnw.net/" + string(8192, "a")) = invalid, "source URL bound")
    for each badRef in ["https://evil.invalid/segment", "http://x.ttvnw.net/segment", "//evil.invalid/segment", "https://user@x.ttvnw.net/segment", "seg.m4s#fragment", "seg.m4s" + Chr(92) + "x"]
        changed = relative.Replace("seg.m4s?token=a%2B%2526", badRef)
        descriptorAssert(rokuDemuxMediaOrigins(changed, base) = invalid, "unsafe actual fragment cannot enter origin allowlist")
    end for
    longMetadata = "#EXT-X-DATERANGE:ID=" + Chr(34) + "canned-ad" + Chr(34) + ",X-URL=" + Chr(34) + "https://untrusted.invalid/information" + Chr(34) + ",X-DATA=" + Chr(34) + string(19000, "x") + Chr(34) + Chr(10)
    origins = rokuDemuxMediaOrigins(descriptorPlaylist(longMetadata), base)
    descriptorAssert(origins <> invalid and origins.Count() = 2, "19KiB informational ad metadata not approved as media")
    descriptorAssert(rokuDemuxMediaOrigins(descriptorPlaylist("#EXT-X-DATERANGE:" + string(32769, "x") + Chr(10)), base) = invalid, "DATERANGE line bound")
    descriptorAssert(rokuDemuxMediaOrigins(descriptorPlaylist("#UNKNOWN:" + string(8193, "x") + Chr(10)), base) = invalid, "ordinary line bound")
    descriptorAssert(rokuDemuxMediaOrigins("#EXTM3U" + Chr(10) + string(262144, "x"), base) = invalid, "aggregate playlist bound")
    descriptorAssert(rokuDemuxMediaOrigins("#EXTM3U" + Chr(10) + string(1024, Chr(10)), base) = invalid, "line count bound")
    descriptorAssert(rokuDemuxMediaOrigins(relative.Replace("URI=", "URI=" + Chr(34) + "other.mp4" + Chr(34) + ",URI="), base) = invalid, "duplicate MAP URI refused")
    descriptorAssert(rokuDemuxMediaOrigins(relative.Replace("../init.mp4?sig=a%2Fb", "https://untrusted.invalid/init.mp4"), base) = invalid, "MAP origin requires approved CDN")
    descriptorAssert(rokuDemuxMediaOrigins(relative.Replace("#EXTINF:2,", "#EXT-X-PART:URI=" + Chr(34) + "part.m4s" + Chr(34)), base) = invalid, "part cannot replace full segment")
    many = "#EXTM3U" + Chr(10) + "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34) + Chr(10)
    for i = 1 to 15
        many += "#EXTINF:2," + Chr(10) + "https://cdn" + i.ToStr() + ".ttvnw.net/s.m4s" + Chr(10)
    end for
    descriptorAssert(rokuDemuxMediaOrigins(many, base).Count() = 16, "exact origin limit accepted")
    many += "#EXTINF:2," + Chr(10) + "https://extra.ttvnw.net/s.m4s" + Chr(10)
    descriptorAssert(rokuDemuxMediaOrigins(many, base) = invalid, "seventeenth origin refused")
    variants = parsePlaybackHlsMaster("#EXTM3U" + Chr(10) + descriptorVariant("muxed", "3322199", "1280x720", base), base).variants
    sample = variants[0]
    value = rokuDemuxPlaybackDescriptor(sample, "720p60", ["https://use14.playlist.ttvnw.net"])
    descriptorAssert(rokuDemuxDescriptorValid(value) and value["sourceUrl"] = base, "complete signed source retained exactly")
    for each key in ["videoCodec", "audioCodec", "frameRate", "bandwidth", "width", "height", "isHD"]
        changed = ParseJSON(FormatJSON(value))
        metadata = changed["metadata"]
        metadata[key] = invalid
        changed["metadata"] = metadata
        descriptorAssert(not rokuDemuxDescriptorValid(changed), "typed metadata refuses invalid primitive")
    end for
    changed = ParseJSON(FormatJSON(value))
    changed["oauth"] = "OAUTH_NEVER_EXPORT"
    descriptorAssert(not rokuDemuxDescriptorValid(changed), "extra credential key refused")
    for each field in ["version", "sourceUrl", "qualityId", "approvedOrigins", "metadata"]
        changed = ParseJSON(FormatJSON(value))
        changed[field] = invalid
        descriptorAssert(not rokuDemuxDescriptorValid(changed), "missing typed top-level field refused")
    end for
    for each bad in [1.0, "1", true, 0, 2]
        changed = ParseJSON(FormatJSON(value))
        changed["version"] = bad
        descriptorAssert(not rokuDemuxDescriptorValid(changed), "version is exact supported integer")
    end for
    changed = ParseJSON(FormatJSON(value))
    changed["approvedOrigins"] = ["https://use14.playlist.ttvnw.net", "https://use14.playlist.ttvnw.net"]
    descriptorAssert(not rokuDemuxDescriptorValid(changed), "duplicate exact origins refused")
    changed["approvedOrigins"] = ["https://different.ttvnw.net"]
    descriptorAssert(not rokuDemuxDescriptorValid(changed), "source origin must be present")
    changed = ParseJSON(FormatJSON(value))
    metadata = changed["metadata"]
    metadata["width"] = 1280.0
    changed["metadata"] = metadata
    descriptorAssert(not rokuDemuxDescriptorValid(changed), "float dimensions cannot replace integer metadata")
    descriptorAssert(rokuDemuxPlaybackDescriptor(sample, "Automatic", value["approvedOrigins"]) = invalid, "Automatic cannot claim a fixed identity")
    descriptorAssert(rokuDemuxPlaybackDescriptor(sample, "720p60", ["https://use14.playlist.ttvnw.net/"]) = invalid, "origin path cannot be approved")
end sub

sub main()
    m.assertions = 0
    m.failures = 0
    m.cases = 0
    screen = CreateObject("roSGScreen")
    host = screen.CreateScene("DescriptorHost")
    screen.Show()
    descriptorHelperCases()
    preferredQualityCases()
    top = "https://use14.playlist.ttvnw.net/canned/top.m3u8?token=source%2B&sig=signature%2526"
    mid = "https://use14.playlist.ttvnw.net/canned/mid.m3u8?token=source%2B&sig=signature%2526"
    low = "https://use14.playlist.ttvnw.net/canned/low.m3u8?token=source%2B&sig=signature%2526"
    ladder = "#EXTM3U" + Chr(10) + descriptorVariant("muxed-top", "8042999", "1920x1080", top) + descriptorVariant("muxed-mid", "3322199", "1280x720", mid) + descriptorVariant("muxed-low", "1327200", "852x480", low, "avc1.4D401F,mp4a.40.2", "30.000")
    bodies = {}
    bodies[top] = descriptorPlaylist()
    bodies[mid] = descriptorPlaylist()
    bodies[low] = descriptorPlaylist()
    descriptorRun(host, ladder, bodies, false)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.isTransmux and host.response.url = top and host.metadata.Count() = 4, "default off retains combined legacy highest Automatic")
    descriptorRun(host, ladder, bodies, true)
    descriptorLocal(host, "720p60", mid)
    descriptorAssert(host.response.QualityID = "Automatic" and host.metadata[1].QualityID = "1080p60" and host.metadata[2].QualityID = "720p60" and host.metadata[3].QualityID = "480p", "Automatic lowers fixed selection without removing/reordering manual choices")
    descriptorAssert(host.response.localPlaybackDescriptor["metadata"]["videoCodec"] = "avc1.4D401F" and host.response.localPlaybackDescriptor["metadata"]["frameRate"] = "60.000", "master hints remain separate from actual init gate")
    descriptorAssert(host.fixtureProbes = 3 and host.fixtureApprovals = 3, "existing once-per-variant approval and probe IO only")
    descriptorAssert(host.fixtureUsher.method = "GET" and host.fixtureUsher.timeout = 15000 and host.fixtureUsher.retries = 2 and host.fixtureUsher.headers.Count() = 5, "Usher HTTP contract untouched")
    descriptorAssert(host.fixtureUsher.headers["Client-ID"] = "kimne78kx3ncx6brgo4mv6wki5h1ko" and host.fixtureUsher.headers["User-Agent"] = "Stitch Roku" and host.fixtureUsher.headers.Origin = "https://android.tv.twitch.tv" and host.fixtureUsher.headers.Referer = "https://android.tv.twitch.tv/" and host.fixtureUsher.headers.Accept = "*/*", "exact existing playback headers retained")
    descriptorAssert(host.fixtureUsher.url.InStr("canned-playback-token/+?=&".EncodeUriComponent()) >= 0 and host.fixtureUsher.url.InStr("&sig=canned-playback-signature") >= 0 and host.fixtureUsher.url.InStr("&supported_codecs=h264%2Ch265") >= 0, "existing encoded token signature and codec request retained")
    descriptorAssert(host.fixtureQuery.variables.login = "canned" and host.fixtureQuery.variables["playerType"] = "roku" and host.fixtureQuery.variables.platform = "web_tv" and not host.fixtureQuery.variables["skipPlayToken"], "existing anonymous-capable LIVE SDK query retained")
    descriptorAssert(host.fixtureProbeOptions.method = "GET" and host.fixtureProbeOptions.timeout > 0 and host.fixtureProbeOptions.timeout <= 3000 and host.fixtureProbeOptions.retries = 1 and host.fixtureProbeOptions.headers.Count() = 5, "existing bounded probe contract retained")
    descriptorRun(host, ladder, bodies, true, "", "highest")
    descriptorLocal(host, "1080p60", top)
    descriptorAssert(host.response.QualityID = "1080p60", "highest preference retained")
    descriptorRun(host, ladder, bodies, true, "", "lowest")
    descriptorLocal(host, "480p", low)
    descriptorAssert(host.response.QualityID = "480p", "lowest preference retained")
    for each choice in [
        { preference: "1080p", expected: "1080p60", url: top },
        { preference: "720p", expected: "720p60", url: mid },
        { preference: "480p", expected: "480p", url: low },
        { preference: "360p", expected: "480p", url: low },
        { preference: "1440p", expected: "1080p60", url: top },
        { preference: "unknown", expected: "Automatic", url: mid }
    ]
        descriptorRun(host, ladder, bodies, true, "", choice.preference)
        underlying = choice.expected
        if underlying = "Automatic" then underlying = "720p60"
        descriptorLocal(host, underlying, choice.url)
        descriptorAssert(host.response.QualityID = choice.expected and host.metadata.Count() = 4, "preferred resolution selects a complete existing contract without removing choices")
    end for
    descriptorRun(host, "#EXTM3U" + Chr(10) + descriptorVariant("muxed-top", "8042999", "1920x1080", top), bodies, true)
    descriptorLocal(host, "1080p60", top)
    descriptorAssert(host.response.QualityID = "Automatic" and host.metadata.Count() = 2, "no lower offered quality uses actual best eligible")
    descriptorRun(host, ladder, bodies, true, "http://service.invalid:8080", "auto")
    descriptorLegacy(host, "python")
    descriptorAssert(host.response.isProxied and not host.response.isTransmux and host.response.url.InStr("/m3u8/selected?u=") > 0, "explicit Python priority and adaptive selected-master route retained")
    descriptorRun(host, ladder, bodies, true, "", "auto", "VOD")
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.contentType = "VOD" and not host.response.live and host.fixtureQuery.variables["videoId"] = "canned-id", "VOD query/playback unchanged")
    nativeBodies = {}
    nativeBodies.Append(bodies)
    nativeBodies[mid] = "#EXTM3U" + Chr(10) + "#EXTINF:2," + Chr(10) + "segment.ts" + Chr(10)
    descriptorRun(host, ladder, nativeBodies, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.QualityID = "Automatic" and host.response.url = mid and not host.response.isTransmux, "mixed ladder Automatic retains direct native preference")
    descriptorAssert(host.metadata.Count() = 4, "mixed ladder retains every eligible manual quality")
    if host.metadata.Count() = 4
        descriptorAssert(host.metadata[1].QualityID = "1080p60" and host.metadata[2].QualityID = "720p60" and host.metadata[3].QualityID = "480p", "mixed ladder retains ordered eligible manual qualities")
        descriptorAssert(host.metadata[2].playbackTransport = "direct" and host.metadata[2].localPlaybackDescriptor = invalid and host.metadata[2].url = mid, "mixed ladder native manual entry stays direct")
    end if
    descriptorManualLocal(host, 1, "1080p60", top)
    descriptorManualLocal(host, 3, "480p", low)
    descriptorRun(host, ladder, nativeBodies, false)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = mid and host.metadata.Count() = 2 and not host.response.isTransmux, "mixed default-off ladder retains only native choices")
    descriptorRun(host, ladder, nativeBodies, true, "", "auto", "VOD")
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = mid and host.metadata.Count() = 2 and not host.response.live, "mixed VOD ladder does not gain local manual choices")
    descriptorRun(host, ladder, nativeBodies, true, "", "highest")
    descriptorLocal(host, "1080p60", top)
    descriptorAssert(host.response.QualityID = "1080p60" and host.metadata[0].url = mid and host.metadata[0].playbackTransport = "direct", "mixed highest preference keeps native Automatic and explicit local source")
    descriptorRun(host, ladder, nativeBodies, true, "", "lowest")
    descriptorLocal(host, "480p", low)
    descriptorAssert(host.response.QualityID = "480p" and host.metadata[0].url = mid and host.metadata[0].playbackTransport = "direct", "mixed lowest preference keeps native Automatic and exact local source")
    twoNativeBodies = {}
    twoNativeBodies.Append(nativeBodies)
    twoNativeBodies[low] = nativeBodies[mid]
    reordered = "#EXTM3U" + Chr(10) + descriptorVariant("native-low", "1327200", "852x480", low, "avc1.4D401F,mp4a.40.2", "30.000") + descriptorVariant("muxed-top", "8042999", "1920x1080", top) + descriptorVariant("native-mid", "3322199", "1280x720", mid)
    descriptorRun(host, reordered, twoNativeBodies, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = mid and not host.response.isTransmux and host.metadata.Count() = 4, "mixed Automatic uses highest native quality after independent native sorting")
    descriptorManualLocal(host, 1, "1080p60", top)
    descriptorRun(host, ladder, nativeBodies, true, "http://service.invalid:8080")
    descriptorLegacy(host, "python")
    descriptorAssert(host.response.isProxied and not host.response.isTransmux and host.response.url.InStr("/m3u8/selected?u=") > 0 and host.metadata.Count() = 4, "mixed explicit service retains adaptive selected master and manual ladder")
    descriptorAssert(host.metadata[1].playbackTransport = "python" and host.metadata[1].localPlaybackDescriptor = invalid and host.metadata[1].isProxied and not host.metadata[1].ForwardQueryStringParams, "mixed service manual entry retains proxy contract")
    descriptorAssert(host.metadata[2].playbackTransport = "direct" and not host.metadata[2].isProxied, "mixed service native manual entry remains direct")
    nativeMid = descriptorVariant("native-mid", "3322199", "1280x720", mid)
    for each ineligible in [descriptorVariant("muxed-hevc", "8042999", "1920x1080", top, "hvc1.1.6.L150.B0,mp4a.40.2"), descriptorVariant("muxed-aac", "8042999", "1920x1080", top, "avc1.4D401F,mp4a.40.5"), descriptorVariant("muxed-no-fps", "8042999", "1920x1080", top, "avc1.4D401F,mp4a.40.2", "")]
        descriptorRun(host, "#EXTM3U" + Chr(10) + ineligible + nativeMid, nativeBodies, true)
        descriptorLegacy(host, "direct")
        descriptorAssert(host.response.url = mid and host.metadata.Count() = 2 and not host.response.isTransmux, "mixed ineligible transport cannot add local manual quality")
    end for
    descriptorRun(host, "#EXTM3U" + Chr(10) + descriptorVariant("reject-decoder", "8042999", "1920x1080", top) + nativeMid, nativeBodies, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = mid and host.metadata.Count() = 2 and host.fixtureProbes = 1, "mixed decoder rejection precedes probe and manual eligibility")
    mixedUnsafe = {}
    mixedUnsafe.Append(nativeBodies)
    mixedUnsafe[top] = descriptorPlaylist().Replace("https://fragments.cloudfront.hls.ttvnw.net/canned/seg", "https://unsafe.invalid/canned/seg")
    descriptorRun(host, "#EXTM3U" + Chr(10) + descriptorVariant("muxed-top", "8042999", "1920x1080", top) + nativeMid, mixedUnsafe, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = mid and host.metadata.Count() = 2, "mixed unapproved media origin cannot add local manual quality")
    mixedUnknown = {}
    mixedUnknown[mid] = nativeBodies[mid]
    descriptorRun(host, "#EXTM3U" + Chr(10) + descriptorVariant("muxed-top", "8042999", "1920x1080", top) + nativeMid, mixedUnknown, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = mid and host.metadata.Count() = 2, "mixed failed transport probe cannot add local manual quality")
    hevc = "#EXTM3U" + Chr(10) + descriptorVariant("muxed-hevc", "8042999", "1920x1080", top, "hvc1.1.6.L150.B0,mp4a.40.2")
    descriptorRun(host, hevc, bodies, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.isTransmux, "HEVC remains legacy source fact without local eligibility claim")
    descriptorRun(host, hevc + descriptorVariant("muxed-low", "1327200", "852x480", low), bodies, true)
    descriptorLocal(host, "480p60", low)
    descriptorAssert(host.metadata.Count() = 3, "ineligible HEVC manual choice retained in all-combined ladder")
    descriptorRun(host, hevc + descriptorVariant("muxed-low", "1327200", "852x480", low), bodies, true, "", "1080p")
    descriptorLocal(host, "480p60", low)
    descriptorAssert(host.response.QualityID = "480p60" and host.metadata.Count() = 3, "preferred resolution falls back past a decoder-supported entry without usable transport")
    rejected = ladder.Replace("muxed-top", "reject-decoder")
    descriptorRun(host, rejected, bodies, true)
    descriptorLocal(host, "720p60", mid)
    descriptorAssert(host.metadata.Count() = 3 and host.fixtureProbes = 2, "decoder rejection stays before probe and descriptor")
    descriptorRun(host, rejected, bodies, true, "", "1080p")
    descriptorLocal(host, "720p60", mid)
    descriptorAssert(host.response.QualityID = "720p60" and host.metadata.Count() = 3, "preferred resolution never restores a decoder-rejected higher rendition")
    grouped = "#EXTM3U" + Chr(10) + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + Chr(34) + "audio" + Chr(34) + ",NAME=Audio,URI=" + Chr(34) + "audio.m3u8" + Chr(34) + Chr(10) + descriptorVariant("grouped", "3322199", "1280x720", mid, "avc1.4D401F,mp4a.40.2", "60.000", "AUDIO=" + Chr(34) + "audio" + Chr(34))
    descriptorRun(host, grouped, bodies, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = host.fixtureUsher.url and host.fixtureProbes = 0 and host.metadata.Count() = 1, "separate audio retains complete direct master")
    descriptorRun(host, grouped + nativeMid, nativeBodies, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.url = host.fixtureUsher.url and host.metadata.Count() = 2 and host.fixtureProbes = 1, "mixed external audio retains native master without local descriptor")
    descriptorAssert(host.metadata[1].playbackTransport = "direct" and host.metadata[1].localPlaybackDescriptor = invalid, "mixed external audio cannot add a local manual choice")
    descriptorRun(host, "#EXTM3U" + Chr(10) + descriptorVariant("muxed", "3322199", "1280x720", mid, "avc1.4D401F,mp4a.40.5"), bodies, true)
    descriptorLegacy(host, "direct")
    descriptorRun(host, "#EXTM3U" + Chr(10) + descriptorVariant("muxed", "3322199", "1280x720", mid, "avc1.4D401F,mp4a.40.2", ""), bodies, true)
    descriptorLegacy(host, "direct")
    unsafe = {}
    unsafe[mid] = descriptorPlaylist().Replace("https://fragments.cloudfront.hls.ttvnw.net/canned/seg", "https://unsafe.invalid/canned/seg")
    one = "#EXTM3U" + Chr(10) + descriptorVariant("muxed", "3322199", "1280x720", mid)
    descriptorRun(host, one, unsafe, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.fixtureProbes = 1, "origin capture performs no fragment request")
    unknown = {}
    descriptorRun(host, one, unknown, true)
    descriptorAssert(host.response.contentType = "ERROR" and host.response.title = "Video transport unavailable", "existing failed probe error remains")
    marker = "#EXTM3U" + Chr(10) + "#EXT-X-TWITCH-INFO:TRANSCODESTACK=" + Chr(34) + "transmux" + Chr(34) + Chr(10) + descriptorVariant("muxed", "3322199", "1280x720", mid)
    descriptorRun(host, marker, unknown, true)
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.isTransmux, "manifest hint cannot create origins from failed probe")
    clipRequest = { contentType: "CLIP", contentId: "canned-clip", clipSlug: "canned-clip", playbackTransport: "roku-demux", localPlaybackDescriptor: { stale: true } }
    host.callFunc("loadClipContent", clipRequest)
    m.cases++
    descriptorLegacy(host, "direct")
    descriptorAssert(host.response.streamFormat = "mp4" and host.response.QualityID = "Original", "clip remains signed direct playback")
    descriptorAssert(host.fixtureFailures = 0, "no unexpected Task exception")
    if "__NEGATIVE_CONTROL__" = "yes" then descriptorAssert(false, "deliberate negative control")
    screen.Close()
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions, "; m.cases; " cases"
end sub

sub preferredQualityCases()
    metadata = [{ QualityID: "Automatic" }, { QualityID: "720p60" }, { QualityID: "1080p HEVC" }, { QualityID: "1080p60 (Source)" }, { QualityID: "480p" }, { QualityID: "360p" }]
    descriptorAssert(playbackPreferredQualityIndex(metadata, "1080p") = 2, "preferred resolution outranks bitrate order and retains the first equal-height entry")
    descriptorAssert(playbackPreferredQualityIndex(metadata, "1440p") = 2 and playbackPreferredQualityIndex(metadata, "2160p") = 2, "unavailable higher preference selects nearest lower resolution")
    descriptorAssert(playbackPreferredQualityIndex(metadata, "720p") = 1 and playbackPreferredQualityIndex(metadata, "480p") = 4, "exact lower resolution preferences select their own rendition")
    descriptorAssert(playbackPreferredQualityIndex(metadata, "160p") = 5, "only higher offers use the lowest concrete resolution")
    descriptorAssert(playbackPreferredQualityIndex(metadata, "auto") = 0 and playbackPreferredQualityIndex(metadata, "invalid") = 0 and playbackPreferredQualityIndex(metadata, invalid) = 0, "automatic unknown and missing preferences retain Automatic")
    descriptorAssert(playbackPreferredQualityIndex(metadata, "highest") = 1 and playbackPreferredQualityIndex(metadata, "lowest") = 5, "existing highest and lowest preferences are unchanged")
    descriptorAssert(playbackPreferredQualityIndex([{ QualityID: "Automatic" }], "1080p") = 0, "master-only external audio stays on the complete master")
    serviceOnly = { QualityID: "1080p60 HEVC", isTransmux: true, isProxied: false, playbackTransport: "direct", localPlaybackDescriptor: invalid }
    descriptorAssert(playbackPreferredQualityIndex([{ QualityID: "Automatic" }, serviceOnly], "1080p") = 0, "unavailable transports retain the existing Automatic fallback")
    serviceOnly.isProxied = true
    serviceOnly.playbackTransport = "python"
    descriptorAssert(playbackPreferredQualityIndex([{ QualityID: "Automatic" }, serviceOnly], "1080p") = 1, "a configured service remains eligible for the preferred resolution")
    descriptorAssert(playbackPreferredQualityIndex([{ QualityID: "Automatic" }, { QualityID: "1080invalid" }, { QualityID: "720p60" }], "1080p") = 2, "malformed labels do not win a resolution preference")
end sub
