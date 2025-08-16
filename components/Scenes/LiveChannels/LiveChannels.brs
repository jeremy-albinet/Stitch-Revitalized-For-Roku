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
    m.rowlist.observeField("itemHasFocus", "handleItemFocus")
    m.GetContentTask = CreateObject("roSGNode", "TwitchApiTask") ' create task for feed retrieving
    ' observe content so we can know when feed content will be parsed
    m.GetContentTask.observeField("response", "handleRecommendedSections")
    m.GetContentTask.request = {
        type: "getBrowsePagePopularQuery"
    }
    m.GetContentTask.functionName = m.GetContentTask.request.type
    m.GetContentTask.control = "run"
end sub

function buildContentNodeFromShelves(shelves as object) as object
    content = CreateObject("roSGNode", "ContentNode")
    if shelves <> invalid and type(shelves) = "roArray"
        for each shelf in shelves
            if shelf <> invalid and shelf.items <> invalid
                row = content.CreateChild("ContentNode")
                row.title = shelf.title
                for each item in shelf.items
                    if item <> invalid
                        ' Create node for each item
                        itemNode = row.CreateChild("ContentNode")
                        if itemNode <> invalid
                            itemNode.setFields(item)
                        end if
                    end if
                next
            end if
        next
    end if
    return content
end function

sub handleRecommendedSections()
    if m.GetContentTask?.response?.data?.streams <> invalid
        contentCollection = buildContentNodeFromShelves(m.GetContentTask.response.data.streams.edges)
        if m.GetContentTask.response.data.streams.pageInfo <> invalid
            if m.GetContentTask.response.data.streams.pageInfo.hasNextPage
                if m.GetContentTask.response.data.streams.edges.peek().cursor <> invalid
                    m.top.cursor = m.GetContentTask.response.data.streams.edges.peek().cursor
                end if
            else
                m.top.maxedOut = true
            end if
        end if
        updateRowList(contentCollection)
    else
        for each error in m.GetContentTask.response.errors
            ' ? "RESP: "; error.message
        end for
    end if
    m.top.buffer = false
end sub

sub appendMoreRows()
    if m.top.maxedOut = false
        m.GetContentTask = CreateObject("roSGNode", "TwitchApiTask") ' create task for feed retrieving
        ' observe content so we can know when feed content will be parsed
        m.GetContentTask.observeField("response", "handleRecommendedSections")
        m.GetContentTask.request = {
            type: "getBrowsePagePopularQuery",
            cursor: m.top.cursor
        }
        m.GetContentTask.functionName = m.GetContentTask.request.type
        m.GetContentTask.control = "run"
    end if
end sub

function buildRowData(contentCollection)
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    ? "Cat CC: "; contentCollection
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        if row.title <> ""
            hasRowLabel = true
        else
            hasRowLabel = false
        end if
        showRowLabel.push(hasRowLabel)
        if row.getchild(0).contentType = "LIVE" or row.getchild(0).contentType = "VOD"
            rowItemSize.push([320, 180])
            if hasRowLabel
                rowHeights.push(275)
            else
                rowHeights.push(235)
            end if
        end if
        if row.getchild(0).contentType = "GAME"
            rowItemSize.push([188, 250])
            if hasRowLabel
                rowHeights.push(325)
            else
                rowHeights.push(305)
            end if
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

sub updateRowList(content as object)
    if content <> invalid and m.rowList <> invalid
        m.rowList.content = content

        if m.rowList.content <> invalid and m.rowList.content.getChildCount() > 0
            m.rowList.visible = true
        end if
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
    else if m.top.focusedChild.id = "homeRowList"
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
