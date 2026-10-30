sub init()
    m.disposed = false
    m.plate = m.top.findNode("plate")
    m.name = m.top.findNode("name")
    m.value = m.top.findNode("value")
    m.focusRing = m.top.findNode("focusRing")
end sub

sub onContentChange()
    if m.disposed then return
    content = m.top.itemContent
    if content = invalid then return
    m.name.text = content.title
    m.value.text = content.shortDescriptionLine1
    layoutRow()
end sub

' The focused row reads in white on the raised plate inside the focus ring.
sub onFocusChange()
    if m.disposed then return
    color = m.global?.constants?.ui?.color
    if color = invalid then return
    focused = m.top.focusPercent > 0.5 and m.top.listHasFocus
    if m.focusRing <> invalid then m.focusRing.visible = focused
    if focused
        m.plate.color = color.raised
        m.name.color = color.onAccent
        m.value.color = color.text
    else
        m.plate.color = color.surface
        m.name.color = color.text
        m.value.color = color.textSecondary
    end if
end sub

sub onSizeChange()
    if m.disposed then return
    width = m.top.width
    height = m.top.height
    if width <= 0 or height <= 0 then return
    m.plate.width = width
    m.plate.height = height
    if m.focusRing <> invalid
        m.focusRing.width = width
        m.focusRing.height = height
    end if
    m.name.height = height
    m.value.height = height
    layoutRow()
end sub

' A short value ("Off") leaves the rest of the row to the name; a long one,
' such as a service address, takes at most half and truncates itself.
sub layoutRow()
    width = m.plate.width
    inner = width - 40
    valueWidth = 0
    if m.value.text <> ""
        valueWidth = Int(inner * 0.42)
        try
            m.value.width = 0
            measured = m.value.boundingRect().width
            if measured > 0 then valueWidth = Int(measured) + 1
        catch e
        end try
        if valueWidth > Int(inner * 0.5) then valueWidth = Int(inner * 0.5)
    end if
    gap = 0
    if valueWidth > 0 then gap = 16
    m.name.width = inner - valueWidth - gap
    m.value.translation = [width - 20 - valueWidth, 0]
    m.value.width = valueWidth
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
end sub
