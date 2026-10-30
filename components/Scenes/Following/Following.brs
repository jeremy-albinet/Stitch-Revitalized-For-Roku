sub init()
    m.disposed = false
    m.top.observeField("focusedChild", "onGetfocus")
    ? "init"; TimeStamp()
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
    ' m.allChannels = m.top.findNode("allChannels")
    ' m.allChannels.observeField("itemSelected", "handleItemSelected")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.offlineList = m.top.findNode("offlineList")
    m.signedIn = isSignedIn()
    initPageStatus()
    if not m.signedIn
        ' Anonymous viewers see popular channels; say so above the rows.
        hint = m.top.findNode("anonymousHint")
        if hint <> invalid
            hint.text = tr("Not signed in. Showing popular live channels — sign in to see who you follow.")
            hint.visible = true
            m.rowlist.translation = [m.rowlist.translation[0], 112]
        end if
    end if
    loadFollowing()
end sub

function isSignedIn() as boolean
    activeUser = get_setting("active_user")
    return activeUser <> invalid and activeUser <> "$default$"
end function

' One finite request per page load or explicit Try again.
sub loadFollowing()
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    if m.signedIn
        setPageStatus("loading", tr("Loading channels you follow…"))
    else
        setPageStatus("loading", tr("Loading live channels…"))
    end if
    m.GetContentTask = createApiTask("getFollowingPageQuery", "decideRoute")
end sub

sub showFollowingError()
    setPageStatus("error", tr("Couldn't load Following"), tr("Check your internet connection and try again."), ["retry"])
end sub

sub onStatusAction(actionId as string)
    if actionId = "retry"
        loadFollowing()
    else if actionId = "browse"
        m.top.menuRequest = "Browse"
    end if
end sub

sub decideRoute()
    if m.disposed or m.GetContentTask = invalid then return
    ? "DecideRoute"; TimeStamp()
    if isSignedIn()
        ? "Route -> handleRecommendedSections"
        handleRecommendedSections()
    else
        ? "Route -> handleDefaultSections"
        handleDefaultSections()
    end if
end sub

sub handleDefaultSections()
    rsp = m.GetcontentTask.response
    if rsp = invalid
        showFollowingError()
        return
    end if
    shelves = rsp.shelves
    if shelves = invalid then shelves = []
    contentCollection = createObject("RoSGNode", "ContentNode")
    for each shelf in shelves
        ' Skip any GAME-tile shelf (e.g., "Categories we think you'll like").
        ' GAME tiles render with the wrong row height in the shared RowList,
        ' which only handles LIVE stream tiles correctly. See TODO.md.
        isGameShelf = shelf.streams <> invalid and shelf.streams.count() > 0 and shelf.streams[0].contentType = "GAME"
        if not isGameShelf
            row = createObject("RoSGNode", "ContentNode")
            row.title = shelf.title
            for each stream in shelf.streams
                rowItem = createObject("RoSGNode", "TwitchContentNode")
                setTwitchContentFields(rowItem, stream)
                row.appendChild(rowItem)
            end for
            if row.getchildcount() > 0
                contentCollection.appendChild(row)
            end if
        end if
    end for
    if contentCollection.getChildCount() = 0
        setPageStatus("empty", tr("No live channels to show right now"), tr("Try again in a moment, or find something to watch in Browse."), ["retry", "browse"])
        return
    end if
    updateRowList(contentCollection)
    hidePageStatus()
end sub



