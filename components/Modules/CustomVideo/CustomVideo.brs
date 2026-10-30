sub init()
    m.disposed = false
    m.channelActionsOpen = false
    initAdCountdown()
    if m.adBadge <> invalid
        m.adBadge.adLabel = tr("Ad")
        m.adBadge.numberedAdLabel = tr("Ad {0} of {1}")
    end if
    m.top.observeField("content", "onAdContentChanged")
    ' Initialize UI elements
    m.top.enableUI = false
    m.top.enableTrickPlay = false

    ' Control overlay elements
    m.controlOverlay = m.top.findNode("controlOverlay")
    m.controlOverlay.visible = false
    m.controlsHint = m.top.findNode("controlsHint")
    m.controlsHint.text = tr("Press Down or Back to hide controls")
    m.scrim = m.top.findNode("scrim")
    m.scrimFade = m.top.findNode("scrimFade")
    m.scrimFadeFill = m.top.findNode("scrimFadeFill")
    m.infoRow = m.top.findNode("infoRow")
    m.seekHint = m.top.findNode("seekHint")
    m.controls = m.top.findNode("controls")
    m.caption = m.top.findNode("caption")
    m.captionPlate = m.top.findNode("captionPlate")
    m.captionLabel = m.top.findNode("captionLabel")

    ' Progress bar elements
    m.progressSection = m.top.findNode("progressSection")
    m.progressBarBase = m.top.findNode("progressBarBase")
    m.progressBarProgress = m.top.findNode("progressBarProgress")
    m.progressBarBuffer = m.top.findNode("progressBarBuffer")
    m.progressDot = m.top.findNode("progressDot")
    m.timeProgress = m.top.findNode("timeProgress")
    m.timeDuration = m.top.findNode("timeDuration")

    ' Control buttons
    m.playPauseGroup = m.top.findNode("playPauseGroup")
    m.rewindGroup = m.top.findNode("rewindGroup")
    m.fastForwardGroup = m.top.findNode("fastForwardGroup")
    m.timeTravelGroup = m.top.findNode("timeTravelGroup")
    m.chatGroup = m.top.findNode("chatGroup")
    m.backGroup = m.top.findNode("backGroup")
    m.channelGroup = m.top.findNode("channelGroup")
    m.channelFocus = m.top.findNode("channelFocus")
    m.controlButton = m.top.findNode("controlButton")
    m.buttonGroups = [m.backGroup, m.timeTravelGroup, m.rewindGroup, m.playPauseGroup, m.fastForwardGroup, m.chatGroup, m.channelGroup]

    ' Focus backgrounds
    m.playPauseFocus = m.top.findNode("playPauseFocus")
    m.rewindFocus = m.top.findNode("rewindFocus")
    m.fastForwardFocus = m.top.findNode("fastForwardFocus")
    m.timeTravelFocus = m.top.findNode("timeTravelFocus")
    m.chatFocus = m.top.findNode("chatFocus")
    m.backFocus = m.top.findNode("backFocus")

    ' Time travel dialog
    m.timeTravelDialog = m.top.findNode("timeTravelDialog")
    m.timeTravelLength = m.top.findNode("timeTravelLength")
    m.hour0 = m.top.findNode("hour0")
    m.hour1 = m.top.findNode("hour1")
    m.minute0 = m.top.findNode("minute0")
    m.minute1 = m.top.findNode("minute1")
    m.second0 = m.top.findNode("second0")
    m.second1 = m.top.findNode("second1")
    m.hour0Text = m.top.findNode("hour0Text")
    m.hour1Text = m.top.findNode("hour1Text")
    m.minute0Text = m.top.findNode("minute0Text")
    m.minute1Text = m.top.findNode("minute1Text")
    m.second0Text = m.top.findNode("second0Text")
    m.second1Text = m.top.findNode("second1Text")
    m.cancelButton = m.top.findNode("cancelButton")
    m.acceptButton = m.top.findNode("acceptButton")
    m.cancelButtonFocus = m.top.findNode("cancelButtonFocus")
    m.acceptButtonFocus = m.top.findNode("acceptButtonFocus")
    setTimeTravelText()

    ' Other elements
    m.thumbnailPreview = m.top.findNode("thumbnailPreview")
    m.thumbnailPlate = m.top.findNode("thumbnailPlate")
    m.thumbnails = m.top.findNode("thumbnails")
    m.thumbnailImage = m.top.findNode("thumbnailImage")
    m.thumbnailTime = m.top.findNode("thumbnailTime")
    m.liveIndicator = m.top.findNode("liveIndicator")
    m.loadingOverlay = m.top.findNode("loadingOverlay")
    m.loadingText = m.top.findNode("loadingText")
    m.loadingSpinner = m.top.findNode("loadingSpinner")
    if m.loadingText <> invalid then m.loadingText.text = tr("Loading video…")

    ' Video info
    m.videoTitle = m.top.findNode("videoTitle")
    m.channelUsername = m.top.findNode("channelUsername")
    m.avatar = m.top.findNode("avatar")
    m.liveBadgeWidth = fitLabelPlate(m.top.findNode("liveLabel"), m.top.findNode("liveBadge"), tr("LIVE"), 16, 56)

    ' State variables
    m.currentFocusedButton = 3 ' 0=back, 1=timetravel, 2=rewind, 3=play/pause, 4=fastforward, 5=chat
    m.isOverlayVisible = false
    m.isTimeTravelDialogOpen = false
    m.timeTravelFocusedField = 0 ' 0-5 for time fields, 6-7 for buttons
    m.currentPositionSeconds = 0
    m.currentPositionUpdated = false
    ' Seek preview: Rewind/Fast-forward and -10/+10 pause the video and move a
    ' preview position. Play (or OK on Play/Pause) applies it, Back cancels it,
    ' and either way the video returns to the state it had before the preview.
    m.isSeekMode = false
    m.preSeekWasPlaying = false
    m.buttonHeld = invalid
    m.scrollInterval = 10
    m.isLiveStream = false

    ' Time field references
    m.timeFields = [m.hour0, m.hour1, m.minute0, m.minute1, m.second0, m.second1]
    m.timeTexts = [m.hour0Text, m.hour1Text, m.minute0Text, m.minute1Text, m.second0Text, m.second1Text]
    m.timeButtons = [m.cancelButton, m.acceptButton]
    m.timeButtonFocus = [m.cancelButtonFocus, m.acceptButtonFocus]

    ' Timers
    m.fadeAwayTimer = createObject("roSGNode", "Timer")
    m.fadeAwayTimer.observeField("fire", "onFadeAway")
    m.fadeAwayTimer.repeat = false
    m.fadeAwayTimer.duration = 5
    m.fadeAwayTimer.control = "stop"

    ' Holding Rewind/Fast-forward accelerates the preview. A press steps 10 s
    ' at once; only a key still held after holdDelay starts the repeating,
    ' growing steps, so an ordinary tap is exactly one 10 s step.
    m.holdDelay = 0.4
    m.holdRepeat = 0.1
    m.buttonHoldTimer = createObject("roSGNode", "Timer")
    m.buttonHoldTimer.observeField("fire", "onButtonHold")
    m.buttonHoldTimer.repeat = false
    m.buttonHoldTimer.duration = m.holdDelay
    m.buttonHoldTimer.control = "stop"

    ' Observers
    m.top.observeField("position", "onPositionChange")
    m.top.observeField("state", "onVideoStateChange")
    m.top.observeField("chatIsVisible", "onChatVisibilityChange")
    m.top.observeField("duration", "onDurationChange")
    m.top.observeField("bufferingStatus", "onBufferingStatusChange")
    m.top.observeField("video_type", "onVideoTypeChange")

    ' Initialize UI
    layoutOverlay()
    updateProgressBar()

    ' Show loading overlay initially
    showLoadingOverlay()

    ? getLogTimestamp(); " [CustomVideo] Initialized"
