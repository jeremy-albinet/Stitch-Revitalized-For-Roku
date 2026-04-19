sub handleContent()
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = m.top.contentRequested.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end sub

sub handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = selectedItem.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end sub

sub onResponse()
    if m.PlayVideo.response <> invalid and m.PlayVideo.response.contentType = "ERROR"
        ' Display error message to user
        errorTitle = "Error while loading this video"
        errorMessage = "Unable to play this content"

        if m.PlayVideo.response.description <> invalid and m.PlayVideo.response.description <> ""
            errorMessage = m.PlayVideo.response.description
        end if

        if m.PlayVideo.response.errorCode <> invalid
            if m.PlayVideo.response.errorCode = "vod_manifest_restricted"
                errorMessage = "This video is only available to subscribers"
            else if m.PlayVideo.response.errorCode = "vod_manifest_expired"
                errorMessage = "This video has expired and is no longer available"
            else if m.PlayVideo.response.errorCode = "vod_manifest_missing"
                errorMessage = "This video has been deleted"
            end if
        end if

        trackEvent("video_load_error", {
            error_code: m.PlayVideo.response.errorCode,
            error_message: errorMessage,
            streamer_login: m.top.contentRequested?.streamerLogin,
            content_type: m.top.contentRequested?.contentType
        })
        showErrorDialog(errorTitle, errorMessage)
        return
    end if

    m.top.content = m.PlayVideo.response
    m.top.metadata = m.PlayVideo.metadata

    ' Warn before playing Enhanced Broadcasting (transmux) streams
    if m.top.content <> invalid and m.top.content.isTransmux = true
        if m.top.content.isProxied = true
            playContent()
        else
            showTransmuxWarning()
        end if
        return
    end if

    playContent()
end sub

sub taskStateChanged(event as object)
    state = event.GetData()
    if state = "done" or state = "stop"
        exitPlayer()
    end if
end sub

sub controlChanged()
    control = m.top.control
    if control = "play"
        playContent()
    else if control = "stop"
        exitPlayer()
    end if
end sub

sub initChat()
    if not m.top.chatStarted
        m.top.chatStarted = true
        m.chatWindow.channel_id = m.top.contentRequested.streamerId
        m.chatWindow.channel = m.top.contentRequested.streamerLogin
        if get_user_setting("ChatOption", "true") = "true"
            m.chatWindow.visible = true
            m.video.chatIsVisible = m.chatWindow.visible
        else
            m.chatWindow.visible = false
        end if
    end if
end sub

sub onQualityChangeRequested()
    new_content = CreateObject("roSGNode", "TwitchContentNode")
    new_content.setFields(m.top.contentRequested.getFields()) ' Preserve original request fields
    new_content.setFields(m.top.metadata[m.video.qualityChangeRequest]) ' Apply new quality fields
    m.top.content = new_content ' Update the main content node for VideoPlayer
    m.allowBreak = false
    exitPlayer() ' This will clean up the old video
    playContent() ' This will play the new m.top.content
    m.allowBreak = true
end sub

function FormatSeconds(seconds as integer) as string
    if seconds < 10
        return "0" + seconds.toStr()
    else
        return seconds.toStr()
    end if
end function

