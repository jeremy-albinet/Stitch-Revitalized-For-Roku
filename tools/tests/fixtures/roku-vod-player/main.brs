sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: { ChatOption: "false", ChatFontSize: "16", "playback.lowLatency": "false" }, fixtureContentTasks: 0, emoteCache: {} })
    m.scene = m.screen.createScene("RokuPlayerHost")
    m.screen.show()
    m.enabled = "__CAPABILITY__" = "enabled"
    try
        testCapabilityAndLive()
        testContentTask()
        if m.enabled
            testOwnerReady()
            testOwnerReplacement()
            testPlayer()
        else
            testDisabledPlayer()
        end if
        check(true, "negative summary anchor")
    catch error
        fail(error.message)
    end try
    fixtureEnd()
end sub

function vodDescriptor() as object
    return { version: 2, mode: "vod", vodId: "123456789", usherUrl: "https://usher.ttvnw.net/vod/v2/123456789.m3u8?nauth=fixture", sourceUrl: "https://d123.cloudfront.net/vod/720.m3u8?fixture=exact%2B", qualityId: "720p60", approvedOrigin: "https://d123.cloudfront.net", metadata: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "60.000", bandwidth: 4000000, isHD: true } }
end function

function liveDescriptor() as object
    d = vodDescriptor()
    return { version: 1, sourceUrl: "https://use14.playlist.ttvnw.net/live/selected.m3u8?fixture=exact%2B", qualityId: "1080p60", approvedOrigins: ["https://use14.playlist.ttvnw.net"], metadata: { videoCodec: "avc1.4D402A", audioCodec: "mp4a.40.2", width: 1920, height: 1080, frameRate: "60.000", bandwidth: 8000000, isHD: true } }
end function

function newManager() as object
    manager = CreateObject("roSGNode", "RokuDemuxSession")
    m.scene.appendChild(manager)
    return manager
end function

function cleanup(id as string) as object
    return { sessionId: id, cleanupOk: true, listenerClosed: true, connectionClosed: true, helperClosed: true, cacheReferencesReleased: true }
end function

sub finishManager(manager as object)
    state = manager.callFunc("fixtureRead")
    if state.worker <> invalid
        manager.callFunc("stopSession", "")
        state.worker.result = cleanup(state.id)
        state.worker.state = "stop"
        if state.video <> invalid then state.video.state = "stopped"
    end if
    manager.callFunc("onDestroy")
    m.scene.removeChild(manager)
end sub

function vodReady(id as string, descriptor as object) as object
    meta = descriptor.metadata
    format = twitchVariantVideoFormat({ CODECS: meta.videoCodec + "," + meta.audioCodec, RESOLUTION: meta.width.ToStr() + "x" + meta.height.ToStr(), "FRAME-RATE": meta.frameRate, BANDWIDTH: meta.bandwidth.ToStr() })
    return { sessionId: id, boundAddressText: "127.0.0.1", boundPort: 49371, metadata: meta, decoderApproved: true, actualInitValidated: true, requestedDecoderFormat: format, mode: "vod", totalDurationUs: 73760000000&, masterPath: "/vod/" + id + "/master.m3u8" }
end function

function nextFailure(port as object) as dynamic
    while true
        event = port.GetMessage()
        if event = invalid then return invalid
        if type(event) = "roSGNodeEvent"
            data = event.GetData()
            if type(data) = "roAssociativeArray" and data.status = "failed" then return data
        end if
    end while
end function

