sub main()
    m.assertions = 0
    m.failures = 0
    port = createObject("roMessagePort")
    screen = createObject("roSGScreen")
    screen.setMessagePort(port)
    m.fixturePort = port
    scene = screen.createScene("FixtureScene")
    screen.show()
    m.global = screen.getGlobalNode()
    seed(false)
    testLogin(scene)
    seed(false)
    testLateLoginFailureFocus(scene)
    seed(true)
    testAccount(scene)
    seed(false)
    testSettings(scene)
    seed(false)
    testFloatingFocus(scene)
    seed(false)
    seed(true)
    testStreamGrid(scene)
    seed(false)
    testProxy(scene)
    testProxyTask()
    seed(true)
    testRoutes(scene)
    seed(false)
    testRemoteSettings(scene)
    if __NEGATIVE_CONTROL__ then check(false, "deliberate real assertion negative control")
    scene.callFunc("fixtureFinalCleanup")
    check(scene.callFunc("fixtureRead").disposed, "final host cleanup disposes native children before normal exit")
    screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: ";m.assertions;" assertions"
    else
        print "STITCH_UI_FAIL:";m.failures;" failures; ";m.assertions;" assertions"
    end if
end sub

sub testLateLoginFailureFocus(scene as object)
    print "SECTION Late Login failure focus"
    scene.callFunc("fixtureOpen", "LoginPage")
    state = scene.callFunc("fixtureRead")
    page = state.active
    pending = inspect(page).rendezvous
    check(pending <> invalid and pending.request.type = "getRendezvouzToken", "actual routed Login begins with one pending request")
    remote("back")
    check(state.menu.isInFocusChain() and page.isSameNode(scene.callFunc("fixtureRead").active), "real Back retains waiting Login and returns menu focus")
    pending.response = invalid
    actions = inspect(page).actions
    check(page.findNode("title").text = "Couldn't sign in" and actions.visible, "late failure still renders truthful retry actions on retained page")
    check(state.menu.isInFocusChain() and not actions.isInFocusChain(), "late failure after Back preserves menu focus")
    page.setFocus(true)
    check(actions.isInFocusChain() and not state.menu.isInFocusChain(), "returning to retained failed Login enters native actions")
    remote("ok")
    retry = inspect(page).rendezvous
    check(retry <> invalid and not pending.isSameNode(retry) and retry.request.type = "getRendezvouzToken" and retry.control = "run", "real Retry starts one fresh explicit request")
    check(not actions.visible and inspect(page).oauth = invalid, "Retry returns to loading without starting another poll")
    remote("back")
    check(state.menu.isInFocusChain(), "Back from retry loading restores menu focus")
    scene.callFunc("fixtureCleanup")
    retry.response = { user_code: "DISPOSED", device_code: "inert-late-device", expires_in: 60 }
    check(inspect(page).disposed and inspect(page).rendezvous = invalid and retry.control = "stop" and state.menu.isInFocusChain(), "permanent disposal stops retry and suppresses late callback without focus transfer")
end sub

sub testProxyTask()
    print "SECTION Actual proxy task parser"
    scenarios = [
        { status: 200, body: "", reason: "", noEvent: true, expected: "unreachable" },
        { status: 0, body: "", reason: "fixture network error", expected: "network" },
        { status: 502, body: "bad upstream", reason: "", expected: "http" },
        { status: 200, body: "", reason: "", expected: "empty_body" },
        { status: 200, body: "not JSON", reason: "", expected: "bad_body" },
        { status: 200, body: "[]", reason: "", expected: "bad_body" },
        { status: 200, body: "{}", reason: "", expected: "bad_status" },
        { status: 200, body: "{""status"":""degraded""}", reason: "", expected: "bad_status" },
        { status: 200, body: "{""status"":5}", reason: "", expected: "bad_status" },
        { status: 200, body: "{""status"":""ok"",""version"":""0.1.0""}", reason: "", expected: "upgrade" },
        { status: 200, body: "{""status"":""ok"",""version"":""0.3.0""}", reason: "", expected: "ok" },
        { status: 200, body: "{""status"":""ok"",""version"":""fixture-version"",""selected_master_version"":1}", reason: "", expected: "ok" }
    ]
    for each scenario in scenarios
        m.global.fixtureHttpInput = scenario
        task = createObject("roSGNode", "ProxyHealthCheck")
        task.proxyUrl = "http://fixture.invalid:8080/"
        if scenario.body = "not JSON" then print "EXPECTED_PARSEJSON_BEGIN"
        task.callFunc("fixtureRunCheck")
        if scenario.body = "not JSON" then print "EXPECTED_PARSEJSON_END"
        result = task.result
        check(result.reason = scenario.expected and result.ok = (scenario.expected = "ok"), "actual ProxyHealthCheck parses inert HTTP " + scenario.expected + " result")
        req = m.global.fixtureHttpRequest
        check(req.url = "http://fixture.invalid:8080/health" and req.method = "GET" and req.timeout = 3000 and req.retries = 1, "actual health worker retains URL/finite HTTP contract")
    end for
    task = createObject("roSGNode", "ProxyHealthCheck")
    task.proxyUrl = ""
    task.callFunc("fixtureRunCheck")
    check(not task.result.ok and task.result.reason = "empty", "actual empty worker input fails before HTTP")
    task.proxyUrl = "ftp://fixture.invalid"
    task.callFunc("fixtureRunCheck")
    check(not task.result.ok and task.result.reason = "scheme", "actual unsupported worker scheme fails before HTTP")
end sub

sub remote(key as string)
    print "FIXTURE_KEY:";key
    settle(350)
end sub

sub settle(ms as integer)
    timer = createObject("roTimespan")
    timer.mark()
    while timer.totalMilliseconds() < ms
        event = wait(10, m.fixturePort)
    end while
end sub

