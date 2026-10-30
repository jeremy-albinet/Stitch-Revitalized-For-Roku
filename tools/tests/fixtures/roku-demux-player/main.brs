sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: { ChatOption: "false", ChatFontSize: "16", "playback.lowLatency": "true" }, fixtureContentTasks: 0, emoteCache: {} })
    m.scene = m.screen.createScene("RokuPlayerHost")
    m.screen.show()
    try
        testLateBindingAndOrdinaryPaths()
        testChoiceReadyAndBack()
        testNativeLiveStartupWindow()
        ' Core skips this group; crash-recovery runs it separately.
        testNativeRecoveryStartupDeadline()
        testObsoleteLiveReconnect()
        testFailedRefreshRecoveryOwnership()
        testCancelledStartAndDisposal()
        testDirectSwitch()
        testLowLatencyRelay()
        testRepeatedRetainedQualityChoices()
        testCombinedQualityWithoutDescriptor()
        testQualityRecoveryLadder()
        testMixedAutomaticRecoveryChoice()
        testFailedRetryAndRecovery()
        testSourceTransitionRecovery()
        testLiveManualQualityIntent()
        testLiveRecoveryHealth()
        testRokuStallRefundableCharge()
        testRefusalAndBlockedOwner()
        testDialogBackAndAttachRefusal()
        testCleanupFailureWhileWaiting()
        testBlockedCancelledReplacement()
        check(true, "failure-control anchor")
    catch error
        ' A failed dispatch must end this fixture before later code dereferences
        ' a Video that the real callback has not created. It still fails QA.
        fail(error.message)
    end try
    fixtureEnd()
end sub

function manualIntentAutomatic(identity as string) as object
    node = content("roku-demux", "Automatic")
    node.localPlaybackDescriptor = { qualityId: "720p60", mediaUrl: "https://fixture.invalid/fresh-auto.m3u8", bandwidth: 4000000, isHD: true, fixtureIdentity: identity }
    return node
end function

sub manualIntentPick(player as object, index as integer)
    video = player.callFunc("fixtureRead").video
    video.callFunc("fixtureQualityDialog").buttonSelected = index
    settle(60)
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
end sub

sub manualIntentRefresh(player as object, automatic as object, metadata as object)
    oldVideo = player.callFunc("fixtureRead").video
    before = calls(sessionOf(player), "start").count()
    player.callFunc("fixtureReconnect")
    task = player.callFunc("fixtureRead").reconnectTask
    check(task <> invalid, "manual intent uses actual fresh recovery request")
    if task = invalid then return
    task.metadata = metadata
    task.response = automatic
    settle(60)
    expected = before
    if automatic.playbackTransport = "roku-demux" then expected++
    check(oldVideo.control = "stop" and calls(sessionOf(player), "start").count() = expected, "manual intent refresh stops old video and preserves the exact owner path")
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
end sub

sub testLiveManualQualityIntent()
    player = openPlayer("LIVE")
    automatic = manualIntentAutomatic("initial-auto")
    selected = content("roku-demux", "1080p60")
    lower = content("roku-demux", "720p60")
    ladder = [automatic.getFields(), selected.getFields(), lower.getFields()]
    deliver(player, automatic, ladder)
    chooseRoku(player)
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
    manualIntentPick(player, 1)
    check(player.callFunc("fixtureRead").manualLiveQuality = "1080p60", "actual explicit LIVE dialog choice records manual intent")

    fallback = manualIntentAutomatic("fallback-auto")
    missing = [fallback.getFields(), lower.getFields()]
    manualIntentRefresh(player, fallback, missing)
    state = player.callFunc("fixtureRead")
    check(state.video.selectedQuality = "Automatic" and player.content.QualityID = "Automatic" and state.video.content.localPlaybackDescriptor.fixtureIdentity = "fallback-auto", "missing manual rung preserves the actual fresh safe fallback")
    check(state.manualLiveQuality = "1080p60", "temporary fallback retains desired manual LIVE intent")

    restored = content("roku-demux", "1080p60")
    restored.url = "https://fixture.invalid/restored1080.m3u8"
    restored.localPlaybackDescriptor = { qualityId: "1080p60", mediaUrl: "https://fixture.invalid/restored-combined.m3u8", bandwidth: 7000000, isHD: true, fixtureIdentity: "restored1080" }
    automatic = manualIntentAutomatic("restored-auto")
    available = [automatic.getFields(), restored.getFields(), lower.getFields()]
    before = calls(sessionOf(player), "start").count()
    player.metadata = available
    settle(40)
    check(player.callFunc("fixtureRead").video.isSameNode(state.video) and state.video.selectedQuality = "Automatic" and calls(sessionOf(player), "start").count() = before, "a newly available rung alone never upgrades playing video")
    manualIntentRefresh(player, automatic, available)
    state = player.callFunc("fixtureRead")
    check(state.video.selectedQuality = "1080p60" and player.content.QualityID = "1080p60", "restored ladder returns to explicit manual quality")
    check(state.video.content.localPlaybackDescriptor.fixtureIdentity = "restored1080" and state.video.content.localPlaybackDescriptor.bandwidth = 7000000, "restored manual intent uses fresh descriptor and metadata")
    check(state.recovery = 0 and state.reconnect = 0 and state.video.suppressStartupSeek, "manual quality matching preserves recovery state and startup suppression")

    ' An intentional recovery downshift must not later promote playback.
    state.video.qualityChangeRequest = 2
    player.callFunc("fixtureQualityEvent")
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
    check(player.callFunc("fixtureRead").manualLiveQuality = invalid, "internal deliberate downshift clears manual upgrade intent")
    manualIntentRefresh(player, automatic, available)
    check(player.callFunc("fixtureRead").video.selectedQuality = "720p60", "later recovery retains deliberate lower quality")

    manualIntentPick(player, 1)
    manualIntentRefresh(player, fallback, missing)
    sessionOf(player).event = { id: player.callFunc("fixtureRead").sessionId, status: "failed", reason: "server_failed" }
    settle(40)
    check(player.callFunc("fixtureRead").errorDialog <> invalid, "fallback failure reaches actual Try again dialog")
    player.callFunc("fixtureRetry")
    deliver(player, automatic, available)
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
    check(player.callFunc("fixtureRead").video.selectedQuality = "1080p60" and player.callFunc("fixtureRead").manualLiveQuality = "1080p60", "same-owner Try again reuses manual intent through existing preferred quality path")

    manualIntentPick(player, 0)
    check(player.callFunc("fixtureRead").manualLiveQuality = invalid, "explicit Automatic clears previous manual intent")
    manualIntentRefresh(player, automatic, available)
    check(player.callFunc("fixtureRead").video.selectedQuality = "Automatic", "recovery respects explicit Automatic after earlier manual selection")

    manualIntentPick(player, 1)
    owner = request("LIVE")
    owner.streamerLogin = "anotherfixture"
    owner.streamerId = "43"
    owner.contentId = "fixture-v2"
    player.contentRequested = owner
    settle(40)
    check(player.callFunc("fixtureRead").manualLiveQuality = invalid, "new channel request clears previous manual intent")
    ' The inert owner supplies its actual stop acknowledgement before direct play.
    sessionOf(player).busy = false
    automatic = content("direct", "Automatic")
    available = [automatic.getFields(), content("direct", "1080p60").getFields(), content("direct", "720p60").getFields()]
    deliver(player, automatic, available)
    manualIntentRefresh(player, automatic, available)
    check(player.callFunc("fixtureRead").video.selectedQuality = "Automatic", "new LIVE owner does not inherit prior manual quality")
    manualIntentPick(player, 1)
    player.contentRequested = request("VOD")
    settle(40)
    check(player.callFunc("fixtureRead").manualLiveQuality = invalid, "recorded owner clears previous manual LIVE intent")
    deliver(player, content("direct", "720p60"))
    check(player.callFunc("fixtureRead").video.isSubtype("CustomVideo"), "recorded replacement preserves its existing wrapper path")
    closePlayer(player)
end sub

function healthPlayer() as object
    player = openPlayer("LIVE")
    selected = content("roku-demux", "1080p60")
    metadata = [selected.getFields(), content("roku-demux", "720p60").getFields()]
    deliver(player, selected, metadata)
    chooseRoku(player)
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
    healthTransition(player)
    state = player.callFunc("fixtureRead")
    if state.video <> invalid then state.video.state = "playing"
    return player
end function

sub healthTransition(player as object)
    state = player.callFunc("fixtureRead")
    sessionOf(player).event = { id: state.sessionId, status: "failed", reason: "source_transition" }
    settle(20)
    state = player.callFunc("fixtureRead")
    if state.reconnectTimer = invalid then return
    player.callFunc("fixtureReconnect")
    healthRefresh(player)
end sub

sub healthRefresh(player as object)
    task = player.callFunc("fixtureRead").reconnectTask
    if task = invalid then return
    selected = content("roku-demux", "1080p60")
    task.metadata = [selected.getFields(), content("roku-demux", "720p60").getFields()]
    task.response = selected
    settle(20)
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
end sub

sub healthSample(player as object, nowSec as integer, position as float)
    video = player.callFunc("fixtureRead").video
    if video <> invalid then video.position = position
    player.callFunc("fixtureWatchdog", nowSec)
end sub

sub healthProgress(player as object, startSec as integer, startPosition as float, seconds as integer, rate = 1 as float)
    for offset = 0 to seconds step 2
        healthSample(player, startSec + offset, startPosition + offset * rate)
    end for
end sub

' Every ad break stalls the native player twice; those reconnects must be
' refundable so a long Roku-only session does not exhaust its budget.
sub testRokuStallRefundableCharge()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    ready(session, player.callFunc("fixtureRead").sessionId)
    video = player.callFunc("fixtureRead").video
    video.state = "buffering"
    settle(20)
    player.callFunc("fixtureStartupAge", 25000)
    player.callFunc("fixtureBufferTimeout")
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer <> invalid and state.reconnect = 1 and state.recovery = 1 and state.transitionCharges = 1, "Roku-only stall reconnect is a refundable charge")
    closePlayer(player)

    player = openPlayer("LIVE")
    deliver(player, content())
    video = player.callFunc("fixtureRead").video
    video.state = "buffering"
    settle(20)
    player.callFunc("fixtureBufferTimeout")
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer <> invalid and state.reconnect = 1 and state.transitionCharges = 0, "ordinary live stall reconnect keeps a permanent charge")
    closePlayer(player)
end sub

