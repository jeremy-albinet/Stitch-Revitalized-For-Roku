' QualitySwitchHandler.brs - Handles quality switching with fallback mechanisms

sub init()
    m.switchAttempts = {}
    m.maxSwitchAttempts = 3
    m.switchTimeout = 10000 ' 10 seconds
    m.lastSwitchTime = 0
    m.switchHistory = []
    m.fallbackQuality = "360p30" ' Default fallback quality
end sub

function attemptQualitySwitch(video as object, targetQuality as string, metadata as object) as object
    result = {
        success: false,
        quality: targetQuality,
        fallbackUsed: false,
        error: ""
    }
    
    ' Initialize attempt counter for this quality
    if m.switchAttempts[targetQuality] = invalid
        m.switchAttempts[targetQuality] = 0
    end if
    
    m.switchAttempts[targetQuality] = m.switchAttempts[targetQuality] + 1
    
    ' ? "[QualitySwitch] Attempting to switch to: "; targetQuality; " (attempt "; m.switchAttempts[targetQuality]; ")"
    
    ' Check if we've exceeded max attempts for this quality
    if m.switchAttempts[targetQuality] > m.maxSwitchAttempts
        ' ? "[QualitySwitch] Max attempts reached for quality: "; targetQuality
        result = tryFallbackQuality(video, targetQuality, metadata)
        return result
    end if
    
    ' Record switch attempt
    m.switchHistory.push({
        targetQuality: targetQuality,
        timestamp: CreateObject("roDateTime").AsSeconds(),
        attempt: m.switchAttempts[targetQuality]
    })
    
    ' Try to switch to target quality
    switchResult = performQualitySwitch(video, targetQuality, metadata)
    
    if switchResult.success
        result.success = true
        result.quality = targetQuality
        ' Reset attempt counter on success
        m.switchAttempts[targetQuality] = 0
        m.lastSwitchTime = CreateObject("roDateTime").AsSeconds()
    else
        ' ? "[QualitySwitch] Switch failed: "; switchResult.error
        result.error = switchResult.error
        
        ' If immediate failure, try fallback
        if shouldUseFallback(switchResult.error)
            result = tryFallbackQuality(video, targetQuality, metadata)
        else
            ' Schedule retry
            scheduleRetry(video, targetQuality, metadata)
        end if
    end if
    
    return result
end function

function performQualitySwitch(video as object, targetQuality as string, metadata as object) as object
    switchResult = {
        success: false,
        error: ""
    }
    
    try
        ' Find the quality in metadata
        targetMetadata = invalid
        for each quality in metadata
            if quality.qualityID = targetQuality
                targetMetadata = quality
                exit for
            end if
        end for
        
        if targetMetadata = invalid
            switchResult.error = "Quality not found in metadata"
            return switchResult
        end if
        
        ' Create new content node with target quality
        new_content = CreateObject("roSGNode", "TwitchContentNode")
        if video.content <> invalid
            new_content.setFields(video.content.getFields())
        end if
        new_content.setFields(targetMetadata)
        
        ' Validate the new content
        if not validateContent(new_content)
            switchResult.error = "Invalid content for quality"
            return switchResult
        end if
        
        ' Apply the new content
        video.content = new_content
        
        ' Wait for switch to complete
        if waitForSwitchCompletion(video)
            switchResult.success = true
        else
            switchResult.error = "Switch timeout"
        end if
        
    catch e
        switchResult.error = "Exception during switch: " + e.message
    end try
    
    return switchResult
end function

function validateContent(content as object) as boolean
    ' Validate that content has required fields
    if content = invalid
        return false
    end if
    
    if content.url = invalid or content.url = ""
        return false
    end if
    
    if content.streamFormat = invalid
        return false
    end if
    
    ' Additional validation for live streams
    if content.live = true
        if content.streamUrls = invalid or content.streamUrls.count() = 0
            return false
        end if
    end if
    
    return true
end function

function waitForSwitchCompletion(video as object) as boolean
    startTime = CreateObject("roDateTime").AsSeconds() * 1000
    timeout = m.switchTimeout
    
    while (CreateObject("roDateTime").AsSeconds() * 1000 - startTime) < timeout
        if video.state = "playing" or video.state = "paused"
            return true
        else if video.state = "error"
            return false
        end if
        sleep(100)
    end while
    
    return false
end function

