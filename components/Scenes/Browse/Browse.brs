sub init()
    m.top.observeField("focusedChild", "onGetFocus")
    m.rowList = m.top.findNode("browseRowList")
    m.rowList.observeField("itemSelected", "onItemSelected")
    m.rowList.observeField("itemHasFocus", "onItemFocused")

    m.categoriesCursor = ""
    m.liveCursor = ""
    m.categoriesMaxed = false
    m.liveMaxed = false
    m.categoriesBuffering = false
    m.liveBuffering = false
    m.categoriesLabelSet = false
    m.liveLabelSet = false

    ' Fire all three API tasks in parallel — three sections of one scrollable list
    m.featuredTask = createApiTask("getHomePageQuery", "onFeaturedResponse")
    m.categoriesTask = createApiTask("getBrowsePageQuery", "onCategoriesResponse")
    m.liveTask = createApiTask("getBrowsePagePopularQuery", "onLiveResponse")
end sub

' ─── Featured section (shelves from getHomePageQuery) ────────────────────────

sub onFeaturedResponse()
    rsp = m.featuredTask.response
    if rsp = invalid then return
    if rsp.shelves = invalid or rsp.shelves.count() = 0 then return
    contentCollection = createObject("roSGNode", "ContentNode")
    for each shelf in rsp.shelves
        row = createObject("roSGNode", "ContentNode")
        row.title = shelf.title
        for each item in shelf.streams
            twitchContentNode = createObject("roSGNode", "TwitchContentNode")
            setTwitchContentFields(twitchContentNode, item)
            row.appendChild(twitchContentNode)
        end for
        if row.getChildCount() > 0
            contentCollection.appendChild(row)
        end if
    end for
    if contentCollection.getChildCount() > 0
        contentCollection.removeChildIndex(0)
    end if
    appendRows(contentCollection)
end sub

' ─── Categories section (games from getBrowsePageQuery) ──────────────────────

sub onCategoriesResponse()
    rsp = m.categoriesTask.response
    if rsp = invalid
        m.categoriesBuffering = false
        return
    end if
    if rsp.hasNextPage and rsp.cursor <> ""
        m.categoriesCursor = rsp.cursor
    else
        m.categoriesMaxed = true
    end if
    contentCollection = buildCategoryRows(rsp.games)
    if not m.categoriesLabelSet and contentCollection.getChildCount() > 0
        m.categoriesLabelSet = true
        contentCollection.getChild(0).title = tr("Categories")
    end if
    m.categoriesBuffering = false
    appendRows(contentCollection)
end sub

function buildCategoryRows(games as object) as object
    itemsPerRow = 5
    contentCollection = createObject("roSGNode", "ContentNode")
    if games = invalid or games.count() = 0
        return contentCollection
    end if
    row = createObject("roSGNode", "ContentNode")
    for i = 0 to (games.count() - 1) step 1
        try
            if i mod itemsPerRow = 0
                row = createObject("roSGNode", "ContentNode")
            end if
            row.title = ""
            rowItem = createObject("roSGNode", "TwitchContentNode")
            setTwitchContentFields(rowItem, games[i])
            row.appendChild(rowItem)
            if row.getChildCount() = itemsPerRow
                contentCollection.appendChild(row)
            end if
        catch e
            ? "[Browse] buildCategoryRows error at index "; i; ": "; e
        end try
    end for
    if row <> invalid and row.getChildCount() > 0 and row.getChildCount() < itemsPerRow
        contentCollection.appendChild(row)
    end if
    return contentCollection
end function

sub appendMoreCategories()
    if not m.categoriesMaxed and not m.categoriesBuffering
        m.categoriesBuffering = true
        m.categoriesTask = createApiTask("getBrowsePageQuery", "onCategoriesResponse", { cursor: m.categoriesCursor })
    end if
end sub

' ─── Live Channels section (streams from getBrowsePagePopularQuery) ───────────

sub onLiveResponse()
    rsp = m.liveTask.response
    if rsp = invalid
        m.liveBuffering = false
        return
    end if
    if rsp.hasNextPage and rsp.cursor <> ""
        m.liveCursor = rsp.cursor
    else
        m.liveMaxed = true
    end if
    contentCollection = buildLiveRows(rsp.streams)
    if not m.liveLabelSet and contentCollection.getChildCount() > 0
        m.liveLabelSet = true
        contentCollection.getChild(0).title = tr("Live Channels")
    end if
    m.liveBuffering = false
    appendRows(contentCollection)
