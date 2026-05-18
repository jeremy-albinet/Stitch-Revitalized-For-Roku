sub init()
    m.scaleWrapper = m.top.findNode("scaleWrapper")
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

        m.top.observeField("isInFocusChain", "onFocusChainChanged")
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

    if m.grid.itemFocused >= 0
        m.focusScaleDownAnim.control = "stop"
        m.focusScaleUpAnim.control = "start"
    end if
end sub

sub onFocusChainChanged()
    if m.lowMem then return

    if not m.top.isInFocusChain
        m.focusScaleUpAnim.control = "stop"
        m.focusScaleDownAnim.control = "start"
    end if
end sub

sub onGridItemSelected()
    m.top.itemSelected = m.grid.itemSelected
end sub

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
        m.top.unobserveField("isInFocusChain")
    end if
end sub
