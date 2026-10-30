sub init()
    m.disposed = false
    m.top.localPlaybackSession = m.top.findNode("rokuPlaybackSession")
    m.global.addField("analyticsTask", "node", false)
    if getAnalyticsConfiguration() <> invalid
        analyticsTask = CreateObject("roSGNode", "AnalyticsTask")
        m.global.analyticsTask = analyticsTask
        analyticsTask.control = "RUN"
    end if

    m.validateOauthToken = createApiTask("validateOauthToken", "ValidateUserLogin")
    VersionJobs()
    m.top.backgroundUri = ""
    m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    m.activeNode = invalid
    m.footprints = []
    m.recentBar = m.top.findNode("recentlyWatchedBar")
    m.recentBar.observeField("contentSelected", "onRecentSelected")
    m.recentBar.observeField("hasItems", "onRecentItemsChanged")
    m.menu = m.top.findNode("MenuBar")
    m.menu.showSearchIcon = false
    m.menu.menuOptionsText = [
        "Following",
        "Browse",
        "Search",
    ]
    m.menu.observeField("buttonSelected", "onMenuSelection")
    m.menu.setFocus(true)
    m.startupStatus = m.top.findNode("startupStatus")
    if m.startupStatus <> invalid then m.startupStatus.observeField("actionSelected", "onStartupAction")
    m.deviceCodePending = false
    m.deviceCodeFailures = 0
    if get_setting("active_user") = invalid
        set_setting("active_user", "$default$")
    end if
    if get_user_setting("device_code") = invalid
        showDeviceCodeLoading()
        startDeviceCode()
    else
        onMenuSelection()
    end if
    sendAppOpenedEvents()
end sub

sub sendAppOpenedEvents()
    deviceInfo = CreateObject("roDeviceInfo")
    osVersion = deviceInfo.GetOSVersion()
    deviceModel = deviceInfo.GetModel()
    priorCrashReason = m.global.priorExitReason ' set by main.brs before scene creation

    rokuOsVersion = osVersion.major.toStr() + "." + osVersion.minor.toStr() + "." + osVersion.revision.toStr()

    appOpenProps = {
        device_model: deviceModel,
        roku_os_version: rokuOsVersion
    }
    if priorCrashReason <> invalid and priorCrashReason <> ""
        appOpenProps.prior_exit_reason = priorCrashReason
    end if

    trackEvent("app_opened", appOpenProps)

    isLoggedIn = get_setting("active_user", "$default$") <> "$default$" and get_user_setting("access_token") <> invalid
    analyticsIdentify({
        app_version: m.global.appInfo.Version.Version,
        device_model: deviceModel,
        roku_os_version: rokuOsVersion,
        is_dev: m.global.appInfo.IsDev,
        is_logged_in: isLoggedIn
    })
end sub

sub cleanUserData()
    signOutAccount()
end sub

sub ValidateUserLogin()
    if m.disposed then return
    response = m.validateOauthToken?.response
    if response = invalid then return
    if response.validationState = "invalid"
        cleanUserData()
        if m.recentBar <> invalid then m.recentBar.callFunc("buildItems")
        m.menu.updateUserIcon = true
    end if
end sub

function focusedMenuItem()
    focusedItem = ""
    if m.menu?.focusedChild?.focusedChild?.id <> invalid
        focusedItem = m.menu.focusedChild.focusedChild.id.toStr()
    end if
    return focusedItem
end function

sub VersionJobs()
    if m.global.appinfo.version.major.toInt() = 2 and m.global.appinfo.version.minor.toInt() = 3
        ' Clean Up Job for switching default profile name to "$default$" as "default" is technically a possible twitch user.
        if get_setting("active_user") <> invalid and get_setting("active_user") = "default"
            set_setting("active_user", "$default$")
        end if
    end if

    lastSeenVersion = get_setting("last_seen_version")

    changelog = getChangelog()
    sortedVersions = getSortedChangelogVersions(changelog)

    ' Collect changelog entries newer than lastSeenVersion.
    ' When lastSeenVersion is invalid (first install), all entries are shown.
    pendingLines = []
    for each v in sortedVersions
        isNew = (lastSeenVersion = invalid) or (compareVersions(v, lastSeenVersion) > 0)
        if isNew and changelog[v] <> invalid
            if pendingLines.count() > 0
                pendingLines.push("")
            end if
            pendingLines.push("v" + v)
            for each line in changelog[v]
                pendingLines.push("  - " + line)
            end for
        end if
    end for

    if pendingLines.count() > 0
        m.pendingChangelog = pendingLines
    end if