sub playContent()
    ' Reset reconnect/watchdog state on every (re)start so stale values
    ' from a prior playback session don't cause false triggers.
    m.isExiting = false
    m.lastGoodPosition = invalid
    m.stallSeconds = 0
    m.reconnectAttempts = 0

    ' Reset buffering state so stale timers from prior attempts don't persist
    m.bufferStartTime = 0
    m.lastBufferState = ""
    if m.bufferCheckTimer <> invalid
        m.bufferCheckTimer.control = "stop"
        m.bufferCheckTimer.unobserveField("fire")
        m.bufferCheckTimer = invalid
    end if

    ' Stamp when this playback attempt started (used for grace period)
    m.playbackInitTime = CreateObject("roTimeSpan")
    m.playbackInitTime.Mark()

    ' Only track stream_started and reset the timer on user-initiated plays.
    ' Internal reconnects (m.allowBreak = false) must not fire this event again.
    if m.allowBreak and m.top.contentRequested <> invalid
        trackEvent("stream_started", {
            content_type: m.top.contentRequested.contentType,
            streamer_login: m.top.contentRequested.streamerLogin,
            content_id: m.top.contentRequested.contentId
        })
        m.playbackStartTime = CreateObject("roTimeSpan")
        m.playbackStartTime.Mark()

        ' Record to recently watched history (LIVE and VOD; skip clips)
        contentType = m.top.contentRequested.contentType
        if contentType = "LIVE" or contentType = "VOD"
            streamerLogin = m.top.contentRequested.streamerLogin
            if streamerLogin <> invalid and streamerLogin <> ""
                rwTask = CreateObject("roSGNode", "RW_AddTask")
                rwTask.entry = {
                    login: streamerLogin,
                    displayName: m.top.contentRequested.streamerDisplayName,
                    iconUrl: m.top.contentRequested.streamerProfileImageUrl
                }
                rwTask.control = "run"
            end if
        end if
    end if

    ' Clean up existing video node and its observers
    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        m.video.unobserveField("QualityChangeRequestFlag") ' StitchVideo specific
        m.video.unobserveField("qualityChangeRequest") ' StitchVideo specific
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("duration")
        m.video.unobserveField("back") ' CustomVideo specific

        m.top.removeChild(m.video)
        m.video = invalid
    end if

    isLiveContent = (m.top.contentRequested.contentType = "LIVE")
    isClipContent = (m.top.contentRequested.contentType = "CLIP")

    if isLiveContent
        quality_options = []
        if m.top.metadata <> invalid
            for each quality_option in m.top.metadata
                quality_options.push(quality_option.qualityID)
            end for
        end if
        m.video = m.top.CreateChild("StitchVideo")
        m.video.qualityOptions = quality_options
        ' StitchVideo will observe its own selectedQuality field
    else
        m.video = m.top.CreateChild("CustomVideo")
    end if

    httpAgent = CreateObject("roHttpAgent")
    httpAgent.setCertificatesFile("common:/certs/ca-bundle.crt")
    httpAgent.InitClientCertificates()
    httpAgent.enableCookies()

    if isClipContent
        httpAgent.addheader("Accept", "video/mp4,video/webm,video/*,*/*")
        httpAgent.addheader("Accept-Encoding", "identity")
        httpAgent.addheader("Accept-Language", "en-US,en;q=0.9")
        httpAgent.addheader("Cache-Control", "no-cache")
        httpAgent.addheader("Connection", "keep-alive")
        httpAgent.addheader("DNT", "1")
        httpAgent.addheader("Origin", "https://www.twitch.tv")
        httpAgent.addheader("Pragma", "no-cache")
        httpAgent.addheader("Referer", "https://www.twitch.tv/")
        httpAgent.addheader("Sec-Ch-Ua", chr(34) + "Not_A Brand" + chr(34) + ";v=" + chr(34) + "8" + chr(34) + ", " + chr(34) + "Chromium" + chr(34) + ";v=" + chr(34) + "120" + chr(34) + ", " + chr(34) + "Google Chrome" + chr(34) + ";v=" + chr(34) + "120" + chr(34))
        httpAgent.addheader("Sec-Ch-Ua-Mobile", "?0")
        httpAgent.addheader("Sec-Ch-Ua-Platform", chr(34) + "Windows" + chr(34))
        httpAgent.addheader("Sec-Fetch-Dest", "video")
        httpAgent.addheader("Sec-Fetch-Mode", "cors")
        httpAgent.addheader("Sec-Fetch-Site", "cross-site")
        httpAgent.addheader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        httpAgent.addheader("Client-ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")
        authToken = get_user_setting("access_token", "")
        if authToken <> ""
            httpAgent.addheader("Authorization", "Bearer " + authToken)
        end if
    else ' Live/VOD
        httpAgent.addheader("Accept", "*/*")
        httpAgent.addheader("Origin", "https://android.tv.twitch.tv")
        httpAgent.addheader("Referer", "https://android.tv.twitch.tv/")
        httpAgent.addheader("User-Agent", "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36")
        httpAgent.addheader("Client-ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")
    end if
    m.video.setHttpAgent(httpAgent)

    m.video.notificationInterval = 0.5 ' fire position/bufferingStatus every 500ms

    ' Add observers to the new video node
    m.video.observeField("toggleChat", "onToggleChat")
    if isLiveContent
        m.video.observeField("QualityChangeRequestFlag", "onQualityChangeRequested") ' StitchVideo specific
    else
        m.video.observeField("back", "onVideoBack") ' CustomVideo specific
    end if
    m.video.observeField("position", "onPositionChanged")
    m.video.observeField("state", "onVideoStateChange")
    m.video.observeField("duration", "onDurationChanged")

    videoBookmarks = get_user_setting("VideoBookmarks", "")
    m.video.video_type = m.top.contentRequested.contentType
    m.video.video_id = m.top.contentRequested.contentId

    if videoBookmarks <> ""
        m.video.videoBookmarks = ParseJSON(videoBookmarks)
    else
        m.video.videoBookmarks = {}
    end if

    contentNodeToPlay = m.top.content ' This is the TwitchContentNode
    if contentNodeToPlay <> invalid
        if isLiveContent
            contentNodeToPlay.ignoreStreamErrors = false ' Important for HLS error reporting
            contentNodeToPlay.switchingStrategy = "full-adaptation"
            ' Seek to live edge. Roku clips this to the current availability window
            ' and starts at the latest segment rather than buffering the full window.
            ' Use max int32 — same as rokudev/transport-control official live sample.
            ' https://developer.roku.com/en-ca/docs/specs/media/streaming-specifications.md
            contentNodeToPlay.PlayStart = 2147483647
        else if isClipContent
            contentNodeToPlay.ignoreStreamErrors = true
            contentNodeToPlay.switchingStrategy = "no-adaptation"
            contentNodeToPlay.enableTrickPlay = false
        else ' VOD
            contentNodeToPlay.ignoreStreamErrors = true ' Or false, depending on desired strictness
            contentNodeToPlay.switchingStrategy = "full-adaptation" ' Typically ABR for VODs
        end if

        m.video.content = contentNodeToPlay

        if contentNodeToPlay.streamerProfileImageUrl <> invalid
            m.video.channelAvatar = contentNodeToPlay.streamerProfileImageUrl
        end if
        if contentNodeToPlay.streamerDisplayName <> invalid
            m.video.channelUsername = contentNodeToPlay.streamerDisplayName
        end if
        if contentNodeToPlay.contentTitle <> invalid
            m.video.videoTitle = contentNodeToPlay.contentTitle
        end if

        m.video.visible = false ' Make visible after PlayerTask starts if needed

        if m.video.video_id <> invalid and m.top.contentRequested.contentType <> "LIVE"
            if m.video.videoBookmarks.DoesExist(m.video.video_id)
                m.video.seek = Val(m.video.videoBookmarks[m.video.video_id])
            end if
        end if

        m.PlayerTask = CreateObject("roSGNode", "PlayerTask")
        m.PlayerTask.observeField("state", "taskStateChanged")
        m.PlayerTask.video = m.video
        m.PlayerTask.control = "RUN"

        if isLiveContent
            initChat()
        end if
    end if
