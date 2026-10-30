sub main()
    m.assertions = 0
    m.failures = 0
    m.cases = 0
    screen = CreateObject("roSGScreen")
    host = screen.CreateScene("SelectionHost")
    screen.Show()
    host.contentRequested = { contentType: "LIVE", streamerLogin: "fixture", contentId: "fixture", streamerId: "fixture" }
    proxy = "http://service.invalid:8080"
    mixed = "#EXTM3U" + Chr(10)
    mixed += selectionVariant("reject-decoder", "9000000", "1920x1080", "https://old.invalid/rejected.m3u8")
    mixed += selectionVariant("muxed", "8042999", "1920x1080", "https://old.invalid/muxed.m3u8?token=fixture&sig=old")
    mixed += selectionVariant("native", "3322199", "1280x720", "https://old.invalid/native.m3u8?token=fixture&sig=old")
    mixed += selectionVariant("unknown-transport", "216299", "284x160", "https://old.invalid/unknown-transport.m3u8")
    mixed += "#EXT-X-STREAM-INF:BANDWIDTH=100000,CODECS=" + Chr(34) + "mp4a.40.2" + Chr(34) + Chr(10) + "https://old.invalid/audio-only.m3u8" + Chr(10)
    runSelectionCase(host, mixed, proxy, "auto")
    checkSelection(host.response <> invalid and host.response.QualityID = "Automatic", "actual Automatic preference selects adaptive metadata")
    checkSelection(host.metadata.Count() = 3, "only two approved video qualities plus Automatic are published")
    selections = selectedRequest(host.response.url, host.fixtureUsherUrl)
    checkSelection(selections.Count() = 2, "descriptors track approved URLs only")
    if selections.Count() = 2
        checkSelection(selections[0].attributes["VIDEO"] = "muxed" and selections[1].attributes["VIDEO"] = "native", "decoder rejection, unknown transport and audio-only never enter selected ladder")
        checkSelection(selections[0].attributes["CODECS"] = "avc1.4D401F,mp4a.40.2", "actual task carries complete original codec declaration")
    end if
    checkSelection(host.response.isProxied and not host.response.isTransmux and not host.response.ForwardQueryStringParams, "actual Automatic retains transport flags")
    checkSelection(host.metadata[1].url.InStr("/m3u8?u=") > 0 and host.metadata[1].url.InStr("&codecs=") > 0, "direct bundled manual demux route and codec hints stay unchanged")
    checkSelection(host.metadata[2].url = "https://old.invalid/native.m3u8?token=fixture&sig=old" and not host.metadata[2].isProxied, "native manual child bypass is unchanged")
    checkSelection(host.fixtureProbes = 3, "actual transport approval runs existing bounded probes before descriptors")
    runSelectionCase(host, mixed, proxy, "highest")
    checkSelection(host.response.QualityID = "1080p60" and host.response.url = host.metadata[1].url, "highest preference still selects manual metadata index1")
    runSelectionCase(host, mixed, proxy, "lowest")
    checkSelection(host.response.QualityID = "720p60" and host.response.url = host.metadata[2].url, "lowest preference still selects native manual quality")
    runSelectionCase(host, mixed, "", "auto")
    checkSelection(host.metadata.Count() = 2 and not host.response.isProxied and host.response.ForwardQueryStringParams, "no service retains native filtered fallback")
    checkSelection(host.response.url = "https://old.invalid/native.m3u8?token=fixture&sig=old", "no-service fallback selects the compatible native child")
    native = "#EXTM3U" + Chr(10) + selectionVariant("native", "3322199", "1280x720", "https://old.invalid/native.m3u8")
    runSelectionCase(host, native, proxy, "auto")
    checkSelection(host.response.url = host.fixtureUsherUrl and not host.response.isProxied, "fully compatible native Automatic keeps upstream ABR master")
    grouped = "#EXTM3U" + Chr(10) + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + Chr(34) + "audio" + Chr(34) + ",NAME=" + Chr(34) + "English, stereo" + Chr(34) + ",URI=" + Chr(34) + Chr(34) + Chr(10)
    grouped += selectionVariant("grouped", "8042999", "1920x1080", "https://old.invalid/video.m3u8?sig=fixture", "AUDIO=" + Chr(34) + "audio" + Chr(34))
    runSelectionCase(host, grouped, proxy, "highest")
    checkSelection(host.metadata.Count() = 2 and host.fixtureProbes = 0, "external-audio transport behavior remains unchanged")
    selections = selectedRequest(host.response.url, host.fixtureUsherUrl)
    checkSelection(selections.Count() = 1 and selections[0].groups.Count() = 1, "manual external-audio selection uses one complete descriptor")
    if selections.Count() = 1 and selections[0].groups.Count() = 1
        checkSelection(selections[0].groups[0]["hasUri"] = true, "actual parser and builder retain blank original URI presence")
        checkSelection(selections[0].groups[0].attributes["NAME"] = "English, stereo", "actual parser and builder retain quoted comma group metadata")
    end if
    checkSelection(host.response.url = host.metadata[0].url and host.response.isProxied and not host.response.ForwardQueryStringParams, "one-quality external audio Automatic/manual share safe selected route")
    runSelectionCase(host, grouped, "", "auto")
    checkSelection(host.metadata.Count() = 1 and host.response.url = host.fixtureUsherUrl and not host.response.isProxied, "no-service external audio preserves native master")
    many = "#EXTM3U" + Chr(10) + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + Chr(34) + "audio" + Chr(34) + ",NAME=English,URI=" + Chr(34) + "audio.m3u8" + Chr(34) + Chr(10)
    for index = 1 to 33
        many += selectionVariant("grouped-" + index.ToStr(), (1000000 + index).ToStr(), "1280x720", "https://old.invalid/video-" + index.ToStr() + ".m3u8", "AUDIO=" + Chr(34) + "audio" + Chr(34))
    end for
    runSelectionCase(host, many, proxy, "auto")
    selections = selectedRequest(host.response.url, host.fixtureUsherUrl)
    checkSelection(selections.Count() = 32, "actual approval collector caps descriptors in lockstep with approved URL bound")
    checkSelection(host.metadata.Count() = 34, "manual metadata remains available beyond filtered master count cap")
    invalidMetadata = mixed.Replace("BANDWIDTH=3322199", "X-LONG=" + string(4097, "x") + ",BANDWIDTH=3322199")
    runSelectionCase(host, invalidMetadata, proxy, "auto")
    checkSelection(host.response.contentType = "ERROR" and host.metadata.Count() = 0, "unserializable new selection fails closed without an unsafe ladder")
    checkSelection(host.response.description.InStr("refresh") >= 0, "selection failure provides a bounded refresh instruction")
    host.fixtureLegacyProxy = true
    runSelectionCase(host, mixed, proxy, "auto")
    checkSelection(host.response.contentType = "ERROR" and host.response.errorCode = "proxy_upgrade_required", "legacy service gets an actionable upgrade result before a missing-route playback error")
    checkSelection(host.response.description.InStr("Settings") >= 0, "legacy service refusal explains the on-Roku alternative")
    runSelectionCase(host, mixed, "", "auto")
    checkSelection(host.response.contentType <> "ERROR" and not host.response.isProxied, "clearing the old service retains compatible native playback")
    host.fixtureLegacyProxy = false
    for each failure in ["timeout", "http", "json"]
        host.fixtureHealthFailure = failure
        runSelectionCase(host, mixed, proxy, "auto")
        checkSelection(host.response.contentType = "ERROR" and host.response.errorCode = "proxy_health_failed", "health failure is a connection problem rather than an upgrade: " + failure)
        checkSelection(host.metadata.Count() = 0, "failed service health never publishes a selected route: " + failure)
    end for
    checkSelection(host.fixtureFailures = 0, "no canned task case raises an unexpected exception")
    screen.Close()
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions, "; m.cases; " cases"
end sub