sub testLiveRecoveryHealth()
    player = healthPlayer()
    healthTransition(player)
    state = player.callFunc("fixtureRead")
    check(state.transitionCharges = 2 and state.recovery = 2 and state.reconnect = 2, "only actually scheduled transitions own refundable charges")
    video = state.video
    video.errorCode = -1
    video.errorStr = "fixture health error"
    video.state = "error"
    state = player.callFunc("fixtureRead")
    check(state.retryTimer <> invalid and state.recovery = 3 and state.transitionCharges = 2, "actual network error retains a separate shared recovery charge")
    player.callFunc("fixtureFireRetry")
    healthRefresh(player)
    video = player.callFunc("fixtureRead").video
    if video <> invalid then video.state = "playing"
    stats = player.callFunc("fixtureErrorStatistics")
    check(stats.retryCount = 1 and stats.totalErrors = 1, "actual error handler records its independent retry history")
    base = CreateObject("roDateTime").AsSeconds() + 46
    healthProgress(player, base, 100, 118)
    healthSample(player, base + 119, 219)
    state = player.callFunc("fixtureRead")
    check(state.transitionCharges = 2 and state.recovery = 3 and state.reconnect = 2, "119 healthy seconds cannot forgive transition charges")
    healthSample(player, base + 120, 220)
    state = player.callFunc("fixtureRead")
    check(state.transitionCharges = 0 and state.reconnect = 0 and state.recovery = 1, "120 healthy seconds refund only scheduled transitions and preserve actual error debt")
    stats = player.callFunc("fixtureErrorStatistics")
    check(stats.retryCount = 1 and stats.totalErrors = 1, "healthy transition refund preserves actual error handler limits and history")
    healthSample(player, base + 122, 222)
    check(player.callFunc("fixtureRead").recovery = 1, "duplicate healthy completion never refunds unrelated recovery twice")
    session = sessionOf(player)
    session.event = { id: state.sessionId, status: "failed", reason: "source_transition" }
    state = player.callFunc("fixtureRead")
    check(state.reconnect = 1 and state.recovery = 2 and state.transitionCharges = 1 and state.reconnectTimer <> invalid, "next transition starts a bounded episode retaining generic spent debt")
    if state.reconnectTimer <> invalid then check(state.reconnectTimer.duration = 1, "healthy transition episode restarts existing one-second backoff")
    player.callFunc("fixtureEventAgain")
    check(player.callFunc("fixtureRead").transitionCharges = 1, "duplicate transition cannot add another refundable charge")
    closePlayer(player)

    player = healthPlayer()
    video = player.callFunc("fixtureRead").video
    base = CreateObject("roDateTime").AsSeconds() + 46
    for offset = 0 to 16 step 2
        healthSample(player, base + offset, 100)
    end for
    state = player.callFunc("fixtureRead")
    check(state.reconnect = 2 and state.recovery = 2 and state.transitionCharges = 1 and state.reconnectTimer <> invalid, "actual stalled watchdog spends a non-transition reconnect charge")
    player.callFunc("fixtureReconnect")
    healthRefresh(player)
    player.callFunc("fixtureRead").video.state = "playing"
    healthProgress(player, base + 50, 100, 120)
    state = player.callFunc("fixtureRead")
    check(state.reconnect = 1 and state.recovery = 1 and state.transitionCharges = 0, "healthy source refund preserves the actual generic stall reconnect budget")
    closePlayer(player)

    player = healthPlayer()
    base = CreateObject("roDateTime").AsSeconds() + 46
    healthSample(player, base, 100)
    attempts = player.callFunc("fixtureRead").reconnect
    for offset = 2 to 22 step 2
        healthSample(player, base + offset, 50 + offset)
    end for
    state = player.callFunc("fixtureRead")
    check(state.reconnect = attempts and state.reconnectTimer = invalid, "backward timeline correction followed by progress does not trigger a false stall")
    check(state.transitionCharges = 1, "backward correction does not refund recovery health")
    closePlayer(player)

    for each mode in ["stalled", "noise", "pause", "buffer", "backward", "jump", "gap", "clock", "seek", "cooldown", "duplicate", "quality", "retry", "dialog", "back", "disposed", "blocked", "pending", "foreign", "inconsistent"]
        player = healthPlayer()
        session = sessionOf(player)
        video = player.callFunc("fixtureRead").video
        base = CreateObject("roDateTime").AsSeconds() + 46
        if mode = "stalled" or mode = "noise"
            rate = 0.0
            if mode = "noise" then rate = 0.1
            healthProgress(player, base, 100, 130, rate)
        else if mode = "duplicate"
            healthSample(player, base, 100)
            for duplicate = 1 to 70
                healthSample(player, base, 100 + duplicate / 100)
            end for
            healthSample(player, base + 120, 220)
        else
            healthProgress(player, base, 100, 118)
            if mode = "pause" or mode = "buffer"
                if mode = "pause" then video.state = "paused" else video.state = "buffering"
                check(player.callFunc("fixtureRead").healthVideo = invalid, "non-playing observation clears health before watchdog restarts")
                video.state = "playing"
                healthSample(player, base + 120, 220)
                healthSample(player, base + 122, 222)
            else if mode = "backward"
                video.position = 200
                healthSample(player, base + 119, 219)
                healthSample(player, base + 120, 220)
            else if mode = "jump"
                healthSample(player, base + 120, 1218)
                healthSample(player, base + 122, 1220)
            else if mode = "gap"
                healthSample(player, base + 130, 230)
                healthSample(player, base + 132, 232)
            else if mode = "clock"
                healthSample(player, base + 117, 219)
                healthSample(player, base + 120, 222)
            else if mode = "seek"
                video.recentSeekTimestamp = base + 118
                healthSample(player, base + 120, 220)
                healthSample(player, base + 138, 238)
                healthSample(player, base + 140, 240)
            else if mode = "cooldown"
                player.callFunc("fixtureCooldown", base + 118)
                healthSample(player, base + 120, 220)
                healthSample(player, base + 163, 263)
                healthSample(player, base + 165, 265)
            else if mode = "quality"
                video.QualityChangeRequest = 1
                video.QualityChangeRequestFlag = true
                ready(session, player.callFunc("fixtureRead").sessionId)
                replacement = player.callFunc("fixtureRead").video
                check(not replacement.isSameNode(video) and replacement.selectedQuality = "720p60", "actual quality replacement starts a distinct current wrapper")
                replacement.state = "playing"
                healthSample(player, base + 120, 0)
                healthSample(player, base + 122, 2)
            else if mode = "retry"
                video.errorCode = -1
                video.errorStr = "fixture pending health retry"
                video.state = "error"
                check(player.callFunc("fixtureRead").retryTimer <> invalid, "health guard uses an actual pending automatic retry")
                video.state = "playing"
                healthSample(player, base + 120, 220)
            else if mode = "dialog"
                session.event = { id: player.callFunc("fixtureRead").sessionId, status: "failed", reason: "worker_finished" }
                healthSample(player, base + 120, 220)
            else if mode = "back" or mode = "disposed"
                if mode = "back" then player.callFunc("fixtureBack") else player.callFunc("onDestroy")
                healthSample(player, base + 120, 220)
                check(player.callFunc("fixtureRead").healthVideo = invalid, "Back or disposal releases the borrowed health wrapper")
            else if mode = "blocked"
                session.cleanupBlocked = true
                healthSample(player, base + 120, 220)
            else if mode = "pending"
                session.event = { id: player.callFunc("fixtureRead").sessionId, status: "failed", reason: "source_transition" }
                player.callFunc("fixtureReconnect")
                task = player.callFunc("fixtureRead").reconnectTask
                if task <> invalid then task.response = content("roku-demux")
                video.state = "playing"
                healthSample(player, base + 120, 220)
                check(player.callFunc("fixtureRead").pendingContent <> invalid, "pending current descriptor cannot credit old ready health")
            else if mode = "foreign"
                player.callFunc("fixtureSessionIdentity", "foreign-health-owner")
                healthSample(player, base + 120, 220)
                healthSample(player, base + 122, 222)
            else if mode = "inconsistent"
                player.callFunc("fixtureRecovery", 0)
                healthSample(player, base + 120, 220)
                check(player.callFunc("fixtureRead").recovery = 0 and player.callFunc("fixtureRead").reconnect = 0, "inconsistent source accounting cannot underflow either counter")
            end if
        end if
        state = player.callFunc("fixtureRead")
        expectedCharges = 1
        if mode = "pending" then expectedCharges = 2
        check(state.transitionCharges = expectedCharges, mode + " interrupts health without forgiving transition debt")
        closePlayer(player)
    end for

    player = healthPlayer()
    for transition = 2 to 6
        healthTransition(player)
    end for
    state = player.callFunc("fixtureRead")
    check(state.transitionCharges = 6 and state.reconnect = 6 and state.recovery = 6, "six rapid transitions retain the exact existing cap")
    sessionOf(player).event = { id: state.sessionId, status: "failed", reason: "source_transition" }
    state = player.callFunc("fixtureRead")
    check(state.transitionCharges = 6 and state.reconnect = 7 and state.recovery = 7 and state.errorDialog <> invalid and state.reconnectTimer = invalid, "seventh rapid transition schedules nothing and grants no refundable charge")
    player.callFunc("fixtureRetry")
    state = player.callFunc("fixtureRead")
    check(state.transitionCharges = 0 and state.reconnect = 0 and state.recovery = 0, "actual explicit retry resets charge accounting with its existing budgets")
    closePlayer(player)

    player = healthPlayer()
    player.contentRequested = request("LIVE")
    state = player.callFunc("fixtureRead")
    check(state.transitionCharges = 0 and state.reconnect = 0 and state.recovery = 0 and state.healthVideo = invalid, "actual new-content entry clears its previous health and accounting")
    closePlayer(player)
end sub

