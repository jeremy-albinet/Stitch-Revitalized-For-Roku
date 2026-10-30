sub init()
    m.disposed = false
    m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    m.top.observeField("focusedChild", "onGetfocus")
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    initPageStatus()
end sub

sub updatePage()
    m.top.pageTitle = m.top.contentRequested.gameName
    showCategoryHeader(m.top.contentRequested)
    loadDirectory()
end sub

' Box art and viewer count come from the category tile that opened the page.
sub showCategoryHeader(content as dynamic)
    if content = invalid then return
    boxArt = m.top.findNode("boxArt")
    viewers = m.top.findNode("viewers")
    header = m.top.findNode("Header")
    title = content.gameDisplayName
    if title = invalid or title = "" then title = content.gameName
    if header <> invalid and title <> invalid then header.text = title
    if boxArt <> invalid and content.gameBoxArtUrl <> invalid then boxArt.uri = content.gameBoxArtUrl
    if viewers <> invalid
        text = ""
        if content.viewersCount <> invalid and content.viewersCount > 0 then text = content.viewersDisplay
        viewers.text = text
    end if
end sub

' One finite request on open or explicit Try again.
sub loadDirectory()
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    setPageStatus("loading", tr("Loading live channels…"))
    m.GetContentTask = createApiTask("getGameDirectoryQuery", "handleRecommendedSections", {
        params: { gameAlias: m.top.contentRequested.gameName }
    })
end sub

sub onStatusAction(actionId as string)
    if actionId = "retry"
        loadDirectory()
    else if actionId = "back"
        m.top.backPressed = true
    end if
end sub

' Returns card fields for each well-formed directory edge. Malformed edges are
' skipped before grouping so they cannot shift or drop the remaining streams.
function buildGameStreamItems(streams as dynamic) as object
    items = []
    if type(streams) <> "roArray" then return items
    for each stream in streams
        node = invalid
        broadcaster = invalid
        if type(stream) = "roAssociativeArray" then node = stream.node
        if type(node) = "roAssociativeArray" then broadcaster = node.broadcaster
        login = invalid
        if type(broadcaster) = "roAssociativeArray" then login = broadcaster.login
        if GetInterface(login, "ifString") <> invalid and login <> ""
            title = invalid
            if type(broadcaster.broadcastSettings) = "roAssociativeArray" then title = broadcaster.broadcastSettings.title
            items.push({
                contentId: node.id,
                contentType: "LIVE",
                previewImageURL: Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", login, "1280", "720"),
                contentTitle: title,
                viewersCount: node.viewersCount,
                streamerDisplayName: broadcaster.displayName,
                streamerLogin: login,
                streamerId: broadcaster.id,
                streamerProfileImageUrl: broadcaster.profileImageURL
            })
        end if
    end for
    return items
end function

function buildContentNodeFromShelves(streams)
    contentCollection = createObject("RoSGNode", "ContentNode")
    tile = getStreamTile()
    for each rowItems in chunkItems(buildGameStreamItems(streams), tile.perRow)
        row = createObject("RoSGNode", "ContentNode")
        row.title = ""
        for each fields in rowItems
            rowItem = createObject("RoSGNode", "TwitchContentNode")
            setTwitchContentFields(rowItem, fields)
            row.appendChild(rowItem)
        end for
        contentCollection.appendChild(row)
    end for
    return contentCollection
end function


sub updateRowList(contentCollection)
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
    m.rowList.rowHeights = rowHeights
    m.rowlist.showRowLabel = showRowLabel
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.content = contentCollection
    m.rowlist.numRows = contentCollection.getChildCount()
end sub


sub handleRecommendedSections()
    if m.disposed or m.GetContentTask = invalid then return
    rsp = m.GetContentTask.response
    if rsp = invalid
        setPageStatus("error", tr("Couldn't load this category"), tr("Check your internet connection and try again."), ["retry", "back"])
        return
    end if
    contentCollection = buildContentNodeFromShelves(rsp.edges)
    if contentCollection.getChildCount() = 0
        gameName = m.top.contentRequested.gameName
        if gameName = invalid then gameName = ""
        setPageStatus("empty", Substitute(tr("No live channels in {0} right now."), gameName), "", ["back"])
        return
    end if
    updateRowList(contentCollection)
    hidePageStatus()
end sub

sub handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.disposed then return
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

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
sub updateRowListFocusFeedback()
    if m.rowlist = invalid then return
    m.rowlist.drawFocusFeedback = m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ? "Home Scene Key Event: "; key
        if key = "back"
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
    m.rowlist.unobserveField("itemSelected")
    releasePageStatus()
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
