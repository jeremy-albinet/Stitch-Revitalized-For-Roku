' Real Hero, Player, ChannelPage and wrappers. Network, registry, socket and
' media-decoder I/O are inert boundaries; their ownership controllers run.
sub main()
    m.assertions = 0
    m.failures = 0
    m.port = CreateObject("roMessagePort")
    screen = CreateObject("roSGScreen")
    screen.SetMessagePort(m.port)
    m.global = screen.GetGlobalNode()
    setConstants()
    m.global.AddFields({ priorExitReason: "", fixtureRegistry: { "app/last_seen_version": "999.0.0", "app/active_user": "$default$", device_code: "canned-device", ChatOption: "true", ChatFontSize: "16", "chat.hypeTrain": "true", "chat.pinnedMessages": "true" }, fixtureHistory: [], fixtureContentTasks: 0, fixtureWrites: 0, fixtureDeletes: 0, emoteCache: {} })
    m.scene = screen.CreateScene("HeroScene")
    screen.Show()
    m.scene.CallFunc("fixtureOpenFollowing")
    settle(60)
    m.prior = hero().active
    check(m.prior.id = "Following", "actual anonymous Hero opens the pre-player page")
    runScenarios()
    m.scene.CallFunc("onDestroy")
    screen.Close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "CHANNEL_FAIL_SUMMARY: "; m.failures
    end if
end sub