sub testSourceTransitionRecovery()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    first = player.callFunc("fixtureRead").sessionId
    ready(session, first)
    original = player.callFunc("fixtureRead").video
    before = m.global.fixtureContentTasks
    session.event = { id: first, status: "failed", reason: "source_transition" }
    settle(40)
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer <> invalid and state.reconnect = 1 and state.recovery = 1 and state.errorDialog = invalid, "ready source transition schedules one bounded automatic reconnect")
    check(state.prepared = invalid and calls(session, "start").count() = 1 and m.global.fixtureContentTasks = before, "source transition consumes old preparation without starting or fetching a replacement early")
    ' A mutation must finish cleanly after reporting the actual missing behavior.
    if state.reconnectTimer = invalid
        closePlayer(player)
        return
    end if
    player.callFunc("fixtureEventAgain")
    check(player.callFunc("fixtureRead").reconnect = 1, "duplicate transition while scheduled consumes no second attempt")
    player.callFunc("fixtureReconnect")
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer = invalid and state.reconnectTask <> invalid and state.reconnectTask.enableRokuDemux, "actual scheduled reconnect requests a fresh opted-in LIVE descriptor")
    player.callFunc("fixtureEventAgain")
    check(m.global.fixtureContentTasks = before + 1 and player.callFunc("fixtureRead").recovery = 1, "duplicate transition during refresh starts no second fetch or budget charge")
    refreshed = content("roku-demux", "1080p60")
    refreshed.localPlaybackDescriptor = { qualityId: "1080p60", mediaUrl: "https://fixture.invalid/fresh1080.m3u8", bandwidth: 8000000, isHD: true, fixtureIdentity: "fresh-descriptor" }
    automatic = content("roku-demux", "Automatic")
    task = state.reconnectTask
    task.metadata = [automatic.getFields(), refreshed.getFields()]
    task.response = automatic
    settle(60)
    second = player.callFunc("fixtureRead").sessionId
    started = calls(session, "start")
    check(second <> first and started.count() = 2 and started[1].descriptor.qualityId = "1080p60" and started[1].descriptor.fixtureIdentity = "fresh-descriptor", "transition refresh retains selected 1080 quality using the fresh descriptor")
    check(started[0].lowLatency = true and started[1].lowLatency = true, "the lower-latency preference reaches every Roku-only session start")
    check(original.control = "stop" and player.callFunc("fixtureRead").pendingContent <> invalid and player.callFunc("fixtureRead").recovery = 1, "refresh stops the old wrapper and retains spent budget while replacement awaits ready")
    ready(session, first)
    check(calls(session, "attach").count() = 1, "stale old ready cannot attach the refreshed transition session")
    ready(session, second)
    video = player.callFunc("fixtureRead").video
    check(video.control = "play" and video.selectedQuality = "1080p60" and video.content.localPlaybackDescriptor.fixtureIdentity = "fresh-descriptor", "only fresh ready resumes selected 1080 playback")
    check(video.suppressStartupSeek and player.callFunc("fixtureRead").reconnect = 1 and player.callFunc("fixtureRead").recovery = 1, "transition recovery preserves local startup-seek suppression and finite budgets")
    closePlayer(player)

    ' A real Video error can schedule its retry before the source result lands.
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    first = player.callFunc("fixtureRead").sessionId
    ready(session, first)
    video = player.callFunc("fixtureRead").video
    video.errorCode = -1
    video.errorStr = "fixture network failure"
    video.state = "error"
    settle(40)
    state = player.callFunc("fixtureRead")
    check(state.retryTimer <> invalid and state.recovery = 1 and state.reconnect = 0, "actual Video error schedules its single existing recovery timer")
    retry = state.retryTimer
    before = m.global.fixtureContentTasks
    session.event = { id: first, status: "failed", reason: "source_transition" }
    settle(40)
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer = invalid and state.reconnectTask = invalid and state.recovery = 1 and state.reconnect = 0, "source transition preserves one actual error retry without a second timer or budget charge")
    check(state.retryTimer <> invalid and state.retryTimer.isSameNode(retry) and m.global.fixtureContentTasks = before and calls(session, "start").count() = 1, "pending actual error retry owns recovery until its timer fires")
    player.callFunc("fixtureFireRetry")
    state = player.callFunc("fixtureRead")
    check(state.retryTimer = invalid and state.reconnectTimer = invalid and state.reconnectTask <> invalid and state.reconnectTask.enableRokuDemux and m.global.fixtureContentTasks = before + 1, "actual existing retry performs exactly one fresh LIVE descriptor request")
    state.reconnectTask.metadata = [automatic.getFields(), refreshed.getFields()]
    state.reconnectTask.response = automatic
    settle(60)
    second = player.callFunc("fixtureRead").sessionId
    started = calls(session, "start")
    check(second <> first and started.count() = 2 and started[1].descriptor.qualityId = "1080p60" and started[1].descriptor.fixtureIdentity = "fresh-descriptor", "error retry after transition retains the same selected quality and fresh descriptor")
    ready(session, second)
    state = player.callFunc("fixtureRead")
    check(state.video.control = "play" and state.video.selectedQuality = "1080p60" and state.recovery = 1 and state.reconnect = 0, "one existing error retry resumes selected playback without resetting spent recovery")
    closePlayer(player)

    ' The stopped Roku-only server can also fail the Video after the transition
    ' armed its reconnect; that error must neither cancel nor repeat recovery.
    for each errorText in ["fixture network failure", "buffer:loop:demux fixture"]
        player = openPlayer("LIVE")
        session = sessionOf(player)
        deliver(player, content("roku-demux"))
        chooseRoku(player)
        first = player.callFunc("fixtureRead").sessionId
        ready(session, first)
        video = player.callFunc("fixtureRead").video
        session.event = { id: first, status: "failed", reason: "source_transition" }
        settle(40)
        timer = player.callFunc("fixtureRead").reconnectTimer
        video.errorCode = -1
        video.errorStr = errorText
        video.state = "error"
        settle(40)
        state = player.callFunc("fixtureRead")
        kept = timer <> invalid and state.reconnectTimer <> invalid
        if kept then kept = state.reconnectTimer.isSameNode(timer)
        check(kept and state.retryTimer = invalid and state.reconnect = 1 and state.recovery = 1, "Video error after a scheduled transition keeps one reconnect and one charge: " + errorText)
        check(state.errorDialog = invalid and m.scene.dialog = invalid, "Video error after a scheduled transition opens no dialog: " + errorText)
        closePlayer(player)
    end for

    for each mode in ["startup", "stale", "other", "malformed", "blocked", "exit", "deferred", "disposed", "manual", "budget"]
        player = openPlayer("LIVE")
        session = sessionOf(player)
        metadata = [content("roku-demux").getFields(), content("direct", "720p60").getFields()]
        deliver(player, content("roku-demux"), metadata)
        chooseRoku(player)
        id = player.callFunc("fixtureRead").sessionId
        if mode <> "startup" then ready(session, id)
        event = { id: id, status: "failed", reason: "source_transition" }
        if mode = "stale" then event.id = "old-identity"
        if mode = "other" then event.reason = "worker_finished"
        if mode = "malformed" then event.reason = {}
        if mode = "blocked" then session.cleanupBlocked = true
        if mode = "exit" then player.callFunc("fixtureBack")
        if mode = "deferred"
            player.callFunc("fixtureRead").video.QualityChangeRequest = 1
            player.callFunc("fixtureRead").video.QualityChangeRequestFlag = true
            settle(40)
            check(player.callFunc("fixtureRead").deferred, "transition guard fixture has an actual pending direct-quality handoff")
        end if
        if mode = "disposed" then player.callFunc("onDestroy")
        if mode = "manual"
            session.event = { id: id, status: "failed", reason: "worker_finished" }
            settle(40)
            press("ok")
            settle(160)
            check(player.callFunc("fixtureRead").pending, "transition guard fixture has an actual manual retry pending")
        end if
        if mode = "budget" then player.callFunc("fixtureRecovery", 6)
        before = m.global.fixtureContentTasks
        session.event = event
        settle(40)
        state = player.callFunc("fixtureRead")
        check(state.reconnectTimer = invalid and state.reconnectTask = invalid and m.global.fixtureContentTasks = before, mode + " transition cannot start an automatic refresh")
        if mode = "other" or mode = "malformed" or mode = "blocked" or mode = "budget"
            check(state.errorDialog <> invalid, mode + " failure retains an actionable dialog")
        end if
        if mode = "budget" then check(state.reconnect = 7 and state.recovery = 7 and calls(session, "start").count() = 1, "transition cannot exceed the existing six-attempt recovery budget")
        closePlayer(player)
    end for
end sub

sub testMixedAutomaticRecoveryChoice()
    for each mode in ["buffer", "decode"]
        player = openPlayer("LIVE")
        session = sessionOf(player)
        metadata = [
            content("direct", "Automatic").getFields()
            content("roku-demux", "1080p60").getFields()
            content("direct", "720p60").getFields()
            content("roku-demux", "480p30").getFields()
        ]
        deliver(player, content("direct", "Automatic"), metadata)
        original = player.callFunc("fixtureRead").video
        if mode = "buffer"
            for checkNumber = 1 to 6
                player.callFunc("fixtureProlongedBufferCheck")
            end for
        else
            original.errorCode = 9
            original.errorStr = "fixture media decode error"
            original.state = "error"
        end if
        settle(40)
        check(player.content.QualityID = "480p30" and player.content.localPlaybackDescriptor.qualityId = "480p30", mode + " mixed-Automatic recovery retains the exact lower local descriptor")
        check(original.control = "stop", mode + " recovery stops the failed direct wrapper")
        chooseRoku(player)
        started = calls(session, "start")
        check(started.count() = 1 and started[0].descriptor.qualityId = "480p30", mode + " recovery starts only the selected lower local descriptor")
        ready(session, player.callFunc("fixtureRead").sessionId)
        video = player.callFunc("fixtureRead").video
        check(video.control = "play" and video.selectedQuality = "480p30" and video.content.localPlaybackDescriptor.qualityId = "480p30", mode + " opted-in mixed recovery plays the preserved lower selection")
        closePlayer(player)
    end for
end sub

function recoveryMetadata() as object
    return [
        { QualityID: "Automatic", url: "http://fixture.invalid/master", playbackTransport: "direct" }
        { QualityID: "1080p60", url: "http://fixture.invalid/1080p60", playbackTransport: "direct" }
        { QualityID: "720p60", url: "http://fixture.invalid/720p60", playbackTransport: "direct" }
        { QualityID: "480p30", url: "http://fixture.invalid/480p30", playbackTransport: "direct" }
    ]
end function