end sub

sub setTimeTravelText()
    m.top.findNode("timeTravelTitle").text = tr("Jump to time")
    m.top.findNode("timeTravelHint").text = tr("Enter the time you want to jump to.")
    m.top.findNode("hoursLabel").text = tr("Hours")
    m.top.findNode("minutesLabel").text = tr("Minutes")
    m.top.findNode("secondsLabel").text = tr("Seconds")
    m.top.findNode("instructionsLabel").text = tr("Use ← → to move between digits and ↑ ↓ to change them.")
    m.top.findNode("cancelButtonLabel").text = tr("Cancel")
    m.top.findNode("acceptButtonLabel").text = tr("Jump")
end sub

sub createMessageOverlay()
    if m.messageOverlay = invalid
        m.messageOverlay = createPlayerMessageOverlay()
        m.top.appendChild(m.messageOverlay)
    end if
end sub

' The video area is 1280 wide, or 960 when chat is shown beside it.
function videoAreaWidth() as integer
    if m.top.chatIsVisible = true then return 960
    return 1280
end function

sub layoutOverlay()
    if m.adBadge <> invalid then m.adBadge.videoAreaWidth = videoAreaWidth()
    width = videoAreaWidth()
    m.scrim.width = width
    m.controlsHint.width = width - 96
    m.scrimFadeFill.width = width
    m.scrimFade.maskSize = [width, 48]
    barWidth = width - 96
    m.progressBarBase.width = barWidth
    m.timeDuration.translation = [barWidth - 240, 0]
    m.seekHint.width = barWidth
    if width < 1280
        m.videoTitle.maxWidth = 660
    else
        m.videoTitle.maxWidth = 900
    end if
    if m.loadingOverlay <> invalid then m.loadingOverlay.translation = [Int(width / 2), 360]
    if m.messageOverlay <> invalid then m.messageOverlay.translation = [Int((width - 640) / 2), 0]
    layoutControls()
