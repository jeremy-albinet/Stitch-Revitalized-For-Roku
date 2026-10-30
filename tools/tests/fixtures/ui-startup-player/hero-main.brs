' Whole-app startup and navigation fixture. The production heroScene, MenuBar,
' recent rail, StatusPanel and Following page run unchanged; remote keys are
' dispatched by the engine through the real focus chain (see key-driver.js).
sub main()
    m.assertions = 0
    m.failures = 0
    m.exitRequested = false
    m.port = createObject("roMessagePort")
    screen = createObject("roSGScreen")
    screen.setMessagePort(m.port)
    m.global = screen.getGlobalNode()
    setConstants()
    ' Fixture inputs: a first launch with no device identity or account, an
    ' already-seen release (no What's New dialog) and no recent channels.
    m.global.addFields({ priorExitReason: "", fixtureRegistry: { "app/last_seen_version": "999.0.0" }, fixtureHistory: [] })
    ' Same order as production main: create, show, observe exit, focus scene.
    m.scene = screen.createScene("HeroScene")
    screen.show()
    m.scene.observeField("exitApp", m.port)
    m.scene.setFocus(true)

    testFirstLaunchFailure()
    testRetryAndGate()
    testLateCallbacks()
    testRecoverySuccess()
    testRailBackAndExit()

    screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_UI_FAIL:"; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub testFirstLaunchFailure()
    r = hero()
    first = r.task
    check(first <> invalid and r.pending and first.request.type = "getRendezvouzToken", "first launch starts one real rendezvous request")
    check(r.status.state = "loading" and r.active = invalid, "first launch shows the connecting state, not a blank page")
    check(get_setting("active_user") = "$default$" and get_user_setting("device_code") = invalid, "first launch is anonymous with no identity yet")

    press("up")
    waitUntil("menuFocus", true)
    r = hero()
    check(r.menu.isInFocusChain() and r.pending and r.status.state = "loading", "Up reaches the menu while the first attempt is connecting")

    ' The menu's Settings icon resolves to the actual openPage("Settings").
    openTab("Settings")
    r = hero()
    settings = r.active
    check(settings <> invalid and settings.id = "Settings" and settings.isInFocusChain(), "Settings opens offline while the attempt continues")
    check(r.status.state = "hidden" and r.pending and first.isSameNode(r.task), "opening Settings neither cancels nor repeats the pending attempt")

    first.response = invalid
    waitUntil("pending", false)
    r = hero()
    check(r.failures = 1 and r.task = invalid and first.control = "stop", "a failed attempt stops its task and clears pending")
    check(r.status.state = "hidden" and settings.isSameNode(r.active) and settings.isInFocusChain(), "a late failure keeps Settings open and focused")

    press("up")
    waitUntil("menuFocus", true)
    openTab("Following")
    r = hero()
    check(r.active = invalid and settings.getParent() = invalid, "a content tab without an identity discards the open page")
    check(r.status.state = "error" and r.status.actions.count() = 2 and r.status.isInFocusChain(), "the identity gate shows Try again and Settings with focus")
    check(not r.pending and r.task = invalid and r.menu.activeItem = "", "the gate does not retry by itself after a failure")
    m.firstMessage = r.status.message
end sub

sub testRetryAndGate()
    r = hero()
    press("ok")
    waitUntil("pending", true)
    r = hero()
    second = r.task
    check(second <> invalid and second.request.type = "getRendezvouzToken" and r.status.state = "loading" and not r.status.hasActions, "OK on Try again starts exactly one new request")
    check(r.status.isInFocusChain(), "the loading panel keeps focus while the request is pending")
    press("ok")
    settle(300)
    r.status.actionSelected = 0
    settle(100)
    r = hero()
    check(r.pending and r.task.isSameNode(second), "repeated OK or a stale Try again while pending starts no duplicate request")

    second.response = { device_code: "" }
    waitUntil("status", "error")
    r = hero()
    check(r.failures = 2 and r.status.message = m.firstMessage and r.status.isInFocusChain(), "an empty device code is a failure with the same guidance")

    ' The panel's own Settings action works offline and replaces the panel.
    press("down")
    settle(200)
    press("ok")
    waitUntil("active", "Settings")
    r = hero()
    m.settings = r.active
    check(m.settings <> invalid and m.settings.isInFocusChain() and r.menu.activeItem = "Settings", "the panel Settings action opens Settings with focus")
    check(r.status.state = "hidden" and r.task = invalid, "Settings hides recovery and starts no request")