end sub

sub exitPlayer()
    ' If allowBreak is true, this is a real user/back exit. During internal
    ' reconnects we set allowBreak=false before calling exitPlayer().
    if m.allowBreak
        m.isExiting = true
    end if

    if m.allowBreak and m.top.contentRequested <> invalid
        exitProps = {
            content_type: m.top.contentRequested.contentType,
            streamer_login: m.top.contentRequested.streamerLogin,
            content_id: m.top.contentRequested.contentId,
            is_transmux: false,
            is_proxied: false,
            selected_bitrate_kbps: 0
        }
        if m.top.content <> invalid
            exitProps.is_transmux = m.top.content.isTransmux
            exitProps.is_proxied = m.top.content.isProxied
            if m.top.content.StreamBitrates <> invalid and m.top.content.StreamBitrates.Count() > 0
                exitProps.selected_bitrate_kbps = m.top.content.StreamBitrates[0]
            end if
        end if
        if m.playbackStartTime <> invalid
            exitProps.duration_seconds = Int(m.playbackStartTime.TotalMilliseconds() / 1000)
        end if
        trackEvent("stream_ended", exitProps)
    end if

    ' Stop watchdog/reconnect timers and clean up any in-flight reconnect task
    if m.watchdogTimer <> invalid
        m.watchdogTimer.control = "stop"
    end if
    if m.reconnectTimer <> invalid
        m.reconnectTimer.control = "stop"
        m.reconnectTimer = invalid
    end if
    if m.retryTimer <> invalid
        m.retryTimer.control = "stop"
        m.retryTimer.unobserveField("fire")
        m.retryTimer = invalid
    end if
    cleanupReconnectTask()

    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        if m.video.isSubtype("StitchVideo")
            m.video.unobserveField("QualityChangeRequestFlag")
        else if m.video.isSubtype("CustomVideo")
            m.video.unobserveField("back")
        end if
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("duration")

        m.video.control = "stop"
        m.video.visible = false
    end if

    m.PlayerTask = destroyTask(m.PlayerTask, "state")

    if m.allowBreak
        m.top.state = "done"
        m.top.backpressed = true ' Ensure this signals back correctly
    end if