end sub

' Places the visible buttons side by side as one group centered in the video
' area, so the hidden seek buttons of a live stream leave no gap.
sub layoutControls()
    x = 0
    for each button in m.buttonGroups
        if button.visible
            button.translation = [x, 0]
            x += 76
        end if
    end for
    groupWidth = x - 12
    m.controls.translation = [Int((videoAreaWidth() - groupWidth) / 2), 214]
    updateCaption()
end sub

function focusedButtonNode() as object
    if m.isLiveStream
        return [m.backGroup, m.playPauseGroup, m.chatGroup][m.currentFocusedButton]
    end if
    return m.buttonGroups[m.currentFocusedButton]
end function

sub onChannelAvailableChange()
    if m.disposed or m.channelGroup = invalid then return
    m.channelGroup.visible = m.top.channelAvailable and not m.isLiveStream
    if not m.channelGroup.visible and m.currentFocusedButton = 6 then focusButton(3)
    layoutControls()
end sub

function captionForButton() as string
    node = focusedButtonNode()
    if node = invalid then return ""
    if node.isSameNode(m.backGroup)
        return tr("Exit player")
    else if node.isSameNode(m.timeTravelGroup)
        return tr("Jump to time")
    else if node.isSameNode(m.rewindGroup)
        return tr("Back 10 seconds")
    else if node.isSameNode(m.playPauseGroup)
        if m.isSeekMode then return tr("Jump to {0}").replace("{0}", convertToReadableTimeFormat(m.currentPositionSeconds))
        if m.top.state = "paused" then return tr("Play")
        return tr("Pause")
    else if node.isSameNode(m.fastForwardGroup)
        return tr("Forward 10 seconds")
    else if node.isSameNode(m.chatGroup)
        if not m.isLiveStream then return tr("Chat replay unavailable")
        if m.top.chatIsVisible = true then return tr("Hide chat")
        return tr("Show chat")
    else if node.isSameNode(m.channelGroup)
        return tr("Channel actions")
    end if
    return ""
end function

' Every focused control names itself in a caption above it.
sub updateCaption()
    if m.caption = invalid then return
    node = focusedButtonNode()
    if not m.isOverlayVisible or node = invalid
        m.caption.visible = false
        return
    end if
    plateWidth = fitLabelPlate(m.captionLabel, m.captionPlate, captionForButton(), 24, 96)
    center = m.controls.translation[0] + node.translation[0] + 32
    m.caption.translation = [clampToVideoArea(center - Int(plateWidth / 2), plateWidth), 178]
    m.caption.visible = true
end sub

function clampToVideoArea(x as integer, width as integer) as integer
    limit = videoAreaWidth() - 48 - width
    if x > limit then x = limit
    if x < 48 then x = 48
    return x
end function

sub onVideoTypeChange()
    m.isLiveStream = (m.top.video_type = "LIVE")
    updateUIForVideoType()

    ' Update loading text based on video type
    if m.loadingText <> invalid
        if m.isLiveStream
            m.loadingText.text = tr("Loading stream…")
        else
            m.loadingText.text = tr("Loading video…")
        end if
    end if
end sub

sub updateUIForVideoType()
    if m.isLiveStream
        ' Hide seek-related controls for live streams
        m.rewindGroup.visible = false
        m.fastForwardGroup.visible = false
        m.timeTravelGroup.visible = false
        m.progressSection.visible = false
        m.liveIndicator.visible = true
        m.channelUsername.translation = [64 + m.liveBadgeWidth + 12, 0]

        ' Adjust button focus indices for live streams
        ' 0=back, 1=play/pause, 2=chat
        if m.currentFocusedButton = 1 or m.currentFocusedButton = 2 or m.currentFocusedButton = 4
            m.currentFocusedButton = 1 ' Focus play/pause for live
        end if
        focusButton(m.currentFocusedButton) ' <-- keep focus visuals in sync
    else
        ' Show all controls for VOD/clips
        m.rewindGroup.visible = true
        m.fastForwardGroup.visible = true
        m.timeTravelGroup.visible = true
        m.progressSection.visible = true
        m.liveIndicator.visible = false
        m.channelUsername.translation = [64, 0]
    end if
    layoutControls()
end sub

sub onPositionChange()
    if not m.isSeekMode
        m.currentPositionSeconds = m.top.position
        updateProgressBar()
    end if

    ' Auto-save bookmark every 20 seconds (not for live streams)
    if not m.isLiveStream
        checker = Int(m.top.position) mod 20
        if checker = 0 and (m._lastBookmarkSecond = invalid or m._lastBookmarkSecond <> Int(m.top.position))
            m._lastBookmarkSecond = Int(m.top.position)
            saveVideoBookmark()
        end if
    end if
end sub

