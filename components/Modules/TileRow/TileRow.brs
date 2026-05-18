sub init()
    m.rowList = m.top.findNode("rowList")

    c = m.global.constants

    ' Focus bitmap from design tokens
    m.rowList.focusBitmapUri = c.focus.bitmapUri

    ' Tile dimensions and spacing
    m.rowList.rowItemSize = [[c.tile.w, c.tile.h]]
    m.rowList.rowItemSpacing = [[c.tile.gap, c.tile.gap]]

    ' Row layout
    m.rowList.itemSize = [c.screenWidth, c.row.h]
    m.rowList.rowLabelOffset = [[c.row.labelOffset[0], c.row.labelOffset[1]]]

    ' Focus animation style
    m.rowList.vertFocusAnimationStyle = "fixedFocus"
    m.rowList.rowFocusAnimationStyle = "floatingFocus"

    ' Default item component (settable via interface field)
    m.rowList.itemComponentName = m.top.itemComponentName

    ' Observe internal RowList events to re-emit on m.top
    m.rowList.observeField("itemFocused", "onRowListItemFocused")
    m.rowList.observeField("itemSelected", "onRowListItemSelected")
end sub

sub onContentChange()
    if m.rowList <> invalid
        m.rowList.content = m.top.content
    end if
end sub

sub onItemComponentNameChange()
    if m.rowList <> invalid
        m.rowList.itemComponentName = m.top.itemComponentName
    end if
end sub

sub onJumpToItemChange()
    if m.rowList <> invalid
        m.rowList.jumpToItem = m.top.jumpToItem
    end if
end sub

sub onRowListItemFocused()
    m.top.itemFocused = m.rowList.itemFocused
end sub

sub onRowListItemSelected()
    m.top.itemSelected = m.rowList.itemSelected
end sub

sub onDestroy()
    if m.rowList <> invalid
        m.rowList.unobserveField("itemFocused")
        m.rowList.unobserveField("itemSelected")
    end if
end sub