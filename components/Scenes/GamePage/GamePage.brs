sub init()
    m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    m.top.observeField("focusedChild", "onGetfocus")
    m.tileRow = m.top.findNode("homeRowList")
    m.rowList = m.tileRow.findNode("rowList")
    m.tileRow.observeField("itemSelected", "handleItemSelected")
end sub

sub updatePage()
    m.top.pageTitle = m.top.contentRequested.gameName
    m.GetContentTask = createApiTask("getGameDirectoryQuery", "handleRecommendedSections", {
        params: { gameAlias: m.top.contentRequested.gameName }
    })
end sub

function buildContentNodeFromShelves(streams)
    itemsPerRow = 3
    contentCollection = createObject("RoSGNode", "ContentNode")
    row = createObject("RoSGNode", "ContentNode")
    for i = 0 to (streams.count() - 1) step 1
        if i mod itemsPerRow = 0
            row = createObject("RoSGNode", "ContentNode")
        end if
        stream = streams[i]
        if stream = invalid or stream.node = invalid then continue for
        row.title = ""
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        rowItem.contentId = stream.node.Id
        rowItem.contentType = "LIVE"
        rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", stream.node.broadcaster.login, "1920", "1080")
        rowItem.contentTitle = stream.node.broadcaster.broadcastSettings.title
        rowItem.viewersCount = stream.node.viewersCount
        rowItem.streamerDisplayName = stream.node.broadcaster.displayName
        rowItem.streamerLogin = stream.node.broadcaster.login
        rowItem.streamerId = stream.node.broadcaster.id
        rowItem.streamerProfileImageUrl = stream.node.broadcaster.profileImageURL
        ' rowItem.gameDisplayName = stream.node.game.displayName
        ' rowItem.Title = stream.node.broadcaster.broadcastsettings.title
        ' rowItem.secondaryTitle = stream.node.broadcaster.displayName
        ' rowItem.ShortDescriptionLine1 = stream.node.viewersCount
        ' rowItem.ShortDescriptionLine2 = stream.node.game.displayName
        row.appendChild(rowItem)
        if row.getChildCount() = itemsPerRow
            contentCollection.appendChild(row)
        end if
    end for
    return contentCollection
end function


sub updateRowList(contentCollection)
    m.tileRow.content = contentCollection
end sub


sub handleRecommendedSections()
    rsp = m.GetContentTask.response
    if rsp = invalid then return
    contentCollection = buildContentNodeFromShelves(rsp.edges)
    updateRowList(contentCollection)
end sub

sub handleItemSelected()
    selectedRow = m.tileRow.content.getchild(m.rowList.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowList.rowItemSelected[1])
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.tileRow.focusedChild = invalid
        m.rowList.setFocus(true)
    else if m.tileRow.focusedChild.id = "rowList"
        m.tileRow.focusedChild.setFocus(true)
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
sub updateRowListFocusFeedback()
    if m.rowList = invalid then return
    m.rowList.drawFocusFeedback = m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
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