function tryFallbackQuality(video as object, failedQuality as string, metadata as object) as object
    result = {
        success: false,
        quality: failedQuality,
        fallbackUsed: false,
        error: "All fallbacks exhausted"
    }
    
    ' ? "[QualitySwitch] Trying fallback strategies for failed quality: "; failedQuality
    
    ' Strategy 1: Try a lower quality
    lowerQuality = findLowerQuality(failedQuality, metadata)
    if lowerQuality <> invalid
        ' ? "[QualitySwitch] Fallback: Trying lower quality: "; lowerQuality.qualityID
        switchResult = performQualitySwitch(video, lowerQuality.qualityID, metadata)
        if switchResult.success
            result.success = true
            result.quality = lowerQuality.qualityID
            result.fallbackUsed = true
            return result
        end if
    end if
    
    ' Strategy 2: Try automatic quality
    automaticQuality = findAutomaticQuality(metadata)
    if automaticQuality <> invalid
        ' ? "[QualitySwitch] Fallback: Trying automatic quality"
        switchResult = performQualitySwitch(video, automaticQuality.qualityID, metadata)
        if switchResult.success
            result.success = true
            result.quality = automaticQuality.qualityID
            result.fallbackUsed = true
            return result
        end if
    end if
    
    ' Strategy 3: Try the fallback quality
    fallbackMetadata = findQualityByResolution(m.fallbackQuality, metadata)
    if fallbackMetadata <> invalid
        ' ? "[QualitySwitch] Fallback: Trying default fallback: "; m.fallbackQuality
        switchResult = performQualitySwitch(video, fallbackMetadata.qualityID, metadata)
        if switchResult.success
            result.success = true
            result.quality = fallbackMetadata.qualityID
            result.fallbackUsed = true
            return result
        end if
    end if
    
    ' Strategy 4: Try any available quality
    for each quality in metadata
        if quality.qualityID <> failedQuality
            ' ? "[QualitySwitch] Fallback: Trying any available quality: "; quality.qualityID
            switchResult = performQualitySwitch(video, quality.qualityID, metadata)
            if switchResult.success
                result.success = true
                result.quality = quality.qualityID
                result.fallbackUsed = true
                return result
            end if
        end if
    end for
    
    return result
end function

function findLowerQuality(currentQuality as string, metadata as object) as object
    ' Parse resolution from quality string (e.g., "720p60" -> 720)
    currentRes = parseResolution(currentQuality)
    if currentRes = 0
        return invalid
    end if
    
    bestLower = invalid
    bestLowerRes = 0
    
    for each quality in metadata
        qualityRes = parseResolution(quality.qualityID)
        if qualityRes < currentRes and qualityRes > bestLowerRes
            bestLower = quality
            bestLowerRes = qualityRes
        end if
    end for
    
    return bestLower
end function

function findAutomaticQuality(metadata as object) as object
    for each quality in metadata
        if quality.qualityID.InStr("Auto") > -1 or quality.qualityID.InStr("automatic") > -1
            return quality
        end if
    end for
    return invalid
end function

function findQualityByResolution(resolution as string, metadata as object) as object
    for each quality in metadata
        if quality.qualityID.InStr(resolution) > -1
            return quality
        end if
    end for
    return invalid
end function

function parseResolution(qualityString as string) as integer
    ' Extract resolution number from quality string
    ' e.g., "720p60" -> 720, "1080p" -> 1080
    if qualityString = invalid or qualityString = ""
        return 0
    end if
    
    ' Remove "p" and everything after it
    pIndex = qualityString.InStr("p")
    if pIndex > 0
        resString = qualityString.Left(pIndex)
        ' Remove any non-numeric prefix
        numericRes = ""
        for i = 0 to resString.Len() - 1
            char = resString.Mid(i, 1)
            if char >= "0" and char <= "9"
                numericRes = numericRes + char
            end if
        end for
        if numericRes <> ""
            return Val(numericRes)
        end if
    end if
    
    return 0
end function

function shouldUseFallback(error as string) as boolean
    ' Determine if we should immediately try fallback based on error type
    if error = invalid
        return false
    end if
    
    errorLower = LCase(error)
    
    ' Immediate fallback for these errors
    if errorLower.InStr("not found") > -1
        return true
    else if errorLower.InStr("invalid") > -1
        return true
    else if errorLower.InStr("unavailable") > -1
        return true
    else if errorLower.InStr("forbidden") > -1
        return true
    end if
    
    ' Retry for temporary errors
    return false
end function

sub scheduleRetry(video as object, targetQuality as string, metadata as object)
    ' Schedule a retry after a delay
    retryTimer = CreateObject("roSGNode", "Timer")
    retryTimer.duration = 3 ' 3 seconds
    retryTimer.repeat = false
    
    ' Store context for retry
    retryTimer.video = video
    retryTimer.targetQuality = targetQuality
    retryTimer.metadata = metadata
    
    retryTimer.observeField("fire", "onRetryTimer")
    retryTimer.control = "start"
end sub

sub onRetryTimer(event as object)
    timer = event.getRoSGNode()
    video = timer.video
    targetQuality = timer.targetQuality
    metadata = timer.metadata
    
    ' ? "[QualitySwitch] Retrying quality switch to: "; targetQuality
    attemptQualitySwitch(video, targetQuality, metadata)
end sub

sub resetSwitchAttempts()
    m.switchAttempts = {}
    m.switchHistory = []
end sub

function getSwitchStatistics() as object
    stats = {
        totalAttempts: 0,
        failedQualities: [],
        successRate: 0,
        lastSwitchTime: m.lastSwitchTime
    }
    
    for each quality in m.switchAttempts
        stats.totalAttempts = stats.totalAttempts + m.switchAttempts[quality]
        if m.switchAttempts[quality] >= m.maxSwitchAttempts
            stats.failedQualities.push(quality)
        end if
    end for
    
    if m.switchHistory.count() > 0
        successCount = 0
        for each switch in m.switchHistory
            if switch.attempt = 1
                successCount = successCount + 1
            end if
        end for
        stats.successRate = successCount / m.switchHistory.count()
    end if
    
    return stats
end function