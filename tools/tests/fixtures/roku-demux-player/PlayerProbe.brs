' Read-only inspection and direct calls to actual production handlers.
function fixtureRead() as object
    return { task: m.PlayVideo, video: m.video, session: m.rokuSession, sessionId: m.rokuSessionId, chosen: m.rokuChosen, pendingContent: m.rokuPendingContent, prepared: m.rokuPreparedContent, deferred: m.rokuDeferredPlay, exitPending: m.rokuExitPending, pending: m.manualRetryPending, errorDialog: m.errorDialog, transmuxDialog: m.transmuxDialog, recovery: m.recoveryAttempts, reconnect: m.reconnectAttempts, reconnectTask: m.reconnectTask, reconnectTimer: m.reconnectTimer, retryTimer: m.retryTimer, disposed: m.disposed, transitionCharges: m.sourceTransitionCharges, healthVideo: m.liveRecoveryVideo, manualLiveQuality: m.manualLiveQuality, bufferTimer: m.bufferCheckTimer, relay: m.lowLatencyRelay, advanced: m.playbackHasAdvanced }
end function
sub fixtureChoiceAgain()
    onTransmuxDialogButton()
end sub
sub fixtureEventAgain()
    onRokuSessionEvent()
end sub
sub fixtureRetry()
    retryAfterError()
end sub
sub fixtureReconnect()
    doLiveReconnect()
end sub
sub fixtureFireRetry()
    retryPlayback()
end sub
sub fixtureRecovery(count as integer)
    m.recoveryAttempts = count
    m.reconnectAttempts = count
end sub
sub fixtureBack()
    ignored = onKeyEvent("back", true)
end sub
sub fixtureQualityEvent(event = invalid as dynamic)
    onQualityChangeRequested(event)
end sub
function fixtureLowerQuality() as dynamic
    return findLowerQuality()
end function
function fixtureDecodeRecovery() as object
    return m.errorHandler.callFunc("handleVideoError", 9, "fixture media decode error", m.video, m.top.contentRequested)
end function
sub fixtureProlongedBufferCheck()
    m.bufferStartTime = createObject("roDateTime").asSeconds() - 11
    handleBufferingState()
end sub
function fixtureWatchdogClock() as integer
    if m.fixtureWatchdogSec = invalid then return CreateObject("roDateTime").AsSeconds()
    return m.fixtureWatchdogSec
end function
sub fixtureWatchdog(nowSec as integer)
    m.fixtureWatchdogSec = nowSec
    onWatchdogFire()
end sub
sub fixtureCooldown(nowSec as integer)
    m.lastReconnectSuccessSec = nowSec
end sub
sub fixtureSessionIdentity(id as string)
    m.rokuSessionId = id
end sub
function fixtureErrorStatistics() as object
    return m.errorHandler.callFunc("getErrorStatistics")
end function
sub fixtureBufferTimeout(timer = invalid as dynamic)
    onBufferTimeout(fixtureNodeEvent(timer))
end sub

function fixtureNodeEvent(node as dynamic) as dynamic
    if node = invalid then return invalid
    return {
        node: node, getRoSGNode: function() as object
            return m.node
        end function
    }
end function

sub fixtureReconnectTimer(timer as object)
    doLiveReconnect(fixtureNodeEvent(timer))
end sub

sub fixtureReconnectResponse(task as object)
    onLiveReconnectResponse(fixtureNodeEvent(task))
end sub

' Only native clock reads are controlled. Callback decisions remain actual code.
function fixtureStartupClock() as object
    m.fixtureStartupMilliseconds = invalid
    return CreateObject("roTimeSpan")
end function

function fixtureStartupElapsed() as float
    if m.fixtureStartupMilliseconds <> invalid then return m.fixtureStartupMilliseconds
    return m.playbackInitTime.TotalMilliseconds()
end function

sub fixtureStartupAge(milliseconds as integer)
    m.fixtureStartupMilliseconds = milliseconds
end sub

sub fixtureScheduleReconnect(reason as string)
    beginLiveReconnect(reason)
end sub
