function playerChannelOwner(content as object) as object
    source = m.top.contentRequested
    return { account: get_setting("active_user", "$default$"), token: get_user_setting("access_token", ""), video: m.video, source: source, sourceLogin: source.streamerLogin, login: content.streamerLogin, id: content.streamerId, contentId: source.contentId, contentType: source.contentType, clipSlug: source.clipSlug }
end function

function playerChannelOwnerCurrent(owner as dynamic) as boolean
    if owner = invalid or m.disposed or m.isExiting or m.rokuExitPending then return false
    if m.video = invalid or m.top.contentRequested = invalid then return false
    if not m.video.IsSameNode(owner.video) or not m.top.contentRequested.IsSameNode(owner.source) then return false
    if owner.account <> get_setting("active_user", "$default$") or owner.token <> get_user_setting("access_token", "") then return false
    source = m.top.contentRequested
    return source.streamerLogin = owner.sourceLogin and source.streamerId = owner.id and source.contentId = owner.contentId and source.contentType = owner.contentType and source.clipSlug = owner.clipSlug
end function

function playerFollowCacheCurrent() as boolean
    if m.channelFollowCache = invalid then return false
    return playerChannelOwnerCurrent(m.channelFollowCache.owner)
end function

function playerFollowMenu() as object
    owner = m.channelActionsOwner
    if owner.account = "$default$" or owner.token = "" then return { id: "signin", label: tr("Sign in to follow"), state: invalid }
    if LCase(owner.account) = LCase(owner.login) then return { id: "self", label: tr("Your channel"), state: invalid }
    if playerFollowCacheCurrent()
        state = m.channelFollowCache.state
        if state.isSelf then return { id: "self", label: tr("Your channel"), state: state }
        if state.following then return { id: "unfollow", label: tr("Unfollow"), state: state }
        return { id: "follow", label: tr("Follow"), state: state }
    end if
    m.channelFollowCache = invalid
    return { id: "status", label: tr("Check follow status"), state: invalid }
end function

sub handleChannelFollowAction(action as string)
    if m.channelFollowTask <> invalid then return
    if action = "status" or m.channelActionsFollowComplete = true
        if playerFollowCacheCurrent()
            ' The user's explicit refresh resets native focus predictably. Never
            ' replace buttons in response to an asynchronous field notification.
            closeChannelActions(false)
            showPlayerChannelActions()
        else
            startChannelFollow(false)
        end if
    else
        startChannelFollow(true)
    end if
end sub

sub startChannelFollow(write as boolean)
    if not channelFollowDialogCurrent() or m.channelFollowTask <> invalid then return
    owner = m.channelActionsOwner
    if owner.account = "$default$" or owner.token = "" then return
    params = { account: owner.account, login: owner.login, id: owner.id }
    functionName = "getPlayerFollowState"
    if write
        state = m.channelActionsFollowState
        if state = invalid or not playerFollowCacheCurrent() then return
        if state.isSelf or LCase(state.login) <> LCase(owner.login) then return
        if state.following <> m.channelFollowCache.state.following then return
        params.id = state.id
        params.viewerId = state.viewerId
        params.following = not state.following
        functionName = "setPlayerFollowState"
        m.channelFollowCache = invalid
    end if
    cancelChannelFollow()
    generation = m.channelFollowGeneration
    task = CreateObject("roSGNode", "TwitchApiTask")
    task.request = { params: params, generation: generation }
    task.functionName = functionName
    task.ObserveField("response", "onChannelFollowResponse")
    m.channelFollowTask = task
    m.channelFollowContext = { owner: owner, dialog: m.channelActionsDialog, generation: generation, write: write }
    ' Each worker performs at most three 8-second HTTP requests, once each.
    m.channelFollowTimer = createTimer(26, "onChannelFollowTimeout")
    message = tr("Checking follow status…")
    if write then message = tr("Updating follow status…")
    setChannelFollowMessage(message)
    task.control = "run"
end sub

function channelFollowDialogCurrent() as boolean
    if m.channelActionsDialog = invalid or not playerChannelOwnerCurrent(m.channelActionsOwner) then return false
    scene = m.top.GetScene()
    if scene = invalid or scene.dialog = invalid then return false
    return scene.dialog.IsSameNode(m.channelActionsDialog)
end function

function channelFollowRequestCurrent(task as object) as boolean
    context = m.channelFollowContext
    if context = invalid or m.channelFollowTask = invalid then return false
    if not task.IsSameNode(m.channelFollowTask) then return false
    if task.request.generation <> context.generation or context.generation <> m.channelFollowGeneration then return false
    if not channelFollowDialogCurrent() then return false
    return m.channelActionsDialog.IsSameNode(context.dialog) and playerChannelOwnerCurrent(context.owner)
end function

sub onChannelFollowResponse(event as object)
    task = event.getRoSGNode()
    if not channelFollowRequestCurrent(task)
        if m.channelFollowTask <> invalid
            if task.IsSameNode(m.channelFollowTask) then cancelChannelFollow()
        end if
        return
    end if
    context = m.channelFollowContext
    rsp = task.response
    cancelChannelFollow()
    if rsp = invalid
        m.channelFollowCache = invalid
        m.channelActionsFollowComplete = true
        setChannelFollowMessage(tr("Couldn't confirm follow status. Select again to check, or close this menu and try later."))
        return
    end if
    ' The worker boundary validates the authenticated viewer and broadcaster.
    ' Check the returned flat identity again at the component boundary.
    if rsp.account <> context.owner.account or LCase(rsp.login) <> LCase(context.owner.login) then return
    if context.owner.id <> "" and rsp.id <> context.owner.id then return
    m.channelFollowCache = { owner: context.owner, state: rsp }
    message = tr("Not following this channel.")
    if rsp.following then message = tr("Following this channel.")
    if rsp.isSelf then message = tr("You can't follow your own channel.")
    setChannelFollowMessage(message + " " + tr("Select again to refresh this menu."))
    if context.write
        m.channelActionsFollowComplete = true
        m.top.channelFollowChanged = true
    end if
end sub

sub onChannelFollowTimeout(event as object)
    if m.channelFollowTimer = invalid or m.channelFollowTask = invalid then return
    if not event.getRoSGNode().IsSameNode(m.channelFollowTimer) then return
    if not channelFollowRequestCurrent(m.channelFollowTask)
        cancelChannelFollow()
        return
    end if
    cancelChannelFollow()
    m.channelFollowCache = invalid
    m.channelActionsFollowComplete = true
    setChannelFollowMessage(tr("Couldn't confirm follow status. Select again to check, or close this menu and try later."))
end sub

sub setChannelFollowMessage(message as string)
    if not channelFollowDialogCurrent() then return
    m.channelActionsDialog.message = [m.channelActionsName, message]
end sub

sub cancelChannelFollow()
    if m.channelFollowGeneration = invalid then m.channelFollowGeneration = 0
    m.channelFollowGeneration++
    if m.channelFollowTimer <> invalid
        m.channelFollowTimer.control = "stop"
        m.channelFollowTimer.UnobserveField("fire")
        m.channelFollowTimer = invalid
    end if
    if m.channelFollowTask <> invalid then m.channelFollowTask.followStopRequested = true
    m.channelFollowTask = destroyTask(m.channelFollowTask, "response")
    m.channelFollowContext = invalid
end sub
