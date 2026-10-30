sub init()
    m.disposed = false
    if m.global.constants <> invalid
        m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    end if
    m.top.observeField("focusedChild", "onGetfocus")
    m.rowlist = m.top.findNode("homeRowList")
    m.rowlist.observeField("itemSelected", "handleItemSelected")
    m.username = m.top.findNode("username")
    m.followers = m.top.findNode("followers")
    m.description = m.top.findNode("description")
    m.avatar = m.top.findNode("avatar")
    initPageStatus()
end sub

sub updatePage()
    m.username.text = m.top.contentRequested.streamerDisplayName
    updatePinHint()
    loadChannelInfo()
    m.GetShellTask = createApiTask("getChannelShell", "updateChannelShell", {
        params: { id: m.top.contentRequested.streamerLogin }
    })
end sub

sub updatePinHint()
    hint = m.top.findNode("pinHint")
    if RW_IsPinned(m.top.contentRequested.streamerLogin)
        hint.text = tr("Press * to unpin from sidebar")
    else
        hint.text = Substitute(tr("Press * to pin to sidebar ({0} max)"), RW_MaxItems().ToStr())
    end if
end sub

sub toggleChannelPin()
    content = m.top.contentRequested
    if content = invalid then return
    entry = {
        login: content.streamerLogin,
        displayName: content.streamerDisplayName,
        iconUrl: content.streamerProfileImageUrl,
        id: content.streamerId
    }
    ' Prefer resolved metadata without mutating the shared navigation request.
    if m.GetContentTask <> invalid
        rsp = m.GetContentTask.response
        if type(rsp) = "roAssociativeArray"
            if rsp.streamerId <> invalid then entry.id = rsp.streamerId
            if rsp.profileImageUrl <> invalid then entry.iconUrl = rsp.profileImageUrl
        end if
    end if
    result = RW_SetPinned(entry, not RW_IsPinned(content.streamerLogin))
    updatePinHint()
    if result = "limit"
        m.top.findNode("pinHint").text = Substitute(tr("Pin limit reached ({0}). Unpin a channel first."), RW_MaxItems().ToStr())
    end if
end sub

' One finite request on open or explicit Try again. The banner keeps its
' own request and default image.
sub loadChannelInfo()
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    setPageStatus("loading", tr("Loading channel…"))
    m.GetContentTask = createApiTask("getChannelHomeQuery", "updateChannelInfo", {
        params: { id: m.top.contentRequested.streamerLogin }
    })
end sub

sub onStatusAction(actionId as string)
    if actionId = "retry"
        loadChannelInfo()
    else if actionId = "back"
        m.top.backPressed = true
    end if
end sub

function channelName() as string
    content = m.top.contentRequested
    if content = invalid then return ""
    if content.streamerDisplayName <> invalid and content.streamerDisplayName <> "" then return content.streamerDisplayName
    if content.streamerLogin <> invalid then return content.streamerLogin
    return ""
end function

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
    if m.disposed or m.GetContentTask = invalid then return
    rsp = m.GetContentTask.response
    if rsp = invalid
        setPageStatus("error", tr("Couldn't load this channel"), tr("Check your internet connection and try again."), ["retry", "back"])
        return
    end if
    m.description.infoText = rsp.description
    m.followers.text = numberToText(rsp.followerCount) + " " + tr("followers")
    if rsp.profileImageUrl <> invalid
        m.avatar.uri = rsp.profileImageUrl
    end if
    isLive = false
    if GetInterface(rsp.isLive, "ifBoolean") <> invalid then isLive = rsp.isLive
    showLiveMarker(isLive)
    channelContent = buildContentNodeFromShelves(rsp)
    if channelContent.getChildCount() = 0
        setPageStatus("empty", tr("Nothing to watch yet"), Substitute(tr("{0} isn't live and has no recent videos or clips."), channelName()), ["back"])
        return
    end if
    updateRowList(channelContent)
    hidePageStatus()
end sub

' A live channel's avatar gets Twitch's red ring and a LIVE pill below it.
sub showLiveMarker(isLive as boolean)
    ring = m.top.findNode("liveRing")
    pill = m.top.findNode("livePill")
    if ring <> invalid then ring.visible = isLive
    if pill = invalid then return
    pill.visible = isLive
    if not isLive then return
    width = fitLabelPlate(m.top.findNode("livePillLabel"), m.top.findNode("livePillPlate"), tr("LIVE"), 16, 48)
    ' Centre the pill under the 120 px avatar.
    pill.translation = [60 - Int(width / 2), 110]
