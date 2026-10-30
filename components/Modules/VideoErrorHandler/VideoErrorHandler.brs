' VideoErrorHandler.brs - Handles error recovery and retry logic for video playback

sub init()
    m.maxRetries = 3
    m.retryDelay = 2000 ' 2 seconds initial delay
    m.maxRetryDelay = 30000 ' 30 seconds max delay
    m.currentRetryCount = 0
    m.lastErrorTime = 0
    m.errorHistory = []
    m.bufferStallCount = 0
    m.maxBufferStalls = 5
    m.bufferStallResetSeconds = 120 ' Policy: forget prolonged checks after two quiet minutes.
    m.lastBufferTime = 0

    ' Error recovery strategies
    m.recoveryStrategies = {
        "connection_error": "retry_with_backoff",
        "buffer_timeout": "quality_downgrade",
        "stream_unavailable": "retry_different_quality",
        "stream_not_found": "fail_immediately",
        "authentication_error": "refresh_token",
        "excessive_buffering": "switch_to_lower_quality",
        "stream_format_error": "retry_different_quality",
        "media_decode_error": "quality_downgrade",
        "server_error": "retry_with_backoff",
        "codec_incompatible": "fail_immediately"
    }
end sub

function handleVideoError(errorCode as integer, errorMessage as string, video as object, contentRequested as object) as object
    ' Log error to history
    m.errorHistory.push({
        code: errorCode,
        message: errorMessage,
        timestamp: CreateObject("roDateTime").AsSeconds()
    })

    ' Determine error type and recovery strategy
    errorType = classifyError(errorCode, errorMessage)
    strategy = m.recoveryStrategies[errorType]

    ' ? "[VideoErrorHandler] Error detected - Code: "; errorCode; ", Type: "; errorType; ", Strategy: "; strategy

    recovery = {
        shouldRetry: false,
        action: "none",
        delay: 0,
        newContent: invalid
    }
    if m.currentRetryCount >= m.maxRetries
        recovery.action = "fail"
        return recovery
    end if
    m.currentRetryCount++

    if strategy = "retry_with_backoff"
        if m.currentRetryCount < m.maxRetries
            recovery.shouldRetry = true
            recovery.action = "retry"
            recovery.delay = calculateBackoffDelay()
            ' ? "[VideoErrorHandler] Retrying playback (attempt "; m.currentRetryCount; " of "; m.maxRetries; ")"
        else
            recovery.action = "fail"
            ' ? "[VideoErrorHandler] Max retries reached, playback failed"
        end if

    else if strategy = "quality_downgrade"
        newQuality = getNextLowerQuality(video)
        if newQuality <> invalid
            recovery.shouldRetry = true
            recovery.action = "change_quality"
            recovery.newContent = newQuality
            recovery.delay = 1000
            ' ? "[VideoErrorHandler] Switching to lower quality: "; newQuality.qualityID
        else
            recovery.shouldRetry = true
            recovery.action = "retry"
            recovery.delay = 2000
        end if

    else if strategy = "retry_different_quality"
        alternativeQuality = getAlternativeQuality(video, contentRequested)
        if alternativeQuality <> invalid
            recovery.shouldRetry = true
            recovery.action = "change_quality"
            recovery.newContent = alternativeQuality
            recovery.delay = 1500
            ' ? "[VideoErrorHandler] Trying alternative quality: "; alternativeQuality.qualityID
        end if

    else if strategy = "refresh_token"
        ' Trigger token refresh
        recovery.shouldRetry = true
        recovery.action = "refresh_auth"
        recovery.delay = 500
        ' ? "[VideoErrorHandler] Requesting authentication refresh"

    else if strategy = "switch_to_lower_quality"
        ' Force switch to lower quality for buffer issues
        recovery.shouldRetry = true
        recovery.action = "force_lower_quality"
        recovery.delay = 2000
    end if

    return recovery
end function

