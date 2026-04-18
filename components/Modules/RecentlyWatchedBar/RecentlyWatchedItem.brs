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

sub onFocusChanged()
    if m.top.focused
        m.selectionIndicator.visible = true
        m.avatar.outlineColor = m.global.constants.colors.twitch.purple10
        try
            m.avatar.scale = [1.08, 1.08]
        catch e
        end try
    else
        m.selectionIndicator.visible = false
        m.avatar.outlineColor = "0x00000000"
        try
            m.avatar.scale = [1.0, 1.0]
        catch e
        end try
    end if
end sub

sub onDestroy()
    m.top.unobserveField("itemData")
    m.top.unobserveField("focused")
end sub