sub onVideoStateChange()
    if m.disposed then return
    updateAdPresented()
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/pause.png"
        hideLoadingOverlay()
        hideMessage()
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/play.png"
        hideLoadingOverlay()
    else if m.top.state = "buffering"
        showLoadingOverlay()
        if m.loadingText <> invalid
            if m.isLiveStream
                m.loadingText.text = tr("Buffering stream…")
            else
                m.loadingText.text = tr("Buffering video…")
            end if
        end if
    else if m.top.state = "error"
        hideLoadingOverlay()
        ? getLogTimestamp(); " [CustomVideo] Video error occurred"
        if m.top.errorStr <> invalid and (m.top.errorStr.InStr("970") > -1 or m.top.errorStr.InStr("buffer:loop:demux") > -1)
            showErrorMessage(tr("Video format not supported"), tr("This video can't be played on this Roku."))
        else
            showErrorMessage(tr("Stream problem"), tr("Having trouble loading the video. Retrying…"))
        end if
    end if
    if m.currentFocusedButton = 3 or m.isLiveStream then updateCaption()

    ' Show live indicator for live streams
    m.liveIndicator.visible = m.isLiveStream
end sub

sub onChatVisibilityChange()
    ' Adjust layout based on chat visibility
    layoutOverlay()

    ' Update all progress bar elements to match new width
    updateProgressBar()

    ' Update buffer bar if buffering status is available
    if m.top.bufferingStatus <> invalid
        bufferPercent = m.top.bufferingStatus.percentage
        if bufferPercent <> invalid and m.top.duration > 0
            bufferWidth = m.progressBarBase.width * (bufferPercent / 100)
            m.progressBarBuffer.width = bufferWidth
        end if
    end if
end sub

sub onDurationChange()
    updateProgressBar()
    ' Update UI when duration is available
    updateUIForVideoType()
end sub

sub onBufferingStatusChange()
    if m.top.bufferingStatus <> invalid
        bufferPercent = m.top.bufferingStatus.percentage
        if bufferPercent <> invalid and m.top.duration > 0
            bufferWidth = m.progressBarBase.width * (bufferPercent / 100)
            m.progressBarBuffer.width = bufferWidth
        end if
    end if
end sub

sub updateProgressBar()
    if m.isLiveStream
        ' Live streams show the LIVE badge instead of a progress bar.
        m.timeProgress.text = tr("LIVE")
        m.timeDuration.text = ""
        m.progressBarProgress.width = m.progressBarBase.width
    else if m.top.duration > 0 and m.currentPositionSeconds >= 0
        ' Update progress bar for VOD/clips
        progressRatio = m.currentPositionSeconds / m.top.duration
        m.progressBarProgress.width = m.progressBarBase.width * progressRatio

        ' Keep the knob inside the bar
        dotX = Int(m.progressBarBase.width * progressRatio) - 7
        if dotX < 0 then dotX = 0
        if dotX > m.progressBarBase.width - 14 then dotX = m.progressBarBase.width - 14

        m.progressDot.translation = [dotX, 26]
        m.progressDot.visible = true

        ' Update time displays
        m.timeProgress.text = convertToReadableTimeFormat(m.currentPositionSeconds)
        m.timeDuration.text = convertToReadableTimeFormat(m.top.duration)
    end if
end sub

sub showOverlay()
    m.isOverlayVisible = true
    m.controlOverlay.visible = true
    updateUIForVideoType() ' Ensure UI is correct for video type
    focusButton(m.currentFocusedButton)
    restartFade()
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    m.thumbnailPreview.visible = false
    clearAllButtonFocus()
    updateCaption()
end sub

sub restartFade()
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub onFadeAway()
    if m.channelActionsOpen then return
    ' A pending seek preview or the time dialog keeps the controls on screen.
    if m.isTimeTravelDialogOpen or m.isSeekMode then return
    hideOverlay()
end sub

sub setChannelActionsOpen(open as boolean)
    if m.disposed then return
    m.channelActionsOpen = open
    if open then stopHold()
    m.fadeAwayTimer.control = "stop"
    if not open and m.isOverlayVisible then m.fadeAwayTimer.control = "start"
end sub

sub focusButton(buttonIndex)
    clearAllButtonFocus()

    if m.isLiveStream
        ' Adjust button indices for live streams (only back, play/pause, chat available)
        if buttonIndex = 0 ' Back
            m.currentFocusedButton = 0
            m.backFocus.visible = true
        else if buttonIndex = 1 or buttonIndex = 2 or buttonIndex = 3 or buttonIndex = 4 ' Any middle button -> play/pause
            m.currentFocusedButton = 1
            m.playPauseFocus.visible = true
        else if buttonIndex = 5 ' Chat
            m.currentFocusedButton = 2
            m.chatFocus.visible = true
        end if
    else
        ' Normal button handling for VOD/clips
        m.currentFocusedButton = buttonIndex
        if buttonIndex = 0 ' Back
            m.backFocus.visible = true
        else if buttonIndex = 1 ' Time Travel
            m.timeTravelFocus.visible = true
        else if buttonIndex = 2 ' Rewind
            m.rewindFocus.visible = true
        else if buttonIndex = 3 ' Play/Pause
            m.playPauseFocus.visible = true
        else if buttonIndex = 4 ' Fast Forward
            m.fastForwardFocus.visible = true
        else if buttonIndex = 5 ' Chat
            m.chatFocus.visible = true
        else if buttonIndex = 6
            m.channelFocus.visible = true
        end if
    end if
    updateCaption()
    if m.isSeekMode then updateSeekHint()
