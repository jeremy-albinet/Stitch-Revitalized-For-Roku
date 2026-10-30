sub init()
    m.disposed = false
    m.top.observeField("focusedChild", "onGetFocus")
    m.rowList = m.top.findNode("browseRowList")
    m.rowList.observeField("itemSelected", "onItemSelected")
    m.rowList.observeField("rowItemFocused", "onItemFocused")
    initPageStatus()
    loadBrowse()
end sub

' Starts one finite request per section, on page load or explicit Try again.
sub loadBrowse()
    m.featuredTask = destroyTask(m.featuredTask, "response")
    m.categoriesTask = destroyTask(m.categoriesTask, "response")
    m.liveTask = destroyTask(m.liveTask, "response")
    m.categoriesCursor = ""
    m.liveCursor = ""
    m.categoriesMaxed = false
    m.liveMaxed = false
    m.categoriesBuffering = false
    m.liveBuffering = false
    m.categoriesLabelSet = false
    m.liveLabelSet = false

    ' Section insertion tracking — ensures Featured → Categories → Live order
    ' regardless of which API task returns first.
    ' -1 = section not yet placed; >= 0 = index of first row in that section.
    m.featuredEndIndex = -1
    m.categoriesEndIndex = -1

    ' Page status follows each section's first response only; pagination
    ' failures keep the rows already shown.
    m.sectionSettled = { featured: false, categories: false, live: false }
    m.sectionsFailed = 0
    setPageStatus("loading", tr("Loading channels and categories…"))

    ' Fire all three API tasks in parallel — three sections of one scrollable list
    m.featuredTask = createApiTask("getHomePageQuery", "onFeaturedResponse", { requireShelves: true })
    m.categoriesTask = createApiTask("getBrowsePageQuery", "onCategoriesResponse")
    m.liveTask = createApiTask("getBrowsePagePopularQuery", "onLiveResponse")
end sub

' ─── Featured section (shelves from getHomePageQuery) ────────────────────────

sub onFeaturedResponse()
    if m.disposed or m.featuredTask = invalid then return
    rsp = m.featuredTask.response
    if rsp = invalid
        settleSection("featured", false)
        return
    end if
    if rsp.shelves = invalid or rsp.shelves.count() = 0
        settleSection("featured", true)
        return
    end if
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
    ' Featured always inserts at position 0.
    ' If Categories already landed while Featured was pending, shift its tracked
    ' end index down by the number of Featured rows now inserted before it.
    featuredRowCount = contentCollection.getChildCount()
    insertRows(contentCollection, 0)
    m.featuredEndIndex = featuredRowCount
    if featuredRowCount > 0 and m.categoriesEndIndex >= 0
        m.categoriesEndIndex = m.categoriesEndIndex + featuredRowCount
    end if
    settleSection("featured", true)
end sub

' ─── Categories section (games from getBrowsePageQuery) ──────────────────────

sub onCategoriesResponse()
    if m.disposed or m.categoriesTask = invalid then return
    rsp = m.categoriesTask.response
    if rsp = invalid
        m.categoriesBuffering = false
        settleSection("categories", false)
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
    ' Categories always follow Featured. If Featured hasn't arrived yet, insert at 0;
    ' subsequent pages append after existing Categories rows (tracked by m.categoriesEndIndex).
    categoriesRowCount = contentCollection.getChildCount()
    if m.categoriesEndIndex < 0
        insertAt = m.featuredEndIndex
        if insertAt < 0 then insertAt = 0
        insertRows(contentCollection, insertAt)
        m.categoriesEndIndex = insertAt + categoriesRowCount
        ' If Featured hasn't arrived yet, update its placeholder so it inserts before us
        if m.featuredEndIndex < 0
            m.featuredEndIndex = 0
        end if
    else
        insertRows(contentCollection, m.categoriesEndIndex)
        m.categoriesEndIndex = m.categoriesEndIndex + categoriesRowCount
    end if
    settleSection("categories", true)
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
        m.categoriesTask = destroyTask(m.categoriesTask, "response")
        m.categoriesTask = createApiTask("getBrowsePageQuery", "onCategoriesResponse", { cursor: m.categoriesCursor })
    end if
