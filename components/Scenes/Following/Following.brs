sub init()
    m.top.observeField("focusedChild", "onGetfocus")
    ? "init"; TimeStamp()
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
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
    m.rowlist.rowlabelcolor = m.global.constants.colors.twitch.purple10
    ? "updateRowList Done: "; TimeStamp()
end sub

sub handleItemSelected()
    item = invalid
    if m.rowlist.focusedChild <> invalid
        item = m.rowList
    else if m.offlinelist.focusedChild <> invalid
        item = m.offlinelist
    end if
    if item <> invalid
        selectedRow = item.content.getchild(item.rowItemSelected[0])
        selectedItem = selectedRow.getChild(item.rowItemSelected[1])
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
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.playContent = true
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.rowlist.focusedChild.id = "homeRowList"
        m.rowlist.focusedChild.setFocus(true)
    end if
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