end sub

function buildLiveRows(streams as object) as object
    itemsPerRow = 3
    contentCollection = createObject("roSGNode", "ContentNode")
    if streams = invalid or streams.count() = 0
        return contentCollection
    end if
    row = createObject("roSGNode", "ContentNode")
    for i = 0 to (streams.count() - 1) step 1
        try
            if i mod itemsPerRow = 0
                row = createObject("roSGNode", "ContentNode")
            end if
            row.title = ""
            rowItem = createObject("roSGNode", "TwitchContentNode")
            setTwitchContentFields(rowItem, streams[i])
            row.appendChild(rowItem)
            if row.getChildCount() = itemsPerRow
                contentCollection.appendChild(row)
            end if
        catch e
            ? "[Browse] buildLiveRows error at index "; i; ": "; e
        end try
    end for
    if row <> invalid and row.getChildCount() > 0 and row.getChildCount() < itemsPerRow
        contentCollection.appendChild(row)
    end if
    return contentCollection
end function

sub appendMoreLive()
    if not m.liveMaxed and not m.liveBuffering
        m.liveBuffering = true
        m.liveTask = createApiTask("getBrowsePagePopularQuery", "onLiveResponse", { cursor: m.liveCursor })
    end if
end sub

' ─── Append rows into the single RowList ─────────────────────────────────────

sub appendRows(contentCollection as object)
    if m.rowList = invalid or contentCollection = invalid then return
    if contentCollection.getChildCount() = 0 then return

    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        showRowLabel.push(hasRowLabel)
        firstChild = row.getChild(0)
        contentType = ""
        if firstChild <> invalid
            contentType = firstChild.contentType
        end if
        config = getRowConfig(contentType, hasRowLabel)
        if config <> invalid
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for

    if m.rowList.content <> invalid
        existingSizes = m.rowList.rowItemSize
        existingLabels = m.rowList.showRowLabel
        existingHeights = m.rowList.rowHeights
        existingSizes.append(rowItemSize)
        existingLabels.append(showRowLabel)
        existingHeights.append(rowHeights)
        while contentCollection.getChildCount() > 0
            m.rowList.content.appendChild(contentCollection.getChild(0))
        end while
        m.rowList.rowItemSize = existingSizes
        m.rowList.showRowLabel = existingLabels
        m.rowList.rowHeights = existingHeights
    else
        m.rowList.rowItemSize = rowItemSize
        m.rowList.showRowLabel = showRowLabel
        m.rowList.rowHeights = rowHeights
        m.rowList.content = contentCollection
    end if

    m.rowList.numRows = m.rowList.content.getChildCount()
    m.rowList.rowLabelColor = m.global.constants.colors.twitch.purple10
    m.rowList.visible = true
end sub

' ─── Selection ───────────────────────────────────────────────────────────────

sub onItemSelected()
    row = m.rowList.content.getChild(m.rowList.rowItemSelected[0])
    item = row.getChild(m.rowList.rowItemSelected[1])
    m.top.contentSelected = item
end sub

' ─── Pagination trigger ──────────────────────────────────────────────────────

sub onItemFocused()
    if m.rowList.rowItemFocused[0] = invalid then return
    rowsLeft = m.rowList.content.getChildCount() - m.rowList.rowItemFocused[0]
    if rowsLeft < 5
        appendMoreCategories()
        appendMoreLive()
    end if
end sub

' ─── Focus ───────────────────────────────────────────────────────────────────

sub onGetFocus()
    if m.rowList.focusedChild = invalid
        m.rowList.setFocus(true)
    else if m.top.focusedChild <> invalid and m.top.focusedChild.id = "browseRowList"
        m.rowList.focusedChild.setFocus(true)
    end if
end sub

' ─── Keys ────────────────────────────────────────────────────────────────────

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        if key = "up" or key = "back"
            m.top.backPressed = true
            return true
        end if
    end if
    return false
end function

' ─── Cleanup ─────────────────────────────────────────────────────────────────

sub onDestroy()
    m.top.unobserveField("focusedChild")
    if m.rowList <> invalid
        m.rowList.unobserveField("itemSelected")
        m.rowList.unobserveField("itemHasFocus")
    end if
    m.featuredTask = destroyTask(m.featuredTask, "response")
    m.categoriesTask = destroyTask(m.categoriesTask, "response")
    m.liveTask = destroyTask(m.liveTask, "response")
end sub