sub testCapabilityAndLive()
    check(rokuVodRuntimeAvailable() = m.enabled, "only explicit native capability boundary changes availability")
    manager = newManager()
    check(rokuVodDescriptorValid(vodDescriptor()), "actual v2 descriptor is valid independently of runtime availability")
    id = manager.callFunc("startSession", vodDescriptor())
    if m.enabled
        check(id <> "" and manager.callFunc("fixtureRead").worker.subtype() = "RokuVodDemuxServer", "actual owner chooses the VOD Task class")
        check(not manager.callFunc("fixtureRead").worker.hasField("enableAdMetadata"), "VOD worker does not expose or receive the LIVE ad option")
    else
        check(id = "" and not manager.busy and manager.callFunc("fixtureRead").worker = invalid, "normal capability gate refuses VOD before worker or user flow")
    end if
    finishManager(manager)
    manager = newManager()
    id = manager.callFunc("startSession", liveDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    check(id <> "" and worker.subtype() = "RokuDemuxServer", "v1 LIVE still selects the original worker")
    check(worker.hasField("enableAdMetadata") and (type(worker.enableAdMetadata) = "Boolean" or type(worker.enableAdMetadata) = "roBoolean") and worker.enableAdMetadata, "LIVE worker retains typed observational ad metadata")
    check(worker.cacheBudgetBytes = 33554432 and worker.experimentalMode, "existing HD LIVE budget and consent remain")
    worker.ready = { sessionId: id, boundPort: 49371, boundAddressText: "127.0.0.1", decoderApproved: true, actualInitValidated: true, metadata: { width: 1920, height: 1080 } }
    check(manager.event.status = "ready" and manager.event.url = "http://127.0.0.1:49371/master.m3u8", "legacy LIVE readiness stays accepted without new VOD fields")
    finishManager(manager)
end sub

sub testOwnerReady()
    manager = newManager()
    d = vodDescriptor()
    d.metadata = liveDescriptor().metadata
    d["qualityId"] = "1080p60"
    id = manager.callFunc("startSession", d)
    worker = manager.callFunc("fixtureRead").worker
    check(worker.cacheBudgetBytes = 25165824, "VOD uses its bounded24MiB profile at1080")
    changed = d
    changed["sourceUrl"] = "https://d123.cloudfront.net/vod/other.m3u8"
    check(worker.inputDescriptor.sourceUrl <> changed.sourceUrl, "pending and worker input use primitive descriptor snapshot")
    r = vodReady(id, worker.inputDescriptor)
    check(rokuVodSessionReadyValid(r, id, worker.inputDescriptor), "HD VOD ready primitive snapshot independently validates")
    worker.ready = vodReady("00000000000000000000000000000000", worker.inputDescriptor)
    check(manager.event.status = "starting" and not worker.stopRequested, "foreign ready cannot stop or publish the current VOD")
    worker.ready = r
    check(manager.event.status = "ready" and manager.event.mode = "vod", "valid actual VOD Ready is accepted")
    check(manager.event.totalDurationUs = 73760000000& and manager.event.masterPath = r.masterPath, "owner event retains full duration and immutable session path")
    check(manager.event.url = "http://127.0.0.1:49371" + r.masterPath, "VOD URL is constructed at exact127 loopback")
    check(rokuVodPlaybackReadyValid(manager.event, id, worker.inputDescriptor), "actual owner event meets player boundary")
    worker.ready = vodReady(id, worker.inputDescriptor)
    check(manager.event.status = "ready" and not worker.stopRequested, "duplicate ready does not start replacement")
    finishManager(manager)

    cases = [
        { key: "mode", value: "live" }, { key: "mode", value: {} },
        { key: "totalDurationUs", value: 0 }, { key: "totalDurationUs", value: -1 }, { key: "totalDurationUs", value: 172800000001& }, { key: "totalDurationUs", value: 1.5 },
        { key: "masterPath", value: "/master.m3u8" }, { key: "masterPath", value: "/vod/00000000000000000000000000000000/master.m3u8" },
        { key: "masterPath", value: "https://d123.cloudfront.net/foreign.m3u8" },
        { key: "boundAddressText", value: "192.0.2.1" }, { key: "boundPort", value: 49151 }, { key: "boundPort", value: "49371" },
        { key: "decoderApproved", value: false }, { key: "decoderApproved", value: "true" }, { key: "actualInitValidated", value: false },
        { key: "requestedDecoderFormat", value: "h264" }, { key: "requestedDecoderFormat", value: { codec: "hevc", profile: "main", level: "5.0" } },
        { key: "metadata", value: { width: 1280, height: 720 } }, { key: "metadata", value: invalid },
        { key: "metadata", value: liveDescriptor().metadata },
        { key: "metadata", value: { videoCodec: "hvc1.1.6.L120", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "60.000", bandwidth: 4000000, isHD: true } },
        { key: "metadata", value: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.5", width: 1280, height: 720, frameRate: "60.000", bandwidth: 4000000, isHD: true } },
        { key: "metadata", value: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "30.000", bandwidth: 4000000, isHD: true } },
        { key: "metadata", value: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "60.000", bandwidth: 6000000, isHD: true } },
        { key: "extraUrl", value: "https://fixture.invalid/must-not-escape" }
    ]
    for each item in cases
        manager = newManager()
        id = manager.callFunc("startSession", vodDescriptor())
        worker = manager.callFunc("fixtureRead").worker
        r = vodReady(id, vodDescriptor())
        if item.value = invalid
            r.Delete(item.key)
        else
            r[item.key] = item.value
        end if
        port = CreateObject("roMessagePort")
        manager.observeField("event", port)
        worker.ready = r
        failed = nextFailure(port)
        check(failed <> invalid and worker.stopRequested, "malformed current VOD Ready refuses and cooperatively stops: " + item.key)
        if failed <> invalid then check(failed.reason = "invalid_ready", "VOD readiness has one fixed refusal code")
        manager.unobserveField("event")
        finishManager(manager)
    end for
