' Live items show a small red dot in the bottom-right of the avatar.
' Avatars are never dimmed; the dot alone signals live state.

sub init()
    m.selectionIndicator = m.top.findNode("selectionIndicator")
    m.avatar = m.top.findNode("avatar")
    m.root = m.top.findNode("root")
    m.liveDot = m.top.findNode("liveDot")
end sub

sub onDataChanged()
    data = m.top.itemData
    if data = invalid then return

    if data.iconUrl <> invalid and data.iconUrl <> ""
        m.avatar.uri = data.iconUrl
    end if
end sub

' Focus shows a single purple ring around the avatar. No scaling, no color shift.
sub onFocusChanged()
    m.selectionIndicator.visible = m.top.focused = true
end sub

sub onIsLiveChanged()
    if m.liveDot <> invalid
        m.liveDot.visible = m.top.isLive = true
    end if
end sub

sub onDestroy()
    m.top.unobserveField("itemData")
    m.top.unobserveField("focused")
    m.top.unobserveField("isLive")
end sub