sub handleRecommendedSections()
    ? "handleRecommendedSections: "; TimeStamp()
    contentCollection = createObject("RoSGNode", "ContentNode")
    rsp = m.GetcontentTask.response
    if rsp = invalid
        showFollowingError()
        return
    end if
    try
        if rsp <> invalid and rsp.liveFollows <> invalid and rsp.liveFollows.count() > 0
            row = createObject("RoSGNode", "ContentNode")
            row.title = tr("followedLiveUsers")
            first = true
            itemsPerRow = getStreamTile().perRow
            appended = false
            for i = 0 to (rsp.liveFollows.count() - 1) step 1
                if first
                    first = false
                else if i mod itemsPerRow = 0
                    row = createObject("RoSGNode", "ContentNode")
                end if
                twitchContentNode = createObject("roSGNode", "TwitchContentNode")
                setTwitchContentFields(twitchContentNode, rsp.liveFollows[i])
                row.appendChild(twitchContentNode)
                appended = false
                if row.getChildCount() = itemsPerRow
                    contentCollection.appendChild(row)
                    appended = true
                end if
            end for
            if not appended and row <> invalid and row.getchildcount() > 0
                contentCollection.appendChild(row)
            end if
        end if
    catch e
        ? "[Following] handleRecommendedSections: live follows parse error: "; e
    end try
    liveRowCount = contentCollection.getChildCount()
    try
        ? "LiveStreamSection Complete: "; TimeStamp()
        if rsp <> invalid and rsp.offlineFollows <> invalid and rsp.offlineFollows.count() > 0
            row = createObject("RoSGNode", "ContentNode")
            row.title = tr("followedOfflineUsers")
            first = true
            itemsPerRow = 6
            ? "OfflineSection Start: "; TimeStamp()
            streams = []
            streams.append(rsp.offlineFollows)
            sortMethod = get_user_setting("FollowPageSorting", "streamerLogin")
            ? "Sort Method: "; sortMethod
            if sortMethod = "streamerLogin"
                streams.sortBy("streamerLogin", "i")
            else if sortMethod = "followerCount"
                streams.sortBy("followerCount", "r")
            else if sortMethod = "ASC_followerCount"
                streams.sortBy("followerCount")
            end if
            appended = false
            for i = 0 to (streams.count() - 1) step 1
                if first
                    first = false
                else if i mod itemsPerRow = 0
                    row = createObject("RoSGNode", "ContentNode")
                end if
                twitchContentNode = createObject("roSGNode", "TwitchContentNode")
                setTwitchContentFields(twitchContentNode, streams[i])
                row.appendChild(twitchContentNode)
                appended = false
                if row.getChildCount() = itemsPerRow
                    contentCollection.appendChild(row)
                    appended = true
                end if
            end for
            if not appended and row <> invalid and row.getchildcount() > 0
                contentCollection.appendChild(row)
            end if
            ? "OfflineStreamSection Complete: "; TimeStamp()
        end if
    catch e
        ? "[Following] handleRecommendedSections: offline follows parse error: "; e
    end try
    if contentCollection.getChildCount() = 0
        m.rowlist.content = contentCollection
        m.rowlist.numRows = 0
        setPageStatus("empty", tr("You're not following anyone yet"), tr("Channels you follow on Twitch appear here. Find something to watch in Browse."), ["browse"])
        return
    end if
    if liveRowCount = 0
        contentCollection.getChild(0).title = tr("No one you follow is live · Offline channels")
    end if
    updateRowList(contentCollection)
    hidePageStatus()
end sub

sub updateRowList(contentCollection)
    ? "updateRowList: "; TimeStamp()
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        showRowLabel.push(hasRowLabel)
        config = getRowConfig(row.getchild(0).contentType, hasRowLabel, true)
        if config <> invalid
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for
    m.rowlist.rowHeights = rowHeights
    m.rowlist.showRowLabel = showRowLabel
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.content = contentCollection
    m.rowlist.numRows = m.rowlist.content.getChildCount()
    m.rowlist.rowlabelcolor = m.global.constants.ui.color.text
    ? "updateRowList Done: "; TimeStamp()
end sub

sub handleItemSelected()
    item = invalid
    if m.rowlist.focusedChild <> invalid
        item = m.rowlist
    else if m.offlinelist <> invalid and m.offlinelist.focusedChild <> invalid
        item = m.offlinelist
    end if
    if item <> invalid
        selectedRow = item.content.getchild(item.rowItemSelected[0])
        if selectedRow = invalid then return
        selectedItem = selectedRow.getChild(item.rowItemSelected[1])
        if selectedItem = invalid then return
    else
        return
    end if

    ' Delegate to specific handler based on content type
    if selectedItem.contentType = "LIVE"
        ' Use the existing live handler for direct playback
        handleLiveItemSelected()
    else
        ' Regular navigation for other content types
        m.top.playContent = false
        m.top.contentSelected = selectedItem
    end if
end sub

sub handleLiveItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    if selectedRow = invalid then return
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    if selectedItem = invalid then return
    m.top.playContent = true
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.disposed then return
    ' focusedChild also notifies when a retained page loses focus.
    if not m.top.IsInFocusChain()
        updateRowListFocusFeedback()
        return
    end if
    if m.top.followRefreshPending
        m.top.followRefreshPending = false
        loadFollowing()
    end if
    ' While the status panel offers actions, it holds page focus.
    if not focusStatusIfActive()
        if m.rowlist.focusedChild = invalid
            m.rowlist.setFocus(true)
        else if m.rowlist.focusedChild.id = "homeRowList"
            m.rowlist.focusedChild.setFocus(true)
        end if
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene (e.g. user
' presses Up to MenuBar). Restore it when focus returns. RowList still
' remembers the previously focused tile internally.
sub updateRowListFocusFeedback()
    if m.rowlist = invalid then return
    hasFocus = false
    if m.top.IsInFocusChain() and m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
        hasFocus = true
    end if
    m.rowlist.drawFocusFeedback = hasFocus
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ? "Home Scene Key Event: "; key
        if key = "up" or key = "back"
            m.top.backPressed = true
            return true
        end if
    end if
    return false
end function

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.lastFocus = invalid
    m.top.unobserveField("focusedChild")
    if m.rowlist <> invalid
        m.rowlist.unobserveField("itemSelected")
    end if
    releasePageStatus()
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
