' Startup/auth and menu UI are outside this disposal fixture.
sub init()
    m.disposed = false
    m.recentBar = invalid
    m.footprints = []
    m.activeNode = invalid
end sub

function fixtureMount() as object
    player = createObject("roSGNode", "PlayerDisposalPlayer")
    m.top.appendChild(player)
    m.activeNode = player
    previous = createObject("roSGNode", "Group")
    previous.addFields({ lastFocus: invalid })
    m.footprints = [previous]
    player.observeField("backPressed", "onBackPressed")
    return player
end function

function focusedMenuItem() as string
    return ""
end function

' __PRODUCTION_HANDLERS__
