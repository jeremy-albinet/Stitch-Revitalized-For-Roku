sub init()
    m.scaleWrapper = m.top.findNode("scaleWrapper")
    m.rowList = m.top.findNode("rowList")
    m.focusGlow = m.top.findNode("focusGlow")

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

    ' Focus scale animation (gated by low-RAM check)
    if not m.lowMem
        m.focusScaleUpAnim = CreateObject("roSGNode", "Animation")
        m.focusScaleUpInterp = CreateObject("roSGNode", "Vector2DFieldInterpolator")
        m.focusScaleUpInterp.fieldToInterp = "scale"
        m.focusScaleUpInterp.keyValue = [[1.0, 1.0], [c.focus.scale, c.focus.scale]]
        m.focusScaleUpAnim.duration = c.focus.duration
        m.focusScaleUpAnim.AddInterpolator(m.focusScaleUpInterp)
        m.scaleWrapper.appendChild(m.focusScaleUpAnim)

        m.focusScaleDownAnim = CreateObject("roSGNode", "Animation")
        m.focusScaleDownInterp = CreateObject("roSGNode", "Vector2DFieldInterpolator")
        m.focusScaleDownInterp.fieldToInterp = "scale"
        m.focusScaleDownInterp.keyValue = [[c.focus.scale, c.focus.scale], [1.0, 1.0]]
        m.focusScaleDownAnim.duration = c.focus.duration
        m.focusScaleDownAnim.AddInterpolator(m.focusScaleDownInterp)
        m.scaleWrapper.appendChild(m.focusScaleDownAnim)

        ' Focus glow poster
        m.focusGlow.uri = "pkg:/images/focus_fhd.9.png"
        m.focusGlow.width = c.tile.w * 1.1
        m.focusGlow.height = c.tile.h * 1.1
        m.focusGlow.opacity = 0

        ' Glow fade-in animation (0 -> 0.4)
        m.glowFadeInAnim = CreateObject("roSGNode", "Animation")
        m.glowFadeInInterp = CreateObject("roSGNode", "FloatFieldInterpolator")
        m.glowFadeInInterp.fieldToInterp = "opacity"
        m.glowFadeInInterp.keyValue = [0, 0.4]
        m.glowFadeInAnim.duration = 0.2
        m.glowFadeInAnim.AddInterpolator(m.glowFadeInInterp)
        m.focusGlow.appendChild(m.glowFadeInAnim)

        ' Glow fade-out animation (0.4 -> 0)
        m.glowFadeOutAnim = CreateObject("roSGNode", "Animation")
        m.glowFadeOutInterp = CreateObject("roSGNode", "FloatFieldInterpolator")
        m.glowFadeOutInterp.fieldToInterp = "opacity"
        m.glowFadeOutInterp.keyValue = [0.4, 0]
        m.glowFadeOutAnim.duration = 0.2
        m.glowFadeOutAnim.AddInterpolator(m.glowFadeOutInterp)
        m.focusGlow.appendChild(m.glowFadeOutAnim)

        m.top.observeField("isInFocusChain", "onFocusChainChanged")
    end if
end sub

sub onRowListItemFocused()
    m.top.itemFocused = m.rowList.itemFocused

    if m.lowMem then return

    if m.rowList.itemFocused >= 0
        m.focusScaleDownAnim.control = "stop"
        m.focusScaleUpAnim.control = "start"
        m.glowFadeOutAnim.control = "stop"
        m.glowFadeInAnim.control = "start"
    end if
end sub

sub onFocusChainChanged()
    if m.lowMem then return

    if not m.top.isInFocusChain
        m.focusScaleUpAnim.control = "stop"
        m.focusScaleDownAnim.control = "start"
        m.glowFadeInAnim.control = "stop"
        m.glowFadeOutAnim.control = "start"
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

sub onRowListItemSelected()
    m.top.itemSelected = m.rowList.itemSelected
end sub

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
        if m.glowFadeInAnim <> invalid
            m.glowFadeInAnim.control = "stop"
        end if
        if m.glowFadeOutAnim <> invalid
            m.glowFadeOutAnim.control = "stop"
        end if
        m.top.unobserveField("isInFocusChain")
    end if
end sub
