sub init()
    m.disposed = false
    m.top.observeField("focusedChild", "onGetFocus")
    m.background = m.top.findNode("background")
    m.avatar = m.top.findNode("avatar")
    m.title = m.top.findNode("title")
    m.steps = m.top.findNode("steps")
    m.codeGroup = m.top.findNode("codeGroup")
    m.codePlate = m.top.findNode("codePlate")
    m.code = m.top.findNode("code")
    m.qrHint = m.top.findNode("qrHint")
    m.status = m.top.findNode("status")
    m.optional = m.top.findNode("optional")
    m.qrGroup = m.top.findNode("qrGroup")
    m.qrCode = m.top.findNode("qrCode")
    m.actions = m.top.findNode("actions")
    m.actionIds = []
    m.signOutDialog = invalid
    applyActionStyle()
    m.actions.observeField("buttonSelected", "onLoginAction")
    RunContentTask()
end sub

' ButtonGroup fonts are assigned here rather than as XML role children.
sub applyActionStyle()
    ui = m.global?.constants?.ui
    if ui = invalid then return
    font = CreateObject("roSGNode", "Font")
    font.uri = ui.font.bold
    font.size = ui.type.body
    m.actions.textFont = font
    m.actions.focusedTextFont = font
    if m.background <> invalid then m.background.color = ui.color.canvas
end sub

sub handleOauthToken()
    ? "[LoginPage] - handleOauthToken"
    rsp = m.oauthtask.response
    if rsp = invalid
        showLoginFailure(tr("Sign-in expired or could not be completed. Try again to get a new code."))
        return
    end if
    set_user_setting("access_token", rsp.access_token)
    if rsp.refresh_token <> invalid then set_user_setting("refresh_token", rsp.refresh_token)
    set_user_setting("device_code", get_user_setting("temp_device_code"))
    if get_user_setting("device_code") = get_user_setting("temp_device_code")
        unset_user_setting("temp_device_code")
    end if
    getUserLogin()
end sub

sub handleUserLogin()
    ? "[LoginPage] - handleUserLogin()"
    rsp = m.UserLoginTask.response
    if rsp = invalid
        showLoginFailure(tr("Twitch could not load your account. Check your connection and try again."))
        return
    end if
    currentUser = rsp.currentUser
    if currentUser <> invalid and currentUser.login <> invalid
        access_token = get_user_setting("access_token")
        refresh_token = get_user_setting("refresh_token")
        device_code = get_user_setting("device_code")
        unset_user_setting("access_token")
        unset_user_setting("refresh_token")
        unset_user_setting("device_code")
        set_setting("active_user", currentUser.login)
        set_user_setting("login", currentUser.login)
        set_user_setting("access_token", access_token)
        if refresh_token <> invalid then set_user_setting("refresh_token", refresh_token)
        set_user_setting("device_code", device_code)
        ?"Set finished true"
        m.top.finished = true
    else
        showLoginFailure(tr("Twitch could not confirm your account. Try signing in again."))
    end if
end sub

sub getUserLogin()
    ? "[LoginPage] - getUserLogin"
    m.UserLoginTask = createApiTask("getHomePageQuery", "handleUserLogin")
end sub


sub handleRendezvouzToken()
    ? "handle Rendezvouz token"
    rsp = m.RendezvouzTask.response
    if rsp = invalid
        showLoginFailure(tr("Twitch could not create a sign-in code. Check your connection and try again."))
        return
    end if
    set_user_setting("temp_device_code", rsp.device_code)
    showCode(rsp.user_code, rsp.expires_in)
    m.OauthTask = createApiTask("getOauthToken", "handleOauthToken", { params: rsp })
    loadDynamicQr(rsp.user_code)
end sub

' Shows the real activation code. The approval window is the lifetime the
' sign-in request waits for, so it is mentioned only when the response has one.
sub showCode(userCode as dynamic, expiresIn as dynamic)
    if GetInterface(userCode, "ifString") = invalid then userCode = ""
    m.code.text = userCode
    width = 400
    try
        codeWidth = m.code.boundingRect().width
        if codeWidth > 0 then width = codeWidth + 48
    catch e
    end try
    m.codePlate.width = width
    m.codeGroup.visible = userCode <> ""
    m.qrHint.visible = true
    status = tr("Waiting for you to approve…")
    if GetInterface(expiresIn, "ifInt") <> invalid and expiresIn > 0
        minutes = Int((expiresIn + 30) / 60)
        if minutes < 1 then minutes = 1
        status = status + " " + Substitute(tr("This code works for about {0} minutes."), minutes.toStr())
    end if
    m.status.text = status
