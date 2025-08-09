sub handleContent()
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = m.top.contentRequested.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end sub

function handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    ' m.top.playContent = true
    ' m.top.contentSelected = selectedItem
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = selectedItem.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end function

function onResponse()
    ' content.ignoreStreamErrors = true
    m.top.content = m.PlayVideo.response
    m.top.metadata = m.PlayVideo.metadata
    playContent()
end function

sub taskStateChanged(event as object)
    ' print "Player: taskStateChanged(), id = "; event.getNode(); ", "; event.getField(); " = "; event.getData()
    state = event.GetData()
    if state = "done" or state = "stop"
        exitPlayer()
    end if
end sub

sub controlChanged()
    'handle orders by the parent/owner
    control = m.top.control
    if control = "play" then
        playContent()
    else if control = "stop" then
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

function onQualityChangeRequested()
    ' ? "[Video Wrapper] - Quality Change Requested: "; m.video.qualityChangeRequest
    new_content = CreateObject("roSGNode", "TwitchContentNode")
    new_content.setFields(m.top.contentRequested.getFields()) ' Preserve original request fields
    new_content.setFields(m.top.metadata[m.video.qualityChangeRequest]) ' Apply new quality fields
    m.top.content = new_content ' Update the main content node for VideoPlayer
    m.allowBreak = false
    exitPlayer() ' This will clean up the old video
    playContent() ' This will play the new m.top.content
    m.allowBreak = true
end function

sub configureVideoForLatency(video as object, isLive as boolean)
    latencyPreference = get_user_setting("preferred.latency", "low")
    isLowLatency = (latencyPreference = "low")

    ' ? "[VideoPlayer] ===== BUFFERING CONFIGURATION ====="
    ' ? "[VideoPlayer] Latency preference: "; latencyPreference
    ' ? "[VideoPlayer] Is low latency: "; isLowLatency
    ' ? "[VideoPlayer] Is live content: "; isLive
    ' ? "[VideoPlayer] Video component type: "; video.subtype()

    if video.isSubtype("StitchVideo")
        ' ? "[VideoPlayer] StitchVideo handles its own low-latency configuration"
        ' ? "[VideoPlayer] ========================================="
        return
    end if

    ' Original configuration for regular Video components only
    if isLive and isLowLatency
        ' Enable LL-HLS for regular Video components
        try
            video.enableLowLatencyHLS = true
            video.hlsOptimization = "lowLatency"
            video.enablePartialSegments = true
            video.enablePreloadHints = true
            video.enableBlockingPlaylistReload = true
            ' ? "[VideoPlayer] ✓ Regular Video LL-HLS settings applied"
        catch e
            ' ? "[VideoPlayer] ⚠️ LL-HLS not fully supported on this device"
        end try

        video.bufferingConfig = {
            initialBufferingMs: 200,
            minBufferMs: 500,
            maxBufferMs: 1500,
            bufferForPlaybackMs: 200,
            bufferForPlaybackAfterRebufferMs: 500,
            rebufferMs: 200
        }

        video.enableDecoderCompatibility = false
        video.maxVideoDecodeResolution = "1440p"

        video.adaptiveBitrateConfig = {
            initialBandwidthBps: 5000000,
            maxInitialBitrate: 8000000,
            minDurationForQualityIncreaseMs: 60000,
            maxDurationForQualityDecreaseMs: 2000,
            minDurationToRetainAfterDiscardMs: 1000,
            bandwidthMeterSlidingWindowMs: 3000
        }

        ' ? "[VideoPlayer] ✓ Regular Video configured for LL-HLS"
    else if isLive
        ' Normal latency configuration for live streams
        video.bufferingConfig = {
            initialBufferingMs: 2000,
            minBufferMs: 5000,
            maxBufferMs: 15000,
            bufferForPlaybackMs: 2000,
            bufferForPlaybackAfterRebufferMs: 5000,
            rebufferMs: 2000
        }

        video.enableDecoderCompatibility = true

        video.adaptiveBitrateConfig = {
            initialBandwidthBps: 3000000,
            maxInitialBitrate: 6000000,
            minDurationForQualityIncreaseMs: 10000,
            maxDurationForQualityDecreaseMs: 25000,
            minDurationToRetainAfterDiscardMs: 5000,
            bandwidthMeterSlidingWindowMs: 10000
        }

        ' ? "[VideoPlayer] Regular Video configured for NORMAL LATENCY mode"
    else
        ' VOD configuration
        video.bufferingConfig = {
            initialBufferingMs: 3000,
            minBufferMs: 10000,
            maxBufferMs: 30000,
            bufferForPlaybackMs: 3000,
            bufferForPlaybackAfterRebufferMs: 8000,
            rebufferMs: 3000
        }

        video.enableDecoderCompatibility = true
        ' ? "[VideoPlayer] Regular Video configured for VOD playback"
    end if
    ' ? "[VideoPlayer] ========================================="