sub testRemoteSettings(scene as object)
    print "SECTION Real remote keys"
    page = addPage(scene, "Settings")
    focusSetting(page, "playback.lowLatency")
    s = inspect(page)
    check(s.options.checkedItem = 0 and not s.options.isInFocusChain() and registry_read("playback.lowLatency", "$default$") = invalid, "native option list displays checked Off without focused input or storage writes")
    remote("right")
    check(s.options.isInFocusChain() and s.options.itemFocused = 0, "real remote Right enters native options through production page handler")
    remote("down")
    check(s.options.itemFocused = 1 and s.options.checkedItem = 0 and registry_read("playback.lowLatency", "$default$") = invalid, "real remote Down moves option focus without checking or saving")
    remote("ok")
    check(s.options.checkedItem = 1 and registry_read("playback.lowLatency", "$default$") = "true", "real remote OK checks focused native option and production observer saves")
    remote("up")
    check(s.options.itemFocused = 0 and s.options.checkedItem = 1 and registry_read("playback.lowLatency", "$default$") = "true", "real remote Up returns focus to Off without changing stored On")
    remote("ok")
    check(s.options.checkedItem = 0 and registry_read("playback.lowLatency", "$default$") = "false", "real remote OK checks Off and production observer stores false string")
    remote("back")
    check(s.menu.isInFocusChain() and not page.backPressed, "real remote Back returns options to native settings list")
    remote("back")
    check(not page.backPressed and inspect(page).levels = 1 and inspect(page).menu.itemFocused = 1, "second real remote Back restores the Playback panel selection")
    remote("back")
    check(page.backPressed, "third real remote Back emits root-page navigation")
    page.backPressed = false
    page.callFunc("fixtureFocus", 2)
    remote("ok")
    check(inspect(page).levels = 2 and inspect(page).menu.itemFocused = 0, "real remote OK opens Chat at its first setting")
    remote("up")
    check(inspect(page).levels = 1 and inspect(page).menu.itemFocused = 2 and not page.backPressed, "real remote Up from the first Chat setting restores its parent panel selection")
    page.callFunc("fixtureFocus", 0)
    remote("up")
    check(page.backPressed, "real remote Up from the root first row still leaves Settings")
    disposePage(scene, page)

    seed(true)
    page = addPage(scene, "LoginPage")
    remote("ok")
    check(page.contentSelected <> invalid and page.contentSelected.contentType = "LIVE", "real remote OK selects Account Your channel through native ButtonGroup")
    remote("down")
    check(inspect(page).actions.buttonFocused = 1, "real remote Down focuses native Account Sign out button")
    remote("ok")
    dialog = inspect(page).dialog
    check(dialog <> invalid and scene.dialog <> invalid, "real remote OK opens shared native confirmation handler")
    remote("back")
    check(inspect(page).dialog = invalid and get_setting("active_user") = "fixture-user" and not page.signedOut, "real remote confirmation Back cancels without signing out")
    remote("ok")
    dialog = inspect(page).dialog
    remote("down")
    remote("ok")
    check(inspect(page).dialog = invalid and get_setting("active_user") = "fixture-user" and not page.signedOut, "real remote native confirmation Cancel returns without signing out")
    remote("ok")
    remote("ok")
    check(page.signedOut and get_setting("active_user") = "$default$", "real remote native confirmation Sign out invokes production account cleanup")
    disposePage(scene, page)

    seed(false)
    page = addPage(scene, "Settings")
    keyboard = openProxy(page)
    pending = saveProxy(page, "http://remote-back.invalid:8080")
    remote("back")
    pending.result = { ok: true }
    check(inspect(page).keyboard = invalid and pending.control = "stop" and registry_read("proxy.url", "$default$") = invalid, "real remote keyboard Back cancels pending actual save and suppresses late success")
    disposePage(scene, page)
end sub

sub check(value as boolean, message as string)
    m.assertions = m.assertions + 1
    if value
        print "PASS ";m.assertions;": ";message
    else
        m.failures = m.failures + 1
        print "FAIL ";m.assertions;": ";message
    end if
end sub

function tokenColor(token as string) as dynamic
    probe = createObject("roSGNode", "Label")
    probe.color = token
    return probe.color
end function

sub seed(signed as boolean)
    allValues = {}
    if signed
        allValues[m.global.appid + ":active_user"] = "fixture-user"
        allValues["fixture-user:login"] = "fixture-user"
        allValues["fixture-user:display_name"] = "Fixture Viewer"
        allValues["fixture-user:id"] = "12345"
        allValues["fixture-user:profile_image_url"] = "pkg:/images/iconLogin.png"
        allValues["fixture-user:access_token"] = "inert-token"
        allValues["fixture-user:refresh_token"] = "inert-refresh"
        allValues["fixture-user:token_expires_at"] = "999"
        allValues["fixture-user:device_code"] = "account-device"
        allValues["fixture-user:ChatFontSize"] = "14"
        allValues["fixture-user:recentlyWatched"] = "fixture-history"
    else
        allValues[m.global.appid + ":active_user"] = "$default$"
    end if
    allValues["$default$:device_code"] = "anonymous-device"
    m.global.fixtureRegistry = allValues
    m.global.fixtureWrites = 0
    m.global.fixtureDeletes = 0
end sub

function addPage(scene as object, name as string) as object
    page = createObject("roSGNode", name)
    scene.appendChild(page)
    page.setFocus(true)
    return page
end function
function inspect(page as object) as object
    return page.callFunc("fixtureRead")
end function
sub disposePage(scene as object, page as object)
    page.callFunc("onDestroy")
    scene.removeChild(page)
end sub
sub selectAccount(page as object, index as integer)
    inspect(page).actions.buttonSelected = index
end sub
function settingIndex(page as object, name as string) as integer
    content = inspect(page).menu.content
    for i = 0 to content.getChildCount() - 1
        if content.getChild(i).id = name then return i
    end for
    return -1
end function
sub focusSetting(page as object, name as string)
    s = inspect(page)
    s.menu.setFocus(true)
    index = settingIndex(page, name)
    if index >= 0
        page.callFunc("fixtureFocus", index)
        return
    end if
    while inspect(page).levels > 1
        page.callFunc("fixtureKey", "back")
    end while
    path = settingPath(GetConfigTree(), name)
    if path = invalid
        check(false, "setting exists in grouped schema: " + name)
        return
    end if
    for i = 0 to path.count() - 1
        page.callFunc("fixtureFocus", path[i])
        if i < path.count() - 1 then page.callFunc("fixtureSelect")
    end for
end sub

function settingPath(items as object, name as string) as dynamic
    for i = 0 to items.count() - 1
        item = items[i]
        if item.settingName = name then return [i]
        if item.children <> invalid
            path = settingPath(item.children, name)
            if path <> invalid
                result = [i]
                result.append(path)
                return result
            end if
        end if
    end for
    return invalid
