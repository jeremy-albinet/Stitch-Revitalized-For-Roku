' Actual Hero, Player and manager composition. Only worker/SDK/media state are
' fixture inputs. The main port observes exitApp without closing the test early.
sub main()
    m.assertions = 0
    m.failures = 0
    m.exitRequested = false
    m.port = CreateObject("roMessagePort")
    screen = CreateObject("roSGScreen")
    screen.SetMessagePort(m.port)
    m.global = screen.GetGlobalNode()
    setConstants()
    m.global.AddFields({ priorExitReason: "", fixtureRegistry: { "app/last_seen_version": "999.0.0", "app/active_user": "$default$", device_code: "canned-device", ChatOption: "false", ChatFontSize: "16" }, fixtureHistory: [], fixtureContentTasks: 0, emoteCache: {} })
    m.scene = screen.CreateScene("HeroScene")
    screen.Show()
    m.scene.ObserveField("exitApp", m.port)
    m.scene.SetFocus(true)
    ' brs-node reports a ButtonGroup as its own focusedChild, so the native menu
    ' tab ID resolver cannot select Following. Execute the same real openPage.
    m.scene.CallFunc("fixtureOpenFollowing")
    settle(80)
    check(hero().active <> invalid and hero().active.id = "Following", "actual Hero startup creates Following")
    permanentManager = m.scene.localPlaybackSession
    m.scene.CallFunc("fixtureLoginFinished")
    settle(60)
    check(m.scene.localPlaybackSession.IsSameNode(permanentManager) and not permanentManager.CallFunc("fixtureManager").disposed, "ordinary sign-in preserves the same usable permanent manager")
    if "__NEGATIVE_CONTROL__" = "yes"
        check(false, "deliberate reversed assertion")
        finishMain(screen)
        return
    end if
    ' Actual live overlay Exit reaches the same typed cooperative Player action.
    player = openPlayer(true)
    if player = invalid
        finishMain(screen)
        return
    end if
    manager = m.scene.localPlaybackSession
    owned = manager.CallFunc("fixtureManager")
    worker = owned.worker
    id = owned.currentId
    worker.ready = readyFor(id)
    video = player.CallFunc("fixturePlayer").video
    video.state = "playing"
    selectLiveExit(video)
    check(hero().active.IsSameNode(player) and not player.backPressed and player.CallFunc("fixturePlayer").exitPending and manager.busy, "actual on-screen Exit retains busy Player until strict cleanup acknowledgment")
    overlay = video.CallFunc("fixtureOverlay")
    check(overlay.disposed and video.control = "stop" and overlay.fadeControl = "stop" and video.IsInFocusChain(), "actual Exit disposes focused wrapper and stops fade timer while cleanup waits")
    press("play")
    settle(350)
    check(video.control = "stop" and video.CallFunc("fixtureOverlay").fadeControl = "stop", "remote Play after disposed Exit cannot replace stop or restart fade timer")
    press("left")
    settle(350)
    press("ok")
    settle(350)
    after = video.CallFunc("fixtureOverlay")
    check(after.focusedButton = overlay.focusedButton and after.fadeControl = "stop" and not after.qualityVisible and m.scene.dialog = invalid and video.control = "stop", "remote Left OK after disposal cannot mutate overlay focus quality dialog or control")
    video.state = "paused"
    press("play")
    settle(350)
    check(video.state = "paused" and video.control = "stop" and video.CallFunc("fixtureOverlay").fadeControl = "stop", "disposed paused wrapper cannot resume from later remote Play")
    video.state = "playing"
    video.CallFunc("fixtureDisposedAction", 2)
    check(video.control = "stop" and video.CallFunc("fixtureOverlay").fadeControl = "stop", "direct disposed Play action cannot replace stop")
    video.qualityOptions = ["720p60", "480p30"]
    video.CallFunc("fixtureDisposedAction", 3)
    check(not video.CallFunc("fixtureOverlay").qualityVisible and m.scene.dialog = invalid and video.control = "stop", "direct disposed Quality action cannot open its valid quality dialog")
    check(hero().active.IsSameNode(player) and player.CallFunc("fixturePlayer").exitPending and manager.busy and manager.CallFunc("fixtureManager").currentId = id and worker.state = "run", "later disposed inputs preserve the same pending cleanup owner and navigation")
    video.CallFunc("fixtureExitAgain")
    check(hero().active.IsSameNode(player) and manager.CallFunc("fixtureManager").currentId = id and worker.stopRequested and worker.control = "run", "duplicate live Exit consumes the pending action without pop or forced Task stop")
    worker.result = cleanupFor(id)
    check(manager.busy and hero().active.IsSameNode(player), "on-screen Exit final flags alone cannot acknowledge running Task")
    worker.state = "stop"
    check(manager.busy and hero().active.IsSameNode(player), "on-screen Exit actual Task STOP still requires attached Video STOP")
    video.state = "stopped"
    settle(60)
    check(not manager.busy and hero().active.id = "Following" and player.GetParent() = invalid, "on-screen Exit restores Following only after actual Task Video and flags ACK")

    manager = m.scene.CallFunc("fixtureNewManager")
    player = openPlayer(true)
    if player = invalid
        finishMain(screen)
        return
    end if
    owned = manager.CallFunc("fixtureManager")
    worker = owned.worker
    id = owned.currentId
    worker.ready = readyFor(id)
    video = player.CallFunc("fixturePlayer").video
    video.state = "playing"
    selectLiveExit(video)
    manager.CallFunc("fixtureTimeout")
    check(manager.busy and manager.cleanupBlocked and video.state = "playing" and hero().active.IsSameNode(player), "blocked on-screen Exit keeps playing Video attached despite requested stop")
    video.CallFunc("fixtureExitAgain")
    check(hero().active.IsSameNode(player) and not player.backPressed and not m.exitRequested, "duplicate blocked on-screen Exit cannot bypass actual Video STOP guard")
    video.state = "stopped"
    settle(60)
    check(hero().active.id = "Following" and player.GetParent() = invalid, "actual Video STOP permits blocked on-screen UI exit")
    owned = manager.CallFunc("fixtureManager")
    check(manager.busy and manager.cleanupBlocked and owned.worker.IsSameNode(worker) and owned.video.IsSameNode(video) and worker.state = "run", "blocked on-screen departure retains hung Task and stopped Video without cleanup claim")
    check(manager.CallFunc("startSession", descriptor()) = "", "on-screen blocked departure cannot start another writer")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    check(not manager.busy and manager.cleanupBlocked and manager.CallFunc("fixtureManager").worker = invalid, "late safe ACK after on-screen departure releases only the original owner")

    manager = m.scene.CallFunc("fixtureNewManager")
    player = openPlayer(false)
    if player = invalid
        finishMain(screen)
        return
    end if
    video = player.CallFunc("fixturePlayer").video
    selectLiveExit(video)
    check(hero().active.id = "Following" and player.GetParent() = invalid and not manager.busy and not m.exitRequested, "ordinary direct live on-screen Exit returns normally without local ownership")

    for cycle = 1 to 2
        player = openPlayer(true)
        if player = invalid
            finishMain(screen)
            return
        end if
        manager = m.scene.localPlaybackSession
        owned = manager.CallFunc("fixtureManager")
        worker = owned.worker
        id = owned.currentId
        worker.ready = readyFor(id)
        settle(60)
        state = player.CallFunc("fixturePlayer")
        video = state.video
        check(video <> invalid and video.control = "play" and manager.busy, "actual Player starts its attached wrapper")
        video.state = "playing"
        hero().menu.SetFocus(true)
        settle(60)
        check(hero().menu.IsInFocusChain() and not player.IsInFocusChain(), "focus deliberately escapes active Player to actual menu")
        press("back")
        settle(350)
        state = player.CallFunc("fixturePlayer")
        check(state.exitPending and manager.busy and not player.backPressed, "root-dispatched Back waits for real manager acknowledgment")
        check(not m.scene.exitApp and not m.exitRequested, "root Back never signals main exit while worker owns playback")
        check(worker.stopRequested and worker.control = "run", "root Back cooperatively stops one worker without forced controlstop")
        before = state.sessionId
        press("back")
        settle(350)
        check(player.CallFunc("fixturePlayer").sessionId = before and manager.busy and not m.scene.exitApp, "repeated root Back cannot restart exit or close app")
        check(player.CallFunc("requestBack"), "shared Back action consumes a pending repeat")
        worker.result = cleanupFor("00000000000000000000000000000000")
        worker.state = "stop"
        settle(30)
        check(manager.busy and not player.backPressed and not m.exitRequested, "stale cleanup and actual worker stop cannot acknowledge wrong namespace")
        worker.result = cleanupFor(id)
        settle(30)
        check(manager.busy and not player.backPressed, "matching cleanup still requires actual attached Video stopped")
        video.state = "stopped"
        settle(80)
        check(not manager.busy and hero().active.id = "Following" and hero().footprints = 0, "strict acknowledgment restores Following through actual Hero navigation")
        check(player.CallFunc("fixturePlayer").disposed and player.GetParent() = invalid, "old Player is actually disposed and removed after acknowledgment")
        check(player.CallFunc("requestBack") and not m.exitRequested, "disposed old Player consumes stale Back without affecting app")
    end for

    ' A start cancelled before ready also belongs to the manager until true ACK.
    player = openPlayer(true)
    if player = invalid
        finishMain(screen)
        return
    end if
    manager = m.scene.localPlaybackSession
    owned = manager.CallFunc("fixtureManager")
    worker = owned.worker
    id = owned.currentId
    hero().menu.SetFocus(true)
    press("back")
    settle(350)
    check(player.CallFunc("fixturePlayer").exitPending and worker.stopRequested and manager.busy, "root Back cancels actual pending start cooperatively")
    worker.ready = readyFor(id)
    check(player.CallFunc("fixturePlayer").video = invalid, "cancelled pending ready cannot create a wrapper")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    settle(60)
    check(not manager.busy and hero().active.id = "Following" and not m.exitRequested, "pending cancellation restores Following after real worker stop")

    ' An ordinary direct Player has no local owner to wait for; it still returns
    ' to Following and does not accidentally invoke root app exit.
    player = openPlayer(false)
    if player = invalid
        finishMain(screen)
        return
    end if
    check(player.CallFunc("fixturePlayer").sessionId = "" and not manager.busy, "direct path never claims manager ownership")
    hero().menu.SetFocus(true)
    press("back")
    settle(350)
    check(hero().active.id = "Following" and player.GetParent() = invalid and not m.exitRequested, "unowned direct root Back performs ordinary Player exit")

    ' The recent-rail special case remains first, even with an active Player.
    player = openPlayer(false)
    if player = invalid
        finishMain(screen)
        return
    end if
    rail = hero().rail
    rail.itemHasFocus = true
    hero().menu.SetFocus(true)
    press("back")
    settle(350)
    check(not rail.itemHasFocus and hero().active.IsSameNode(player) and not player.backPressed and not m.exitRequested, "recent rail Back restores active page without exiting Player")
    check(player.CallFunc("requestBack"), "physical and root paths share the exported Boolean action")
    settle(60)
    check(hero().active.id = "Following", "shared action retains ordinary navigation")

    ' The server writes exactly one terminal result. False/missing flags allow
    ' Back after actual stop while keeping unsafe resource ownership blocked.
    for each missing in [false, true]
        manager = m.scene.CallFunc("fixtureNewManager")
        player = openPlayer(true)
        if player = invalid
            finishMain(screen)
            return
        end if
        owner = manager.CallFunc("fixtureManager")
        worker = owner.worker
        id = owner.currentId
        worker.ready = readyFor(id)
        video = player.CallFunc("fixturePlayer").video
        video.state = "playing"
        manager.CallFunc("stopSession", id)
        result = cleanupFor(id)
        if missing
            result.Delete("helperClosed")
        else
            result.helperClosed = false
        end if
        worker.result = result
        worker.state = "stop"
        check(manager.busy and not player.backPressed, "one final unsafe result still waits for actual Video STOP")
        video.state = "stopped"
        settle(60)
        check(not manager.busy and manager.cleanupBlocked, "one-shot terminal unsafe stop ends UI wait without a repair result")
        owned = manager.CallFunc("fixtureManager")
        check(owned.worker.IsSameNode(worker) and owned.video.IsSameNode(video) and owned.currentId = id and worker.control = "run", "terminal unsafe manager retains actual worker Video and namespace without factory stop")
        dialog = m.scene.dialog
        check(dialog <> invalid and dialog.buttons.Count() = 1 and dialog.buttons[0] = "Back", "actual failed cleanup dialog has only Back")
        check(manager.CallFunc("startSession", descriptor()) = "", "terminal unsafe session refuses a new Roku-only owner")
        press("ok")
        settle(350)
        check(hero().active.id = "Following" and player.GetParent() = invalid and not m.exitRequested, "actual failure dialog Back leaves the acknowledged stopped unsafe owner")
        m.scene.CallFunc("fixtureLoginFinished")
        check(m.scene.localPlaybackSession.IsSameNode(manager) and manager.cleanupBlocked and not manager.CallFunc("fixtureManager").disposed, "sign-in retains the same blocked manager without clearing safety latch")
        check(manager.CallFunc("startSession", descriptor()) = "", "sign-in cannot revive a blocked manager")
        player = openPlayer(true, false)
        if player = invalid
            finishMain(screen)
            return
        end if
        check(not m.lastDescriptorEnabled and m.scene.dialog.buttons[0] = "Back", "new Player refuses Roku-only playback after unsafe owner stop")
        press("ok")
        settle(350)
        check(hero().active.id = "Following" and manager.CallFunc("fixtureManager").worker.IsSameNode(worker), "blocked unavailable dialog returns without releasing retained owner")
    end for

    ' A deadline does not fabricate Task ACK or actual Video STOP. The existing
    ' pending Back is reevaluated only after the manager observes Video STOP.
    manager = m.scene.CallFunc("fixtureNewManager")
    player = openPlayer(true)
    if player = invalid
        finishMain(screen)
        return
    end if
    owned = manager.CallFunc("fixtureManager")
    worker = owned.worker
    id = owned.currentId
    worker.ready = readyFor(id)
    video = player.CallFunc("fixturePlayer").video
    video.state = "playing"
    hero().menu.SetFocus(true)
    press("back")
    settle(350)
    manager.CallFunc("fixtureTimeout")
    settle(60)
    check(manager.busy and manager.cleanupBlocked and worker.state = "run" and video.control = "stop" and video.state = "playing", "deadline preserves actual unacknowledged worker and playing Video")
    check(player.CallFunc("fixturePlayer").exitPending and not player.backPressed and not m.exitRequested, "blocked pending Back cannot leave before actual Video STOP")
    check(m.scene.dialog <> invalid and m.scene.dialog.buttons[0] = "Back", "pre-ACK deadline preserves truthful restart dialog")
    press("ok")
    settle(350)
    check(hero().active.IsSameNode(player) and not player.backPressed and manager.busy, "actual deadline dialog Back still requires attached Video STOP")
    video.state = "stopped"
    settle(60)
    check(hero().active.id = "Following" and player.GetParent() = invalid, "late actual Video STOP completes blocked UI Back without Task ACK")
    owned = manager.CallFunc("fixtureManager")
    check(manager.busy and manager.cleanupBlocked and owned.worker.IsSameNode(worker) and owned.video.IsSameNode(video) and worker.state = "run", "UI departure retains busy hung Task owner and stopped Video")
    check(manager.CallFunc("startSession", descriptor()) = "", "blocked UI departure cannot start another writer")
    worker.result = cleanupFor(id)
    check(manager.busy, "late safe result still waits for actual Task STOP")
    worker.state = "stop"
    check(not manager.busy and manager.cleanupBlocked and manager.CallFunc("fixtureManager").worker = invalid, "late genuine Task ACK safely releases without resetting blockage")

    ' A real Roku-to-Roku quality change owns one queued Player ID. When the old
    ' Task times out, only that pending ID is retained as its cancelled UI caller.
    manager = m.scene.CallFunc("fixtureNewManager")
    player = openPlayer(true)
    if player = invalid
        finishMain(screen)
        return
    end if
    owned = manager.CallFunc("fixtureManager")
    worker = owned.worker
    id = owned.currentId
    worker.ready = readyFor(id)
    video = player.CallFunc("fixturePlayer").video
    video.state = "playing"
    replacement = descriptor()
    replacement["sourceUrl"] = "https://use14.playlist.ttvnw.net/canned/480.m3u8"
    replacement["qualityId"] = "480p30"
    replacement["metadata"] = { "videoCodec": "avc1.4D401F", "audioCodec": "mp4a.40.2", "width": 854, "height": 480, "frameRate": "30.000", "bandwidth": 1327200, "isHD": false }
    player.metadata = [{ QualityID: "480p30", url: replacement["sourceUrl"], isTransmux: true, playbackTransport: "roku-demux", localPlaybackDescriptor: replacement }]
    video.QualityChangeRequest = 0
    video.QualityChangeRequestFlag = true
    pendingId = player.CallFunc("fixturePlayer").sessionId
    check(pendingId <> id and manager.CallFunc("fixtureManager").pending.id = pendingId and worker.stopRequested, "actual local-quality replacement queues its new Player identity on the old worker")
    manager.CallFunc("fixtureTimeout")
    settle(60)
    owned = manager.CallFunc("fixtureManager")
    check(manager.busy and manager.cleanupBlocked and owned.pending = invalid and owned.blockedPendingId = pendingId, "blockage records only the actual cancelled replacement before notifying its Player")
    check(not player.CallFunc("fixturePlayer").deferred and not manager.CallFunc("canLeaveBlockedSession", pendingId), "cancelled replacement cannot play or leave before actual old Video STOP")
    press("ok")
    settle(350)
    check(player.CallFunc("fixturePlayer").exitPending and hero().active.IsSameNode(player), "cancelled replacement dialog Back waits on attached old Video STOP")
    video.state = "stopped"
    settle(60)
    check(hero().active.id = "Following" and player.GetParent() = invalid, "known cancelled replacement receives late Video STOP and completes Back")
    check(manager.busy and manager.cleanupBlocked and worker.state = "run" and manager.CallFunc("fixtureManager").worker.IsSameNode(worker), "cancelled replacement UI departure retains hung old Task without fabricated ACK")
    check(manager.CallFunc("startSession", descriptor()) = "", "cancelled replacement cannot revive another local writer")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    check(not manager.busy and manager.cleanupBlocked and manager.CallFunc("fixtureManager").worker = invalid, "cancelled replacement late safe ACK releases old owner without starting pending playback")

    ' With the failed-event observer deliberately absent, the busy observer must
    ' independently reject a deferred direct-quality start after unsafe cleanup.
    manager = m.scene.CallFunc("fixtureNewManager")
    player = openPlayer(true)
    if player = invalid
        finishMain(screen)
        return
    end if
    owned = manager.CallFunc("fixtureManager")
    worker = owned.worker
    id = owned.currentId
    worker.ready = readyFor(id)
    video = player.CallFunc("fixturePlayer").video
    video.state = "playing"
    player.metadata = [{ QualityID: "480p30", url: "https://use14.playlist.ttvnw.net/canned/direct480.m3u8", isTransmux: false, playbackTransport: "direct" }]
    player.CallFunc("fixtureSuppressSessionEvent")
    video.QualityChangeRequest = 0
    video.QualityChangeRequestFlag = true
    check(player.CallFunc("fixturePlayer").deferred and worker.stopRequested, "actual direct-quality handler waits on the current local owner")
    result = cleanupFor(id)
    result.cacheReferencesReleased = false
    worker.result = result
    worker.state = "stop"
    video.state = "stopped"
    settle(60)
    state = player.CallFunc("fixturePlayer")
    check(not manager.busy and manager.cleanupBlocked and not state.deferred and state.video.IsSameNode(video) and state.sessionId = id, "busy observer independently cancels unsafe deferred direct playback")
    check(video.control = "stop" and manager.CallFunc("fixtureManager").worker.IsSameNode(worker), "unsafe deferred quality creates no replacement wrapper or released resource")
    player.CallFunc("requestBack")
    settle(60)
    check(hero().active.id = "Following" and not m.exitRequested, "Back still leaves retained stopped unsafe owner when failure observation is absent")

    hero().menu.SetFocus(true)
    press("back")
    settle(350)
    check(m.scene.exitApp and m.exitRequested, "ordinary root Back after Player removal still requests main app exit")
    retained = manager.CallFunc("fixtureManager").worker
    m.scene.UnobserveField("exitApp")
    m.scene.CallFunc("onDestroy")
    check(manager.CallFunc("fixtureManager").disposed and manager.CallFunc("fixtureManager").worker.IsSameNode(retained) and retained.stopRequested, "permanent Hero teardown cooperates with retained unsafe manager")
    finishMain(screen)