end sub

sub measureStreamDelay()
    if m.video <> invalid and m.video.content <> invalid
        currentTime = CreateObject("roDateTime").AsSeconds()
        videoPosition = m.video.position

        ' Initialize tracking on first call
        if m.delayTrackingStartTime = invalid
            m.delayTrackingStartTime = currentTime
            m.delayTrackingStartPosition = videoPosition
            m.lastRealTime = currentTime
            m.lastVideoPosition = videoPosition
            ' ? "[VideoPlayer] ===== INITIAL DELAY MEASUREMENT ====="
            ' ? "[VideoPlayer] Starting delay tracking..."
            ' ? "[VideoPlayer] Initial position: "; videoPosition; " seconds"
            ' ? "[VideoPlayer] ==========================================="
            return
        end if

        ' Calculate time since we started tracking
        realTimeElapsed = currentTime - m.lastRealTime
        videoTimeElapsed = videoPosition - m.lastVideoPosition

        ' For live streams, video should progress at same rate as real time
        ' Any difference indicates buffering/delay from live edge
        if realTimeElapsed > 0
            progressionRate = videoTimeElapsed / realTimeElapsed

            ' Estimate delay based on how video progression compares to real time
            if m.estimatedLiveDelay = invalid then m.estimatedLiveDelay = 25 ' Start with reasonable estimate

            ' If video is progressing slower than real time, we're falling behind
            if progressionRate < 0.99 ' Allow small variance
                ' We're falling behind the live stream
                delayIncrease = realTimeElapsed * (1 - progressionRate)
                m.estimatedLiveDelay = m.estimatedLiveDelay + delayIncrease
            else if progressionRate > 1.01
                ' We're catching up (unlikely but possible during buffering recovery)
                delayCatchup = realTimeElapsed * (progressionRate - 1)
                m.estimatedLiveDelay = m.estimatedLiveDelay - delayCatchup
            end if

            ' Keep delay within reasonable bounds for live streams
            if m.estimatedLiveDelay < 5 then m.estimatedLiveDelay = 5
            if m.estimatedLiveDelay > 120 then m.estimatedLiveDelay = 120

            ' ? "[VideoPlayer] ===== STREAM DELAY MEASUREMENT ====="
            ' ? "[VideoPlayer] Real time elapsed: "; realTimeElapsed; " seconds"
            ' ? "[VideoPlayer] Video time elapsed: "; videoTimeElapsed; " seconds"
            ' ? "[VideoPlayer] Progression rate: "; Int(progressionRate * 100); "%"
            ' ? "[VideoPlayer] ESTIMATED LIVE DELAY: "; Int(m.estimatedLiveDelay); " seconds"

            ' Convert to minutes:seconds for readability
            delayMinutes = Int(m.estimatedLiveDelay / 60)
            delaySeconds = Int(m.estimatedLiveDelay mod 60)
            ' ? "[VideoPlayer] Delay: "; delayMinutes; ":"; FormatSeconds(delaySeconds)

            ' Additional context
            ' if progressionRate < 0.95
            '     ? "[VideoPlayer] ⚠️  Falling behind live stream"
            ' else if progressionRate > 1.05
            '     ? "[VideoPlayer] ✓ Catching up to live stream"
            ' else
            '     ? "[VideoPlayer] ✓ Keeping pace with live stream"
            ' end if

            ' if m.video.bufferingStatus <> invalid
            '     ? "[VideoPlayer] Buffering status: "; m.video.bufferingStatus
            ' end if

            ' ? "[VideoPlayer] ==========================================="
        end if

        ' Update tracking values
        m.lastRealTime = currentTime
        m.lastVideoPosition = videoPosition
    end if
end sub

function FormatSeconds(seconds as integer) as string
    if seconds < 10
        return "0" + seconds.toStr()
    else
        return seconds.toStr()
    end if
end function

