' Actual bar, item, registry and Hero handlers. Only Task I/O and dialog input
' are boundaries; production dialog observers receive native field events.
sub testSidebarSections(scene as object)
    RW_Add(entry("offline", 1))
    RW_Add(entry("live_recent", 2))
    RW_Add(entry("live_pin", 3))
    result = RW_SetPinned(entry("offline_pin", 4), true)
    result = RW_SetPinned(entry("live_pin", 3), true)
    scene.callFunc("fixtureReady")
    rail = scene.callFunc("fixtureRead").rail
    state = rail.callFunc("fixtureRead")
    check(state.task.request.type = "getLiveStatusForLogins" and state.task.request.params.logins.Count() = 4, "the only rail request checks the bounded existing local collection")
    check(state.items.Count() = 2 and state.items[0].itemData.login = "live_pin" and state.items[1].itemData.login = "offline_pin", "pending lookup shows only pins in stable pin order")
    check(rail.findNode("pinnedHeader").visible and not rail.findNode("liveHeader").visible, "pending lookup has a dedicated pinned header and no misleading Live header")
    state.task.response = { live_recent: true, live_pin: true, offline: false }
    state = rail.callFunc("fixtureRead")
    check(state.items.Count() = 3 and state.items[2].itemData.login = "live_recent", "Live includes only confirmed unpinned history without duplicating a live pin")
    check(state.items[0].isLive and not state.items[1].isLive and state.items[2].isLive, "live dots remain independent of local pins")
    check(RW_Load().Count() = 3, "offline unpinned history remains in storage")
    check(rail.findNode("pinnedHeader").text = "PINNED" and rail.findNode("liveHeader").text = "LIVE", "both groups have dedicated localized text headers")
    assertSidebarGeometry(rail)
    state.task.response = {}
    check(rail.callFunc("fixtureRead").items.Count() = 2 and not rail.findNode("liveHeader").visible, "failed or empty lookup hides Live while preserving offline pins")
    state.task.response = { live_recent: "true", offline: 1 }
    check(rail.callFunc("fixtureRead").items.Count() = 2, "malformed live values do not label history Live")
    registry_delete("pins", RW_Section())
    rail.callFunc("buildItems")
    check(not rail.hasItems and rail.callFunc("fixtureRead").task <> invalid, "history-only pending rail still polls even with no visible items")
    rail.callFunc("fixtureRead").task.response = { live_recent: true }
    check(rail.hasItems and not rail.findNode("pinnedHeader").visible and rail.findNode("liveHeader").visible, "Live-only rail recovers after a successful poll")
    press("left")
    dialog = openSidebarMenu(rail)
    rail.callFunc("fixtureRead").task.response = {}
    check(rail.hasItems and rail.callFunc("fixtureRead").items[0].itemData.login = "live_recent", "a poll leaves an open menu's channel selection stable")
    dialog.wasClosed = true
    check(not rail.hasItems and not rail.itemHasFocus and scene.callFunc("fixtureRead").active.isInFocusChain(), "menu dismissal applies the pending failed lookup and returns empty-rail focus")
    check(RW_Load().Count() = 3, "dismissing a menu never removes offline history")
    ' Both groups, twelve candidates and both navigation bounds.
    registry_delete("history", RW_Section())
    for i = 11 to 0 step -1
        RW_Add(entry("scroll_" + i.ToStr(), i))
    end for
    result = RW_SetPinned(entry("scroll_0", 0), true)
    rail.callFunc("buildItems")
    live = {}
    for i = 0 to 11
        live["scroll_" + i.ToStr()] = true
    end for
    rail.callFunc("fixtureRead").task.response = live
    press("left")
    for i = 1 to 11
        press("down")
        assertSidebarGeometry(rail)
    end for
    check(rail.callFunc("fixtureRead").index = 11, "navigation reaches the bounded last channel")
    rail.callFunc("fixtureKey", "down")
    check(rail.callFunc("fixtureRead").index = 11, "Down at the last channel remains bounded")
    for i = 1 to 11
        rail.callFunc("fixtureKey", "up")
    end for
    check(not rail.callFunc("fixtureKey", "up") and rail.callFunc("fixtureRead").index = 0, "Up at the first channel returns navigation to Hero")
    assertSidebarGeometry(rail)
end sub

sub assertSidebarGeometry(rail as object)
    state = rail.callFunc("fixtureRead")
    lastBottom = 0
    for each item in state.items
        if item.visible
            y = item.translation[1]
            check(item.translation[0] = 7 and y >= 51 and y + 64 <= 640 and y >= lastBottom, "visible full rings fit nonnegative HD safe bounds without overlap")
            check(item.findNode("selectionIndicator").width = 64 and item.findNode("avatar").width = 54 and item.findNode("avatar").translation[0] = 3, "grouping preserves the concentric 64 ring and 54 face")
            check(item.findNode("pinBadge") = invalid, "PINNED text never covers an avatar or ring")
            for each id in ["pinnedHeader", "liveHeader"]
                header = rail.findNode(id)
                if header.visible then check(y >= header.translation[1] + header.height or y + 64 <= header.translation[1], "section headers own space outside every visible ring")
            end for
            lastBottom = y + 64
        end if
    end for
    check(state.items[state.index].visible, "the selected channel stays visible through section scrolling")