sub runScenarios()
    ' Failed prerequisites return to Main's teardown and failure summary.
    for each kind in ["LIVE", "VOD", "CLIP"]
        request = channelRequest(kind)
        player = openPlayer(request)
        video = player.CallFunc("fixturePlayer").video
        chat = player.CallFunc("fixturePlayer").chat
        engagement = player.CallFunc("fixturePlayer").engagement
        if kind = "LIVE"
            check(chat.visible and chat.CallFunc("fixtureChat").job <> invalid and engagement <> invalid, "live playback owns actual chat and engagement before departure")
            check(video.width = 960 and video.viewersCount = 1234 and video.selectedQuality = "Automatic", "side chat retains viewers quality and video geometry")
        else
            check(not chat.visible and engagement = invalid, "recordings and clips retain hidden chat layout")
        end if
        original = player.contentRequested
        if not selectChannel(video, kind) then return
        page = hero().active
        verifyPage(player, page, original)
        check(chat.CallFunc("fixtureChat").disposed and chat.CallFunc("fixtureChat").job = invalid and chat.CallFunc("fixtureChat").emote = invalid, "departure explicitly closes visible or hidden chat ownership")
        if engagement <> invalid then check(engagement.stopRequested and engagement.control = "stop" and engagement.GetParent() = invalid, "departure stops and detaches the engagement worker")
        video.CallFunc("fixtureRepeatAction")
        video.channelActionsRequested = true
        player.channelRequested = channelRequest("STREAMER")
        m.scene.CallFunc("fixtureDeliverChannel", player)
        check(hero().active.IsSameNode(page) and hero().pages = 1 and hero().players = 0, "double Select disposed wrapper fields and stale root events cannot duplicate the profile")
        goBackToPrior()
    end for

    ' A valid login is enough for the actual anonymous ChannelPage query.
    request = channelRequest("VOD")
    request.streamerId = ""
    player = openPlayer(request)
    if not selectChannel(player.CallFunc("fixturePlayer").video, "VOD") then return
    check(hero().active.contentRequested.streamerId = "" and hero().active.CallFunc("fixtureChannel").task.request.params.id = "canned", "missing numeric ID uses the existing ChannelPage login contract without account login")
    goBackToPrior()

    for each kind in ["LIVE", "VOD", "CLIP"]
        request = channelRequest(kind)
        request.streamerLogin = ""
        if kind = "CLIP" then request.streamerId = ""
        if kind = "VOD" then request.streamerLogin = "bad/login"
        player = openPlayer(request)
        video = player.CallFunc("fixturePlayer").video
        check(not video.channelAvailable and not video.FindNode("channelGroup").visible, "missing or invalid query identity hides the channel action")
        video.channelActionsRequested = true
        check(hero().active.IsSameNode(player) and not player.backPressed and player.channelRequested = invalid, "forced action without identity cannot exit or route a recording ID")
        player.CallFunc("requestBack")
        settle(40)
        check(hero().active.IsSameNode(m.prior) and hero().players = 0, "missing identity still allows ordinary player Back")
    end for

    ' Overlay chat leaves full video width; replaced wrappers lose authority.
    set_user_setting("chat.layout", "overlay")
    player = openPlayer(channelRequest("LIVE"))
    oldVideo = player.CallFunc("fixturePlayer").video
    if not openActions(oldVideo, "LIVE") then return
    oldDialog = m.scene.dialog
    player.CallFunc("fixtureReplaceWrapper")
    video = player.CallFunc("fixturePlayer").video
    check(not oldVideo.IsSameNode(video) and oldVideo.CallFunc("fixtureOverlay").disposed, "quality-style wrapper replacement disposes its old action owner")
    oldVideo.channelActionsRequested = true
    oldDialog.buttonSelected = 1
    player.CallFunc("fixtureDeliverOpenChannel", oldVideo)
    check(hero().active.IsSameNode(player) and player.channelRequested = invalid and video.control = "play", "late old wrapper events cannot stop current playback")
    check(m.scene.dialog = invalid and not RW_IsPinned("canned"), "wrapper replacement closes its old dialog and rejects late pin actions")
    check(video.chatOverlayMode and video.width = 1280 and video.chatIsVisible, "overlay chat retains full video width with the channel action")
    if not selectChannel(video, "LIVE") then return
    check(hero().active.id = "ChannelPage", "replacement wrapper remote action still opens the channel")
    goBackToPrior()
    set_user_setting("chat.layout", "side")

    set_user_setting("ChatOption", "false")
    set_user_setting("playback.lowLatency", "true")
    player = openPlayer(channelRequest("LIVE"))
    relay = player.CallFunc("fixturePlayer").relay
    check(relay <> invalid and relay.control = "run", "actual lower latency controller owns a relay before ready")
    relay.status = { url: "http://127.0.0.1:49372/live.m3u8" }
    video = player.CallFunc("fixturePlayer").video
    check(video <> invalid and video.lowLatency and not video.chatIsVisible and video.FindNode("scrim").width = 1280, "relay live wrapper retains full controls width when chat is closed")
    if not selectChannel(video, "LIVE") then return
    check(hero().active.id = "ChannelPage" and relay.stopRequested and relay.control = "stop", "channel departure explicitly stops the active relay")
    goBackToPrior()
    set_user_setting("playback.lowLatency", "false")
    set_user_setting("ChatOption", "true")

    ' Returning from a recording to its retained profile never nests that same
    ' profile or loses the page/focus that preceded it.
    m.scene.CallFunc("fixtureSelectContent", channelRequest("STREAMER"), false)
    settle(40)
    profile = hero().active
    check(profile.id = "ChannelPage" and hero().footprints = 1, "real content selection opens the starting profile")
    player = openPlayer(channelRequest("CLIP"))
    if not selectChannel(player.CallFunc("fixturePlayer").video, "CLIP") then return
    check(hero().active.IsSameNode(profile) and hero().pages = 1 and hero().footprints = 1 and hero().players = 0, "same-channel profile is reused without a duplicate or phantom player")
    goBackToPrior()

    testPlayerPins()
    if m.failures > 0 then return
    testPinDuringSeek()
    if m.failures > 0 then return
    testSupersededDialog()
    if m.failures > 0 then return
    testPlayerFollows()
    if m.failures > 0 then return

    ' Local LIVE and completed VOD use their actual production manager paths.
    for each kind in ["LIVE", "VOD"]
        manager = m.scene.CallFunc("fixtureNewManager")
        player = openPlayer(channelRequest(kind), true)
        owned = manager.CallFunc("fixtureManager")
        worker = owned.worker
        id = owned.currentId
        check(worker <> invalid and id <> "" and manager.busy, "local playback has one actual manager owner")
        worker.ready = readyFor(id, kind)
        settle(40)
        video = player.CallFunc("fixturePlayer").video
        if video = invalid then throw "local wrapper did not attach"
        video.state = "playing"
        testLocalFollow(player, video, manager, worker, kind)
        if m.failures > 0 then return
        if not openActions(video, kind) then return
        if not pinFromDialog() then return
        check(RW_IsPinned("canned") and manager.busy and not worker.stopRequested and video.control = "play", "local pin preserves the active worker and attached playing Video")
        if not openActions(video, kind) then return
        if not pinFromDialog() then return
        check(not RW_IsPinned("canned") and manager.CallFunc("fixtureManager").worker.IsSameNode(worker) and video.state = "playing", "local unpin preserves the same playback session")
        if not selectChannel(video, kind) then return
        check(hero().active.IsSameNode(player) and player.CallFunc("fixturePlayer").exitPending and manager.busy and player.channelRequested = invalid, "local channel action waits for the owned worker and Video")
        if not hero().active.IsSameNode(player) then exit for
        check(worker.stopRequested and worker.control = "run" and video.control = "stop" and not video.visible, "local channel action cooperates with worker and hides stopped video")
        check(player.CallFunc("fixturePlayer").chat.CallFunc("fixtureChat").disposed and player.CallFunc("fixturePlayer").engagement = invalid, "local wait already closes chat and engagement")
        snapshot = video.CallFunc("fixtureOverlay")
        video.CallFunc("fixtureRepeatAction")
        video.channelActionsRequested = true
        press("play")
        settle(250)
        check(video.control = "stop" and video.CallFunc("fixtureOverlay").fade = "stop" and snapshot.disposed, "disposed live or recorded wrapper cannot replay or restart fade during cleanup")
        worker.result = cleanupFor("00000000000000000000000000000000")
        check(manager.busy and hero().active.IsSameNode(player), "stale cleanup acknowledgment cannot publish a channel request")
        worker.result = cleanupFor(id)
        check(manager.busy and hero().active.IsSameNode(player), "cleanup flags alone cannot leave a running worker")
        worker.state = "stop"
        check(manager.busy and hero().active.IsSameNode(player), "worker STOP alone cannot leave the attached playing Video")
        video.state = "stopped"
        settle(40)
        check(not manager.busy and hero().active.id = "ChannelPage" and hero().players = 0, "matching flags Task STOP and Video STOP release profile navigation once")
        goBackToPrior()
    end for

    ' A blocked owner permits UI departure only when its actual Video stops;
    ' it retains the worker and safety latch after the profile opens.
    if m.failures = 0
        manager = m.scene.CallFunc("fixtureNewManager")
        player = openPlayer(channelRequest("LIVE"), true)
        owned = manager.CallFunc("fixtureManager")
        worker = owned.worker
        id = owned.currentId
        worker.ready = readyFor(id, "LIVE")
        video = player.CallFunc("fixturePlayer").video
        video.state = "playing"
        if not selectChannel(video, "LIVE") then return
        manager.CallFunc("fixtureTimeout")
        check(manager.busy and manager.cleanupBlocked and hero().active.IsSameNode(player) and player.channelRequested = invalid, "cleanup timeout preserves the blocked active owner before actual Video STOP")
        player.CallFunc("requestBack")
        check(hero().active.IsSameNode(player), "Back repeat cannot bypass blocked channel cleanup")
        video.state = "stopped"
        settle(40)
        check(hero().active.id = "ChannelPage" and manager.busy and manager.cleanupBlocked, "blocked UI can leave only after real Video STOP without claiming worker cleanup")
        check(manager.CallFunc("fixtureManager").worker.IsSameNode(worker) and manager.CallFunc("startSession", liveDescriptor()) = "", "profile departure retains unsafe worker ownership and refuses another writer")
        worker.result = cleanupFor(id)
        worker.state = "stop"
        check(not manager.busy and manager.cleanupBlocked, "late genuine acknowledgment releases owner without clearing cleanup blockage")
        goBackToPrior()
    end if
