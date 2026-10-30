' Override startup only. Navigation/disposal executes production heroScene code.
sub init()
    m.disposed = false
    m.activeNode = invalid
    m.footprints = []
    m.global.addField("analyticsTask", "node", false)
    m.menu = createObject("roSGNode", "Group")
    m.menu.addFields({ updateUserIcon: false })
    options = createObject("roSGNode", "Group")
    m.menuButton = createObject("roSGNode", "Button")
    m.menuButton.id = "Following"
    options.appendChild(m.menuButton)
    m.menu.appendChild(options)
    m.top.appendChild(m.menu)
    m.recentBar = createObject("roSGNode", "Group")
    m.recentBar.addFields({ itemHasFocus: false })
    m.recentBar.addField("contentSelected", "node", true)
    m.top.appendChild(m.recentBar)
    m.top.sidebarResource = createObject("roSGNode", "Following")
    m.recentBar.appendChild(m.top.sidebarResource)
end sub

sub begin()
    m.activeNode = buildNode("Following")
    m.activeNode.setFocus(true)
    m.top.active = m.activeNode
end sub

sub retain()
    m.recentBar.contentSelected = createObject("roSGNode", "ContentNode")
    onRecentSelected()
    m.top.saved = m.footprints.peek()
    m.top.active = m.activeNode
end sub

sub goBack()
    m.activeNode.backPressed = true
    onBackPressed()
    m.top.active = m.activeNode
end sub

sub switchTab()
    m.menuButton.setFocus(true)
    onMenuSelection()
    m.top.active = m.activeNode
end sub

sub login()
    onLoginFinished()
    m.top.active = m.activeNode
end sub

sub logout()
    onLogoutFinished()
    m.top.active = m.activeNode
end sub

sub disposeAgain(node as object)
    disposeNodeTree(node)
end sub

function rootBack(press as boolean) as boolean
    return onKeyEvent("back", press)
end function
