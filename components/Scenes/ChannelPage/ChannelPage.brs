sub init()
    m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    m.top.observeField("focusedChild", "onGetfocus")
    m.rowlist = m.top.findNode("homeRowList")
    m.rowlist.observeField("itemSelected", "handleItemSelected")
    m.username = m.top.findNode("username")
    m.followers = m.top.findNode("followers")
    m.description = m.top.findNode("description")
    m.avatar = m.top.findNode("avatar")
end sub

sub updatePage()
    m.username.text = m.top.contentRequested.streamerDisplayName
    m.GetContentTask = createApiTask("getChannelHomeQuery", "updateChannelInfo", {
        params: { id: m.top.contentRequested.streamerLogin }
    })
    m.GetShellTask = createApiTask("getChannelShell", "updateChannelShell", {
        params: { id: m.top.contentRequested.streamerLogin }
    })
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
    FocusRowlist()
end sub

sub onDestroy()
    m.top.unobserveField("focusedChild")
    m.rowlist.unobserveField("itemSelected")
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.GetShellTask = destroyTask(m.GetShellTask, "response")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        if key = "back"
            m.top.backPressed = true
            return true
        end if
        if key = "OK"
            ? "selected"
        end if
    end if
    return false
end function