end sub

sub showChangelogDialog()
    if m.pendingChangelog = invalid or m.pendingChangelog.count() = 0 then return

    lines = m.pendingChangelog
    lines.push("")
    lines.push("Found a bug or have a suggestion? Visit bit.ly/roku-twitch")

    dialog = createObject("roSGNode", "StandardMessageDialog")
    dialog.title = "What's New"
    dialog.message = lines
    dialog.width = 1100
    dialog.maxWidth = 1100
    dialog.buttons = ["Got it"]
    applyDialogPalette(dialog)
    dialog.observeField("buttonSelected", "onChangelogDialogButtonSelected")
    dialog.observeField("wasClosed", "onChangelogDialogClosed")

    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = dialog
        m.changelogDialog = dialog
    end if
    m.pendingChangelog = invalid
end sub

' Fired when the user clicks "Got it" — persist version and close.
sub onChangelogDialogButtonSelected()
    set_setting("last_seen_version", m.global.appInfo.Version.Version)
    if m.changelogDialog <> invalid
        m.changelogDialog.unobserveField("buttonSelected")
        m.changelogDialog.unobserveField("wasClosed")
        m.changelogDialog.close = true
        m.changelogDialog = invalid
    end if
end sub

' Fired when the dialog is dismissed via Back without clicking "Got it".
' Persists last_seen_version so the dialog is not reshown for this version.
sub onChangelogDialogClosed()
    set_setting("last_seen_version", m.global.appInfo.Version.Version)
    if m.changelogDialog <> invalid
        m.changelogDialog.unobserveField("buttonSelected")
        m.changelogDialog.unobserveField("wasClosed")
        m.changelogDialog = invalid
    end if
end sub

' Anonymous device identity. Each attempt is one real finite rendezvous task,
' started at launch or by an explicit user action; there is no automatic retry.
sub startDeviceCode()
    if m.disposed or m.deviceCodePending = true then return
    m.getDeviceCodeTask = destroyTask(m.getDeviceCodeTask, "response")
    m.deviceCodePending = true
    m.getDeviceCodeTask = createApiTask("getRendezvouzToken", "handleDeviceCode")
end sub

function validDeviceCode(response as dynamic) as dynamic
    if type(response) <> "roAssociativeArray" then return invalid
    deviceCode = response.device_code
    if GetInterface(deviceCode, "ifString") = invalid or deviceCode = "" then return invalid
    return deviceCode
end function

sub handleDeviceCode()
    if m.disposed or m.getDeviceCodeTask = invalid then return
    deviceCode = validDeviceCode(m.getDeviceCodeTask.response)
    m.getDeviceCodeTask = destroyTask(m.getDeviceCodeTask, "response")
    m.deviceCodePending = false
    if deviceCode = invalid
        m.deviceCodeFailures += 1
        ' Settings or sign-in opened meanwhile keeps the user's place and focus.
        if m.activeNode = invalid then showDeviceCodeError()
        return
    end if
    set_user_setting("device_code", deviceCode)
    m.deviceCodeFailures = 0
    hideStartupStatus()
    if m.activeNode <> invalid then return
    m.menu.setFocus(true)
    menuItem = focusedMenuItem()
    if not isContentTab(menuItem) then menuItem = "Following"
    openPage(menuItem)
end sub

function isContentTab(menuItem as dynamic) as boolean
    return menuItem = "Following" or menuItem = "Browse" or menuItem = "Search"
end function

sub showDeviceCodeLoading()
    if m.startupStatus = invalid then return
    m.startupStatus.title = tr("Connecting to Twitch…")
    m.startupStatus.message = ""
    m.startupStatus.actions = []
    m.startupStatus.state = "loading"
end sub

