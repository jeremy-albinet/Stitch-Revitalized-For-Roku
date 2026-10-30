sub init()
    setConstants()
    m.global.addFields({ fixtureSigned: false, fixtureHistory: [] })
    m.disposed = false
    m.footprints = []
    m.menu = createObject("roSGNode", "MenuBar")
    m.top.appendChild(m.menu)
    m.menu.menuOptionsText = ["Following", "Browse", "Live Channels", "Categories"]
    m.startupStatus = createObject("roSGNode", "StatusPanel")
    m.top.appendChild(m.startupStatus)
end sub

function fixtureRoute() as object
    m.activeNode = buildNode("Following")
    before = m.activeNode
    m.activeNode.setFocus(true)
    task = before.callFunc("fixtureRead").task
    task.response = { shelves: [] }
    before.findNode("status").findNode("buttons").buttonSelected = 1
    after = m.activeNode
    value = { before: before, after: after, active: m.menu.activeItem, focus: m.menu.focusItem, task: task }
    before.menuRequest = "Following"
    value.afterStale = m.activeNode
    teardownAllScenes()
    return value
end function

' Unused host endpoints: the actual onMenuRequest/openPage/build/discard run.
sub onBackPressed()
end sub

sub onContentSelected()
end sub
