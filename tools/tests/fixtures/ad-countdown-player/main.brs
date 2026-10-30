sub main()
    m.assertions = 0
    m.failures = 0
    m.port = CreateObject("roMessagePort")
    m.screen = CreateObject("roSGScreen")
    m.screen.SetMessagePort(m.port)
    m.global = m.screen.getGlobalNode()
    m.global.addFields({fixtureRegistry: {}})
    setConstants()
    m.scene = m.screen.CreateScene("AdClockHost")
    m.screen.Show()
    print "STITCH_AD_PLAYER_BEGIN: __MARKER__"
    for each name in ["StitchVideo", "CustomVideo"]
        if not __RETENTION_ONLY__ then testRealWrapper(name)
        testRetainedClock(name)
    end for
    if not __RETENTION_ONLY__
        testOwnerReplacement()
        testOwnerFailure("no-response")
        testOwnerFailure("unsafe")
        testOwnerDeadline()
    end if
    m.screen.Close()
    print "STITCH_AD_PLAYER_END: __MARKER__ "; FormatJson({assertions: m.assertions, failures: m.failures})
end sub

sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_AD_PLAYER_FAIL: __MARKER__ " + message
    end if
end sub

sub settle(duration as integer)
    clock = CreateObject("roTimespan")
    while clock.TotalMilliseconds() < duration
        wait(10, m.port)
    end while
end sub

function video(name as string) as object
    result = CreateObject("roSGNode", name)
    m.scene.appendChild(result)
    result.video_type = "VOD"
    result.duration = 600
    if result.hasField("suppressStartupSeek") then result.suppressStartupSeek = true
    content = CreateObject("roSGNode", "ContentNode")
    content.url = "https://test.ttvnw.net/current.m3u8"
    result.content = content
    result.state = "playing"
    settle(60)
    return result
end function

function cue() as object
    return {startUs: 1767225601000000&, endUs: 1767225605500001&, durationUs: 4500001&, podCount: 2, podPosition: 0}
end function

function bounds() as object
    return [{startUs: 1767225600000000&, endUs: 1767225608000000&}]
end function

sub shown(node as object, time as string, message as string)
    read = node.callFunc("fixtureAdRead")
    check(read.badgeVisible and read.title = "Ad 1 of 2" and read.time = Chr(183) + " " + time, message)
end sub

sub hidden(node as object, message as string)
    read = node.callFunc("fixtureAdRead")
    check(not read.badgeVisible and read.title = "" and read.time = "", message)
end sub

sub destroyVideo(node as object)
    node.callFunc("onDestroy")
    m.scene.removeChild(node)
end sub