end sub

function onKeyEvent(key, press) as boolean
    if press
        if key = "back"
            if m.chatWindow <> invalid and m.chatWindow.visible = true
                m.chatWindow.callFunc("stopJobs") ' Stop chat jobs if chat is open
            end if
            m.allowBreak = true ' Ensure exitPlayer signals upwards
            exitPlayer()
            return true
        end if
    end if
    return false ' Let child video component (StitchVideo/CustomVideo) handle other keys
end function

sub init()
    m.chatWindow = m.top.findNode("chat")
    if m.chatWindow <> invalid
        m.chatWindow.fontSize = get_user_setting("ChatFontSize")
        m.chatWindow.observeField("visible", "onChatVisibilityChange")
    end if
    m.allowBreak = true ' Default to allowing break unless in quality change

    ' Initialize error handler
    m.errorHandler = CreateObject("roSGNode", "VideoErrorHandler")
    m.bufferCheckTimer = invalid
    m.lastBufferState = ""
    m.bufferStartTime = 0

    ' ===== Robust LIVE stall watchdog / reconnect =====
    ' Detects the common Twitch post-ad freeze where state stays "playing"
    ' but position stops advancing. When detected, it re-fetches the Twitch
    ' playlist/auth (GetTwitchContent) and restarts playback with backoff.
    m.isExiting = false
    m.reconnectAttempts = 0
    m.maxReconnectAttempts = 6
    m.reconnectCooldownSec = 45
    m.lastReconnectSuccessSec = 0
    m.lastGoodPosition = invalid
    m.stallSeconds = 0
    m.reconnectTimer = invalid
    m.retryTimer = invalid
    m.playbackInitTime = invalid ' tracks when current playback attempt started

    m.watchdogTimer = CreateObject("roSGNode", "Timer")
    m.watchdogTimer.repeat = true
    m.watchdogTimer.duration = 2 ' seconds
    m.watchdogTimer.observeField("fire", "onWatchdogFire")
end sub

sub onToggleChat()
    if m.video.toggleChat = true ' Check the field on the video component
        if m.chatWindow <> invalid
            m.chatWindow.visible = not m.chatWindow.visible
            m.video.chatIsVisible = m.chatWindow.visible ' Update video component's knowledge
        end if
        m.video.toggleChat = false ' Reset the flag on the video component
    end if
end sub

sub onChatVisibilityChange()
    if m.chatWindow <> invalid and m.video <> invalid
        if m.chatWindow.visible
            ' Example: Chat takes up 320px, video takes remaining width
            m.chatWindow.translation = [1280 - 320, 0] ' Position chat on the right
            m.chatWindow.height = 720 ' Full height
            m.chatWindow.width = 320

            m.video.width = 1280 - 320 ' Video width adjusted
            m.video.height = 720 ' Video full height
            m.video.translation = [0, 0] ' Video on the left
            m.video.chatIsVisible = true
        else
            m.video.width = 1280 ' Video full width
            m.video.height = 720
            m.video.translation = [0, 0]
            m.video.chatIsVisible = false
        end if
    end if
end sub