sub showDeviceCodeError()
    if m.startupStatus = invalid then return
    message = tr("Stitch needs to register this Roku with Twitch before it can load channels. Check that your Roku is connected to the internet, then try again.")
    if m.deviceCodeFailures >= 3
        message = message + " " + tr("If it still doesn't work, restart your Roku or check its network settings.")
    end if
    m.startupStatus.title = tr("Can't connect to Twitch")
    m.startupStatus.message = message
    m.startupStatus.actions = [tr("Try again"), tr("Settings")]
    m.startupStatus.state = "error"
    m.startupStatus.setFocus(true)
end sub

sub hideStartupStatus()
    if m.startupStatus = invalid then return
    m.startupStatus.state = "hidden"
end sub

' Content tabs need the device identity; show recovery instead of a blank page.
sub showDeviceCodeRecovery()
    if m.deviceCodePending = true
        showDeviceCodeLoading()
    else if m.deviceCodeFailures > 0
        showDeviceCodeError()
    else
        showDeviceCodeLoading()
        startDeviceCode()
    end if
end sub

sub onStartupAction()
    if m.disposed or m.startupStatus = invalid then return
    action = m.startupStatus.actionSelected
    if action = 0
        if m.deviceCodePending = true then return
        showDeviceCodeLoading()
        startDeviceCode()
    else if action = 1
        ' Settings works offline, including the optional demux service address.
        openPage("Settings")
    end if
end sub

function buildNode(name)
    if name = invalid then return invalid
    m.global.compactGrid = get_user_setting("ui.gridDensity", "comfortable") = "compact"

    ' Dispatch to scene-specific factory
    if name = "Following"
        newNode = build_Following()
    else if name = "Browse"
        newNode = build_Browse()
    else if name = "Search"
        newNode = build_Search()
    else if name = "Settings"
        newNode = build_Settings()
    else if name = "LoginPage"
        newNode = build_LoginPage()
    else if name = "ChannelPage"
        newNode = build_ChannelPage()
    else if name = "GamePage"
        newNode = build_GamePage()
    else if name = "VideoPlayer"
        newNode = build_VideoPlayer()
    else
        return invalid
    end if

    if newNode = invalid then return invalid

    ' Content pages are rebuilt when leaving Settings, so the choice applies immediately.
    rowList = newNode.findNode("homeRowList")
    if rowList = invalid then rowList = newNode.findNode("browseRowList")
    if rowList <> invalid and get_user_setting("ui.floatingFocus", "false") = "true"
        ' Floating focus must scroll before a card leaves the HD picture.
        rowX = 0
        parentNode = rowList
        while parentNode <> invalid
            rowX += parentNode.translation[0]
            parentNode = parentNode.getParent()
        end while
        rowList.itemSize = [1280 - rowX, rowList.itemSize[1]]
        rowList.rowFocusAnimationStyle = "floatingFocus"
    end if

    ' Shared observer wiring
    newNode.observeField("backPressed", "onBackPressed")
    newNode.observeField("contentSelected", "onContentSelected")
    if newNode.hasField("menuRequest") then newNode.observeField("menuRequest", "onMenuRequest")
    if name = "VideoPlayer" then newNode.observeField("channelRequested", "onPlayerChannelRequested")
    if name = "VideoPlayer" then newNode.observeField("channelPinChanged", "onPlayerPinChanged")
    if name = "VideoPlayer" then newNode.observeField("channelFollowChanged", "onPlayerFollowChanged")
    if name = "VideoPlayer" then newNode.observeField("channelSignInRequested", "onPlayerSignInRequested")

    ' Tree placement
    if name = "GamePage" or name = "ChannelPage" or name = "VideoPlayer"
        m.top.appendChild(newNode)
    else
        m.top.insertChild(newNode, 1)
    end if

    return newNode
end function

' Tear down activeNode and any footprints (back-stack) so login/logout
' transitions don't leave stale, detached scenes wired up with observers.
sub teardownAllScenes()
    if m.activeNode <> invalid
        discardScene(m.activeNode)
        m.activeNode = invalid
    end if
    for each node in m.footprints
        discardScene(node)
    end for
    m.footprints = []
end sub

