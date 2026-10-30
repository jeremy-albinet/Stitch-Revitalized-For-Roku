' The scene owns the cooperative session beyond this player's lifetime.
' Eligible combined-track content without a configured service uses it.
sub initRokuPlayback()
    m.rokuSession = invalid
    m.rokuSessionId = ""
    m.rokuChosen = false
    m.rokuPendingContent = invalid
    m.rokuPreparedContent = invalid
    m.rokuDeferredPlay = false
    m.rokuExitPending = false
    m.rokuPlayRecovery = false
    m.rokuLowLatency = false
    scene = m.top.getScene()
    if scene = invalid then return
    if not scene.hasField("localPlaybackSession") then return
    session = scene.localPlaybackSession
    if session = invalid then return
    m.rokuSession = session
    session.observeFieldScoped("event", "onRokuSessionEvent")
    session.observeFieldScoped("busy", "onRokuSessionBusy")
end sub

sub enableRokuDescriptor(task as object)
    if get_user_setting("proxy.builtin", "true") <> "true" then return
    if m.rokuSession = invalid then return
    if m.rokuSession.cleanupBlocked then return
    if m.top.contentRequested = invalid then return
    if m.top.contentRequested.contentType = "LIVE" then task.enableRokuDemux = true
    if m.top.contentRequested.contentType = "VOD" and rokuVodRuntimeAvailable() then task.enableRokuDemux = true
end sub

function hasRokuDescriptor() as boolean
    if m.rokuSession = invalid or m.top.content = invalid then return false
    if m.top.content.playbackTransport <> "roku-demux" then return false
    descriptor = m.top.content.localPlaybackDescriptor
    if type(descriptor) <> "roAssociativeArray" then return false
    if descriptor.version = 2 then return rokuVodRuntimeAvailable() and rokuVodDescriptorValid(descriptor)
    return true
end function

function canTryRokuPlayback() as boolean
    if not hasRokuDescriptor() then return false
    if m.rokuSession.cleanupBlocked then return false
    return not m.disposed and not m.rokuExitPending
end function

' Eligible combined audio/video content plays through the on-Roku splitter
' without a prompt; the playback notice names the fixed quality it uses.
function chooseRokuPlayback() as boolean
    if not m.rokuChosen
        if not canTryRokuPlayback() then return false
        m.rokuChosen = true
    end if
    return hasRokuDescriptor()
end function

' True means the ordinary play path must wait. Metadata retains the original
' signed rendition for a future refresh/quality switch; it is never persisted.
function prepareRokuPlayback(isRecovery as boolean) as boolean
    if m.rokuSession = invalid then return false
    if m.rokuExitPending then return true
    if hasRokuDescriptor() and m.rokuChosen
        if m.rokuPreparedContent <> invalid
            if m.rokuPreparedContent.isSameNode(m.top.content) then return false
        end if
        if m.rokuPendingContent <> invalid
            if m.rokuPendingContent.isSameNode(m.top.content) then return true
        end if
        if m.rokuSession.cleanupBlocked
            showErrorDialog(tr("Roku playback stopped"), tr("The previous playback session could not finish cleaning up. Restart Stitch before trying on Roku again."), false)
            return true
        end if
        m.rokuDeferredPlay = false
        m.rokuPreparedContent = invalid
        m.rokuPendingContent = m.top.content
        m.rokuPlayRecovery = isRecovery
        m.rokuLowLatency = get_user_setting("playback.lowLatency", "false") = "true"
        sessionId = m.rokuSession.callFunc("startSession", m.top.content.localPlaybackDescriptor, m.rokuLowLatency)
        if type(sessionId) <> "String" and type(sessionId) <> "roString" then sessionId = ""
        m.rokuSessionId = sessionId
        if sessionId = ""
            m.rokuPendingContent = invalid
            showErrorDialog(tr("Roku playback unavailable"), tr("This stream could not start on Roku. Try again, choose another quality, or configure the optional audio service."))
        else
            ' Also handles a synchronous worker-creation refusal.
            onRokuSessionEvent()
        end if
        return true
    end if
    if m.rokuSessionId <> ""
        m.rokuPendingContent = invalid
        m.rokuPreparedContent = invalid
        m.rokuDeferredPlay = true
        m.rokuPlayRecovery = isRecovery
        m.rokuSession.callFunc("stopSession", m.rokuSessionId)
        onRokuSessionBusy()
        return true
    end if
    return false