end function

function settingValue(page as object, name as string) as string
    if settingIndex(page, name) < 0 then focusSetting(page, name)
    return inspect(page).menu.content.getChild(settingIndex(page, name)).shortDescriptionLine1
end function

sub testLogin(scene as object)
    print "SECTION Login"
    page = addPage(scene, "LoginPage")
    s = inspect(page)
    check(s.rendezvous.request.type = "getRendezvouzToken" and s.oauth = invalid, "signed-out creates one real factory rendezvous request")
    check(page.findNode("title").text = "Sign in to Twitch" and not s.actions.visible, "signed-out loading title and hidden actions")
    check(instr(1, page.findNode("optional").text, "optional") > 0, "sign-in remains optional")
    task = s.rendezvous
    task.response = invalid
    s = inspect(page)
    check(page.findNode("title").text = "Couldn't sign in" and s.rendezvous = invalid and task.control = "stop", "registration failure stops task and shows failure")
    check(s.actions.buttons.count() = 2 and s.actions.buttons[0] = "Try again" and s.actions.buttons[1] = "Back to browsing", "failure keeps retry and browsing actions")
    check(s.actions.isInFocusChain(), "native failure ButtonGroup receives focus")
    selectAccount(page, 9)
    check(inspect(page).rendezvous = invalid and not page.backPressed, "invalid action index cannot retry or navigate")
    selectAccount(page, 0)
    s = inspect(page)
    check(s.rendezvous <> invalid and not task.isSameNode(s.rendezvous) and not s.actions.visible, "Retry creates one replacement and hides actions")
    current = s.rendezvous
    selectAccount(page, 0)
    check(current.isSameNode(inspect(page).rendezvous), "duplicate hidden Retry cannot create another task")
    task.response = { user_code: "STALE", device_code: "stale", expires_in: 900 }
    check(page.findNode("code").text = "", "stale removed registration observer cannot set code")
    current.response = { user_code: "ABCD-1234", device_code: "temporary-device", expires_in: 180 }
    s = inspect(page)
    check(page.findNode("code").text = "ABCD-1234" and page.findNode("codeGroup").visible, "real rendezvous user_code reaches visible native code")
    check(instr(1, page.findNode("status").text, "3 minutes") > 0, "expiry comes from actual 180-second response")
    check(s.oauth.request.type = "getOauthToken" and s.oauth.request.params.device_code = "temporary-device", "real code response starts bounded OAuth request contract")
    check(instr(1, page.findNode("qrCode").uri, "ABCD-1234") > 0, "dynamic QR encodes short user code through inert Poster boundary")
    page.findNode("qrCode").loadStatus = "failed"
    check(page.findNode("qrCode").uri = "pkg:/images/qr_activate.png", "QR failure uses actual local fallback")
    page.callFunc("fixtureShowCode", "OTHER", invalid)
    check(instr(1, page.findNode("status").text, "minutes") = 0 and page.findNode("code").text = "OTHER", "missing expiry is not fabricated")
    page.callFunc("fixtureShowCode", invalid, 0)
    check(not page.findNode("codeGroup").visible and instr(1, page.findNode("status").text, "minutes") = 0, "invalid code and nonpositive expiry remain hidden")
    oauth = s.oauth
    oauth.response = invalid
    s = inspect(page)
    check(s.oauth = invalid and oauth.control = "stop" and page.findNode("title").text = "Couldn't sign in", "expired OAuth enters finite failure and stops polling task")
    selectAccount(page, 1)
    check(page.backPressed, "Back to browsing emits actual navigation field")
    page.backPressed = false
    selectAccount(page, 0)
    pending = inspect(page).rendezvous
    page.callFunc("onDestroy")
    page.callFunc("onDestroy")
    pending.response = { user_code: "DISPOSED", device_code: "x", expires_in: 60 }
    selectAccount(page, 1)
    check(inspect(page).disposed and inspect(page).rendezvous = invalid and pending.control = "stop" and not page.backPressed, "idempotent Login disposal removes response and action observers")
    scene.removeChild(page)

    page = addPage(scene, "LoginPage")
    inspect(page).rendezvous.response = { user_code: "GOOD", device_code: "new-device", expires_in: 60 }
    inspect(page).oauth.response = { access_token: "new-token", refresh_token: "new-refresh" }
    check(inspect(page).user.request.type = "getHomePageQuery" and get_user_setting("device_code") = "new-device", "OAuth success promotes actual temporary identity and loads account")
    check(get_user_setting("temp_device_code") = invalid, "temporary identity cleared after promotion")
    inspect(page).user.response = invalid
    check(page.findNode("title").text = "Couldn't sign in" and inspect(page).user = invalid, "account-query failure offers bounded retry")
    disposePage(scene, page)

    page = addPage(scene, "LoginPage")
    inspect(page).rendezvous.response = { user_code: "FINAL", device_code: "authenticated-device", expires_in: 60 }
    inspect(page).oauth.response = { access_token: "final-token", refresh_token: "final-refresh" }
    inspect(page).user.response = { currentUser: { login: "authenticated-fixture" } }
    check(page.finished and get_setting("active_user") = "authenticated-fixture" and get_user_setting("login") = "authenticated-fixture", "valid account response promotes real login and emits finished")
    check(get_user_setting("access_token") = "final-token" and get_user_setting("refresh_token") = "final-refresh" and get_user_setting("device_code") = "authenticated-device", "real login completion moves credentials and independent identity to account section")
    check(registry_read("access_token", "$default$") = invalid and registry_read("device_code", "$default$") = invalid, "login completion removes promoted anonymous credentials")
    disposePage(scene, page)
end sub