end sub

sub testOwnerReplacement()
    for each videoFirst in [false, true]
        manager = newManager()
        first = manager.callFunc("startSession", vodDescriptor())
        old = manager.callFunc("fixtureRead").worker
        video = CreateObject("roSGNode", "VodVideoBoundary")
        video.state = "playing"
        check(manager.callFunc("attachVideo", first, video), "actual VOD owner attaches Video")
        second = manager.callFunc("startSession", vodDescriptor())
        third = manager.callFunc("startSession", vodDescriptor())
        check(second <> third and manager.callFunc("fixtureRead").pending.id = third, "actual VOD pending supersession keeps only latest identity")
        check(old.stopRequested and video.control = "stop", "replacement requests both actual Task and Video stop")
        old.result = cleanup(first)
        if videoFirst
            video.state = "stopped"
        else
            old.state = "stop"
        end if
        check(manager.callFunc("fixtureRead").worker.isSameNode(old), "one STOP alone cannot replace the VOD owner")
        if videoFirst
            old.state = "stop"
        else
            video.state = "stopped"
        end if
        state = manager.callFunc("fixtureRead")
        check(state.id = third and not state.worker.isSameNode(old) and state.video = invalid, "replacement starts only after both STOP and all cleanup acknowledgments")
        check(not state.worker.stopRequested and state.worker.subtype() = "RokuVodDemuxServer", "old continuation cannot stop or select wrong new worker")
        old.ready = vodReady(first, vodDescriptor())
        old.result = cleanup(first)
        check(manager.callFunc("fixtureRead").id = third, "released old callbacks cannot mutate new VOD owner")
        finishManager(manager)
    end for
    for each key in ["cleanupOk", "listenerClosed", "connectionClosed", "helperClosed", "cacheReferencesReleased"]
        manager = newManager()
        id = manager.callFunc("startSession", vodDescriptor())
        worker = manager.callFunc("fixtureRead").worker
        replacement = manager.callFunc("startSession", vodDescriptor())
        result = cleanup(id)
        result[key] = false
        worker.result = result
        worker.state = "stop"
        check(manager.cleanupBlocked and manager.callFunc("fixtureRead").worker.isSameNode(worker), "unsafe typed VOD cleanup retains resource owner: " + key)
        check(manager.callFunc("startSession", vodDescriptor()) = "" and manager.callFunc("fixtureRead").pending = invalid, "unsafe cleanup blocks all VOD replacement")
        manager.callFunc("onDestroy")
        check(manager.callFunc("fixtureRead").disposed, "blocked disposal retains owner until safe acknowledgment")
        worker.result = cleanup(id)
        m.scene.removeChild(manager)
    end for
    manager = newManager()
    id = manager.callFunc("startSession", vodDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    worker.ready = vodReady(id, vodDescriptor())
    port = CreateObject("roMessagePort")
    manager.observeField("event", port)
    result = cleanup(id)
    result.reason = "live_helper_failed"
    result.helperFailureReason = "native-live: selected discontinuity change unsupported"
    worker.result = result
    failed = nextFailure(port)
    check(failed <> invalid and failed.reason = "worker_finished", "VOD never enters LIVE source-transition classification")
    manager.unobserveField("event")
    finishManager(manager)
end sub

function variantLine(height as integer, width as integer, bandwidth as integer, codec as string, url as string) as string
    return "#EXT-X-STREAM-INF:BANDWIDTH=" + bandwidth.ToStr() + ",RESOLUTION=" + width.ToStr() + "x" + height.ToStr() + ",FRAME-RATE=60.000,CODECS=" + Chr(34) + codec + ",mp4a.40.2" + Chr(34) + Chr(10) + url + Chr(10)
end function

function completedPlaylist(map = true as boolean) as string
    nl = Chr(10)
    text = "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl + "#EXT-X-PLAYLIST-TYPE:VOD" + nl + "#EXT-X-TARGETDURATION:10" + nl
    if map then text += "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34) + nl
    return text + "#EXTINF:10.000," + nl + "0.m4s" + nl + "#EXTINF:10.000," + nl + "1.m4s" + nl + "#EXT-X-ENDLIST" + nl
end function

function runContent(master as string, playlist as string, proxy = "" as string) as object
    set_user_setting("proxy.url", proxy)
    task = CreateObject("roSGNode", "VodContentProbe")
    m.scene.appendChild(task)
    task.fixtureMaster = master
    task.fixturePlaylist = playlist
    task.fixtureMasterStatus = 200
    task.enableRokuDemux = true
    task.callFunc("loadHlsContent", { contentType: "VOD", contentId: "123456789", contentTitle: "Recorded fixture", streamerDisplayName: "Fixture", Length: 73760 })
    check(task.graphqlCount = 1, "public recorded request resolves token without assumed login")
    prefix = "https://usher.ttvnw.net/vod/v2/123456789.m3u8?"
    check(task.httpRequests.Count() >= 1 and task.httpRequests[0].url.Left(prefix.Len()) = prefix, "actual hardcoded recorded Usher request precedes rendition inspection")
    return task
end function

sub testContentTask()
    high = variantLine(1080, 1920, 8000000, "avc1.4D402A", "https://d123.cloudfront.net/vod/1080.m3u8?fixture=exact%2B")
    low = variantLine(720, 1280, 4000000, "avc1.4D4020", "https://d123.cloudfront.net/vod/720.m3u8?fixture=exact%2B")
    master = "#EXTM3U" + Chr(10) + high + low
    task = runContent(master, completedPlaylist())
    node = task.response
    check(node.contentType = "VOD" and node.contentId = "123456789" and node.Length = 73760, "actual Task preserves recorded identity and duration")
    if m.enabled
        check(node.playbackTransport = "roku-demux" and node.localPlaybackDescriptor.version = 2, "enabled completed combined VOD gets only v2 descriptor")
        check(node.QualityID = "Automatic" and node.localPlaybackDescriptor.qualityId = "720p60", "Automatic picks one bounded supported fixed recorded rendition")
        check(node.localPlaybackDescriptor.sourceUrl = "https://d123.cloudfront.net/vod/720.m3u8?fixture=exact%2B", "descriptor retains exact signed selected source")
        check(task.metadata.Count() = 3 and task.metadata[1].localPlaybackDescriptor.qualityId = "1080p60", "original selected quality ladder remains intact")
    else
        check(node.playbackTransport <> "roku-demux" and node.localPlaybackDescriptor = invalid, "normal gatefalse does not advertise futile recorded local path")
    end if
    m.scene.removeChild(task)
    task = runContent(master, completedPlaylist(), "http://192.0.2.10:3000")
    check(task.response.playbackTransport = "python" and task.response.isProxied and task.response.localPlaybackDescriptor = invalid, "configured optional service retains recorded precedence")
    m.scene.removeChild(task)
    task = runContent(master, completedPlaylist(false))
    check(task.response.playbackTransport = "direct" and not task.response.isTransmux and task.response.localPlaybackDescriptor = invalid, "direct recorded TS never enters bundled VOD helper")
    m.scene.removeChild(task)
    separate = "#EXTM3U" + Chr(10) + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + Chr(34) + "aud" + Chr(34) + ",NAME=" + Chr(34) + "Audio" + Chr(34) + ",URI=" + Chr(34) + "https://d123.cloudfront.net/vod/audio.m3u8" + Chr(34) + Chr(10)
    separate += "#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1280x720,FRAME-RATE=60.000,CODECS=" + Chr(34) + "avc1.4D4020,mp4a.40.2" + Chr(34) + ",AUDIO=" + Chr(34) + "aud" + Chr(34) + Chr(10) + "https://d123.cloudfront.net/vod/video.m3u8" + Chr(10)
    task = runContent(separate, completedPlaylist())
    check(task.response.QualityID = "Automatic" and task.response.playbackTransport = "direct" and task.response.localPlaybackDescriptor = invalid, "separate audio preserves full master without VOD opt-in")
    check(task.httpRequests.Count() = 1, "separate-audio fallback performs no child/bundled probe")
    m.scene.removeChild(task)
    task = runContent(master, completedPlaylist().Replace("#EXT-X-ENDLIST", ""))
    check(task.response.playbackTransport <> "roku-demux", "unfinished recorded EVENT is not eligible")
    m.scene.removeChild(task)
    task = runContent("#EXTM3U" + Chr(10) + low + low, completedPlaylist())
    check(task.response.playbackTransport <> "roku-demux", "duplicate selected master URI cannot create VOD descriptor")
    m.scene.removeChild(task)
    errorHandler = CreateObject("roSGNode", "VideoErrorHandler")
    kind = errorHandler.callFunc("classifyError", 403, "restricted recording")
    message = errorHandler.callFunc("getUserFriendlyErrorMessage", 403, kind)
    check(kind = "authentication_error" and message.title = "Twitch didn't authorize this video", "restricted recorded403 uses original truthful authorization copy")
    check(message.suggestion = "Public streams play without signing in. Try again, or choose another video.", "403 alone never establishes mandatory login")
    set_user_setting("proxy.url", "")
end sub

function vodContent() as object
    node = CreateObject("roSGNode", "TwitchContentNode")
    d = vodDescriptor()
    node.setFields({ contentType: "VOD", contentId: d.vodId, contentTitle: "Recorded fixture", streamerLogin: "fixturechannel", streamerDisplayName: "Fixture", url: d.sourceUrl, QualityID: d.qualityId, streamFormat: "hls", Length: 73760, playbackTransport: "roku-demux", localPlaybackDescriptor: d, isTransmux: true })
    return node
end function

sub testDisabledPlayer()
    manager = newManager()
    m.scene.localPlaybackSession = manager
    player = CreateObject("roSGNode", "VideoPlayer")
    m.scene.appendChild(player)
    player.contentRequested = vodContent()
    settle(40)
    task = player.callFunc("fixtureRead").task
    check(task <> invalid and not task.enableRokuDemux, "normal recorded player cannot open capability through Task flag")
    task.response = vodContent()
    settle(40)
    dialog = player.callFunc("fixtureRead").transmuxDialog
    check(dialog <> invalid and dialog.buttons.Count() = 1 and dialog.buttons[0] = "Back", "normal gatefalse offers no futile Roku-only playback for v2 input")
    check(manager.callFunc("fixtureRead").worker = invalid, "caller-supplied v2 descriptor cannot bypass normal compiled capability")
    player.callFunc("onDestroy")
    m.scene.removeChild(player)
    m.scene.dialog = invalid
    m.scene.localPlaybackSession = invalid
    finishManager(manager)
end sub

sub testPlayer()
    set_user_setting("VideoBookmarks", "{" + Chr(34) + "123456789" + Chr(34) + ":" + Chr(34) + "41" + Chr(34) + "}")
    manager = newManager()
    m.scene.localPlaybackSession = manager
    player = CreateObject("roSGNode", "VideoPlayer")
    m.scene.appendChild(player)
    request = vodContent()
    player.contentRequested = request
    settle(40)
    task = player.callFunc("fixtureRead").task
    check(task <> invalid and task.enableRokuDemux, "actual recorded player opts Task only under offline native capability")
    original = vodContent()
    task.response = original
    settle(40)
    check(player.callFunc("fixtureRead").video = invalid and player.callFunc("fixtureRead").transmuxDialog = invalid, "eligible recorded content waits for its session without a prompt")
    id = player.callFunc("fixtureRead").sessionId
    worker = manager.callFunc("fixtureRead").worker
    check(id <> "" and worker <> invalid and worker.subtype() = "RokuVodDemuxServer", "eligible recorded content reaches actual VOD session owner")
    if worker = invalid then throw "VOD worker missing after automatic start"
    stale = vodReady("00000000000000000000000000000000", vodDescriptor())
    worker.ready = stale
    check(player.callFunc("fixtureRead").video = invalid, "stale VOD Ready never changes active playback")
    for each key in ["url", "masterPath", "mode", "totalDurationUs", "metadata", "extraField"]
        event = { id: id, status: "ready", reason: "", url: "http://127.0.0.1:49371/vod/" + id + "/master.m3u8", metadata: vodDescriptor().metadata, mode: "vod", totalDurationUs: 73760000000&, masterPath: "/vod/" + id + "/master.m3u8" }
        if key = "url" then event[key] = "http://192.0.2.1:49371" + event.masterPath
        if key = "masterPath" then event[key] = "/vod/00000000000000000000000000000000/master.m3u8"
        if key = "mode" then event[key] = "live"
        if key = "totalDurationUs" then event[key] = "73760000000"
        if key = "metadata" then event[key] = liveDescriptor().metadata
        if key = "extraField" then event[key] = "refuse"
        manager.event = event
        check(player.callFunc("fixtureRead").video = invalid and not worker.stopRequested, "actual player refuses malformed current VOD owner event: " + key)
    end for
    worker.ready = vodReady(id, vodDescriptor())
    settle(30)
    video = player.callFunc("fixtureRead").video
    check(video <> invalid and video.subtype() = "CustomVideo", "recorded local playback retains actual CustomVideo wrapper")
    if video = invalid then throw "valid recorded Ready failed to create wrapper"
    check(video.control = "play" and video.content.url = "http://127.0.0.1:49371/vod/" + id + "/master.m3u8", "valid VOD Ready plays exact session-bound local URL")
    check(m.scene.findNode("stitchAdMetadataOwner") = invalid, "VOD playback does not create an unsupported LIVE ad sidecar")
    check(manager.callFunc("fixtureRead").video.isSameNode(video), "actual Session owns the exact playing wrapper")
    check(not player.content.isSameNode(original) and original.url = vodDescriptor().sourceUrl, "local playable ContentNode is cloned; original source stays unchanged")
    check(player.content.localPlaybackDescriptor.sourceUrl = original.localPlaybackDescriptor.sourceUrl and player.content.QualityID = original.QualityID, "signed source descriptor and selected quality survive clone")
    check(player.content.contentId = original.contentId and player.content.contentType = "VOD" and player.content.Length = original.Length and player.content.contentTitle = original.contentTitle, "recorded identity/title/full duration survive local transport swap")
    check(video.video_type = "VOD" and video.video_id = original.contentId and video.content.PlayStart = 41, "actual bookmark resume remains native PlayStart without timestamp normalization")
    check(not player.content.isProxied and not player.content.isTransmux and not player.content.ForwardQueryStringParams, "local route retains original transport flag semantics")
    first = video
    worker.ready = vodReady(id, vodDescriptor())
    player.callFunc("fixtureEventAgain")
    check(player.callFunc("fixtureRead").video.isSameNode(first), "duplicate matching Ready does not replace Video")
    video.duration = 73760
    video.position = 100
    video.state = "paused"
    beforeSeek = video.seek
    video.callFunc("fixturePreview", 10)
    check(video.callFunc("fixtureSeekRead").preview and video.callFunc("fixtureSeekRead").position = 110 and video.seek = beforeSeek, "actual VOD seek preview does not apply native seek")
    video.callFunc("fixtureCancelPreview")
    check(not video.callFunc("fixtureSeekRead").preview and video.seek = beforeSeek and video.control = "pause", "actual preview cancel retains paused state and original seek")
    video.state = "playing"
    video.callFunc("fixturePreview", 20)
    video.callFunc("fixtureApplyPreview")
    check(video.seek = 120 and video.control = "resume", "actual preview apply uses native target and restores playing state")
    video.toggleChat = true
    settle(20)
    check(m.scene.dialog <> invalid and m.scene.dialog.title = "Chat is unavailable for this video", "recorded chat opens preserved unavailable notice")
    check(video.control = "resume", "recorded chat notice does not stop playback")
    if m.scene.dialog <> invalid then m.scene.dialog.buttonSelected = 0
    video.position = 180
    previousRequests = m.global.fixtureContentTasks
    manager.event = { id: id, status: "failed", reason: "worker_finished" }
    settle(20)
    dialog = player.callFunc("fixtureRead").errorDialog
    check(dialog <> invalid and dialog.buttons[0] = "Try again" and video.control = "stop" and worker.stopRequested, "recorded failure offers actual manual retry and stops both owned resources")
    if dialog = invalid then throw "recorded error dialog missing"
    dialog.buttonSelected = 0
    settle(20)
    retryTask = player.callFunc("fixtureRead").task
    player.callFunc("fixtureRetry")
    check(m.global.fixtureContentTasks = previousRequests + 1 and player.callFunc("fixtureRead").task.isSameNode(retryTask), "repeated recorded Retry creates exactly one fresh request")
    check(retryTask.enableRokuDemux and retryTask.contentRequested.contentId = original.contentId and retryTask.contentRequested.contentType = "VOD", "actual recorded Retry retains the video request and native eligibility gate")
    retryTask.response = vodContent()
    settle(20)
    replacementId = player.callFunc("fixtureRead").sessionId
    check(replacementId <> id and manager.callFunc("fixtureRead").worker.isSameNode(worker), "refreshed VOD waits behind old owner until complete cleanup")
    worker.result = cleanup(id)
    worker.state = "stop"
    check(manager.callFunc("fixtureRead").worker.isSameNode(worker), "manual recorded Retry cannot replace before old Video STOP")
    video.state = "stopped"
    replacement = manager.callFunc("fixtureRead").worker
    check(not replacement.isSameNode(worker) and replacement.subtype() = "RokuVodDemuxServer", "manual Retry starts a fresh VOD Task only after actual dual STOP")
    worker.ready = vodReady(id, vodDescriptor())
    check(player.callFunc("fixtureRead").sessionId = replacementId, "old ready cannot impersonate refreshed recorded owner")
    replacement.ready = vodReady(replacementId, vodDescriptor())
    settle(20)
    video = player.callFunc("fixtureRead").video
    worker = replacement
    id = replacementId
    check(video <> invalid and video.content.PlayStart = 180 and video.video_type = "VOD", "actual recorded Retry retains native resume position on the new local timeline")
    player.callFunc("fixtureBack")
    settle(20)
    check(worker.stopRequested and video.control = "stop", "recorded Back requests actual Task and Video stop")
    worker.result = cleanup(id)
    worker.state = "stop"
    video.state = "stopped"
    settle(20)
    check(not manager.busy and player.backPressed and player.state = "done", "recorded Back waits for actual five cleanup acknowledgments")
    player.callFunc("onDestroy")
    m.scene.removeChild(player)
    m.scene.dialog = invalid
    m.scene.localPlaybackSession = invalid
    finishManager(manager)
end sub
