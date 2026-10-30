sub init()
    m.disposed = false
    m.channelActionsOpen = false
    initAdCountdown()
    if m.adBadge <> invalid
        m.adBadge.adLabel = tr("Ad")
        m.adBadge.numberedAdLabel = tr("Ad {0} of {1}")
    end if
    ' Initialize UI elements
    m.top.enableUI = false
    m.top.enableTrickPlay = false

    ' Control overlay elements
    m.controlOverlay = m.top.findNode("controlOverlay")
    m.controlOverlay.visible = false
    m.controlsHint = m.top.findNode("controlsHint")
    m.controlsHint.text = tr("Press Down or Back to hide controls")

    ' Overlay layout elements (sized to the video area in layoutOverlay)
    m.scrim = m.top.findNode("scrim")
    m.scrimFade = m.top.findNode("scrimFade")
    m.scrimFadeFill = m.top.findNode("scrimFadeFill")
    m.controls = m.top.findNode("controls")
    m.caption = m.top.findNode("caption")
    m.captionPlate = m.top.findNode("captionPlate")
    m.captionLabel = m.top.findNode("captionLabel")
    m.latencyTag = m.top.findNode("latencyTag")
    m.latencyTag.text = tr("Low-latency mode (experimental)")

    ' Control buttons
    m.backGroup = m.top.findNode("backGroup")
    m.chatGroup = m.top.findNode("chatGroup")
    m.playPauseGroup = m.top.findNode("playPauseGroup")
    m.qualityGroup = m.top.findNode("qualityGroup")
    m.channelGroup = m.top.findNode("channelGroup")
    m.channelFocus = m.top.findNode("channelFocus")
    m.controlButton = m.top.findNode("controlButton")
    m.messagesButton = m.top.findNode("messagesButton")
    m.qualitySelectButton = m.top.findNode("qualitySelectButton")

    ' Focus backgrounds
    m.backFocus = m.top.findNode("backFocus")
    m.chatFocus = m.top.findNode("chatFocus")
    m.playPauseFocus = m.top.findNode("playPauseFocus")
    m.qualityFocus = m.top.findNode("qualityFocus")

    ' Video info
    m.videoTitle = m.top.findNode("videoTitle")
    m.viewerCount = m.top.findNode("viewerCount")
    m.streamCategory = m.top.findNode("streamCategory")
    m.categoryArt = m.top.findNode("categoryArt")
    m.liveUptime = m.top.findNode("liveUptime")
    m.streamStartSeconds = 0
    m.channelUsername = m.top.findNode("channelUsername")
    m.avatar = m.top.findNode("avatar")

    ' Other elements
    m.liveIndicator = m.top.findNode("liveIndicator")
    initLiveBadge()

    ' Loading overlay
    m.loadingOverlay = m.top.findNode("loadingOverlay")
    m.loadingSpinner = m.top.findNode("loadingSpinner")
    m.loadingText = m.top.findNode("loadingText")
    if m.loadingText <> invalid then m.loadingText.text = tr("Loading stream…")

    ' Quality dialog
    m.qualityDialog = CreateObject("roSGNode", "StandardMessageDialog")
    m.qualityDialog.visible = false
    m.qualityDialogOpen = false
    applyDialogPalette(m.qualityDialog)
    ' Set up quality dialog observer once during initialization
    m.qualityDialog.observeFieldScopedEx("buttonSelected", "onQualityButtonSelect")
    m.qualityDialog.observeFieldScoped("wasClosed", "onQualityDialogClosed")

    ' State variables
    m.currentFocusedButton = 2 ' 0=back, 1=chat, 2=play/pause, 3=quality
    m.isOverlayVisible = false
    m.currentPositionSeconds = 0
    m.isLiveStream = true ' StitchVideo is always for live streams

    ' Timers
    m.fadeAwayTimer = createObject("roSGNode", "Timer")
    m.fadeAwayTimer.observeField("fire", "onFadeAway")
    m.fadeAwayTimer.repeat = false
    m.fadeAwayTimer.duration = 5
    m.fadeAwayTimer.control = "stop"

    m.streamDetailsTimer = createObject("roSGNode", "Timer")
    m.streamDetailsTimer.duration = 1
    m.streamDetailsTimer.repeat = true
    m.streamDetailsTimer.observeField("fire", "updateLiveUptime")

    ' Live-edge latency diagnostic timer.
    ' Logs streamingSegment.latency every 5s while the stream is active
    ' (started on state=playing, stopped on paused/error/finished/stopped;
    ' continues to fire during buffering so buffer dips are visible in logs).
    ' See AGENTS.md / DEV.md for how to read these logs over the debug console.
    m.latencyLogTimer = createObject("roSGNode", "Timer")
    m.latencyLogTimer.observeField("fire", "onLatencyLogFire")
    m.latencyLogTimer.repeat = true
    m.latencyLogTimer.duration = 5
    m.latencyLogTimer.control = "stop"

    ' One-shot timer for the post-startup live-edge re-anchor.
    ' Fires ~3s after state=playing settles, then issues a single seek=999999.
    ' Roku's streaming spec endorses seek=999999 as the canonical "go to live"
    ' sentinel: the player clips it to the current availability window.
    ' m.startupSeekFired guards against re-firing on every state transition -
    ' a single seek causes its own buffering/playing cycle, which would
    ' otherwise re-arm this timer in onVideoStateChange and create a tight
    ' 3s seek loop. Reset to false only when content is reassigned (i.e. a
    ' new stream is loaded).
    m.startupSeekFired = false
    m.liveEdgeStartupTimer = createObject("roSGNode", "Timer")
    m.liveEdgeStartupTimer.observeField("fire", "onLiveEdgeStartupFire")
    m.liveEdgeStartupTimer.repeat = false
    m.liveEdgeStartupTimer.duration = 3
    m.liveEdgeStartupTimer.control = "stop"

    ' Suppress the loading overlay during the brief (~200-400ms) re-buffer
    ' that follows the app-initiated live-edge seek. Set true right before
    ' the seek, cleared on the next state=playing. Without this, the user
    ' sees a quick spinner flash right after the stream first starts which
    ' looks like a stutter, even though the seek is working as intended.
    m.suppressLoadingOverlayUntilPlaying = false

    ' Deferred-analytics state for the live_edge_seek event's "fire"
    ' branch. issueLiveEdgeSeek sets these right before issuing the seek;
    ' onLatencyLogFire consumes them on the next valid latency sample
    ' (~5s later) to emit one PostHog event with the full pre/post
    ' picture. Both invalid means no outcome is pending.
    m.pendingSeekReason = invalid
    m.pendingSeekOutcomePreMs = invalid

    ' Observers
    m.top.observeField("position", "onPositionChange")
    m.top.observeField("state", "onVideoStateChange")
    m.top.observeField("content", "onContentChange")
    m.top.observeField("chatIsVisible", "onChatVisibilityChange")
    m.top.observeField("duration", "onDurationChange")
    m.top.observeField("bufferingStatus", "onBufferingStatusChange")
    m.top.observeField("qualityOptions", "onQualityOptionsChange")
    m.top.observeField("selectedQuality", "onSelectedQualityChange")

    ' Initialize UI
    layoutOverlay()
    setupLiveUI()

    ' Show loading overlay initially
    showLoadingOverlay()

    ' ? "[StitchVideo] Initialized for live stream"