end sub

' The StandardMessageDialog selection is the explicit simulator boundary.
' Wrapper navigation is still driven by remote keys; these tests do not claim
' native hardware dialog focus or authenticated Twitch mutation validation.
sub testPlayerFollows()
    set_setting("active_user", "alice")
    set_user_setting("access_token", "canned-token")
    set_user_setting("login", "alice")
    m.scene.CallFunc("fixtureAccountChanged")
    m.prior = hero().active
    originalFollowingTask = m.prior.CallFunc("fixtureFollowingTask")
    originalFollowingTask.response = populatedFollowing("canned")
    rows = m.prior.FindNode("homeRowList")
    check(rows.visible and rows.numRows = 1 and rows.content.GetChild(0).GetChild(0).streamerLogin = "canned", "retained Following starts with an actual populated channel row")
    player = openPlayer(channelRequest("LIVE"))
    before = player.CallFunc("fixturePlayer")
    video = before.video
    chatJob = before.chat.CallFunc("fixtureChat").job
    player.CallFunc("fixtureFollowDebts")
    contentTasks = m.global.fixtureContentTasks
    if not openActions(video, "LIVE") then return
    dialog = m.scene.dialog
    status = player.CallFunc("fixturePlayer").followTask
    timer = player.CallFunc("fixturePlayer").followTimer
    check(dialog.buttons[0] = "Open channel" and dialog.buttons[1] = "Pin streamer" and dialog.buttons[2] = "Check follow status" and dialog.buttons[3] = "Cancel", "signed-in unknown status leaves stable Open Pin Check Cancel identities")
    check(status.functionName = "getPlayerFollowState" and status.request.params.id = "987654" and status.request.params.login = "canned" and status.control = "run", "status Task uses broadcaster identity separately from recording identity")
    dialog.buttonSelected = 2
    check(player.CallFunc("fixturePlayer").followTask.IsSameNode(status), "selection during unknown status neither duplicates a query nor starts a mutation")
    status.response = followState(false)
    check(status.control = "stop" and status.followStopRequested and timer.control = "stop" and player.CallFunc("fixturePlayer").followTask = invalid, "completed status destroys Task and stops its timeout")
    check(m.scene.dialog.IsSameNode(dialog) and dialog.buttons[2] = "Check follow status" and video.control = "play", "asynchronous state cannot relabel or replace the focused dialog button")
    dialog.buttonSelected = 2
    ready = m.scene.dialog
    check(not ready.IsSameNode(dialog) and ready.buttons[2] = "Follow" and player.CallFunc("fixturePlayer").followTask = invalid, "explicit refresh creates a Follow menu using verified state without another read")
    player.CallFunc("fixtureDeliverClosed", dialog)
    dialog.buttonSelected = 2
    check(m.scene.dialog.IsSameNode(ready) and player.CallFunc("fixturePlayer").followTask = invalid, "stale closed dialog events cannot close or act on the refreshed dialog")
    ready.buttonSelected = 2
    write = player.CallFunc("fixturePlayer").followTask
    check(write.functionName = "setPlayerFollowState" and write.request.params.following and write.request.params.viewerId = "101" and write.request.params.id = "987654", "explicit Follow starts one owned write with verified viewer and broadcaster")
    ready.buttonSelected = 2
    check(player.CallFunc("fixturePlayer").followTask.IsSameNode(write), "repeated Follow selection cannot start a second mutation")
    check(not m.prior.followRefreshPending and m.prior.CallFunc("fixtureFollowingTask").IsSameNode(originalFollowingTask), "in-flight mutation leaves retained Following and task budget untouched")
    write.response = followState(true)
    check(m.prior.followRefreshPending and m.prior.CallFunc("fixtureFollowingTask").IsSameNode(originalFollowingTask), "verified mutation defers retained Following reload until focus returns")
    check(ready.buttons[2] = "Follow" and m.scene.dialog.IsSameNode(ready), "mutation completion preserves immutable button identity until explicit refresh")
    ready.buttonSelected = 2
    check(m.scene.dialog.buttons[2] = "Unfollow", "explicit refresh displays Unfollow only after verified mutation success")
    m.scene.dialog.buttonSelected = 2
    write = player.CallFunc("fixturePlayer").followTask
    check(not write.request.params.following and write.functionName = "setPlayerFollowState", "current Unfollow selection requests only unfollow")
    write.response = followState(false)
    m.scene.dialog.buttonSelected = 2
    check(m.scene.dialog.buttons[2] = "Follow", "verified unfollow refreshes back to Follow")
    m.scene.dialog.buttonSelected = 2
    write = player.CallFunc("fixturePlayer").followTask
    write.response = invalid
    check(player.CallFunc("fixturePlayer").followCache = invalid and m.scene.dialog.message[1].Instr("Couldn't confirm") >= 0, "write failure becomes unknown with readable error rather than optimistic state")
    m.scene.dialog.buttonSelected = 2
    retry = player.CallFunc("fixturePlayer").followTask
    check(retry.functionName = "getPlayerFollowState", "retry after failure is read-only and cannot repeat a mutation")
    player.CallFunc("fixtureExpireFollow", player.CallFunc("fixturePlayer").followTimer)
    check(retry.control = "stop" and player.CallFunc("fixturePlayer").followTask = invalid and player.CallFunc("fixturePlayer").followTimer = invalid, "timeout stops and destroys the worker and timer")
    retry.response = followState(true)
    player.CallFunc("fixtureDeliverFollow", retry)
    check(player.CallFunc("fixturePlayer").followCache = invalid, "late timed-out response cannot apply state")
    m.scene.dialog.buttonSelected = 2
    current = player.CallFunc("fixturePlayer").followTask
    player.CallFunc("fixtureDeliverFollow", retry)
    check(player.CallFunc("fixturePlayer").followTask.IsSameNode(current) and current.control = "run", "old response event cannot cancel a newer request generation")
    current.response = invalid
    m.scene.dialog.buttonSelected = 3
    after = player.CallFunc("fixturePlayer")
    check(after.video.IsSameNode(video) and video.control = "play" and video.IsInFocusChain() and after.chat.IsSameNode(before.chat) and after.chat.CallFunc("fixtureChat").job.IsSameNode(chatJob), "follow unfollow failure and timeout preserve Video chat transport and restored focus")
    check(after.engagement.IsSameNode(before.engagement) and after.relay = before.relay and after.sessionId = before.sessionId and after.recovery = 1 and after.reconnect = 2 and after.charges = 3, "follow menu preserves engagement session and recovery debt budgets")
    check(m.global.fixtureContentTasks = contentTasks and not video.QualityChangeRequestFlag and video.selectedQuality = "Automatic", "follow state work never reloads playback or changes quality")
    player.CallFunc("requestBack")
    settle(40)
    check(hero().active.IsSameNode(m.prior) and not m.prior.followRefreshPending and not m.prior.CallFunc("fixtureFollowingTask").IsSameNode(originalFollowingTask), "Back refreshes the retained Following page once without retaining a Player")
    refreshed = m.prior.CallFunc("fixtureFollowingTask")
    refreshed.response = { liveFollows: [], offlineFollows: [] }
    pageStatus = m.prior.FindNode("status")
    check(rows.numRows = 0 and rows.content.GetChildCount() = 0, "valid empty dirty refresh removes every retained channel row")
    check(pageStatus.state = "empty" and pageStatus.visible and pageStatus.actions.Count() = 1 and pageStatus.actions[0] = "Go to Browse" and pageStatus.IsInFocusChain(), "empty refresh keeps its Browse action and status focus without stale channels")

    m.scene.FindNode("MenuBar").SetFocus(true)
    m.prior.followRefreshPending = true
    m.prior.SetFocus(true)
    retry = m.prior.CallFunc("fixtureFollowingTask")
    check(not retry.IsSameNode(refreshed) and not m.prior.followRefreshPending and pageStatus.state = "loading", "dirty focus from the empty page starts one fresh Following request")
    retry.response = invalid
    check(pageStatus.state = "error" and pageStatus.actions[0] = "Try again" and pageStatus.IsInFocusChain() and rows.numRows = 0 and rows.content.GetChildCount() = 0, "failed refresh retains truthful error and retry focus without resurrecting old rows")
    pageStatus.actionSelected = 0
    recovered = m.prior.CallFunc("fixtureFollowingTask")
    check(not recovered.IsSameNode(retry) and pageStatus.state = "loading", "actual status retry loads Following again after the empty refresh error")
    recovered.response = populatedFollowing("recovered")
    check(rows.visible and rows.numRows = 1 and rows.content.GetChildCount() = 1 and rows.content.GetChild(0).GetChild(0).streamerLogin = "recovered", "nonempty recovery restores only the newly returned channel row")
    check(pageStatus.state = "hidden" and not pageStatus.visible and rows.IsInFocusChain(), "nonempty recovery hides the status panel and restores row focus")

    for each scenario in ["cancel", "account", "signout", "token", "stream", "wrapper", "generation", "superseded", "destroy"]
        player = openPlayer(channelRequest("CLIP"))
        video = player.CallFunc("fixturePlayer").video
        if not openActions(video, "CLIP") then return
        dialog = m.scene.dialog
        status = player.CallFunc("fixturePlayer").followTask
        if scenario = "cancel"
            dialog.buttonSelected = 3
        else if scenario = "account"
            set_setting("active_user", "bob")
        else if scenario = "signout"
            set_setting("active_user", "$default$")
        else if scenario = "token"
            set_user_setting("access_token", "changed-token")
        else if scenario = "stream"
            player.contentRequested = channelRequest("LIVE")
        else if scenario = "wrapper"
            player.CallFunc("fixtureReplaceWrapper")
        else if scenario = "generation"
            request = status.request
            request.generation++
            status.request = request
        else if scenario = "superseded"
            replacement = CreateObject("roSGNode", "StandardMessageDialog")
            replacement.buttons = ["Continue"]
            m.scene.dialog = replacement
        else
            player.CallFunc("onDestroy")
        end if
        status.response = followState(true)
        player.CallFunc("fixtureDeliverFollow", status)
        if scenario <> "generation" then dialog.buttonSelected = 2
        check(player.CallFunc("fixturePlayer").followCache = invalid and player.CallFunc("fixturePlayer").followTask = invalid and status.control = "stop", scenario + " rejects late status actions and destroys old worker")
        if scenario = "superseded" then check(m.scene.dialog.IsSameNode(replacement), "superseded follow response leaves the replacement dialog and its focus alone")
        if scenario = "account" or scenario = "signout" then set_setting("active_user", "alice")
        if scenario = "token" then set_user_setting("access_token", "canned-token")
        m.scene.dialog = invalid
        player.CallFunc("fixtureCloseActions")
        player.CallFunc("requestBack")
        if scenario = "destroy" then player.backPressed = true
        settle(40)
    end for

    request = channelRequest("VOD")
    request.streamerId = ""
    request.streamerLogin = " canned "
    player = openPlayer(request)
    video = player.CallFunc("fixturePlayer").video
    if not openActions(video, "VOD") then return
    status = player.CallFunc("fixturePlayer").followTask
    check(status.request.params.id = "" and status.request.params.login = "canned", "missing broadcaster id asks one bounded login lookup without VOD id or clip slug")
    status.response = followState(false)
    m.scene.dialog.buttonSelected = 2
    m.scene.dialog.buttonSelected = 2
    write = player.CallFunc("fixturePlayer").followTask
    check(write.request.params.id = "987654" and write.request.params.id <> request.contentId, "resolved broadcaster id alone is used in follow writes")
    m.scene.dialog.buttonSelected = 3
    write.response = followState(true)
    player.CallFunc("fixtureDeliverFollow", write)
    check(write.control = "stop" and write.followStopRequested and player.CallFunc("fixturePlayer").followCache = invalid, "closing a pending mutation cancels its worker and suppresses late success")
    player.CallFunc("requestBack")
    settle(40)

    request = channelRequest("CLIP")
    request.streamerLogin = "alice"
    player = openPlayer(request)
    video = player.CallFunc("fixturePlayer").video
    if not openActions(video, "CLIP") then return
    check(m.scene.dialog.buttons[2] = "Your channel" and player.CallFunc("fixturePlayer").followTask = invalid, "own channel offers a clear inert self state without a request")
    m.scene.dialog.buttonSelected = 2
    check(player.CallFunc("fixturePlayer").followTask = invalid and video.control = "play", "self selection cannot write or interrupt playback")
    m.scene.dialog.buttonSelected = 3
    player.CallFunc("requestBack")
    settle(40)

    set_setting("active_user", "$default$")
    set_user_setting("access_token", "")
    m.scene.CallFunc("fixtureAccountChanged")
    m.prior = hero().active
    player = openPlayer(channelRequest("LIVE"))
    video = player.CallFunc("fixturePlayer").video
    if not openActions(video, "LIVE") then return
    check(m.scene.dialog.buttons[2] = "Sign in to follow" and player.CallFunc("fixturePlayer").followTask = invalid and video.control = "play", "anonymous viewers can keep watching with Open Pin and clear optional sign-in")
    m.scene.dialog.buttonSelected = 2
    settle(40)
    check(hero().active.id = "LoginPage" and hero().players = 0 and player.CallFunc("fixturePlayer").disposed, "explicit sign-in leaves through normal Player cleanup into existing account navigation")
    m.scene.CallFunc("fixtureOpenFollowing")
    m.prior = hero().active
