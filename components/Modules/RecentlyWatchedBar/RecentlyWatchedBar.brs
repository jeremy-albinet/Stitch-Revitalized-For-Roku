' Local pins first, then confirmed-live channels from bounded recent history.
' Offline unpinned history stays stored and returns when live or pinned again.

sub init()
    m.disposed = false
    m.icon = m.top.findNode("icon")
    m.caption = m.top.findNode("caption")
    m.captionPlate = m.top.findNode("captionPlate")
    m.captionLabel = m.top.findNode("captionLabel")
    m.captionHint = m.top.findNode("captionHint")
    m.pinnedHeader = m.top.findNode("pinnedHeader")
    m.liveHeader = m.top.findNode("liveHeader")
    m.pinnedHeader.text = tr("PINNED")
    m.liveHeader.text = tr("LIVE")
    m.itemSpacing = 68
    m.itemStartY = 51
    m.itemX = 7
    ' Eight full rings plus two 24px headers end at y=639 (HD screen y=703).
    m.visibleWindow = 8
    m.items = []
    m.currentIndex = 0
    m.min = 0
    m.liveStatus = {}
    m.liveStatusTask = invalid
    m.actionDialog = invalid
    m.actionContext = invalid
    m.top.focusable = true
    buildItems()
    m.refreshTimer = createTimer(30, "onRefreshTimer", true)
end sub

sub buildItems()
    if m.disposed then return
    sameAccount = m.accountSection = RW_Section()
    hadDialog = m.actionDialog <> invalid
    closeSidebarActions()
    if not sameAccount
        m.liveStatus = {}
        m.currentIndex = 0
    end if
    m.accountSection = RW_Section()
    m.liveStatusTask = destroyTask(m.liveStatusTask, "response")
    m.entries = RW_LoadRail()
    renderItems(sameAccount)
    ' Poll candidates even when the pending/empty Live section has no nodes.
    fetchLiveStatus()
    if hadDialog then restoreSidebarFocus()
end sub

sub renderItems(preserveSelection = true as boolean, reuseNodes = false as boolean)
    selectedLogin = ""
    previousIndex = m.currentIndex
    if preserveSelection and m.currentIndex < m.items.Count() then selectedLogin = m.items[m.currentIndex].itemData.login
    previousItems = m.items
    if not reuseNodes
        for each item in previousItems
            item.callFunc("onDestroy")
        end for
        m.top.removeChildren(previousItems)
    end if
    m.items = []
    m.currentIndex = 0
    for each entry in m.entries
        live = false
        if GetInterface(m.liveStatus[entry.login], "ifBoolean") <> invalid then live = m.liveStatus[entry.login]
        if entry.pinned = true or live
            item = invalid
            if reuseNodes
                for each previous in previousItems
                    if previous.itemData.login = entry.login then item = previous
                end for
            end if
            if item = invalid
                item = CreateObject("roSGNode", "RecentlyWatchedItem")
                m.top.appendChild(item)
            end if
            item.itemData = entry
            item.isLive = live
            m.items.push(item)
        end if
    end for
    if reuseNodes
        for each previous in previousItems
            retained = false
            for each item in m.items
                if previous.isSameNode(item) then retained = true
            end for
            if not retained
                previous.callFunc("onDestroy")
                m.top.removeChild(previous)
            end if
        end for
    end if
    if preserveSelection and m.items.Count() > 0
        m.currentIndex = previousIndex
        if m.currentIndex >= m.items.Count() then m.currentIndex = m.items.Count() - 1
        for i = 0 to m.items.Count() - 1
            if m.items[i].itemData.login = selectedLogin then m.currentIndex = i
        end for
    end if
    m.min = 0
    if m.currentIndex >= m.visibleWindow then m.min = m.currentIndex - m.visibleWindow + 1
    updateItemVisibility()
    m.top.hasItems = m.items.Count() > 0
    updateCaption()
end sub

sub fetchLiveStatus()
    if m.entries.Count() = 0 then return
    logins = []
    for each entry in m.entries
        logins.push(entry.login)
    end for
    m.liveStatusTask = createApiTask("getLiveStatusForLogins", "onLiveStatusResponse", { params: { logins: logins } })
end sub

sub onLiveStatusResponse(event = invalid as dynamic)
    if m.disposed or m.liveStatusTask = invalid then return
    if m.accountSection <> RW_Section() then return
    if event <> invalid
        if not event.getRoSGNode().isSameNode(m.liveStatusTask) then return
    end if
    rsp = m.liveStatusTask.response
    m.liveStatus = {}
    if type(rsp) = "roAssociativeArray" then m.liveStatus = rsp
    ' Keep a menu's visual selection stable until it closes; its action owns
    ' immutable metadata and account scope even if this response arrives late.
    if m.actionDialog = invalid then renderItems(true, true)
end sub

sub onRefreshTimer()
    if m.top.itemHasFocus or m.actionDialog <> invalid then return
    buildItems()
end sub

sub onFocusToggle()
    if not m.top.itemHasFocus then closeSidebarActions()
    if m.items.Count() = 0 then return
    if m.currentIndex >= m.items.Count() then m.currentIndex = 0
    m.items[m.currentIndex].focused = m.top.itemHasFocus
    updateCaption()
end sub

