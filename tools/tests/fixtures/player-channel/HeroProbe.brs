function fixtureHero() as object
    pages = 0
    players = 0
    for each node in m.top.GetChildren(-1, 0)
        if node.IsSubtype("ChannelPage") then pages++
        if node.IsSubtype("VideoPlayer") then players++
    end for
    return { active: m.activeNode, rail: m.recentBar, footprints: m.footprints.Count(), pages: pages, players: players }
end function

sub fixtureOpenFollowing()
    openPage("Following")
end sub

sub fixtureAccountChanged()
    onLoginFinished()
end sub

sub fixtureSelectContent(content as object, play as boolean)
    m.activeNode.playContent = play
    m.activeNode.contentSelected = content
end sub

sub fixtureDeliverChannel(player as object)
    event = { owner: player, getRoSGNode: function() as object
        return m.owner
    end function }
    onPlayerChannelRequested(event)
end sub

function fixtureNewManager() as object
    manager = CreateObject("roSGNode", "RokuDemuxSession")
    m.top.AppendChild(manager)
    m.top.localPlaybackSession = manager
    return manager
end function
