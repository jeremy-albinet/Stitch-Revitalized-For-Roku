sub init()
    setConstants()
    m.global.addFields({ fixtureRegistry: {}, fixtureWrites: 0, fixtureDeletes: 0, fixtureHttpInput: {}, fixtureHttpRequest: {} })
    m.disposed = false
    m.footprints = []
    m.menu = createObject("roSGNode", "MenuBar")
    m.top.appendChild(m.menu)
    m.menu.menuOptionsText = ["Following", "Browse", "Live Channels", "Categories"]
    m.startupStatus = createObject("roSGNode", "StatusPanel")
    m.top.appendChild(m.startupStatus)
end sub
sub fixtureOpen(name as string)
    openPage(name)
end sub
sub fixtureMenuSelection()
    onMenuSelection()
end sub
function fixtureRead() as object
    return { active: m.activeNode, footprints: m.footprints, menu: m.menu, disposed: m.disposed }
end function
sub fixtureCleanup()
    teardownAllScenes()
end sub
sub fixtureFinalCleanup()
    teardownAllScenes()
    disposeNodeTree(m.menu)
    disposeNodeTree(m.startupStatus)
    m.disposed = true
end sub
sub showDeviceCodeRecovery()
    m.global.fixtureRecovery = true
end sub
sub startDeviceCode()
end sub
sub onMenuRequest()
end sub
