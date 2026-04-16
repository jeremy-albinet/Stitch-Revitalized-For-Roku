sub init()
    m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    m.top.observeField("focusedChild", "onGetfocus")
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.username = m.top.findNode("username")
    m.followers = m.top.findNode("followers")
    m.description = m.top.findNode("description")
    m.livestreamlabel = m.top.findNode("livestreamlabel")
    m.liveDuration = m.top.findNode("liveDuration")
    m.avatar = m.top.findNode("avatar")
    m.chatWindow = m.top.findNode("chat")
    m.menu = m.top.findNode("channelMenu")
    m.menu.menuOptionsText = ["Full Screen Chat", "Logout"]
    m.menu.observeField("buttonSelected", "onButtonSelected")
    m.menu.setFocus(true)
end sub

sub fullScreenChat()
    if m.top.fullscreenchat
        m.chatWindow.translation = "[0,0]"
        m.chatWindow.height = 720
        m.chatWindow.width = 1280
        m.chatWindow.fontSize = get_user_setting("FullScreenChatFontSize")
    else
        m.chatWindow.translation = "[30,330]"
        m.chatWindow.width = "1220"
        m.chatWindow.height = "380"
        m.chatWindow.fontSize = get_user_setting("ChatFontSize")
    end if
end sub

sub updatePage()
    m.username.text = m.top.contentRequested.streamerDisplayName
    m.GetContentTask = CreateObject("roSGNode", "TwitchApiTask") ' create task for feed retrieving
    ' ' observe content so we can know when feed content will be parsed
    m.GetContentTask.observeField("response", "updateChannelInfo")
    m.GetContentTask.request = {
        type: "getChannelHomeQuery",
        params: {
            id: m.top.contentRequested.streamerLogin
        }
    }
    m.GetContentTask.functionName = m.getcontenttask.request.type
    m.getcontentTask.control = "run"
    m.GetShellTask = CreateObject("roSGNode", "TwitchApiTask") ' create task for feed retrieving
    ' ' observe content so we can know when feed content will be parsed
    m.GetShellTask.observeField("response", "updateChannelShell")
    m.GetShellTask.request = {
        type: "getChannelShell",
        params: {
            id: m.top.contentRequested.streamerLogin
        }
    }
    m.getshellTask.functionName = m.getshelltask.request.type
    m.getshellTask.control = "run"
    m.chatWindow.channel_id = m.top.contentRequested.streamerId
    m.chatWindow.channel = m.top.contentRequested.streamerLogin
    m.chatWindow.visible = true
end sub

sub updateChannelShell()
    setBannerImage()
end sub

sub setBannerImage()
    bannerGroup = m.top.findNode("banner")
    poster = createObject("roSGNode", "Poster")
    rsp = m.GetShellTask.response
    if rsp?.bannerImageUrl <> invalid
        poster.uri = rsp.bannerImageUrl
    else
        poster.uri = "pkg:/images/default_banner.png"
    end if
    poster.width = 1280
    poster.height = 320
    poster.scale = [1.1, 1.1]
    poster.visible = true
    poster.translation = [0, (0 - poster.height / 3)]
    ' overlay = createObject("roSGNode", "Rectangle")
    ' overlay.color = "0x01010110"
    ' overlay.width = 1280
    ' overlay.height = 320
    ' poster.appendChild(overlay)
    bannerGroup.appendChild(poster)
end sub

sub updateChannelInfo()
    rsp = m.GetcontentTask.response
    if rsp = invalid then return
    m.followers.text = numberToText(rsp.followerCount) + " " + tr("followers")
    if rsp.profileImageUrl <> invalid
        m.avatar.uri = rsp.profileImageUrl
    end if
end sub


sub handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.playContent = true
    m.top.contentSelected = selectedItem
end sub


function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ? "Channel Page Key Event: "; key
        if key = "up"
            return true
        end if
        if key = "down"
            return true
        end if
        if key = "right"
            return true
        end if
        if key = "left"
            return true
        end if
        if key = "back"
            if m.top.fullscreenchat
                m.top.fullscreenchat = false
            else
                m.top.backPressed = true
            end if
            return true
        end if
        if key = "OK"
            ? "selected"
        end if
    end if
    return false
end function

sub onButtonSelected()
    selectedButton = LCase(m.menu.menuOptionsText[m.menu.buttonSelected])
    ? "selected button: "; selectedButton
    if selectedButton = "logout"
        active_user = get_setting("active_user", "$default$")
        if active_user <> "$default$"
            ? "default Registry keys: "; getRegistryKeys("$default$")
            NukeRegistry(active_user)
            set_setting("active_user", "$default$")
            ? "active User: "; get_setting("active_user", "$default$")
        else
            for each key in getRegistryKeys("$default$")
                if key <> "temp_device_code"
                    unset_user_setting(key)
                end if
            end for
        end if
        m.top.finished = true
        m.top.backPressed = true
    end if
    if selectedButton = "full screen chat"
        m.top.fullscreenchat = not m.top.fullscreenchat
    end if
end sub
