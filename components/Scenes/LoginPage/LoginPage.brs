sub init()
    m.top.observeField("itemHasFocus", "onGetfocus")
    m.code = m.top.findNode("code")
    m.loginText = m.top.findNode("topText")
    m.bottomText = m.top.findNode("bottomText")
    m.buttonGroup = m.top.findNode("buttonGroup")
    m.qrCode = m.top.findNode("qrCode")
    RunContentTask()
end sub

sub handleOauthToken()
    ? "[LoginPage] - handleOauthToken"
    rsp = m.oauthtask.response
    if rsp = invalid then return
    set_user_setting("access_token", rsp.access_token)
    set_user_setting("device_code", get_user_setting("temp_device_code"))
    if get_user_setting("device_code") = get_user_setting("temp_device_code")
        unset_user_setting("temp_device_code")
    end if
    getUserLogin()
end sub

sub handleUserLogin()
    ? "[LoginPage] - handleUserLogin()"
    rsp = m.UserLoginTask.response
    if rsp = invalid then return
    currentUser = rsp.currentUser
    if currentUser <> invalid and currentUser.login <> invalid
        access_token = get_user_setting("access_token")
        device_code = get_user_setting("device_code")
        unset_user_setting("access_token")
        unset_user_setting("device_code")
        set_setting("active_user", currentUser.login)
        set_user_setting("login", currentUser.login)
        set_user_setting("access_token", access_token)
        set_user_setting("device_code", device_code)
        ' TODO: Yet again with the static reference that should be fixed.
        ' Parent = heroScene, child 1 = MenuBar, child 3 = ButtonGroup, child 6 = loginIconButton
        ?"Set finished true"
        m.top.finished = true
    end if
    RunContentTask()
end sub

sub getUserLogin()
    ? "[LoginPage] - getUserLogin"
    m.UserLoginTask = createApiTask("getHomePageQuery", "handleUserLogin")
end sub


sub handleRendezvouzToken()
    ? "handle Rendezvouz token"
    rsp = m.RendezvouzTask.response
    if rsp = invalid then return
    set_user_setting("temp_device_code", rsp.device_code)
    m.code.text = rsp.user_code
    m.OauthTask = createApiTask("getOauthToken", "handleOauthToken", { params: rsp })
    loadDynamicQr(rsp.user_code)
end sub

sub loadDynamicQr(userCode as string)
    ' Note: twitch.tv/activate accepts the short user_code in its `device-code=`
    ' query parameter — that is Twitch's own naming, not the long OAuth
    ' device_code credential. Do not "fix" this to pass rsp.device_code; the
    ' opaque device_code is not what the activation page expects.
    urlTransfer = CreateObject("roUrlTransfer")
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
    ? "got focus"
    if m.top.focusedChild = invalid
        if m.buttonGroup.visible
            m.buttonGroup.setFocus(true)
        end if
    end if
end sub

sub RunContentTask()
    ? "active User: "; get_setting("active_user", "$default$")
    if get_setting("active_user", "$default$") <> "$default$"
        ' Already logged in — dismiss LoginPage and return to the previous scene.
        m.top.backPressed = true
    else
        ? "[LoginPage] - RunContentTask"
        m.code.visible = true
        m.loginText.visible = true
        m.bottomText.visible = true
        m.buttonGroup.visible = false
        m.qrCode.visible = true
        m.RendezvouzTask = createApiTask("getRendezvouzToken", "handleRendezvouzToken")
    end if
end sub

sub onDestroy()
    if m.qrCode <> invalid
        m.qrCode.unobserveField("loadStatus")
    end if
    m.RendezvouzTask = destroyTask(m.RendezvouzTask, "response")
    m.OauthTask = destroyTask(m.OauthTask, "response")
    m.UserLoginTask = destroyTask(m.UserLoginTask, "response")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    m.top.backPressed = true
    return true
end function
