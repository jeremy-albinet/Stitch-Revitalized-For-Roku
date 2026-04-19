sub init()
    m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    m.top.observeField("focusedChild", "onGetfocus")
    m.rowlist = m.top.findNode("homeRowList")
    m.rowlist.observeField("itemSelected", "handleItemSelected")
    m.username = m.top.findNode("username")
    m.followers = m.top.findNode("followers")
    m.description = m.top.findNode("description")
    m.avatar = m.top.findNode("avatar")
    m.channelMenu = m.top.findNode("channelMenu")
    m.chat = m.top.findNode("chat")
    m.focusindicator = m.top.findNode("focusindicator")
end sub

function isOwnChannel() as boolean
    if get_setting("active_user", "$default$") = "$default$" then return false
    if m.top.contentRequested = invalid then return false
    myLogin = get_user_setting("login")
    theirLogin = m.top.contentRequested.streamerLogin
    if myLogin = invalid or theirLogin = invalid then return false
    return myLogin.toStr() = theirLogin.toStr()
end function

sub configureOwnChannelMode()
    if isOwnChannel()
        m.channelMenu.visible = true
        m.chat.visible = true
        m.focusindicator.visible = true
        m.chat.channel_id = m.top.contentRequested.streamerId
        m.chat.channel = m.top.contentRequested.streamerLogin
        m.channelMenu.menuOptionsText = ["Full Screen Chat", "Logout"]
        m.channelMenu.observeField("buttonSelected", "onMenuButtonSelected")
        m.channelMenu.setFocus(true)
    else
        m.channelMenu.visible = false
        m.chat.visible = false
        m.focusindicator.visible = false
    end if
end sub

sub updatePage()
    m.username.text = m.top.contentRequested.streamerDisplayName
    m.GetContentTask = createApiTask("getChannelHomeQuery", "updateChannelInfo", {
        params: { id: m.top.contentRequested.streamerLogin }
    })
    m.GetShellTask = createApiTask("getChannelShell", "updateChannelShell", {
        params: { id: m.top.contentRequested.streamerLogin }
    })
    configureOwnChannelMode()
end sub

sub fullScreenChat()
    if m.top.fullScreenChat
        m.chat.translation = "[0,0]"
        m.chat.height = 720
        m.chat.width = 1280
        m.chat.fontSize = get_user_setting("FullScreenChatFontSize")
    else
        m.chat.translation = "[30,330]"
        m.chat.width = "1220"
        m.chat.height = "380"
        m.chat.fontSize = get_user_setting("ChatFontSize")
    end if
end sub

sub onMenuButtonSelected()
    selectedButton = LCase(m.channelMenu.menuOptionsText[m.channelMenu.buttonSelected])
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
        m.top.fullScreenChat = not m.top.fullScreenChat
    end if
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
    rsp = m.GetContentTask.response
    if rsp = invalid then return
    m.description.infoText = rsp.description
    m.followers.text = numberToText(rsp.followerCount) + " " + tr("followers")
    if rsp.profileImageUrl <> invalid
        m.avatar.uri = rsp.profileImageUrl
    end if
    channelContent = buildContentNodeFromShelves(rsp)
    updateRowList(channelContent)
end sub

function buildContentNodeFromShelves(rsp)
    contentCollection = createObject("RoSGNode", "ContentNode")
    if rsp.isLive
        row = createObject("RoSGNode", "ContentNode")
        row.title = "Live Stream"
        rowItem = m.top.contentRequested
        row.appendChild(rowItem)
        contentCollection.appendChild(row)
    end if
    shelves = rsp.videoShelves
    for each shelf in shelves
        row = createObject("RoSGNode", "ContentNode")
        row.title = shelf.node.title
        for each stream in shelf.node.items
            rowItem = createObject("RoSGNode", "TwitchContentNode")
            rowItem.contentId = stream.id
            if stream.slug <> invalid
                rowItem.contentType = "CLIP"
                rowItem.clipSlug = stream.slug
                rowItem.contentTitle = stream.title
                rowItem.viewersCount = stream.viewCount
                rowItem.datePublished = stream.createdAt
            else
                rowItem.contentType = "VOD"
                rowItem.contentTitle = stream.vodTitle
                rowItem.viewersCount = stream.vodViewCount
                rowItem.datePublished = stream.vodCreatedAt
            end if
            if stream.previewThumbnailURL <> invalid
                rowItem.previewImageURL = Left(stream.previewThumbnailURL, len(stream.previewThumbnailURL) - 20) + "320x180." + Right(stream.previewThumbnailURL, 3)
            else if stream.thumbnailURL <> invalid
                rowItem.previewImageURL = stream.thumbnailURL
            end if
            rowItem.streamerDisplayName = m.top.contentRequested.streamerDisplayName
            rowItem.streamerLogin = m.top.contentRequested.streamerLogin
            rowItem.streamerId = m.top.contentRequested.streamerId
            rowItem.streamerProfileImageUrl = m.top.contentRequested.streamerProfileImageUrl
            if stream.game <> invalid
                rowItem.gameDisplayName = stream.game.displayName
                rowItem.gameBoxArtUrl = Left(stream.game.boxArtUrl, Len(stream.game.boxArtUrl) - 20) + "188x250.jpg"
                rowItem.gameId = stream.game.Id
            end if
            row.appendChild(rowItem)
        end for
        contentCollection.appendChild(row)
    end for
    return contentCollection
end function

sub updateRowList(contentCollection)
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        config = getRowConfig(row?.getchild(0)?.contentType, hasRowLabel)
        if config <> invalid
            showRowLabel.push(hasRowLabel)
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for
    m.rowList.rowHeights = rowHeights
    m.rowlist.showRowLabel = showRowLabel
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.content = contentCollection
    m.rowlist.numRows = rowHeights.count()
end sub

sub handleItemSelected()
    selectedRow = m.rowlist.content.getChild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.playContent = true
    m.top.contentSelected = selectedItem
end sub

sub FocusRowlist()
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.rowlist.focusedChild.id = "homeRowList"
        m.rowlist.focusedChild.setFocus(true)
    end if
end sub

sub onGetFocus()
    if isOwnChannel()
        if m.channelMenu <> invalid
            m.channelMenu.setFocus(true)
        end if
    else
        FocusRowlist()
    end if
end sub

sub onDestroy()
    m.top.unobserveField("focusedChild")
    m.rowlist.unobserveField("itemSelected")
    if m.channelMenu <> invalid
        m.channelMenu.unobserveField("buttonSelected")
    end if
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.GetShellTask = destroyTask(m.GetShellTask, "response")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ? "Channel Page Key Event: "; key
        if key = "back"
            if m.top.fullScreenChat
                m.top.fullScreenChat = false
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
