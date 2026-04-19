sub init()
    analyticsTask = CreateObject("roSGNode", "AnalyticsTask")
    analyticsTask.control = "RUN"
    m.global.addFields({ analyticsTask: analyticsTask })

    m.validateOauthToken = createApiTask("validateOauthToken", "ValidateUserLogin")
    VersionJobs()
    m.top.backgroundUri = ""
    m.top.backgroundColor = m.global.constants.colors.hinted.grey1
    m.activeNode = invalid
    m.recentBar = m.top.findNode("recentlyWatchedBar")
    m.recentBar.observeField("contentSelected", "onRecentSelected")
    m.menu = m.top.findNode("MenuBar")
    m.menu.menuOptionsText = [
        "Following",
        "Discover",
        "LiveChannels",
        "Categories",
    ]
    m.menu.observeField("buttonSelected", "onMenuSelection")
    m.menu.setFocus(true)
    if get_setting("active_user") = invalid
        set_setting("active_user", "$default$")
    end if
    if get_user_setting("device_code") = invalid
        m.getDeviceCodeTask = createApiTask("getRendezvouzToken", "handleDeviceCode")
    else
        onMenuSelection()
    end if
    m.footprints = []

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
    active_user = get_setting("active_user", "$default$")
    if active_user <> "$default$"
        unset_user_setting("access_token")
        unset_user_setting("device_code")
        ? "default Registry keys: "; getRegistryKeys("$default$")
        NukeRegistry(active_user)
        set_setting("active_user", "$default$")
        ? "active User: "; get_setting("active_user", "$default$")
    else
        for each key in getRegistryKeys("$default$")
            if key <> "temp_device_code" and key <> "device_code"
                unset_user_setting(key)
            end if
        end for
    end if
end sub

sub ValidateUserLogin()
    if m.validateOauthToken?.response?.tokenValid <> invalid
        tokenValid = m.validateOauthToken.response.tokenValid
    else
        tokenValid = false
    end if
    if tokenValid
        ? "User Token Seems Valid"
    else
        cleanUserData()
        m.menu.updateUserIcon = true
        ? "pause"
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

    currentVersion = m.global.appInfo.Version.Version
    lastSeenVersion = get_setting("last_seen_version")

    changelog = getChangelog()
    sortedVersions = getSortedChangelogVersions(changelog)

    ' Collect changelog entries newer than lastSeenVersion.
    ' When lastSeenVersion is invalid (first install), all entries are shown.
    pendingLines = []
    for each v in sortedVersions
        isNew = lastSeenVersion = invalid or compareVersions(v, lastSeenVersion) > 0
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
    lines.push("Found a bug or have a suggestion? -> bit.ly/roku-twitch")

    dialog = createObject("roSGNode", "StandardMessageDialog")
    dialog.title = "What's New"
    dialog.message = lines
    dialog.buttons = ["Got it"]
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
' Version is intentionally NOT persisted so the dialog shows again next launch.
sub onChangelogDialogClosed()
    if m.changelogDialog <> invalid
        m.changelogDialog.unobserveField("buttonSelected")
        m.changelogDialog.unobserveField("wasClosed")
        m.changelogDialog = invalid
    end if
end sub

sub handleDeviceCode()
    if m.getDeviceCodeTask <> invalid
        response = m.getDeviceCodeTask.response
        if response = invalid then return
        set_user_setting("device_code", response.device_code)
    end if
    onMenuSelection()
end sub

function buildNode(name)
    if name = invalid then return invalid

    ' Dispatch to scene-specific factory
    if name = "Following"
        newNode = build_Following()
    else if name = "Discover"
        newNode = build_Discover()
    else if name = "LiveChannels"
        newNode = build_LiveChannels()
    else if name = "Categories"
        newNode = build_Categories()
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
    else if name = "StreamerChannelPage"
        newNode = build_StreamerChannelPage()
    else
        return invalid
    end if

    if newNode = invalid then return invalid

    ' Shared observer wiring
    newNode.observeField("backPressed", "onBackPressed")
    newNode.observeField("contentSelected", "onContentSelected")

    ' Tree placement
    if name = "GamePage" or name = "ChannelPage" or name = "VideoPlayer" or name = "StreamerChannelPage"
        m.top.appendChild(newNode)
    else
        m.top.insertChild(newNode, 1)
    end if

    return newNode
