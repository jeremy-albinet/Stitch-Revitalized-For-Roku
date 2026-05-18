sub init()
    m.top.observeField("focusedChild", "onGetFocus")
    m.rowList = m.top.findNode("browseRowList")
    ' Inner RowList handle for fields not exposed by TileRow
    ' (rowItemSelected, drawFocusFeedback).
    m.rowListInner = m.rowList.findNode("rowList")
    m.rowList.observeField("itemSelected", "onItemSelected")
    m.rowList.observeField("itemFocused", "onItemFocused")

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
    ' Live always appends at the tail (after Featured + Categories).
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
        m.liveTask = destroyTask(m.liveTask, "response")
        m.liveTask = createApiTask("getBrowsePagePopularQuery", "onLiveResponse", { cursor: m.liveCursor })
    end if
end sub

' ─── Append / insert rows into the TileRow's content ──────────────────────────
'
' TileRow handles tile dimensions, row heights, spacing, focus bitmap, and
' animation styles internally via design tokens — per-row size customization
' is no longer applied here.

' insertRows inserts contentCollection rows starting at the given index.
' Use this when section ordering must be enforced (Featured → Categories → Live).
sub insertRows(contentCollection as object, insertIndex as integer)
    if m.rowList = invalid or contentCollection = invalid then return
    rowCount = contentCollection.getChildCount()
    if rowCount = 0 then return

    if m.rowList.content = invalid
        m.rowList.content = createObject("roSGNode", "ContentNode")
    end if

    ' Insert child nodes at insertIndex (preserving order).
    while contentCollection.getChildCount() > 0
        child = contentCollection.getChild(0)
        contentCollection.removeChildIndex(0)
        m.rowList.content.insertChild(child, insertIndex + (rowCount - contentCollection.getChildCount() - 1))
    end while
end sub

sub appendRows(contentCollection as object)
    if m.rowList = invalid or contentCollection = invalid then return
    if contentCollection.getChildCount() = 0 then return

    if m.rowList.content <> invalid
        while contentCollection.getChildCount() > 0
            m.rowList.content.appendChild(contentCollection.getChild(0))
        end while
    else
        m.rowList.content = contentCollection
    end if
end sub

' ─── Selection ───────────────────────────────────────────────────────────────

sub onItemSelected()
    ' rowItemSelected is internal to RowList — access via TileRow's inner RowList handle
    if m.rowListInner = invalid or m.rowList.content = invalid then return
    rowItemSelected = m.rowListInner.rowItemSelected
    if rowItemSelected = invalid then return
    row = m.rowList.content.getChild(rowItemSelected[0])
    if row = invalid then return
    item = row.getChild(rowItemSelected[1])
    if item = invalid then return
    m.top.contentSelected = item
end sub

' ─── Pagination trigger ──────────────────────────────────────────────────────

sub onItemFocused()
    focusedRowIndex = m.rowList.itemFocused
    if focusedRowIndex = invalid or focusedRowIndex < 0 then return
    if m.rowList.content = invalid then return

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
    if m.rowList.focusedChild = invalid
        m.rowList.setFocus(true)
    else if m.top.focusedChild <> invalid and m.top.focusedChild.id = "browseRowList"
        m.rowList.focusedChild.setFocus(true)
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
' drawFocusFeedback is internal to RowList — access via TileRow's inner RowList handle.
sub updateRowListFocusFeedback()
    if m.rowListInner = invalid then return
    hasFocus = m.top.focusedChild <> invalid and m.top.focusedChild.id = "browseRowList"
    m.rowListInner.drawFocusFeedback = hasFocus
end sub

' ─── Keys ────────────────────────────────────────────────────────────────────

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ' Note: "up" is intentionally not consumed here — heroScene's focus
        ' contract routes Up cross-bar. Only "back" exits the scene.
        if key = "back"
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
        m.rowList.unobserveField("itemFocused")
    end if
    m.featuredTask = destroyTask(m.featuredTask, "response")
    m.categoriesTask = destroyTask(m.categoriesTask, "response")
    m.liveTask = destroyTask(m.liveTask, "response")
end sub