end sub

sub finishMain(screen as object)
    screen.Close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "ROOT_BACK_FAIL_SUMMARY: "; m.failures
    end if
end sub

function openPlayer(local as boolean, choose = true as boolean) as object
    request = CreateObject("roSGNode", "TwitchContentNode")
    request.SetFields({ contentType: "LIVE", contentId: "canned", streamerLogin: "canned", streamerId: "canned", streamerDisplayName: "Canned" })
    m.scene.CallFunc("fixtureOpenPlayer", request)
    player = hero().active
    task = player.CallFunc("fixturePlayer").task
    m.lastDescriptorEnabled = task.enableRokuDemux
    node = CreateObject("roSGNode", "TwitchContentNode")
    fields = request.GetFields()
    fields.url = "https://use14.playlist.ttvnw.net/canned/720.m3u8?token=canned%2B"
    fields.streamFormat = "hls"
    fields.QualityID = "Automatic"
    fields.playbackTransport = "direct"
    if local
        fields.isTransmux = true
        fields.playbackTransport = "roku-demux"
        fields.localPlaybackDescriptor = descriptor()
    end if
    node.SetFields(fields)
    task.metadata = []
    task.response = node
    settle(60)
    if local and choose
        if not chooseLocalPlayer(player) then return invalid
    end if
    return player