end sub

sub loadDynamicQr(userCode as string)
    ' Note: twitch.tv/activate accepts the short user_code in its `device-code=`
    ' query parameter — that is Twitch's own naming, not the long OAuth
    ' device_code credential. Do not "fix" this to pass rsp.device_code; the
    ' opaque device_code is not what the activation page expects.
    urlTransfer = CreateObject("roUrlTransfer")
    if urlTransfer = invalid then return
    encodedUrl = urlTransfer.Escape("https://twitch.tv/activate?device-code=" + userCode)
    dynamicUri = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=" + encodedUrl
    m.qrCode.observeField("loadStatus", "onQrLoadStatus")
    m.qrCode.uri = dynamicUri
end sub

sub onQrLoadStatus()
    ' The Poster's loadStatus observer can fire after the scene starts
    ' tearing down (e.g., user logs in via the short code before the QR
    ' image finishes loading), so guard against m.qrCode being invalid.
    if m.qrCode = invalid then return
    status = m.qrCode.loadStatus
    if status = "failed"
        ? "[LoginPage] QR dynamic load failed, using static fallback"
        m.qrCode.unobserveField("loadStatus")
        m.qrCode.uri = "pkg:/images/qr_activate.png"
    else if status = "ready"
        m.qrCode.unobserveField("loadStatus")
    end if
end sub

sub onGetFocus()
    if m.disposed then return
    ' Focus given to the page itself moves to its actions when they are shown.
    if m.top.hasFocus() and m.actions.visible then m.actions.setFocus(true)
end sub

sub RunContentTask()
    if m.disposed then return
    ? "active User: "; get_setting("active_user", "$default$")
    if get_setting("active_user", "$default$") <> "$default$"
        showAccount()
    else
        ? "[LoginPage] - RunContentTask"
        m.RendezvouzTask = destroyTask(m.RendezvouzTask, "response")
        m.OauthTask = destroyTask(m.OauthTask, "response")
        m.UserLoginTask = destroyTask(m.UserLoginTask, "response")
        setTitle(tr("Sign in to Twitch"), false)
        m.title.translation = [110, 104]
        m.avatar.visible = false
        m.steps.text = tr("On your phone or computer, go to twitch.tv/activate and enter this code:")
        m.steps.translation = [110, 168]
        m.steps.visible = true
        m.code.text = ""
        m.codeGroup.visible = false
        m.qrHint.text = tr("Or scan the QR code with your phone.")
        m.qrHint.visible = false
        m.status.text = tr("Getting a sign-in code…")
        m.status.translation = [110, 404]
        m.status.visible = true
        m.optional.text = tr("Signing in is optional — you can watch public streams without an account. Press Back to keep browsing.")
        m.optional.visible = true
        setActions([], [])
        m.qrCode.unobserveField("loadStatus")
        m.qrCode.uri = "pkg:/images/qr_activate.png"
        m.qrGroup.visible = true
        m.RendezvouzTask = createApiTask("getRendezvouzToken", "handleRendezvouzToken")
    end if
end sub

sub showLoginFailure(message as string)
    pageWasFocused = m.top.isInFocusChain()
    m.RendezvouzTask = destroyTask(m.RendezvouzTask, "response")
    m.OauthTask = destroyTask(m.OauthTask, "response")
    m.UserLoginTask = destroyTask(m.UserLoginTask, "response")
    setTitle(tr("Couldn't sign in"), true)
    m.steps.text = message
    m.steps.visible = true
    m.codeGroup.visible = false
    m.qrHint.visible = false
    m.qrGroup.visible = false
    m.status.visible = false
    m.optional.visible = false
    m.actions.translation = [110, 296]
    setActions([tr("Try again"), tr("Back to browsing")], ["retry", "back"])
    if pageWasFocused then m.actions.setFocus(true)
end sub