end function

sub onLoginFinished()
    m.menu.updateUserIcon = true
    if get_user_setting("device_code") = invalid
        m.getDeviceCodeTask = createApiTask("getRendezvouzToken", "handleDeviceCode")
    end if
end sub

sub onMenuSelection()
    menuItem = focusedMenuItem()
    if menuItem <> ""
        trackEvent("tab_visited", { tab: menuItem })
    end if
    isFirstLoad = m.activeNode = invalid
    ' If user is already logged in, show them their user page
    if menuItem = "LoginPage" and get_setting("active_user", "$default$") <> "$default$"
        content = createObject("roSGNode", "TwitchContentNode")
        content.streamerDisplayName = get_user_setting("display_name")
        content.streamerLogin = get_user_setting("login")
        content.streamerId = get_user_setting("id")
        content.streamerProfileImageUrl = get_user_setting("profile_image_url")
        content.contentType = "STREAMER"
        m.activeNode.contentSelected = content
    else
        if m.menu.focusedChild = invalid then return
        if m.activeNode <> invalid and m.activeNode.id.toStr() <> menuItem
            m.top.removeChild(m.activeNode)
            m.activeNode = invalid
        end if
        if m.activeNode = invalid
            m.activeNode = buildNode(menuItem)
            if m.activeNode = invalid then return
        end if
        m.activeNode.setfocus(true)
        if isFirstLoad
            showChangelogDialog()
        end if
    end if
end sub

sub onRecentSelected()
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
    if m.activeNode = invalid or m.activeNode.contentSelected = invalid then return
    id = invalid
    if m.activeNode.contentSelected.contentType = "STREAMER"
        id = "StreamerChannelPage"
    else if m.activeNode.contentSelected.contentType = "GAME"
        id = "GamePage"
    else if m.activeNode.contentSelected.contentType = "LIVE" or m.activeNode.contentSelected.contentType = "VOD" or m.activeNode.contentSelected.contentType = "USER"
        id = "ChannelPage"
    end if
    if m.activeNode.playContent = true
        id = "VideoPlayer"
    end if
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

sub onBackPressed()
    if m.activeNode.backPressed = invalid or not m.activeNode.backPressed then return
    if m.activeNode.id = "StreamerChannelPage"
        if m.footprints.Count() > 0 and m.footprints[0].id = "LoginPage"
            m.footprints.pop()
        end if
        m.top.removeChild(m.activeNode)
        m.activeNode = invalid
        m.menu.buttonFocus = 0
    end if
    if m.footprints.Count() > 0
        if m.activeNode <> invalid
            m.top.removeChild(m.activeNode)
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
    if m.activeNode = invalid then return false

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
        if m.activeNode.id <> "GamePage" and m.activeNode.id <> "ChannelPage" and m.activeNode.id <> "VideoPlayer" and m.activeNode.id <> "StreamerChannelPage"
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

sub onDestroy()
    if m.changelogDialog <> invalid
        m.changelogDialog.unobserveField("buttonSelected")
        m.changelogDialog.unobserveField("wasClosed")
        m.changelogDialog = invalid
    end if
    if m.recentBar <> invalid
        m.recentBar.unobserveField("contentSelected")
    end if
    if m.menu <> invalid
        m.menu.unobserveField("buttonSelected")
    end if
    if m.activeNode <> invalid
        m.activeNode.unobserveField("backPressed")
        m.activeNode.unobserveField("contentSelected")
        m.activeNode.unobserveField("finished")
    end if
    for each node in m.footprints
        if node <> invalid
            node.unobserveField("backPressed")
            node.unobserveField("contentSelected")
            node.unobserveField("finished")
        end if
    end for
    m.validateOauthToken = destroyTask(m.validateOauthToken, "response")
    m.getDeviceCodeTask = destroyTask(m.getDeviceCodeTask, "response")
end sub