end sub

function populatedFollowing(login as string) as object
    return { liveFollows: [{ contentType: "LIVE", contentId: "123456789", streamerId: "987654", streamerLogin: login, streamerDisplayName: login, title: "Canned live channel", viewersCount: 1234 }], offlineFollows: [] }
end function

sub testLocalFollow(player as object, video as object, manager as object, worker as object, kind as string)
    set_setting("active_user", "alice")
    set_user_setting("access_token", "canned-token")
    player.CallFunc("fixtureFollowDebts")
    id = manager.CallFunc("fixtureManager").currentId
    if not openActions(video, kind) then return
    player.CallFunc("fixturePlayer").followTask.response = followState(false)
    m.scene.dialog.buttonSelected = 2
    m.scene.dialog.buttonSelected = 2
    player.CallFunc("fixturePlayer").followTask.response = followState(true)
    m.scene.dialog.buttonSelected = 3
    after = player.CallFunc("fixturePlayer")
    check(manager.busy and manager.CallFunc("fixtureManager").worker.IsSameNode(worker) and not worker.stopRequested and manager.CallFunc("fixtureManager").currentId = id, "local follow preserves the live or VOD worker and session ownership")
    check(video.control = "play" and video.state = "playing" and after.recovery = 1 and after.reconnect = 2 and after.charges = 3, "local follow retains Video playback and recovery debt without bypassing later cleanup")
    set_setting("active_user", "$default$")
    set_user_setting("access_token", "")
