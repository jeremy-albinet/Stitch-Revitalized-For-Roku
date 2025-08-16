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
    m.lowLatencyIndicator = m.top.findNode("lowLatencyIndicator")
    if m.lowLatencyIndicator <> invalid
        m.lowLatencyIndicatorLabel = m.lowLatencyIndicator.findNode("lowLatencyIndicatorLabel")
    end if
    m.normalLatencyIndicator = m.top.findNode("normalLatencyIndicator")
    if m.normalLatencyIndicator <> invalid
        m.normalLatencyIndicatorLabel = m.normalLatencyIndicator.findNode("normalLatencyIndicatorLabel") ' Though not changed in this iteration, good practice to have the reference
    end if

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

    ' Observers
    m.top.observeField("position", "onPositionChange")
    m.top.observeField("state", "onVideoStateChange")
    m.top.observeField("chatIsVisible", "onChatVisibilityChange")
    m.top.observeField("duration", "onDurationChange")
    m.top.observeField("bufferingStatus", "onBufferingStatusChange")
    m.top.observeField("qualityOptions", "onQualityOptionsChange")
    m.top.observeField("selectedQuality", "onSelectedQualityChange")

    ' Initialize UI
    updateProgressBar()
    setupLiveUI()
    updateLatencyIndicator()

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

sub updateLatencyIndicator()
    latencySetting = get_user_setting("preferred.latency", "low")
    userPrefersLowLatency = (latencySetting = "low")
    isActuallyLowLatency = m.top.isActualLowLatency ' This field is set from VideoPlayer.brs

    ' Hide both indicators initially
    if m.lowLatencyIndicator <> invalid then m.lowLatencyIndicator.visible = false
    if m.normalLatencyIndicator <> invalid then m.normalLatencyIndicator.visible = false

    if m.isOverlayVisible
        if userPrefersLowLatency
            if m.lowLatencyIndicator <> invalid and m.lowLatencyIndicatorLabel <> invalid
                if isActuallyLowLatency
                    m.lowLatencyIndicatorLabel.text = "Stream Mode: Low Latency"
                else
                    m.lowLatencyIndicatorLabel.text = "Stream Mode: Low Latency (Unavailable)"
                end if
                m.lowLatencyIndicator.visible = true
            end if
        else ' User prefers normal latency
            if m.normalLatencyIndicator <> invalid and m.normalLatencyIndicatorLabel <> invalid
                m.normalLatencyIndicatorLabel.text = "Stream Mode: Normal" ' Ensure text is set
                m.normalLatencyIndicator.visible = true
            end if
        end if
    end if
end sub

sub onPositionChange()
    m.currentPositionSeconds = m.top.position
    ' Live streams don't need position-based updates
end sub

sub onVideoStateChange()
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/pause.png"
        hideLoadingOverlay()
        hideMessage()
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/play.png"
        hideLoadingOverlay()
    else if m.top.state = "buffering"
        showLoadingOverlay()
    else if m.top.state = "error"
        hideLoadingOverlay()
        if m.top.errorStr <> invalid and (m.top.errorStr.InStr("970") > -1 or m.top.errorStr.InStr("buffer:loop:demux") > -1)
            showErrorMessage("Incompatible Video Format", "This stream cannot be played on your device")
        else
            showErrorMessage("Stream Error", "Having trouble loading the live stream. Retrying...")
        end if
    end if
end sub

sub onChatVisibilityChange()
    ' Adjust layout based on chat visibility
    if m.top.chatIsVisible
        m.progressBarBase.width = 900
        ' Adjust latency indicator position when chat is visible (move further left)
        m.lowLatencyIndicator.translation = [750, 0]
        m.normalLatencyIndicator.translation = [750, 0]
    else
        m.progressBarBase.width = 1160
        ' Reset latency indicator position (bottom right of overlay)
        m.lowLatencyIndicator.translation = [0, 0]
        m.normalLatencyIndicator.translation = [0, 0]
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
    updateLatencyIndicator()
    ' ? "[StitchVideo] Quality changed to: "; m.top.selectedQuality
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

        ' Update latency indicator
        updateLatencyIndicator()
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
    m.liveIndicator.visible = true ' Show LIVE indicator with overlay
    updateLatencyIndicator() ' Update latency indicator visibility
    focusButton(m.currentFocusedButton)

    ' Start fade timer
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    m.liveIndicator.visible = false ' Hide LIVE indicator with overlay
    updateLatencyIndicator() ' Hide latency indicators
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
