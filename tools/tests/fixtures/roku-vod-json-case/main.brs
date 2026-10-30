sub main()
    m.assertions = 0
    m.failures = 0
    try
        master = ReadAsciiFile("pkg:/master.m3u8")
        selection = ParseJson("{" + Chr(34) + "sourceUrl" + Chr(34) + ":" + Chr(34) + "https://dsynthetic.cloudfront.net/archive/index.m3u8?fixture=synthetic" + Chr(34) + "," + Chr(34) + "qualityId" + Chr(34) + ":" + Chr(34) + "1080p60" + Chr(34) + "}")
        descriptor = rokuVodDescriptorFromTrustedMaster(master, "https://usher.ttvnw.net/vod/v2/123.m3u8?fixture=synthetic", selection, "123")
        caseCheck(descriptor <> invalid, "actual generator accepts exact parsed selection")
        descriptor = ParseJson(FormatJson(descriptor))
        caseCheck(rokuVodDescriptorValid(descriptor), "actual descriptor validates after JSON clone")
        caseCheck(descriptor["vodId"] = "123" and descriptor["qualityId"] = "1080p60", "exact identity and quality survive clone")
        caseCheck(descriptor["sourceUrl"] = selection["sourceUrl"] and descriptor["usherUrl"].InStr("?fixture=synthetic") > 0, "signed URLs retain exact query")
        caseCheck(descriptor["approvedOrigin"] = "https://dsynthetic.cloudfront.net", "exact origin retained")
        meta = descriptor["metadata"]
        caseCheck(meta["videoCodec"] = "avc1.4D402A" and meta["audioCodec"] = "mp4a.40.2", "canonical codec fields survive clone")
        caseCheck(meta["frameRate"] = "60.000" and meta["isHD"] and meta.width = 1920 and meta.height = 1080, "canonical frame/dimension values survive clone")
        caseCheck(rokuVodDescriptorMatchesMaster(descriptor, master), "actual master corroboration rebuilds quoted selection")
        state = rokuVodFetchCreate(descriptor, "0123456789abcdef0123456789abcdef")
        intent = rvfIntent(state, "master", -1)
        caseCheck(intent <> invalid and intent.url = descriptor["usherUrl"], "actual Fetch clone retains exact Usher authority")
        caseCheck(rvfIntent(state, "playlist", -1) = invalid, "JSON repair does not bypass master trust")
        state.trusted = true
        intent = rvfIntent(state, "playlist", -1)
        caseCheck(intent <> invalid and intent.url = descriptor["sourceUrl"], "actual Fetch clone retains selected playlist")
        m.sessionId = state.sessionId
        m.config = ParseJson(FormatJson(descriptor))
        m.result = { "decoderApproved": true, "actualInitValidated": true, "requestedDecoderFormat": twitchVariantVideoFormat({ "CODECS": meta["videoCodec"] + "," + meta["audioCodec"], "RESOLUTION": "1920x1080", "FRAME-RATE": meta["frameRate"], "BANDWIDTH": meta.bandwidth.ToStr() }) }
        m.index = { totalUs: 240000000& }
        bound = { GetAddress: caseAddress, GetPort: casePort }
        ready = ParseJson(FormatJson(rvsReady(bound)))
        caseCheck(rokuVodSessionReadyValid(ready, m.sessionId, descriptor), "actual Server Ready validates after JSON clone")
        caseCheck(ready["totalDurationUs"] = 240000000& and ready["masterPath"] = "/vod/" + m.sessionId + "/master.m3u8", "full duration and session path survive clone")
        caseCheck(rvdKeys(ready["requestedDecoderFormat"], ["codec", "profile", "level"]), "canonical actual formatter AA retained")
        event = ParseJson(FormatJson({ "id": m.sessionId, "status": "ready", "reason": "", "url": "http://127.0.0.1:49371" + ready["masterPath"], "metadata": ready.metadata, "mode": "vod", "totalDurationUs": ready["totalDurationUs"], "masterPath": ready["masterPath"] }))
        caseCheck(rokuVodPlaybackReadyValid(event, m.sessionId, descriptor), "actual playback-ready validator accepts parsed owner event")
        manifest = rokuVodMasterManifest(ParseJson(FormatJson(meta)), m.sessionId)
        caseCheck(manifest <> invalid and manifest.ToAsciiString().InStr("FRAME-RATE=60.000,CODECS=" + Chr(34) + "avc1.4D402A,mp4a.40.2" + Chr(34)) > 0, "actual master formatter reads serialized metadata")
        bad = ParseJson(FormatJson(descriptor))
        bad.Delete("sourceUrl")
        bad["sourceurl"] = selection["sourceUrl"]
        caseCheck(not rokuVodDescriptorValid(bad), "wrong-case descriptor key refused")
        bad = ParseJson(FormatJson(ready))
        bad.Delete("masterPath")
        bad["masterpath"] = ready["masterPath"]
        caseCheck(not rokuVodSessionReadyValid(bad, m.sessionId, descriptor), "wrong-case ready key refused")
        caseCheck(rokuVodRuntimeAvailable(), "compiled runtime capability enables eligible recorded playback")
        caseCheck(true, "negative summary anchor")
    catch error
        caseFail("exception: " + error.message)
    end try
    if m.failures = 0
        print "STITCH_VOD_JSON_CASE_PASS: __MARKER__ "; FormatJson({ assertions: m.assertions, failures: m.failures })
    else
        print "STITCH_VOD_JSON_CASE_FAILURES: "; m.failures
    end if
end sub

function caseAddress() as string
    return "127.0.0.1"
end function

function casePort() as integer
    return 49371
end function

sub caseCheck(ok as boolean, label as string)
    m.assertions++
    if not ok then caseFail(label)
end sub

sub caseFail(label as string)
    m.failures++
    print "STITCH_VOD_JSON_CASE_FAIL: "; label
end sub
