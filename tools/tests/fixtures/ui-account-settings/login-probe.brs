function fixtureRead() as object
    return { rendezvous: m.RendezvouzTask, oauth: m.OauthTask, user: m.UserLoginTask, dialog: m.signOutDialog, actions: m.actions, disposed: m.disposed }
end function
sub fixtureShowCode(code as dynamic, expiry as dynamic)
    showCode(code, expiry)
end sub
sub fixtureRetry()
    RunContentTask()
end sub
