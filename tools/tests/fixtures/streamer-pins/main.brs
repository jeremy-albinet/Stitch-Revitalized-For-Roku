sub main()
    m.assertions = 0
    m.failures = 0
    m.port = createObject("roMessagePort")
    screen = createObject("roSGScreen")
    screen.setMessagePort(m.port)
    m.global = screen.getGlobalNode()
    setConstants()
    scene = screen.createScene("FixtureScene")
    m.scene = scene
    screen.show()
    if "__FIXTURE_CASE__" = "sections"
        testSidebarSections(scene)
    else if "__FIXTURE_CASE__" = "removal"
        testSidebarRemoval(scene)
    else if "__FIXTURE_CASE__" = "menuaccount"
        testSidebarMenuAccount(scene)
    else if "__FIXTURE_CASE__" = "account"
        testAccountChanges(scene)
    else if "__FIXTURE_CASE__" = "storage"
        testStorage()
    else if "__FIXTURE_CASE__" = "navigation"
        testRailAndPage(scene)
    else
        testOfflinePage(scene)
    end if
    scene.callFunc("fixtureCleanup")
    screen.close()
    if m.failures = 0 then print "__PASS_MARKER__:"; m.assertions; " assertions"
end sub

sub seedAccountChange(anonymousHasPin as boolean, aliceHasPin = false as boolean)
    set_setting("active_user", "$default$")
    registry_delete("pins", RW_Section())
    registry_delete("history", RW_Section())
    if anonymousHasPin then result = RW_SetPinned(entry("anon_saved", 1), true)
    if aliceHasPin then result = RW_SetPinned(entry("alice_recent", 2), true)
    set_setting("active_user", "alice")
    registry_delete("pins", RW_Section())
    registry_delete("history", RW_Section())
    set_user_setting("access_token", "fixture-token")
    set_user_setting("device_code", "fixture-device")
    set_user_setting("ChatFontSize", "14")
    RW_Add(entry("alice_recent", 2))
    if aliceHasPin then result = RW_SetPinned(entry("alice_recent", 2), true)
end sub

