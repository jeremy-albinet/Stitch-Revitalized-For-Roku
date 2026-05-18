sub init()
    m.top.observeField("focusedChild", "onGetfocus")
    ? "init"; TimeStamp()
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
    ' TileRow wraps an internal RowList; cache it for runtime-only fields
    ' (rowItemSelected, drawFocusFeedback) that TileRow does not re-expose.
    m.rowlistInner = m.rowlist.findNode("rowList")
    ' m.allChannels = m.top.findNode("allChannels")
    ' m.allChannels.observeField("itemSelected", "handleItemSelected")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.offlineList = m.top.findNode("offlineList")
    m.GetContentTask = createApiTask("getFollowingPageQuery", "decideRoute")
end sub

sub decideRoute()
    ? "DecideRoute"; TimeStamp()
    if get_setting("active_user") <> invalid and get_setting("active_user") <> "$default$"
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
            itemsPerRow = 3
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
    if contentCollection.getChildCount() > 0
        updateRowList(contentCollection)
    end if
end sub

sub updateRowList(contentCollection)
    ? "updateRowList: "; TimeStamp()
    ' TileRow owns rowItemSize, rowHeights, showRowLabel, rowLabelOffset, focus bitmap,
    ' and animation styles internally from design tokens. Per-scene tuning of those is
    ' no longer permitted; we only hand TileRow the content tree.
    m.rowlist.content = contentCollection
    ? "updateRowList Done: "; TimeStamp()
end sub

sub handleItemSelected()
    ' TileRow does not re-expose rowItemSelected, so read the [row, col] tuple from
    ' the internal RowList cached in init().
    item = invalid
    if m.rowlistInner <> invalid and m.rowlistInner.focusedChild <> invalid
        item = m.rowlistInner
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
    if m.rowlistInner = invalid then return
    selectedRow = m.rowlistInner.content.getchild(m.rowlistInner.rowItemSelected[0])
    if selectedRow = invalid then return
    selectedItem = selectedRow.getChild(m.rowlistInner.rowItemSelected[1])
    if selectedItem = invalid then return
    m.top.playContent = true
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.rowlist.focusedChild.id = "homeRowList"
        m.rowlist.focusedChild.setFocus(true)
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene (e.g. user
' presses Up to MenuBar). Restore it when focus returns. RowList still
' remembers the previously focused tile internally. drawFocusFeedback is a
' RowList property TileRow does not re-expose, so drive it on the internal
' RowList directly.
sub updateRowListFocusFeedback()
    if m.rowlistInner = invalid then return
    hasFocus = false
    if m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
        hasFocus = true
    end if
    m.rowlistInner.drawFocusFeedback = hasFocus
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
end sub