sub testAccount(scene as object)
    print "SECTION Account"
    page = addPage(scene, "LoginPage")
    s = inspect(page)
    check(s.rendezvous = invalid and s.oauth = invalid and s.user = invalid, "signed-in Account starts no sign-in tasks")
    check(page.findNode("title").text = "Fixture Viewer" and page.findNode("avatar").visible and page.findNode("avatar").uri = "pkg:/images/iconLogin.png", "Account displays stored native avatar and name")
    check(instr(1, page.findNode("steps").text, "fixture-user") > 0 and s.actions.buttons.count() = 3, "Account login and three actions remain available")
    check(s.actions.isInFocusChain(), "native Account ButtonGroup receives page focus")
    selectAccount(page, 0)
    content = page.contentSelected
    check(content.contentType = "LIVE" and content.streamerLogin = "fixture-user" and not page.playContent, "Your channel emits actual LIVE by-login browse contract")
    check(content.streamerId = "12345" and content.streamerDisplayName = "Fixture Viewer" and content.streamerProfileImageUrl = "pkg:/images/iconLogin.png", "own-channel metadata is preserved")
    selectAccount(page, 1)
    dialog = inspect(page).dialog
    check(dialog <> invalid and dialog.title = "Sign out of Twitch?" and dialog.buttons[0] = "Sign out" and dialog.buttons[1] = "Cancel", "actual shared sign-out dialog has truthful confirmation")
    selectAccount(page, 1)
    check(dialog.isSameNode(inspect(page).dialog), "duplicate sign-out action cannot duplicate dialog")
    dialog.buttonSelected = 1
    check(inspect(page).dialog = invalid and scene.dialog = invalid and get_setting("active_user") = "fixture-user" and not page.signedOut, "Cancel closes confirmation without signing out")
    check(inspect(page).actions.isInFocusChain(), "Cancel returns actual Account action focus")
    selectAccount(page, 1)
    dialog = inspect(page).dialog
    dialog.wasClosed = true
    check(inspect(page).dialog = invalid and get_setting("active_user") = "fixture-user", "dialog Back/wasClosed cancels sign-out")
    dialog.buttonSelected = 0
    check(get_setting("active_user") = "fixture-user", "closed dialog observer cannot sign out later")
    selectAccount(page, 1)
    inspect(page).dialog.buttonSelected = 0
    check(page.signedOut and get_setting("active_user") = "$default$", "confirm runs real signOutAccount and emits signedOut")
    check(registry_read("access_token", "fixture-user") = invalid and registry_read("refresh_token", "fixture-user") = invalid and registry_read("token_expires_at", "fixture-user") = invalid, "confirmed sign-out removes actual account credentials")
    check(registry_read("ChatFontSize", "fixture-user") = "14" and registry_read("recentlyWatched", "fixture-user") = "fixture-history", "confirmed sign-out preserves stored preferences and history")
    check(get_user_setting("device_code") = "anonymous-device" and registry_read("device_code", "fixture-user") = "account-device", "sign-out preserves existing independent anonymous device identity")
    disposePage(scene, page)

    seed(true)
    registry_delete("device_code", "$default$")
    page = addPage(scene, "LoginPage")
    selectAccount(page, 1)
    oldDialog = inspect(page).dialog
    page.callFunc("onDestroy")
    oldDialog.buttonSelected = 0
    oldDialog.wasClosed = true
    check(get_setting("active_user") = "fixture-user" and not page.signedOut and inspect(page).dialog = invalid, "disposed Account confirmation cannot mutate identity")
    scene.removeChild(page)
    page = addPage(scene, "LoginPage")
    selectAccount(page, 1)
    inspect(page).dialog.buttonSelected = 0
    check(get_user_setting("device_code") = "account-device", "real signOutAccount seeds missing anonymous identity from account")
    disposePage(scene, page)
end sub