end sub

sub testSidebarRemoval(scene as object)
    for i = 2 to 0 step -1
        RW_Add(entry("remove_" + i.ToStr(), i))
        result = RW_SetPinned(entry("remove_" + i.ToStr(), i), true)
    end for
    scene.callFunc("fixtureReady")
    rail = scene.callFunc("fixtureRead").rail
    press("left")
    press("down")
    oldTask = rail.callFunc("fixtureRead").task
    dialog = openSidebarMenu(rail)
    check(dialog.title = "remove_1" and dialog.buttons[1] = "Remove from sidebar", "Options identifies the selected channel and individual removal")
    check(dialog.buttons[0] = "Unpin from sidebar" and dialog.buttons[2] = "Cancel", "menu retains explicit local pin and cancel actions")
    check(Instr(1, dialog.message[0], "Twitch") > 0, "removal explains its local scope")
    ' Polls may reorder or hide the underlying selection; the menu owns a copy.
    oldTask.response = { remove_0: true, remove_1: true, remove_2: true }
    dialog.buttonSelected = 1
    state = rail.callFunc("fixtureRead")
    check(not RW_IsPinned("remove_1") and RW_Load().Count() = 2, "removal deletes the selected pin and history entry")
    check(state.items.Count() = 2 and state.index = 1 and state.items[1].itemData.login = "remove_2" and state.items[1].focused, "removal keeps the next neighbor focused")
    check(rail.itemHasFocus and rail.isInFocusChain() and scene.dialog = invalid, "menu closes and returns native focus to the rail")
    dialog.buttonSelected = 0
    rail.callFunc("fixtureStaleDialog", dialog)
    check(not RW_IsPinned("remove_1") and state.items.Count() = 2, "closed dialog events cannot restore the removed channel")
    oldTask.response = { remove_1: true }
    rail.callFunc("fixtureStale", oldTask)
    check(rail.callFunc("fixtureRead").items.Count() = 2, "late polls cannot resurrect a removed item")
    press("back")
    rail.callFunc("fixtureRefresh")
    check(rail.callFunc("fixtureRead").items.Count() = 2, "poll refresh reloads removal from registry")
    scene.callFunc("fixtureReady")
    rail = scene.callFunc("fixtureRead").rail
    check(rail.callFunc("fixtureRead").items.Count() = 2 and not RW_IsPinned("remove_1"), "new component instance preserves removal after restart")
    RW_Add(entry("remove_1", 1))
    rail.callFunc("buildItems")
    rail.callFunc("fixtureRead").task.response = { remove_1: true }
    check(RW_Load()[0].login = "remove_1" and rail.callFunc("fixtureRead").items.Count() = 3 and not RW_IsPinned("remove_1"), "explicitly watching later readds ordinary unpinned history")
    press("left")
    dialog = openSidebarMenu(rail)
    rail.callFunc("fixtureKey", "down")
    dialog.buttonSelected = 0
    check(not RW_IsPinned("remove_0") and RW_IsPinned("remove_2"), "an open menu acts on its immutable channel even if underlying selection changes")
    result = RW_SetPinned(entry("remove_0", 0), true)
    rail.callFunc("buildItems")
    rail.callFunc("fixtureKey", "up")
    dialog = openSidebarMenu(rail)
    dialog.wasClosed = true
    check(rail.callFunc("fixtureRead").dialog = invalid and rail.isInFocusChain() and RW_LoadPins().Count() = 2, "Back closes only the menu without changing local state")
    press("ok")
    check(scene.callFunc("fixtureRead").active.contentRequested.streamerId = "0", "first OK after menu dismissal opens the selected neighbor with metadata")
    press("back")
    ' Remove every remaining item, including a live history-only channel.
    press("left")
    for attempt = 0 to 3
        if rail.hasItems
            dialog = openSidebarMenu(rail)
            dialog.buttonSelected = 1
        end if
    end for
    check(not rail.itemHasFocus and scene.callFunc("fixtureRead").active.isInFocusChain(), "removing the last icon returns focus to the originating page")
    check(RW_LoadPins().Count() = 0 and RW_Load().Count() = 0 and rail.callFunc("fixtureRead").task = invalid, "final removal clears local lists and cancels the task")
    print "FIXTURE_KEY:back"
    elapsed = createObject("roTimespan")
    while not scene.exitApp and elapsed.TotalMilliseconds() < 3000
        wait(25, m.port)
    end while
    check(scene.exitApp, "first Back after empty-rail focus return follows normal Hero routing")
end sub