sub runSelectionCase(host as object, master as string, proxy as string, preference as string)
    m.cases++
    host.fixtureMaster = master
    host.fixtureProxy = proxy
    host.fixturePreference = preference
    host.fixtureProbes = 0
    host.response = invalid
    host.metadata = []
    host.callFunc("loadHlsContent", { contentType: "LIVE", streamerLogin: "fixture", contentId: "fixture", streamerId: "fixture" })
end sub

function selectionVariant(video as string, bandwidth as string, resolution as string, url as string, extra = "" as string) as string
    text = "#EXT-X-STREAM-INF:BANDWIDTH=" + bandwidth + ",RESOLUTION=" + resolution + ",FRAME-RATE=60.000,CODECS=" + Chr(34) + "avc1.4D401F,mp4a.40.2" + Chr(34) + ",VIDEO=" + Chr(34) + video + Chr(34)
    if extra <> "" then text += "," + extra
    return text + Chr(10) + url + Chr(10)
end function

function selectedRequest(url as string, expectedMaster as string) as object
    checkSelection(url.InStr("http://service.invalid:8080/m3u8/selected?u=") = 0, "actual task uses the explicit selected endpoint")
    parts = url.Split("?")[1].Split("&")
    checkSelection(parts.Count() = 2, "actual selected request excludes all legacy URL/transport fields")
    if parts.Count() <> 2 then return []
    checkSelection(parts[0].Mid(2).DecodeUriComponent() = expectedMaster, "actual request preserves the complete original Usher query")
    value = parts[1].Mid(11).DecodeUriComponent()
    checkSelection(value.InStr("old.invalid") < 0, "actual approved selection contains no rendition URLs")
    return ParseJSON(value)
end function

sub checkSelection(condition as boolean, label as string)
    m.assertions++
    if not condition
        m.failures++
        print "STITCH_SELECTION_FAIL: " + label
    end if
end sub