end sub

sub clearAllButtonFocus()
    m.playPauseFocus.visible = false
    m.rewindFocus.visible = false
    m.fastForwardFocus.visible = false
    m.timeTravelFocus.visible = false
    m.chatFocus.visible = false
    m.backFocus.visible = false
    m.channelFocus.visible = false
end sub

sub executeButtonAction()
    if m.disposed then return
    if not m.isLiveStream and m.currentFocusedButton = 6 and m.top.channelAvailable
        m.top.channelActionsRequested = true
        return
    end if
    if m.isLiveStream
        ' Live stream button actions
        if m.currentFocusedButton = 0 ' Back
            ? getLogTimestamp(); " [CustomVideo] Back button pressed - attempting to exit"
            m.top.back = true
            if m.top.getParent() <> invalid
                m.top.getParent().back = true
            end if
            hideOverlay()
            m.top.control = "stop"
        else if m.currentFocusedButton = 1 ' Play/Pause
            togglePlayPause()
        else if m.currentFocusedButton = 2 ' Chat
            m.top.toggleChat = true
            m.top.streamLayoutMode = (m.top.streamLayoutMode + 1) mod 3
        end if
    else
        ' VOD/Clips button actions
        if m.currentFocusedButton = 0 ' Back
            ? getLogTimestamp(); " [CustomVideo] Back button pressed - attempting to exit"
            m.top.back = true
            if m.top.getParent() <> invalid
                m.top.getParent().back = true
            end if
            hideOverlay()
            m.top.control = "stop"
        else if m.currentFocusedButton = 1 ' Time Travel
            if m.isSeekMode then cancelSeekPreview()
            openTimeTravelDialog()
        else if m.currentFocusedButton = 2 ' Rewind
            seekRelative(-10)
        else if m.currentFocusedButton = 3 ' Play/Pause
            togglePlayPause()
        else if m.currentFocusedButton = 4 ' Fast Forward
            seekRelative(10)
        else if m.currentFocusedButton = 5 ' Chat
            m.top.toggleChat = true
            m.top.streamLayoutMode = (m.top.streamLayoutMode + 1) mod 3
        end if
    end if
end sub

sub togglePlayPause()
    if m.isSeekMode and not m.isLiveStream
        applySeekPreview()
    else
        ' Toggle play/pause
        if m.top.state = "paused"
            m.top.control = "resume"
        else
            m.top.control = "pause"
        end if
    end if
end sub

sub seekRelative(seconds)
    if m.isLiveStream
        ? getLogTimestamp(); " [CustomVideo] Seeking disabled for live streams"
        return
    end if
    if m.top.duration <= 0 then return

    if not m.isSeekMode then beginSeekPreview()

    m.currentPositionSeconds += seconds
    if m.currentPositionSeconds < 0
        m.currentPositionSeconds = 0
    else if m.currentPositionSeconds > m.top.duration
        m.currentPositionSeconds = m.top.duration
    end if

    updateProgressBar()
    showThumbnailPreview()
    updateSeekHint()
end sub

' Starts a preview at the current playback position. The video pauses while
' the preview moves; the earlier playing/paused state is restored afterwards.
sub beginSeekPreview()
    m.currentPositionSeconds = m.top.position
    m.preSeekWasPlaying = (m.top.state = "playing" or m.top.state = "buffering")
    m.isSeekMode = true
    m.top.control = "pause"
    m.fadeAwayTimer.control = "stop"
    m.infoRow.visible = false
    m.seekHint.visible = true
    m.controlsHint.visible = false
    m.progressDot.color = knobColor(true)
    updateCaption()
end sub

sub applySeekPreview()
    if not m.isSeekMode then return
    target = m.currentPositionSeconds
    resume = m.preSeekWasPlaying
    endSeekPreview()
    m.top.seek = target
    if resume then m.top.control = "resume"
end sub

sub cancelSeekPreview()
    if not m.isSeekMode then return
    resume = m.preSeekWasPlaying
    endSeekPreview()
    m.currentPositionSeconds = m.top.position
    updateProgressBar()
    if resume then m.top.control = "resume"
end sub

sub endSeekPreview()
    stopHold()
    m.isSeekMode = false
    m.preSeekWasPlaying = false
    m.currentPositionUpdated = false
    m.thumbnailPreview.visible = false
    m.seekHint.visible = false
    m.controlsHint.visible = true
    m.infoRow.visible = true
    m.progressDot.color = knobColor(false)
    updateCaption()
    if m.isOverlayVisible then restartFade()
