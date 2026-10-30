' @include components/Modules/VideoErrorHandler/VideoErrorHandler.brs
sub main()
    init()
    for check = 1 to 5
        recovery = handleBufferStall(invalid)
        if not playbackPolicyExpect(not recovery.shouldRecover and recovery.action = "wait", "recent prolonged checks wait before quality reduction") then return
    end for
    recovery = handleBufferStall(invalid)
    if not playbackPolicyExpect(recovery.shouldRecover and recovery.action = "reduce_quality", "sixth recent check requests quality reduction") then return
    if not playbackPolicyExpect(m.bufferStallCount = 0, "quality reduction resets the check count") then return
    m.bufferStallCount = 5
    m.lastBufferTime = CreateObject("roDateTime").AsSeconds() - 121
    recovery = handleBufferStall(invalid)
    if not playbackPolicyExpect(not recovery.shouldRecover and recovery.action = "wait" and m.bufferStallCount = 1, "two quiet minutes reset stale checks in seconds") then return
    if not playbackPolicyExpect(m.currentRetryCount = 0, "buffer checks preserve the error retry budget") then return
    ? "STITCH_TEST_PASS: playback buffer policy"
end sub

function playbackPolicyExpect(condition as boolean, detail as string) as boolean
    if not condition then ? "STITCH_TEST_FAIL: " + detail
    return condition
end function