end sub

function followState(following as boolean) as object
    return { account: "alice", login: "canned", id: "987654", viewerId: "101", following: following, isSelf: false }
end function

sub testSupersededDialog()
    player = openPlayer(channelRequest("VOD"))
    video = player.CallFunc("fixturePlayer").video
    if not openActions(video, "VOD") then return
    oldDialog = m.scene.dialog
    player.CallFunc("fixturePlaybackError")
    recovery = m.scene.dialog
    check(recovery <> invalid and not recovery.IsSameNode(oldDialog) and recovery.title = "Canned playback error", "playback recovery supersedes the channel dialog")
    oldDialog.buttonSelected = 1
    oldDialog.wasClosed = true
    check(not RW_IsPinned("canned") and m.scene.dialog.IsSameNode(recovery) and hero().active.IsSameNode(player), "superseded channel buttons cannot pin navigate or steal the recovery dialog")
    recovery.buttonSelected = 1
    settle(40)
    check(hero().active.IsSameNode(m.prior) and hero().players = 0, "normal recovery Back retains explicit player cleanup")
end sub

sub testPinDuringSeek()
    player = openPlayer(channelRequest("VOD"))
    video = player.CallFunc("fixturePlayer").video
    video.duration = 180
    video.position = 60
    video.state = "playing"
    press("fastforward")
    settle(250)
    before = video.CallFunc("fixtureOverlay")
    check(before.preview and before.position = 70 and video.control = "pause", "recorded channel controls retain the first-press seek preview")
    if not openActions(video, "VOD") then return
    if not pinFromDialog() then return
    after = video.CallFunc("fixtureOverlay")
    check(RW_IsPinned("canned") and after.preview and after.position = 70 and video.control = "pause", "pinning preserves an unapplied seek preview and its paused state")
    press("back")
    settle(250)
    check(not video.CallFunc("fixtureOverlay").preview and video.control = "resume" and hero().active.IsSameNode(player), "Back still cancels the seek and resumes after pinning")
    registry_delete("pins", RW_Section())
    player.CallFunc("requestBack")
    settle(40)