function handleBufferStall(video as object) as object
    currentTime = CreateObject("roDateTime").AsSeconds()

    ' Check if this is a new buffer stall
    if currentTime - m.lastBufferTime > m.bufferStallResetSeconds
        m.bufferStallCount = 0
    end if

    m.bufferStallCount = m.bufferStallCount + 1
    m.lastBufferTime = currentTime

    recovery = {
        shouldRecover: false,
        action: "wait",
        delay: 0
    }

    ' Let Roku's player recover for the first five recent prolonged checks.
    ' The sixth requests a lower quality; VideoPlayer caps session recoveries.
    if m.bufferStallCount > m.maxBufferStalls
        ' ? "[VideoErrorHandler] Excessive buffering detected ("; m.bufferStallCount; " stalls)"
        recovery.shouldRecover = true
        recovery.action = "reduce_quality"
        recovery.delay = 1000
        m.bufferStallCount = 0
    end if

    return recovery
end function

function classifyError(errorCode as integer, errorMessage as string) as string
    if errorMessage.InStr("970") > -1 or errorMessage.InStr("buffer:loop:demux") > -1
        return "codec_incompatible"
    else if errorCode = 9
        if errorMessage.InStr("all bitrates") > -1
            return "stream_format_error"
        else
            return "media_decode_error"
        end if
    else if errorCode >= -5 and errorCode <= -1
        if errorCode = -5 and (errorMessage.InStr("demux") > -1 or errorMessage.InStr("970") > -1)
            return "codec_incompatible"
        else
            return "connection_error"
        end if
    else if errorCode >= 400 and errorCode <= 499
        if errorCode = 401 or errorCode = 403
            return "authentication_error"
        else if errorCode = 404
            return "stream_not_found"
        else
            return "stream_unavailable"
        end if
    else if errorCode >= 500 and errorCode <= 599
        return "server_error"
    else if errorMessage.InStr("buffer") > -1 or errorMessage.InStr("timeout") > -1
        return "buffer_timeout"
    else if errorMessage.InStr("excessive") > -1 or errorMessage.InStr("stall") > -1
        return "excessive_buffering"
    else
        return "connection_error"
    end if
end function

function calculateBackoffDelay() as integer
    ' Exponential backoff with jitter
    baseDelay = m.retryDelay * (2 ^ (m.currentRetryCount - 1))
    jitter = Rnd(500) ' Add random jitter up to 500ms
    delay = baseDelay + jitter

    if delay > m.maxRetryDelay
        delay = m.maxRetryDelay
    end if

    return delay
end function

function getNextLowerQuality(video as object) as object
    if video = invalid then return invalid
    options = video.qualityOptions
    if options = invalid or options.count() = 0
        return invalid
    end if

    currentQuality = video.selectedQuality
    if currentQuality = invalid
        return invalid
    end if

    if currentQuality = "Automatic"
        descriptor = invalid
        if video.content <> invalid then descriptor = video.content.GetField("localPlaybackDescriptor")
        if type(descriptor) = "roAssociativeArray"
            currentQuality = descriptor["qualityId"]
            if GetInterface(currentQuality, "ifString") = invalid then return invalid
            if currentQuality = "Automatic" then return invalid
        else
            ' Automatic may already be using a low adaptive rung.
            if options.count() <= 2 then return invalid
            lowestIndex = options.count() - 1
            return { qualityID: options[lowestIndex], index: lowestIndex, isLowerQuality: true }
        end if
    end if

    ' Find current quality index
    currentIndex = -1
    for i = 0 to options.count() - 1
        if options[i] = currentQuality
            currentIndex = i
            exit for
        end if
    end for

    ' Concrete options are ordered from highest to lowest bitrate.
    if currentIndex >= 0 and currentIndex < options.count() - 1
        return {
            qualityID: options[currentIndex + 1],
            index: currentIndex + 1,
            isLowerQuality: true
        }
    end if

    return invalid
end function

function getAlternativeQuality(video as object, contentRequested as object) as object
    if video.qualityOptions = invalid or video.qualityOptions.count() = 0
        return invalid
    end if

    ' Try to find a mid-range quality as alternative
    qualityCount = video.qualityOptions.count()
    if qualityCount > 2
        midIndex = Int(qualityCount / 2)
        return {
            qualityID: video.qualityOptions[midIndex],
            index: midIndex,
            isAlternative: true
        }
    end if

    return invalid
