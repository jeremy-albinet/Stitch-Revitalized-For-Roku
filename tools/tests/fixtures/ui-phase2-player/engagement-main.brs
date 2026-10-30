sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: { ChatFontSize: "16" }, fixtureContentTasks: 0, emoteCache: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()

    set_setting("active_user", "viewer")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, invalid)
    check(player.callFunc("fixtureEngagement").worker = invalid, "default settings create no engagement worker")
    chat = player.callFunc("fixtureEngagement").chat
    check(not chat.forceLive and not chat.visible and countChatWorkers(chat) = 0, "missing chat preferences default to Sync and hidden with no chat or emote job")
    closePlayer(player)
    set_user_setting("chat.enabled", "false")
    set_user_setting("ChatOption", "true")
    set_user_setting("chat.hypeTrain", "true")
    set_user_setting("chat.pinnedMessages", "true")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, invalid)
    current = player.callFunc("fixtureEngagement")
    check(current.chat.visible and countChatWorkers(current.chat) = 0 and current.chat.findNode("chatStatus").text = "Chat is disabled in Settings.", "disabled startup chat opens only its notice")
    check(current.worker = invalid, "disabled processing suppresses Hype Train and pinned-message polling")
    set_user_setting("playback.watchCredit", "true")
    player.callFunc("fixtureResume", 0)
    video = waitVideo(player, video)
    current = player.callFunc("fixtureEngagement")
    check(current.worker <> invalid and current.worker.watchEnabled and not current.worker.hypeEnabled and not current.worker.pinsEnabled, "disabled chat preserves independently enabled watch credit without chat-event polling")
    closePlayer(player)
    set_user_setting("chat.enabled", "true")
    set_user_setting("ChatOption", "false")
    set_user_setting("chat.hypeTrain", "false")
    set_user_setting("chat.pinnedMessages", "false")
    set_user_setting("playback.watchCredit", "false")
    checkChatPerformancePause()

    for each timing in ["live", "sync"]
        set_user_setting("chat.timing", timing)
        showOnStartup = timing = "sync"
        if showOnStartup
            set_user_setting("ChatOption", "true")
        else
            set_user_setting("ChatOption", "false")
        end if
        player = openPlayer("LIVE")
        contentTask(player).response = playable("720p60")
        video = waitVideo(player, invalid)
        chat = player.callFunc("fixtureEngagement").chat
        check(chat.forceLive = (timing = "live") and chat.visible = showOnStartup, "actual player honors saved timing and show-on-startup true/false: " + timing)
        if not showOnStartup then check(countChatWorkers(chat) = 0, "saved false creates no hidden chat or emote job")
        chat.visible = true
        settle(50)
        check(countChatWorkers(chat) = 2, "opening chat starts only one transport and one emote loader: " + timing)
        for each job in chat.getChildren(-1, 0)
            if job.subtype() = "ChatJob" then check(job.forceLive = (timing = "live"), "new transport receives the selected timing: " + timing)
        end for
        closePlayer(player)
    end for
    set_user_setting("ChatOption", "false")

    set_user_setting("playback.watchCredit", "true")
    set_setting("active_user", "$default$")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, invalid)
    check(player.callFunc("fixtureEngagement").worker = invalid, "anonymous watch-only playback creates no reporter")
    closePlayer(player)

    set_setting("active_user", "viewer")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, invalid)
    current = player.callFunc("fixtureEngagement")
    worker = current.worker
    check(worker <> invalid and worker.watchEnabled and not worker.hypeEnabled and not current.chat.visible, "signed-in watch reporter exists with chat hidden")
    video.state = "playing"
    video.position = 10
    settle(80)
    check(worker.sample.playing and worker.sample.position = 10, "actual position and state callbacks publish watch samples")
    firstGeneration = worker.sample.generation
    firstSequence = worker.sample.sequence
    video.state = "paused"
    settle(80)
    check(not worker.sample.playing and worker.sample.sequence > firstSequence, "pause publishes a fresh non-playing sample")
    video.state = "playing"
    settle(80)
    check(worker.sample.playing, "resume permits new forward samples")

    set_user_setting("chat.hypeTrain", "true")
    current.chat.visible = true
    settle(100)
    check(worker.isSameNode(player.callFunc("fixtureEngagement").worker) and worker.hypeEnabled, "opening chat reuses the watch worker for Hype Train updates")
    set_user_setting("playback.watchCredit", "false")
    player.callFunc("fixtureResume", 0)
    publicVideo = waitVideo(player, video)
    publicState = player.callFunc("fixtureEngagement")
    check(worker.stopRequested and publicState.worker <> invalid and not publicState.worker.watchEnabled and publicState.worker.hypeEnabled, "opting out replaces the reporter with a public Hype-only worker")
    set_user_setting("playback.watchCredit", "true")
    player.callFunc("fixtureResume", 0)
    video = waitVideo(player, publicVideo)
    current = player.callFunc("fixtureEngagement")
    worker = current.worker
    check(publicState.worker.stopRequested and worker.watchEnabled, "opting back in creates a fresh reporter for identity validation")
    video.state = "playing"
    video.position = 10
    settle(80)
    firstGeneration = worker.sample.generation
    owner = current.owner
    now = createObject("roDateTime").asSeconds()
    hype = { id: "train", level: 3, percent: 18, expiresAt: now + 90&, observedAt: now, status: "active", shared: false }
    worker.response = { owner: owner, watchState: "telemetry_accepted", attemptedMinutes: 1, acceptedMinutes: 1, hypeTrain: hype }
    settle(100)
    check(player.engagementStatus.acceptedMinutes = 1 and current.chat.findNode("hypePanel").visible, "current owner updates diagnostics and the real chat banner")
    worker.response = { owner: "stale-owner", acceptedMinutes: 99, hypeTrain: invalid }
    settle(80)
    check(player.engagementStatus.acceptedMinutes = 1 and current.chat.findNode("hypePanel").visible, "a stale response owner cannot replace current engagement state")

    stoppedWorker = worker
    stoppedWorker.control = "stop"
    current.chat.visible = false
    settle(80)
    current = player.callFunc("fixtureEngagement")
    worker = current.worker
    check(worker <> invalid and not worker.isSameNode(stoppedWorker) and current.owner <> owner, "a visibility update replaces a stopped worker with a fresh owner")
    check(stoppedWorker.stopRequested and stoppedWorker.getParent() = invalid, "replacing a stopped worker detaches and destroys it")
    stoppedWorker.response = { owner: owner, acceptedMinutes: 99, hypeTrain: hype }
    settle(80)
    check(player.engagementStatus = invalid, "a stopped worker's late response observer is released")
    owner = current.owner
    current.chat.visible = true
    settle(80)

    player.callFunc("fixtureResume", 0)
    nextVideo = waitVideo(player, video)
    nextVideo.state = "playing"
    nextVideo.position = 0
    settle(80)
    check(worker.isSameNode(player.callFunc("fixtureEngagement").worker) and worker.owner = owner, "wrapper replacement keeps a single channel-owned worker")
    check(worker.sample.generation > firstGeneration and worker.sample.position = 0, "wrapper replacement changes the watch baseline generation")
    current.chat.visible = false
    settle(80)
    check(worker.isSameNode(player.callFunc("fixtureEngagement").worker) and not worker.hypeEnabled, "hiding chat preserves watch credit and disables Hype Train polling")

    stoppedWorker = worker
    stoppedWorker.control = "stop"
    for i = 1 to 31
        nextVideo.position = i
        settle(1000)
    end for
    current = player.callFunc("fixtureEngagement")
    worker = current.worker
    check(worker <> invalid and not worker.isSameNode(stoppedWorker) and current.owner <> owner, "advancing playback recovers a stopped worker after the bounded restart delay")
    check(stoppedWorker.stopRequested and stoppedWorker.getParent() = invalid and worker.sample.playing, "automatic recovery releases the old worker and starts fresh playing samples")
    owner = current.owner

    replacement = request("LIVE")
    replacement.streamerLogin = "otherchannel"
    replacement.streamerId = "43"
    player.contentRequested = replacement
    check(worker.stopRequested and worker.control = "stop" and worker.getParent() = invalid, "changing channel stops and detaches the old worker")
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, nextVideo)
    nextState = player.callFunc("fixtureEngagement")
    check(nextState.worker <> invalid and nextState.owner <> owner and nextState.worker.channelId = "43", "replacement channel gets its own worker and owner")
    worker.response = { owner: owner, acceptedMinutes: 99, hypeTrain: hype }
    settle(80)
    check(player.engagementStatus = invalid, "the detached worker's observer is released")
    player.callFunc("requestBack")
    check(nextState.worker.stopRequested and nextState.worker.control = "stop" and player.callFunc("fixtureEngagement").worker = invalid, "Back stops engagement immediately")
    nextState.worker.response = { owner: nextState.owner, acceptedMinutes: 99 }
    settle(80)
    check(player.engagementStatus = invalid, "late completion after Back is ignored")
    closePlayer(player)

    set_setting("active_user", "$default$")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, invalid)
    current = player.callFunc("fixtureEngagement")
    check(current.worker = invalid, "anonymous hidden-chat playback still creates no worker")
    current.chat.visible = true
    settle(80)
    current = player.callFunc("fixtureEngagement")
    check(current.worker <> invalid and not current.worker.watchEnabled and current.worker.hypeEnabled, "anonymous visible chat can request public Hype Train state")
    worker = current.worker
    current.chat.visible = false
    settle(80)
    check(player.callFunc("fixtureEngagement").worker = invalid and worker.stopRequested, "hiding Hype-only chat removes its worker")
    closePlayer(player)

    set_user_setting("chat.hypeTrain", "false")
    set_user_setting("chat.pinnedMessages", "true")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, invalid)
    current = player.callFunc("fixtureEngagement")
    current.chat.visible = true
    settle(80)
    current = player.callFunc("fixtureEngagement")
    worker = current.worker
    check(worker <> invalid and worker.pinsEnabled and not worker.watchEnabled and not worker.hypeEnabled, "anonymous pins-only chat creates a public worker")
    now = createObject("roDateTime").asSeconds()
    pin = { id: "pin-1", messageId: "message-1", userId: "202", login: "moderator", senderName: "Moderator", text: "Pinned text", sentAt: now - 10, updatedAt: now, expiresAt: invalid, observedAt: now }
    worker.response = { owner: current.owner, pinnedMessage: pin, hypeTrain: invalid }
    settle(80)
    check(current.chat.findNode("pinPanel").visible, "the current worker forwards its pin to chat")
    player.setFocus(true)
    press("down")
    settle(300)
    check(m.scene.dialog <> invalid, "the actual Down key opens the current pin")
    pinDialog = m.scene.dialog
    worker.response = { owner: current.owner, pinnedMessage: pin, hypeTrain: invalid, hypeState: "unavailable" }
    settle(80)
    check(m.scene.dialog <> invalid and m.scene.dialog.isSameNode(pinDialog), "an unrelated metadata failure leaves the current pin dialog open")
    current.chat.pinnedMessage = invalid
    check(m.scene.dialog = invalid, "removing the pin closes its dialog before playback continues")
    current.chat.pinnedMessage = pin
    worker.response = { owner: "stale-owner", pinnedMessage: invalid }
    settle(80)
    check(current.chat.findNode("pinPanel").visible, "a stale worker cannot clear the current pin")
    current.chat.visible = false
    settle(80)
    check(player.callFunc("fixtureEngagement").worker = invalid and worker.stopRequested and current.chat.pinnedMessage = invalid, "hiding pins-only chat stops its worker and clears the pin")
    closePlayer(player)

    set_setting("active_user", "viewer")
    player = openPlayer("VOD")
    player.callFunc("fixtureRead").bookmarksTask.response = {}
    contentTask(player).response = playable("720p60")
    video = waitVideo(player, invalid)
    check(player.callFunc("fixtureEngagement").worker = invalid, "recorded playback never creates a live engagement reporter")
    closePlayer(player)
    fixtureEnd()