sub testQualityRecoveryLadder()
    for each mode in ["buffer", "decode"]
        for each quality in ["Automatic", "720p60", "480p30"]
            player = openPlayer("LIVE")
            metadata = recoveryMetadata()
            selected = content("direct", quality)
            deliver(player, selected, metadata)
            original = player.callFunc("fixtureRead").video
            expected = 3
            if quality = "480p30" then expected = invalid
            check(sameValue(player.callFunc("fixtureLowerQuality"), expected), mode + " actual lower-quality helper respects " + quality)

            if mode = "buffer"
                for checkNumber = 1 to 5
                    player.callFunc("fixtureProlongedBufferCheck")
                end for
                check(player.callFunc("fixtureRead").video.isSameNode(original) and player.callFunc("fixtureRead").recovery = 0, "five prolonged checks preserve " + quality + " playback before recovery")
                player.callFunc("fixtureProlongedBufferCheck")
                settle(40)
            else
                original.errorCode = 9
                original.errorStr = "fixture media decode error"
                original.state = "error"
                settle(40)
            end if

            video = player.callFunc("fixtureRead").video
            check(player.content.QualityID = "480p30" and video.selectedQuality = "480p30", mode + " recovery never promotes " + quality + " to the highest rung")
            if expected <> invalid
                check(not video.isSameNode(original) and player.content.url = metadata[3].url and player.callFunc("fixtureRead").recovery = 1, mode + " recovery plays the exact lowest metadata URL using one bounded attempt")
            else
                check(video.isSameNode(original) and player.content.url = selected.url, mode + " lowest rung has no lower quality replacement")
                if mode = "decode" then check(player.callFunc("fixtureRead").retryTimer <> invalid, "lowest decode failure keeps the existing bounded retry path")
                if mode = "buffer" then check(player.callFunc("fixtureRead").recovery = 0, "lowest buffering consumes no quality recovery attempt")
            end if
            closePlayer(player)
        end for
    end for

    ' Roku Automatic retains the exact fixed rendition in its descriptor.
    ' Use that rung as the baseline instead of the Automatic option index.
    player = openPlayer("LIVE")
    session = sessionOf(player)
    metadata = []
    for each quality in ["1080p60", "720p60", "480p30"]
        metadata.push(content("roku-demux", quality).getFields())
    end for
    fixed = content("roku-demux", "720p60")
    fixed.QualityID = "Automatic"
    metadata.unshift(fixed.getFields())
    deliver(player, fixed, metadata)
    chooseRoku(player)
    ready(session, player.callFunc("fixtureRead").sessionId)
    recoveryProgress(player, 1)
    player.callFunc("fixtureRead").video.state = "buffering"
    settle(20)
    check(player.callFunc("fixtureRead").advanced and player.callFunc("fixtureRead").recovery = 0, "fixed-Automatic rebuffer recovery starts only after actual forward progress")
    check(player.callFunc("fixtureLowerQuality") = 3, "fixed Automatic lowers below its actual 720 descriptor")
    recovery = player.callFunc("fixtureDecodeRecovery")
    check(recovery.shouldRetry and recovery.action = "change_quality" and recovery.newContent.index = 3 and recovery.newContent.qualityID = "480p30", "actual decode recovery planner lowers fixed Automatic below its retained rendition")
    for checkNumber = 1 to 6
        player.callFunc("fixtureProlongedBufferCheck")
    end for
    started = calls(session, "start")
    check(started.count() = 2 and started[1].descriptor.qualityId = "480p30" and player.content.QualityID = "480p30", "sixth actual fixed-Automatic buffer check starts the truly lower descriptor")
    closePlayer(player)

    for each fixedLowest in [false, true]
        player = openPlayer("LIVE")
        selected = content("direct", "Automatic")
        metadata = [selected.getFields(), content().getFields()]
        if fixedLowest
            selected.localPlaybackDescriptor = content("roku-demux", "480p30").localPlaybackDescriptor
            metadata = recoveryMetadata()
        end if
        deliver(player, selected, metadata)
        check(player.callFunc("fixtureLowerQuality") = invalid, "single concrete or fixed-lowest Automatic offers no verified lower rung")
        recovery = player.callFunc("fixtureDecodeRecovery")
        check(recovery.action = "retry" and recovery.newContent = invalid, "single concrete or fixed-lowest decode recovery never invents a lower rung")
        original = player.callFunc("fixtureRead").video
        for checkNumber = 1 to 6
            player.callFunc("fixtureProlongedBufferCheck")
        end for
        check(player.callFunc("fixtureRead").video.isSameNode(original) and player.callFunc("fixtureRead").recovery = 0 and player.content.QualityID = "Automatic", "Automatic with no lower rung keeps its current content and recovery budget")
        closePlayer(player)
    end for
end sub

function qualityFlagEvent(port as object) as dynamic
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 1000
        event = wait(20, port)
        if type(event) = "roSGNodeEvent"
            if event.getData() = true then return event
        end if
    end while
    return invalid
end function

' A Roku start must not let a later combined rendition without a
' descriptor reach the Video node directly.
sub testCombinedQualityWithoutDescriptor()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    combined = content("combined", "720p60")
    metadata = [content("roku-demux", "1080p60").getFields(), combined.getFields()]
    deliver(player, content("roku-demux", "1080p60"), metadata)
    chooseRoku(player)
    ready(session, player.callFunc("fixtureRead").sessionId)
    video = player.callFunc("fixtureRead").video
    video.qualityChangeRequest = 1
    player.callFunc("fixtureQualityEvent")
    settle(60)
    session.busy = false
    settle(60)
    dialog = m.scene.dialog
    check(dialog <> invalid and dialog.buttons.count() = 1 and dialog.buttons[0] = "Back", "combined rendition without a descriptor shows the Back-only audio-service dialog after a Roku start")
    state = player.callFunc("fixtureRead")
    played = false
    if state.video <> invalid
        if state.video.content <> invalid then played = state.video.content.url = combined.url and state.video.control = "play"
    end if
    check(not played and calls(session, "start").count() = 1, "combined rendition without a descriptor is never played directly")
    closePlayer(player)
end sub

sub testRepeatedRetainedQualityChoices()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    metadata = []
    for each quality in ["1080p60", "720p60", "480p30"]
        item = content("roku-demux", quality).getFields()
        metadata.push(item)
    end for
    deliver(player, content("roku-demux"), metadata)
    chooseRoku(player)
    originalId = player.callFunc("fixtureRead").sessionId
    ready(session, originalId)
    video = player.callFunc("fixtureRead").video
    flagPort = createObject("roMessagePort")
    video.observeField("QualityChangeRequestFlag", flagPort)
    requestPort = createObject("roMessagePort")
    video.observeField("QualityChangeRequest", requestPort)

    ' Inspect the runtime modal through a read-only fixture export. Its real
    ' buttonSelected field invokes the unchanged wrapper handler.
    video.callFunc("fixtureQualityDialog").buttonSelected = 1
    settle(60)
    firstEvent = wait(1000, requestPort)
    firstId = player.callFunc("fixtureRead").sessionId
    started = calls(session, "start")
    check(type(firstEvent) = "roSGNodeEvent" and firstEvent.getData() = 1, "first actual dialog pick emits its selected request index")
    check(firstId <> originalId and started.count() = 2 and started[1].descriptor.qualityId = "720p60", "first pick starts the exact 720 descriptor")
    check(player.callFunc("fixtureRead").video.isSameNode(video) and not video.QualityChangeRequestFlag, "consuming the first choice clears the flag on the same retained wrapper")

    video.callFunc("fixtureQualityDialog").buttonSelected = 2
    settle(60)
    secondEvent = wait(1000, requestPort)
    secondId = player.callFunc("fixtureRead").sessionId
    started = calls(session, "start")
    secondDelivered = false
    if type(secondEvent) = "roSGNodeEvent" then secondDelivered = secondEvent.getData() = 2 and secondEvent.getRoSGNode().isSameNode(video)
    check(secondDelivered, "a second distinct pick on the retained wrapper delivers another actual event")
    secondApplied = player.callFunc("fixtureRead").video.isSameNode(video) and secondId <> firstId and started.count() = 3 and started[2].descriptor.qualityId = "480p30"
    check(secondApplied, "same retained wrapper starts the second exact 480 descriptor")
    if not secondApplied
        ' Latest-ready and stale-source checks require this replacement.
        ' Historical mutants must report the failed precondition and clean up.
        closePlayer(player)
        return
    end if
    check(not video.QualityChangeRequestFlag, "consuming the second choice also clears its retained-wrapper flag")
    check(player.content.QualityID = "480p30" and video.selectedQuality = "480p30", "second selection preserves its metadata index and selected label")

    video.QualityChangeRequestFlag = false
    settle(40)
    check(calls(session, "start").count() = 3, "a false flag notification is not a quality command")
    ready(session, firstId)
    check(player.callFunc("fixtureRead").video.isSameNode(video), "superseded first-choice ready cannot replace the retained wrapper")
    ready(session, secondId)
    replacement = player.callFunc("fixtureRead").video
    check(not replacement.isSameNode(video) and replacement.selectedQuality = "480p30" and replacement.control = "play", "only the latest exact selection publishes and plays")
    ' brs-engine dispatches the port observer after the parent clears a flag,
    ' so the queued flag notifications read false. The request index events
    ' above are stable; exact start calls prove both commands were consumed.
    ' After replacement the old node has no parent observer, letting us keep
    ' an actual true flag event to exercise the source guard without a fake.
    video.observeField("QualityChangeRequestFlag", flagPort)
    video.QualityChangeRequestFlag = true
    staleEvent = qualityFlagEvent(flagPort)
    check(type(staleEvent) = "roSGNodeEvent" and staleEvent.getData() and staleEvent.getRoSGNode().isSameNode(video), "old detached wrapper supplies a real true flag event for the source guard")
    player.callFunc("fixtureQualityEvent", staleEvent)
    check(calls(session, "start").count() = 3 and player.callFunc("fixtureRead").video.isSameNode(replacement), "an actual old-wrapper event cannot restart its replacement")
    player.callFunc("onDestroy")
    oldRequest = video.QualityChangeRequest
    oldQuality = video.selectedQuality
    video.callFunc("fixtureQualityDialog").buttonSelected = 0
    player.callFunc("fixtureQualityEvent", staleEvent)
    player.callFunc("fixtureQualityEvent")
    check(video.QualityChangeRequest = oldRequest and video.selectedQuality = oldQuality and calls(session, "start").count() = 3, "disposed wrapper and player reject late selections and quality callbacks")
    m.scene.removeChild(player)
    m.scene.dialog = invalid
    m.scene.localPlaybackSession = invalid
end sub

sub testBlockedCancelledReplacement()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    originalId = player.callFunc("fixtureRead").sessionId
    ready(session, originalId)
    player.callFunc("fixtureReconnect")
    player.callFunc("fixtureRead").reconnectTask.response = content("roku-demux")
    settle(60)
    pendingId = player.callFunc("fixtureRead").sessionId
    check(pendingId <> originalId and player.callFunc("fixtureRead").pendingContent <> invalid, "replacement descriptor has a distinct pending owned identity")
    session.cleanupBlocked = true
    session.event = { id: originalId, status: "failed" }
    settle(40)
    check(m.scene.dialog = invalid, "failed former current ID cannot act on the player's pending replacement")
    session.event = { id: pendingId, status: "cancelled" }
    settle(60)
    check(m.scene.dialog <> invalid and m.scene.dialog.buttons.count() = 1 and m.scene.dialog.buttons[0] = "Back", "matching cancelled pending ID reports cleanup blockage without retry")
    state = player.callFunc("fixtureRead")
    check(state.pendingContent = invalid and state.prepared = invalid and not state.deferred and session.busy, "blocked cancelled replacement clears pending playback without fabricating manager cleanup")
    check(state.sessionId = pendingId and calls(session, "attach").count() = 1, "blocked cancellation retains owned ID and never attaches the pending wrapper")
    closePlayer(player)
