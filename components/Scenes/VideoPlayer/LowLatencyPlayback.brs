' Opt-in lower live latency: direct Twitch live playback goes through a
' loopback relay that trims the playlists (see LowLatencyRelay). One relay
' serves one Video, so every restart begins near the live edge again.
sub initLowLatencyPlayback()
    m.lowLatencyRelay = invalid
    m.lowLatencyReadyUrl = ""
    m.lowLatencyPending = false
    m.lowLatencyDirect = false
    m.lowLatencyRecovery = false
    m.lowLatencyUnavailable = false
end sub

function lowLatencyEligible() as boolean
    if m.lowLatencyUnavailable or m.rokuSessionId <> "" then return false
    if m.top.contentRequested = invalid or m.top.content = invalid then return false
    if m.top.contentRequested.contentType <> "LIVE" then return false
    if m.top.content.isProxied or m.top.content.isTransmux then return false
    url = m.top.content.url
    if GetInterface(url, "ifString") = invalid then return false
    if url.Left(8) <> "https://" then return false
    return get_user_setting("playback.lowLatency", "false") = "true"
end function

' True means playContent waits for a fresh relay to report its local URL.
function prepareLowLatencyPlayback(isRecovery as boolean) as boolean
    if m.lowLatencyReadyUrl <> "" then return false
    stopLowLatencyRelay()
    ' One direct start after a failed relay; the next start tries again.
    if m.lowLatencyDirect
        m.lowLatencyDirect = false
        return false
    end if
    if not lowLatencyEligible() then return false
    m.lowLatencyRelay = CreateObject("roSGNode", "LowLatencyRelay")
    if m.lowLatencyRelay = invalid
        m.lowLatencyUnavailable = true
        return false
    end if
    m.lowLatencyPending = true
    m.lowLatencyRecovery = isRecovery
    m.lowLatencyRelay.observeField("status", "onLowLatencyStatus")
    m.lowLatencyRelay.sourceUrl = m.top.content.url
    m.lowLatencyRelay.control = "run"
    return true
end function

' Only the attempt playContent is waiting for is applied. A relay that fails
' after serving is left to the player's stall and error recovery.
sub onLowLatencyStatus(event as object)
    if m.disposed or m.isExiting or m.lowLatencyRelay = invalid or not m.lowLatencyPending then return
    if not event.getRoSGNode().isSameNode(m.lowLatencyRelay) then return
    status = event.getData()
    if type(status) <> "roAssociativeArray" then return
    m.lowLatencyPending = false
    if GetInterface(status.url, "ifString") <> invalid
        m.lowLatencyReadyUrl = status.url
    else
        ? getLogTimestamp(); " [VideoPlayer] Lower latency unavailable: "; status.failure
        ' A refused playlist (for example separate audio) stays refused for
        ' this item; a failed fetch or bind may work on the next start.
        if status.failure = "unsupported_playlist" then m.lowLatencyUnavailable = true
        stopLowLatencyRelay()
        m.lowLatencyDirect = true
    end if
    playContent(m.lowLatencyRecovery)
end sub

' Roku can report finished when a relayed playlist stops advancing. Unless
' Twitch ended the stream, that is recovered like a stall instead of leaving.
function lowLatencyFinishedEarly() as boolean
    if m.lowLatencyRelay = invalid or m.video = invalid or m.rokuSessionId <> "" then return false
    return m.video.lowLatency and not m.lowLatencyRelay.ended
end function

' Consumes the ready URL: the returned copy plays through the relay, while
' m.top.content keeps the signed Twitch source for refreshes and switches.
function lowLatencyContent(original as object) as object
    url = m.lowLatencyReadyUrl
    m.lowLatencyReadyUrl = ""
    fields = original.getFields()
    fields.Delete("change")
    fields.Delete("focusedChild")
    fields.url = url
    fields.StreamUrls = [url]
    stream = { "quality": true, "bitrate": 0 }
    if type(fields.Streams) = "roArray"
        if fields.Streams.Count() > 0 then stream.Append(fields.Streams[0])
    end if
    stream.url = url
    fields.Streams = [stream]
    playable = CreateObject("roSGNode", "TwitchContentNode")
    playable.setFields(fields)
    return playable
end function

sub stopLowLatencyRelay()
    if m.lowLatencyRelay <> invalid then m.lowLatencyRelay.stopRequested = true
    m.lowLatencyRelay = destroyTask(m.lowLatencyRelay, "status")
    m.lowLatencyReadyUrl = ""
    m.lowLatencyPending = false
end sub
