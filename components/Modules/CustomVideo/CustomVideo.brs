function init()
    ' Initialize UI elements
    m.top.enableUI = false
    m.top.enableTrickPlay = false

    ' Control overlay elements
    m.controlOverlay = m.top.findNode("controlOverlay")
    m.controlOverlay.visible = false

    ' Progress bar elements
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
    m.controlButton = m.top.findNode("controlButton")

    ' Focus backgrounds
    m.playPauseFocus = m.top.findNode("playPauseFocus")
    m.rewindFocus = m.top.findNode("rewindFocus")
    m.fastForwardFocus = m.top.findNode("fastForwardFocus")
    m.timeTravelFocus = m.top.findNode("timeTravelFocus")
    m.chatFocus = m.top.findNode("chatFocus")
    m.backFocus = m.top.findNode("backFocus")

    ' Time travel dialog
    m.timeTravelDialog = m.top.findNode("timeTravelDialog")
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

    ' Other elements
    m.thumbnailPreview = m.top.findNode("thumbnailPreview")
    m.thumbnails = m.top.findNode("thumbnails")
    m.thumbnailImage = m.top.findNode("thumbnailImage")
    m.thumbnailTime = m.top.findNode("thumbnailTime")
    m.liveIndicator = m.top.findNode("liveIndicator")
    m.loadingSpinner = m.top.findNode("loadingSpinner")

    ' Video info
    m.videoTitle = m.top.findNode("videoTitle")
    m.channelUsername = m.top.findNode("channelUsername")
    m.avatar = m.top.findNode("avatar")

    ' State variables
    m.currentFocusedButton = 3 ' 0=back, 1=timetravel, 2=rewind, 3=play/pause, 4=fastforward, 5=chat
    m.isOverlayVisible = false
    m.isTimeTravelDialogOpen = false
    m.timeTravelFocusedField = 0 ' 0-5 for time fields, 6-7 for buttons
    m.currentPositionSeconds = 0
    m.currentPositionUpdated = false
    m.isSeekMode = false
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

    m.buttonHoldTimer = createObject("roSGNode", "Timer")
    m.buttonHoldTimer.observeField("fire", "onButtonHold")
    m.buttonHoldTimer.repeat = true
    m.buttonHoldTimer.duration = 0.1
    m.buttonHoldTimer.control = "stop"

    ' Observers
    m.top.observeField("position", "onPositionChange")
    m.top.observeField("state", "onVideoStateChange")
    m.top.observeField("chatIsVisible", "onChatVisibilityChange")
    m.top.observeField("duration", "onDurationChange")
    m.top.observeField("bufferingStatus", "onBufferingStatusChange")
    m.top.observeField("video_type", "onVideoTypeChange")

    ' Pre-create message overlay to avoid runtime overhead
    createMessageOverlay()
    
    ' Initialize UI
    updateProgressBar()

    ? "[CustomVideo] Initialized"
end function

sub createMessageOverlay()
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
end sub

sub onVideoTypeChange()
    m.isLiveStream = (m.top.video_type = "LIVE")
    updateUIForVideoType()
end sub

sub updateUIForVideoType()
    if m.isLiveStream
        ' Hide seek-related controls for live streams
        m.rewindGroup.visible = false
        m.fastForwardGroup.visible = false
        m.timeTravelGroup.visible = false
        m.progressDot.visible = false

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
        m.progressDot.visible = true
    end if
end sub

sub onPositionChange()
    m.currentPositionSeconds = m.top.position
    if not m.isSeekMode
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
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/pause.png"
        m.loadingSpinner.visible = false
        hideMessage()
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/play.png"
        m.loadingSpinner.visible = false
    else if m.top.state = "buffering"
        m.loadingSpinner.visible = true
    else if m.top.state = "error"
        m.loadingSpinner.visible = false
        ? "[CustomVideo] Video error occurred"
        if m.top.errorStr <> invalid and (m.top.errorStr.InStr("970") > -1 or m.top.errorStr.InStr("buffer:loop:demux") > -1)
            showErrorMessage("Incompatible Video Format", "This video cannot be played on your device")
        else
            showErrorMessage("Stream Error", "Having trouble loading the stream. Retrying...")
        end if
    end if

    ' Show live indicator for live streams
    if m.isLiveStream
        m.liveIndicator.visible = true
    else
        m.liveIndicator.visible = false
    end if