end sub

sub createMessageOverlay()
    if m.messageOverlay = invalid
        m.messageOverlay = createPlayerMessageOverlay()
        m.top.appendChild(m.messageOverlay)
    end if
end sub

sub setupLiveUI()
    ' The LIVE badge sits in the info row, so it shows with the controls.
    m.liveIndicator.visible = true
    updateLatencyTag()
end sub

' Sizes the red badge to the localized LIVE text and starts the channel
' name after it.
sub initLiveBadge()
    width = fitLabelPlate(m.top.findNode("liveLabel"), m.top.findNode("liveBadge"), tr("LIVE"), 16, 56)
    if m.channelUsername <> invalid then m.channelUsername.translation = [64 + width + 12, 0]
end sub

' The video area is 1280 wide, or 960 when chat is shown beside it. The
' scrim, caption, tag and controls stay inside that area's safe margins.
function videoAreaWidth() as integer
    if m.top.chatIsVisible = true and m.top.chatOverlayMode <> true then return 960
    return 1280
end function

sub layoutOverlay()
    if m.adBadge <> invalid then m.adBadge.videoAreaWidth = videoAreaWidth()
    width = videoAreaWidth()
    m.scrim.width = width
    m.controlsHint.width = width - 96
    m.scrimFadeFill.width = width
    m.scrimFade.maskSize = [width, 48]
    m.latencyTag.translation = [width - 48 - 360, 35]
    m.viewerCount.translation = [width - 96 - m.viewerCount.width, 34]
    m.liveUptime.translation = [width - 96 - m.liveUptime.width, 80]
    categoryX = m.streamCategory.translation[0]
    m.streamCategory.width = width - 96 - categoryX
    if m.liveUptime.visible then m.streamCategory.width = m.liveUptime.translation[0] - categoryX - 24
    titleWidth = 900
    if width < 1280
        titleWidth = 660
    end if
    if m.viewerCount.visible
        availableTitleWidth = m.viewerCount.translation[0] - 64 - 24
        if titleWidth > availableTitleWidth then titleWidth = availableTitleWidth
    end if
    if m.videoTitle.maxWidth <> titleWidth
        m.videoTitle.repeatCount = 0
        m.videoTitle.maxWidth = titleWidth
    end if
    updateTitleScroll()
    controlsWidth = 292
    if m.top.channelAvailable then controlsWidth += 76
    m.controls.translation = [Int((width - controlsWidth) / 2), 178]
    if m.loadingOverlay <> invalid then m.loadingOverlay.translation = [Int(width / 2), 360]
    if m.messageOverlay <> invalid then m.messageOverlay.translation = [Int((width - 640) / 2), 0]
    updateCaption()
