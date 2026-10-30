function fixturePlayer() as object
    return { task: m.PlayVideo, video: m.video, sessionId: m.rokuSessionId, exitPending: m.rokuExitPending, deferred: m.rokuDeferredPlay, disposed: m.disposed, dialog: m.transmuxDialog, errorDialog: m.errorDialog }
end function

sub fixtureSuppressSessionEvent()
    m.rokuSession.UnobserveFieldScoped("event")
end sub