sub testAccountChanges(scene as object)
    ' Valid validation must leave a focused Alice rail and its normal action alone.
    seedAccountChange(true)
    scene.callFunc("fixtureReady", true)
    rail = scene.callFunc("fixtureRead").rail
    press("left")
    original = rail.callFunc("fixtureRead").items[0]
    scene.callFunc("fixtureRead").validation.response = { validationState: "valid" }
    check(get_setting("active_user") = "alice" and rail.callFunc("fixtureRead").items[0].isSameNode(original), "valid OAuth validation retains Alice's focused rail snapshot")
    press("options")
    check(RW_IsPinned("alice_recent") and rail.itemHasFocus and rail.isInFocusChain(), "same-account Options still pins Alice's selected channel")
    check(ParseJson(registry_read("pins", "$default$_recently_watched")).Count() = 1, "normal Alice Options leaves anonymous pins untouched")

    ' Exercise the guard independently of the automatic refresh, for both add
    ' and remove. The timer deliberately skips the focused stale snapshot.
    for each alreadyPinned in [false, true]
        seedAccountChange(true, alreadyPinned)
        scene.callFunc("fixtureReady", true)
        rail = scene.callFunc("fixtureRead").rail
        press("left")
        aliceItem = rail.callFunc("fixtureRead").items[0]
        aliceBefore = registry_read("pins", RW_Section())
        anonBefore = registry_read("pins", "$default$_recently_watched")
        signOutAccount()
        rail.callFunc("fixtureRefresh")
        check(rail.callFunc("fixtureRead").accountSection = "alice_recently_watched" and rail.itemHasFocus, "account switch can leave a focused snapshot stale until its Options guard runs")
        check(rail.callFunc("fixtureOptions"), "stale account Options is consumed")
        state = rail.callFunc("fixtureRead")
        check(state.accountSection = RW_Section() and not state.items[0].isSameNode(aliceItem), "stale account Options rebuilds before reading a pin action")
        check(registry_read("pins", "$default$_recently_watched") = anonBefore and registry_read("pins", "alice_recently_watched") = aliceBefore, "stale pin and unpin actions cannot write either account's pins")
        check(rail.itemHasFocus and rail.isInFocusChain() and state.items[0].focused, "a guarded rebuild preserves focus when the new account has channels")
    end for

    seedAccountChange(false)
    scene.callFunc("fixtureReady", true)
    rail = scene.callFunc("fixtureRead").rail
    press("left")
    signOutAccount()
    check(rail.callFunc("fixtureOptions"), "stale Options is consumed even when the new account is empty")
    check(not rail.hasItems and not rail.itemHasFocus and scene.callFunc("fixtureRead").active.isInFocusChain(), "guarded empty rebuild returns focus to the originating page")
    check(RW_LoadPins().Count() = 0, "guarded empty rebuild never pins Alice into anonymous storage")

    ' Complete the real pending validation Task after entering Alice's rail.
    for each anonymousHasPin in [true, false]
        seedAccountChange(anonymousHasPin)
        scene.callFunc("fixtureReady", true)
        rail = scene.callFunc("fixtureRead").rail
        press("left")
        state = rail.callFunc("fixtureRead")
        oldTask = state.task
        check(state.accountSection = "alice_recently_watched" and state.items[0].itemData.login = "alice_recent" and rail.itemHasFocus, "pending validation begins with the actual Alice rail selected")
        prior = scene.callFunc("fixtureRead").active
        scene.callFunc("fixtureRead").validation.response = { validationState: "invalid" }
        state = rail.callFunc("fixtureRead")
        check(get_setting("active_user") = "$default$" and state.accountSection = RW_Section(), "actual OAuth invalidation signs out and immediately refreshes the rail account")
        check(oldTask.control = "stop" and scene.callFunc("fixtureRead").active.isSameNode(prior), "automatic signout cancels old rail work without replacing the current page")
        check(registry_read("access_token", "alice") = invalid and registry_read("ChatFontSize", "alice") = "14", "automatic signout preserves account settings while removing credentials")
        if anonymousHasPin
            check(state.items[0].itemData.login = "anon_saved" and state.items[0].focused and rail.itemHasFocus and rail.isInFocusChain(), "automatic signout keeps focus on the populated anonymous rail")
            press("options")
            check(not RW_IsPinned("alice_recent") and RW_LoadPins().Count() = 0, "Options after invalidation acts on the displayed anonymous pin and never pins Alice")
        else
            check(not rail.hasItems and not rail.itemHasFocus and prior.isInFocusChain(), "automatic signout to an empty anonymous rail returns focus to the page")
        end if
    end for

    ' Explicit logout keeps its existing account refresh and page focus behavior.
    seedAccountChange(true, true)
    scene.callFunc("fixtureReady", true)
    rail = scene.callFunc("fixtureRead").rail
    press("left")
    signOutAccount()
    scene.callFunc("fixtureLogout")
    state = scene.callFunc("fixtureRead")
    check(state.active.id = "Settings" and state.active.isInFocusChain() and not rail.itemHasFocus, "explicit logout still opens Settings and releases rail focus")
    check(rail.callFunc("fixtureRead").accountSection = RW_Section() and RW_IsPinned("anon_saved"), "explicit logout still refreshes the anonymous rail and preserves its pins")
    check(ParseJson(registry_read("pins", "alice_recently_watched")).Count() = 1, "explicit logout preserves Alice's independent pin storage")
end sub

