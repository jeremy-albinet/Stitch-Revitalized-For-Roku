sub init()
    ' Initialize UI elements
    m.top.enableUI = false
    m.top.enableTrickPlay = false

    ' Control overlay elements
    m.controlOverlay = m.top.findNode("controlOverlay")
    m.controlOverlay.visible = false

    ' Progress bar elements
    m.progressBarBase = m.top.findNode("progressBarBase")
    m.progressBarProgress = m.top.findNode("progressBarProgress")

    ' Control buttons
    m.backGroup = m.top.findNode("backGroup")
    m.chatGroup = m.top.findNode("chatGroup")
    m.playPauseGroup = m.top.findNode("playPauseGroup")
    m.qualityGroup = m.top.findNode("qualityGroup")
    m.controlButton = m.top.findNode("controlButton")
    m.messagesButton = m.top.findNode("messagesButton")
    m.qualitySelectButton = m.top.findNode("qualitySelectButton")

    ' Focus backgrounds
    m.backFocus = m.top.findNode("backFocus")
    m.chatFocus = m.top.findNode("chatFocus")
    m.playPauseFocus = m.top.findNode("playPauseFocus")
    m.qualityFocus = m.top.findNode("qualityFocus")

    ' Other elements
    m.liveIndicator = m.top.findNode("liveIndicator")

    ' Video info
    m.videoTitle = m.top.findNode("videoTitle")
    m.channelUsername = m.top.findNode("channelUsername")
    m.avatar = m.top.findNode("avatar")

    ' Loading overlay
    m.loadingOverlay = m.top.findNode("loadingOverlay")
    m.loadingSpinner = m.top.findNode("loadingSpinner")

    ' Quality dialog
    m.qualityDialog = m.top.findNode("QualityDialog")
    ' Set up quality dialog observer once during initialization
    m.qualityDialog.observeFieldScoped("buttonSelected", "onQualityButtonSelect")

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

    ' Live-edge latency diagnostic timer.
    ' Logs streamingSegment.latency every 5s while playing, so we can measure
    ' real-world distance from the live edge on a TV. See AGENTS.md / DEV.md
    ' for how to read these logs over the debug console.
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
    updateProgressBar()
    setupLiveUI()

    ' Show loading overlay initially
    showLoadingOverlay()

    ' ? "[StitchVideo] Initialized for live stream"
end sub

sub createMessageOverlay()
    if m.messageOverlay = invalid
        m.messageOverlay = CreateObject("roSGNode", "Group")
        m.messageOverlay.visible = false

        messageBg = CreateObject("roSGNode", "Rectangle")
        messageBg.width = 600
        messageBg.height = 150
        messageBg.color = "0x000000CC"
        messageBg.translation = [340, 285]

        messageTitle = CreateObject("roSGNode", "Label")
        messageTitle.id = "messageTitle"
        messageTitle.font = "font:MediumBoldSystemFont"
        messageTitle.text = ""
        messageTitle.horizAlign = "center"
        messageTitle.vertAlign = "center"
        messageTitle.width = 600
        messageTitle.height = 50
        messageTitle.translation = [340, 300]

        messageText = CreateObject("roSGNode", "Label")
        messageText.id = "messageText"
        messageText.font = "font:SmallSystemFont"
        messageText.text = ""
        messageText.horizAlign = "center"
        messageText.vertAlign = "center"
        messageText.width = 600
        messageText.height = 50
        messageText.translation = [340, 350]

        m.messageOverlay.appendChild(messageBg)
        m.messageOverlay.appendChild(messageTitle)
        m.messageOverlay.appendChild(messageText)
        m.top.appendChild(m.messageOverlay)
    end if
end sub

sub setupLiveUI()
    ' Set up UI specifically for live streams
    m.progressBarProgress.width = m.progressBarBase.width ' Full bar for live

    ' Live indicator is only visible when overlay is shown
    m.liveIndicator.visible = m.isOverlayVisible
end sub


sub onPositionChange()
    m.currentPositionSeconds = m.top.position
    ' Live streams don't need position-based updates
end sub

' Re-arm the one-shot startup seek when a fresh stream is loaded.
' Setting m.top.content fires this; we use it to reset the latched flag so
' the next stream session gets its own startup seek. Also clear the recent
' seek timestamp - otherwise the watchdog cooldown could be triggered by a
' stale value from the previous stream session.
sub onContentChange()
    if m.top.content <> invalid
        m.startupSeekFired = false
        m.top.recentSeekTimestamp = 0
    end if