' Placeholder for onPositionChanged, onVideoStateChange, onVideoError, onDurationChanged
' These are observed on m.video, but their handlers can be minimal here if
' StitchVideo/CustomVideo handle their own UI updates based on these.
' However, some global actions might be needed here.

sub onPositionChanged()
    ' This is observed on m.video.
    ' StitchVideo/CustomVideo have their own onPositionChange for UI.
    ' Can be used for global logic if needed, e.g. global bookmarking not tied to UI.

    ' LIVE watchdog: keep track of forward progress (post-ad freezes often stop position)
    if m.video <> invalid and m.top.contentRequested <> invalid and m.top.contentRequested.contentType = "LIVE"
        if m.lastGoodPosition = invalid
            m.lastGoodPosition = m.video.position
            m.stallSeconds = 0
        else if m.video.position > m.lastGoodPosition
            m.lastGoodPosition = m.video.position
            m.stallSeconds = 0
        end if
    end if

end sub

sub onVideoStateChange()
    if m.video = invalid then return

    ' Handle buffering states
    if m.video.state = "buffering"
        handleBufferingState()
    else if m.lastBufferState = "buffering" and m.video.state = "playing"
        ' Recovered from buffering — cancel all pending retry/buffer timers
        m.errorHandler.callFunc("resetErrorState")
        if m.bufferCheckTimer <> invalid
            m.bufferCheckTimer.control = "stop"
            m.bufferCheckTimer.unobserveField("fire")
            m.bufferCheckTimer = invalid
        end if
        if m.retryTimer <> invalid
            m.retryTimer.control = "stop"
            m.retryTimer.unobserveField("fire")
            m.retryTimer = invalid
        end if
    end if

    m.lastBufferState = m.video.state

    ' Start/stop LIVE watchdog based on video state (single decision point)
    if m.top.contentRequested <> invalid and m.top.contentRequested.contentType = "LIVE" and m.watchdogTimer <> invalid
        if m.video.state = "playing"
            if m.lastGoodPosition = invalid then m.lastGoodPosition = m.video.position
            m.stallSeconds = 0
            m.watchdogTimer.control = "start"
        else
            m.watchdogTimer.control = "stop"
        end if
    end if

    if m.video.state = "finished" and m.allowBreak
        exitPlayer()
    else if m.video.state = "error"
        ' Log the raw error immediately for debugging visibility
        ? "[VideoPlayer] video.state=error — code="; m.video.errorCode; " msg="; m.video.errorStr

        ' Grace period: within the first 5 seconds of a fresh playback attempt,
        ' Roku's engine often fires a transient error on the initial segment fetch
        ' (CDN 302, auth pre-check, etc.) and then self-recovers on the next segment.
        ' Skip our retry machinery for non-fatal errors during this window.
        elapsedMs = 999999
        if m.playbackInitTime <> invalid
            elapsedMs = m.playbackInitTime.TotalMilliseconds()
        end if

        errorCode = m.video.errorCode
        errorMsg = m.video.errorStr
        if errorMsg = invalid then errorMsg = ""

        ' Enhanced Broadcasting / codec error — Roku cannot decode this stream at all.
        ' Exit silently: no dialog, no retry loop.
        if errorMsg.InStr("buffer:loop:demux") > -1 or errorMsg.InStr("970") > -1
            m.allowBreak = true
            exitPlayer()
            return
        end if

        ' Classify as fatal immediately (don't wait): auth errors
        isFatalError = false
        if errorCode = 401 or errorCode = 403 or errorCode = 404
            isFatalError = true
        end if

        if isFatalError or elapsedMs > 5000
            handleStreamError()
        else
            ? "[VideoPlayer] Transient error within grace period ("; elapsedMs; "ms) — letting Roku self-recover"
        end if
    end if
end sub

