sub init()
    m.top.observeField("itemHasFocus", "onGetfocus")
    m.code = m.top.findNode("code")
    m.loginText = m.top.findNode("topText")
    m.bottomText = m.top.findNode("bottomText")
    m.buttonGroup = m.top.findNode("buttonGroup")
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
        m.code.visible = false
        m.loginText.visible = false
        m.bottomText.visible = false
        content = createObject("roSGNode", "TwitchContentNode")
        content.streamerDisplayName = get_user_setting("display_name")
        content.streamerLogin = get_user_setting("login")
        content.streamerId = get_user_setting("id")
        content.streamerProfileImageUrl = get_user_setting("profile_image_url")
        content.contentType = "STREAMER"
        m.top.contentSelected = content
    else
        ? "[LoginPage] - RunContentTask"
        m.code.visible = true
        m.loginText.visible = true
        m.bottomText.visible = true
        m.buttonGroup.visible = false
        m.RendezvouzTask = createApiTask("getRendezvouzToken", "handleRendezvouzToken")
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    m.top.backPressed = true
    return true
end function
