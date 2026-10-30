function fixtureHero() as object
    return { active: m.activeNode, menu: m.menu, rail: m.recentBar, footprints: m.footprints.Count(), disposed: m.disposed }
end function

sub fixtureOpenFollowing()
    openPage("Following")
end sub

sub fixtureLoginFinished()
    onLoginFinished()
end sub

function fixtureNewManager() as object
    manager = CreateObject("roSGNode", "RokuDemuxSession")
    m.top.AppendChild(manager)
    m.top.localPlaybackSession = manager
    return manager
end function

sub fixtureOpenPlayer(request as object)
    if m.activeNode <> invalid then m.footprints.Push(m.activeNode)
    m.activeNode = buildNode("VideoPlayer")
    m.activeNode.contentRequested = request
    m.activeNode.SetFocus(true)
end sub