sub testStorage()
    set_setting("active_user", "$default$")
    check(RW_Section() = "$default$_recently_watched" and RW_LoadPins().Count() = 0, "anonymous pins start empty in the history account scope")
    for each raw in ["garbage", "{}", "null", "[null,3,true," + Chr(34) + "bad" + Chr(34) + "]"]
        registry_write("pins", raw, RW_Section())
        check(RW_LoadPins().Count() = 0, "corrupt or wrongly typed pin data loads safely")
    end for
    oversized = []
    for i = 0 to 19
        oversized.push(entry("loaded_" + i.ToStr(), i))
    end for
    registry_write("pins", FormatJson(oversized), RW_Section())
    check(RW_LoadPins().Count() = 12 and RW_LoadPins()[11].login = "loaded_11", "load bounds oversized stored arrays without changing order")
    dirty = [
        { login: " Mixed_Case ", displayName: "Mixed", iconUrl: "pkg:/images/default_banner.png", id: "123", access_token: "must-not-persist" },
        { login: "MIXED_CASE", displayName: "Duplicate" }, { login: "bad-login" }, { login: "" }, { login: 12 },
        { login: "second", displayName: 3, iconUrl: "http://untrusted/", id: "not-numeric" }
    ]
    registry_write("pins", FormatJson(dirty), RW_Section())
    pins = RW_LoadPins()
    check(pins.Count() = 2 and pins[0].login = "mixed_case" and pins[0].displayName = "Mixed", "load filters malformed entries and deduplicates normalized logins in order")
    check(pins[0].id = "123" and not pins[0].DoesExist("access_token"), "load retains numeric IDs and only channel metadata")
    check(pins[1].displayName = "second" and pins[1].iconUrl = "" and pins[1].id = "", "bad optional metadata falls back safely")
    long = { login: "bounded", displayName: String(100, "x"), iconUrl: "https://" + String(600, "x"), id: String(40, "1") }
    check(RW_SetPinned(long, true) = "pinned", "bounded valid login can be pinned without optional metadata")
    check(Len(RW_LoadPins()[0].displayName) = 64 and RW_LoadPins()[0].iconUrl = "" and RW_LoadPins()[0].id = "", "pin metadata has explicit size bounds")
    check(RW_SetPinned({ login: "../bad" }, true) = "invalid" and RW_SetPinned(12, true) = "invalid", "invalid pin identities never reach storage")
    for i = 0 to 20
        RW_Add(entry("recent_" + i.ToStr(), i))
    end for
    RW_Add({ login: "RECENT_20", displayName: "Newest" })
    check(RW_Load().Count() = RW_MaxItems() and RW_Load()[0].displayName = "Newest", "history retains its cap and case-insensitive move-to-front deduplication")
    rail = RW_LoadRail()
    check(rail.Count() = 12 and rail[0].pinned and rail[0].login = "bounded" and rail[3].login = "recent_20", "pins precede recent history under the original rail cap")
    check(RW_IsPinned("MIXED_CASE") and RW_LoadPins().Count() = 3, "pins survive history eviction and case-insensitive lookup")
    check(RW_SetPinned({ login: "mixed_case" }, true) = "pinned" and RW_LoadPins()[1].login = "mixed_case", "repeated add preserves pin order without duplicates")
    RW_Add({ login: "mixed_case" })
    rail = RW_LoadRail()
    count = 0
    for each item in rail
        if item.login = "mixed_case" then count += 1
    end for
    check(count = 1 and rail[0].login = "bounded", "watching a pin neither duplicates nor reorders it")
    for i = 0 to 8
        result = RW_SetPinned(entry("pin_" + i.ToStr(), i), true)
    end for
    before = registry_read("pins", RW_Section())
    check(RW_LoadPins().Count() = 12 and RW_SetPinned({ login: "overflow" }, true) = "limit", "full pin list rejects an extra pin explicitly")
    check(before = registry_read("pins", RW_Section()) and RW_LoadRail().Count() = 12, "limit never evicts a pin or writes partial data")
    check(RW_SetPinned({ login: "PIN_8" }, false) = "unpinned" and not RW_IsPinned("pin_8"), "remove normalizes login and persists the removal")
    check(RW_SetPinned({ login: "overflow" }, true) = "pinned" and RW_LoadPins()[0].login = "overflow", "removal frees a slot for a new pin")
    saved = RW_LoadPins()[0]
    saved.login = "local_mutation"
    check(RW_LoadPins()[0].login = "overflow", "a fresh load reads persisted JSON rather than a mutable cached list")
    nativeSection = createObject("roRegistrySection", RW_Section())
    check(ParseJson(nativeSection.Read("pins")).Count() = 12, "the actual config writer flushed the pins key into the native registry")
    set_setting("active_user", "alice")
    set_user_setting("ChatFontSize", "14")
    set_user_setting("device_code", "fixture-device")
    set_user_setting("access_token", "fixture-token")
    check(RW_LoadPins().Count() = 0, "another account cannot see anonymous pins")
    result = RW_SetPinned(entry("alice_pin", 42), true)
    signOutAccount()
    check(get_setting("active_user") = "$default$" and RW_LoadPins().Count() = 12, "logout restores anonymous pins without combining accounts")
    check(registry_read("access_token", "alice") = invalid and registry_read("ChatFontSize", "alice") = "14", "sign-out keeps preferences while removing credentials")
    set_setting("active_user", "alice")
    check(RW_LoadPins().Count() = 1 and RW_LoadPins()[0].login = "alice_pin", "signing back in restores the account's own pins")
    set_setting("active_user", "$default$")
    registry_delete("pins", RW_Section())
    registry_delete("history", RW_Section())
end sub