end sub

' ─── Live Channels section (streams from getBrowsePagePopularQuery) ───────────

sub onLiveResponse()
    if m.disposed or m.liveTask = invalid then return
    rsp = m.liveTask.response
    if rsp = invalid
        m.liveBuffering = false
        settleSection("live", false)
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
    ' Live always appends at the tail (after Featured + Categories).
    appendRows(contentCollection)
    settleSection("live", true)
end sub

' ─── Page status ─────────────────────────────────────────────────────────────

' Records a section's first response. Later pages of the same section are
' pagination and never change the page status.
sub settleSection(section as string, succeeded as boolean)
    if m.sectionSettled[section] = true then return
    m.sectionSettled[section] = true
    if not succeeded then m.sectionsFailed += 1
    updateBrowseStatus()
end sub

' Any loaded section hides the panel, so partial failures keep what loaded.
' With nothing loaded, a failure offers Try again; responses that all
' succeeded without content show the empty message.
sub updateBrowseStatus()
    if m.rowList.content <> invalid and m.rowList.content.getChildCount() > 0
        hidePageStatus()
        return
    end if
    for each section in m.sectionSettled
        if not m.sectionSettled[section] then return
    end for
    if m.sectionsFailed > 0
        setPageStatus("error", tr("Couldn't load Browse"), tr("Check your internet connection and try again."), ["retry"])
    else
        setPageStatus("empty", tr("Nothing to browse right now"), tr("Twitch didn't return any channels or categories. Try again in a moment."), ["retry"])
    end if
end sub

sub onStatusAction(actionId as string)
    if actionId = "retry" then loadBrowse()
end sub

function buildLiveRows(streams as object) as object
    itemsPerRow = getStreamTile().perRow
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
        m.liveTask = destroyTask(m.liveTask, "response")
        m.liveTask = createApiTask("getBrowsePagePopularQuery", "onLiveResponse", { cursor: m.liveCursor })
    end if
end sub

' ─── Append / insert rows into the single RowList ───────────────────────────

' insertRows inserts contentCollection rows starting at the given index.
' Use this when section ordering must be enforced (Featured → Categories → Live).
sub insertRows(contentCollection as object, insertIndex as integer)
    if m.rowList = invalid or contentCollection = invalid then return
    rowCount = contentCollection.getChildCount()
    if rowCount = 0 then return

    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(rowCount, 0)
        hasRowLabel = row.title <> ""
        showRowLabel.push(hasRowLabel)
        firstChild = row.getChild(0)
        contentType = ""
        if firstChild <> invalid
            contentType = firstChild.contentType
        end if
        config = getRowConfig(contentType, hasRowLabel, true)
        if config <> invalid
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for

    if m.rowList.content = invalid
        content = createObject("roSGNode", "ContentNode")
        m.rowList.content = content
    end if

    ' RowList fields may be invalid (not yet assigned) — treat as empty arrays
    existingSizes = m.rowList.rowItemSize
    existingLabels = m.rowList.showRowLabel
    existingHeights = m.rowList.rowHeights
    if existingSizes = invalid then existingSizes = []
    if existingLabels = invalid then existingLabels = []
    if existingHeights = invalid then existingHeights = []

    ' Splice arrays at insertIndex
    newSizes = []
    newLabels = []
    newHeights = []
    existingCount = existingSizes.count()
    for i = 0 to existingCount - 1
        if i = insertIndex
            newSizes.append(rowItemSize)
            newLabels.append(showRowLabel)
            newHeights.append(rowHeights)
        end if
        newSizes.push(existingSizes[i])
        newLabels.push(existingLabels[i])
        newHeights.push(existingHeights[i])
    end for
    if insertIndex >= existingCount
        newSizes.append(rowItemSize)
        newLabels.append(showRowLabel)
        newHeights.append(rowHeights)
    end if

    ' Insert child nodes at insertIndex
    while contentCollection.getChildCount() > 0
        child = contentCollection.getChild(0)
        contentCollection.removeChildIndex(0)
        m.rowList.content.insertChild(child, insertIndex + (rowCount - contentCollection.getChildCount() - 1))
    end while

    m.rowList.rowItemSize = newSizes
    m.rowList.showRowLabel = newLabels
    m.rowList.rowHeights = newHeights
    m.rowList.numRows = m.rowList.content.getChildCount()
    m.rowList.rowLabelColor = m.global.constants.ui.color.text
    m.rowList.visible = true