end sub

sub testLateCallbacks()
    press("up")
    waitUntil("menuFocus", true)
    openTab("Browse")
    r = hero()
    check(r.active = invalid and m.settings.getParent() = invalid and r.status.state = "error", "Browse without an identity shows recovery instead of a blank page")

    press("ok")
    waitUntil("pending", true)
    pending = hero().task
    press("up")
    waitUntil("menuFocus", true)
    openTab("LoginPage")
    r = hero()
    login = r.active
    check(login <> invalid and login.id = "LoginPage" and login.isInFocusChain() and r.status.state = "hidden", "sign-in opens while a Try again is pending")
    pending.response = { device_code: 42 }
    waitUntil("pending", false)
    r = hero()
    check(r.failures = 3 and r.status.state = "hidden" and login.isSameNode(r.active) and login.isInFocusChain(), "a malformed late response keeps sign-in open and focused")

    openTab("Search")
    r = hero()
    third = r.status.message
    check(r.active = invalid and login.getParent() = invalid and r.status.state = "error", "Search without an identity shows recovery")
    check(len(third) > len(m.firstMessage) and left(third, len(m.firstMessage)) = m.firstMessage, "the third failure adds restart and network guidance")

    press("ok")
    waitUntil("pending", true)
    pending = hero().task
    press("up")
    waitUntil("menuFocus", true)
    openTab("Settings")
    settings = hero().active
    pending.response = { device_code: "fixture-anonymous-device" }
    waitUntil("pending", false)
    r = hero()
    check(get_user_setting("device_code") = "fixture-anonymous-device" and r.failures = 0, "a late valid response stores the anonymous device identity")
    check(r.status.state = "hidden" and settings.isSameNode(r.active) and settings.isInFocusChain() and r.footprints = 0, "a late success neither replaces Settings nor steals its focus")
    check(get_user_setting("access_token") = invalid and get_setting("active_user") = "$default$" and get_setting("fixtureSignedOut") = invalid, "identity recovery never requires or changes an account")
end sub

sub testRecoverySuccess()
    ' Fixture input: the identity is missing again before a content tab opens.
    registry = m.global.fixtureRegistry
    registry.delete("device_code")
    m.global.fixtureRegistry = registry
    press("up")
    waitUntil("menuFocus", true)
    openTab("Following")
    r = hero()
    attempt = r.task
    check(attempt <> invalid and r.pending and r.status.state = "loading" and r.active = invalid, "with no failure yet the gate starts one attempt itself")

    attempt.response = { device_code: "fixture-anonymous-device-2" }
    waitUntil("active", "Following")
    r = hero()
    page = r.active
    check(get_user_setting("device_code") = "fixture-anonymous-device-2" and r.status.state = "hidden", "success stores the identity and hides recovery")
    check(page <> invalid and page.isInFocusChain() and r.menu.activeItem = "Following", "success opens Following with focus and marks it active")
    p = page.callFunc("fixtureRead")
    check(p.task <> invalid and p.task.request.type = "getFollowingPageQuery" and page.findNode("anonymousHint").visible, "Following loads anonymously without sign-in")
end sub

