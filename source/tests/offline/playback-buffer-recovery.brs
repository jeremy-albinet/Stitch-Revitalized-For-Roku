' @include components/Scenes/VideoPlayer/VideoPlayer.brs
' @include components/Scenes/VideoPlayer/ContentAdvisory.brs
sub main()
    m.disposed = false
    m.top = { contentRequested: { contentType: "VOD" } }
    m.chatWindow = invalid
    m.watchdogTimer = invalid
    m.errorHandler = invalid
    m.compatibilityNoticeShown = true
    m.isExiting = false
    m.allowBreak = false
    m.recoveryAttempts = 3
    m.lastBufferState = "buffering"
    m.bufferStartTime = CreateObject("roDateTime").AsSeconds() - 120
    for episode = 1 to 3
        m.video = { state: "playing", position: 20 }
        m.bufferCheckTimer = playbackBufferFixtureTimer()
        m.retryTimer = playbackBufferFixtureTimer()
        onVideoStateChange()
        if not playbackBufferExpect(m.bufferStartTime = 0, "recovery resets the elapsed buffer episode") then return
        if not playbackBufferExpect(m.bufferCheckTimer = invalid and m.retryTimer = invalid, "successful recovery releases pending timers") then return
        if not playbackBufferExpect(m.lastBufferState = "playing", "recovered state recorded") then return
        startTime = CreateObject("roDateTime").AsSeconds()
        m.video = { state: "buffering", position: 20 }
        m.bufferCheckTimer = playbackBufferFixtureTimer()
        onVideoStateChange()
        if not playbackBufferExpect(m.bufferStartTime >= startTime, "later buffering begins with a fresh timestamp") then return
        if not playbackBufferExpect(m.lastBufferState = "buffering", "new buffer state recorded") then return
        if not playbackBufferExpect(m.recoveryAttempts = 3, "brief new buffering preserves the recovery budget") then return
    end for
    ? "STITCH_TEST_PASS: playback buffer recovery"
end sub

function playbackBufferFixtureTimer() as object
    return {
        control: "start",
        unobserveField: function(field as string) as dynamic
            return invalid
        end function
    }
end function

function playbackBufferExpect(condition as boolean, detail as string) as boolean
    if not condition then ? "STITCH_TEST_FAIL: " + detail
    return condition
end function