end sub

function countChatWorkers(chat as object) as integer
    count = 0
    for each child in chat.getChildren(-1, 0)
        if child.subtype() = "ChatJob" or child.subtype() = "EmoteJob" then count++
    end for
    return count
end function

sub checkChatPerformancePause()
    set_user_setting("ChatOption", "true")
    set_user_setting("chat.hypeTrain", "true")
    set_user_setting("chat.pinnedMessages", "true")
    set_user_setting("playback.watchCredit", "true")
    for each reason in ["buffer_timeout", "source_transition", "stall"]
        player = openPlayer("LIVE")
        contentTask(player).response = playable("1080p60")
        video = waitVideo(player, invalid)
        current = player.callFunc("fixtureEngagement")
        chat = current.chat
        job = invalid
        for each child in chat.getChildren(-1, 0)
            if child.subtype() = "ChatJob" then job = child
        end for
        check(job <> invalid and current.worker.watchEnabled and current.worker.hypeEnabled and current.worker.pinsEnabled, "chat and independent watch reporting start before recovery: " + reason)
        if job <> invalid
            job.connectionState = "connected"
            busyMs = 1500
            if reason = "buffer_timeout" then busyMs = 20
            job.workload = { observedAt: createObject("roDateTime").asSeconds(), windowMs: 5000, busyMs: busyMs, highWindows: 2 }
        end if
        player.callFunc("fixtureRecovery", reason)
        current = player.callFunc("fixtureEngagement")
        if reason <> "stall"
            check(not current.autoPaused and not chat.pausedForPerformance and countChatWorkers(chat) = 2, "ordinary buffering or a source transition leaves chat running: " + reason)
        else
            check(current.autoPaused and chat.pausedForPerformance and countChatWorkers(chat) = 0, "accepted stall with fresh sustained chat overload latches the session pause")
            check(current.worker <> invalid and current.worker.watchEnabled and not current.worker.hypeEnabled and not current.worker.pinsEnabled, "automatic pause keeps watch reporting and suppresses both chat metadata polls")
            check(chat.findNode("chatStatus").text = "Chat is too fast for this TV. Chat is paused for this stream.", "automatic pause explains the stopped chat")
            player.callFunc("fixtureResume", 0)
            video = waitVideo(player, video)
            current = player.callFunc("fixtureEngagement")
            check(current.autoPaused and current.chat.pausedForPerformance and countChatWorkers(current.chat) = 0, "quality wrapper replacement cannot restart paused chat")
            sameChannel = request("LIVE")
            sameChannel.streamerLogin = ucase(sameChannel.streamerLogin)
            player.contentRequested = sameChannel
            contentTask(player).response = playable("720p60")
            video = waitVideo(player, video)
            current = player.callFunc("fixtureEngagement")
            check(current.autoPaused and current.chat.pausedForPerformance and countChatWorkers(current.chat) = 0, "same-channel content rebuild preserves the pause regardless of login case")
            replacement = request("LIVE")
            replacement.streamerLogin = "anotherchannel"
            replacement.streamerId = "43"
            player.contentRequested = replacement
            contentTask(player).response = playable("1080p60")
            video = waitVideo(player, video)
            current = player.callFunc("fixtureEngagement")
            check(not current.autoPaused and not current.chat.pausedForPerformance and countChatWorkers(current.chat) = 2, "a new channel starts a fresh chat session")
            check(current.worker.watchEnabled and current.worker.hypeEnabled and current.worker.pinsEnabled, "new channel restores enabled chat polling without changing watch preference")
        end if
        closePlayer(player)
    end for
    set_user_setting("ChatOption", "false")
    set_user_setting("chat.hypeTrain", "false")
    set_user_setting("chat.pinnedMessages", "false")
    set_user_setting("playback.watchCredit", "false")
end sub
