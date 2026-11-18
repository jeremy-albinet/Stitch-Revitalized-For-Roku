sub init()
    m.top.observeField("focusedChild", "onGetfocus")
    ? "init"; TimeStamp()
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
    ' m.allChannels = m.top.findNode("allChannels")
    ' m.allChannels.observeField("itemSelected", "handleItemSelected")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.offlineList = m.top.findNode("offlineList")
    m.loading = true
    m.lastLoad = 0
    m.GetContentTask = createApiTask("getFollowingPageQuery", "decideRoute")
    m.refreshTimer = createTimer(120, "onRefreshTimer", true)
end sub

function isLoggedIn() as boolean
    user = get_setting("active_user")
    return not m.top.anonymous and user <> invalid and user <> "$default$"
end function

' Following is the visible screen only while heroScene has no channel, game or player page on top of it.
function isTopScene() as boolean
    parent = m.top.getParent()
    if parent = invalid then return false
    for each child in parent.getChildren(-1, 0)
        kind = child.subtype()
        if kind = "ChannelPage" or kind = "GamePage" or kind = "VideoPlayer" then return false
    end for
    return true
end function

sub onRefreshTimer()
    refreshFollowing(0)
end sub

' Silent reload; skipped for anonymous users, hidden screen, in-flight load or a load newer than minAge seconds.
sub refreshFollowing(minAge as integer)
    if m.loading or not isLoggedIn() or not isTopScene() then return
    if CreateObject("roDateTime").AsSeconds() - m.lastLoad < minAge then return
    m.loading = true
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.GetContentTask = createApiTask("getFollowingPageQuery", "decideRoute")
end sub

sub decideRoute()
    ? "DecideRoute"; TimeStamp()
    m.loading = false
    if m.GetContentTask.response <> invalid
        m.lastLoad = CreateObject("roDateTime").AsSeconds()
        ' Count the next timer refresh from this load, so a return refresh and a tick don't run back to back.
        m.refreshTimer.control = "stop"
        m.refreshTimer.control = "start"
    end if
    if isLoggedIn()
        ? "Route -> handleRecommendedSections"
        handleRecommendedSections()
    else
        ? "Route -> handleDefaultSections"
        handleDefaultSections()
    end if
end sub

sub handleDefaultSections()
    rsp = m.GetcontentTask.response
    if rsp = invalid or rsp.shelves = invalid or rsp.shelves.count() = 0 then return
    contentCollection = createObject("RoSGNode", "ContentNode")
    for each shelf in rsp.shelves
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
    updateRowList(contentCollection)
end sub



sub handleRecommendedSections()
    ? "handleRecommendedSections: "; TimeStamp()
    contentCollection = createObject("RoSGNode", "ContentNode")
    rsp = m.GetcontentTask.response
    if rsp = invalid then return
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
    try
        ? "LiveStreamSection Complete: "; TimeStamp()
        if rsp <> invalid and rsp.offlineFollows <> invalid and rsp.offlineFollows.count() > 0
            row = createObject("RoSGNode", "ContentNode")
            row.title = tr("followedOfflineUsers")
            first = true
            itemsPerRow = 9
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
    if contentCollection.getChildCount() > 0
        updateRowList(contentCollection)
    end if
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
    focusPos = findFocusedChannel(contentCollection)
    m.rowlist.rowHeights = rowHeights
    m.rowlist.showRowLabel = showRowLabel
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.content = contentCollection
    m.rowlist.numRows = m.rowlist.content.getChildCount()
    if focusPos <> invalid then m.rowlist.jumpToRowItem = focusPos
    m.rowlist.rowlabelcolor = m.global.constants.colors.twitch.purple10
    ? "updateRowList Done: "; TimeStamp()
end sub

' On a reload, where the focused channel lands in newContent (same login), else the old row/index clamped.
' Returns invalid on the first load.
function findFocusedChannel(newContent as object) as dynamic
    old = m.rowlist.content
    focused = m.rowlist.rowItemFocused
    if old = invalid or focused = invalid or newContent.getChildCount() = 0 then return invalid
    oldRow = old.getChild(focused[0])
    oldItem = invalid
    if oldRow <> invalid then oldItem = oldRow.getChild(focused[1])
    if oldItem <> invalid
        rows = []
        for each row in newContent.getChildren(-1, 0)
            logins = []
            for each item in row.getChildren(-1, 0)
                logins.push(item.streamerLogin)
            end for
            rows.push(logins)
        end for
        found = findLoginPosition(rows, oldItem.streamerLogin)
        if found <> invalid then return found
    end if
    r = focused[0]
    if r > newContent.getChildCount() - 1 then r = newContent.getChildCount() - 1
    c = focused[1]
    if c > newContent.getChild(r).getChildCount() - 1 then c = newContent.getChild(r).getChildCount() - 1
    return [r, c]
end function

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
    ' A dialog is open: it owns focus until it closes (heroScene restores focus then).
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid then return
    ' focusedChild also fires when focus leaves (menu, sidebar) or the list content changes: only act on gaining it.
    if not m.top.isInFocusChain()
        updateRowListFocusFeedback()
        return
    end if
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.rowlist.focusedChild.id = "homeRowList"
        m.rowlist.focusedChild.setFocus(true)
    end if
    updateRowListFocusFeedback()
    refreshFollowing(30)
end sub

' Hide the RowList focus rectangle when focus leaves the scene (e.g. user
' presses Up to MenuBar). Restore it when focus returns. RowList still
' remembers the previously focused tile internally.
sub updateRowListFocusFeedback()
    if m.rowlist = invalid then return
    hasFocus = false
    if m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
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
    m.top.unobserveField("focusedChild")
    if m.rowlist <> invalid
        m.rowlist.unobserveField("itemSelected")
    end if
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    if m.refreshTimer <> invalid
        m.refreshTimer.control = "stop"
        m.refreshTimer.unobserveField("fire")
    end if
end sub