sub playContent()
    ' Clean up existing video node and its observers
    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        m.video.unobserveField("QualityChangeRequestFlag") ' StitchVideo specific
        m.video.unobserveField("qualityChangeRequest") ' StitchVideo specific
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("errorCode")
        m.video.unobserveField("duration")
        m.video.unobserveField("back") ' CustomVideo specific

        m.top.removeChild(m.video)
        m.video = invalid
    end if

    isLiveContent = (m.top.contentRequested.contentType = "LIVE")
    isClipContent = (m.top.contentRequested.contentType = "CLIP")

    ' ? "[VideoPlayer] ===== PLAYBACK INITIALIZATION ====="
    ' ? "[VideoPlayer] Content type: "; m.top.contentRequested.contentType
    ' ? "[VideoPlayer] Is live: "; isLiveContent
    ' ? "[VideoPlayer] Is clip: "; isClipContent

    if isLiveContent
        quality_options = []
        if m.top.metadata <> invalid
            for each quality_option in m.top.metadata
                quality_options.push(quality_option.qualityID)
            end for
        end if
        m.video = m.top.CreateChild("StitchVideo")
        m.video.qualityOptions = quality_options
        ' ? "[VideoPlayer] Created StitchVideo component for live stream"
        ' StitchVideo will observe its own selectedQuality field
    else
        m.video = m.top.CreateChild("CustomVideo")
        ' ? "[VideoPlayer] Created CustomVideo component for VOD/clip"
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
        httpAgent.addheader("X-Device-Id", CreateObject("roDeviceInfo").GetRandomUUID())
        authToken = get_user_setting("auth_token", "")
        if authToken <> ""
            httpAgent.addheader("Authorization", "Bearer " + authToken)
        end if
        ' ? "[VideoPlayer] Configured HTTP agent for clip with enhanced headers"
    else ' Live/VOD
        httpAgent.addheader("Accept", "*/*")
        httpAgent.addheader("Origin", "https://android.tv.twitch.tv")
        httpAgent.addheader("Referer", "https://android.tv.twitch.tv/")
        httpAgent.addheader("User-Agent", "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36")
        httpAgent.addheader("Client-ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")
        latencyPreference = get_user_setting("preferred.latency", "low")
        if isLiveContent and latencyPreference = "low"
            httpAgent.addheader("Cache-Control", "no-cache")
            httpAgent.addheader("Connection", "keep-alive")
            httpAgent.addheader("X-Low-Latency", "1")
            ' ? "[VideoPlayer] Added low-latency headers to HTTP agent"
        end if
    end if
    m.video.setHttpAgent(httpAgent)

    ' Configure video player properties (buffering, ABR config, etc.)
    configureVideoForLatency(m.video, isLiveContent)

    m.video.notificationInterval = 1

    ' Add observers to the new video node
    m.video.observeField("toggleChat", "onToggleChat")
    if isLiveContent
        m.video.observeField("QualityChangeRequestFlag", "onQualityChangeRequested") ' StitchVideo specific
    else
        m.video.observeField("back", "onVideoBack") ' CustomVideo specific
    end if
    m.video.observeField("position", "onPositionChanged")
    m.video.observeField("state", "onVideoStateChange")
    m.video.observeField("errorCode", "onVideoError")
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
    if contentNodeToPlay <> invalid then
        ' ? "[VideoPlayer] Preparing to play content. QualityID: "; contentNodeToPlay.QualityID
        ' ? "[VideoPlayer] Latency Preference: "; get_user_setting("preferred.latency", "low")

        if isLiveContent
            contentNodeToPlay.ignoreStreamErrors = false ' Important for HLS error reporting

            latencyPreference = get_user_setting("preferred.latency", "low")
            isLowLatencyMode = (latencyPreference = "low")

            currentQualityID = contentNodeToPlay.QualityID
            isAutomaticQuality = (currentQualityID.Instr("Automatic") > -1)

            if isLowLatencyMode and not isAutomaticQuality and currentQualityID <> ""
                contentNodeToPlay.switchingStrategy = "no-adaptation"
                ' ? "[VideoPlayer] Low latency with specific quality ('";currentQualityID;"'): ABR disabled (no-adaptation)."
            else
                contentNodeToPlay.switchingStrategy = "full-adaptation"
                ' if isLowLatencyMode and isAutomaticQuality
                '     ? "[VideoPlayer] Low latency with 'Automatic' quality ('";currentQualityID;"'): ABR enabled (full-adaptation, conservative config)."
                ' else if isLiveContent ' Normal latency live
                '     ? "[VideoPlayer] Normal latency live ('";currentQualityID;"'): ABR enabled (full-adaptation, standard config)."
                ' end if
            end if

            ' Log if we have low-latency streams available
            ' if contentNodeToPlay.lowLatencyStreamsAvailable <> invalid
            '     ? "[VideoPlayer] Low latency streams available: "; contentNodeToPlay.lowLatencyStreamsAvailable
            ' end if
        else if isClipContent
            contentNodeToPlay.ignoreStreamErrors = true
            contentNodeToPlay.switchingStrategy = "no-adaptation"
            contentNodeToPlay.streamFormat = "mp4"
            contentNodeToPlay.enableTrickPlay = false
            ' ? "[VideoPlayer] Configured content for clip playback ('";contentNodeToPlay.QualityID;"')"
        else ' VOD
            contentNodeToPlay.ignoreStreamErrors = true ' Or false, depending on desired strictness
            contentNodeToPlay.switchingStrategy = "full-adaptation" ' Typically ABR for VODs
            ' ? "[VideoPlayer] Configured content for VOD playback ('";contentNodeToPlay.QualityID;"')"
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
            ' ? "[VideoPlayer] VOD/Clip ID is valid: "; m.video.video_id
            if m.video.videoBookmarks.DoesExist(m.video.video_id)
                ' ? "[VideoPlayer] Jump To Position From Bookmarks > "; m.video.videoBookmarks[m.video.video_id]
                m.video.seek = Val(m.video.videoBookmarks[m.video.video_id])
            end if
        end if

        m.PlayerTask = CreateObject("roSGNode", "PlayerTask")
        m.PlayerTask.observeField("state", "taskStateChanged")
        m.PlayerTask.video = m.video
        m.PlayerTask.control = "RUN"

        if isLiveContent
            initChat()
            ' Start measuring delay after a short delay to let the stream start
            m.delayMeasureTimer = createObject("roSGNode", "Timer")
            m.delayMeasureTimer.observeField("fire", "measureStreamDelay")
            m.delayMeasureTimer.repeat = false
            m.delayMeasureTimer.duration = 10 ' Wait 10 seconds before first measurement
            m.delayMeasureTimer.control = "start"
        end if

        ' ? "[VideoPlayer] ==========================================="
    else
        ' ? "[VideoPlayer] Error: contentNodeToPlay is invalid. Cannot start playback."
    end if
