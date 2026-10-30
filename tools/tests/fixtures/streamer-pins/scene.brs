sub init()
    m.disposed = false
    m.footprints = []
    m.menu = createObject("roSGNode", "MenuBar")
    m.top.appendChild(m.menu)
    m.menu.menuOptionsText = ["Following", "Browse", "Search"]
end sub

sub fixtureReady(liveHistory = false as boolean)
    teardownAllScenes()
    m.validateOauthToken = destroyTask(m.validateOauthToken, "response")
    m.validateOauthToken = createApiTask("validateOauthToken", "ValidateUserLogin")
    if m.recentBar <> invalid
        m.recentBar.unobserveField("contentSelected")
        m.recentBar.unobserveField("hasItems")
        m.recentBar.callFunc("onDestroy")
        m.top.removeChild(m.recentBar)
    end if
    m.recentBar = createObject("roSGNode", "RecentlyWatchedBar")
    m.top.appendChild(m.recentBar)
    if liveHistory
        task = m.recentBar.callFunc("fixtureRead").task
        if task <> invalid
            live = {}
            for each login in task.request.params.logins
                live[login] = true
            end for
            task.response = live
        end if
    end if
    m.recentBar.observeField("contentSelected", "onRecentSelected")
    m.recentBar.observeField("hasItems", "onRecentItemsChanged")
    m.activeNode = createObject("roSGNode", "SceneManagerGroup")
    m.activeNode.id = "PriorPage"
    m.top.appendChild(m.activeNode)
    m.top.setFocus(true)
    m.activeNode.setFocus(true)
end sub

function fixtureRead() as object
    return { rail: m.recentBar, active: m.activeNode, depth: m.footprints.Count(), validation: m.validateOauthToken }
end function

sub fixtureLogout()
    onLogoutFinished()
end sub

sub fixtureCleanup()
    teardownAllScenes()
    m.validateOauthToken = destroyTask(m.validateOauthToken, "response")
    if m.recentBar <> invalid
        m.recentBar.unobserveField("contentSelected")
        m.recentBar.unobserveField("hasItems")
        m.recentBar.callFunc("onDestroy")
    end if
    disposeNodeTree(m.menu)
end sub

' Playback is an output boundary, so OK can be checked without playing video.
sub onContentSelected()
end sub

sub onMenuRequest()
end sub