end sub

' The knob turns focus purple while a preview position is pending.
function knobColor(seeking as boolean) as string
    color = m.global?.constants?.ui?.color
    if color = invalid then return "0xEFEFF1FF"
    if seeking then return color.focus
    return color.text
end function

sub updateSeekHint()
    if m.currentFocusedButton = 3 then updateCaption()
    time = convertToReadableTimeFormat(m.currentPositionSeconds)
    ' OK applies only from Play/Pause; the remote Play key applies anywhere.
    if m.currentFocusedButton = 3
        m.seekHint.text = tr("Press OK or Play to jump to {0}. Press Back to cancel.").replace("{0}", time)
    else
        m.seekHint.text = tr("Press Play to jump to {0}. Press Back to cancel.").replace("{0}", time)
    end if
end sub

sub startHold(direction as string)
    m.buttonHeld = direction
    m.scrollInterval = 10
    m.buttonHoldTimer.control = "stop"
    m.buttonHoldTimer.duration = m.holdDelay
    m.buttonHoldTimer.control = "start"
end sub

sub stopHold()
    m.buttonHoldTimer.control = "stop"
    m.buttonHeld = invalid
    m.scrollInterval = 10
end sub

sub showThumbnailPreview()
    if m.isLiveStream
        return ' No thumbnails for live streams
    end if
    if m.top.duration <= 0 then return
    info = m.top.thumbnailInfo
    if info = invalid or info.interval = invalid or info.cols = invalid or info.count = invalid then return
    if info.interval <= 0 or info.cols <= 0 or info.count <= 0 then return
    if info.width = invalid or info.height = invalid or info.width <= 0 or info.height <= 0 then return

    m.thumbnailPreview.visible = true
    m.thumbnailTime.text = convertToReadableTimeFormat(m.currentPositionSeconds)

    ' Show one sprite cell scaled to a 240 px wide frame.
    scale = 240 / info.width
    imageHeight = Int(info.height * scale)
    m.thumbnails.scale = [scale, scale]
    m.thumbnails.clippingRect = [0, 0, info.width, info.height]
    m.thumbnailTime.translation = [0, imageHeight + 8]
    m.thumbnailPlate.height = imageHeight + 42

    ' Guard against divide-by-zero and invalid thumbnail_parts
    if info.thumbnail_parts <> invalid and info.thumbnail_parts.Count() > 0
        thumbnailsPerPart = Int(info.count / info.thumbnail_parts.Count())

        if thumbnailsPerPart > 0
            thumbnailPosOverall = Int(m.currentPositionSeconds / info.interval)
            thumbnailPosCurrent = thumbnailPosOverall mod thumbnailsPerPart
            thumbnailRow = Int(thumbnailPosCurrent / info.cols)
            thumbnailCol = Int(thumbnailPosCurrent mod info.cols)

            m.thumbnailImage.translation = [-thumbnailCol * info.width, -thumbnailRow * info.height]

            ' Check bounds before accessing thumbnail_parts array
            partIndex = Int(thumbnailPosOverall / thumbnailsPerPart)
            if info.info_url <> invalid and partIndex < info.thumbnail_parts.Count() and info.thumbnail_parts[partIndex] <> invalid
                m.thumbnailImage.uri = info.info_url + info.thumbnail_parts[partIndex]
            end if
        end if
    end if

    ' Float the frame above the knob, inside the video area.
    progressRatio = m.currentPositionSeconds / m.top.duration
    frameX = clampToVideoArea(48 + Int(m.progressBarBase.width * progressRatio) - 124, 248)
    m.thumbnailPreview.translation = [frameX, 480 - (imageHeight + 42)]
end sub

sub openTimeTravelDialog()
    if m.isLiveStream
        ? getLogTimestamp(); " [CustomVideo] Time travel disabled for live streams"
        return
    end if

    m.isTimeTravelDialogOpen = true
    m.timeTravelDialog.visible = true
    m.timeTravelDialog.translation = [Int((videoAreaWidth() - 600) / 2), 168]
    ' The digits cannot go past the end, so state the limit up front.
    if m.top.duration > 0
        m.timeTravelLength.text = tr("Video length: {0}").replace("{0}", convertToReadableTimeFormat(m.top.duration))
    else
        m.timeTravelLength.text = ""
    end if
    m.timeTravelFocusedField = 0
    focusTimeTravelField(0)

    ' Reset all time values
    for i = 0 to 5
        m.timeTexts[i].text = "0"
    end for
end sub

sub closeTimeTravelDialog()
    m.isTimeTravelDialogOpen = false
    m.timeTravelDialog.visible = false
    clearTimeTravelFocus()
    if m.isOverlayVisible then restartFade()
end sub