sub discardScene(node as dynamic)
    if node = invalid then return
    ' Suppress navigation callbacks before component cleanup changes fields.
    node.unobserveField("backPressed")
    node.unobserveField("contentSelected")
    if node.hasField("channelRequested") then node.unobserveField("channelRequested")
    if node.hasField("channelPinChanged") then node.unobserveField("channelPinChanged")
    if node.hasField("channelFollowChanged") then node.unobserveField("channelFollowChanged")
    if node.hasField("channelSignInRequested") then node.unobserveField("channelSignInRequested")
    node.unobserveField("finished")
    if node.hasField("signedOut") then node.unobserveField("signedOut")
    if node.hasField("menuRequest") then node.unobserveField("menuRequest")
    node.lastFocus = invalid
    disposeNodeTree(node)
    m.top.removeChild(node)
end sub

sub onLoginFinished()
    if m.disposed then return
    if m.recentBar <> invalid
        m.recentBar.itemHasFocus = false
        m.recentBar.callFunc("buildItems")
    end if
    m.menu.updateUserIcon = true
    if get_user_setting("device_code") = invalid
        startDeviceCode()
    end if
    teardownAllScenes()
    m.activeNode = buildNode("Following")
    if m.activeNode <> invalid
        m.menu.activeItem = "Following"
        m.activeNode.setFocus(true)
    end if
end sub

sub onLogoutFinished()
    if m.disposed then return
    if m.recentBar <> invalid
        m.recentBar.itemHasFocus = false
        m.recentBar.callFunc("buildItems")
    end if
    ' Signing out from the Account panel returns to anonymous browsing;
    ' Settings rebuilds itself so its account row updates.
    target = "Settings"
    if m.activeNode <> invalid and m.activeNode.id = "LoginPage" then target = "Following"
    m.menu.updateUserIcon = true
    teardownAllScenes()
    if target = "Following"
        m.menu.focusItem = target
        openPage(target)
        return
    end if
    m.activeNode = buildNode(target)
    if m.activeNode <> invalid
        m.menu.activeItem = target
        m.activeNode.setFocus(true)
    end if
end sub

sub onMenuSelection()
    if m.disposed then return
    menuItem = focusedMenuItem()
    if menuItem <> ""
        trackEvent("tab_visited", { tab: menuItem })
    end if
    if m.menu.focusedChild = invalid then return
    ' Signed in, the account button opens the Account panel (LoginPage).
    openPage(menuItem)
end sub

sub openPage(menuItem as string)
    isFirstLoad = (m.activeNode = invalid)
    if isContentTab(menuItem) and get_user_setting("device_code") = invalid
        teardownAllScenes()
        m.menu.activeItem = ""
        showDeviceCodeRecovery()
        return
    end if
    if m.activeNode <> invalid and m.activeNode.id.toStr() <> menuItem
        teardownAllScenes()
    end if
    if m.activeNode = invalid
        m.activeNode = buildNode(menuItem)
        if m.activeNode = invalid then return
    end if
    m.menu.activeItem = menuItem
    hideStartupStatus()
    m.activeNode.setfocus(true)
    if isFirstLoad
        showChangelogDialog()
    end if
end sub

' A page asks to open a menu tab (e.g. Following's "Go to Browse").
sub onMenuRequest()
    if m.disposed or m.activeNode = invalid then return
    target = m.activeNode.menuRequest
    if not isContentTab(target) then return
    m.menu.focusItem = target
    openPage(target)
end sub

sub onRecentItemsChanged()
    if m.disposed or m.recentBar.hasItems or not m.recentBar.itemHasFocus then return
    m.recentBar.itemHasFocus = false
    if m.activeNode <> invalid
        m.activeNode.setFocus(true)
    else
        m.menu.setFocus(true)
    end if
end sub

sub onRecentSelected()
    if m.disposed then return
    content = m.recentBar.contentSelected
    if content = invalid then return

    ' Ensure bar focus state is cleared regardless of which code path triggered this
    m.recentBar.itemHasFocus = false

    if m.activeNode <> invalid
        ' Save focus before pushing
        focused = lastFocusedChild(m.activeNode)
        if focused <> invalid and focused.id <> m.activeNode.id
            m.activeNode.lastFocus = focused
        else
            m.activeNode.lastFocus = invalid
        end if
        m.footprints.push(m.activeNode)
        m.activeNode = invalid
    end if
    m.activeNode = buildNode("ChannelPage")
    if m.activeNode = invalid then return
    m.activeNode.contentRequested = content
    m.activeNode.setFocus(true)
end sub