end sub

sub onViewersCountChange()
    if m.viewerCount = invalid then return
    m.viewerCount.visible = m.top.video_type = "LIVE" and m.top.viewersCount >= 0
    m.viewerCount.text = ""
    if m.viewerCount.visible
        countWidth = fitLabelPlate(m.viewerCount, invalid, Substitute("{0} {1}", numberToText(m.top.viewersCount), tr("Viewers")), 0, 160)
        if countWidth > 320 then m.viewerCount.width = 320
    end if
    layoutOverlay()
end sub

' VideoPlayer sets lowLatency while the relay serves this wrapper. The tag
' states the mode, never a measured result.
sub updateLatencyTag()
    m.latencyTag.visible = m.top.lowLatency
end sub

sub onChannelAvailableChange()
    if m.disposed or m.channelGroup = invalid then return
    m.channelGroup.visible = m.top.channelAvailable
    if not m.top.channelAvailable and m.currentFocusedButton = 4 then focusButton(2)
    layoutOverlay()
end sub

function captionForButton(index as integer) as string
    if index = 0
        return tr("Exit player")
    else if index = 1
        if m.top.chatIsVisible = true then return tr("Hide chat")
        return tr("Show chat")
    else if index = 2
        if m.top.state = "paused" then return tr("Play")
        return tr("Pause")
    else if index = 3
        quality = m.top.selectedQuality
        if quality <> invalid and quality <> "" then return tr("Quality · {0}").replace("{0}", quality)
        return tr("Quality")
    else if index = 4
        return tr("Channel actions")
    end if
    return ""
end function

' Every focused control names itself in a caption above it.
sub updateCaption()
    if m.caption = invalid then return
    if not m.isOverlayVisible
        m.caption.visible = false
        return
    end if
    plateWidth = fitLabelPlate(m.captionLabel, m.captionPlate, captionForButton(m.currentFocusedButton), 24, 96)
    center = m.controls.translation[0] + m.currentFocusedButton * 76 + 32
    m.caption.translation = [clampToVideoArea(center - Int(plateWidth / 2), plateWidth), 140]
    m.caption.visible = true
end sub

function clampToVideoArea(x as integer, width as integer) as integer
    limit = videoAreaWidth() - 48 - width
    if x > limit then x = limit
    if x < 48 then x = 48
    return x
end function


sub onPositionChange()
    m.currentPositionSeconds = m.top.position
    ' Live streams don't need position-based updates
end sub

' Re-arm the one-shot startup seek when a fresh stream is loaded.
' Setting m.top.content fires this; we use it to reset the latched flag so
' the next stream session gets its own startup seek. Also clear the recent
' seek timestamp - otherwise the watchdog cooldown could be triggered by a
' stale value from the previous stream session — and any pending seek
' outcome event from the prior stream, which would otherwise be emitted
' against the new stream's latency sample.
sub onContentChange()
    ' Counts are launch/refresh metadata; a new item must not keep the old count.
    m.top.viewersCount = -1
    loadStreamDetails()
    ignored = clearAdCountdown(m.adOwner)
    if m.top.content <> invalid
        m.startupSeekFired = false
        m.top.recentSeekTimestamp = 0
        m.pendingSeekReason = invalid
        m.pendingSeekOutcomePreMs = invalid
        updateLatencyTag()
    end if
end sub