sub testRailAndPage(scene as object)
    for i = 9 to 0 step -1
        RW_Add(entry("channel_" + i.ToStr(), i + 100))
    end for
    scene.callFunc("fixtureReady", true)
    rail = scene.callFunc("fixtureRead").rail
    pause(300)
    press("left")
    check(rail.itemHasFocus and rail.isInFocusChain() and rail.findNode("captionHint").text = "Press * for sidebar actions", "native Left enters the rail with a discoverable localized Options hint")
    for i = 1 to 9
        press("down")
    end for
    state = rail.callFunc("fixtureRead")
    oldTask = state.task
    check(state.index = 9 and state.items[9].visible and state.items[9].focused, "native Down scrolls to the last recent channel")
    press("options")
    state = rail.callFunc("fixtureRead")
    pinned = state.items[0]
    check(RW_IsPinned("channel_9") and state.index = 0 and pinned.itemData.login = "channel_9" and pinned.focused, "native Options persists the pin and retains focus on that channel after sorting")
    check(rail.findNode("pinnedHeader").visible and rail.findNode("pinnedHeader").text = "PINNED", "the pinned avatar has a persistent code-native PINNED indicator")
    check(rail.findNode("captionHint").text = "Press * for sidebar actions" and rail.findNode("caption").translation[1] = pinned.translation[1] + 12, "pinning changes the hint without moving the centered tooltip")
    header = rail.findNode("pinnedHeader")
    check(header.translation[1] >= 0 and header.translation[1] + header.height <= pinned.translation[1], "the PINNED indicator owns space outside the 64 by 64 avatar footprint")
    check(pinned.findNode("selectionIndicator").width = 64 and pinned.findNode("avatar").translation[0] = 3, "pinning preserves the existing concentric ring and avatar geometry")
    oldTask.response = { channel_9: false }
    rail.callFunc("fixtureStale", oldTask)
    check(oldTask.control = "stop" and pinned.isLive, "removed task callbacks and already queued stale responses cannot change rebuilt items")
    state.task.response = { channel_9: true }
    check(pinned.isLive and pinned.findNode("liveDot").visible and rail.findNode("pinnedHeader").visible, "live status and persistent PIN remain independent")
    state.task.response = {}
    check(not pinned.isLive and rail.findNode("pinnedHeader").visible, "failed or offline status preserves a local pin")
    set_setting("active_user", "alice")
    state.task.response = { channel_9: true }
    check(not pinned.isLive, "a response from a previous account cannot update the visible pin state")
    set_setting("active_user", "$default$")
    rail.callFunc("fixtureRefresh")
    check(rail.callFunc("fixtureRead").items[0].isSameNode(pinned), "periodic refresh does not rebuild a focused rail")
    live = {}
    for i = 0 to 9
        live["channel_" + i.ToStr()] = true
    end for
    state.task.response = live
    press("options")
    state = rail.callFunc("fixtureRead")
    check(not RW_IsPinned("channel_9") and state.index = 9 and state.items[9].focused and state.items[9].visible, "unpin returns a recent channel to history order while keeping it focused and visible")
    press("options")
    press("back")
    check(not rail.itemHasFocus and scene.callFunc("fixtureRead").active.isInFocusChain(), "native rail Back returns focus to the originating page")
    press("left")
    press("ok")
    page = scene.callFunc("fixtureRead").active
    check(page.id = "ChannelPage" and page.contentRequested.streamerLogin = "channel_9" and page.contentRequested.streamerId = "109", "pinned OK opens one ChannelPage with retained login and broadcaster metadata")
    task = page.callFunc("fixtureRead").task
    task.response = { streamerId: "109", description: "", followerCount: 1, profileImageUrl: "pkg:/images/default_banner.png", isLive: true, liveTitle: "Live", liveViewersCount: 4, videoShelves: [] }
    pause(300)
    check(page.callFunc("fixtureRead").rowlist.isInFocusChain() and scene.callFunc("fixtureRead").depth = 1, "pins keep initial native RowList focus and a single reusable backstack entry")
    press("options")
    check(not RW_IsPinned("channel_9") and Instr(1, page.findNode("pinHint").text, "12") > 0, "ChannelPage Options unpins locally and reveals the bounded pin action")
    press("ok")
    check(page.playContent and page.contentSelected <> invalid and page.contentSelected.contentType = "LIVE", "first native OK after Options still selects the LIVE card")
    press("back")
    check(scene.callFunc("fixtureRead").active.id = "PriorPage" and scene.callFunc("fixtureRead").depth = 0 and page.callFunc("fixtureRead").disposed, "one native Back restores the prior page and disposes the ChannelPage")
    state = rail.callFunc("fixtureRead")
    check(state.items[state.index].itemData.pinned <> true, "hero back routing refreshes the visible rail immediately after a profile pin change")
end sub