sub onContentSelected()
    if m.disposed then return
    if m.activeNode = invalid or m.activeNode.contentSelected = invalid then return
    id = invalid
    if m.activeNode.contentSelected.contentType = "STREAMER"
        id = "ChannelPage"
    else if m.activeNode.contentSelected.contentType = "GAME"
        id = "GamePage"
    else if m.activeNode.contentSelected.contentType = "LIVE" or m.activeNode.contentSelected.contentType = "VOD" or m.activeNode.contentSelected.contentType = "USER"
        id = "ChannelPage"
    end if
    if m.activeNode.playContent = true
        id = "VideoPlayer"
    end if
    if id = invalid then return
    holdContent = m.activeNode.contentSelected.getFields()
    content = createObject("roSGNode", "TwitchContentNode")
    setTwitchContentFields(content, holdContent)
    if m.activeNode <> invalid
        ' Save focus before pushing
        focused = lastFocusedChild(m.activeNode)
        if focused <> invalid and focused.id <> m.activeNode.id
            m.activeNode.lastFocus = focused
        else
            m.activeNode.lastFocus = invalid
        end if
        m.footprints.push(m.activeNode)
        m.activeNode = invalid
    end if
    if m.activeNode = invalid
        m.activeNode = buildNode(id)
        if m.activeNode = invalid then return
    end if
    m.activeNode.contentRequested = content
    m.activeNode.setfocus(true)
end sub

' Pinning refreshes the rail while the active Player keeps playback and focus.
sub onPlayerPinChanged(event as object)
    if m.disposed or m.activeNode = invalid then return
    if not event.getRoSGNode().isSameNode(m.activeNode) then return
    if m.recentBar <> invalid then m.recentBar.callFunc("buildItems")
end sub

' Defer retained page I/O until Back returns focus; the Player's workers and
' playback session keep their existing task budget throughout the action.
sub onPlayerFollowChanged(event as object)
    if m.disposed or m.activeNode = invalid then return
    if not event.getRoSGNode().IsSameNode(m.activeNode) then return
    if not m.activeNode.IsSubtype("VideoPlayer") then return
    for each page in m.footprints
        if page.IsSubtype("Following") then page.followRefreshPending = true
    end for
end sub

sub onPlayerSignInRequested(event as object)
    if m.disposed or m.activeNode = invalid then return
    player = event.getRoSGNode()
    if not player.IsSameNode(m.activeNode) or not player.IsSubtype("VideoPlayer") then return
    if player.state <> "done" or not player.channelSignInRequested then return
    ' The Player publishes only after its normal Video/worker exit barrier.
    m.menu.focusItem = "LoginPage"
    openPage("LoginPage")
end sub

' A finished Player is replaced, never retained as a playable footprint.
sub onPlayerChannelRequested(event as object)
    if m.disposed or m.activeNode = invalid then return
    player = event.getRoSGNode()
    if not player.isSameNode(m.activeNode) or not player.isSubtype("VideoPlayer") then return
    if player.state <> "done" or player.channelRequested = invalid then return
    content = player.channelRequested
    m.activeNode = invalid
    discardScene(player)
    ' Opening a VOD from this very profile should return to the retained page.
    if m.footprints.Count() > 0
        previous = m.footprints.Peek()
        if previous.isSubtype("ChannelPage") and previous.contentRequested <> invalid
            if LCase(previous.contentRequested.streamerLogin) = LCase(content.streamerLogin)
                m.activeNode = m.footprints.Pop()
            end if
        end if
    end if
    if m.activeNode = invalid
        m.activeNode = buildNode("ChannelPage")
        if m.activeNode = invalid then return
        m.activeNode.contentRequested = content
    end if
    if m.activeNode.lastFocus <> invalid
        m.activeNode.lastFocus.setFocus(true)
    else
        m.activeNode.setFocus(true)
    end if
end sub

sub onBackPressed()
    if m.disposed or m.activeNode = invalid then return
    if m.activeNode.backPressed = invalid or not m.activeNode.backPressed then return
    if m.recentBar <> invalid then m.recentBar.callFunc("buildItems")
    if m.footprints.Count() > 0
        if m.activeNode <> invalid
            discardScene(m.activeNode)
        end if
        m.activeNode = m.footprints.pop()
        ' Restore focus to previously focused child if available
        if m.activeNode.lastFocus <> invalid
            m.activeNode.lastFocus.setFocus(true)
        else
            m.activeNode.setFocus(true)
        end if
        if focusedMenuItem() = "LoginPage"
            m.menu.setFocus(true)
        end if
    else
        m.menu.setFocus(true)
    end if