' Signed in: account status, the user's own channel and sign-out.
sub showAccount()
    login = get_user_setting("login", "")
    name = get_user_setting("display_name", "")
    if name = invalid or name = "" then name = login
    setTitle(name, false)
    m.title.translation = [254, 112]
    avatarUri = get_user_setting("profile_image_url", "")
    if avatarUri = invalid or avatarUri = "" then avatarUri = m.global?.constants?.defaultIcons?.login
    if avatarUri <> invalid then m.avatar.uri = avatarUri
    m.avatar.visible = true
    m.steps.text = Substitute(tr("Signed in to Twitch as {0}."), login)
    m.steps.translation = [254, 168]
    m.steps.visible = true
    m.codeGroup.visible = false
    m.qrHint.visible = false
    m.qrGroup.visible = false
    m.status.text = tr("Signing out keeps your settings and recent channels on this Roku.")
    m.status.translation = [110, 248]
    m.status.visible = true
    m.optional.visible = false
    m.actions.translation = [110, 320]
    setActions([tr("Your channel"), tr("Sign out"), tr("Back")], ["channel", "signout", "back"])
    if m.top.isInFocusChain() then m.actions.setFocus(true)
end sub

sub setTitle(text as string, isError as boolean)
    m.title.text = text
    color = m.global?.constants?.ui?.color
    if color = invalid then return
    if isError
        m.title.color = color.error
    else
        m.title.color = color.text
    end if
end sub

sub setActions(labels as object, ids as object)
    m.actionIds = ids
    m.actions.buttons = labels
    m.actions.visible = labels.count() > 0
    if labels.count() > 0 then m.actions.focusButton = 0
end sub

sub onLoginAction()
    if m.disposed or not m.actions.visible then return
    index = m.actions.buttonSelected
    if index < 0 or index >= m.actionIds.count() then return
    action = m.actionIds[index]
    if action = "retry"
        RunContentTask()
    else if action = "channel"
        openOwnChannel()
    else if action = "signout"
        confirmSignOut()
    else if action = "back"
        m.top.backPressed = true
    end if
end sub

' The user's channel opens like a recent channel: a LIVE request by login, so
' its live row has a card size and plays through the normal live path.
sub openOwnChannel()
    login = get_user_setting("login", "")
    if login = invalid or login = "" then return
    name = get_user_setting("display_name", "")
    if name = invalid or name = "" then name = login
    content = CreateObject("roSGNode", "TwitchContentNode")
    content.contentType = "LIVE"
    content.streamerLogin = login
    content.streamerDisplayName = name
    id = get_user_setting("id", "")
    if id <> invalid and id <> "" then content.streamerId = id
    avatarUri = get_user_setting("profile_image_url", "")
    if avatarUri <> invalid and avatarUri <> "" then content.streamerProfileImageUrl = avatarUri
    m.top.playContent = false
    m.top.contentSelected = content
end sub

sub confirmSignOut()
    if m.signOutDialog <> invalid then return
    dialog = createSignOutDialog()
    dialog.observeField("buttonSelected", "onSignOutChoice")
    dialog.observeField("wasClosed", "onSignOutClosed")
    m.signOutDialog = dialog
    scene = m.top.getScene()
    if scene <> invalid then scene.dialog = dialog
end sub

sub onSignOutChoice()
    if m.disposed or m.signOutDialog = invalid then return
    confirmed = m.signOutDialog.buttonSelected = 0
    closeSignOutDialog()
    if confirmed
        ' Keeps preferences, recent channels and the anonymous device identity.
        signOutAccount()
        ' Emitted last: the scene removes this page in response.
        m.top.signedOut = true
    else
        m.actions.setFocus(true)
    end if
end sub

sub onSignOutClosed()
    if m.disposed or m.signOutDialog = invalid then return
    closeSignOutDialog()
    m.actions.setFocus(true)
end sub

sub closeSignOutDialog()
    dialog = m.signOutDialog
    if dialog = invalid then return
    m.signOutDialog = invalid
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        if scene.dialog.isSameNode(dialog) then scene.dialog = invalid
    end if
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.lastFocus = invalid
    m.top.unobserveField("focusedChild")
    m.actions.unobserveField("buttonSelected")
    closeSignOutDialog()
    if m.qrCode <> invalid
        m.qrCode.unobserveField("loadStatus")
    end if
    m.RendezvouzTask = destroyTask(m.RendezvouzTask, "response")
    m.OauthTask = destroyTask(m.OauthTask, "response")
    m.UserLoginTask = destroyTask(m.UserLoginTask, "response")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        m.top.backPressed = true
        return true
    end if
    return false
end function