sub updateCaption()
    if m.caption = invalid or m.captionLabel = invalid then return
    if not m.top.itemHasFocus or m.currentIndex >= m.items.Count()
        m.caption.visible = false
        return
    end if
    item = m.items[m.currentIndex]
    data = item.itemData
    name = ""
    if data <> invalid
        if data.displayName <> invalid and data.displayName <> ""
            name = data.displayName
        else if data.login <> invalid
            name = data.login
        end if
    end if
    if item.isLive then name = name + " · " + tr("LIVE")
    m.captionLabel.text = name
    width = 0
    try
        width = m.captionLabel.boundingRect().width
    catch e
    end try
    if width <= 0 then width = len(name) * 11
    hint = tr("Press * for sidebar actions")
    m.captionHint.text = hint
    m.captionHint.translation = [width + 28, 0]
    m.captionPlate.width = width + 42 + Len(hint) * 10
    m.caption.translation = [88, item.translation[1] + 12]
    m.caption.visible = m.actionDialog = invalid
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or m.disposed then return false
    ' A stale focused snapshot must never open a channel or mutate another user.
    if (key = "options" or key = "OK") and m.accountSection <> RW_Section()
        buildItems()
        return true
    end if
    if key = "left" then return true
    if m.items.Count() = 0 then return false
    if key = "up"
        if m.currentIndex = 0 then return false
        m.items[m.currentIndex].focused = false
        m.currentIndex -= 1
        if m.currentIndex < m.min then m.min = m.currentIndex
    else if key = "down"
        if m.currentIndex >= m.items.Count() - 1 then return true
        m.items[m.currentIndex].focused = false
        m.currentIndex += 1
        if m.currentIndex >= m.min + m.visibleWindow then m.min = m.currentIndex - m.visibleWindow + 1
    else if key = "options"
        showSidebarActions()
        return true
    else if key = "OK"
        data = m.items[m.currentIndex].itemData
        content = CreateObject("roSGNode", "TwitchContentNode")
        content.contentType = "LIVE"
        content.streamerLogin = data.login
        if data.id <> invalid then content.streamerId = data.id
        content.streamerDisplayName = data.displayName
        content.streamerProfileImageUrl = data.iconUrl
        m.top.itemHasFocus = false
        m.top.setFocus(false)
        m.top.contentSelected = content
        return true
    else
        return false
    end if
    updateItemVisibility()
    updateCaption()
    return true
end function

' Repeated headers stay with their visible group when the window scrolls.
' Hidden nodes never leave a partial avatar or header at a viewport edge.
sub updateItemVisibility()
    m.pinnedHeader.visible = false
    m.liveHeader.visible = false
    y = m.itemStartY
    group = ""
    for i = 0 to m.items.Count() - 1
        item = m.items[i]
        item.visible = i >= m.min and i < m.min + m.visibleWindow
        item.focused = m.top.itemHasFocus and i = m.currentIndex
        if item.visible
            section = "live"
            if item.itemData.pinned = true then section = "pinned"
            if group <> section
                header = m.liveHeader
                if section = "pinned" then header = m.pinnedHeader
                header.translation = [0, y]
                header.visible = true
                y += header.height
                group = section
            end if
            item.translation = [m.itemX, y]
            y += m.itemSpacing
        end if
    end for
end sub

sub showSidebarActions()
    if m.actionDialog <> invalid then return
    scene = m.top.getScene()
    if scene = invalid or scene.dialog <> invalid then return
    data = m.items[m.currentIndex].itemData
    ' Normalize to a fresh metadata-only AA, independent of later polls/rebuilds.
    m.actionContext = { entry: RW_NormalizeEntry(data), section: m.accountSection, pinned: data.pinned = true }
    label = tr("Pin to sidebar")
    if m.actionContext.pinned then label = tr("Unpin from sidebar")
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = data.displayName
    dialog.message = [tr("Sidebar changes stay on this Roku and do not change who you follow on Twitch.")]
    dialog.buttons = [label, tr("Remove from sidebar"), tr("Cancel")]
    applyDialogPalette(dialog)
    dialog.observeField("buttonSelected", "onSidebarAction")
    dialog.observeField("wasClosed", "onSidebarActionsClosed")
    m.actionDialog = dialog
    scene.dialog = dialog
    updateCaption()
end sub

sub onSidebarAction(event as object)
    if m.disposed or m.actionDialog = invalid then return
    if not event.getRoSGNode().isSameNode(m.actionDialog) then return
    context = m.actionContext
    index = m.actionDialog.buttonSelected
    closeSidebarActions()
    if context = invalid then return
    if context.section <> RW_Section() or context.section <> m.accountSection
        buildItems()
        restoreSidebarFocus()
        return
    end if
    if index = 0
        result = RW_SetPinned(context.entry, not context.pinned, context.section)
    else if index = 1
        removed = RW_Remove(context.entry, context.section)
    end if
    if index = 0 or index = 1
        buildItems()
    else
        renderItems(true, true)
    end if
    restoreSidebarFocus()
end sub

sub onSidebarActionsClosed(event as object)
    if m.disposed or m.actionDialog = invalid then return
    if not event.getRoSGNode().isSameNode(m.actionDialog) then return
    closeSidebarActions()
    if m.accountSection <> RW_Section()
        buildItems()
    else
        renderItems(true, true)
    end if
    restoreSidebarFocus()
end sub

sub restoreSidebarFocus()
    if m.top.hasItems and m.top.itemHasFocus then m.top.setFocus(true)
    updateCaption()
end sub

sub closeSidebarActions()
    dialog = m.actionDialog
    m.actionDialog = invalid
    m.actionContext = invalid
    if dialog = invalid then return
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    dialog.close = true
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        if scene.dialog.isSameNode(dialog) then scene.dialog = invalid
    end if
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    closeSidebarActions()
    if m.refreshTimer <> invalid
        m.refreshTimer.control = "stop"
        m.refreshTimer.unobserveField("fire")
        m.refreshTimer = invalid
    end if
    m.liveStatusTask = destroyTask(m.liveStatusTask, "response")
    m.top.unobserveField("itemHasFocus")
    for each item in m.items
        item.callFunc("onDestroy")
    end for
    m.items = []
end sub
