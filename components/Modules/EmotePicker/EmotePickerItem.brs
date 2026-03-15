sub init()
    m.focusBg = m.top.findNode("focusBg")
    m.emoteImage = m.top.findNode("emoteImage")
    m.emoteName = m.top.findNode("emoteName")
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    if content.emoteCode <> invalid
        m.emoteName.text = content.emoteCode
    end if
    if content.emoteUri <> invalid and content.emoteUri <> ""
        m.emoteImage.uri = content.emoteUri
    end if
end sub

sub onFocusChanged()
    if m.focusBg <> invalid
        m.focusBg.visible = (m.top.focusPercent > 0)
    end if
end sub
