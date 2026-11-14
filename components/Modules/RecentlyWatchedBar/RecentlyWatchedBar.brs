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
    m.dialog = invalid
    m.dialogActions = []

    m.top.focusable = true

    buildItems()

    ' Refresh history periodically, but never while user has focus in the bar
    m.refreshTimer = createTimer(30, "onRefreshTimer", true)
end sub

' Build (or rebuild) item nodes from registry history.
' Called on init and by refresh timer.
sub buildItems()
    ' Which account's history these items show (see showOptionsDialog)
    m.itemsSection = RW_Section()
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

    else if key = "options"
        if m.currentIndex >= m.items.Count() then return false
        showOptionsDialog()
        return true
    end if

    return false
end function

' Options menu for the focused channel. Edits local history only; never calls Twitch.
' After a login/logout (including the startup token check finishing late) the list can
' still show the previous account's history, and edits would hit the new account.
' Checked before opening the menu and again before every change; refreshes on mismatch.
function accountChanged() as boolean
    if m.itemsSection = RW_Section() then return false
    closeDialog()
    rebuildKeepingFocus(0)
    return true
end function

sub showOptionsDialog()
    if accountChanged() then return
    data = m.items[m.currentIndex].itemData
    name = data.displayName
    if name = invalid or name = "" then name = data.login
    pinLabel = tr("Pin")
    if data.pinned = true then pinLabel = tr("Unpin")
    m.dialogActions = ["pin", "remove", "clearall", "cancel"]
    openDialog(name, "", [pinLabel, tr("Remove from sidebar"), tr("Clear all recent"), tr("Cancel")], "onOptionsButton")
end sub

sub openDialog(title as string, message as string, buttons as object, callback as string)
    closeDialog()
    m.dialog = CreateObject("roSGNode", "StandardMessageDialog")
    m.dialog.title = title
    if message <> "" then m.dialog.message = [message]
    m.dialog.buttons = buttons
    m.dialog.observeField("buttonSelected", callback)
    m.dialog.observeField("wasClosed", "onDialogClosed")
    m.top.getScene().dialog = m.dialog
end sub

' Unobserves and closes the open dialog, if any.
sub closeDialog()
    if m.dialog = invalid then return
    m.dialog.unobserveField("buttonSelected")
    m.dialog.unobserveField("wasClosed")
    m.dialog.close = true
    m.dialog = invalid
end sub

' Back dismissed the dialog.
sub onDialogClosed()
    if m.dialog = invalid then return
    m.dialog.unobserveField("buttonSelected")
    m.dialog.unobserveField("wasClosed")
    m.dialog = invalid
end sub

sub onOptionsButton()
    if m.dialog = invalid then return
    pressed = m.dialog.buttonSelected
    action = "cancel"
    if pressed >= 0 and pressed < m.dialogActions.Count() then action = m.dialogActions[pressed]
    if action <> "cancel" and accountChanged() then return

    if action = "pin"
        closeDialog()
        togglePinSelected()
    else if action = "remove"
        closeDialog()
        removeSelected()
    else if action = "clearall"
        ' Cancel comes first so a stray OK keeps the list.
        openDialog(tr("Clear all recent"), tr("This clears your recent channels. Pinned channels stay."), [tr("Cancel"), tr("OK")], "onClearAllButton")
    else
        closeDialog()
    end if
end sub

sub onClearAllButton()
    if m.dialog = invalid then return
    pressed = m.dialog.buttonSelected
    closeDialog()
    if pressed <> 1 then return
    if accountChanged() then return
    RW_Clear()
    rebuildKeepingFocus(m.currentIndex)
end sub

' Pin or unpin the focused channel. A pinned channel moves up, an unpinned one down,
' so focus follows the channel to its new spot.
sub togglePinSelected()
    data = m.items[m.currentIndex].itemData
    if data.login = invalid then return
    login = data.login
    if data.pinned = true then RW_Unpin(login) else RW_Pin(data)
    newIndex = 0
    list = RW_Load()
    for i = 0 to list.Count() - 1
        if list[i].login = login then newIndex = i
    end for
    rebuildKeepingFocus(newIndex)
end sub

sub removeSelected()
    login = m.items[m.currentIndex].itemData.login
    if login = invalid then return
    RW_Remove(login)
    rebuildKeepingFocus(m.currentIndex)
end sub

' Rebuild the list after an edit and put focus on the same spot (or the last item).
' Releases focus and emits becameEmpty when nothing is left.
sub rebuildKeepingFocus(keepIndex as integer)
    buildItems()
    count = m.items.Count()
    if count = 0
        m.top.itemHasFocus = false
        m.top.becameEmpty = true
        return
    end if
    if keepIndex >= count then keepIndex = count - 1
    m.currentIndex = keepIndex
    ' Scroll so the focused item is the last visible one if it is past the first window
    m.min = 0
    if keepIndex > m.visibleWindow - 1 then m.min = keepIndex - m.visibleWindow + 1
    m.max = m.min + m.visibleWindow - 1
    for each item in m.items
        item.translation = [m.itemX, item.translation[1] - m.min * m.itemSpacing]
    end for
    updateItemVisibility()
    m.items[keepIndex].focused = true
    m.top.setFocus(true)
end sub

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
    closeDialog()
    m.liveStatusTask = destroyTask(m.liveStatusTask, "response")
    m.top.unobserveField("itemHasFocus")
end sub