sub handleStreamError()
    if m.errorHandler = invalid
        m.errorHandler = CreateObject("roSGNode", "VideoErrorHandler")
    end if

    errorCode = m.video.errorCode
    errorMessage = m.video.errorMessage
    if errorMessage = invalid then errorMessage = "Unknown error"

    ' Get error classification for user-friendly messages
    errorType = m.errorHandler.callFunc("classifyError", errorCode, errorMessage)

    trackEvent("video_error", {
        error_code: errorCode,
        error_message: errorMessage,
        error_type: errorType,
        streamer_login: m.top.contentRequested?.streamerLogin,
        content_type: m.top.contentRequested?.contentType
    })

    recovery = m.errorHandler.callFunc("handleVideoError", errorCode, errorMessage, m.video, m.top.contentRequested)

    if recovery.shouldRetry
        if recovery.action = "retry"
            ? "[VideoPlayer] Retry action with delay: "; recovery.delay; " errorCode="; errorCode; " errorMsg="; errorMessage
            showTemporaryMessage("Reconnecting...")

            ' Cancel any in-flight retry timer before creating a new one
            if m.retryTimer <> invalid
                m.retryTimer.control = "stop"
                m.retryTimer.unobserveField("fire")
                m.retryTimer = invalid
            end if
            m.retryTimer = CreateObject("roSGNode", "Timer")
            m.retryTimer.duration = recovery.delay / 1000
            m.retryTimer.repeat = false
            m.retryTimer.observeField("fire", "retryPlayback")
            m.retryTimer.control = "start"

        else if recovery.action = "change_quality" and recovery.newContent <> invalid
            ' Show quality change message
            showTemporaryMessage("Switching to lower quality...")

            ' Switch to different quality
            m.video.qualityChangeRequest = recovery.newContent.qualityID
            onQualityChangeRequested()

        else if recovery.action = "refresh_auth"
            ' Show auth message
            showTemporaryMessage("Refreshing authentication...")

            ' Refresh authentication and retry
            refreshAuthAndRetry()

        else if recovery.action = "force_lower_quality"
            ' Show quality message
            showTemporaryMessage("Adjusting quality for better playback...")

            ' Force switch to lowest available quality
            if m.video.qualityOptions <> invalid and m.video.qualityOptions.count() > 0
                lowestQuality = m.video.qualityOptions[m.video.qualityOptions.count() - 1]
                m.video.qualityChangeRequest = lowestQuality
                onQualityChangeRequested()
            end if
        else if recovery.action = "fail_immediately"
            ' Get user-friendly error message
            errorInfo = m.errorHandler.callFunc("getUserFriendlyErrorMessage", errorCode, errorType)
            showErrorDialog(errorInfo.title, errorInfo.message + Chr(10) + Chr(10) + "Suggestion: " + errorInfo.suggestion)
            exitPlayer()
        end if
    else
        if m.errorHandler.callFunc("shouldGiveUp")
            ' Get user-friendly error message for final failure
            errorInfo = m.errorHandler.callFunc("getUserFriendlyErrorMessage", errorCode, errorType)
            showErrorDialog(errorInfo.title, errorInfo.message)
            exitPlayer()
        end if
    end if
end sub

sub handleBufferingState()
    if m.bufferStartTime = 0
        m.bufferStartTime = CreateObject("roDateTime").AsSeconds()
    end if

    ' Check for excessive buffering
    currentTime = CreateObject("roDateTime").AsSeconds()
    bufferDuration = currentTime - m.bufferStartTime

    if bufferDuration > 10 ' More than 10 seconds of buffering
        recovery = m.errorHandler.callFunc("handleBufferStall", m.video)

        if recovery.shouldRecover
            if recovery.action = "reduce_quality"
                ' Switch to lower quality
                lowerQuality = findLowerQuality()
                if lowerQuality <> invalid
                    m.video.qualityChangeRequest = lowerQuality
                    onQualityChangeRequested()
                end if
            end if
        end if

        m.bufferStartTime = 0 ' Reset timer
    end if

    ' Start a timer to check for stuck buffering.
    ' 25s gives Twitch CDN enough time for initial segment delivery on busy streams.
    if m.bufferCheckTimer = invalid
        m.bufferCheckTimer = CreateObject("roSGNode", "Timer")
        m.bufferCheckTimer.duration = 25
        m.bufferCheckTimer.repeat = false
        m.bufferCheckTimer.observeField("fire", "onBufferTimeout")
        m.bufferCheckTimer.control = "start"
    end if
end sub