sub focusTimeTravelField(fieldIndex)
    clearTimeTravelFocus()
    m.timeTravelFocusedField = fieldIndex

    if fieldIndex >= 0 and fieldIndex <= 5
        ' Focus time field
        m.timeFields[fieldIndex].visible = true
    else if fieldIndex = 6
        ' Focus cancel button
        m.timeButtonFocus[0].visible = true
    else if fieldIndex = 7
        ' Focus accept button
        m.timeButtonFocus[1].visible = true
    end if
end sub

sub clearTimeTravelFocus()
    for i = 0 to 5
        m.timeFields[i].visible = false
    end for
    m.timeButtonFocus[0].visible = false
    m.timeButtonFocus[1].visible = false
end sub

sub executeTimeTravelAction()
    if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
        ' Move to buttons
        focusTimeTravelField(6)
    else if m.timeTravelFocusedField = 6
        ' Cancel
        closeTimeTravelDialog()
    else if m.timeTravelFocusedField = 7
        ' Accept - jump to time
        jumpToTime = getTimeTravelTime()

        ' Ensure we're not in seek mode when applying time travel
        m.isSeekMode = false
        m.currentPositionUpdated = false

        ' Apply the seek immediately
        m.top.seek = jumpToTime

        ' Update our internal position tracking
        m.currentPositionSeconds = jumpToTime

        ' Update the progress bar to reflect the new position
        updateProgressBar()

        ' Hide thumbnail preview if it was visible
        m.thumbnailPreview.visible = false

        closeTimeTravelDialog()
    end if
end sub

function getTimeTravelTime() as integer
    hour0 = Int(Val(m.timeTexts[0].text)) * 36000
    hour1 = Int(Val(m.timeTexts[1].text)) * 3600
    minute0 = Int(Val(m.timeTexts[2].text)) * 600
    minute1 = Int(Val(m.timeTexts[3].text)) * 60
    second0 = Int(Val(m.timeTexts[4].text)) * 10
    second1 = Int(Val(m.timeTexts[5].text))
    return hour0 + hour1 + minute0 + minute1 + second0 + second1
end function

sub changeTimeTravelValue(direction)
    if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
        currentValue = Int(Val(m.timeTexts[m.timeTravelFocusedField].text))

        ' Store old value for rollback if needed
        oldValue = currentValue
        if direction > 0
            currentValue += 1
        else
            currentValue -= 1
        end if

        ' Apply limits based on field type
        if m.timeTravelFocusedField = 2 or m.timeTravelFocusedField = 4 ' Minutes/seconds tens
            if currentValue > 5 then currentValue = 0
            if currentValue < 0 then currentValue = 5
        else
            if currentValue > 9 then currentValue = 0
            if currentValue < 0 then currentValue = 9
        end if

        m.timeTexts[m.timeTravelFocusedField].text = currentValue.toStr()
        ' Validate total time doesn't exceed video duration
        totalTime = getTimeTravelTime()
        if totalTime > m.top.duration and m.top.duration > 0
            ' Rollback to old value if exceeded
            m.timeTexts[m.timeTravelFocusedField].text = oldValue.toStr()
        end if
    end if
end sub

' Fires once holdDelay after a Rewind/Fast-forward press that is still held,
' then every holdRepeat while it stays held, each step 5 s larger.
sub onButtonHold()
    if m.disposed or m.isLiveStream or m.buttonHeld = invalid then return
    if m.buttonHeld = "left"
        seekRelative(-m.scrollInterval)
    else if m.buttonHeld = "right"
        seekRelative(m.scrollInterval)
    end if
    m.scrollInterval += 5
    if m.buttonHeld = invalid then return
    m.buttonHoldTimer.duration = m.holdRepeat
    m.buttonHoldTimer.control = "start"
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

sub saveVideoBookmark()
    ' Bookmark saving logic (keeping your existing implementation)
    if m.top.video_type = "LIVE" or m.top.video_type = "VOD"
        bookmarkPosition = Int(m.top.position)
        if m.top.video_type = "LIVE" and m.top?.content?.createdAt <> invalid
            secondsSincePublished = createObject("roDateTime")
            secondsSincePublished.FromISO8601String(m.top.content.createdAt.toStr())
            currentTime = createObject("roDateTime").AsSeconds()
            bookmarkPosition = currentTime - secondsSincePublished.AsSeconds()
        end if

        if get_user_setting("id", invalid) <> invalid
            m.bookmarkTask = destroyTask(m.bookmarkTask, "response")
            m.bookmarkTask = createObject("roSGNode", "TwitchApiTask")
            m.bookmarkTask.functionname = "updateUserViewedVideo"
            m.bookmarkTask.request = {
                "userId": get_user_setting("id"),
                "position": bookmarkPosition,
                "videoId": m.top.video_id,
                "videoType": m.top.video_type
            }
            m.bookmarkTask.control = "run"
        end if
    end if
end sub

sub showErrorMessage(title as string, message as string)
    showMessage(title, message, 0)
end sub

sub hideErrorMessage()
    hideMessage()
end sub