end sub

sub onVideoStateChange()
    ? getLogTimestamp(); " [StitchVideo][state] state="; m.top.state; " pos="; m.top.position
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/pause.png"
        hideLoadingOverlay()
        hideMessage()
        startLatencyLog()
        ' Fire one immediate sample so we see latency even if the repeating
        ' timer is delayed/blocked for some reason.
        onLatencyLogFire()
        ' Arm the one-shot live-edge re-anchor (latched via m.startupSeekFired
        ' so it fires exactly once per stream session).
        startLiveEdgeStartupTimer()
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/play.png"
        hideLoadingOverlay()
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
    else if m.top.state = "buffering"
        showLoadingOverlay()
        stopLiveEdgeStartupTimer()
    else if m.top.state = "error"
        hideLoadingOverlay()
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
        if m.top.errorStr <> invalid and (m.top.errorStr.InStr("970") > -1 or m.top.errorStr.InStr("buffer:loop:demux") > -1)
            showErrorMessage("Incompatible Video Format", "This stream cannot be played on your device")
        else
            showErrorMessage("Stream Error", "Having trouble loading the live stream. Retrying...")
        end if
    else if m.top.state = "finished" or m.top.state = "stopped"
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

    if seg <> invalid
        segValid = "yes"
        if seg.segType <> invalid then segType = seg.segType.toStr()
        if seg.latency <> invalid then latencyMs = seg.latency.toStr()
        if seg.segBitrateBps <> invalid then bitrate = seg.segBitrateBps.toStr()
        if seg.segSequence <> invalid then segSeq = seg.segSequence.toStr()
    end if

    measured = m.top.measuredBitrate

    ? getLogTimestamp(); " [StitchVideo][latency] state="; m.top.state; " pos="; m.top.position; " seg_valid="; segValid; " seg_type="; segType; " live_edge_ms="; latencyMs; " seg_bitrate_bps="; bitrate; " measured_bps="; measured; " seg_seq="; segSeq
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

' Single point of seek=999999 application. Logs a snapshot of live_edge_ms
' before issuing the seek so we can compare against the next 5s latency log
' line. Bails if not in steady-state playing.
sub issueLiveEdgeSeek(reason as string)
    if m.top.state <> "playing"
        ? getLogTimestamp(); " [StitchVideo][seek] action=skip reason="; reason; " state="; m.top.state
        return
    end if

    seg = m.top.streamingSegment
    preLatency = "?"
    if seg <> invalid and seg.latency <> invalid
        preLatency = seg.latency.toStr()
    end if

    ? getLogTimestamp(); " [StitchVideo][seek] action=fire reason="; reason; " pre_live_edge_ms="; preLatency; " pos="; m.top.position
    ' Tell VideoPlayer's stall watchdog we just seeked so it doesn't treat
    ' the brief re-buffer that follows as a fake stall and force a reconnect.
    m.top.recentSeekTimestamp = CreateObject("roDateTime").AsSeconds()
    m.top.seek = 999999
end sub

sub onChatVisibilityChange()
    if m.top.chatIsVisible
        m.progressBarBase.width = 900
    else
        m.progressBarBase.width = 1160
    end if
    updateProgressBar()
end sub

sub onDurationChange()
    updateProgressBar()
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
end sub

sub setupQualityDialog()
    if m.top.qualityOptions <> invalid and m.top.qualityOptions.count() > 0
        m.qualityDialog.title = "Please Choose Your Video Quality"
        m.qualityDialog.message = ["Choose video quality:"]

        buttons = []
        for each quality in m.top.qualityOptions
            buttons.push(quality)
        end for
        buttons.push("Cancel")

        m.qualityDialog.buttons = buttons
    end if
end sub

