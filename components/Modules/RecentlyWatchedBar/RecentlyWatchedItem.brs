' Live items show a small red dot in the bottom-right of the avatar.
' Avatars are never dimmed; the dot alone signals live state.

sub init()
    m.selectionIndicator = m.top.findNode("selectionIndicator")
    m.avatar = m.top.findNode("avatar")
    m.root = m.top.findNode("root")
    m.liveDot = m.top.findNode("liveDot")
    m.pinDot = m.top.findNode("pinDot")
end sub

sub onDataChanged()
    data = m.top.itemData
    if data = invalid then return

    m.pinDot.visible = (data.pinned = true)

    if data.iconUrl <> invalid and data.iconUrl <> ""
        m.avatar.uri = data.iconUrl
    end if
end sub

' Focus shows a single purple ring around the avatar. No scaling, no color shift.
sub onFocusChanged()
    m.selectionIndicator.visible = m.top.focused
end sub

sub onIsLiveChanged()
    if m.liveDot <> invalid
        m.liveDot.visible = m.top.isLive
    end if
end sub

sub onDestroy()
    m.top.unobserveField("itemData")
    m.top.unobserveField("focused")
    m.top.unobserveField("isLive")
end sub