sub onBufferTimeout()
    m.bufferCheckTimer = invalid
    if m.video = invalid then return
    if m.video.state <> "buffering" then return
    ' LIVE streams stall 15-20s waiting for the CDN segment to be produced — normal.
    ' Let Roku self-recover; don't force an error retry.
    if m.top.contentRequested <> invalid and m.top.contentRequested.contentType = "LIVE" then return
    handleStreamError()
end sub

' ===== LIVE stall watchdog / reconnect =====
sub onWatchdogFire()
    if m.isExiting then return
    if m.video = invalid or m.top.contentRequested = invalid then return
    if m.top.contentRequested.contentType <> "LIVE" then return
    if m.video.state <> "playing" then return

    nowSec = CreateObject("roDateTime").AsSeconds()

    ' Cooldown after a successful reconnect to avoid immediate re-triggers while Twitch stabilizes
    if m.lastReconnectSuccessSec <> 0 and (nowSec - m.lastReconnectSuccessSec) < m.reconnectCooldownSec
        return
    end if

    ' If position advanced, reset stall tracking
    if m.lastGoodPosition = invalid
        m.lastGoodPosition = m.video.position
        m.stallSeconds = 0
        return
    end if

    if m.video.position > m.lastGoodPosition
        m.lastGoodPosition = m.video.position
        m.stallSeconds = 0
        return
    end if

    ' Position didn't advance since last tick
    m.stallSeconds = m.stallSeconds + 2

    ' Common post-ad freeze: state remains "playing" but position is stuck
    if m.stallSeconds >= 8
        ? "[VideoPlayer] LIVE stall detected (pos="; m.video.position; "). Reconnecting..."
        beginLiveReconnect("stall")
    end if
end sub

sub beginLiveReconnect(reason as string)
    if m.isExiting then return

    ' If a reconnect is already scheduled/in-flight, don't stack them
    if m.reconnectTimer <> invalid then return

    m.reconnectAttempts = m.reconnectAttempts + 1
    if m.reconnectAttempts > m.maxReconnectAttempts
        showErrorDialog("Stream frozen", "Twitch playback froze after an ad and could not be recovered.")
        m.allowBreak = true
        exitPlayer()
        return
    end if

    ' Exponential backoff: 1,2,4,8,16,16...
    delaySec = 1
    for i = 1 to m.reconnectAttempts - 1
        delaySec = delaySec * 2
    end for
    if delaySec > 16 then delaySec = 16

    ? "[VideoPlayer] beginLiveReconnect reason="; reason; " attempt="; m.reconnectAttempts; "/"; m.maxReconnectAttempts
    showTemporaryMessage("Reconnecting... (" + m.reconnectAttempts.toStr() + "/" + m.maxReconnectAttempts.toStr() + ")")

    if m.watchdogTimer <> invalid
        m.watchdogTimer.control = "stop"
    end if

    m.reconnectTimer = CreateObject("roSGNode", "Timer")
    m.reconnectTimer.duration = delaySec
    m.reconnectTimer.repeat = false
    m.reconnectTimer.observeField("fire", "doLiveReconnect")
    m.reconnectTimer.control = "start"
end sub

sub cleanupReconnectTask()
    m.reconnectTask = destroyTask(m.reconnectTask, "response")
end sub

sub doLiveReconnect()
    if m.isExiting then return

    if m.reconnectTimer <> invalid
        m.reconnectTimer.control = "stop"
        m.reconnectTimer = invalid
    end if

    ' Clean up any prior reconnect task before creating a new one
    cleanupReconnectTask()

    ' Re-fetch playlist/auth via GetTwitchContent
    m.reconnectTask = CreateObject("roSGNode", "GetTwitchContent")
    m.reconnectTask.observeField("response", "onLiveReconnectResponse")
    m.reconnectTask.contentRequested = m.top.contentRequested.getFields()
    m.reconnectTask.functionName = "main"
    m.reconnectTask.control = "run"
end sub