end sub

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
        config = getRowConfig(contentType, hasRowLabel, true)
        if config <> invalid
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for

    if m.rowList.content <> invalid
        ' SceneGraph field arrays are non-resizable on Roku; append to copies.
        existingSizes = []
        existingLabels = []
        existingHeights = []
        existingSizes.append(m.rowList.rowItemSize)
        existingLabels.append(m.rowList.showRowLabel)
        existingHeights.append(m.rowList.rowHeights)
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
    m.rowList.rowLabelColor = m.global.constants.ui.color.text
    m.rowList.visible = true
end sub

' ─── Selection ───────────────────────────────────────────────────────────────

sub onItemSelected()
    row = m.rowList.content.getChild(m.rowList.rowItemSelected[0])
    if row = invalid then return
    item = row.getChild(m.rowList.rowItemSelected[1])
    if item = invalid then return
    m.top.contentSelected = item
end sub

' ─── Pagination trigger ──────────────────────────────────────────────────────

sub onItemFocused()
    focusedRowIndex = m.rowList.rowItemFocused[0]
    if focusedRowIndex = invalid then return

    ' Paginate Categories only when focus is near the end of the Categories section,
    ' not whenever focus is near the bottom of the whole list.
    if m.categoriesEndIndex >= 0
        categoriesRowsLeft = m.categoriesEndIndex - focusedRowIndex
        if categoriesRowsLeft >= 0 and categoriesRowsLeft < 5
            appendMoreCategories()
        end if
    end if

    ' Paginate Live only when focus is in or near the Live section tail.
    liveStartIndex = 0
    if m.categoriesEndIndex >= 0
        liveStartIndex = m.categoriesEndIndex
    else if m.featuredEndIndex >= 0
        liveStartIndex = m.featuredEndIndex
    end if
    totalRows = m.rowList.content.getChildCount()
    if focusedRowIndex >= liveStartIndex and (totalRows - focusedRowIndex) < 5
        appendMoreLive()
    end if
end sub

' ─── Focus ───────────────────────────────────────────────────────────────────

sub onGetFocus()
    if m.disposed then return
    ' While the status panel offers actions, it holds page focus.
    if not focusStatusIfActive()
        if m.rowList.focusedChild = invalid
            m.rowList.setFocus(true)
        else if m.top.focusedChild <> invalid and m.top.focusedChild.id = "browseRowList"
            m.rowList.focusedChild.setFocus(true)
        end if
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
sub updateRowListFocusFeedback()
    if m.rowList = invalid then return
    hasFocus = m.top.focusedChild <> invalid and m.top.focusedChild.id = "browseRowList"
    m.rowList.drawFocusFeedback = hasFocus
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
    if m.disposed then return
    m.disposed = true
    m.top.lastFocus = invalid
    m.top.unobserveField("focusedChild")
    if m.rowList <> invalid
        m.rowList.unobserveField("itemSelected")
        m.rowList.unobserveField("rowItemFocused")
    end if
    releasePageStatus()
    m.featuredTask = destroyTask(m.featuredTask, "response")
    m.categoriesTask = destroyTask(m.categoriesTask, "response")
    m.liveTask = destroyTask(m.liveTask, "response")
end sub