end sub

function buildContentNodeFromShelves(rsp)
    ' Navigation can share this request node with the source screen.
    request = m.top.contentRequested
    streamerId = request.streamerId
    if GetInterface(rsp.streamerId, "ifString") <> invalid
        if rsp.streamerId <> "" then streamerId = rsp.streamerId
    end if
    contentCollection = createObject("RoSGNode", "ContentNode")
    if rsp.isLive
        row = createObject("RoSGNode", "ContentNode")
        row.title = tr("Live now")
        rowItem = createObject("roSGNode", "TwitchContentNode")
        if request.contentType = "LIVE"
            setTwitchContentFields(rowItem, request.getFields())
        else
            liveTitle = rsp.liveTitle
            if GetInterface(liveTitle, "ifString") = invalid then liveTitle = ""
            if liveTitle = "" then liveTitle = channelName()
            setTwitchContentFields(rowItem, {
                contentType: "LIVE",
                contentTitle: liveTitle,
                viewersCount: rsp.liveViewersCount,
                gameDisplayName: rsp.liveGameDisplayName,
                streamerLogin: request.streamerLogin,
                streamerDisplayName: request.streamerDisplayName,
                streamerProfileImageUrl: request.streamerProfileImageUrl,
                previewImageURL: Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-1280x720.jpg", request.streamerLogin)
            })
        end if
        if rowItem.contentTitle = invalid or rowItem.contentTitle = ""
            liveTitle = rsp.liveTitle
            if GetInterface(liveTitle, "ifString") = invalid or liveTitle = "" then liveTitle = channelName()
            rowItem.contentTitle = liveTitle
        end if
        rowItem.streamerId = streamerId
        if rowItem.previewImageURL = invalid or rowItem.previewImageURL = ""
            rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-1280x720.jpg", rowItem.streamerLogin)
        end if
        if GetInterface(rsp.liveViewersCount, "ifInt") <> invalid
            if rsp.liveViewersCount >= 0 then rowItem.viewersCount = rsp.liveViewersCount
        end if
        row.appendChild(rowItem)
        contentCollection.appendChild(row)
    end if
    shelves = rsp.videoShelves
    if type(shelves) <> "roArray" then shelves = []
    for each shelf in shelves
        items = shelf?.node?.items
        if type(items) <> "roArray" then items = []
        row = createObject("RoSGNode", "ContentNode")
        title = shelf?.node?.title
        if title = invalid then title = ""
        row.title = title
        for each stream in items
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
            rowItem.streamerId = streamerId
            rowItem.streamerProfileImageUrl = m.top.contentRequested.streamerProfileImageUrl
            if stream.game <> invalid
                rowItem.gameDisplayName = stream.game.displayName
                rowItem.gameBoxArtUrl = Left(stream.game.boxArtUrl, Len(stream.game.boxArtUrl) - 20) + "188x250.jpg"
                rowItem.gameId = stream.game.Id
            end if
            row.appendChild(rowItem)
        end for
        ' Empty shelves would leave the RowList without a row size.
        if row.getChildCount() > 0 then contentCollection.appendChild(row)
    end for
    return contentCollection
end function

sub updateRowList(contentCollection)
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        config = getRowConfig(row?.getchild(0)?.contentType, hasRowLabel, true)
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
    if m.rowlist.content = invalid then return
    selectedRow = m.rowlist.content.getChild(m.rowlist.rowItemSelected[0])
    if selectedRow = invalid then return
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
    if m.disposed then return
    if m.top.contentRequested <> invalid then updatePinHint()
    ' While the status panel offers actions, it holds page focus.
    if not focusStatusIfActive() then FocusRowlist()
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
sub updateRowListFocusFeedback()
    if m.rowlist = invalid then return
    m.rowlist.drawFocusFeedback = m.rowlist.isInFocusChain()
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.lastFocus = invalid
    m.top.unobserveField("focusedChild")
    m.rowlist.unobserveField("itemSelected")
    releasePageStatus()
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.GetShellTask = destroyTask(m.GetShellTask, "response")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and not m.disposed
        if key = "options"
            toggleChannelPin()
            return true
        end if
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
