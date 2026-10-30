sub init()
    m.disposed = false
    m.global.addFields({ fixtureSigned: false, fixtureHistory: [{ login: "fixture-channel", displayName: "Fixture Channel", iconUrl: "pkg:/images/default_banner.png" }], fixtureCards: [] })
    setConstants()
    m.footprints = []
    m.menu = createObject("roSGNode", "MenuBar")
    m.top.appendChild(m.menu)
    m.menu.menuOptionsText = ["Following", "Browse", "Live Channels", "Categories"]
    m.recentBar = createObject("roSGNode", "RecentlyWatchedBar")
    m.top.appendChild(m.recentBar)
    m.recentBar.observeField("contentSelected", "onRecentSelected")
    m.activeNode = createObject("roSGNode", "SceneManagerGroup")
    m.activeNode.id = "PriorPage"
    m.top.appendChild(m.activeNode)
end sub

function fixtureStart() as object
    m.recentBar.callFunc("fixtureSelect")
    return m.activeNode
end function

function fixtureRead() as object
    pages = []
    for each node in m.top.getChildren(m.top.getChildCount(), 0)
        if node.subtype() = "ChannelPage" then pages.push(node)
    end for
    return { active: m.activeNode, depth: m.footprints.count(), request: m.recentBar.contentSelected, pages: pages }
end function

function fixtureFollowing(signedIn as boolean) as object
    teardownAllScenes()
    m.global.fixtureSigned = signedIn
    m.activeNode = buildNode("Following")
    m.activeNode.setFocus(true)
    return m.activeNode
end function

' Playback and unrelated menu actions are output boundaries.
sub onContentSelected()
end sub

sub onMenuRequest()
end sub
