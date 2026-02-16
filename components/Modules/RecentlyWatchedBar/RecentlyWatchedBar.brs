sub init()
    m.backgroundBar = m.top.findNode("backgroundBar")
    m.xTranslation = 15
    m.top.focusable = true
    m.children = []

    ' existing children: background + history icon are 0 and 1
    for child = 2 to m.top.getChildCount() - 1
        m.children.push(m.top.getChild(child))
    end for

    m.currentIndex = 0
    m.min = 0
    m.max = 9
    m.cooldownUntil = 0

    refreshRecentBar()

    ' periodic refresh in case history changes while idle
    m.refreshTimer = CreateObject("roSGNode", "Timer")
    m.refreshTimer.observeField("fire", "refreshRecentBar")
    m.refreshTimer.repeat = true
    m.refreshTimer.duration = "10"
    m.refreshTimer.control = "start"
end sub

sub refreshRecentBar()
    ' Avoid rebuilding while focused; prevents jumping selection
    if m.top.itemHasFocus = true then return

    translationY = 50

    ' remove existing item children
    if m.children <> invalid and m.children.Count() > 0
        m.top.removeChildren(m.children)
    end if

    data = RW_Load(12)

    m.currentIndex = 0
    m.min = 0
    m.max = 9

    if data <> invalid and data.Count() > 0
        for each it in data
            group = CreateObject("roSGNode", "RecentSidebarItem")

            if it.login <> invalid then group.twitch_login = it.login
            if it.displayName <> invalid then group.display_name = it.displayName
            if it.id <> invalid then group.streamer_id = it.id
            if it.iconUrl <> invalid then group.streamerProfileImage = it.iconUrl

            group.translation = [m.xTranslation, translationY]
            m.top.appendChild(group)
            translationY += 60
        end for

        m.children = []
        for child = 2 to m.top.getChildCount() - 1
            m.children.push(m.top.getChild(child))
        end for
    else
        m.children = []
    end if
end sub

sub onGetFocus()
    if m.top.itemHasFocus = true
        if m.children <> invalid and m.children.Count() > 0
            if m.children[m.currentIndex] <> invalid
                m.children[m.currentIndex].focused = true
            end if
        end if
    else
        if m.children <> invalid and m.children.Count() > 0
            if m.children[m.currentIndex] <> invalid
                m.children[m.currentIndex].focused = false
            end if
        end if
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    handled = false
    if not press then return false

    if key = "left" then return true ' stop moving further left

    if m.children = invalid or m.children.Count() = 0
        return false
    end if

    if key = "up"
        if m.currentIndex = 0
            return false
        end if
        if m.currentIndex - 1 >= 0
            m.children[m.currentIndex].focused = false
            m.currentIndex -= 1
            if m.currentIndex < m.min
                for each stream in m.children
                    stream.translation = [m.xTranslation, (stream.translation[1] + 60)]
                    if stream.translation[1] > 0 then stream.visible = true
                end for
                m.min -= 1
                m.max -= 1
            end if
            m.children[m.currentIndex].focused = true
        end if
        handled = true

    else if key = "down"
        if m.currentIndex + 1 < m.children.Count()
            m.children[m.currentIndex].focused = false
            m.currentIndex += 1
            if m.currentIndex > m.max
                for each stream in m.children
                    stream.translation = [m.xTranslation, (stream.translation[1] - 60)]
                    if stream.translation[1] <= 0 then stream.visible = false
                end for
                m.min += 1
                m.max += 1
            end if
            m.children[m.currentIndex].focused = true
        end if
        handled = true

    else if key = "OK"
        ' Build a TwitchContentNode for the selected streamer page
        selected = m.children[m.currentIndex]
        content = CreateObject("roSGNode", "TwitchContentNode")
        content.contentType = "STREAMER"
        content.streamerLogin = selected.twitch_login
        content.streamerDisplayName = selected.display_name
        content.streamerId = selected.streamer_id
        content.streamerProfileImageUrl = selected.streamerProfileImage
        m.top.contentSelected = content
        ' Hand off focus back to the scene so the navigation handler can switch pages
        m.children[m.currentIndex].focused = false
        m.top.itemHasFocus = false
        m.top.setFocus(false)
        handled = true
    end if

    return handled
end function