end sub

sub exitPlayer()
    ' print "[VideoPlayer] exitPlayer()"

    if m.delayMeasureTimer <> invalid
        m.delayMeasureTimer.control = "stop"
        m.delayMeasureTimer = invalid
    end if

    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        if m.video.isSubtype("StitchVideo")
            m.video.unobserveField("QualityChangeRequestFlag")
        else if m.video.isSubtype("CustomVideo")
            m.video.unobserveField("back")
        end if
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("errorCode")
        m.video.unobserveField("duration")

        m.video.control = "stop"
        m.video.visible = false
    end if

    if m.PlayerTask <> invalid
        m.PlayerTask.unobserveField("state")
        m.PlayerTask.control = "stop" ' Ensure task is stopped
        m.PlayerTask = invalid
    end if

    ' ? "[VideoPlayer] Allow Break?: "; m.allowBreak
    if m.allowBreak
        m.top.state = "done"
        m.top.backpressed = true ' Ensure this signals back correctly
    end if
end sub

function onKeyEvent(key, press) as boolean
    if press
        ' ? "[VideoPlayer] Key Event: "; key
        if key = "back" then
            if m.chatWindow <> invalid and m.chatWindow.visible = true
                m.chatWindow.callFunc("stopJobs") ' Stop chat jobs if chat is open
            end if
            m.allowBreak = true ' Ensure exitPlayer signals upwards
            exitPlayer()
            ' m.top.backpressed = true ' This is set in exitPlayer if allowBreak is true
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

    ' Initialize delay tracking variables
    m.lastDelayMeasurement = invalid
    m.estimatedDelay = 0
    m.streamStartSystemTime = invalid
    ' New variables for proper live delay tracking
    m.delayTrackingStartTime = invalid
    m.delayTrackingStartPosition = invalid
    m.lastRealTime = invalid
    m.lastVideoPosition = invalid
    m.estimatedLiveDelay = invalid
    
    ' Initialize error handler
    m.errorHandler = CreateObject("roSGNode", "VideoErrorHandler")
    m.bufferCheckTimer = invalid
    m.lastBufferState = ""
    m.bufferStartTime = 0
end sub

sub onToggleChat()
    ' ? "[VideoPlayer] onToggleChat received from video component"
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
        ' ? "[VideoPlayer] Chat visibility changed. Chat visible: "; m.chatWindow.visible; ", Video width: "; m.video.width
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

    ' Measure delay every 30 seconds for debugging
    if m.video <> invalid and Int(m.video.position) mod 30 = 0
        measureStreamDelay()
    end if
end sub