end function

' Eligible combined content starts on this Roku without a prompt.
function chooseLocalPlayer(player as object) as boolean
    started = m.scene.dialog = invalid and player.CallFunc("fixturePlayer").sessionId <> "" and m.scene.localPlaybackSession.busy
    check(started, "eligible content starts one actual manager without a prompt")
    return started
end function

function descriptor() as object
    return { "version": 1, "sourceUrl": "https://use14.playlist.ttvnw.net/canned/720.m3u8?token=canned%2B", "qualityId": "720p60", "approvedOrigins": ["https://use14.playlist.ttvnw.net"], "metadata": { "videoCodec": "avc1.4D4020", "audioCodec": "mp4a.40.2", "width": 1280, "height": 720, "frameRate": "60.000", "bandwidth": 3322199, "isHD": true } }
end function

function readyFor(id as string) as object
    return { sessionId: id, boundPort: 49371, boundAddressText: "127.0.0.1", actualInitValidated: true, decoderApproved: true, metadata: descriptor()["metadata"] }
end function

function cleanupFor(id as string) as object
    return { sessionId: id, cleanupOk: true, listenerClosed: true, connectionClosed: true, helperClosed: true, cacheReferencesReleased: true }
end function

function hero() as object
    return m.scene.CallFunc("fixtureHero")
end function

sub selectLiveExit(video as object)
    video.SetFocus(true)
    press("up")
    settle(350)
    press("left")
    settle(350)
    press("left")
    settle(350)
    check(video.FindNode("controlOverlay").visible and video.FindNode("backFocus").visible and video.IsInFocusChain(), "real live overlay keys focus the on-screen Exit control")
    press("ok")
    settle(350)
end sub

sub press(key as string)
    print "FIXTURE_KEY:" + key
end sub

sub settle(duration as integer)
    timer = CreateObject("roTimespan")
    while timer.TotalMilliseconds() < duration
        event = Wait(10, m.port)
        if Type(event) = "roSGNodeEvent"
            if event.GetField() = "exitApp" and event.GetData() = true then m.exitRequested = true
        end if
    end while
end sub

sub check(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "ROOT_BACK_ASSERT_FAIL: " + label
    end if
end sub
