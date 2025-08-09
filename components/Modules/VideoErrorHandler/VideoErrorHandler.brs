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
    m.bufferStallTimeout = 10000 ' 10 seconds
    m.lastBufferTime = 0
    
    ' Error recovery strategies
    m.recoveryStrategies = {
        "connection_error": "retry_with_backoff",
        "buffer_timeout": "quality_downgrade",
        "stream_unavailable": "retry_different_quality",
        "authentication_error": "refresh_token",
        "excessive_buffering": "switch_to_lower_quality"
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
    
    if strategy = "retry_with_backoff"
        if m.currentRetryCount < m.maxRetries
            m.currentRetryCount = m.currentRetryCount + 1
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
    if currentTime - m.lastBufferTime > m.bufferStallTimeout
        m.bufferStallCount = 0
    end if
    
    m.bufferStallCount = m.bufferStallCount + 1
    m.lastBufferTime = currentTime
    
    recovery = {
        shouldRecover: false,
        action: "wait",
        delay: 0
    }
    
    if m.bufferStallCount > m.maxBufferStalls
        ' ? "[VideoErrorHandler] Excessive buffering detected ("; m.bufferStallCount; " stalls)"
        recovery.shouldRecover = true
        recovery.action = "reduce_quality"
        recovery.delay = 1000
        m.bufferStallCount = 0
    else if m.bufferStallCount > 3
        ' Adjust buffering config
        recovery.shouldRecover = true
        recovery.action = "adjust_buffer"
        recovery.delay = 0
    end if
    
    return recovery
end function

function classifyError(errorCode as integer, errorMessage as string) as string
    ' Network errors
    if errorCode >= -5 and errorCode <= -1
        return "connection_error"
    ' HTTP errors
    else if errorCode >= 400 and errorCode <= 499
        if errorCode = 401 or errorCode = 403
            return "authentication_error"
        else
            return "stream_unavailable"
        end if
    else if errorCode >= 500 and errorCode <= 599
        return "connection_error"
    ' Buffering timeout
    else if errorMessage.InStr("buffer") > -1 or errorMessage.InStr("timeout") > -1
        return "buffer_timeout"
    ' Excessive buffering
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
    if video.qualityOptions = invalid or video.qualityOptions.count() = 0
        return invalid
    end if
    
    currentQuality = video.selectedQuality
    if currentQuality = invalid
        return invalid
    end if
    
    ' Find current quality index
    currentIndex = -1
    for i = 0 to video.qualityOptions.count() - 1
        if video.qualityOptions[i] = currentQuality
            currentIndex = i
            exit for
        end if
    end for
    
    ' Get next lower quality (higher index typically means lower quality)
    if currentIndex >= 0 and currentIndex < video.qualityOptions.count() - 1
        return {
            qualityID: video.qualityOptions[currentIndex + 1],
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