sub loadStreamDetails()
    m.streamStartSeconds = 0
    m.streamCategory.text = ""
    m.categoryArt.uri = ""
    content = m.top.content
    if content <> invalid and m.top.video_type = "LIVE"
        category = content.gameDisplayName
        if category = invalid or category = "" then category = content.gameName
        if GetInterface(category, "ifString") <> invalid then m.streamCategory.text = category
        if GetInterface(content.gameBoxArtUrl, "ifString") <> invalid then m.categoryArt.uri = content.gameBoxArtUrl
        if GetInterface(content.createdAt, "ifString") <> invalid and content.createdAt <> ""
            started = CreateObject("roDateTime")
            started.FromSeconds(0)
            started.FromISO8601String(content.createdAt)
            m.streamStartSeconds = started.AsSeconds()
        end if
    end if
    m.streamCategory.visible = m.streamCategory.text <> ""
    m.categoryArt.visible = m.streamCategory.visible and m.categoryArt.uri <> ""
    categoryX = 64
    if m.categoryArt.visible then categoryX = 164
    m.streamCategory.translation = [categoryX, 80]
    updateLiveUptime()
    layoutOverlay()
    m.streamDetailsTimer.control = "stop"
    if m.isOverlayVisible and m.liveUptime.visible then m.streamDetailsTimer.control = "start"
end sub

sub updateLiveUptime()
    if m.disposed then return
    elapsed = TimeStamp() - m.streamStartSeconds
    wasVisible = m.liveUptime.visible
    m.liveUptime.visible = m.streamStartSeconds > 0 and elapsed >= 0
    m.liveUptime.text = ""
    if m.liveUptime.visible then m.liveUptime.text = Substitute(tr("Live for {0}"), convertToReadableTimeFormat(elapsed))
    if wasVisible <> m.liveUptime.visible then layoutOverlay()
end sub