end sub

sub onChatVisibilityChange()
    ' Adjust layout based on chat visibility
    if m.top.chatIsVisible
        m.progressBarBase.width = 900
        m.controlOverlay.translation = [0, 580]
    else
        m.progressBarBase.width = 1160
        m.controlOverlay.translation = [0, 580]
    end if

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
        ' For live streams, show minimal progress info
        m.timeProgress.text = "LIVE"
        m.timeDuration.text = "LIVE"
        m.progressBarProgress.width = m.progressBarBase.width ' Full bar for live
        m.progressDot.visible = false
    else if m.top.duration > 0 and m.currentPositionSeconds >= 0
        ' Update progress bar for VOD/clips
        progressRatio = m.currentPositionSeconds / m.top.duration
        m.progressBarProgress.width = m.progressBarBase.width * progressRatio

        ' Clamp the progress dot position within bounds
        dotX = m.progressBarBase.width * progressRatio - 8
        if dotX < 0 then dotX = 0
        if dotX > m.progressBarBase.width then dotX = m.progressBarBase.width

        m.progressDot.translation = [dotX, 59]
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

    ' Start fade timer
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    m.thumbnailPreview.visible = false
    clearAllButtonFocus()
end sub

sub onFadeAway()
    if not m.isTimeTravelDialogOpen
        hideOverlay()
    end if
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
        end if
    end if
end sub

sub clearAllButtonFocus()
    m.playPauseFocus.visible = false
    m.rewindFocus.visible = false
    m.fastForwardFocus.visible = false
    m.timeTravelFocus.visible = false
    m.chatFocus.visible = false
    m.backFocus.visible = false
end sub

sub executeButtonAction()
    if m.isLiveStream
        ' Live stream button actions
        if m.currentFocusedButton = 0 ' Back
            ? "[CustomVideo] Back button pressed - attempting to exit"
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
            ? "[CustomVideo] Back button pressed - attempting to exit"
            m.top.back = true
            if m.top.getParent() <> invalid
                m.top.getParent().back = true
            end if
            hideOverlay()
            m.top.control = "stop"
        else if m.currentFocusedButton = 1 ' Time Travel
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
        ' Apply seek for VOD/clips
        m.top.seek = m.currentPositionSeconds
        m.isSeekMode = false
        m.currentPositionUpdated = false
        ' Hide thumbnail preview after seeking
        m.thumbnailPreview.visible = false
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
        ? "[CustomVideo] Seeking disabled for live streams"
        return
    end if

    if not m.isSeekMode
        m.currentPositionSeconds = m.top.position
        m.isSeekMode = true
        m.top.control = "pause"
    end if

    m.currentPositionSeconds += seconds
    if m.currentPositionSeconds < 0
        m.currentPositionSeconds = 0
    else if m.currentPositionSeconds > m.top.duration
        m.currentPositionSeconds = m.top.duration
    end if

    updateProgressBar()
    showThumbnailPreview()
end sub