sub testOfflinePage(scene as object)
    RW_Add(entry("channel_9", 109))
    scene.callFunc("fixtureReady", true)
    rail = scene.callFunc("fixtureRead").rail
    oldTask = rail.callFunc("fixtureRead").task
    ' Reopen an offline channel: the profile action remains available with no rows.
    press("left")
    press("ok")
    page = scene.callFunc("fixtureRead").active
    page.callFunc("fixtureRead").task.response = { streamerId: "109", description: "", followerCount: 1, isLive: false, videoShelves: [] }
    press("options")
    check(RW_IsPinned("channel_9") and page.findNode("status").state = "empty", "an offline channel with no media can be pinned through native Options")
    press("options")
    for i = 0 to 11
        result = RW_SetPinned(entry("limit_" + i.ToStr(), i), true)
    end for
    print "FIXTURE_KEY:options"
    elapsed = createObject("roTimespan")
    while Instr(1, page.findNode("pinHint").text, "Pin limit reached") = 0 and elapsed.TotalMilliseconds() < 3000
        wait(25, m.port)
    end while
    check(Instr(1, page.findNode("pinHint").text, "Pin limit reached (12)") > 0 and not RW_IsPinned("channel_9"), "native profile Options explains the cap without replacing another pin or changing focus")
    registry_delete("pins", RW_Section())
    result = RW_SetPinned(entry("channel_9", 109), true)
    press("back")
    ' A new rail instance must load the persisted pin even with history removed.
    registry_delete("history", RW_Section())
    scene.callFunc("fixtureReady")
    rail = scene.callFunc("fixtureRead").rail
    check(rail.hasItems and rail.callFunc("fixtureRead").items.Count() = 1 and rail.findNode("pinnedHeader").visible and not rail.callFunc("fixtureRead").items[0].isLive, "recreating the rail reloads an offline pin after history eviction")
    press("left")
    press("options")
    check(not rail.hasItems and not rail.itemHasFocus and scene.callFunc("fixtureRead").active.isInFocusChain(), "unpinning the final history-free pin returns focus to the page without trapping the user")
    check(rail.callFunc("fixtureRead").task = invalid and RW_LoadPins().Count() = 0, "empty rail cancels its old request and persists the removal")
    oldTask.response = { channel_9: true }
    rail.callFunc("fixtureStale", oldTask)
    check(not rail.hasItems and rail.callFunc("fixtureRead").items.Count() = 0, "an empty rebuilt rail ignores late responses from removed items")
    timer = rail.callFunc("fixtureRead").timer
    rail.callFunc("onDestroy")
    check(timer.control = "stop" and rail.callFunc("fixtureRead").disposed, "permanent rail cleanup stops its timer and disposes items")
end sub

function entry(login as string, id as integer) as object
    return { login: login, displayName: login, iconUrl: "pkg:/images/default_banner.png", id: id.ToStr() }
end function

sub press(key as string)
    before = m.scene.callFunc("fixtureRead")
    rail = before.rail
    wasRail = rail.itemHasFocus
    index = rail.callFunc("fixtureRead").index
    login = ""
    if key = "options"
        if wasRail
            login = rail.callFunc("fixtureRead").items[index].itemData.login
        else
            login = before.active.contentRequested.streamerLogin
        end if
        wasPinned = RW_IsPinned(login)
    end if
    print "FIXTURE_KEY:"; key
    elapsed = createObject("roTimespan")
    received = false
    while not received and elapsed.TotalMilliseconds() < 3000
        wait(25, m.port)
        state = m.scene.callFunc("fixtureRead")
        if key = "left"
            received = rail.itemHasFocus and rail.isInFocusChain()
        else if key = "down"
            received = rail.callFunc("fixtureRead").index = index + 1
        else if key = "options"
            if wasRail
                dialog = rail.callFunc("fixtureRead").dialog
                if dialog <> invalid then dialog.buttonSelected = 0
            end if
            received = RW_IsPinned(login) <> wasPinned
        else if key = "back"
            if wasRail
                received = not rail.itemHasFocus
            else
                received = not state.active.isSameNode(before.active)
            end if
        else if key = "ok"
            if wasRail
                received = state.active.id = "ChannelPage"
            else
                received = state.active.contentSelected <> invalid
            end if
        end if
    end while
    check(received, "native " + key + " has an observed result before the next key")
end sub

sub pause(duration as integer)
    elapsed = createObject("roTimespan")
    while elapsed.TotalMilliseconds() < duration
        wait(25, m.port)
    end while
end sub

sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_PINS_FAIL:"; message
    end if
end sub