end sub

sub testDialogBackAndAttachRefusal()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("combined"))
    press("ok")
    settle(180)
    check(player.backPressed and player.state = "done" and m.scene.dialog = invalid, "the combined-format dialog's actual Back button leaves the player")
    check(calls(session, "start").count() = 0 and calls(session, "stop").count() = 0, "dialog Back never starts or stops an empty session")
    closePlayer(player)

    player = openPlayer("LIVE")
    session = sessionOf(player)
    session.allowAttach = false
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    ready(session, id)
    attached = calls(session, "attach")
    video = player.callFunc("fixtureRead").video
    check(attached.count() = 1 and not attached[0].allowed and attached[0].contentEmpty, "the actual wrapper is presented once to an explicit attach refusal")
    check(video.control <> "play" and video.content = invalid and m.scene.dialog <> invalid, "failed attach never assigns media or starts wrapper playback")
    stopped = calls(session, "stop")
    check(stopped.count() = 1 and stopped[0].id = id, "failed attach requests owned-session cleanup")
    closePlayer(player)
end sub

function request(kind as string) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields({ contentType: kind, contentId: "fixture-v1", streamerLogin: "fixturechannel", streamerDisplayName: "Fixture Channel", streamerId: "42", contentTitle: "Fixture title" })
    return node
end function

function content(transport = "direct" as string, quality = "1080p60" as string) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields({ url: "http://fixture.invalid/" + quality, QualityID: quality, streamFormat: "hls", contentTitle: "Fixture title", streamerDisplayName: "Fixture Channel", contentId: "fixture-v1", playbackTransport: transport })
    if transport = "roku-demux"
        node.isTransmux = true
        node.localPlaybackDescriptor = { qualityId: quality, mediaUrl: "https://fixture.invalid/combined.m3u8", bandwidth: 8000000, isHD: true, fixtureIdentity: "original-descriptor" }
    else if transport = "python"
        node.isTransmux = true
        node.isProxied = true
        node.ForwardQueryStringParams = false
    else if transport = "combined"
        node.isTransmux = true
    end if
    return node
end function

function openPlayer(kind as string, withOwner = true as boolean) as object
    m.scene.dialog = invalid
    session = invalid
    if withOwner then session = createObject("roSGNode", "SessionBoundary")
    m.scene.localPlaybackSession = invalid
    player = createObject("roSGNode", "VideoPlayer")
    check(player.callFunc("fixtureRead").session = invalid, "init without a scene owner leaves the session unbound")
    m.scene.localPlaybackSession = session
    m.scene.appendChild(player)
    player.setFocus(true)
    player.contentRequested = request(kind)
    settle(40)
    check(player.callFunc("fixtureRead").task <> invalid, "a real contentRequested callback creates a content task")
    return player
end function

sub closePlayer(player as object)
    player.callFunc("onDestroy")
    m.scene.removeChild(player)
    m.scene.dialog = invalid
    m.scene.localPlaybackSession = invalid
end sub

function sessionOf(player as object) as dynamic
    return player.callFunc("fixtureRead").session
end function

sub deliver(player as object, node as object, metadata = invalid as dynamic)
    task = player.callFunc("fixtureRead").task
    task.metadata = metadata
    task.response = node
    settle(60)
end sub

function calls(session as object, action as string) as object
    result = []
    for each item in session.calls
        if item.action = action then result.push(item)
    end for
    return result
end function

' Eligible combined streams start on this Roku without a prompt.
sub chooseRoku(player as object)
    state = player.callFunc("fixtureRead")
    started = state.transmuxDialog = invalid and state.chosen and state.sessionId <> ""
    check(started, "eligible combined stream starts on Roku without a prompt")
    if not started then throw "eligible combined stream did not start on Roku automatically"
end sub

sub ready(session as object, id as string)
    session.event = { id: id, status: "ready", url: "http://127.0.0.1:49371/master.m3u8", metadata: { isHD: true, bandwidth: 8000000 } }
    settle(60)
end sub

sub testLateBindingAndOrdinaryPaths()
    for each kind in ["LIVE", "VOD", "CLIP"]
        player = openPlayer(kind)
        session = sessionOf(player)
        check(session <> invalid and session.isSameNode(m.scene.localPlaybackSession), "handleContent binds the scene owner after attachment")
        check(player.callFunc("fixtureRead").task.enableRokuDemux = (kind = "LIVE" or kind = "VOD"), "LIVE and verified VOD opt into descriptor eligibility; CLIP does not")
        direct = content()
        deliver(player, direct)
        video = player.callFunc("fixtureRead").video
        check(video <> invalid and video.control = "play", "ordinary playback creates and plays its actual wrapper")
        expected = "CustomVideo"
        if kind = "LIVE" then expected = "StitchVideo"
        check(video.subtype() = expected and video.content.url = direct.url, "ordinary LIVE/VOD/CLIP retains wrapper and original URL")
        check(calls(session, "start").count() = 0 and calls(session, "attach").count() = 0, "ordinary paths never start or attach a local session")
        if kind = "LIVE"
            video.state = "buffering"
            settle(20)
            timer = player.callFunc("fixtureRead").bufferTimer
            check(timer <> invalid and timer.duration = 25, "ordinary live keeps the 25 s buffering allowance")
            video.state = "playing"
            settle(20)
        end if
        closePlayer(player)
        check(calls(session, "stop").count() = 0, "ordinary destruction never stops an empty session ID")
    end for
    player = openPlayer("LIVE", false)
    check(not player.callFunc("fixtureRead").task.enableRokuDemux, "missing scene owner leaves LIVE descriptor opt-in off")
    deliver(player, content("combined"))
    check(m.scene.dialog.buttons.count() = 1 and m.scene.dialog.buttons[0] = "Back", "combined stream without owner keeps audio-service Back-only fallback")
    closePlayer(player)
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("python"))
    check(m.scene.dialog = invalid and player.callFunc("fixtureRead").video.control = "play", "Python proxied combined content follows ordinary playback without opt-in")
    check(player.content.isProxied and not player.content.ForwardQueryStringParams and calls(session, "start").count() = 0, "optional service flags remain intact")
    closePlayer(player)
end sub

function recoveryPlayer() as object
    player = openPlayer("LIVE")
    selected = content("roku-demux", "1080p60")
    deliver(player, selected, [selected.getFields(), content("roku-demux", "720p60").getFields()])
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
    return player
end function

sub recoveryProgress(player as object, position as float)
    video = player.callFunc("fixtureRead").video
    video.state = "playing"
    settle(20)
    video.position = position
    settle(20)
end sub

sub testNativeRecoveryStartupDeadline()
    ' The Video's preparation can take time without spending its startup grace.
    for each startup in [12000, 15000]
        player = recoveryPlayer()
        video = player.callFunc("fixtureRead").video
        timer = player.callFunc("fixtureRead").bufferTimer
        check(timer <> invalid and timer.duration = 25, "prepared native owner arms its 25 second absolute deadline before buffering")
        video.state = "buffering"
        settle(20)
        player.callFunc("fixtureStartupAge", 10000)
        player.callFunc("fixtureBufferTimeout", timer)
        state = player.callFunc("fixtureRead")
        check(state.reconnect = 0 and state.recovery = 0 and state.reconnectTimer = invalid and state.reconnectTask = invalid and state.bufferTimer.duration = 15, "native startup cannot charge or replace at ten seconds")
        player.callFunc("fixtureStartupAge", startup)
        for bufferCheck = 1 to 6
            player.callFunc("fixtureProlongedBufferCheck")
        end for
        check(player.callFunc("fixtureRead").recovery = 0 and player.content.QualityID = "1080p60", "repeated buffer observations cannot downshift a native owner during its startup allowance")
        recoveryProgress(player, 1)
        state = player.callFunc("fixtureRead")
        check(state.advanced and state.bufferTimer = invalid and state.video.isSameNode(video) and state.reconnect = 0 and state.recovery = 0, "12 to 15 second startup advances on the original owner without recovery debt")
        video.state = "buffering"
        settle(20)
        timer = player.callFunc("fixtureRead").bufferTimer
        check(timer <> invalid and timer.duration = 10, "an actually advancing native owner retains its ten second rebuffer limit")
        player.callFunc("fixtureBufferTimeout", timer)
        state = player.callFunc("fixtureRead")
        check(state.reconnect = 1 and state.recovery = 1 and state.reconnectTimer <> invalid, "ten second rebuffer timeout still charges one recovery")
        closePlayer(player)
    end for

    player = recoveryPlayer()
    video = player.callFunc("fixtureRead").video
    player.callFunc("fixtureRecovery", 2)
    for each age in [10000, 15000, 24000]
        player.callFunc("fixtureStartupAge", age)
        video.state = "buffering"
        settle(20)
        timer = player.callFunc("fixtureRead").bufferTimer
        video.state = "playing"
        settle(20)
        state = player.callFunc("fixtureRead")
        check(not state.advanced and state.bufferTimer <> invalid and state.bufferTimer.isSameNode(timer), "playing at zero and state flaps retain the absolute startup timer")
        for tick = 1 to 8
            player.callFunc("fixtureWatchdog", 2000000000 + tick * 2)
        end for
        player.callFunc("fixtureBufferTimeout", timer)
        state = player.callFunc("fixtureRead")
        check(state.reconnect = 2 and state.recovery = 2 and state.reconnectTimer = invalid and state.bufferTimer.duration = (25000 - age) / 1000, "startup flaps and watchdog cannot extend the deadline or refund existing debt")
    end for
    player.callFunc("fixtureStartupAge", 25000)
    player.callFunc("fixtureBufferTimeout", player.callFunc("fixtureRead").bufferTimer)
    state = player.callFunc("fixtureRead")
    check(state.reconnect = 3 and state.recovery = 3 and state.reconnectTimer <> invalid and not state.advanced, "nonadvancing playing at zero expires at 25 seconds from original assignment")
    closePlayer(player)

    ' Each successful refresh prepares a genuinely new owner. Never-ready
    ' playback still exhausts exactly six automatic recoveries and then stops.
    player = recoveryPlayer()
    session = sessionOf(player)
    for attempt = 1 to 7
        video = player.callFunc("fixtureRead").video
        video.state = "buffering"
        settle(20)
        player.callFunc("fixtureStartupAge", 25000)
        player.callFunc("fixtureBufferTimeout", player.callFunc("fixtureRead").bufferTimer)
        state = player.callFunc("fixtureRead")
        if attempt <= 6
            expectedDelay = 2 ^ (attempt - 1)
            if expectedDelay > 16 then expectedDelay = 16
            check(state.reconnectTimer <> invalid and state.reconnectTimer.duration = expectedDelay and state.recovery = attempt and state.reconnect = attempt, "never-advancing startup retains all six finite exponential backoffs")
            if state.reconnectTimer = invalid then exit for
            player.callFunc("fixtureReconnectTimer", state.reconnectTimer)
            healthRefresh(player)
            state = player.callFunc("fixtureRead")
            check(not state.video.isSameNode(video) and state.bufferTimer.duration = 25 and not state.advanced, "automatic refresh gives only the new prepared Video a fresh startup allowance")
        else
            check(state.errorDialog <> invalid and state.reconnectTimer = invalid and state.reconnectTask = invalid and video.control = "stop" and calls(session, "start").count() = 7, "seventh startup timeout stops after exactly six replacement sessions")
        end if
    end for
    closePlayer(player)

    player = recoveryPlayer()
    oldTimer = player.callFunc("fixtureRead").bufferTimer
    video = player.callFunc("fixtureRead").video
    video.qualityChangeRequest = 1
    player.callFunc("fixtureQualityEvent")
    player.callFunc("fixtureBufferTimeout", oldTimer)
    state = player.callFunc("fixtureRead")
    check(state.pendingContent <> invalid and state.bufferTimer = invalid and state.recovery = 0, "quality preparation invalidates the previous startup timer before its new worker is ready")
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
    state = player.callFunc("fixtureRead")
    timer = state.bufferTimer
    player.callFunc("fixtureStartupAge", 25000)
    state.video.state = "buffering"
    settle(20)
    player.callFunc("fixtureBufferTimeout", oldTimer)
    state = player.callFunc("fixtureRead")
    check(state.bufferTimer <> invalid and state.bufferTimer.isSameNode(timer) and state.recovery = 0 and state.video.selectedQuality = "720p60", "stale buffer timer cannot charge the new manual quality owner")
    player.callFunc("onDestroy")
    player.callFunc("fixtureBufferTimeout", timer)
    state = player.callFunc("fixtureRead")
    check(state.disposed and state.bufferTimer = invalid and state.reconnectTask = invalid and state.reconnect = 0, "buffer timer after disposal cannot restart or charge playback")
    closePlayer(player)