sub showThumbnailPreview()
    if m.isLiveStream
        return ' No thumbnails for live streams
    end if

    if m.top.thumbnailInfo <> invalid and m.top.thumbnailInfo.width <> invalid
        m.thumbnailPreview.visible = true
        m.thumbnailTime.text = convertToReadableTimeFormat(m.currentPositionSeconds)

        ' Guard against divide-by-zero and invalid thumbnail_parts
        if m.top.thumbnailInfo.thumbnail_parts <> invalid and m.top.thumbnailInfo.thumbnail_parts.Count() > 0
            ' Calculate thumbnail position
            thumbnailsPerPart = Int(m.top.thumbnailInfo.count / m.top.thumbnailInfo.thumbnail_parts.Count())

            ' Additional guard to ensure thumbnailsPerPart is valid
            if thumbnailsPerPart > 0
                thumbnailPosOverall = Int(m.currentPositionSeconds / m.top.thumbnailInfo.interval)
                thumbnailPosCurrent = thumbnailPosOverall mod thumbnailsPerPart
                thumbnailRow = Int(thumbnailPosCurrent / m.top.thumbnailInfo.cols)
                thumbnailCol = Int(thumbnailPosCurrent mod m.top.thumbnailInfo.cols)

                m.thumbnailImage.translation = [-thumbnailCol * m.top.thumbnailInfo.width, -thumbnailRow * m.top.thumbnailInfo.height]

                ' Check bounds before accessing thumbnail_parts array
                partIndex = Int(thumbnailPosOverall / thumbnailsPerPart)
                if m.top.thumbnailInfo.info_url <> invalid and partIndex < m.top.thumbnailInfo.thumbnail_parts.Count() and m.top.thumbnailInfo.thumbnail_parts[partIndex] <> invalid
                    m.thumbnailImage.uri = m.top.thumbnailInfo.info_url + m.top.thumbnailInfo.thumbnail_parts[partIndex]
                end if
            end if
        end if

        ' Position thumbnail preview near progress bar
        progressRatio = m.currentPositionSeconds / m.top.duration
        thumbnailX = 60 + (m.progressBarBase.width * progressRatio) - 100
        if thumbnailX < 60 then thumbnailX = 60
        if thumbnailX > 1020 then thumbnailX = 1020
        m.thumbnailPreview.translation = [thumbnailX, 400]
    end if
end sub

sub openTimeTravelDialog()
    if m.isLiveStream
        ? "[CustomVideo] Time travel disabled for live streams"
        return
    end if

    m.isTimeTravelDialogOpen = true
    m.timeTravelDialog.visible = true
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

sub onButtonHold()
    if m.isLiveStream
        return ' No seeking for live streams
    end if

    if m.buttonHeld = "left"
        seekRelative(-m.scrollInterval)
        m.scrollInterval += 5
    else if m.buttonHeld = "right"
        seekRelative(m.scrollInterval)
        m.scrollInterval += 5
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

function saveVideoBookmark() as void
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
            if m.bookmarkTask <> invalid
                m.bookmarkTask = invalid
            end if
            m.bookmarkTask = createObject("roSGNode", "TwitchApiTask")
            m.bookmarkTask.functionname = "updateUserViewedVideo"
            m.bookmarkTask.request = {
                "userId": get_user_setting("id")
                "position": bookmarkPosition
                "videoId": m.top.video_id
                "videoType": m.top.video_type
            }
            m.bookmarkTask.control = "run"
        end if
    end if
end function

sub showErrorMessage(title as string, message as string)
    showMessage(title, message, 0)
end sub

sub hideErrorMessage()
    hideMessage()
end sub

sub showMessage(title as string, message as string, duration as float)
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
    
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
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
        m.messageTimer = invalid
    end if
end sub

sub onMessageTimeout()
    hideMessage()
    m.messageTimer = invalid
end sub

function onKeyEvent(key, press) as boolean
    ? "[CustomVideo] KeyEvent: "; key; " "; press

    if press
        ' Reset fade timer on any key press
        if m.isOverlayVisible
            m.fadeAwayTimer.control = "stop"
            m.fadeAwayTimer.control = "start"
        end if

        if m.isTimeTravelDialogOpen
            return handleTimeTravelKeys(key)
        else
            return handleMainKeys(key)
        end if
    else
        ' Handle key release
        if key = "rewind" or key = "fastforward"
            m.buttonHeld = invalid
            m.buttonHoldTimer.control = "stop"
            m.scrollInterval = 10
            if m.isSeekMode
                m.thumbnailPreview.visible = false
            end if
        end if
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
                focusButton(5) ' Wrap to chat button
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
            if m.currentFocusedButton < 5
                focusButton(m.currentFocusedButton + 1)
            else
                focusButton(0) ' Wrap to back button
            end if
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
    else if key = "rewind"
        if not m.isLiveStream
            m.buttonHeld = "left"
            m.buttonHoldTimer.control = "start"
            seekRelative(-10)
        end if
        return true
    else if key = "fastforward"
        if not m.isLiveStream
            m.buttonHeld = "right"
            m.buttonHoldTimer.control = "start"
            seekRelative(10)
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