sub onLiveReconnectResponse()
    if m.isExiting
        cleanupReconnectTask()
        return
    end if

    if m.reconnectTask = invalid or m.reconnectTask.response = invalid
        cleanupReconnectTask()
        beginLiveReconnect("refresh_failed")
        return
    end if

    if m.reconnectTask.response.contentType = "ERROR"
        cleanupReconnectTask()
        beginLiveReconnect("refresh_failed")
        return
    end if

    ' Capture response before cleanup
    refreshedContent = m.reconnectTask.response
    refreshedMetadata = m.reconnectTask.metadata
    cleanupReconnectTask()

    ' Apply fresh content + metadata
    m.top.content = refreshedContent
    m.top.metadata = refreshedMetadata

    ' Reset stall tracking
    m.lastGoodPosition = invalid
    m.stallSeconds = 0

    ' Restart playback in-place without exiting the scene
    m.allowBreak = false
    exitPlayer()
    m.allowBreak = true
    playContent()

    ' Mark successful reconnect (cooldown prevents immediate re-triggers)
    m.lastReconnectSuccessSec = CreateObject("roDateTime").AsSeconds()

    ' Success -> reset attempt counter and restart watchdog
    m.reconnectAttempts = 0
    if m.watchdogTimer <> invalid
        m.watchdogTimer.control = "start"
    end if
end sub

sub retryPlayback()
    ? "[VideoPlayer] retryPlayback() — restarting playback"
    m.retryTimer = invalid
    m.allowBreak = false
    exitPlayer()
    m.allowBreak = true
    playContent()
end sub

sub refreshAuthAndRetry()
    ' TODO: Implement auth refresh logic
    ' For now, just retry
    retryPlayback()
end sub

function findLowerQuality() as dynamic
    if m.video.qualityOptions = invalid or m.video.qualityOptions.count() = 0
        return invalid
    end if

    currentQuality = m.video.selectedQuality
    if currentQuality = invalid
        currentQuality = m.video.qualityOptions[0]
    end if

    ' Find current index
    currentIndex = -1
    for i = 0 to m.video.qualityOptions.count() - 1
        if m.video.qualityOptions[i] = currentQuality
            currentIndex = i
            exit for
        end if
    end for

    ' Return next lower quality
    if currentIndex >= 0 and currentIndex < m.video.qualityOptions.count() - 1
        return m.video.qualityOptions[currentIndex + 1]
    end if

    return invalid
end function

sub showErrorDialog(title as string, message as string)
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = title
    dialog.message = message
    dialog.buttons = ["OK"]
    dialog.observeField("buttonSelected", "onErrorDialogDismissed")
    ' Use the scene's dialog property, not m.top.dialog
    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = dialog
    end if
    m.errorDialog = dialog
end sub

sub onErrorDialogDismissed()
    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = invalid
    end if
    m.errorDialog = invalid
    exitPlayer()
end sub

sub showTransmuxWarning()
    m.transmuxButtonIndex = -1
    dialog = createObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Stream Not Supported"
    dialog.message = ["This stream uses Twitch Enhanced Broadcasting, a new format that is not yet compatible with Roku.", "", "We're working with Twitch and Roku to fix this."]
    dialog.buttons = ["Go Back", "Try Anyway"]
    dialog.observeField("buttonSelected", "onTransmuxDialogButton")
    dialog.observeField("wasClosed", "onTransmuxDialogClosed")
    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = dialog
    end if
end sub

sub onTransmuxDialogButton()
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        m.transmuxButtonIndex = scene.dialog.buttonSelected
        scene.dialog.close = true
    end if
end sub

sub onTransmuxDialogClosed()
    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = invalid
    end if
    if m.transmuxButtonIndex = 1
        playContent()
    else
        exitPlayer()
    end if
end sub

sub onDurationChanged()
    ' This is observed on m.video.
    ' StitchVideo/CustomVideo have their own onDurationChange for UI.
    ' ? "[VideoPlayer] Global onDurationChanged: "; m.video.duration
end sub

sub onVideoBack()
    ' Called when CustomVideo's back field is true
    ' ? "[VideoPlayer] Back key propagated from CustomVideo"
    if m.chatWindow <> invalid and m.chatWindow.visible = true
        m.chatWindow.callFunc("stopJobs")
    end if
    m.allowBreak = true
    exitPlayer()
end sub

sub showTemporaryMessage(message as string)
    ' For now, we'll skip temporary messages since we can't call external functions on Video nodes
    ' The error handling still works with the showErrorDialog function
    ? "[VideoPlayer] Status: "; message
end sub

sub dismissTemporaryMessage()
    ' No-op for now
end sub