sub testSidebarMenuAccount(scene as object)
    seedAccountChange(true)
    result = RW_SetPinned(entry("alice_recent", 2), true)
    scene.callFunc("fixtureReady")
    rail = scene.callFunc("fixtureRead").rail
    press("left")
    dialog = openSidebarMenu(rail)
    check(rail.findNode("captionHint").text = "Press * for sidebar actions", "the focused rail advertises local Options actions")
    alicePins = registry_read("pins", RW_Section())
    aliceHistory = registry_read("history", RW_Section())
    anonPins = registry_read("pins", "$default$_recently_watched")
    signOutAccount()
    dialog.buttonSelected = 1
    check(registry_read("pins", "alice_recently_watched") = alicePins and registry_read("history", "alice_recently_watched") = aliceHistory, "delayed removal never writes the old account")
    check(registry_read("pins", RW_Section()) = anonPins and RW_Load().Count() = 0, "delayed removal never writes the new anonymous account")
    check(rail.callFunc("fixtureRead").accountSection = RW_Section() and rail.callFunc("fixtureRead").items[0].itemData.login = "anon_saved", "stale menu rebuilds the current account before restoring focus")
    oldDialog = openSidebarMenu(rail)
    scene.callFunc("fixtureRead").validation.response = { validationState: "invalid" }
    rail.callFunc("buildItems")
    currentDialog = openSidebarMenu(rail)
    oldDialog.buttonSelected = 1
    rail.callFunc("fixtureStaleDialog", oldDialog)
    activeDialog = rail.callFunc("fixtureRead").dialog
    sameDialog = false
    if activeDialog <> invalid then sameDialog = activeDialog.isSameNode(currentDialog)
    check(RW_IsPinned("anon_saved") and sameDialog, "a late closed dialog cannot act on a newer menu")
    if not sameDialog or not RW_IsPinned("anon_saved") then return
    section = RW_Section()
    set_setting("active_user", "alice")
    check(not RW_Remove(entry("alice_recent", 2), section), "registry removal rejects a mismatched immutable account section")
    check(registry_read("pins", "alice_recently_watched") = alicePins, "utility account guard prevents cross-account removal")
    check(RW_SetPinned(entry("anon_saved", 1), false, section) = "stale", "registry pin action rejects a mismatched immutable account section")
    check(not RW_Remove({ login: "../bad" }, RW_Section()) and registry_read("pins", "alice_recently_watched") = alicePins, "malformed removal identities cannot change native registry data")
    set_setting("active_user", "$default$")
    timer = rail.callFunc("fixtureRead").timer
    task = rail.callFunc("fixtureRead").task
    rail.callFunc("onDestroy")
    currentDialog.buttonSelected = 1
    rail.callFunc("fixtureStaleDialog", currentDialog)
    check(RW_IsPinned("anon_saved") and rail.callFunc("fixtureRead").dialog = invalid and scene.dialog = invalid, "disposal clears menu observers and rejects queued dialog actions")
    check(timer.control = "stop" and task.control = "stop", "menu disposal also stops timer and task")
    ' Real OAuth invalidation while a dialog owns focus, populated and empty.
    for each anonymousHasPin in [true, false]
        seedAccountChange(anonymousHasPin)
        result = RW_SetPinned(entry("alice_recent", 2), true)
        scene.callFunc("fixtureReady")
        rail = scene.callFunc("fixtureRead").rail
        press("left")
        dialog = openSidebarMenu(rail)
        oldTask = rail.callFunc("fixtureRead").task
        scene.callFunc("fixtureRead").validation.response = { validationState: "invalid" }
        check(scene.dialog = invalid and rail.callFunc("fixtureRead").accountSection = RW_Section(), "OAuth account refresh closes the old menu and rebuilds anonymous state")
        dialog.buttonSelected = 1
        rail.callFunc("fixtureStaleDialog", dialog)
        oldTask.response = { alice_recent: true }
        rail.callFunc("fixtureStale", oldTask)
        check(ParseJson(registry_read("pins", "alice_recently_watched")).Count() = 1, "OAuth cleanup rejects late menu and task responses without changing Alice's pins")
        if anonymousHasPin
            check(rail.itemHasFocus and rail.isInFocusChain() and RW_IsPinned("anon_saved"), "OAuth menu cleanup preserves populated anonymous rail focus")
        else
            check(not rail.itemHasFocus and scene.callFunc("fixtureRead").active.isInFocusChain(), "OAuth menu cleanup returns focus when the anonymous rail is empty")
        end if
    end for
end sub

function openSidebarMenu(rail as object) as object
    print "FIXTURE_KEY:options"
    elapsed = createObject("roTimespan")
    while rail.callFunc("fixtureRead").dialog = invalid and elapsed.TotalMilliseconds() < 3000
        wait(25, m.port)
    end while
    dialog = rail.callFunc("fixtureRead").dialog
    check(dialog <> invalid, "native Options opens the local sidebar actions menu")
    return dialog
end function