sub testSettings(scene as object)
    print "SECTION Settings"
    registry = m.global.fixtureRegistry
    registry["$default$:proxy.builtin"] = "false"
    m.global.fixtureRegistry = registry
    page = addPage(scene, "Settings")
    s = inspect(page)
    check(s.menu.subtype() = "MarkupList" and s.menu.content.getChildCount() = 7, "actual Settings shows account, five grouped panels and upstream Support")
    check(page.findNode("sectionTitle").text = "Settings", "root Settings identifies its location")
    check(m.global.fixtureWrites = 0 and m.global.fixtureDeletes = 0, "opening Settings displays defaults without any storage writes")
    check(settingValue(page, "ChatFontSize") = "Large (16)", "new-install chat display defaults to authorized 16")
    check(settingValue(page, "chat.enabled") = "On", "chat processing stays enabled by default")
    check(settingValue(page, "analytics.enabled") = "Off" and settingValue(page, "playback.lowLatency") = "Off", "diagnostics and experimental latency remain default off")
    check(settingValue(page, "BetterTTVEmote") = "On" and settingValue(page, "proxy.url") = "Not set", "bool/text defaults have readable current values")
    focusSetting(page, "logout")
    check(s.menu.content.getChild(0).title = "Account" and settingValue(page, "logout") = "Not signed in", "signed-out Account row remains truthful")
    page.callFunc("fixtureSelect")
    check(inspect(page).dialog = invalid and not page.finished, "signed-out Account row has no sign-out action")
    focusSetting(page, "playback.lowLatency")
    s = inspect(page)
    check(page.findNode("settingTag").visible and s.options.visible and s.options.content.getChild(0).title = "Off" and s.options.content.getChild(1).title = "On", "experimental label and actual Off/On options shown")
    check(s.options.checkedItem = 0 and m.global.fixtureWrites = 0, "list focus checks stored/default value without writes")
    page.callFunc("fixtureKey", "right")
    check(s.options.isInFocusChain() and not s.menu.isInFocusChain(), "Right enters native RadioButtonList")
    s.options.checkedItem = 1
    check(get_user_setting("playback.lowLatency") = "true" and settingValue(page, "playback.lowLatency") = "On", "actual option observer stores true string and refreshes row")
    s.options.checkedItem = 0
    check(get_user_setting("playback.lowLatency") = "false", "actual Off choice stores false string")
    check(page.callFunc("fixtureKey", "back") and s.menu.isInFocusChain() and not page.backPressed, "Back from options returns list before leaving page")
    focusSetting(page, "playback.video.quality")
    s = inspect(page)
    check(s.options.checkedItem = 0 and s.options.content.getChild(5).id = "1080p", "quality defaults to Automatic and offers the preferred resolution")
    page.callFunc("fixtureSelect")
    s.options.checkedItem = 5
    check(get_user_setting("playback.video.quality") = "1080p" and settingValue(page, "playback.video.quality") = "1080p", "quality choice persists its stable resolution ID")
    page.callFunc("fixtureKey", "back")
    focusSetting(page, "ChatFontSize")
    focusSetting(page, "playback.video.quality")
    page.callFunc("fixtureSelect")
    check(inspect(page).options.itemFocused = 5 and inspect(page).options.checkedItem = 5, "reopening quality choices restores the saved resolution focus")
    page.callFunc("fixtureKey", "back")
    focusSetting(page, "chat.enabled")
    page.callFunc("fixtureSelect")
    inspect(page).options.checkedItem = 0
    check(get_user_setting("chat.enabled") = "false" and settingValue(page, "chat.enabled") = "Off", "the chat processing switch saves an explicit Off")
    inspect(page).options.checkedItem = 1
    check(get_user_setting("chat.enabled") = "true", "chat processing can be re-enabled")
    page.callFunc("fixtureKey", "back")
    focusSetting(page, "chat.timing")
    s = inspect(page)
    check(settingValue(page, "chat.timing") = "Match video" and s.options.checkedItem = 0, "chat keeps synchronized timing by default")
    page.callFunc("fixtureSelect")
    s.options.checkedItem = 1
    check(get_user_setting("chat.timing") = "live" and settingValue(page, "chat.timing") = "Live (no added delay)", "chat timing saves the explicit Live choice")
    s.options.checkedItem = 0
    page.callFunc("fixtureKey", "back")
    focusSetting(page, "analytics.enabled")
    check(not page.findNode("settingTag").visible and inspect(page).options.checkedItem = 0, "leaving experimental setting clears tag and shows diagnostics Off")
    page.callFunc("fixtureSelect")
    inspect(page).options.checkedItem = 1
    check(get_user_setting("analytics.enabled") = "true" and get_user_setting("analytics.consentVersion") = "1", "diagnostics selection preserves explicit consent version contract")
    inspect(page).options.checkedItem = 0
    check(get_user_setting("analytics.enabled") = "false", "diagnostics can be turned off using string storage")
    page.callFunc("fixtureKey", "left")
    set_user_setting("ChatFontSize", "14")
    focusSetting(page, "ChatFontSize")
    s = inspect(page)
    check(s.options.checkedItem = 2 and s.options.content.getChild(2).id = "14", "stored chat 14 remains checked with unchanged option id")
    page.callFunc("fixtureSelect")
    check(s.options.itemFocused = 2, "opening choices focuses the stored option instead of the first option")
    s.options.checkedItem = 3
    check(get_user_setting("ChatFontSize") = "16" and settingValue(page, "ChatFontSize") = "Large (16)", "chat selection stores option id and refreshes current label")
    page.callFunc("fixtureKey", "back")
    for each key in ["playback.watchCredit", "chat.hypeTrain", "chat.pinnedMessages"]
        focusSetting(page, key)
        s = inspect(page)
        check(page.findNode("settingTag").visible and s.options.checkedItem = 0 and settingValue(page, key) = "Off", "engagement setting is experimental and defaults off: " + key)
        page.callFunc("fixtureKey", "right")
        s.options.checkedItem = 1
        check(get_user_setting(key) = "true" and settingValue(page, key) = "On", "engagement option stores an explicit opt-in: " + key)
        s.options.checkedItem = 0
        check(get_user_setting(key) = "false", "engagement option supports opting out: " + key)
        page.callFunc("fixtureKey", "back")
    end for
    focusSetting(page, "support")
    check(settingIndex(page, "support") > 0, "upstream support action stays available beside the redesigned settings")
    qr = page.findNode("supportQrPoster")
    check(qr <> invalid and qr.visible and qr.uri = "pkg:/images/qr_buymeacoffee.png", "focusing Support shows the upstream donation QR")
    writes = m.global.fixtureWrites
    page.callFunc("fixtureSelect")
    check(qr.visible and m.global.fixtureWrites = writes and not page.finished, "Support selection keeps the QR visible without storage changes or navigation")
    check(not inspect(page).options.visible and not page.findNode("settingValue").visible, "support panel does not overlap choices or a saved value")
    settle(100)
    qrBounds = qr.sceneBoundingRect()
    cardBounds = page.findNode("detailsCard").sceneBoundingRect()
    check(qrBounds.width > 0 and qrBounds.x >= cardBounds.x and qrBounds.y >= cardBounds.y and qrBounds.x + qrBounds.width <= cardBounds.x + cardBounds.width and qrBounds.y + qrBounds.height <= cardBounds.y + cardBounds.height, "support QR fits inside the redesigned details card")
    focusSetting(page, "proxy.builtin")
    check(settingValue(page, "proxy.builtin") = "Off" and inspect(page).options.checkedItem = 0, "existing community splitter Off preference is retained")
    set_user_setting("proxy.builtin", "true")
    check(not qr.visible and inspect(page).options.visible, "leaving Support restores the focused setting's options and hides the QR")
    focusSetting(page, "logout")
    page.callFunc("fixtureFocus", 2)
    check(inspect(page).menu.content.getChild(2).id = "chat" and inspect(page).menu.content.getChild(2).shortDescriptionLine1 = "Open", "Chat is a root panel with an Open action")
    page.callFunc("fixtureSelect")
    check(inspect(page).levels = 2 and inspect(page).menu.itemFocused = 0 and inspect(page).menu.content.getChildCount() = 9 and page.findNode("sectionTitle").text = "Settings / Chat", "Chat opens its nine settings at the first row with a breadcrumb")
    page.callFunc("fixtureKey", "back")
    check(inspect(page).levels = 1 and inspect(page).menu.itemFocused = 2 and page.findNode("sectionTitle").text = "Settings" and not page.backPressed, "Back restores Chat panel selection before leaving Settings")
    section = { title: "Nested", children: [{ title: "Nested", settingName: "fixture.nested", type: "bool", default: "false" }] }
    page.callFunc("fixtureHierarchy", section)
    check(inspect(page).levels = 2 and inspect(page).menu.content.getChildCount() = 1, "actual LoadMenu supports retained hierarchy")
    page.callFunc("fixtureKey", "back")
    check(inspect(page).levels = 1 and inspect(page).menu.content.getChildCount() = 7 and not page.backPressed, "Back restores parent settings before page back")
    page.callFunc("fixtureKey", "back")
    check(page.backPressed, "Back at root emits page back")
    page.backPressed = false
    writes = m.global.fixtureWrites
    options = inspect(page).options
    page.callFunc("onDestroy")
    page.callFunc("onDestroy")
    options.checkedItem = 1
    inspect(page).menu.itemSelected = 1
    check(inspect(page).disposed and m.global.fixtureWrites = writes and inspect(page).task = invalid, "Settings disposal suppresses observed option/list saves")
    scene.removeChild(page)

    row = addPage(scene, "SettingsListItem")
    content = createObject("roSGNode", "ContentNode")
    content.title = "Chat text size"
    content.shortDescriptionLine1 = "Medium (14)"
    row.itemContent = content
    check(inspect(row).name.text = "Chat text size" and inspect(row).value.text = "Medium (14)", "real row component renders actual content fields")
    row.listHasFocus = true
    row.focusPercent = 1.0
    check(inspect(row).plate.color = tokenColor(m.global.constants.ui.color.raised) and inspect(row).value.color = tokenColor(m.global.constants.ui.color.text), "actual row focus uses raised/white palette")
    row.listHasFocus = false
    check(inspect(row).plate.color = tokenColor(m.global.constants.ui.color.surface) and inspect(row).value.color = tokenColor(m.global.constants.ui.color.textSecondary), "row loses focus feedback with list focus")
    content2 = createObject("roSGNode", "ContentNode")
    content2.title = "Optional diagnostics"
    content2.shortDescriptionLine1 = "Off"
    row.itemContent = content2
    check(inspect(row).name.text = "Optional diagnostics" and inspect(row).value.text = "Off", "native row recycling replaces both labels")
    row.width = 600
    row.height = 70
    check(inspect(row).plate.width = 600 and inspect(row).name.height = 70 and inspect(row).value.width > 0, "row resizing maintains readable dimensions")
    row.callFunc("onDestroy")
    row.callFunc("onDestroy")
    row.itemContent = content
    row.listHasFocus = true
    row.focusPercent = 0.7
    check(inspect(row).disposed and inspect(row).name.text = "Optional diagnostics" and inspect(row).plate.color = tokenColor(m.global.constants.ui.color.surface), "disposed recycled row ignores XML content/focus callbacks")
    scene.removeChild(row)
