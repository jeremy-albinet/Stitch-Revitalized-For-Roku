sub init()
    m.disposed = false
    m.worker = invalid
    m.video = invalid
    m.content = invalid
    m.pending = invalid
    m.owner = ""
    m.stopping = false
    m.acknowledged = false
    m.cleanupClock = invalid
    m.timer = m.top.findNode("cleanupTimer")
    if m.timer <> invalid then m.timer.observeField("fire", "onAdCleanupTick")
end sub

function beginContent(video as object, source as string, sourceKind as string) as string
    if m.disposed or m.top.cleanupBlocked then return ""
    if type(video) <> "roSGNode" or video.content = invalid then return ""
    if not video.isSubtype("Video") then return ""
    if not video.hasField("supportsDisposal") or not video.supportsDisposal then return ""
    if source <> video.content.url then return ""
    if sourceKind <> "direct" and sourceKind <> "loopback" and sourceKind <> "relay" then return ""
    owner = LCase(CreateObject("roDeviceInfo").GetRandomUUID()).Replace("-", "")
    if not tadOwner(owner) then return ""
    ' One pending primitive source snapshot and its current video replace any
    ' older pending request; an old worker must acknowledge stop first.
    m.pending = { owner: owner, video: video, content: video.content, source: source, sourceKind: sourceKind }
    if m.worker <> invalid
        stopAdWorker()
    else
        startPendingAdWorker()
    end if
    return owner
end function

sub startPendingAdWorker()
    if m.pending = invalid or m.disposed or m.top.cleanupBlocked or m.worker <> invalid then return
    pending = m.pending
    m.pending = invalid
    if pending.video.content = invalid then return
    if not pending.content.isSameNode(pending.video.content) then return
    if pending.video.content.url <> pending.source then return
    m.video = pending.video
    m.content = pending.content
    m.owner = pending.owner
    m.source = pending.source
    m.stopping = false
    m.acknowledged = false
    if not m.video.callFunc("beginAdCountdown", m.owner)
        clearAdVideo()
        return
    end if
    m.worker = CreateObject("roSGNode", "TwitchAdMetadata")
    if m.worker = invalid
        clearAdVideo()
        return
    end if
    m.worker.observeField("response", "onAdMetadataResponse")
    m.worker.observeField("state", "onAdWorkerState")
    m.worker.owner = m.owner
    m.worker.source = m.source
    m.worker.sourceKind = pending.sourceKind
    m.worker.stopRequested = false
    m.top.busy = true
    m.worker.control = "run"
end sub

sub endContent(owner as string)
    if m.pending <> invalid
        if m.pending.owner = owner then m.pending = invalid
    end if
    if m.owner <> owner or owner = "" then return
    stopAdWorker()
end sub

sub clearAdVideo()
    if m.video <> invalid then m.video.callFunc("clearAdCountdown", m.owner)
    m.video = invalid
    m.content = invalid
    m.source = ""
end sub

sub stopAdWorker()
    clearAdVideo()
    if m.worker = invalid
        m.owner = ""
        return
    end if
    if not m.stopping
        m.stopping = true
        m.cleanupClock = CreateObject("roTimespan")
        if m.timer <> invalid then m.timer.control = "start"
    end if
    m.worker.stopRequested = true
    onAdWorkerState()
end sub

sub onAdMetadataResponse()
    if m.worker = invalid then return
    response = m.worker.response
    if type(response) <> "roAssociativeArray" then return
    if response.owner <> m.owner then return
    if response.DoesExist("closed")
        if response.Count() <> 5 or not twitchAdClockBoolean(response.closed) or response.closed <> true then return
        if not twitchAdClockBoolean(response.cleanupOk) then return
        if type(response.cues) <> "roArray" or type(response.bounds) <> "roArray" then return
        if response.cues.Count() <> 0 or response.bounds.Count() <> 0 then return
        m.acknowledged = response.cleanupOk
        clearAdVideo()
        if not m.acknowledged
            m.top.cleanupBlocked = true
            m.pending = invalid
            return ' Retain until actual Task state=stop; never force unsafe work.
        end if
        ' A closed response acknowledges native/file cleanup, but the Task must
        ' also actually stop before its observer owner or a replacement moves on.
        if m.worker.state = "stop" then releaseAdWorker()
        return
    end if
    if m.disposed or m.stopping or m.video = invalid or m.content = invalid then return
    if response.Count() <> 3 or not tadCuesValid(response.cues) or not twitchAdClockBoundsValid(response.bounds) then return
    if m.video.content = invalid then return
    if not m.content.isSameNode(m.video.content) or m.video.content.url <> m.source then return
    m.video.callFunc("setAdMetadata", m.owner, response.cues, response.bounds)
end sub

sub onAdWorkerState()
    if m.worker = invalid then return
    worker = m.worker
    if worker.state <> "stop" then return
    response = m.worker.response
    if type(response) = "roAssociativeArray"
        if response.DoesExist("closed") then onAdMetadataResponse()
    end if
    if m.worker = invalid then return
    if not m.worker.isSameNode(worker) then return
    ' A crash/normal return without the explicit safe cleanup acknowledgement
    ' cannot authorize a new Task or claim that its staging file was removed.
    if not m.acknowledged then m.top.cleanupBlocked = true
    clearAdVideo()
    releaseAdWorker()
end sub

sub releaseAdWorker()
    worker = m.worker
    m.worker = invalid
    ignored = destroyTask(worker, "state")
    ignored = destroyTask(worker, "response")
    if m.timer <> invalid then m.timer.control = "stop"
    m.owner = ""
    m.stopping = false
    m.top.busy = false
    if m.disposed
        closeAdOwner()
    else if not m.top.cleanupBlocked
        startPendingAdWorker()
    else
        m.pending = invalid
    end if
end sub

sub onAdCleanupTick()
    if not m.stopping or m.worker = invalid or m.cleanupClock = invalid then return
    onAdWorkerState()
    if m.worker = invalid then return
    if m.cleanupClock.TotalMilliseconds() >= 5000
        m.top.cleanupBlocked = true
        m.pending = invalid
        ' Fail boundedly and retain the native worker until acknowledgement.
        ' Never interrupt a transfer/file owner to manufacture clean shutdown.
        if m.timer <> invalid then m.timer.control = "stop"
    end if
end sub

sub closeAdOwner()
    if m.worker <> invalid then return
    if m.timer <> invalid
        m.timer.control = "stop"
        m.timer.unobserveField("fire")
    end if
    m.top.closed = true
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.pending = invalid
    stopAdWorker()
    if m.worker = invalid then closeAdOwner()
end sub
