sub init()
    m.grid = m.top.findNode("grid")

    c = m.global.constants

    numColumns = int((c.screenWidth - 2 * c.spacing.xl) / (c.tile.w + c.tile.gap))

    m.grid.focusBitmapUri = c.focus.bitmapUri
    m.grid.itemSize = [c.tile.w, c.tile.h]
    m.grid.itemSpacing = [c.tile.gap, c.tile.gap]
    m.grid.numColumns = numColumns
    m.grid.itemComponentName = m.top.itemComponentName

    m.grid.observeField("itemFocused", "onGridItemFocused")
    m.grid.observeField("itemSelected", "onGridItemSelected")

    ' Low-RAM gate for visual polish
    m.lowMem = CreateObject("roDeviceInfo").GetMemoryLimit() < 30

    ' Focus scale animation (gated by low-RAM check)
    if not m.lowMem
        m.focusScaleUpAnim = CreateObject("roSGNode", "Animation")
        m.focusScaleUpInterp = CreateObject("roSGNode", "Vector2DFieldInterpolator")
        m.focusScaleUpInterp.keyField = "time"
        m.focusScaleUpInterp.keyValue = [[1.0, 1.0], [c.focus.scale, c.focus.scale]]
        m.focusScaleUpAnim.duration = c.focus.duration
        m.focusScaleUpAnim.AddInterpolator(m.focusScaleUpInterp)
        m.top.appendChild(m.focusScaleUpAnim)

        m.focusScaleDownAnim = CreateObject("roSGNode", "Animation")
        m.focusScaleDownInterp = CreateObject("roSGNode", "Vector2DFieldInterpolator")
        m.focusScaleDownInterp.keyField = "time"
        m.focusScaleDownInterp.keyValue = [[c.focus.scale, c.focus.scale], [1.0, 1.0]]
        m.focusScaleDownAnim.duration = c.focus.duration
        m.focusScaleDownAnim.AddInterpolator(m.focusScaleDownInterp)
        m.top.appendChild(m.focusScaleDownAnim)

        m.prevFocusedItem = invalid
    end if
end sub

sub onContentChange()
    m.grid.content = m.top.content
end sub

sub onItemComponentNameChange()
    m.grid.itemComponentName = m.top.itemComponentName
end sub

sub onJumpToItemChange()
    m.grid.jumpToItem = m.top.jumpToItem
end sub

sub onGridItemFocused()
    m.top.itemFocused = m.grid.itemFocused

    if m.lowMem then return

    ' Find the currently focused item component
    focusedItem = findFocusedItem(m.grid)

    ' Animate previous item back to normal scale
    if m.prevFocusedItem <> invalid and m.prevFocusedItem <> focusedItem
        m.prevFocusedItem.id = "gridFocusScaleDownTarget"
        m.focusScaleDownInterp.fieldToInterp = "gridFocusScaleDownTarget.scale"
        m.focusScaleDownAnim.control = "start"
    end if

    ' Animate new item to focused scale
    if focusedItem <> invalid
        focusedItem.scaleRotateCenter = [m.global.constants.tile.w / 2, m.global.constants.tile.h / 2]
        focusedItem.id = "gridFocusScaleUpTarget"
        m.focusScaleUpInterp.fieldToInterp = "gridFocusScaleUpTarget.scale"
        m.focusScaleUpAnim.control = "start"
        m.prevFocusedItem = focusedItem
    end if
end sub

sub onGridItemSelected()
    m.top.itemSelected = m.grid.itemSelected
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
    if m.grid <> invalid
        m.grid.unobserveField("itemFocused")
        m.grid.unobserveField("itemSelected")
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