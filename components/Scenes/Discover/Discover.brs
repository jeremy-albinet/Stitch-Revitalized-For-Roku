sub init()
    ? "init: "; TimeStamp()
    m.top.observeField("focusedChild", "onGetfocus")
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.GetContentTask = createApiTask("getHomePageQuery", "handleRecommendedSections")
end sub

sub handleRecommendedSections()
    ? "handleRecommendedSections: "; TimeStamp()
    rsp = m.GetContentTask.response
    if rsp = invalid then return
    if rsp.shelves <> invalid and rsp.shelves.count() > 0
        updateRowList(rsp.shelves)
    else
        for each error in rsp.errors
            ? "RESP: "; error.message
        end for
    end if
end sub

' function createRowList()
'     newRowList = createObject("RoSGNode", "RowList")
'     newRowList.rowLabelOffset = "[[0,5]]"
'     newRowList.rowLabelFont = "font:LargeBoldSystemFont"
'     newRowList.itemComponentName = "VideoItem"
'     newRowList.numRows = 1
'     newRowList.rowItemSize = "[[320,180]]"
'     newRowList.rowItemSpacing = "[[30,0]]"
'     newRowList.itemSize = "[1080,275]"
'     newRowList.itemSpacing = "[ 0, 40 ]"
'     newRowList.showRowLabel = "[true]"
'     newRowList.focusBitmapUri = "pkg:/images/focusindicator.9.png"
'     newRowList.vertFocusAnimationStyle = "fixedFocus"
'     newRowList.rowFocusAnimationStyle = "fixedFocusWrap"
'     return newRowList
' end function

sub updateRowList(shelves)
    ? "updateRowList: "; TimeStamp()
    contentCollection = createObject("roSGNode", "ContentNode")
    if shelves <> invalid
        for each shelf in shelves
            row = createObject("roSGNode", "ContentNode")
            row.title = shelf.title
            for each item in shelf.streams
                twitchContentNode = createObject("roSGNode", "TwitchContentNode")
                setTwitchContentFields(twitchContentNode, item)
                row.appendChild(twitchContentNode)
            end for
            contentCollection.appendChild(row)
        end for
        contentCollection.removeChildIndex(0)
    end if
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        showRowLabel.push(hasRowLabel)
        config = getRowConfig(row.getchild(0).contentType, hasRowLabel)
        if config <> invalid
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for
    m.rowlist.visible = false
    m.rowList.rowHeights = rowHeights
    m.rowlist.showRowLabel = showRowLabel
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.content = contentCollection
    m.rowlist.numRows = contentCollection.getChildCount()
    m.rowlist.rowlabelcolor = m.global.constants.colors.twitch.purple10
    m.rowlist.visible = true
end sub

sub handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    ? "Selected: "; selectedItem
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

sub onDestroy()
    m.top.unobserveField("focusedChild")
    if m.rowlist <> invalid
        m.rowlist.unobserveField("itemSelected")
    end if
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
