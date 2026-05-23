' Offline items are dimmed (~40% opacity) to mimic the twitch.tv web app's
' offline appearance. Live items remain at full opacity.

sub init()
    m.selectionIndicator = m.top.findNode("selectionIndicator")
    m.avatar = m.top.findNode("avatar")
    m.root = m.top.findNode("root")
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

' Live → avatar at full opacity. Offline → dimmed (~40%).
sub onIsLiveChanged()
    if m.top.isLive
        m.avatar.opacity = 1.0
    else
        m.avatar.opacity = 0.4
    end if
end sub

sub onDestroy()
    m.top.unobserveField("itemData")
    m.top.unobserveField("focused")
    m.top.unobserveField("isLive")
end sub