sub testRealWrapper(name as string)
    node = video(name)
    check(node.callFunc("beginAdCountdown", "contentA"), name + " actual wrapper begins local owner")
    check(node.callFunc("setAdMetadata", "contentA", [cue()], bounds()), name + " sanitized cues and anchors accepted")
    hidden(node, name + " cues alone cannot invent frame time")
    node.positionInfo = {epoch: 1, video: 1767225601#, audio: 1767225601#}
    settle(50)
    shown(node, "0:05", name + " actual positionInfo starts fractional countdown")
    node.position = 500
    node.seek = 500
    settle(50)
    shown(node, "0:05", name + " requested seek/position cannot substitute for rendered UTC")
    node.state = "paused"
    settle(150)
    shown(node, "0:05", name + " pause freezes the actual frame without a timer")
    node.state = "buffering"
    settle(120)
    shown(node, "0:05", name + " buffering does not advance presented time")
    node.positionInfo = {epoch: 1, video: 1767225602.500001#, audio: 1767225602.500001#}
    settle(50)
    shown(node, "0:03", name + " an actually presented seek frame updates countdown")
    check(not node.callFunc("setAdMetadata", "old", [cue()], bounds()), name + " stale metadata refuses before UI")
    shown(node, "0:03", name + " stale owner does not hide current valid badge")
    node.chatIsVisible = true
    settle(50)
    read = node.callFunc("fixtureAdRead")
    check(read.x + read.width = 912, name + " badge fits actual 960px video beside chat")
    node.chatIsVisible = false
    settle(50)
    read = node.callFunc("fixtureAdRead")
    check(read.x + read.width = 1232, name + " badge follows full video geometry")
    node.positionInfo = {epoch: 0, video: 4.5#}
    settle(40)
    hidden(node, name + " unknown relative clock hides badge")
    node.positionInfo = {epoch: 1, video: 1767225608#}
    settle(40)
    hidden(node, name + " unanchored exact segment end hides badge")
    node.positionInfo = {epoch: 1, video: 1767225603#}
    settle(40)
    shown(node, "0:03", name + " exact real frame recovers truthful display")
    node.state = "error"
    settle(40)
    hidden(node, name + " terminal playback error clears owner/badge")
    check(node.callFunc("fixtureAdRead").owner = "", name + " terminal owner cleared")
    node.state = "playing"
    node.callFunc("beginAdCountdown", "contentB")
    node.callFunc("setAdMetadata", "contentB", [cue()], bounds())
    node.positionInfo = {epoch: 1, video: 1767225602#}
    settle(40)
    shown(node, "0:04", name + " new content owner receives its own frame")
    replacement = CreateObject("roSGNode", "ContentNode")
    replacement.url = "https://test.ttvnw.net/replacement.m3u8"
    node.content = replacement
    settle(40)
    hidden(node, name + " actual content replacement clears clock/cues")
    node.callFunc("onDestroy")
    check(not node.callFunc("beginAdCountdown", "disposed"), name + " disposed wrapper refuses new countdown")
    check(not node.callFunc("setAdMetadata", "contentB", [cue()], bounds()), name + " disposed callback cannot revive UI")
    m.scene.removeChild(node)
end sub

function owner() as object
    result = CreateObject("roSGNode", "AdMetadataOwner")
    m.scene.appendChild(result)
    return result
end function

function response(token as string) as object
    return {owner: token, cues: [cue()], bounds: bounds()}
end function

sub awaitIdle(ownerNode as object)
    clock = CreateObject("roTimespan")
    while ownerNode.busy and clock.TotalMilliseconds() < 2000
        settle(10)
    end while
    check(not ownerNode.busy, "actual cooperative worker is idle within finite fixture deadline")
end sub

sub testOwnerReplacement()
    manager = owner()
    first = video("StitchVideo")
    token = manager.callFunc("beginContent", first, first.content.url, "direct")
    check(tadOwner(token) and manager.busy, "retained owner starts one actual Task")
    state = manager.callFunc("fixtureAdOwnerRead")
    oldWorker = state.worker
    oldWorker.fixtureHoldStop = true
    check(oldWorker <> invalid and oldWorker.subtype() = "TwitchAdMetadata", "actual worker boundary is explicit")
    manager.callFunc("fixtureDeliverAd", response("old"))
    settle(50)
    check(first.callFunc("fixtureAdRead").bounds = 0, "wrong Task owner cannot deliver metadata")
    manager.callFunc("fixtureDeliverAd", {owner: token, cues: [cue()], bounds: bounds(), rawUrl: "SECRET"})
    settle(50)
    check(first.callFunc("fixtureAdRead").bounds = 0, "extra provider payload refused at scene boundary")
    manager.callFunc("fixtureDeliverAd", response(token))
    first.positionInfo = {epoch: 1, video: 1767225602#}
    settle(70)
    shown(first, "0:04", "actual owner response reaches actual wrapper clock/badge")
    replacementVideo = video("CustomVideo")
    skippedToken = manager.callFunc("beginContent", replacementVideo, replacementVideo.content.url, "direct")
    newToken = manager.callFunc("beginContent", replacementVideo, replacementVideo.content.url, "direct")
    check(newToken <> skippedToken, "rapid replacement has independent current owners")
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.video = invalid and state.stopping, "old video reference dropped immediately before replacement")
    check(oldWorker.stopRequested, "actual old worker receives typed stop")
    for each malformed in [{owner:token,cues:[],bounds:[],closed:"true",cleanupOk:true}, {owner:token,cues:[],bounds:[],closed:true,cleanupOk:1}, {owner:token,cues:[],bounds:[],closed:false,cleanupOk:true}]
        manager.callFunc("fixtureDeliverAd", malformed)
        settle(20)
        check(not manager.callFunc("fixtureAdOwnerRead").acknowledged and manager.busy, "non-Boolean or false closed acknowledgment cannot release native owner")
    end for
    manager.callFunc("fixtureDeliverAd", {owner: token, cues: [], bounds: [], closed: true, cleanupOk: true})
    settle(40)
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.acknowledged and manager.busy and state.worker.isSameNode(oldWorker) and oldWorker.state <> "stop", "closed response alone retains running old Task and pending replacement")
    currentPendingOwner = ""
    if state.pending <> invalid then currentPendingOwner = state.pending.owner
    check(currentPendingOwner = newToken, "one replaceable pending request coalesces rapid content changes")
    oldWorker.fixtureHoldStop = false
    ' Wait for the real cooperative Task/owner handshake, not a machine-speed
    ' assumption. The unchanged assertions below still fail on this deadline.
    replacementClock = CreateObject("roTimespan")
    while replacementClock.TotalMilliseconds() < 2000
        state = manager.callFunc("fixtureAdOwnerRead")
        closed = oldWorker.response
        safeClosed = false
        if type(closed) = "roAssociativeArray"
            safeClosed = twitchAdClockBoolean(closed.closed) and closed.closed = true and twitchAdClockBoolean(closed.cleanupOk) and closed.cleanupOk = true
        end if
        if safeClosed and oldWorker.fixtureReceivedStop and oldWorker.state = "stop" and state.owner = newToken and state.worker <> invalid
            if not state.worker.isSameNode(oldWorker) then exit while
        end if
        settle(10)
    end while
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.owner = newToken and state.worker <> invalid and not state.worker.isSameNode(oldWorker), "new worker starts only after old safe acknowledgement")
    check(oldWorker.fixtureReceivedStop and oldWorker.state = "stop", "old Task actually stopped cooperatively")
    hidden(first, "old wrapper badge cleared on source replacement")
    manager.callFunc("fixtureDeliverAd", response(token))
    settle(40)
    check(replacementVideo.callFunc("fixtureAdRead").bounds = 0, "old callback cannot cross new content owner")
    manager.callFunc("endContent", newToken)
    awaitIdle(manager)
    check(not manager.cleanupBlocked, "safe cleanup remains available")
    manager.callFunc("onDestroy")
    check(manager.closed and not manager.busy, "permanent owner disposal pairs timer/Task cleanup")
    check(manager.callFunc("beginContent", replacementVideo, replacementVideo.content.url, "direct") = "", "permanent owner cannot restart")
    destroyVideo(first)
    destroyVideo(replacementVideo)
    m.scene.removeChild(manager)
end sub

sub testOwnerFailure(mode as string)
    manager = owner()
    node = video("CustomVideo")
    token = manager.callFunc("beginContent", node, node.content.url, "direct")
    manager.callFunc("fixtureWorkerMode", mode)
    manager.callFunc("endContent", token)
    awaitIdle(manager)
    check(manager.cleanupBlocked, "stop/no-response or unsafe acknowledgement permanently refuses restart: " + mode)
    check(manager.callFunc("beginContent", node, node.content.url, "direct") = "", "unsafe worker cannot authorize overlap")
    manager.callFunc("onDestroy")
    check(manager.closed, "stopped unsafe owner can dispose without claiming clean success")
    destroyVideo(node)
    m.scene.removeChild(manager)
end sub

sub testOwnerDeadline()
    manager = owner()
    node = video("CustomVideo")
    token = manager.callFunc("beginContent", node, node.content.url, "direct")
    held = manager.callFunc("fixtureAdOwnerRead").worker
    held.fixtureHoldStop = true
    ' The actual cleanup handler sees a fake clock at its original deadline;
    ' native Task and timer state remain real. No budget is raised.
    manager.callFunc("endContent", token)
    manager.callFunc("fixtureExpireAdCleanup")
    check(manager.cleanupBlocked, "actual five-second cleanup deadline refuses progress")
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.timerControl = "stop", "deadline stops timer instead of polling forever")
    check(manager.busy and state.worker.isSameNode(held), "deadline cannot force-stop or release pending file owner")
    held.fixtureHoldStop = false
    awaitIdle(manager)
    check(manager.cleanupBlocked, "late safe acknowledgement cannot erase prior unsafe deadline")
    manager.callFunc("onDestroy")
    destroyVideo(node)
    m.scene.removeChild(manager)
end sub

function boundAt(startUs as longinteger, endUs as longinteger) as object
    return {startUs: startUs, endUs: endUs}
end function

function cueAt(startUs as longinteger, endUs as longinteger, position as integer) as object
    return {startUs: startUs, endUs: endUs, durationUs: endUs - startUs, podCount: 2, podPosition: position}
end function

sub retainedEmpty(node as object, message as string)
    read = node.callFunc("fixtureAdRetention")
    check(read.bounds.Count() = 0 and read.cues.Count() = 0 and read.utc = invalid, message)
    hidden(node, message + " hides badge")
end sub

sub startRetained(node as object)
    check(node.callFunc("beginAdCountdown", "retainedA"), "retained current owner begins")
    check(node.callFunc("setAdMetadata", "retainedA", [cue()], bounds()), "retained initial exact metadata accepted")
    node.positionInfo = {epoch: 1, video: 1767225602.500001#, audio: 1767225602.500001#}
    settle(30)
    shown(node, "0:03", "initial real frame covered")
end sub

sub testRetainedClock(name as string)
    node = video(name)
    startRetained(node)
    for each state in ["buffering", "paused"]
        node.state = state
        settle(20)
        check(node.callFunc("setAdMetadata", "retainedA", [], [boundAt(1767225608000000&, 1767225614000000&)]), name + " advancing source window accepted with no new ad")
        shown(node, "0:03", name + " exact buffered/paused frame retains observed ad and anchor")
    end for
    read = node.callFunc("fixtureAdRetention")
    check(read.bounds.Count() = 2 and read.cues.Count() = 1, name + " exact duplicates coalesced across publications")
    check(read.bounds[0].startUs = 1767225600000000& and read.bounds[0].endUs = 1767225608000000&, name + " old bound never extended")
    check(read.cues[0].Count() = 5 and read.cues[0].durationUs = 4500001&, name + " retained primitive five-field cue unchanged")
    check(not node.callFunc("setAdMetadata", "old", [], []), name + " stale fully empty response cannot clear owner")
    shown(node, "0:03", name + " stale owner preserves buffered frame")
    node.positionInfo = {epoch: 0, video: 1767225602.500001#}
    settle(20)
    hidden(node, name + " retained dates cannot promote unknown native epoch")
    node.positionInfo = {epoch: 1, video: 1767225602.500001#}
    settle(20)
    shown(node, "0:03", name + " real native frame restores retained display")
    check(node.callFunc("setAdMetadata", "retainedA", [], [boundAt(1767225620000000&, 1767225626000000&)]), name + " disjoint source interval accepted without filling gap")
    node.positionInfo = {epoch: 1, video: 1767225616#}
    settle(20)
    hidden(node, name + " unobserved interval gap remains hidden")
    node.positionInfo = {epoch: 1, video: 1767225602.500001#}
    settle(20)
    shown(node, "0:03", name + " prior exact interval still covers frame")
    check(not node.callFunc("setAdMetadata", "retainedA", [], [boundAt(1767225600000000&, 1767225607000000&)]), name + " same-start changed end conflicts rather than shortening observed bound")
    retainedEmpty(node, name + " conflicting bounds clear all retained state")

    startRetained(node)
    conflict = cue()
    conflict.podPosition = 1
    check(not node.callFunc("setAdMetadata", "retainedA", [conflict], bounds()), name + " exact interval differing pod identity refused")
    retainedEmpty(node, name + " pod conflict clears retained state")
    startRetained(node)
    check(not node.callFunc("setAdMetadata", "retainedA", [], [boundAt(1767225607000000&, 1767225610000000&)]), name + " overlapping nonduplicate bounds refused")
    retainedEmpty(node, name + " overlapping bound conflict clears")

    check(node.callFunc("beginAdCountdown", "rounding"), name + " original pod-rounding owner begins")
    first = cueAt(1767225601000000&, 1767225605500001&, 0)
    second = cueAt(1767225605500000&, 1767225609000000&, 1)
    check(node.callFunc("setAdMetadata", "rounding", [first, second], [boundAt(1767225600000000&, 1767225610000000&)]), name + " original within-payload one-microsecond consecutive-pod overlap preserved")
    check(node.callFunc("setAdMetadata", "rounding", [second], [boundAt(1767225610000000&, 1767225615000000&)]), name + " exact duplicate preserves already corroborated pod rounding")
    check(node.callFunc("fixtureAdRetention").cues.Count() = 2, name + " exact repeated overlapping cue coalesces")
    check(node.callFunc("beginAdCountdown", "cross"), name + " fresh begin clears old overlapping pod")
    retainedEmpty(node, name + " fresh begin clears both caches and frame")
    check(node.callFunc("setAdMetadata", "cross", [first], bounds()), name + " first publication has one exact cue")
    check(not node.callFunc("setAdMetadata", "cross", [second], [boundAt(1767225608000000&, 1767225614000000&)]), name + " new cross-publication overlap refused despite valid individual pod cues")
    retainedEmpty(node, name + " cross-publication overlap clears safe state")

    startRetained(node)
    manyBounds = []
    for i = 0 to 127
        start = 1767225620000000& + i * 2000000&
        manyBounds.Push(boundAt(start, start + 1000000&))
    end for
    check(node.callFunc("setAdMetadata", "retainedA", [], manyBounds), name + " bounded sorted merge evicts oldest exact bound at 128")
    read = node.callFunc("fixtureAdRetention")
    check(read.bounds.Count() = 128 and read.bounds[0].startUs = 1767225620000000& and read.bounds[127].endUs = 1767225875000000&, name + " newest 128 exact bounds retained")
    hidden(node, name + " evicted old presented frame hides conservatively")
    manyCues = []
    for i = 0 to 31
        start = 1767225620000000& + i * 2000000&
        manyCues.Push(cueAt(start, start + 1000000&, 0))
    end for
    check(node.callFunc("setAdMetadata", "retainedA", manyCues, manyBounds), name + " cue cache evicts oldest at exact 32 cap")
    read = node.callFunc("fixtureAdRetention")
    check(read.cues.Count() = 32 and read.cues[0].startUs = 1767225620000000& and read.cues[31].endUs = 1767225683000000&, name + " newest 32 exact cues retained")
    node.positionInfo = {epoch: 1, video: 1767225620.5#}
    settle(20)
    shown(node, "0:01", name + " actual frame in retained newest observed ad renders")
    check(node.callFunc("setAdMetadata", "retainedA", manyCues, manyBounds), name + " repeated cap-size payload remains exact duplicates")
    read = node.callFunc("fixtureAdRetention")
    check(read.bounds.Count() = 128 and read.cues.Count() = 32, name + " duplicates do not consume bounded capacity")
    check(node.callFunc("setAdMetadata", "retainedA", [], []), name + " fully empty valid metadata clears retention")
    retainedEmpty(node, name + " fully empty reset requires new native frame")
    check(node.callFunc("setAdMetadata", "retainedA", [cue()], bounds()), name + " fresh metadata after empty cannot invent last frame")
    hidden(node, name + " full-empty reset lost old frame safely")
    check(not node.callFunc("setAdMetadata", "retainedA", invalid, bounds()), name + " malformed metadata clears all retained state")
    retainedEmpty(node, name + " invalid metadata clears both caches")
    for each state in ["stopped", "finished", "error"]
        node.state = "playing"
        startRetained(node)
        node.state = state
        settle(20)
        read = node.callFunc("fixtureAdRetention")
        check(read.owner = "", name + " terminal state clears current owner: " + state)
        retainedEmpty(node, name + " terminal state clears retained data: " + state)
    end for
    node.state = "playing"
    startRetained(node)
    replacement = CreateObject("roSGNode", "ContentNode")
    replacement.url = "https://test.ttvnw.net/new-source.m3u8"
    node.content = replacement
    settle(20)
    retainedEmpty(node, name + " actual source replacement drops exact old dates/cues")
    check(node.callFunc("fixtureAdRetention").owner = "", name + " source replacement drops current owner")
    startRetained(node)
    node.callFunc("onDestroy")
    retainedEmpty(node, name + " actual permanent disposal clears exact retention")
    check(not node.callFunc("setAdMetadata", "retainedA", [cue()], bounds()), name + " disposed callback cannot restore cache")
    m.scene.removeChild(node)
end sub