end sub

function onKeyEvent(key, press) as boolean
    if not press then return false
    if key = "back"
        ' The rail does not consume Back; return to the page it was entered
        ' from, whose focus handler restores the remembered RowList item.
        if m.recentBar <> invalid and m.recentBar.itemHasFocus = true and m.activeNode <> invalid
            m.recentBar.itemHasFocus = false
            m.activeNode.setFocus(true)
            return true
        end if
        ' Focus can leave the Player while its Task still owns local playback.
        if m.activeNode <> invalid
            if m.activeNode.isSubtype("VideoPlayer")
                ignored = m.activeNode.callFunc("requestBack")
                return true
            end if
        end if
        ' Children consume navigation Back. The remaining root Back requests
        ' cleanup on the main thread before it closes the render thread.
        m.top.exitApp = true
        return true
    end if
    if m.activeNode = invalid then return handleStartupKey(key)

    if key = "replay"
        return true
    end if

    if key = "up"
        if m.activeNode.id <> "GamePage" and m.activeNode.id <> "ChannelPage" and m.activeNode.id <> "VideoPlayer"
            m.recentBar.itemHasFocus = false
            m.menu.setFocus(true)
        end if
        return true
    end if

    if key = "down"
        m.activeNode.setFocus(true)
        return true
    end if

    if key = "left"
        if m.activeNode.id <> "GamePage" and m.activeNode.id <> "ChannelPage" and m.activeNode.id <> "VideoPlayer"
            ' An empty rail has nothing to focus; keep focus on the page.
            m.recentBar.callFunc("buildItems")
            if m.recentBar.hasItems <> true then return true
            m.recentBar.setFocus(true)
            m.recentBar.itemHasFocus = true
            return true
        end if
    end if

    if key = "right"
        if m.recentBar.itemHasFocus = true
            m.recentBar.itemHasFocus = false
            m.activeNode.setFocus(true)
            return true
        end if
    end if

    return false
end function

' With no page, Up/Down move between the menu and the startup recovery panel.
' Up also reaches the menu while the first attempt is still connecting.
function handleStartupKey(key as string) as boolean
    if m.startupStatus = invalid or not m.startupStatus.visible then return false
    if key = "up" and not m.menu.isInFocusChain()
        m.menu.setFocus(true)
        return true
    else if key = "down" and m.startupStatus.hasActions
        m.startupStatus.setFocus(true)
        return true
    end if
    return false
end function

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    if m.changelogDialog <> invalid
        m.changelogDialog.unobserveField("buttonSelected")
        m.changelogDialog.unobserveField("wasClosed")
        if m.top.dialog <> invalid
            if m.top.dialog.isSameNode(m.changelogDialog) then m.top.dialog = invalid
        end if
        m.changelogDialog = invalid
    end if
    if m.recentBar <> invalid
        m.recentBar.unobserveField("contentSelected")
        m.recentBar.unobserveField("hasItems")
    end if
    if m.menu <> invalid
        m.menu.unobserveField("buttonSelected")
    end if
    if m.startupStatus <> invalid
        m.startupStatus.unobserveField("actionSelected")
        disposeNodeTree(m.startupStatus)
    end if
    teardownAllScenes()
    metadataOwner = m.top.findNode("stitchAdMetadataOwner")
    if metadataOwner <> invalid then ignored = metadataOwner.callFunc("onDestroy")
    if m.top.localPlaybackSession <> invalid then ignored = m.top.localPlaybackSession.callFunc("onDestroy")
    disposeNodeTree(m.recentBar)
    disposeNodeTree(m.menu)
    m.validateOauthToken = destroyTask(m.validateOauthToken, "response")
    m.getDeviceCodeTask = destroyTask(m.getDeviceCodeTask, "response")
    if m.global.analyticsTask <> invalid
        m.global.analyticsTask.control = "stop"
        m.global.analyticsTask = invalid
    end if
end sub
