sub init()
    m.top.observeField("focusedChild", "onGetFocus")
    m.rowList = m.top.findNode("browseRowList")
    m.rowList.observeField("itemSelected", "onItemSelected")
    m.rowList.observeField("rowItemFocused", "onItemFocused")

    m.categoriesCursor = ""
    m.categoriesMaxed = false
    m.categoriesBuffering = false
    m.categoriesLabelSet = false

    ' Section insertion tracking — ensures Featured → Categories order
    ' regardless of which API task returns first.
    ' -1 = section not yet placed; >= 0 = index of first row in that section.
    m.featuredEndIndex = -1
    m.categoriesEndIndex = -1

    ' Fire both API tasks in parallel — two sections of one scrollable list
    m.featuredTask = createApiTask("getHomePageQuery", "onFeaturedResponse")
    m.categoriesTask = createApiTask("getBrowsePageQuery", "onCategoriesResponse")
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
    ' Featured always inserts at position 0.
    ' If Categories already landed while Featured was pending, shift its tracked
    ' end index down by the number of Featured rows now inserted before it.
    featuredRowCount = contentCollection.getChildCount()
    insertRows(contentCollection, 0)
    m.featuredEndIndex = featuredRowCount
    if featuredRowCount > 0 and m.categoriesEndIndex >= 0
        m.categoriesEndIndex = m.categoriesEndIndex + featuredRowCount
    end if
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
end sub

function buildCategoryRows(games as object) as object
    itemsPerRow = 8
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

' ─── Append / insert rows into the single RowList ───────────────────────────

' insertRows inserts contentCollection rows starting at the given index.
' Use this when section ordering must be enforced (Featured → Categories).
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
        config = getRowConfig(contentType, hasRowLabel)
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
    m.rowList.rowLabelColor = m.global.constants.colors.twitch.purple10
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
end sub

' ─── Focus ───────────────────────────────────────────────────────────────────

sub onGetFocus()
    if m.rowList.focusedChild = invalid
        m.rowList.setFocus(true)
    else if m.top.focusedChild <> invalid and m.top.focusedChild.id = "browseRowList"
        m.rowList.focusedChild.setFocus(true)
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
    m.top.unobserveField("focusedChild")
    if m.rowList <> invalid
        m.rowList.unobserveField("itemSelected")
        m.rowList.unobserveField("rowItemFocused")
    end if
    m.featuredTask = destroyTask(m.featuredTask, "response")
    m.categoriesTask = destroyTask(m.categoriesTask, "response")
end sub
