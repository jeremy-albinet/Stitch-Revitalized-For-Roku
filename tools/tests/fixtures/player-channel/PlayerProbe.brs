function fixturePlayer() as object
    return { task: m.PlayVideo, video: m.video, chat: m.chatWindow, engagement: m.engagementTask, relay: m.lowLatencyRelay, sessionId: m.rokuSessionId, exitPending: m.rokuExitPending, disposed: m.disposed, followTask: m.channelFollowTask, followTimer: m.channelFollowTimer, followCache: m.channelFollowCache, followGeneration: m.channelFollowGeneration, recovery: m.recoveryAttempts, reconnect: m.reconnectAttempts, charges: m.sourceTransitionCharges }
end function

sub fixtureReplaceWrapper()
    playContent()
end sub

sub fixtureFollowDebts()
    m.recoveryAttempts = 1
    m.reconnectAttempts = 2
    m.sourceTransitionCharges = 3
end sub

sub fixtureDeliverFollow(task as object)
    event = { owner: task, getRoSGNode: function() as object
        return m.owner
    end function }
    onChannelFollowResponse(event)
end sub

sub fixtureExpireFollow(timer as object)
    event = { owner: timer, getRoSGNode: function() as object
        return m.owner
    end function }
    onChannelFollowTimeout(event)
end sub

sub fixtureDeliverClosed(dialog as object)
    event = { owner: dialog, getRoSGNode: function() as object
        return m.owner
    end function }
    onChannelActionsClosed(event)
end sub

sub fixtureCloseActions()
    closeChannelActions()
end sub

sub fixturePlaybackError()
    showErrorDialog("Canned playback error", "Canned recovery advice")
end sub

sub fixtureDeliverOpenChannel(video as object)
    event = { owner: video, getRoSGNode: function() as object
        return m.owner
    end function }
    onChannelActionsRequested(event)
end sub