sub showMessage(title as string, message as string, duration as float)
    createMessageOverlay()
    m.messageOverlay.translation = [Int((videoAreaWidth() - 640) / 2), 0]
    setPlayerMessage(m.messageOverlay, title, message)
    m.messageOverlay.visible = true

    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
        m.messageTimer = invalid
    end if

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
    ? getLogTimestamp(); " [CustomVideo] KeyEvent: "; key; " "; press

    if press
        ' Reset fade timer on any key press
        if m.isOverlayVisible then restartFade()

        if m.isTimeTravelDialogOpen
            return handleTimeTravelKeys(key)
        else
            return handleMainKeys(key)
        end if
    else
        ' Releasing Rewind/Fast-forward ends the hold; the preview stays
        ' until Play applies it or Back cancels it.
        if key = "rewind" or key = "fastforward" then stopHold()
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
        else if (key = "rewind" or key = "fastforward") and not m.isLiveStream
            ' Show the seek preview, then use the shared hold/seek handling below.
            showOverlay()
        end if
    end if

    if not m.isOverlayVisible
        return false
    end if

    if key = "left"
        if m.isLiveStream
            ' Live stream navigation: back(0) -> play/pause(1) -> chat(2)
            if m.currentFocusedButton > 0
                focusButton(m.currentFocusedButton - 1)
            else
                focusButton(2) ' Wrap to chat
            end if
        else
            ' Normal navigation
            if m.currentFocusedButton > 0
                focusButton(m.currentFocusedButton - 1)
            else
                lastButton = 5
                if m.top.channelAvailable then lastButton = 6
                focusButton(lastButton)
            end if
        end if
        return true
    else if key = "right"
        if m.isLiveStream
            ' Live stream navigation: back(0) -> play/pause(1) -> chat(2)
            if m.currentFocusedButton < 2
                focusButton(m.currentFocusedButton + 1)
            else
                focusButton(0) ' Wrap to back
            end if
        else
            ' Normal navigation
            lastButton = 5
            if m.top.channelAvailable then lastButton = 6
            if m.currentFocusedButton < lastButton
                focusButton(m.currentFocusedButton + 1)
            else
                focusButton(0) ' Wrap to back button
            end if
        end if
        return true
    else if key = "back" and m.isSeekMode
        ' Back cancels a pending preview and keeps the controls on screen.
        cancelSeekPreview()
        return true
    else if key = "down" or key = "back"
        ' Hiding the controls also drops a pending preview, so no paused
        ' video is left with an invisible, unapplied seek.
        cancelSeekPreview()
        hideOverlay()
        return true
    else if key = "OK"
        executeButtonAction()
        return true
    else if key = "play"
        togglePlayPause()
        return true
    else if key = "rewind" or key = "fastforward"
        if not m.isLiveStream
            direction = "right"
            if key = "rewind" then direction = "left"
            ' A repeated press of the key already held is the same hold.
            if m.buttonHeld = direction then return true
            startHold(direction)
            if key = "rewind"
                seekRelative(-10)
            else
                seekRelative(10)
            end if
        end if
        return true
    end if

    return false
end function

function handleTimeTravelKeys(key) as boolean
    if key = "left"
        if m.timeTravelFocusedField > 0
            focusTimeTravelField(m.timeTravelFocusedField - 1)
        end if
        return true
    else if key = "right"
        if m.timeTravelFocusedField < 7
            focusTimeTravelField(m.timeTravelFocusedField + 1)
        end if
        return true
    else if key = "up"
        if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
            changeTimeTravelValue(1)
        else if m.timeTravelFocusedField = 6
            focusTimeTravelField(5)
        else if m.timeTravelFocusedField = 7
            focusTimeTravelField(5)
        end if
        return true
    else if key = "down"
        if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
            changeTimeTravelValue(-1)
        else if m.timeTravelFocusedField <= 5
            focusTimeTravelField(6)
        end if
        return true
    else if key = "OK"
        executeTimeTravelAction()
        return true
    else if key = "back"
        closeTimeTravelDialog()
        return true
    end if

    return false
end function

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    destroyAdCountdown()
    m.top.unobserveField("content")
    m.bookmarkTask = destroyTask(m.bookmarkTask, "response")
    if m.fadeAwayTimer <> invalid
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.unobserveField("fire")
    end if
    if m.buttonHoldTimer <> invalid
        m.buttonHoldTimer.control = "stop"
        m.buttonHoldTimer.unobserveField("fire")
    end if
    m.buttonHeld = invalid
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
    end if
    m.top.unobserveField("position")
    m.top.unobserveField("state")
    m.top.unobserveField("chatIsVisible")
    m.top.unobserveField("duration")
    m.top.unobserveField("bufferingStatus")
    m.top.unobserveField("video_type")
    if m.loadingSpinner <> invalid then m.loadingSpinner.control = "stop"
    if m.timeTravelDialog <> invalid then m.timeTravelDialog.visible = false
    m.top.control = "stop"
end sub

sub onAdContentChanged()
    ignored = clearAdCountdown(m.adOwner)
end sub