end function

sub onRokuSessionEvent()
    if m.disposed or m.rokuSession = invalid then return
    event = m.rokuSession.event
    if type(event) <> "roAssociativeArray" then return
    if event.id <> m.rokuSessionId or m.rokuSessionId = "" then return
    if m.rokuSession.cleanupBlocked and (event.status = "failed" or event.status = "cancelled")
        m.rokuPendingContent = invalid
        m.rokuPreparedContent = invalid
        m.rokuDeferredPlay = false
        showErrorDialog(tr("Roku playback stopped"), tr("The previous playback session could not finish cleaning up. Restart Stitch before trying on Roku again."), false)
        if m.rokuExitPending
            if m.rokuSession.callFunc("canLeaveBlockedSession", m.rokuSessionId) then exitPlayer()
        end if
        return
    end if
    if m.rokuExitPending or m.rokuDeferredPlay then return
    if event.status = "ready"
        if m.rokuPendingContent = invalid or m.rokuPreparedContent <> invalid then return
        if type(event.metadata) <> "roAssociativeArray" then return
        original = m.rokuPendingContent
        if original.localPlaybackDescriptor.version = 2
            if not rokuVodRuntimeAvailable() or not rokuVodPlaybackReadyValid(event, m.rokuSessionId, original.localPlaybackDescriptor) then return
        end if
        fields = original.getFields()
        fields.Delete("change")
        fields.Delete("focusedChild")
        fields.url = event.url
        fields.StreamUrls = [event.url]
        streams = []
        if type(fields.Streams) = "roArray"
            if fields.Streams.count() > 0
                stream = {}
                stream.append(fields.Streams[0])
                stream.url = event.url
                streams.push(stream)
            end if
        end if
        if streams.count() = 0
            streams = [{ "url": event.url, "quality": event.metadata["isHD"], "bitrate": Int(event.metadata.bandwidth / 1000), "contentid": original.localPlaybackDescriptor["qualityId"] }]
        end if
        fields.Streams = streams
        fields.StreamQualities = [event.metadata["isHD"]]
        fields.isTransmux = false
        fields.isProxied = false
        fields.ForwardQueryStringParams = false
        fields.playbackNotice = tr("Playing on this Roku at {0}. Automatic uses a fixed quality.").replace("{0}", original.localPlaybackDescriptor["qualityId"])
        playable = CreateObject("roSGNode", "TwitchContentNode")
        playable.setFields(fields)
        m.rokuPendingContent = invalid
        m.rokuPreparedContent = playable
        m.top.content = playable
        playContent(m.rokuPlayRecovery)
    else if event.status = "failed"
        sourceTransition = false
        if GetInterface(event.reason, "ifString") <> invalid then sourceTransition = event.reason = "source_transition"
        if sourceTransition
            if m.isExiting or m.manualRetryPending or m.errorDialog <> invalid then return
            if m.rokuPendingContent <> invalid or m.rokuPreparedContent = invalid or m.video = invalid or not m.rokuChosen then return
            if m.top.contentRequested = invalid then return
            if m.top.contentRequested.contentType <> "LIVE" then return
            if m.retryTimer <> invalid or m.reconnectTimer <> invalid or m.reconnectTask <> invalid then return
            m.rokuPreparedContent = invalid
            ' The owner still acknowledges old Task/Video cleanup before a
            ' refreshed, decoder-validated session can replace the timeline.
            beginLiveReconnect("source_transition")
            return
        end if
        m.rokuPendingContent = invalid
        m.rokuPreparedContent = invalid
        showErrorDialog(tr("Roku playback stopped"), tr("This stream could not continue on Roku. Try again, choose another quality, or configure the optional audio service."), not m.rokuSession.cleanupBlocked)
    end if
