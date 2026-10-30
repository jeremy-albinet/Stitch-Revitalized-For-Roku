' Real Session handlers execute; the Task/Video boundary has no native IO.
sub runTests()
    m.assertions = 0
    m.failures = 0
    m.snapshot = invalid
    for each version in [1, 1&, 2, 0, "1", 1.0, invalid]
        manager = CreateObject("roSGNode", "RokuDemuxSession")
        m.top.appendChild(manager)
        descriptor = adSessionDescriptor()
        descriptor["version"] = version
        kind = type(version, 3)
        valid = (kind = "Integer" or kind = "LongInteger") and version = 1
        if valid
            id = manager.callFunc("startSession", descriptor)
            check(id.Len() = 32, "real public LIVE descriptor accepted")
        else
            check(manager.callFunc("startSession", descriptor) = "", "future or malformed public descriptor refused")
            check(manager.callFunc("adFixtureRead").worker = invalid and not manager.busy, "refusal cannot create worker")
            if rokuDemuxInteger(version) and version = 2
                manager.callFunc("onDestroy")
                m.top.removeChild(manager)
                continue for
            end if
            ' Exercise only the internal option selector on the hypothetical
            ' future descriptor: this is not a public playback authorization.
            id = "0123456789abcdef0123456789abcdef"
            manager.callFunc("adFixtureBegin", id, descriptor)
        end if
        state = manager.callFunc("adFixtureRead")
        worker = state.worker
        check(worker <> invalid and worker.state = "run" and manager.busy, "real worker run dispatch")
        check((type(worker.enableAdMetadata) = "Boolean" or type(worker.enableAdMetadata) = "roBoolean"), "XML option is strictly Boolean")
        expected = valid
        check(worker.enableAdMetadata = expected, "observational ad option only LIVE v1")
        check(worker.experimentalMode and worker.cacheBudgetBytes = 25165824 and worker.listenPort = 0, "consent and existing resource options unchanged")
        if expected
            m.snapshot = {version:worker.inputDescriptor["version"],enableAdMetadata:worker.enableAdMetadata,
                experimentalMode:worker.experimentalMode,cacheBudgetBytes:worker.cacheBudgetBytes,listenPort:worker.listenPort}
        end if
        manager.callFunc("stopSession", id)
        check(worker.stopRequested and worker.control = "run" and manager.busy, "cooperative stop retains active worker")
        worker.result = adSessionCleanup(id)
        check(manager.busy and manager.callFunc("adFixtureRead").worker.isSameNode(worker), "closed response alone does not release running worker")
        worker.state = "stop"
        check(not manager.busy and manager.callFunc("adFixtureRead").worker = invalid and worker.control = "stop", "actual stopped worker acknowledgment releases through factory")
        manager.callFunc("onDestroy")
        m.top.removeChild(manager)
    end for
    manager = CreateObject("roSGNode", "RokuDemuxSession")
    m.top.appendChild(manager)
    descriptor = adSessionVodDescriptor()
    check(rokuVodDescriptorValid(descriptor), "separate complete v2 VOD descriptor validates")
    id = manager.callFunc("startSession", descriptor)
    worker = manager.callFunc("adFixtureRead").worker
    check(id.Len() = 32 and worker <> invalid and worker.subtype() = "RokuVodDemuxServer", "valid VOD chooses its separate worker")
    check(not worker.hasField("enableAdMetadata"), "VOD has no LIVE ad field or assignment")
    check(worker.experimentalMode and worker.cacheBudgetBytes = 25165824 and worker.listenPort = 0, "VOD retains consent and24MiB profile")
    manager.callFunc("stopSession", id)
    check(worker.stopRequested and worker.control = "run" and manager.busy, "VOD retains cooperative stop owner")
    worker.result = adSessionCleanup(id)
    check(manager.busy, "VOD cleanup acknowledgment still waits for actual worker stop")
    worker.state = "stop"
    check(not manager.busy and manager.callFunc("adFixtureRead").worker = invalid, "VOD actual stopped worker safely releases")
    manager.callFunc("onDestroy")
    m.top.removeChild(manager)
    check(m.snapshot <> invalid, "actual valid worker snapshot captured")
    m.top.result = {assertions:m.assertions,failures:m.failures,snapshot:m.snapshot}
end sub

function adSessionDescriptor() as object
    return {"version":1,"sourceUrl":"https://fixture.ttvnw.net/current.m3u8","qualityId":"720p60","approvedOrigins":["https://fixture.ttvnw.net"],
        "metadata":{"videoCodec":"avc1.4D4020","audioCodec":"mp4a.40.2","width":1280,"height":720,"frameRate":"60.000","bandwidth":3322199,"isHD":true}}
end function

function adSessionCleanup(id as string) as object
    return {sessionId:id,cleanupOk:true,listenerClosed:true,connectionClosed:true,helperClosed:true,cacheReferencesReleased:true}
end function

function adSessionVodDescriptor() as object
    metadata = adSessionDescriptor()["metadata"]
    return { "version": 2, "mode": "vod", "vodId": "123456789", "usherUrl": "https://usher.ttvnw.net/vod/v2/123456789.m3u8?nauth=fixture", "sourceUrl": "https://d123.cloudfront.net/vod/720.m3u8?fixture=exact", "qualityId": "720p60", "approvedOrigin": "https://d123.cloudfront.net", "metadata": metadata }
end function

sub check(ok as boolean, reason as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "AD_LIVE_FAIL: __MARKER__ " + reason
    end if
end sub