end sub

function openProxy(page as object) as object
    focusSetting(page, "proxy.url")
    page.callFunc("fixtureSelect")
    return inspect(page).keyboard
end function
function saveProxy(page as object, value as string) as object
    keyboard = inspect(page).keyboard
    keyboard.text = value
    keyboard.buttonSelected = 0
    return inspect(page).task
end function
sub testProxy(scene as object)
    print "SECTION Proxy"
    page = addPage(scene, "Settings")
    bad = [invalid, false, true, 1, "ok", [], {}, { ok: false }, { ok: "true" }, { ok: 1 }, { ok: invalid }, { ok: [] }, { ok: {} }, { message: "unknown" }]
    for each result in bad
        check(not page.callFunc("fixtureHealthPassed", result), "healthCheckPassed rejects invalid/nonboolean/false result " + type(result))
    end for
    check(page.callFunc("fixtureHealthPassed", { ok: true }), "healthCheckPassed accepts only actual boolean true")
    check(page.callFunc("fixtureFailureText", {}) = "Couldn't check the service. Try again.", "unknown health failure retains generic truthful copy")
    check(instr(1, page.callFunc("fixtureFailureText", { ok: false, message: "timeout" }), "timeout") > 0, "health failure reports real task reason")
    keyboard = openProxy(page)
    check(keyboard <> invalid and keyboard.buttons[0] = "Save" and keyboard.buttons[1] = "Cancel", "actual keyboard Save/Cancel contract")
    old = saveProxy(page, "http://fixture.invalid:8080")
    check(old.proxyUrl = "http://fixture.invalid:8080" and old.control = "run" and get_user_setting("proxy.url", "") = "", "Save starts current-address check without premature save")
    keyboard.buttonSelected = 0
    check(old.isSameNode(inspect(page).task), "duplicate pending Save reuses same health task")
    keyboard.text = "http://replacement.invalid:8080"
    keyboard.buttonSelected = 0
    current = inspect(page).task
    check(not old.isSameNode(current) and old.control = "stop" and current.proxyUrl = keyboard.text, "new address replaces/stops prior health task")
    old.result = { ok: true }
    check(current.isSameNode(inspect(page).task) and get_user_setting("proxy.url", "") = "", "replaced task's stale successful result cannot save")
    keyboard.text = "http://changed.invalid:8080"
    current.result = { ok: true }
    check(inspect(page).task = invalid and inspect(page).pending = invalid and get_user_setting("proxy.url", "") = "", "changed-address success cannot save checked old URL")
    check(instr(1, keyboard.message[0], "address changed") > 0 and inspect(page).keyboard <> invalid, "changed address asks for a fresh Save and keeps keyboard")
    for each result in [invalid, {}, { ok: false, message: "offline" }, { ok: "true" }, { ok: 1 }]
        pending = saveProxy(page, "http://failed.invalid:8080")
        pending.result = result
        check(pending.control = "stop" and inspect(page).task = invalid and get_user_setting("proxy.url", "") = "" and inspect(page).keyboard <> invalid, "malformed/failure callback never saves and stops task")
    end for
    pending = saveProxy(page, "http://cancel.invalid:8080")
    keyboard.buttonSelected = 1
    pending.result = { ok: true }
    check(inspect(page).keyboard = invalid and scene.dialog = invalid and pending.control = "stop" and get_user_setting("proxy.url", "") = "", "Cancel destroys pending check and suppresses late save")
    keyboard = openProxy(page)
    pending = saveProxy(page, "http://back.invalid:8080")
    keyboard.wasClosed = true
    pending.result = { ok: true }
    check(inspect(page).keyboard = invalid and pending.control = "stop" and get_user_setting("proxy.url", "") = "", "keyboard Back/wasClosed destroys check and suppresses late save")
    keyboard = openProxy(page)
    pending = saveProxy(page, "  http://verified.invalid:8080  ")
    check(pending.proxyUrl = "http://verified.invalid:8080", "actual Save trims address before check")
    pending.result = { ok: true }
    check(get_user_setting("proxy.url") = "http://verified.invalid:8080" and inspect(page).keyboard = invalid and pending.control = "stop", "valid boolean-true result alone saves actual current address")
    check(settingValue(page, "proxy.url") = "http://verified.invalid:8080", "verified save refreshes current-value row")
    keyboard = openProxy(page)
    keyboard.text = "   "
    keyboard.buttonSelected = 0
    check(get_user_setting("proxy.url") = "" and inspect(page).task = invalid and inspect(page).keyboard = invalid and settingValue(page, "proxy.url") = "Not set", "empty address disables without a health task")
    keyboard = openProxy(page)
    pending = saveProxy(page, "http://disposed.invalid:8080")
    page.callFunc("onDestroy")
    pending.result = { ok: true }
    keyboard.buttonSelected = 0
    keyboard.wasClosed = true
    check(inspect(page).disposed and inspect(page).keyboard = invalid and inspect(page).task = invalid and pending.control = "stop" and get_user_setting("proxy.url") = "", "disposal destroys check and removes keyboard callbacks before late success")
    scene.removeChild(page)