sub onVideoStateChange()
    if m.disposed then return
    updateAdPresented()
    ? getLogTimestamp(); " [StitchVideo][state] state="; m.top.state; " pos="; m.top.position
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/pause.png"
        if m.currentFocusedButton = 2 then updateCaption()
        hideLoadingOverlay()
        ' Reaching "playing" ends any post-seek re-buffer; re-enable the
        ' loading overlay for future, non-seek-related buffering events.
        m.suppressLoadingOverlayUntilPlaying = false
        hideMessage()
        startLatencyLog()
        ' Fire one immediate sample so we see latency even if the repeating
        ' timer is delayed/blocked for some reason.
        onLatencyLogFire()
        ' Arm the one-shot live-edge re-anchor (latched via m.startupSeekFired
        ' so it fires exactly once per stream session). VideoPlayer sets
        ' suppressStartupSeek=true on recovery paths (watchdog reconnect,
        ' error-driven retryPlayback) so we don't fight the conditions that
        ' caused the stall by immediately re-anchoring at the live edge.
        if m.top.suppressStartupSeek
            ? getLogTimestamp(); " [StitchVideo][seek] action=skip reason=disabled_or_recovery"
            m.startupSeekFired = true
        else
            startLiveEdgeStartupTimer()
        end if
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/play.png"
        if m.currentFocusedButton = 2 then updateCaption()
        hideLoadingOverlay()
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
    else if m.top.state = "buffering"
        ' The post-seek re-buffer is ~200-400ms and looks like a stutter
        ' to the user. issueLiveEdgeSeek sets the suppress flag immediately
        ' before issuing seek=999999, and the flag is cleared on the next
        ' state=playing. If the re-buffer ever runs longer than expected,
        ' VideoPlayer's stall watchdog (20s post-seek cooldown then 16s
        ' stall threshold) is still the safety net — no risk of silent
        ' hangs.
        if m.suppressLoadingOverlayUntilPlaying <> true
            showLoadingOverlay()
        end if
        stopLiveEdgeStartupTimer()
    else if m.top.state = "error"
        hideLoadingOverlay()
        m.suppressLoadingOverlayUntilPlaying = false
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
        if m.top.errorStr <> invalid and (m.top.errorStr.InStr("970") > -1 or m.top.errorStr.InStr("buffer:loop:demux") > -1)
            showErrorMessage(tr("Video format not supported"), tr("This stream can't be played on this Roku."))
        else
            showErrorMessage(tr("Stream problem"), tr("Having trouble loading the live stream. Retrying…"))
        end if
    else if m.top.state = "finished" or m.top.state = "stopped"
        m.suppressLoadingOverlayUntilPlaying = false
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
    end if
end sub

' ===== Live-edge latency diagnostics =====
' streamingSegment.latency = ms between live edge and the segment currently
' being played. This is the only Roku-exposed measurement of how far behind
' live we are. Useful for evaluating low-latency tuning.

sub startLatencyLog()
    if m.latencyLogTimer <> invalid
        m.latencyLogTimer.control = "start"
    end if
end sub

sub stopLatencyLog()
    if m.latencyLogTimer <> invalid
        m.latencyLogTimer.control = "stop"
    end if
end sub

sub onLatencyLogFire()
    ' Always print one line per fire so we can debug. No early returns:
    ' if streamingSegment is invalid we want to SEE that, not silently skip.
    seg = m.top.streamingSegment
    segValid = "no"
    segType = "?"
    latencyMs = "?"
    bitrate = "?"
    segSeq = "?"
    latencyValueMs = invalid

    if seg <> invalid
        segValid = "yes"
        if seg.segType <> invalid then segType = seg.segType.toStr()
        if seg.latency <> invalid
            latencyMs = seg.latency.toStr()
            latencyValueMs = seg.latency
        end if
        if seg.segBitrateBps <> invalid then bitrate = seg.segBitrateBps.toStr()
        if seg.segSequence <> invalid then segSeq = seg.segSequence.toStr()
    end if

    measured = m.top.measuredBitrate

    ? getLogTimestamp(); " [StitchVideo][latency] state="; m.top.state; " pos="; m.top.position; " seg_valid="; segValid; " seg_type="; segType; " live_edge_ms="; latencyMs; " seg_bitrate_bps="; bitrate; " measured_bps="; measured; " seg_seq="; segSeq

    ' If a seek just fired and we have a valid post-seek latency sample,
    ' emit the unified live_edge_seek event with the full pre/post picture.
    ' We only consume the pending outcome on a sample that actually has a
    ' latency value — if seg_valid=no we wait for the next fire (5s later)
    ' so the post measurement is meaningful.
    if m.pendingSeekReason <> invalid and latencyValueMs <> invalid
        preMs = m.pendingSeekOutcomePreMs
        deltaMs = invalid
        if preMs <> invalid then deltaMs = preMs - latencyValueMs
        trackEvent("live_edge_seek", {
            decision: "fire",
            reason: m.pendingSeekReason,
            pre_live_edge_ms: preMs,
            post_live_edge_ms: latencyValueMs,
            delta_ms: deltaMs
        })
        m.pendingSeekReason = invalid
        m.pendingSeekOutcomePreMs = invalid
    end if
end sub

' ===== Live-edge re-anchor (strategies B and C) =====
' Roku's streaming spec endorses seek=999999 as the canonical "go to live"
' sentinel - the platform clips the position to the current availability
' window. Both timers below use this mechanism. We log a one-line snapshot
' of live_edge_ms BEFORE every seek so we can correlate before/after impact
' against the regular 5s latency timer.

sub startLiveEdgeStartupTimer()
    if m.startupSeekFired = true then return
    if m.liveEdgeStartupTimer <> invalid
        m.liveEdgeStartupTimer.control = "stop"
        m.liveEdgeStartupTimer.control = "start"
    end if
end sub

sub stopLiveEdgeStartupTimer()
    if m.liveEdgeStartupTimer <> invalid
        m.liveEdgeStartupTimer.control = "stop"
    end if
end sub

sub onLiveEdgeStartupFire()
    m.startupSeekFired = true
    issueLiveEdgeSeek("startup")
end sub

' Single point of seek=999999 application. Decides whether to fire the seek
' based on the current pre-seek latency: if we're already close to live the
' seek buys us nothing (and can even slightly increase latency), so we skip
' it.
'
' Emits exactly one live_edge_seek PostHog event per decision so we can tune
' the threshold from real-world data:
'   - skip path: event fires immediately with decision="skip"
'   - fire path: event fires ~5s later from onLatencyLogFire once the
'     post-seek latency sample is available, carrying both pre and post
'     so we have one row per decision with the full picture
'
' Bails (no analytics, no log spam) if we're not in steady-state playing —
' that's a transient invocation race, not a real decision point.
sub issueLiveEdgeSeek(reason as string)
    if m.top.state <> "playing"
        ? getLogTimestamp(); " [StitchVideo][seek] action=skip reason="; reason; " state="; m.top.state
        return
    end if

    ' Only run the experiment with a measured live-edge distance.
    seg = m.top.streamingSegment
    preLatency = "?"
    preLatencyMs = invalid
    if seg <> invalid and seg.latency <> invalid
        preLatency = seg.latency.toStr()
        preLatencyMs = seg.latency
    end if
    if preLatencyMs = invalid or preLatencyMs < 0 then return

    ' Skip the seek if we're already close enough to live. The seek's
    ' conservative threshold is a guard against unnecessary rebuffering,
    ' not a promise of latency or evidence from this modernization's QA.
    if preLatencyMs <> invalid and preLatencyMs < 30000
        ? getLogTimestamp(); " [StitchVideo][seek] action=skip reason="; reason; " pre_live_edge_ms="; preLatency; " already_near_live=true"
        trackEvent("live_edge_seek", {
            decision: "skip",
            reason: reason,
            skip_reason: "already_near_live",
            pre_live_edge_ms: preLatencyMs
        })
        return
    end if

    ? getLogTimestamp(); " [StitchVideo][seek] action=fire reason="; reason; " pre_live_edge_ms="; preLatency; " pos="; m.top.position
    ' Tell VideoPlayer's stall watchdog we just seeked so it doesn't treat
    ' the brief re-buffer that follows as a fake stall and force a reconnect.
    m.top.recentSeekTimestamp = CreateObject("roDateTime").AsSeconds()
    ' Hide the loading overlay during the brief post-seek re-buffer so the
    ' user doesn't see a spinner flash. Cleared when state returns to
    ' "playing" (typically ~200-400ms after the seek lands).
    m.suppressLoadingOverlayUntilPlaying = true
    ' Stash pre-seek context for the deferred analytics event. Consumed by
    ' onLatencyLogFire on the next sample that has a valid latency value
    ' (~5s after the seek lands). preLatencyMs may be invalid when the
    ' segment wasn't ready — onLatencyLogFire handles that explicitly.
    m.pendingSeekReason = reason
    m.pendingSeekOutcomePreMs = preLatencyMs
    m.top.seek = 999999
end sub

sub onChatVisibilityChange()
    layoutOverlay()
end sub

sub onDurationChange()
    ' Live streams show the LIVE badge instead of a progress bar.
end sub

sub onBufferingStatusChange()
    ' Live streams handle buffering differently
    ' ? "[StitchVideo] Buffering status changed"
end sub

sub onQualityOptionsChange()
    setupQualityDialog()
end sub

sub onSelectedQualityChange()
    setupLiveUI()
    if m.currentFocusedButton = 3 then updateCaption()
    if not m.qualityDialog.visible then setupQualityDialog()
end sub

' Buttons keep the qualityOptions order with Cancel last, so a selected index
' still maps to the same option. Only the label marks the current quality.
sub setupQualityDialog()
    if m.top.qualityOptions <> invalid and m.top.qualityOptions.count() > 0
        current = m.top.selectedQuality
        if current = invalid then current = ""
        m.qualityDialog.title = tr("Video quality")
        if current <> ""
            m.qualityDialog.message = [tr("Now playing: {0}").replace("{0}", current)]
        else
            m.qualityDialog.message = []
        end if

        buttons = []
        for each quality in m.top.qualityOptions
            if current <> "" and quality = current
                buttons.push(tr("{0} (current)").replace("{0}", quality))
            else
                buttons.push(quality)
            end if
        end for
        buttons.push(tr("Cancel"))

        m.qualityDialog.buttons = buttons
    end if
end sub

sub onQualityButtonSelect()
    if m.disposed then return
    ' ? "[StitchVideo] Quality dialog button selected: "; m.qualityDialog.buttonSelected

    selectedIndex = m.qualityDialog.buttonSelected
    totalButtons = m.qualityDialog.buttons.count()
    changeIndex = invalid

    onQualityDialogClosed()

    ' Check if Cancel was selected (last button)
    if selectedIndex = totalButtons - 1
        ' ? "[StitchVideo] Cancel selected, no quality change"
    else if selectedIndex >= 0 and selectedIndex < m.top.qualityOptions.count()
        ' Valid quality option selected
        selectedQuality = m.top.qualityOptions[selectedIndex]
        ' ? "[StitchVideo] Quality selected: "; selectedQuality

        m.top.selectedQuality = selectedQuality
        changeIndex = selectedIndex
    else
        ' ? "[StitchVideo] Invalid selection index: "; selectedIndex
    end if

    ' Emit last: the parent may destroy this node during its callback.
    if changeIndex <> invalid
        m.top.QualityChangeRequest = changeIndex
        m.top.QualityChangeRequestFlag = true
    end if
end sub

sub onQualityDialogClosed()
    if m.disposed or not m.qualityDialogOpen then return
    m.qualityDialogOpen = false
    m.qualityDialog.visible = false
    m.qualityDialog.setFocus(false)
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        if not scene.dialog.isSameNode(m.qualityDialog) then return
        scene.dialog = invalid
    end if
    m.top.setFocus(true)
    if m.isOverlayVisible
        focusButton(m.currentFocusedButton)
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.control = "start"
    end if
end sub

sub showOverlay()
    m.isOverlayVisible = true
    m.controlOverlay.visible = true
    updateLatencyTag()
    updateLiveUptime()
    updateTitleScroll()
    if m.liveUptime.visible then m.streamDetailsTimer.control = "start"
    focusButton(m.currentFocusedButton)

    ' Start fade timer
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    updateTitleScroll()
    m.streamDetailsTimer.control = "stop"
    clearAllButtonFocus()
    updateCaption()
end sub

sub updateTitleScroll()
    repeatCount = 0
    if m.isOverlayVisible and m.videoTitle.width > m.videoTitle.maxWidth then repeatCount = -1
    m.videoTitle.repeatCount = repeatCount
end sub

sub onVideoTitleChange()
    if m.disposed or m.videoTitle = invalid then return
    m.videoTitle.repeatCount = 0
    m.videoTitle.text = m.top.videoTitle
    updateTitleScroll()
end sub

sub onFadeAway()
    if m.channelActionsOpen then return
    ' Only hide overlay if quality dialog is not visible
    if not m.qualityDialog.visible
        hideOverlay()
    end if
end sub

sub setChannelActionsOpen(open as boolean)
    if m.disposed then return
    m.channelActionsOpen = open
    m.fadeAwayTimer.control = "stop"
    if not open and m.isOverlayVisible then m.fadeAwayTimer.control = "start"
end sub

sub focusButton(buttonIndex)
    clearAllButtonFocus()
    m.currentFocusedButton = buttonIndex

    if buttonIndex = 0 ' Back
        m.backFocus.visible = true
    else if buttonIndex = 1 ' Chat
        m.chatFocus.visible = true
    else if buttonIndex = 2 ' Play/Pause
        m.playPauseFocus.visible = true
    else if buttonIndex = 3 ' Quality
        m.qualityFocus.visible = true
    else if buttonIndex = 4
        m.channelFocus.visible = true
    end if
    updateCaption()
end sub

sub clearAllButtonFocus()
    m.backFocus.visible = false
    m.chatFocus.visible = false
    m.playPauseFocus.visible = false
    m.qualityFocus.visible = false
    m.channelFocus.visible = false
end sub

sub executeButtonAction()
    if m.disposed then return
    if m.currentFocusedButton = 0 ' Back
        parent = m.top.getParent()
        if parent <> invalid then ignored = parent.callFunc("requestBack")
    else if m.currentFocusedButton = 1 ' Chat
        m.top.toggleChat = true
        m.top.streamLayoutMode = (m.top.streamLayoutMode + 1) mod 3
    else if m.currentFocusedButton = 2 ' Play/Pause
        togglePlayPause()
    else if m.currentFocusedButton = 3 ' Quality
        showQualityDialog()
    else if m.currentFocusedButton = 4 and m.top.channelAvailable
        m.top.channelActionsRequested = true
    end if
end sub

sub togglePlayPause()
    if m.top.state = "paused"
        m.top.control = "resume"
    else
        m.top.control = "pause"
    end if
end sub

sub showQualityDialog()
    if m.top.qualityOptions <> invalid and m.top.qualityOptions.count() > 0
        ' Stop the fade timer when showing dialog
        m.fadeAwayTimer.control = "stop"
        setupQualityDialog()

        ' Scene.dialog owns native Back handling and restores the player on close.
        m.qualityDialogOpen = true
        m.qualityDialog.visible = true
        scene = m.top.getScene()
        if scene <> invalid then scene.dialog = m.qualityDialog
        m.qualityDialog.setFocus(true)
    else
        ' ? "[StitchVideo] No quality options available"
    end if
end sub

function convertToReadableTimeFormat(time) as string
    time = Int(time)
    if time < 3600
        minutes = Int(time / 60)
        seconds = Int(time mod 60)
        if seconds < 10
            secondStr = "0" + seconds.toStr()
        else
            secondStr = seconds.toStr()
        end if
        return minutes.toStr() + ":" + secondStr
    else
        hours = Int(time / 3600)
        minutes = Int((time mod 3600) / 60)
        seconds = Int(time mod 60)

        if minutes < 10
            minuteStr = "0" + minutes.toStr()
        else
            minuteStr = minutes.toStr()
        end if

        if seconds < 10
            secondStr = "0" + seconds.toStr()
        else
            secondStr = seconds.toStr()
        end if

        return hours.toStr() + ":" + minuteStr + ":" + secondStr
    end if
end function

sub showErrorMessage(title as string, message as string)
    showMessage(title, message, 0) ' 0 duration means persistent
end sub

sub hideErrorMessage()
    hideMessage()
end sub

sub showMessage(title as string, message as string, duration as float)
    createMessageOverlay()
    m.messageOverlay.translation = [Int((videoAreaWidth() - 640) / 2), 0]
    setPlayerMessage(m.messageOverlay, title, message)
    m.messageOverlay.visible = true

    ' Clear any existing auto-hide timer
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
        m.messageTimer = invalid
    end if

    ' Set up auto-hide timer if duration > 0
    if duration > 0
        m.messageTimer = CreateObject("roSGNode", "Timer")
        m.messageTimer.duration = duration
        m.messageTimer.repeat = false
        m.messageTimer.observeField("fire", "onMessageTimeout")
        m.messageTimer.control = "start"
    end if
end sub

sub hideMessage()
    if m.messageOverlay <> invalid
        m.messageOverlay.visible = false
    end if
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
        m.messageTimer = invalid
    end if
end sub

sub onMessageTimeout()
    hideMessage()
    m.messageTimer = invalid
end sub

sub showLoadingOverlay()
    if m.loadingOverlay <> invalid
        m.loadingOverlay.visible = true
    end if
    if m.loadingSpinner <> invalid
        m.loadingSpinner.control = "start"
    end if
end sub

sub hideLoadingOverlay()
    if m.loadingOverlay <> invalid
        m.loadingOverlay.visible = false
    end if
    if m.loadingSpinner <> invalid
        m.loadingSpinner.control = "stop"
    end if
end sub

function onKeyEvent(key, press) as boolean
    if m.disposed then return false
    if m.channelActionsOpen then return false
    ' ? "[StitchVideo] KeyEvent: "; key; " "; press

    if press
        ' If quality dialog is visible, only handle back to close it
        if m.qualityDialog.visible
            if key = "back" or key = "down"
                onQualityDialogClosed()
                return true
            end if
            ' Let dialog handle all other keys
            return false
        end if

        ' Normal key handling when dialog is not visible
        ' Reset fade timer on any key press (except back when overlay is hidden)
        if key <> "back" or m.isOverlayVisible
            if m.isOverlayVisible
                m.fadeAwayTimer.control = "stop"
                m.fadeAwayTimer.control = "start"
            end if
        end if

        return handleMainKeys(key)
    end if

    return false
end function

function handleMainKeys(key) as boolean
    if not m.isOverlayVisible
        if key = "play"
            ' The remote Play key acts on its first press and reveals the state.
            showOverlay()
            togglePlayPause()
            return true
        else if key = "up" or key = "OK"
            showOverlay()
            return true
        end if
    end if

    if not m.isOverlayVisible
        return false
    end if

    if key = "left"
        ' Live stream navigation: back(0) -> chat(1) -> play/pause(2) -> quality(3)
        if m.currentFocusedButton > 0
            focusButton(m.currentFocusedButton - 1)
        else
            lastButton = 3
            if m.top.channelAvailable then lastButton = 4
            focusButton(lastButton)
        end if
        return true
    else if key = "right"
        ' Live stream navigation: back(0) -> chat(1) -> play/pause(2) -> quality(3)
        lastButton = 3
        if m.top.channelAvailable then lastButton = 4
        if m.currentFocusedButton < lastButton
            focusButton(m.currentFocusedButton + 1)
        else
            focusButton(0) ' Wrap to back
        end if
        return true
    else if key = "down" or key = "back"
        hideOverlay()
        return true
    else if key = "OK"
        executeButtonAction()
        return true
    else if key = "play"
        togglePlayPause()
        return true
    end if

    return false
end function

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.videoTitle.callFunc("onDestroy")
    destroyAdCountdown()
    if m.fadeAwayTimer <> invalid
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.unobserveField("fire")
    end if
    if m.streamDetailsTimer <> invalid
        m.streamDetailsTimer.control = "stop"
        m.streamDetailsTimer.unobserveField("fire")
    end if
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
    end if
    if m.latencyLogTimer <> invalid
        m.latencyLogTimer.control = "stop"
        m.latencyLogTimer.unobserveField("fire")
    end if
    if m.liveEdgeStartupTimer <> invalid
        m.liveEdgeStartupTimer.control = "stop"
        m.liveEdgeStartupTimer.unobserveField("fire")
    end if
    if m.qualityDialog <> invalid
        m.qualityDialog.unobserveFieldScoped("buttonSelected")
        m.qualityDialog.unobserveFieldScoped("wasClosed")
        m.qualityDialogOpen = false
        m.qualityDialog.visible = false
        scene = m.top.getScene()
        if scene <> invalid and scene.dialog <> invalid
            if scene.dialog.isSameNode(m.qualityDialog) then scene.dialog = invalid
        end if
    end if
    m.top.unobserveField("position")
    m.top.unobserveField("state")
    m.top.unobserveField("content")
    m.top.unobserveField("chatIsVisible")
    m.top.unobserveField("duration")
    m.top.unobserveField("bufferingStatus")
    m.top.unobserveField("qualityOptions")
    m.top.unobserveField("selectedQuality")
    if m.loadingSpinner <> invalid then m.loadingSpinner.control = "stop"
    m.pendingSeekReason = invalid
    m.pendingSeekOutcomePreMs = invalid
    m.top.control = "stop"
end sub
