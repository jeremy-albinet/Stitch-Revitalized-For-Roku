sub init()
    m.top.observeField("focusedChild", "onGetfocus")
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.rowlist.observeField("itemHasFocus", "handleItemFocus")
    m.GetContentTask = createApiTask("getBrowsePageQuery", "handleRecommendedSections")
end sub

function buildContentNodeFromShelves(games)
    contentCollection = createObject("RoSGNode", "ContentNode")
    row = createObject("RoSGNode", "ContentNode")
    for i = 0 to (games.count() - 1) step 1
        if i mod 5 = 0
            row = createObject("RoSGNode", "ContentNode")
        end if
        row.title = ""
        game = games[i]
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        rowItem.contentId = game.node.Id
        rowItem.contentType = "GAME"
        rowItem.viewersCount = game.node.viewersCount
        rowItem.contentTitle = game.node.displayName
        rowItem.gameDisplayName = game.node.displayName
        rowItem.gameBoxArtUrl = Left(game.node.avatarUrl, Len(game.node.avatarUrl) - 11) + "188x250.jpg"
        rowItem.gameId = game.node.Id
        rowItem.gameName = game.node.name

        rowItem.Title = game.node.displayName
        rowItem.secondaryTitle = game.node.viewersCount
        rowItem.HDPosterUrl = Left(game.node.avatarUrl, Len(game.node.avatarUrl) - 11) + "188x250.jpg"
        rowItem.ShortDescriptionLine1 = game.node.viewersCount
        row.appendChild(rowItem)
        if row.getChildCount() = 5
            contentCollection.appendChild(row)
        end if
    end for
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
        m.GetContentTask = createApiTask("getBrowsePageQuery", "handleRecommendedSections", { cursor: m.top.cursor })
    end if
end sub

function buildRowData(contentCollection)
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    ? "Cat CC: "; contentCollection
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        showRowLabel.push(hasRowLabel)
        config = getRowConfig(row.getchild(0).contentType, hasRowLabel)
        if config <> invalid
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for
    return {
        rowHeights: rowHeights,
        showRowLabel: showRowLabel,
        rowItemSize: rowItemSize,
        content: contentCollection,
        numRows: contentCollection.getChildCount()
    }
end function

sub updateRowList(contentCollection)
    rowData = buildRowData(contentCollection)
    if m.rowlist.content <> invalid
        for i = 0 to (rowData.content.getChildCount() - 1) step 1
            m.rowlist.content.appendChild(rowData.content.getchild(i))
        end for
    else
        m.rowlist.content = rowData.content
    end if
    m.rowlist.numRows = m.rowlist.content.getChildCount()
end sub

sub handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.rowlist.focusedchild.id = "homeRowList"
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
        m.rowlist.unobserveField("itemHasFocus")
    end if
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
