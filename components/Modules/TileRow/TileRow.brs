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

    ' Focus scale animation (gated by memory)
    m.lowRamDevice = CreateObject("roDeviceInfo").GetMemoryLimit() < 30
    m.prevFocusedItem = invalid

    if not m.lowRamDevice
        m.focusScaleUpAnim = CreateObject("roSGNode", "Animation")
        m.focusScaleUpAnim.duration = c.focus.duration
        m.focusScaleUpAnim.easeFunction = "easeOut"
        m.focusScaleUpInterp = CreateObject("roSGNode", "Vector2DFieldInterpolator")
        m.focusScaleUpInterp.fieldToInterpolate = "scale"
        m.focusScaleUpInterp.keyValue = [[1.0, 1.0], [c.focus.scale, c.focus.scale]]
        m.focusScaleUpAnim.appendChild(m.focusScaleUpInterp)
        m.top.appendChild(m.focusScaleUpAnim)

        m.focusScaleDownAnim = CreateObject("roSGNode", "Animation")
        m.focusScaleDownAnim.duration = c.focus.duration
        m.focusScaleDownAnim.easeFunction = "easeIn"
        m.focusScaleDownInterp = CreateObject("roSGNode", "Vector2DFieldInterpolator")
        m.focusScaleDownInterp.fieldToInterpolate = "scale"
        m.focusScaleDownInterp.keyValue = [[c.focus.scale, c.focus.scale], [1.0, 1.0]]
        m.focusScaleDownAnim.appendChild(m.focusScaleDownInterp)
        m.top.appendChild(m.focusScaleDownAnim)
    end if
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

    if m.lowMem then return

    ' Find the currently focused item component
    focusedItem = findFocusedItem(m.rowList)

    ' Animate previous item back to normal scale
    if m.prevFocusedItem <> invalid and m.prevFocusedItem <> focusedItem
        m.prevFocusedItem.id = "focusScaleDownTarget"
        m.focusScaleDownInterp.fieldToInterp = "focusScaleDownTarget.scale"
        m.focusScaleDownAnim.control = "start"
    end if

    ' Animate new item to focused scale
    if focusedItem <> invalid
        focusedItem.scaleRotateCenter = [m.global.constants.tile.w / 2, m.global.constants.tile.h / 2]
        focusedItem.id = "focusScaleUpTarget"
        m.focusScaleUpInterp.fieldToInterp = "focusScaleUpTarget.scale"
        m.focusScaleUpAnim.control = "start"
        m.prevFocusedItem = focusedItem
    end if
end sub

sub onRowListItemSelected()
    m.top.itemSelected = m.rowList.itemSelected
end sub

' Recursively find the item component with itemHasFocus = true
function findFocusedItem(node as object) as object
    if node = invalid then return invalid
    if node.hasField("itemHasFocus") and node.itemHasFocus = true
        return node
    end if
    for i = 0 to node.getChildCount() - 1
        child = node.getChild(i)
        result = findFocusedItem(child)
        if result <> invalid then return result
    end for
    return invalid
end function

sub onDestroy()
    if m.rowList <> invalid
        m.rowList.unobserveField("itemFocused")
        m.rowList.unobserveField("itemSelected")
    end if
    if not m.lowMem
        if m.focusScaleUpAnim <> invalid
            m.focusScaleUpAnim.control = "stop"
        end if
        if m.focusScaleDownAnim <> invalid
            m.focusScaleDownAnim.control = "stop"
        end if
    end if
end sub