end sub

sub testPlayerPins()
    for each kind in ["LIVE", "VOD", "CLIP"]
        player = openPlayer(channelRequest(kind))
        state = player.CallFunc("fixturePlayer")
        video = state.video
        chat = state.chat
        job = chat.CallFunc("fixtureChat").job
        contentTasks = m.global.fixtureContentTasks
        if not openActions(video, kind) then return
        dialog = m.scene.dialog
        check(dialog.buttons[1] = "Pin streamer" and video.control = "play", "current unpinned channel offers Pin without pausing video")
        video.CallFunc("fixtureRepeatAction")
        check(m.scene.dialog.IsSameNode(dialog), "repeated channel action keeps a single dialog")
        if not pinFromDialog() then return
        check(RW_IsPinned("canned") and RW_LoadPins().Count() = 1, "actual player pin action persists one channel via shared helper")
        check(hero().active.IsSameNode(player) and player.CallFunc("fixturePlayer").video.IsSameNode(video) and video.control = "play" and video.IsInFocusChain(), "pin action retains active Video playback and focus")
        check(m.global.fixtureContentTasks = contentTasks and not video.QualityChangeRequestFlag, "pinning neither reloads content nor requests a quality change")
        if job <> invalid then check(chat.CallFunc("fixtureChat").job.IsSameNode(job) and job.control = "run", "pin action preserves the running chat transport")
        railData = railEntry("canned")
        check(railData <> invalid and railData.pinned and railData.id = "987654" and railData.displayName = "Canned", "player pin refreshes actual rail with broadcaster metadata")
        writes = m.global.fixtureWrites
        dialog.buttonSelected = 1
        check(m.global.fixtureWrites = writes and RW_IsPinned("canned"), "late duplicate pin selection cannot toggle or repeat a write")
        if not openActions(video, kind) then return
        check(m.scene.dialog.buttons[1] = "Unpin streamer" and m.scene.dialog.message[0] = "Canned · PINNED", "reopened menu refreshes current pin label and visible PINNED state")
        if not pinFromDialog() then return
        check(not RW_IsPinned("canned") and RW_LoadPins().Count() = 0 and railEntry("canned") = invalid, "actual unpin action removes the pin and refreshes the empty rail")
        check(hero().active.IsSameNode(player) and video.control = "play" and not player.backPressed and video.CallFunc("fixtureOverlay").fade = "start", "unpin preserves playback and restarts control fade")
        if not openActions(video, kind) then return
        press("back")
        settle(250)
        check(m.scene.dialog = invalid and hero().active.IsSameNode(player) and video.control = "play" and video.IsInFocusChain(), "native dialog Back closes channel actions without leaving or pausing playback")
        player.CallFunc("requestBack")
        settle(40)
    end for

    ' A menu opened for anonymous storage cannot change Alice's pins.
    player = openPlayer(channelRequest("VOD"))
    video = player.CallFunc("fixturePlayer").video
    if not openActions(video, "VOD") then return
    stale = m.scene.dialog
    writes = m.global.fixtureWrites
    set_setting("active_user", "alice")
    stale.buttonSelected = 1
    check(not RW_IsPinned("canned") and m.global.fixtureWrites = writes and video.control = "play", "old account dialog cannot pin into the new active account")
    result = RW_SetPinned({ login: "canned", displayName: "Canned", id: "987654" }, true)
    if not openActions(video, "VOD") then return
    check(m.scene.dialog.buttons[1] = "Unpin streamer", "menu reads pin state from the current account when opened")
    if not pinFromDialog() then return
    check(not RW_IsPinned("canned"), "current account unpin uses the shared account helper")
    set_setting("active_user", "$default$")
    check(not RW_IsPinned("canned"), "player account actions preserve anonymous pins independently")

    for i = 1 to RW_MaxItems()
        result = RW_SetPinned({ login: "other_" + i.ToStr(), displayName: "Other", id: i.ToStr() }, true)
    end for
    if not openActions(video, "VOD") then return
    if not pinFromDialog() then return
    check(RW_LoadPins().Count() = 12 and not RW_IsPinned("canned"), "player respects the existing pin limit without evicting channels")
    check(video.FindNode("messageText").text = "Pin limit reached (12). Unpin a channel first." and video.control = "play", "pin limit is readable while video keeps playing")
    registry_delete("pins", RW_Section())
    player.CallFunc("requestBack")
    settle(40)

    request = channelRequest("CLIP")
    request.streamerId = ""
    player = openPlayer(request)
    video = player.CallFunc("fixturePlayer").video
    if not openActions(video, "CLIP") then return
    if not pinFromDialog() then return
    check(RW_IsPinned("canned") and RW_LoadPins()[0].id = "" and RW_LoadPins()[0].login = "canned", "login-only clip pin never persists clip slug or recording ID")
    registry_delete("pins", RW_Section())
    player.CallFunc("requestBack")
    settle(40)