end sub

sub testObsoleteLiveReconnect()
    for each mode in ["backoff", "inflight", "stall", "playing_zero", "buffer_again", "dead_worker", "stopped_worker", "source_transition", "session_changed", "manual_quality", "new_content", "back", "disposed"]
        player = recoveryPlayer()
        session = sessionOf(player)
        video = player.callFunc("fixtureRead").video
        player.callFunc("fixtureRecovery", 5)
        if mode = "source_transition"
            session.event = { id: player.callFunc("fixtureRead").sessionId, status: "failed", reason: "source_transition" }
            settle(20)
        else if mode = "stall"
            recoveryProgress(player, 1)
            player.callFunc("fixtureScheduleReconnect", "stall")
        else
            video.state = "buffering"
            settle(20)
            player.callFunc("fixtureStartupAge", 25000)
            player.callFunc("fixtureBufferTimeout", player.callFunc("fixtureRead").bufferTimer)
        end if
        state = player.callFunc("fixtureRead")
        timer = state.reconnectTimer
        check(timer <> invalid and timer.duration = 16 and state.reconnect = 6 and state.recovery = 6, "attempt six retains its sixteen second backoff and shared recovery debt")
        if timer = invalid
            closePlayer(player)
            return
        end if
        if mode = "inflight" or mode = "manual_quality" or mode = "new_content" or mode = "back" or mode = "disposed"
            player.callFunc("fixtureReconnectTimer", timer)
            task = player.callFunc("fixtureRead").reconnectTask
            check(task <> invalid, "pending recovery fetch belongs to its scheduled owner")
        end if
        tasks = m.global.fixtureContentTasks
        if mode = "playing_zero"
            video.state = "playing"
        else
            recoveryProgress(player, 4)
        end if
        if mode = "buffer_again" then video.state = "buffering"
        if mode = "dead_worker" then session.event = { id: player.callFunc("fixtureRead").sessionId, status: "failed", reason: "source_transition" }
        if mode = "stopped_worker" then session.busy = false
        if mode = "session_changed" then player.callFunc("fixtureSessionIdentity", "different-session")
        settle(20)
        if mode = "manual_quality"
            video.qualityChangeRequest = 1
            video.QualityChangeRequestFlag = true
            settle(20)
            ready(session, player.callFunc("fixtureRead").sessionId)
        else if mode = "new_content"
            player.contentRequested = request("LIVE")
            settle(20)
        else if mode = "back"
            player.callFunc("fixtureBack")
        else if mode = "disposed"
            player.callFunc("onDestroy")
        end if
        if mode = "inflight" or mode = "manual_quality" or mode = "new_content" or mode = "back" or mode = "disposed"
            task.metadata = [content("roku-demux").getFields()]
            task.response = content("roku-demux")
            settle(20)
            player.callFunc("fixtureReconnectResponse", task)
        else
            player.callFunc("fixtureReconnectTimer", timer)
        end if
        state = player.callFunc("fixtureRead")
        if mode = "backoff" or mode = "inflight" or mode = "stall"
            check(state.video.isSameNode(video) and video.control = "play" and state.reconnectTimer = invalid and state.reconnectTask = invalid and calls(session, "start").count() = 1 and m.global.fixtureContentTasks = tasks, "same ready worker and forward progress suppress obsolete recovery before fetch or apply")
            check(state.recovery = 6 and state.reconnect = 6, "resumed progress preserves spent recovery debt without an immediate health refund")
            ' An already queued event cannot dispatch the just-cancelled timer.
            player.callFunc("fixtureReconnectTimer", timer)
            check(player.callFunc("fixtureRead").reconnectTask = invalid, "late cancelled reconnect timer cannot fetch again")
        else if mode = "session_changed"
            check(state.reconnectTask = invalid and state.reconnectTimer = invalid and state.recovery = 6, "obsolete session ownership invalidates recovery without forgiving debt")
        else if mode = "manual_quality"
            check(state.video.selectedQuality = "720p60" and state.manualLiveQuality = "720p60" and state.reconnectTask = invalid and state.recovery = 6, "late refresh cannot override the new explicit manual quality owner")
            current = state.video
            player.callFunc("fixtureReconnectTimer", timer)
            check(player.callFunc("fixtureRead").video.isSameNode(current) and player.callFunc("fixtureRead").reconnectTask = invalid, "old reconnect timer cannot fetch for the new quality owner")
        else if mode = "new_content"
            check(state.task <> invalid and state.reconnectTask = invalid and state.recovery = 0 and state.reconnect = 0, "late refresh cannot apply to a new content request")
        else if mode = "back" or mode = "disposed"
            player.callFunc("fixtureReconnectTimer", timer)
            check(video.control = "stop" and player.callFunc("fixtureRead").reconnectTask = invalid and state.recovery = 6, "late recovery callbacks after Back or disposal cannot revive the owner")
        else
            check(state.reconnectTask <> invalid and state.reconnect = 6 and state.recovery = 6, "playing zero, buffering again and failed workers still dispatch required recovery")
            if state.reconnectTask <> invalid
                healthRefresh(player)
                state = player.callFunc("fixtureRead")
                check(not state.video.isSameNode(video) and video.control = "stop" and calls(session, "start").count() = 2 and state.recovery = 6, "nonhealthy owners and source transitions still apply their fresh replacement")
            end if
        end if
        closePlayer(player)
    end for

    ' A previous response/timer must not disturb a new owner's current work.
    player = recoveryPlayer()
    video = player.callFunc("fixtureRead").video
    video.state = "buffering"
    settle(20)
    player.callFunc("fixtureStartupAge", 25000)
    player.callFunc("fixtureBufferTimeout", player.callFunc("fixtureRead").bufferTimer)
    oldTimer = player.callFunc("fixtureRead").reconnectTimer
    player.callFunc("fixtureReconnectTimer", oldTimer)
    oldTask = player.callFunc("fixtureRead").reconnectTask
    player.contentRequested = request("LIVE")
    settle(20)
    deliver(player, content("roku-demux"))
    ready(sessionOf(player), player.callFunc("fixtureRead").sessionId)
    player.callFunc("fixtureRead").video.state = "buffering"
    settle(20)
    player.callFunc("fixtureStartupAge", 25000)
    player.callFunc("fixtureBufferTimeout", player.callFunc("fixtureRead").bufferTimer)
    timer = player.callFunc("fixtureRead").reconnectTimer
    player.callFunc("fixtureReconnectTimer", oldTimer)
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer <> invalid and state.reconnectTimer.isSameNode(timer) and state.reconnectTask = invalid and state.recovery = 1, "stale reconnect event cannot clear or dispatch the new owner's timer")
    player.callFunc("fixtureReconnectTimer", timer)
    task = player.callFunc("fixtureRead").reconnectTask
    player.callFunc("fixtureReconnectResponse", oldTask)
    state = player.callFunc("fixtureRead")
    check(state.reconnectTask <> invalid and state.reconnectTask.isSameNode(task) and state.recovery = 1 and state.reconnect = 1, "stale refresh response cannot destroy or retry the new owner's current request")
    closePlayer(player)
end sub