sub onVideoStateChange()
    ' This is observed on m.video.
    ' StitchVideo/CustomVideo have their own onVideoStateChange for UI.
    ' ? "[VideoPlayer] Global onVideoStateChange: "; m.video.state
    
    ' Handle buffering states
    if m.video.state = "buffering"
        handleBufferingState()
    else if m.lastBufferState = "buffering" and m.video.state = "playing"
        ' Recovered from buffering
        m.errorHandler.callFunc("resetErrorState")
        if m.bufferCheckTimer <> invalid
            m.bufferCheckTimer.control = "stop"
            m.bufferCheckTimer = invalid
        end if
    end if
    
    m.lastBufferState = m.video.state
    
    if m.video.state = "finished" and m.allowBreak
        ' ? "[VideoPlayer] Video finished, exiting player."
        exitPlayer()
    else if m.video.state = "error"
        ' ? "[VideoPlayer] Video error state. Code: "; m.video.errorCode; ", Message: "; m.video.errorMessage
        handleStreamError()
    end if
end sub

sub onVideoError()
    ' ? "[VideoPlayer] Global onVideoError. Code: "; m.video.errorCode; ", Message: "; m.video.errorMessage
    handleStreamError()
end sub

sub handleStreamError()
    if m.errorHandler = invalid
        m.errorHandler = CreateObject("roSGNode", "VideoErrorHandler")
    end if
    
    errorCode = m.video.errorCode
    errorMessage = m.video.errorMessage
    if errorMessage = invalid then errorMessage = "Unknown error"
    
    recovery = m.errorHandler.callFunc("handleVideoError", errorCode, errorMessage, m.video, m.top.contentRequested)
    
    if recovery.shouldRetry
        ' ? "[VideoPlayer] Attempting error recovery: "; recovery.action
        
        if recovery.action = "retry"
            ' Retry with same content after delay
            retryTimer = CreateObject("roSGNode", "Timer")
            retryTimer.duration = recovery.delay / 1000
            retryTimer.repeat = false
            retryTimer.observeField("fire", "retryPlayback")
            retryTimer.control = "start"
            
        else if recovery.action = "change_quality" and recovery.newContent <> invalid
            ' Switch to different quality
            m.video.qualityChangeRequest = recovery.newContent.qualityID
            onQualityChangeRequested()
            
        else if recovery.action = "refresh_auth"
            ' Refresh authentication and retry
            refreshAuthAndRetry()
            
        else if recovery.action = "force_lower_quality"
            ' Force switch to lowest available quality
            if m.video.qualityOptions <> invalid and m.video.qualityOptions.count() > 0
                lowestQuality = m.video.qualityOptions[m.video.qualityOptions.count() - 1]
                m.video.qualityChangeRequest = lowestQuality
                onQualityChangeRequested()
            end if
        end if
    else
        if m.errorHandler.callFunc("shouldGiveUp")
            ' ? "[VideoPlayer] Too many errors, giving up"
            showErrorDialog("Playback Failed", "Unable to play this stream. Please try again later.")
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
            else if recovery.action = "adjust_buffer"
                ' Adjust buffering configuration
                adjustBufferConfig()
            end if
        end if
        
        m.bufferStartTime = 0 ' Reset timer
    end if
    
    ' Start a timer to check for stuck buffering
    if m.bufferCheckTimer = invalid
        m.bufferCheckTimer = CreateObject("roSGNode", "Timer")
        m.bufferCheckTimer.duration = 15 ' Check after 15 seconds
        m.bufferCheckTimer.repeat = false
        m.bufferCheckTimer.observeField("fire", "onBufferTimeout")
        m.bufferCheckTimer.control = "start"
    end if
end sub

sub onBufferTimeout()
    if m.video.state = "buffering"
        ' ? "[VideoPlayer] Buffer timeout - attempting recovery"
        handleStreamError()
    end if
    m.bufferCheckTimer = invalid
end sub

sub retryPlayback()
    ' ? "[VideoPlayer] Retrying playback..."
    exitPlayer()
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

sub adjustBufferConfig()
    ' Increase buffer sizes to handle network issues
    if m.video <> invalid
        m.video.bufferingConfig = {
            initialBufferingMs: 5000,
            minBufferMs: 10000,
            maxBufferMs: 30000,
            bufferForPlaybackMs: 5000,
            bufferForPlaybackAfterRebufferMs: 10000,
            rebufferMs: 5000
        }
        ' ? "[VideoPlayer] Adjusted buffer configuration for stability"
    end if
end sub

sub showErrorDialog(title as string, message as string)
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = title
    dialog.message = message
    dialog.buttons = ["OK"]
    dialog.observeField("buttonSelected", "onErrorDialogDismissed")
    m.top.dialog = dialog
end sub

sub onErrorDialogDismissed()
    m.top.dialog = invalid
    exitPlayer()
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