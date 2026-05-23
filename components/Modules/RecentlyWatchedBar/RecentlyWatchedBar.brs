' RecentlyWatchedBar — left sidebar showing recently watched streamers.
'
' History is registry-backed (no auth required to populate items).
' Live status dots are fetched via TwitchApiTask after each buildItems() call
' and refreshed on the same 30-second timer. Requires device_code; gracefully
' no-ops if the network is unavailable.
' Items scroll vertically when history exceeds the visible window.

sub init()
    m.icon = m.top.findNode("icon")

    ' Layout constants
    m.itemSpacing = 60 ' px between item origins
    m.itemStartY = 30 ' px below the icon (icon height + space 6px)
    m.itemX = 10 ' px from bar left edge
    m.visibleWindow = 8 ' number of items visible at once before scrolling

    m.items = []
    m.currentIndex = 0
    m.min = 0
    m.max = m.visibleWindow - 1

    m.liveStatusTask = invalid

    m.top.focusable = true

    buildItems()

    ' Refresh history periodically, but never while user has focus in the bar
    m.refreshTimer = createTimer(30, "onRefreshTimer", true)
end sub

' Build (or rebuild) item nodes from registry history.
' Called on init and by refresh timer.
sub buildItems()
    ' Remove previously created item children (children 2+ are items; 0=bg, 1=icon)
    if m.items.Count() > 0
        m.top.removeChildren(m.items)
        m.items = []
    end if

    ' Reset scroll state
    m.currentIndex = 0
    m.min = 0
    m.max = m.visibleWindow - 1

    history = RW_Load()
    if history = invalid or history.Count() = 0 then return

    translationY = m.itemStartY
    index = 0

    for each entry in history
        item = CreateObject("roSGNode", "RecentlyWatchedItem")
        item.translation = [m.itemX, translationY]
        item.itemData = entry
        item.visible = (index >= m.min and index <= m.max)
        m.top.appendChild(item)
        m.items.push(item)
        translationY += m.itemSpacing
        index += 1
    end for

    fetchLiveStatus()
end sub

' Fire a TwitchApiTask to check live status for all items currently in the bar.
sub fetchLiveStatus()
    if m.items.Count() = 0 then return

    logins = []
    for each item in m.items
        data = item.itemData
        if data <> invalid and data.login <> invalid and data.login <> ""
            logins.push(data.login)
        end if
    end for
    if logins.Count() = 0 then return

    m.liveStatusTask = destroyTask(m.liveStatusTask, "response")
    m.liveStatusTask = createApiTask("getLiveStatusForLogins", "onLiveStatusResponse", { params: { logins: logins } })
end sub

' Callback when live status task completes.
' rsp is an AA: login (lowercase) -> boolean
' Always resets all dots first so a failed/empty response clears stale state.
sub onLiveStatusResponse()
    rsp = m.liveStatusTask.response

    ' Clear all dots unconditionally — empty AA means failure or all-offline.
    for each item in m.items
        item.isLive = false
    end for

    if rsp = invalid or rsp.Count() = 0 then return

    for each item in m.items
        data = item.itemData
        if data <> invalid and data.login <> invalid
            login = LCase(data.login)
            if rsp.doesExist(login)
                item.isLive = rsp[login]
            end if
        end if
    end for
end sub

' Refresh timer callback — only rebuilds when focus is not inside the bar,
' so a periodic refresh never disrupts an active selection.
sub onRefreshTimer()
    if m.top.itemHasFocus then return
    buildItems()
end sub

' Called when heroScene sets itemHasFocus to enter or leave the bar.
sub onFocusToggle()
    if m.items.Count() = 0 then return

    if m.top.itemHasFocus
        ' Clamp index in case history shrunk since last visit
        if m.currentIndex >= m.items.Count()
            m.currentIndex = 0
        end if
        m.items[m.currentIndex].focused = true
    else
        if m.currentIndex < m.items.Count()
            m.items[m.currentIndex].focused = false
        end if
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Left key: trap it — don't let focus escape further left
    if key = "left" then return true

    if m.items.Count() = 0 then return false

    if key = "up"
        if m.currentIndex = 0
            ' At the top — let heroScene handle up to give focus back to MenuBar
            return false
        end if
        m.items[m.currentIndex].focused = false
        m.currentIndex -= 1
        ' Scroll window up if we've moved above the visible min
        if m.currentIndex < m.min
            for each item in m.items
                item.translation = [m.itemX, item.translation[1] + m.itemSpacing]
            end for
            m.min -= 1
            m.max -= 1
            updateItemVisibility()
        end if
        m.items[m.currentIndex].focused = true
        return true

    else if key = "down"
        if m.currentIndex >= m.items.Count() - 1
            ' Already at last item
            return true
        end if
        m.items[m.currentIndex].focused = false
        m.currentIndex += 1
        ' Scroll window down if we've moved past the visible max
        if m.currentIndex > m.max
            for each item in m.items
                item.translation = [m.itemX, item.translation[1] - m.itemSpacing]
            end for
            m.min += 1
            m.max += 1
            updateItemVisibility()
        end if
        m.items[m.currentIndex].focused = true
        return true

    else if key = "OK"
        if m.currentIndex >= m.items.Count() then return false
        selected = m.items[m.currentIndex]
        data = selected.itemData

        ' Build a TwitchContentNode for the selected channel
        content = CreateObject("roSGNode", "TwitchContentNode")
        content.contentType = "LIVE"
        content.streamerLogin = data.login
        content.streamerDisplayName = data.displayName
        content.streamerProfileImageUrl = data.iconUrl

        ' Release focus before emitting — heroScene takes it from here
        m.items[m.currentIndex].focused = false
        m.top.itemHasFocus = false
        m.top.setFocus(false)

        m.top.contentSelected = content
        return true
    end if

    return false
end function

' Show only items within the visible scroll window, hide above and below.
sub updateItemVisibility()
    bottomBound = m.itemStartY + m.itemSpacing * m.visibleWindow
    for each item in m.items
        y = item.translation[1]
        item.visible = (y >= 0 and y < bottomBound)
    end for
end sub

sub onDestroy()
    m.refreshTimer = destroyTask(m.refreshTimer, "fire")
    m.liveStatusTask = destroyTask(m.liveStatusTask, "response")
    m.top.unobserveField("itemHasFocus")
end sub