end function

sub resetErrorState()
    m.currentRetryCount = 0
    m.bufferStallCount = 0
    m.errorHistory = []
    ' ? "[VideoErrorHandler] Error state reset"
end sub

function shouldGiveUp() as boolean
    ' Check if we should stop trying based on error history
    if m.errorHistory.count() > 10
        ' Too many errors in this session
        return true
    end if

    ' Check for repeated errors in short time
    currentTime = CreateObject("roDateTime").AsSeconds()
    recentErrors = 0
    for each error in m.errorHistory
        if currentTime - error.timestamp < 60 ' Within last minute
            recentErrors = recentErrors + 1
        end if
    end for

    if recentErrors > 5
        return true
    end if

    return false
end function

function getErrorStatistics() as object
    stats = {
        totalErrors: m.errorHistory.count(),
        retryCount: m.currentRetryCount,
        bufferStalls: m.bufferStallCount,
        errorTypes: {}
    }

    for each error in m.errorHistory
        errorType = classifyError(error.code, error.message)
        if stats.errorTypes[errorType] = invalid
            stats.errorTypes[errorType] = 0
        end if
        stats.errorTypes[errorType] = stats.errorTypes[errorType] + 1
    end for

    return stats
end function

' Copy for the playback error dialog. Classification is unchanged; the dialog
' offers Try again and Back. A 401/403 only says Twitch refused this video:
' public streams play without an account, so it never claims sign-in is needed.
function getUserFriendlyErrorMessage(errorCode as integer, errorType as string) as object
    messages = {
        "connection_error": {
            title: tr("Can't connect to the stream"),
            message: tr("Stitch lost its connection to Twitch while loading this video."),
            suggestion: tr("Check your internet connection, then try again.")
        },
        "buffer_timeout": {
            title: tr("The stream is loading slowly"),
            message: tr("The video took too long to load. The network may be busy."),
            suggestion: tr("Try again, or choose a lower video quality.")
        },
        "stream_unavailable": {
            title: tr("Stream unavailable"),
            message: tr("This stream isn't available right now. The broadcaster may have ended it."),
            suggestion: tr("Try again in a moment, or check back later.")
        },
        "stream_not_found": {
            title: tr("Couldn't find this stream"),
            message: tr("It may have been deleted or moved."),
            suggestion: tr("Go back and choose another stream.")
        },
        "authentication_error": {
            title: tr("Twitch didn't authorize this video"),
            message: tr("It may need a Twitch account or have other restrictions, such as subscriber-only access."),
            suggestion: tr("Public streams play without signing in. Try again, or choose another video.")
        },
        "excessive_buffering": {
            title: tr("Playback keeps stopping"),
            message: tr("The stream is being interrupted often."),
            suggestion: tr("Try a lower video quality, or check your connection speed.")
        },
        "stream_format_error": {
            title: tr("Can't play this stream format"),
            message: tr("The stream may use an encoding this Roku can't play."),
            suggestion: tr("Try again, or choose a different video quality.")
        },
        "media_decode_error": {
            title: tr("Couldn't play this video"),
            message: tr("There was a problem decoding the video stream."),
            suggestion: tr("Try again, or choose a different video quality.")
        },
        "server_error": {
            title: tr("Twitch is having problems"),
            message: tr("Twitch's video service returned an error."),
            suggestion: tr("Wait a moment, then try again.")
        },
        "codec_incompatible": {
            title: tr("Video format not supported"),
            message: tr("This Roku can't play this video's codec or resolution."),
            suggestion: tr("Try a lower video quality, 720p or below.")
        }
    }

    ' Default message if error type not found
    if messages[errorType] = invalid
        return {
            title: tr("Couldn't play this video"),
            message: tr("Error code: {0}").replace("{0}", errorCode.toStr()),
            suggestion: tr("Try again later.")
        }
    end if

    return messages[errorType]
end function
