sub init()
    m.disposed = false
    m.allowBreak = true
    m.isExiting = false
    m.rokuExitPending = false
    m.pendingChannelSignIn = false
    m.chatWindow = m.top.findNode("chat")
end sub

function fixtureReadPlayer() as object
    return { disposed: m.disposed, exiting: m.isExiting }
end function

' __PRODUCTION_HANDLERS__

' No media, network, account or dialog work runs in this fixture.
sub resetContentAdvisory()
end sub

sub pauseTwitchEngagement()
end sub

sub stopTwitchEngagement()
end sub

sub cancelBookmarkWait()
end sub

sub stopAdMetadata()
end sub

sub resetLiveRecoveryHealth()
end sub

sub stopLowLatencyRelay()
end sub

sub closeOwnedPlayerDialogs()
end sub

sub cleanupReconnectTask()
end sub

sub destroyRokuPlayback()
end sub

sub stopPlaybackForDialog()
end sub

function stopRokuPlayback(_exitRequested as boolean) as boolean
    return false
end function