end sub

function pinFromDialog() as boolean
    return selectDialogButton(1, m.scene.dialog)
end function

function railEntry(login as string) as object
    for each child in hero().rail.GetChildren(-1, 0)
        if child.IsSubtype("RecentlyWatchedItem")
            if child.itemData.login = login then return child.itemData
        end if
    end for
    return invalid
end function

function channelRequest(kind as string) as object
    node = CreateObject("roSGNode", "TwitchContentNode")
    node.SetFields({ contentType: kind, contentId: "123456789", clipSlug: "RecordingSlug", streamerLogin: "canned", streamerId: "987654", streamerDisplayName: "Canned", streamerProfileImageUrl: "pkg:/images/default_banner.png", viewersCount: 1234 })
    return node
end function

function openPlayer(request as object, local = false as boolean) as object
    m.scene.CallFunc("fixtureSelectContent", request, true)
    player = hero().active
    check(player.id = "VideoPlayer", "actual content selection opens one player")
    if get_setting("active_user", "$default$") <> "$default$" then player.FindNode("bookmarksTask").response = {}
    task = player.CallFunc("fixturePlayer").task
    node = CreateObject("roSGNode", "TwitchContentNode")
    fields = request.GetFields()
    fields.url = "https://use14.playlist.ttvnw.net/canned/720.m3u8?token=canned%2B"
    fields.streamFormat = "hls"
    fields.QualityID = "Automatic"
    if local
        fields.isTransmux = true
        fields.playbackTransport = "roku-demux"
        fields.localPlaybackDescriptor = liveDescriptor()
        if request.contentType = "VOD" then fields.localPlaybackDescriptor = vodDescriptor()
    end if
    node.SetFields(fields)
    task.metadata = [{ qualityID: "Automatic", url: fields.url }, { qualityID: "720p60", url: fields.url }]
    task.response = node
    settle(40)
    return player
end function

function openActions(video as object, kind as string) as boolean
    video.SetFocus(true)
    if not video.FindNode("controlOverlay").visible
        press("ok")
        ready = waitForPlayerUi(video, "controls")
        ready = ready and video.FindNode("controlOverlay").visible and hero().active.id = "VideoPlayer" and m.scene.dialog = invalid
        check(ready, "first remote Select only reveals controls")
        if not ready then return false
    end if
    target = 6
    if kind = "LIVE" then target = 4
    for i = 1 to 7
        focused = video.CallFunc("fixtureOverlay").focused
        if focused = target then exit for
        press("right")
        if not waitForPlayerUi(video, "focus", focused) then exit for
    end for
    ready = video.FindNode("channelFocus").visible and video.FindNode("captionLabel").text = "Channel actions"
    check(ready, "remote navigation clearly captions the channel actions control")
    if not ready then return false
    press("ok")
    ready = waitForPlayerUi(video, "dialog")
    ready = ready and m.scene.dialog <> invalid and m.scene.dialog.title = "Channel actions" and video.CallFunc("fixtureOverlay").fade = "stop"
    check(ready, "actual channel dialog opens without letting controls fade")
    return ready
end function

function waitForPlayerUi(video as object, outcome as string, previousFocus = -1 as integer) as boolean
    elapsed = CreateObject("roTimespan")
    while elapsed.TotalMilliseconds() < 3000
        overlay = video.CallFunc("fixtureOverlay")
        if outcome = "controls" and video.FindNode("controlOverlay").visible then return true
        if outcome = "focus" and overlay.visible and overlay.focused <> previousFocus then return true
        if outcome = "dialog" and m.scene.dialog <> invalid
            if m.scene.dialog.title = "Channel actions" and overlay.fade = "stop" then return true
        end if
        ignored = Wait(10, m.port)
    end while
    return false
end function

function selectChannel(video as object, kind as string) as boolean
    if not openActions(video, kind) then return false
    dialog = m.scene.dialog
    if dialog = invalid then return false
    check(dialog.buttons[0] = "Open channel", "channel dialog clearly labels profile navigation")
    return selectDialogButton(0, dialog)
end function