sub testRailBackAndExit()
    r = hero()
    page = r.active
    rail = r.rail
    p = page.callFunc("fixtureRead")
    p.task.response = { shelves: [shelf("Popular", "a"), shelf("Also live", "b")] }
    rowlist = p.rowlist
    waitUntil("rows", rowlist)
    check(p.status.state = "hidden" and rowlist.content.getChildCount() = 2, "Following shows the loaded rows")
    press("down")
    waitUntil("focus", rowlist)
    check(rowlist.isInFocusChain() and rowlist.drawFocusFeedback, "Down focuses the first card")

    press("left")
    settle(300)
    check(not rail.hasItems and not rail.itemHasFocus and rowlist.isInFocusChain(), "Left with an empty rail keeps focus on the card")

    m.global.fixtureHistory = [recent("first", "First Channel"), recent("second", "Second Channel")]
    rail.callFunc("fixtureRefresh")
    check(rail.hasItems, "recent history fills the rail")

    press("down")
    press("right")
    waitUntil("item", [1, 1])
    press("left")
    waitUntil("item", [1, 0])
    remembered = rowlist.rowItemFocused
    press("left")
    waitUntil("focus", rail)
    check(rail.itemHasFocus and not rowlist.isInFocusChain() and not rowlist.drawFocusFeedback, "Left from the first card enters the rail")
    check(rail.findNode("caption").visible and rail.findNode("captionLabel").text = "First Channel", "the focused rail item says its channel name")

    press("back")
    waitUntil("focus", rowlist)
    check(not m.exitRequested and not m.scene.exitApp, "Back in the rail does not exit the app")
    check(not rail.itemHasFocus and not rail.findNode("caption").visible, "Back leaves the rail")
    check(rowlist.isInFocusChain() and rowlist.drawFocusFeedback and sameItem(rowlist.rowItemFocused, remembered), "Back returns focus to the same card")

    press("left")
    waitUntil("focus", rail)
    press("up")
    waitUntil("menuFocus", true)
    check(not rail.itemHasFocus and not m.exitRequested, "Up from the top rail item moves to the menu")

    ' Down on a tab selects it; selecting the open tab reuses its page.
    openTab("Following")
    waitUntil("focus", rowlist)
    check(page.isSameNode(hero().active) and sameItem(rowlist.rowItemFocused, remembered), "selecting the open tab returns to the remembered card")
    press("back")
    waitUntil("menuFocus", true)
    check(not m.exitRequested and hero().footprints = 0, "Back from page content moves to the menu")

    press("back")
    waitUntil("exit", true)
    check(m.exitRequested and m.scene.exitApp, "Back from the menu requests the app exit")
    ' Production main disposes the scene after exitApp, then closes it.
    task = p.task
    m.scene.callFunc("onDestroy")
    check(task.control = "stop" and page.getParent() = invalid and hero().active = invalid, "exit cleanup stops the page request and removes the page")
end sub

function shelf(title as string, prefix as string) as object
    streams = []
    for i = 1 to 3
        login = prefix + i.toStr()
        streams.push({ contentType: "LIVE", contentTitle: login, streamerLogin: login, streamerDisplayName: login, viewersCount: i, previewImageURL: "pkg:/images/default_banner.png" })
    end for
    return { title: title, streams: streams }
end function

function recent(login as string, name as string) as object
    return { login: login, displayName: name, iconUrl: "pkg:/images/default_banner.png" }
end function

function sameItem(actual as dynamic, expected as dynamic) as boolean
    return actual <> invalid and expected <> invalid and actual[0] = expected[0] and actual[1] = expected[1]
end function

function hero() as object
    return m.scene.callFunc("fixtureRead")
end function

' Menu boundary: brs-engine reports a ButtonGroupHoriz itself as its
' focusedChild, so focusedMenuItem() cannot read the focused tab id. Focus is
' moved with real keys; this calls the actual openPage that menu selection
' reaches with the resolved id.
sub openTab(name as string)
    m.scene.callFunc("fixtureOpen", name)
    settle(50)
end sub

sub press(key as string)
    print "FIXTURE_KEY:" + key
end sub

' Waits up to three seconds for an observable change, processing port events.
sub waitUntil(what as string, value as dynamic)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 3000
        r = hero()
        if what = "status" and r.status.state = value then return
        if what = "pending" and r.pending = value then return
        if what = "active" and r.active <> invalid and r.active.id = value then return
        if what = "menuFocus" and r.menu.isInFocusChain() = value then return
        if what = "focus" and value.isInFocusChain() then return
        if what = "rows" and value.content <> invalid then return
        if what = "item" and r.active <> invalid and sameItem(r.active.callFunc("fixtureRead").rowlist.rowItemFocused, value) then return
        if what = "exit" and m.exitRequested = value then return
        pump(20)
    end while
    print "STITCH_UI_FAIL:timed out waiting for "; what
    m.failures += 1
end sub

sub settle(duration as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < duration
        pump(20)
    end while
end sub

sub pump(duration as integer)
    msg = wait(duration, m.port)
    if type(msg) = "roSGNodeEvent" and msg.getField() = "exitApp" and msg.getData() = true then m.exitRequested = true
end sub

sub check(condition as boolean, message as string)
    if condition
        m.assertions += 1
    else
        m.failures += 1
        print "STITCH_UI_FAIL:"; message
    end if
end sub
