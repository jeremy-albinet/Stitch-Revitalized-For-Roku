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

    ' Low-RAM gate for visual polish
    m.lowMem = CreateObject("roDeviceInfo").GetMemoryLimit() < 30
    m.prevFocusedItem = invalid

    if not m.lowMem
        ' Focus scale animation
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

        ' Focus glow poster (additive glow behind focused tile)
        m.focusGlow = CreateObject("roSGNode", "Poster")
        m.focusGlow.id = "focusGlow"
        m.focusGlow.uri = "pkg:/images/purple_circle.png"
        m.focusGlow.width = c.tile.w * 1.1
        m.focusGlow.height = c.tile.h * 1.1
        m.focusGlow.opacity = 0
        m.focusGlow.visible = false
        m.top.appendChild(m.focusGlow)

        ' Glow opacity animation (0 -> 0.4 on focus)
        m.glowFadeInAnim = CreateObject("roSGNode", "Animation")
        m.glowFadeInInterp = CreateObject("roSGNode", "FloatFieldInterpolator")
        m.glowFadeInInterp.keyField = "time"
        m.glowFadeInInterp.keyValue = [0, 0.4]
        m.glowFadeInInterp.fieldToInterp = "focusGlow.opacity"
        m.glowFadeInAnim.duration = 0.2
        m.glowFadeInAnim.AddInterpolator(m.glowFadeInInterp)
        m.top.appendChild(m.glowFadeInAnim)

        ' Glow opacity animation (0.4 -> 0 on unfocus)
        m.glowFadeOutAnim = CreateObject("roSGNode", "Animation")
        m.glowFadeOutInterp = CreateObject("roSGNode", "FloatFieldInterpolator")
        m.glowFadeOutInterp.keyField = "time"
        m.glowFadeOutInterp.keyValue = [0.4, 0]
        m.glowFadeOutInterp.fieldToInterp = "focusGlow.opacity"
        m.glowFadeOutAnim.duration = 0.2
        m.glowFadeOutAnim.AddInterpolator(m.glowFadeOutInterp)
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

    if m.lowMem then return

    ' Find the currently focused item component
    focusedItem = findFocusedItem(m.rowList)

    ' Animate previous item back to normal scale and fade out glow
    if m.prevFocusedItem <> invalid and m.prevFocusedItem <> focusedItem
        m.prevFocusedItem.id = "focusScaleDownTarget"
        m.focusScaleDownInterp.fieldToInterp = "focusScaleDownTarget.scale"
        m.focusScaleDownAnim.control = "start"
        ' Fade out glow on previous item
        m.glowFadeOutAnim.control = "start"
    end if

    ' Animate new item to focused scale
    if focusedItem <> invalid
        focusedItem.scaleRotateCenter = [m.global.constants.tile.w / 2, m.global.constants.tile.h / 2]
        focusedItem.id = "focusScaleUpTarget"
        m.focusScaleUpInterp.fieldToInterp = "focusScaleUpTarget.scale"
        m.focusScaleUpAnim.control = "start"
        m.prevFocusedItem = focusedItem

        ' Position glow behind focused tile
        positionGlow(focusedItem)
    else
        ' No focus — hide glow
        m.focusGlow.visible = false
    end if
end sub

sub positionGlow(focusedItem as object)
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
    m.glowFadeInAnim.control = "start"
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
        ' Reset previous focused item scale
        if m.prevFocusedItem <> invalid
            m.prevFocusedItem.scale = [1.0, 1.0]
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
    end if
end sub