function selectDialogButton(index as integer, dialog as object) as boolean
    ' brs-node's native dialog keys are unreliable. Supply its button event
    ' once, without a queued remote key later reaching the restored wrapper.
    if dialog = invalid
        check(false, "channel dialog is available for selection")
        return false
    end if
    dialog.buttonSelected = index
    elapsed = CreateObject("roTimespan")
    while elapsed.TotalMilliseconds() < 3000
        if m.scene.dialog = invalid then return true
        if not m.scene.dialog.IsSameNode(dialog) then return true
        ignored = Wait(10, m.port)
    end while
    check(false, "selected channel dialog closes")
    return false
end function

sub verifyPage(player as object, page as object, original as object)
    check(page.id = "ChannelPage" and hero().pages = 1 and hero().players = 0 and hero().footprints = 1, "channel replaces player without a playable back-stack entry")
    check(player.GetParent() = invalid and player.CallFunc("fixturePlayer").disposed, "root permanently disposes the finished player")
    content = page.contentRequested
    check(not content.IsSameNode(original) and content.contentType = "STREAMER" and content.contentId = "987654", "profile gets an immutable fresh broadcaster identity node")
    check(content.streamerLogin = "canned" and content.streamerId = "987654" and content.streamerDisplayName = "Canned" and content.streamerProfileImageUrl = "pkg:/images/default_banner.png", "channel identity and display metadata survive navigation")
    check(content.clipSlug = "" and content.url = "" and content.localPlaybackDescriptor = invalid and original.contentId = "123456789" and original.clipSlug = "RecordingSlug", "route omits playback and clip identifiers without mutating the original")
    check(page.CallFunc("fixtureChannel").task.request.params.id = "canned" and page.CallFunc("fixtureChannel").shell.request.params.id = "canned", "actual ChannelPage queries use broadcaster login")
end sub

sub goBackToPrior()
    page = hero().active
    press("back")
    settle(250)
    check(hero().active.IsSameNode(m.prior) and hero().footprints = 0 and hero().players = 0 and hero().pages = 0, "Back from profile restores the pre-player stack without replay")
    check(m.prior.IsInFocusChain() and not m.scene.exitApp, "Back restores pre-player focus and does not request app exit")
    if m.prior.lastFocus <> invalid then check(m.prior.lastFocus.IsInFocusChain(), "remembered pre-player child regains focus")
end sub

function liveDescriptor() as object
    return { version: 1, sourceUrl: "https://use14.playlist.ttvnw.net/canned/720.m3u8?token=canned%2B", qualityId: "720p60", approvedOrigins: ["https://use14.playlist.ttvnw.net"], metadata: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "60.000", bandwidth: 3322199, isHD: true } }
end function

function vodDescriptor() as object
    return { version: 2, mode: "vod", vodId: "123456789", usherUrl: "https://usher.ttvnw.net/vod/v2/123456789.m3u8?nauth=fixture", sourceUrl: "https://d123.cloudfront.net/vod/720.m3u8?fixture=exact%2B", qualityId: "720p60", approvedOrigin: "https://d123.cloudfront.net", metadata: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "60.000", bandwidth: 4000000, isHD: true } }
end function

function readyFor(id as string, kind as string) as object
    if kind = "VOD"
        meta = vodDescriptor().metadata
        format = twitchVariantVideoFormat({ CODECS: meta.videoCodec + "," + meta.audioCodec, RESOLUTION: meta.width.ToStr() + "x" + meta.height.ToStr(), "FRAME-RATE": meta.frameRate, BANDWIDTH: meta.bandwidth.ToStr() })
        return { sessionId: id, boundAddressText: "127.0.0.1", boundPort: 49371, metadata: meta, decoderApproved: true, actualInitValidated: true, requestedDecoderFormat: format, mode: "vod", totalDurationUs: 73760000000&, masterPath: "/vod/" + id + "/master.m3u8" }
    end if
    return { sessionId: id, boundPort: 49371, boundAddressText: "127.0.0.1", actualInitValidated: true, decoderApproved: true, metadata: liveDescriptor().metadata }
end function

function cleanupFor(id as string) as object
    return { sessionId: id, cleanupOk: true, listenerClosed: true, connectionClosed: true, helperClosed: true, cacheReferencesReleased: true }
end function

function hero() as object
    return m.scene.CallFunc("fixtureHero")
end function

sub press(key as string)
    if key = "back"
        active = hero().active
        dialog = m.scene.dialog
        video = invalid
        preview = false
        if active.id = "VideoPlayer"
            video = active.CallFunc("fixturePlayer").video
            if video <> invalid then preview = video.CallFunc("fixtureOverlay").preview
        end if
    end if
    print "FIXTURE_KEY:" + key
    if key <> "back" then return
    ' A fixed settle can expire before a loaded CI worker dispatches Back.
    ' Wait for its actual dialog, seek or navigation result; assertions below
    ' still verify playback, focus and the full stack after that result.
    elapsed = CreateObject("roTimespan")
    while elapsed.TotalMilliseconds() < 3000
        if dialog <> invalid
            if m.scene.dialog = invalid then return
        else if preview
            if not video.CallFunc("fixtureOverlay").preview then return
        else
            if not hero().active.IsSameNode(active) then return
        end if
        ignored = Wait(10, m.port)
    end while
end sub

sub settle(duration as integer)
    timer = CreateObject("roTimespan")
    while timer.TotalMilliseconds() < duration
        ignored = Wait(10, m.port)
    end while
end sub

sub check(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "CHANNEL_ASSERT_FAIL: " + label
    end if
end sub