end sub

sub testFloatingFocus(scene as object)
    print "SECTION Floating focus"
    scene.callFunc("fixtureOpen", "Following")
    row = scene.callFunc("fixtureRead").active.findNode("homeRowList")
    check(row.rowFocusAnimationStyle = "fixedFocus" and row.vertFocusAnimationStyle = "fixedFocus", "new installs keep existing fixed content focus")
    scene.callFunc("fixtureOpen", "Settings")
    settings = scene.callFunc("fixtureRead").active
    focusSetting(settings, "ui.floatingFocus")
    check(inspect(settings).levels = 2 and inspect(settings).menu.content.getChildCount() = 4 and settings.findNode("sectionTitle").text = "Settings / Browsing", "floating focus remains available inside the grouped Browsing panel")
    check(settingValue(settings, "ui.floatingFocus") = "Off" and inspect(settings).options.checkedItem = 0, "floating focus defaults to Off in actual Settings")
    settings.callFunc("fixtureSelect")
    inspect(settings).options.checkedItem = 1
    check(get_user_setting("ui.floatingFocus") = "true" and settingValue(settings, "ui.floatingFocus") = "On", "actual option observer persists floating focus opt-in")
    pages = [
        { name: "Following", rowId: "homeRowList", width: 1170, fixedWidth: 1280 },
        { name: "Browse", rowId: "browseRowList", width: 1170, fixedWidth: 1280 },
        { name: "Search", rowId: "homeRowList", width: 780, fixedWidth: 1280 },
        { name: "ChannelPage", rowId: "homeRowList", width: 1170, fixedWidth: 1980 },
        { name: "GamePage", rowId: "homeRowList", width: 1170, fixedWidth: 1280 }
    ]
    for each page in pages
        scene.callFunc("fixtureOpen", page.name)
        row = scene.callFunc("fixtureRead").active.findNode(page.rowId)
        check(row.rowFocusAnimationStyle = "floatingFocus" and row.vertFocusAnimationStyle = "fixedFocus", "new content page floats horizontally and keeps vertical focus: " + page.name)
        check(row.itemSize[0] = page.width and row.itemSize[1] = 295, "floating rows fit the visible remainder without changing row height: " + page.name)
    end for
    scene.callFunc("fixtureOpen", "Settings")
    settings = scene.callFunc("fixtureRead").active
    focusSetting(settings, "ui.floatingFocus")
    check(settingValue(settings, "ui.floatingFocus") = "On" and inspect(settings).options.checkedItem = 1, "reopened Settings restores floating focus preference")
    settings.callFunc("fixtureSelect")
    inspect(settings).options.checkedItem = 0
    for each page in pages
        scene.callFunc("fixtureOpen", page.name)
        row = scene.callFunc("fixtureRead").active.findNode(page.rowId)
        check(row.rowFocusAnimationStyle = "fixedFocus" and row.vertFocusAnimationStyle = "fixedFocus", "turning floating focus Off restores existing content focus: " + page.name)
        check(row.itemSize[0] = page.fixedWidth and row.itemSize[1] = 295, "fixed focus preserves original XML geometry: " + page.name)
    end for
    scene.callFunc("fixtureCleanup")
end sub

sub testStreamGrid(scene as object)
    print "SECTION Stream grid"
    scene.callFunc("fixtureOpen", "Settings")
    settings = scene.callFunc("fixtureRead").active
    focusSetting(settings, "ui.gridDensity")
    check(settingValue(settings, "ui.gridDensity") = "Comfortable" and inspect(settings).options.checkedItem = 0, "stream grid defaults to the comfortable layout")
    settings.callFunc("fixtureSelect")
    inspect(settings).options.checkedItem = 1
    check(get_user_setting("ui.gridDensity") = "compact", "actual Settings observer saves the compact grid choice")
    focusSetting(settings, "ui.floatingFocus")
    settings.callFunc("fixtureSelect")
    inspect(settings).options.checkedItem = 1
    streams = []
    edges = []
    for index = 0 to 8
        streams.push({ contentType: "LIVE", streamerLogin: "fixture-" + index.toStr(), contentTitle: "Fixture stream" })
        edges.push({ node: { id: index.toStr(), broadcaster: { login: "fixture-" + index.toStr() } } })
    end for
    scene.callFunc("fixtureOpen", "Following")
    following = scene.callFunc("fixtureRead").active
    inspect(following).task.response = { liveFollows: streams, offlineFollows: [] }
    rows = following.findNode("homeRowList")
    check(rows.content.getChildCount() = 3 and rows.content.getChild(0).getChildCount() = 4 and rows.content.getChild(1).getChildCount() = 4 and rows.content.getChild(2).getChildCount() = 1, "actual Following chunks compact streams into four-column rows without losing the final item")
    check(rows.rowItemSize[0][0] = 256 and rows.rowItemSize[0][1] = 144, "compact native rows use the shared 16:9 card size")
    check(rows.rowFocusAnimationStyle = "floatingFocus" and rows.itemSize[0] = 1170, "compact Following preserves the saved floating focus and visible row width after content loads")
    check(following.scale[0] = 1 and following.scale[1] = 1, "pages retain native logical geometry instead of stretching rendered text")
    scene.callFunc("fixtureOpen", "GamePage")
    directory = scene.callFunc("fixtureRead").active
    content = createObject("roSGNode", "TwitchContentNode")
    content.gameName = "Fixture Game"
    directory.contentRequested = content
    inspect(directory).task.response = { edges: edges }
    rows = directory.findNode("homeRowList")
    check(rows.content.getChildCount() = 3 and rows.content.getChild(0).getChildCount() = 4 and rows.content.getChild(1).getChildCount() = 4 and rows.content.getChild(2).getChildCount() = 1, "actual category directory preserves all compact streams in four-column rows")
    check(rows.rowItemSize[0][0] = 256 and rows.rowItemSize[0][1] = 144, "compact directory rows match the compact card geometry")
    scene.callFunc("fixtureOpen", "Settings")
    settings = scene.callFunc("fixtureRead").active
    focusSetting(settings, "ui.gridDensity")
    check(settingValue(settings, "ui.gridDensity") = "Compact" and inspect(settings).options.checkedItem = 1, "reopening Settings restores the saved compact grid")
    settings.callFunc("fixtureSelect")
    inspect(settings).options.checkedItem = 0
    scene.callFunc("fixtureOpen", "Following")
    following = scene.callFunc("fixtureRead").active
    inspect(following).task.response = { liveFollows: streams, offlineFollows: [] }
    rows = following.findNode("homeRowList")
    check(rows.content.getChildCount() = 3 and rows.content.getChild(0).getChildCount() = 3 and rows.content.getChild(2).getChildCount() = 3, "comfortable mode restores three-column rows")
    check(rows.rowItemSize[0][0] = 320 and rows.rowItemSize[0][1] = 180, "comfortable cards preserve the existing dimensions")
    check(rows.rowFocusAnimationStyle = "floatingFocus" and rows.itemSize[0] = 1170, "changing grid density preserves the saved floating focus")
    scene.callFunc("fixtureOpen", "GamePage")
    directory = scene.callFunc("fixtureRead").active
    directory.contentRequested = content
    inspect(directory).task.response = { edges: edges }
    rows = directory.findNode("homeRowList")
    check(rows.content.getChildCount() = 3 and rows.content.getChild(0).getChildCount() = 3 and rows.content.getChild(2).getChildCount() = 3, "comfortable category directories restore three-column rows")
    check(rows.rowItemSize[0][0] = 320 and rows.rowItemSize[0][1] = 180, "comfortable category directories preserve the existing card geometry")
    scene.callFunc("fixtureCleanup")
