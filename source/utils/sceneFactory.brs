' Scene factory functions — one per scene type heroScene dispatches.
' Each creates and configures a node with scene-specific observers.
' Shared observers (backPressed, contentSelected) and tree placement
' are handled by the dispatcher in heroScene.brs.

function build_Following()
    node = createObject("roSGNode", "Following")
    node.id = "Following"
    node.translation = [0, 0]
    return node
end function

function build_Browse()
    node = createObject("roSGNode", "Browse")
    node.id = "Browse"
    node.translation = [0, 0]
    return node
end function

function build_Search()
    node = createObject("roSGNode", "Search")
    node.id = "Search"
    node.translation = [0, 0]
    return node
end function

function build_Settings()
    node = createObject("roSGNode", "Settings")
    node.id = "Settings"
    node.translation = [0, 0]
    return node
end function

function build_LoginPage()
    node = createObject("roSGNode", "LoginPage")
    node.id = "LoginPage"
    node.translation = [0, 0]
    node.observeField("finished", "onLoginFinished")
    return node
end function

function build_ChannelPage()
    node = createObject("roSGNode", "ChannelPage")
    node.id = "ChannelPage"
    node.translation = [0, 0]
    node.observeField("finished", "onLoginFinished")
    return node
end function

function build_GamePage()
    node = createObject("roSGNode", "GamePage")
    node.id = "GamePage"
    node.translation = [0, 0]
    return node
end function

function build_VideoPlayer()
    node = createObject("roSGNode", "VideoPlayer")
    node.id = "VideoPlayer"
    node.translation = [0, 0]
    return node
end function