sub onQualityButtonSelect()
    ' ? "[StitchVideo] Quality dialog button selected: "; m.qualityDialog.buttonSelected

    selectedIndex = m.qualityDialog.buttonSelected
    totalButtons = m.qualityDialog.buttons.count()

    ' Hide dialog first
    m.qualityDialog.visible = false
    m.qualityDialog.setFocus(false)

    ' Check if Cancel was selected (last button)
    if selectedIndex = totalButtons - 1
        ' ? "[StitchVideo] Cancel selected, no quality change"
    else if selectedIndex >= 0 and selectedIndex < m.top.qualityOptions.count()
        ' Valid quality option selected
        selectedQuality = m.top.qualityOptions[selectedIndex]
        ' ? "[StitchVideo] Quality selected: "; selectedQuality

        m.top.selectedQuality = selectedQuality
        m.top.QualityChangeRequest = selectedIndex
        m.top.QualityChangeRequestFlag = true
    else
        ' ? "[StitchVideo] Invalid selection index: "; selectedIndex
    end if

    ' Restore focus to video component
    m.top.setFocus(true)

    ' If overlay is visible, restart fade timer
    if m.isOverlayVisible
        focusButton(m.currentFocusedButton)
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.control = "start"
    end if
end sub

sub updateProgressBar()
    ' For live streams, always show full progress bar in Twitch purple
    m.progressBarProgress.width = m.progressBarBase.width
end sub

sub showOverlay()
    m.isOverlayVisible = true
    m.controlOverlay.visible = true
    m.liveIndicator.visible = true
    focusButton(m.currentFocusedButton)

    ' Start fade timer
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    m.liveIndicator.visible = false
    clearAllButtonFocus()
end sub

sub onFadeAway()
    ' Only hide overlay if quality dialog is not visible
    if not m.qualityDialog.visible
        hideOverlay()
    end if
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
    end if
end sub

sub clearAllButtonFocus()
    m.backFocus.visible = false
    m.chatFocus.visible = false
    m.playPauseFocus.visible = false
    m.qualityFocus.visible = false
end sub

sub executeButtonAction()
    if m.currentFocusedButton = 0 ' Back
        ' ? "[StitchVideo] Back button pressed - attempting to exit"
        m.top.backPressed = true
        if m.top.getParent() <> invalid
            m.top.getParent().backPressed = true
        end if
        hideOverlay()
        m.top.control = "stop"
    else if m.currentFocusedButton = 1 ' Chat
        m.top.toggleChat = true
        m.top.streamLayoutMode = (m.top.streamLayoutMode + 1) mod 3
    else if m.currentFocusedButton = 2 ' Play/Pause
        togglePlayPause()
    else if m.currentFocusedButton = 3 ' Quality
        showQualityDialog()
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

        ' Show dialog and give it focus
        ' (Observer is already set up in init() function)
        m.qualityDialog.visible = true
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
    if m.messageOverlay <> invalid
        titleNode = m.messageOverlay.findNode("messageTitle")
        if titleNode <> invalid
            titleNode.text = title
            titleNode.visible = (title <> "")
        end if
        messageNode = m.messageOverlay.findNode("messageText")
        if messageNode <> invalid
            messageNode.text = message
            if title = ""
                messageNode.translation = [340, 335]
            else
                messageNode.translation = [340, 350]
            end if
        end if
    end if

    m.messageOverlay.visible = true

    ' Clear any existing auto-hide timer
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
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
    ' ? "[StitchVideo] KeyEvent: "; key; " "; press

    if press
        ' If quality dialog is visible, only handle back to close it
        if m.qualityDialog.visible
            if key = "back" or key = "down"
                m.qualityDialog.visible = false
                m.qualityDialog.setFocus(false)
                m.top.setFocus(true)

                ' Restart fade timer if overlay is visible
                if m.isOverlayVisible
                    focusButton(m.currentFocusedButton)
                    m.fadeAwayTimer.control = "stop"
                    m.fadeAwayTimer.control = "start"
                end if
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
    if key = "up" or key = "OK" or key = "play"
        if not m.isOverlayVisible
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
            focusButton(3) ' Wrap to quality
        end if
        return true
    else if key = "right"
        ' Live stream navigation: back(0) -> chat(1) -> play/pause(2) -> quality(3)
        if m.currentFocusedButton < 3
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
    if m.fadeAwayTimer <> invalid
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.unobserveField("fire")
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
    end if
    m.top.unobserveField("position")
    m.top.unobserveField("state")
    m.top.unobserveField("content")
    m.top.unobserveField("chatIsVisible")
    m.top.unobserveField("duration")
    m.top.unobserveField("bufferingStatus")
    m.top.unobserveField("qualityOptions")
    m.top.unobserveField("selectedQuality")
end sub
