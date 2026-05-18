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

    ' Visual polish gated by memory (skip on low-RAM devices)
    m.lowRamDevice = CreateObject("roDeviceInfo").GetMemoryLimit() < 30
    m.prevFocusedItem = invalid

    if not m.lowRamDevice
        ' --- Focus scale animation ---
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

        ' --- Focus glow poster ---
        m.focusGlow = CreateObject("roSGNode", "Poster")
        m.focusGlow.id = "focusGlow"
        m.focusGlow.uri = "pkg:/images/purple_circle.png"
        m.focusGlow.width = c.tile.w * 1.1
        m.focusGlow.height = c.tile.h * 1.1
        m.focusGlow.opacity = 0
        m.focusGlow.visible = false
        m.top.appendChild(m.focusGlow)

        ' Glow fade-in animation (0 -> 0.4)
        m.glowFadeInAnim = CreateObject("roSGNode", "Animation")
        m.glowFadeInAnim.duration = 0.2
        m.glowFadeInInterp = CreateObject("roSGNode", "FloatFieldInterpolator")
        m.glowFadeInInterp.fieldToInterpolate = "opacity"
        m.glowFadeInInterp.keyValue = [0, 0.4]
        m.glowFadeInAnim.appendChild(m.glowFadeInInterp)
        m.top.appendChild(m.glowFadeInAnim)

        ' Glow fade-out animation (0.4 -> 0)
        m.glowFadeOutAnim = CreateObject("roSGNode", "Animation")
        m.glowFadeOutAnim.duration = 0.2
        m.glowFadeOutInterp = CreateObject("roSGNode", "FloatFieldInterpolator")
        m.glowFadeOutInterp.fieldToInterpolate = "opacity"
        m.glowFadeOutInterp.keyValue = [0.4, 0]
        m.glowFadeOutAnim.appendChild(m.glowFadeOutInterp)
        m.top.appendChild(m.glowFadeOutAnim)
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

    if m.lowRamDevice then return

    focusedItem = findFocusedItem(m.rowList)

    ' Animate previous item back to normal scale and fade out glow
    if m.prevFocusedItem <> invalid and m.prevFocusedItem <> focusedItem
        ' Stop any running scale-down and reset its target
        m.focusScaleDownAnim.control = "stop"
        if m.focusScaleDownAnim.target <> invalid
            m.focusScaleDownAnim.target.scale = [1.0, 1.0]
        end if
        m.focusScaleDownAnim.target = m.prevFocusedItem
        m.focusScaleDownAnim.control = "start"

        ' Fade out glow
        m.glowFadeOutAnim.target = m.focusGlow
        m.glowFadeOutAnim.control = "start"
    end if

    ' Animate new item to focused scale
    if focusedItem <> invalid
        c = m.global.constants
        focusedItem.scaleRotateCenter = [c.tile.w / 2, c.tile.h / 2]
        m.focusScaleUpAnim.target = focusedItem
        m.focusScaleUpAnim.control = "start"
        m.prevFocusedItem = focusedItem

        ' Position and fade in glow behind focused tile
        positionGlow(focusedItem)
    else
        ' No focus — hide glow
        m.focusGlow.visible = false
        m.prevFocusedItem = invalid
    end if
end sub

sub positionGlow(focusedItem as dynamic)
    if m.focusGlow = invalid then return
    c = m.global.constants
    glowW = c.tile.w * 1.1
    glowH = c.tile.h * 1.1

    ' Get the focused item's position relative to the TileRow
    try
        bounds = focusedItem.boundingRect()
        m.focusGlow.translation = [bounds.x - (glowW - c.tile.w) / 2, bounds.y - (glowH - c.tile.h) / 2]
    catch e
        ' boundingRect can throw in brs-engine — fall back to centering
        m.focusGlow.translation = [0, 0]
    end try

    m.focusGlow.visible = true
    m.glowFadeInAnim.target = m.focusGlow
    m.glowFadeInAnim.control = "start"
end sub

sub onRowListItemSelected()
    m.top.itemSelected = m.rowList.itemSelected
end sub

' Recursively find the item component with itemHasFocus = true
function findFocusedItem(node as dynamic) as dynamic
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

    ' Clean up visual polish
    if m.prevFocusedItem <> invalid
        m.prevFocusedItem.scale = [1.0, 1.0]
        m.prevFocusedItem.scaleRotateCenter = [0.0, 0.0]
    end if
    if m.focusScaleUpAnim <> invalid
        m.focusScaleUpAnim.control = "stop"
    end if
    if m.focusScaleDownAnim <> invalid
        m.focusScaleDownAnim.control = "stop"
    end if
    if m.glowFadeInAnim <> invalid
        m.glowFadeInAnim.control = "stop"
    end if
    if m.glowFadeOutAnim <> invalid
        m.glowFadeOutAnim.control = "stop"
    end if
end sub