end sub

sub testRoutes(scene as object)
    print "SECTION Routes"
    scene.callFunc("fixtureOpen", "LoginPage")
    account = scene.callFunc("fixtureRead").active
    check(account.id = "LoginPage" and account.findNode("title").text = "Fixture Viewer", "actual hero openPage/factory routes signed-in account to Account")
    selectAccount(account, 0)
    state = scene.callFunc("fixtureRead")
    channel = state.active
    check(channel.id = "ChannelPage" and state.footprints.count() = 1 and not inspect(account).disposed, "Your channel uses real hero content routing and retains reusable Account backstack")
    cs = inspect(channel)
    check(cs.task.request.params.id = "fixture-user" and cs.shell.request.params.id = "fixture-user", "actual ChannelPage uses emitted login for both requests")
    cs.task.response = { isLive: true, videoShelves: [], description: "fixture channel", followerCount: 100, profileImageUrl: "pkg:/images/iconLogin.png" }
    row = inspect(channel).rowlist
    check(row.content.getChildCount() = 1 and row.rowHeights.count() = 1 and row.rowHeights[0] > 0, "actual ChannelPage LIVE row receives valid row height")
    live = row.content.getChild(0).getChild(0)
    check(live.contentType = "LIVE" and live.streamerLogin = "fixture-user", "actual native ChannelPage live row keeps playable LIVE/login contract")
    channel.backPressed = true
    check(scene.callFunc("fixtureRead").active.isSameNode(account) and inspect(channel).disposed, "real Back restores Account and permanently cleans channel")
    selectAccount(account, 1)
    inspect(account).dialog.buttonSelected = 0
    state = scene.callFunc("fixtureRead")
    check(state.active.id = "Following" and state.menu.activeItem = "Following" and state.menu.focusItem = "Following" and inspect(account).disposed, "Account signedOut observer rebuilds anonymous Following and menu marker")
    following = state.active
    account.signedOut = true
    account.finished = true
    check(scene.callFunc("fixtureRead").active.isSameNode(following), "discardScene removes both Account signedOut and finished observers")
    check(get_user_setting("device_code") = "anonymous-device", "Account transition preserves independent device identity")
    scene.callFunc("fixtureCleanup")
    seed(true)
    scene.callFunc("fixtureOpen", "Settings")
    settings = scene.callFunc("fixtureRead").active
    check(settingValue(settings, "logout") = "Fixture Viewer" and inspect(settings).menu.content.getChild(0).title = "Sign out", "signed-in Settings account row displays actual name/action")
    settings.callFunc("fixtureSelect")
    dialog = inspect(settings).dialog
    dialog.buttonSelected = 1
    check(get_setting("active_user") = "fixture-user" and not settings.finished, "Settings sign-out Cancel preserves account")
    settings.callFunc("fixtureSelect")
    inspect(settings).dialog.wasClosed = true
    check(get_setting("active_user") = "fixture-user" and inspect(settings).dialog = invalid, "Settings sign-out dialog Back preserves account")
    settings.callFunc("fixtureSelect")
    inspect(settings).dialog.buttonSelected = 0
    after = scene.callFunc("fixtureRead").active
    check(after.id = "Settings" and not after.isSameNode(settings) and inspect(settings).disposed and inspect(after).menu.content.getChild(0).title = "Account", "Settings finished observer rebuilds anonymous Settings instead of Following")
    settings.finished = true
    check(after.isSameNode(scene.callFunc("fixtureRead").active), "discarded Settings finished observer cannot reroute later")
    menu = scene.callFunc("fixtureRead").menu
    ms = inspect(menu)
    ms.icons.setFocus(true)
    ms.icons.buttonFocused = 2
    check(inspect(menu).label.text = "Sign in", "actual signed-out account menu caption updates after sign-out")
    seed(true)
    menu.updateUserIcon = true
    ms.icons.buttonFocused = 1
    ms.icons.buttonFocused = 2
    check(inspect(menu).label.text = "Account · Fixture Viewer", "actual signed-in account caption includes stored display name")
    scene.callFunc("fixtureCleanup")
end sub