sub testFailedRefreshRecoveryOwnership()
    for each reason in ["buffer_timeout", "stall", "source_transition", "error_retry"]
        for each failure in ["invalid", "error"]
            for each phase in ["backoff", "fetch"]
                player = recoveryPlayer()
                session = sessionOf(player)
                recoveryProgress(player, 100)
                video = player.callFunc("fixtureRead").video
                video.state = "buffering"
                settle(20)
                player.callFunc("fixtureScheduleReconnect", reason)
                player.callFunc("fixtureReconnectTimer", player.callFunc("fixtureRead").reconnectTimer)
                task = player.callFunc("fixtureRead").reconnectTask
                check(task <> invalid, "original recovery dispatches before its refresh failure")
                if task = invalid
                    closePlayer(player)
                    return
                end if
                if failure = "invalid"
                    task.response = invalid
                else
                    rejected = content()
                    rejected.contentType = "ERROR"
                    task.response = rejected
                end if
                settle(20)
                state = player.callFunc("fixtureRead")
                check(state.reconnectTimer <> invalid and state.reconnectTimer.duration = 2 and state.reconnect = 2 and state.recovery = 2, "invalid and ERROR refreshes retain the second exponential backoff and shared debt")
                if state.reconnectTimer = invalid
                    closePlayer(player)
                    return
                end if
                timer = state.reconnectTimer
                if phase = "fetch" then player.callFunc("fixtureReconnectTimer", timer)
                beforeTasks = m.global.fixtureContentTasks
                recoveryProgress(player, 104)
                if phase = "backoff"
                    player.callFunc("fixtureReconnectTimer", timer)
                else
                    healthRefresh(player)
                end if
                state = player.callFunc("fixtureRead")
                if reason = "buffer_timeout" or reason = "stall"
                    check(state.video.isSameNode(video) and video.control = "play" and state.reconnectTimer = invalid and state.reconnectTask = invalid and calls(session, "start").count() = 1 and m.global.fixtureContentTasks = beforeTasks, "failed refresh preserves the original buffer or stall trigger for resumed-owner cancellation during " + phase)
                    check(state.recovery = 2 and state.reconnect = 2, "cancelling after a failed refresh preserves both spent attempts")
                else
                    if phase = "backoff" then healthRefresh(player)
                    state = player.callFunc("fixtureRead")
                    check(not state.video.isSameNode(video) and video.control = "stop" and calls(session, "start").count() = 2 and state.recovery = 2 and state.reconnect = 2, "failed refresh preserves protected source-transition and ordinary error-retry triggers")
                end if
                closePlayer(player)
            end for
        end for
    end for
end sub

sub testNativeLiveStartupWindow()
    for each opted in [false, true]
        setting = "false"
        if opted then setting = "true"
        set_user_setting("playback.lowLatency", setting)
        player = openPlayer("LIVE")
        session = sessionOf(player)
        deliver(player, content("roku-demux"))
        chooseRoku(player)
        ready(session, player.callFunc("fixtureRead").sessionId)
        video = player.callFunc("fixtureRead").video
        expected = 4
        if opted then expected = 0
        check(video.content.PlayStart = expected, "native startup requests the correct offset for its latency mode")
        if opted
            for each count in [3, 8]
                segments = []
                for index = 0 to count - 1
                    segments.push({ sequence: index + 0&, durationUs: 2000000&, mapUrl: "https://fixture.invalid/init.mp4", epoch: 0& })
                end for
                window = nlWindow({ ended: false, segments: segments, targetDuration: 2 }, 0&, false, false, 6000000&)
                check(window.durationUs - video.content.PlayStart * 1000000& >= 6000000&, "actual selected window retains six seconds after the requested native start")
            end for
        end if
        closePlayer(player)
    end for
    set_user_setting("playback.lowLatency", "true")
end sub

sub testChoiceReadyAndBack()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    original = content("roku-demux")
    deliver(player, original)
    check(player.callFunc("fixtureRead").video = invalid, "a descriptor waits for its session before creating a wrapper")
    chooseRoku(player)
    started = calls(session, "start")
    check(started.count() = 1 and started[0].descriptor.fixtureIdentity = "original-descriptor", "eligible content starts exactly one session with the retained descriptor")
    id = started[0].id
    player.callFunc("fixtureChoiceAgain")
    player.control = "play"
    settle(40)
    check(calls(session, "start").count() = 1, "duplicate dialog/control choices do not duplicate pending start")
    ready(session, "stale-id")
    check(player.callFunc("fixtureRead").video = invalid and calls(session, "attach").count() = 0, "a stale ready event cannot publish or play")
    ready(session, id)
    video = player.callFunc("fixtureRead").video
    attached = calls(session, "attach")
    check(video <> invalid and attached.count() = 1 and attached[0].id = id and attached[0].node.isSameNode(video), "matching ready attaches the real wrapper to the exact session")
    check(attached[0].contentEmpty and attached[0].control <> "play", "attachment occurs before wrapper content assignment and play")
    check(video.control = "play" and video.content.url = "http://127.0.0.1:49371/master.m3u8", "matching ready publishes and plays only the local URL")
    check(player.content.StreamUrls.count() = 1 and player.content.StreamUrls[0] = "http://127.0.0.1:49371/master.m3u8", "actual supported StreamUrls contains only the local rendition")
    check(player.content.localPlaybackDescriptor.fixtureIdentity = "original-descriptor" and player.content.localPlaybackDescriptor.mediaUrl = original.localPlaybackDescriptor.mediaUrl, "local playable content retains the original descriptor")
    check(player.content.QualityID = "1080p60" and video.selectedQuality = "1080p60", "local playable content and wrapper retain selected quality")
    check(not player.content.isTransmux and not player.content.isProxied and not player.content.ForwardQueryStringParams, "local route disables external proxy/transmux/query-forwarding flags")
    check(video.suppressStartupSeek, "local playback suppresses the experimental live-edge seek even when its preference is enabled")
    check(player.content.playbackNotice.instr("1080p60") >= 0, "local playback notice includes its fixed quality")
    video.state = "buffering"
    settle(20)
    timer = player.callFunc("fixtureRead").bufferTimer
    check(timer <> invalid and timer.duration = 25, "new Roku-only live retains the ordinary 25 second startup allowance")
    video.state = "playing"
    settle(20)
    player.callFunc("fixtureEventAgain")
    ready(session, id)
    check(calls(session, "attach").count() = 1 and player.callFunc("fixtureRead").video.isSameNode(video), "duplicate ready events never create or attach another wrapper")
    player.callFunc("fixtureBack")
    settle(40)
    check(player.callFunc("fixtureRead").exitPending and not player.backPressed and player.state <> "done", "Back waits while the modeled manager remains busy")
    stopCalls = calls(session, "stop")
    check(stopCalls.count() > 0 and stopCalls[stopCalls.count() - 1].id = id, "Back requests stop only for the player's own ID")
    ready(session, id)
    check(calls(session, "attach").count() = 1, "late ready during Back cannot restart playback")
    session.busy = false
    settle(40)
    check(player.backPressed and player.state = "done" and player.callFunc("fixtureRead").sessionId = "", "busy false acknowledges cleanup and completes Back")
    before = calls(session, "stop").count()
    closePlayer(player)
    check(calls(session, "stop").count() = before, "destruction after acknowledged Back never stops an empty ID")
end sub

sub testCleanupFailureWhileWaiting()
    for each mode in ["back", "direct"]
        player = openPlayer("LIVE")
        session = sessionOf(player)
        metadata = [{ QualityID: "1080p60", url: "http://fixture.invalid/combined", isTransmux: true, playbackTransport: "roku-demux", localPlaybackDescriptor: content("roku-demux").localPlaybackDescriptor }, { QualityID: "720p60", url: "http://fixture.invalid/direct720", isTransmux: false, playbackTransport: "direct" }]
        deliver(player, content("roku-demux"), metadata)
        chooseRoku(player)
        id = player.callFunc("fixtureRead").sessionId
        ready(session, id)
        if mode = "back"
            player.callFunc("fixtureBack")
        else
            video = player.callFunc("fixtureRead").video
            video.QualityChangeRequest = 1
            video.QualityChangeRequestFlag = true
        end if
        session.cleanupBlocked = true
        session.event = { id: id, status: "failed" }
        settle(60)
        dialog = m.scene.dialog
        check(dialog <> invalid, "cleanup failure during " + mode + " wait remains visible and actionable")
        if dialog <> invalid
            check(dialog.buttons.count() = 1 and dialog.buttons[0] = "Back", "failed cleanup offers no false retry")
            text = ""
            for each part in dialog.message
                text += part
            end for
            check(lcase(text).instr("restart stitch") >= 0, "failed cleanup explains the required restart")
        end if
        check(session.busy and not player.backPressed and player.state <> "done", "failed cleanup never fabricates an acknowledgment")
        check(not player.callFunc("fixtureRead").deferred, "failed cleanup cancels deferred direct playback")
        closePlayer(player)
    end for
end sub

sub testCancelledStartAndDisposal()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    player.callFunc("fixtureBack")
    ready(session, id)
    check(player.callFunc("fixtureRead").video = invalid and calls(session, "attach").count() = 0, "cancelled start ignores its later ready event")
    session.busy = false
    settle(40)
    check(player.backPressed, "cancelled start completes Back only on manager acknowledgment")
    closePlayer(player)

    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    player.callFunc("onDestroy")
    stops = calls(session, "stop")
    check(stops.count() = 1 and stops[0].id = id, "permanent disposal stops precisely its nonempty owned session")
    ready(session, id)
    session.busy = false
    player.callFunc("fixtureEventAgain")
    player.callFunc("fixtureRetry")
    settle(40)
    check(player.callFunc("fixtureRead").disposed and player.callFunc("fixtureRead").video = invalid and calls(session, "attach").count() = 0, "disposed player ignores stale events and explicit retry")
    player.callFunc("onDestroy")
    check(calls(session, "stop").count() = 1, "permanent destruction is idempotent")
    m.scene.removeChild(player)
    m.scene.localPlaybackSession = invalid
end sub

sub testDirectSwitch()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    metadata = [{ QualityID: "1080p60", url: "http://fixture.invalid/combined", isTransmux: true, playbackTransport: "roku-demux", localPlaybackDescriptor: content("roku-demux").localPlaybackDescriptor }, { QualityID: "720p60", url: "http://fixture.invalid/direct720", isTransmux: false, playbackTransport: "direct", isProxied: false, ForwardQueryStringParams: true }]
    deliver(player, content("roku-demux"), metadata)
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    ready(session, id)
    video = player.callFunc("fixtureRead").video
    video.QualityChangeRequest = 1
    video.QualityChangeRequestFlag = true
    settle(60)
    check(player.callFunc("fixtureRead").deferred and player.callFunc("fixtureRead").video.isSameNode(video), "switch to direct quality waits for local owner cleanup")
    ready(session, id)
    check(player.callFunc("fixtureRead").video.isSameNode(video), "stale local ready cannot override the pending direct quality")
    session.busy = false
    settle(60)
    direct = player.callFunc("fixtureRead").video
    check(not direct.isSameNode(video) and direct.content.url = "http://fixture.invalid/direct720" and direct.selectedQuality = "720p60", "cleanup acknowledgment recreates direct playback at selected quality")
    check(player.callFunc("fixtureRead").sessionId = "" and calls(session, "start").count() = 1 and calls(session, "attach").count() = 1, "direct switch clears local ownership and starts no new local worker")
    closePlayer(player)