end sub

sub onRokuSessionBusy()
    if m.disposed or m.rokuSession = invalid then return
    if m.rokuSession.busy then return
    ' A stopped unsafe owner can end the UI wait without authorizing playback.
    ' Do not depend on delivery order of the failed event and busy observation.
    if m.rokuSession.cleanupBlocked
        m.rokuPendingContent = invalid
        m.rokuPreparedContent = invalid
        m.rokuDeferredPlay = false
    end if
    if m.rokuSessionId = "" then return
    if not m.rokuExitPending and not m.rokuDeferredPlay then return
    m.rokuSessionId = ""
    m.rokuPreparedContent = invalid
    m.rokuPendingContent = invalid
    if m.rokuExitPending
        m.rokuExitPending = false
        finishPlayerExit()
    else
        m.rokuDeferredPlay = false
        playContent(m.rokuPlayRecovery)
    end if
end sub

' Back waits for acknowledged stop. Permanent disposal removes the UI's own
' observers but leaves the scene owner watching the worker and real Video.
function stopRokuPlayback(waitForExit = false as boolean) as boolean
    if m.rokuSession = invalid or m.rokuSessionId = "" then return false
    m.rokuPendingContent = invalid
    m.rokuPreparedContent = invalid
    m.rokuDeferredPlay = false
    if waitForExit then m.rokuExitPending = true
    session = m.rokuSession
    sessionId = m.rokuSessionId
    session.callFunc("stopSession", sessionId)
    mayLeave = not session.busy
    if waitForExit and not mayLeave then mayLeave = session.callFunc("canLeaveBlockedSession", sessionId)
    if mayLeave
        m.rokuSessionId = ""
        m.rokuExitPending = false
        return false
    end if
    return true
end function

sub destroyRokuPlayback()
    if m.rokuSession = invalid then return
    m.rokuSession.unobserveFieldScoped("event")
    m.rokuSession.unobserveFieldScoped("busy")
    ignored = stopRokuPlayback()
    m.rokuSession = invalid
end sub

sub closeTransmuxDialog()
    dialog = m.transmuxDialog
    if dialog = invalid then return
    m.transmuxDialog = invalid
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        if scene.dialog.isSameNode(dialog) then scene.dialog = invalid
    end if
end sub

' Scene-retained metadata ownership survives wrapper replacements. Its stop
' never blocks or retries playback, and untrusted/Automatic sources hide ads.
sub startAdMetadata(content as object)
    if m.disposed or m.video = invalid or content = invalid then return
    if not m.video.hasField("positionInfo") then return
    kind = "direct"
    if m.rokuSessionId <> ""
        if m.rokuPreparedContent = invalid then return
        if not m.rokuPreparedContent.isSameNode(content) then return
        if rokuVodDescriptorValid(content.localPlaybackDescriptor) then return
        kind = "loopback"
    else
        if content.isProxied then return
        if type(content.Streams) <> "roArray" then return
        if content.Streams.Count() <> 1 then return
        if content.Streams[0].url <> content.url then return
        if m.video.lowLatency then kind = "relay"
    end if
    scene = m.top.getScene()
    if scene = invalid then return
    owner = scene.findNode("stitchAdMetadataOwner")
    if owner = invalid
        owner = CreateObject("roSGNode", "AdMetadataOwner")
        if owner = invalid then return
        owner.id = "stitchAdMetadataOwner"
        scene.appendChild(owner)
    end if
    if owner.subtype() <> "AdMetadataOwner" then return
    m.adMetadataOwner = owner
    m.adContentOwner = owner.callFunc("beginContent", m.video, content.url, kind)
end sub

sub stopAdMetadata()
    if m.adMetadataOwner = invalid then return
    if tadString(m.adContentOwner) and m.adContentOwner <> "" then m.adMetadataOwner.callFunc("endContent", m.adContentOwner)
    m.adContentOwner = ""
    m.adMetadataOwner = invalid
end sub
