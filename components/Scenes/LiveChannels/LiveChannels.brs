sub init()
    m.top.observeField("focusedChild", "onGetfocus")
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowList = m.top.findNode("homeRowList")

    ' Guard check for missing node
    if m.rowlist = invalid
        ? "[LiveChannels] ERROR: homeRowList node not found in XML - component initialization failed"
        return
    end if

    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.GetContentTask = createApiTask("getBrowsePagePopularQuery", "handleRecommendedSections")
end sub

function buildContentNodeFromShelves(edges as object) as object
    itemsPerRow = 3
    contentCollection = createObject("RoSGNode", "ContentNode")
    if edges = invalid or type(edges) <> "roArray" or edges.count() = 0
        return contentCollection
    end if
    row = createObject("RoSGNode", "ContentNode")
    for i = 0 to (edges.count() - 1) step 1
        if i mod itemsPerRow = 0
            row = createObject("RoSGNode", "ContentNode")
        end if
        stream = edges[i]
        row.title = ""
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        rowItem.contentId = stream.node.id
        rowItem.contentType = "LIVE"
        rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", stream.node.broadcaster.login, "1280", "720")
        rowItem.contentTitle = stream.node.broadcaster.broadcastSettings.title
        rowItem.viewersCount = stream.node.viewersCount
        rowItem.streamerDisplayName = stream.node.broadcaster.displayName
        rowItem.streamerLogin = stream.node.broadcaster.login
        rowItem.streamerId = stream.node.broadcaster.id
        rowItem.streamerProfileImageUrl = stream.node.broadcaster.profileImageURL
        if stream.node.game <> invalid
            rowItem.gameDisplayName = stream.node.game.displayName
            rowItem.gameName = stream.node.game.name
            rowItem.gameId = stream.node.game.id
        end if
        row.appendChild(rowItem)
        if row.getChildCount() = itemsPerRow
            contentCollection.appendChild(row)
        end if
    end for
    if row <> invalid and row.getChildCount() > 0 and row.getChildCount() < itemsPerRow
        contentCollection.appendChild(row)
    end if
    return contentCollection
end function

sub handleRecommendedSections()
    rsp = m.GetContentTask.response
    if rsp = invalid
        m.top.buffer = false
        return
    end if

    contentCollection = buildContentNodeFromShelves(rsp.edges)
    if rsp.hasNextPage and rsp.cursor <> ""
        m.top.cursor = rsp.cursor
    else
        m.top.maxedOut = true
    end if
    updateRowList(contentCollection)

    m.top.buffer = false
end sub

sub appendMoreRows()
    if m.top.maxedOut = false
        m.GetContentTask = createApiTask("getBrowsePagePopularQuery", "handleRecommendedSections", { cursor: m.top.cursor })
    end if
end sub



sub updateRowList(content as object)
    if content = invalid or m.rowList = invalid
        return
    end if
    if m.rowList.content <> invalid
        while content.getChildCount() > 0
            m.rowList.content.appendChild(content.getChild(0))
        end while
    else
        m.rowList.content = content
    end if
    m.rowList.numRows = m.rowList.content.getChildCount()
    if m.rowList.content.getChildCount() > 0
        m.rowList.visible = true
    end if
end sub

sub handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
        m.rowlist.focusedChild.setFocus(true)
        if m.rowlist.rowItemFocused[0] <> invalid
            if m.rowlist.content.getChildCount() > 0
                if (m.rowlist.content.getChildCount() - m.rowlist.rowItemFocused[0]) < 5
                    if m.top.buffer = false
                        m.top.buffer = true
                        appendMoreRows()
                    end if
                end if
            end if
        end if
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

sub onDestroy()
    m.top.unobserveField("focusedChild")
    if m.rowlist <> invalid
        m.rowlist.unobserveField("itemSelected")
    end if
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