end sub

sub testFailedRetryAndRecovery()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    first = player.callFunc("fixtureRead").sessionId
    session.event = { id: first, status: "failed" }
    settle(60)
    check(m.scene.dialog <> invalid and m.scene.dialog.buttons[0] = "Try again", "matching session failure opens an actionable retry dialog")
    before = m.global.fixtureContentTasks
    ' A first OK on an inert target lets the key driver queue the retry OK
    ' as a repeated press; the handler must wait for its actual dispatch.
    dialogFocus = m.scene
    for depth = 1 to 16
        child = dialogFocus.focusedChild
        if child = invalid then exit for
        if child.isSameNode(dialogFocus) then exit for
        dialogFocus = child
    end for
    primer = createObject("roSGNode", "DialogKeyBoundary")
    m.scene.appendChild(primer)
    primer.setFocus(true)
    press("ok")
    dispatch = createObject("roTimespan")
    while primer.pressCount = 0 and dispatch.totalMilliseconds() < 2000
        pump(20)
    end while
    m.scene.removeChild(primer)
    if primer.pressCount <> 1 then throw "first actual OK did not reach the inert focus boundary"
    dialogFocus.setFocus(true)
    press("ok")
    dispatch = createObject("roTimespan")
    while player.callFunc("fixtureRead").task = invalid and dispatch.totalMilliseconds() < 2000
        pump(20)
    end while
    task = player.callFunc("fixtureRead").task
    requested = false
    if task <> invalid then requested = task.enableRokuDemux and player.callFunc("fixtureRead").pending
    if not requested then throw "manual retry requests one fresh LIVE descriptor"
    check(requested, "manual retry requests one fresh LIVE descriptor")
    player.callFunc("fixtureRetry")
    check(m.global.fixtureContentTasks = before + 1, "duplicate manual retry while pending starts no second fetch")
    deliver(player, content("roku-demux"))
    second = player.callFunc("fixtureRead").sessionId
    check(second <> first and calls(session, "start").count() = 2, "answered manual retry keeps user opt-in and requests a new session identity")
    ready(session, first)
    check(calls(session, "attach").count() = 0, "old ready cannot bind the retried session")
    ready(session, second)
    player.callFunc("fixtureRecovery", 3)
    player.callFunc("fixtureReconnect")
    task = player.callFunc("fixtureRead").reconnectTask
    check(task <> invalid and task.enableRokuDemux, "automatic reconnect retains LIVE descriptor opt-in")
    task.response = content("roku-demux")
    settle(60)
    third = player.callFunc("fixtureRead").sessionId
    check(third <> second and calls(session, "start").count() = 3, "automatic refreshed descriptor requests one replacement session")
    ready(session, third)
    check(player.callFunc("fixtureRead").video.suppressStartupSeek and player.callFunc("fixtureRead").recovery = 3 and player.callFunc("fixtureRead").reconnect = 3, "recovery preserves spent automatic budgets and startup-seek suppression")
    closePlayer(player)
end sub

sub testRefusalAndBlockedOwner()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    session.refuseStart = true
    deliver(player, content("roku-demux"))
    check(player.callFunc("fixtureRead").chosen and calls(session, "start").count() = 1, "eligible content attempts exactly one session start")
    check(player.callFunc("fixtureRead").sessionId = "" and player.callFunc("fixtureRead").video = invalid and m.scene.dialog <> invalid, "synchronous empty start refusal creates no wrapper and presents retry")
    closePlayer(player)
    check(calls(session, "stop").count() = 0, "start refusal never sends empty-ID stop")

    player = openPlayer("LIVE")
    session = sessionOf(player)
    session.cleanupBlocked = true
    player.contentRequested = request("LIVE")
    check(not player.callFunc("fixtureRead").task.enableRokuDemux, "blocked cleanup owner cannot enable new descriptors")
    deliver(player, content("roku-demux"))
    check(m.scene.dialog.buttons.count() = 1 and m.scene.dialog.buttons[0] = "Back" and calls(session, "start").count() = 0, "blocked owner offers Back-only fallback without start")
    closePlayer(player)
end sub

function lowLatencySource() as object
    node = content()
    node.url = "https://fixture.invalid/master.m3u8"
    return node
end function

' The relay is an inert boundary here; its playlists are covered offline.
sub testLowLatencyRelay()
    player = openPlayer("LIVE")
    source = lowLatencySource()
    deliver(player, source)
    relay = player.callFunc("fixtureRead").relay
    check(relay <> invalid and relay.sourceUrl = source.url and relay.control = "run", "an eligible direct live stream starts the relay with its signed source")
    check(player.callFunc("fixtureRead").video = invalid, "playback waits for the relay's local URL")
    relay.status = { url: "http://127.0.0.1:49380/live.m3u8" }
    settle(60)
    video = player.callFunc("fixtureRead").video
    check(video <> invalid and video.control = "play" and video.content.url = "http://127.0.0.1:49380/live.m3u8" and video.lowLatency, "the ready relay URL plays with the low-latency tag")
    check(player.content.url = source.url, "the player keeps the signed source for refreshes and switches")
    player.callFunc("fixtureReconnect")
    settle(40)
    player.callFunc("fixtureRead").reconnectTask.response = lowLatencySource()
    settle(60)
    restarted = player.callFunc("fixtureRead").relay
    check(relay.stopRequested and relay.control = "stop" and restarted <> invalid and not restarted.isSameNode(relay), "a reconnect stops the old relay and starts a fresh one near the live edge")
    restarted.status = { url: "http://127.0.0.1:49381/live.m3u8" }
    settle(60)
    check(player.callFunc("fixtureRead").video.content.url = "http://127.0.0.1:49381/live.m3u8", "the reconnected wrapper plays the fresh relay")
    ' The stopped relay wrapper is still current when the next relay fails.
    player.callFunc("fixtureReconnect")
    settle(40)
    player.callFunc("fixtureRead").reconnectTask.response = lowLatencySource()
    settle(60)
    failed = player.callFunc("fixtureRead").relay
    failed.status = { failure: "source_unavailable" }
    settle(60)
    state = player.callFunc("fixtureRead")
    check(state.video.control = "play" and state.video.content.url = source.url and not state.video.lowLatency and failed.stopRequested and state.relay = invalid, "a failed relay after a served one plays the signed source")
    player.callFunc("fixtureReconnect")
    settle(40)
    player.callFunc("fixtureRead").reconnectTask.response = lowLatencySource()
    settle(60)
    retried = player.callFunc("fixtureRead").relay
    check(retried <> invalid and not retried.isSameNode(failed), "a failed fetch is tried through the relay again on the next start")
    retried.status = { url: "http://127.0.0.1:49382/live.m3u8" }
    settle(60)
    state = player.callFunc("fixtureRead")
    check(state.video.content.url = "http://127.0.0.1:49382/live.m3u8" and state.video.lowLatency, "the retried relay plays")
    ' Roku can finish a relayed live playlist early; that recovers in place.
    state.video.state = "finished"
    settle(40)
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer <> invalid and state.reconnect = 1 and not state.disposed and player.callFunc("fixtureRead").relay <> invalid, "a relay that finishes early reconnects instead of leaving")
    player.callFunc("fixtureBack")
    settle(60)
    check(retried.stopRequested and player.callFunc("fixtureRead").relay = invalid, "Back stops the relay")
    closePlayer(player)

    ' A stream Twitch ended leaves the player as direct playback does.
    player = openPlayer("LIVE")
    deliver(player, lowLatencySource())
    relay = player.callFunc("fixtureRead").relay
    relay.status = { url: "http://127.0.0.1:49380/live.m3u8" }
    settle(60)
    relay.ended = true
    player.callFunc("fixtureRead").video.state = "finished"
    settle(60)
    state = player.callFunc("fixtureRead")
    check(state.reconnectTimer = invalid and state.reconnect = 0 and relay.stopRequested and state.relay = invalid, "an ended stream leaves the player")
    closePlayer(player)

    ' Loading another item while a relay serves the first one: closing that
    ' relay must not start recovery for the stopped wrapper.
    player = openPlayer("LIVE")
    deliver(player, lowLatencySource())
    relay = player.callFunc("fixtureRead").relay
    relay.status = { url: "http://127.0.0.1:49380/live.m3u8" }
    settle(60)
    previous = player.callFunc("fixtureRead").video
    player.contentRequested = request("LIVE")
    settle(40)
    ' This engine stops delivering the replaced wrapper's state changes, so
    ' the detached observers themselves are not proven here.
    previous.errorCode = -1
    previous.errorStr = "fixture network failure"
    previous.state = "error"
    settle(40)
    state = player.callFunc("fixtureRead")
    check(relay.stopRequested and state.task <> invalid and state.retryTimer = invalid and state.reconnectTimer = invalid and state.reconnect = 0 and state.recovery = 0, "loading another item closes the relay without recovering its stopped wrapper")
    deliver(player, lowLatencySource())
    following = player.callFunc("fixtureRead").relay
    check(following <> invalid and not following.isSameNode(relay) and player.callFunc("fixtureRead").reconnect = 0, "the next item starts its own relay")
    closePlayer(player)

    player = openPlayer("LIVE")
    deliver(player, lowLatencySource())
    relay = player.callFunc("fixtureRead").relay
    relay.status = { failure: "unsupported_playlist" }
    settle(60)
    video = player.callFunc("fixtureRead").video
    check(video <> invalid and video.content.url = "https://fixture.invalid/master.m3u8" and not video.lowLatency and relay.stopRequested, "a refused source plays directly without the tag")
    player.callFunc("fixtureReconnect")
    settle(40)
    player.callFunc("fixtureRead").reconnectTask.response = lowLatencySource()
    settle(60)
    check(player.callFunc("fixtureRead").relay = invalid and player.callFunc("fixtureRead").video.content.url = "https://fixture.invalid/master.m3u8", "a refused stream is not retried through the relay")
    closePlayer(player)

    registry = m.global.fixtureRegistry
    registry["playback.lowLatency"] = "false"
    m.global.fixtureRegistry = registry
    player = openPlayer("LIVE")
    deliver(player, lowLatencySource())
    check(player.callFunc("fixtureRead").relay = invalid and player.callFunc("fixtureRead").video.content.url = "https://fixture.invalid/master.m3u8", "with the setting off, live plays directly")
    closePlayer(player)
    registry["playback.lowLatency"] = "true"
    m.global.fixtureRegistry = registry
end sub
