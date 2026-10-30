' One optional metadata request per selected stream. Quality changes and
' recovery replace the Video wrapper without repeating this notice.
sub updateContentAdvisory()
    if m.disposed or m.isExiting or m.video = invalid then return
    if m.top.contentRequested = invalid or m.video.state <> "playing" then return
    if m.top.contentRequested.contentType <> "LIVE" then return
    if m.advisoryChecked <> true
        m.advisoryChecked = true
        login = m.top.contentRequested.streamerLogin
        if GetInterface(login, "ifString") = invalid or login.Trim() = "" then return
        m.advisoryOwner = m.top.contentRequested
        m.advisoryTask = CreateObject("roSGNode", "TwitchApiTask")
        m.advisoryTask.observeField("response", "onContentAdvisoryResponse")
        m.advisoryTask.request = { params: { login: login } }
        m.advisoryTask.functionName = "getContentAdvisoryQuery"
        m.advisoryTask.control = "run"
    end if
    panel = m.top.findNode("contentAdvisory")
    if panel.visible
        m.top.removeChild(panel)
        m.top.appendChild(panel)
    end if
    if m.advisoryShown = true or GetInterface(m.advisoryLabels, "ifArray") = invalid then return
    if m.advisoryLabels.Count() = 0 then return
    m.advisoryShown = true
    title = m.top.findNode("advisoryTitle")
    title.text = tr("Intended for certain audiences")
    names = []
    for each name in m.advisoryLabels
        if name = "" then name = tr("Additional audience advisory")
        names.Push(name)
    end for
    label = m.top.findNode("advisoryLabels")
    label.text = names.Join(" " + Chr(183) + " ")
    height = 192
    try
        height = label.translation[1] + label.boundingRect().height + 16
    catch e
    end try
    if height < 96 then height = 96
    if height > 232 then height = 232
    m.top.findNode("advisoryPlate").height = height
    m.top.findNode("advisoryAccent").height = height
    ' Playback wrappers are appended dynamically; keep this notice above them.
    m.top.removeChild(panel)
    m.top.appendChild(panel)
    panel.visible = true
    m.advisoryTimer = CreateObject("roSGNode", "Timer")
    m.advisoryTimer.duration = 5
    m.advisoryTimer.repeat = false
    m.advisoryTimer.observeField("fire", "hideContentAdvisory")
    m.advisoryTimer.control = "start"
end sub

sub onContentAdvisoryResponse(event as object)
    if m.disposed or m.isExiting or m.advisoryTask = invalid then return
    if not event.GetRoSGNode().isSameNode(m.advisoryTask) then return
    response = event.GetData()
    m.advisoryTask = destroyTask(m.advisoryTask, "response")
    if m.advisoryOwner = invalid or m.top.contentRequested = invalid then return
    if not m.advisoryOwner.isSameNode(m.top.contentRequested) then return
    if response = invalid then return
    m.advisoryLabels = response.labels
    updateContentAdvisory()
end sub

sub hideContentAdvisory()
    panel = m.top.findNode("contentAdvisory")
    if panel <> invalid then panel.visible = false
    if m.advisoryTimer <> invalid
        m.advisoryTimer.control = "stop"
        m.advisoryTimer.unobserveField("fire")
        m.advisoryTimer = invalid
    end if
end sub

sub resetContentAdvisory()
    m.advisoryTask = destroyTask(m.advisoryTask, "response")
    hideContentAdvisory()
    m.advisoryOwner = invalid
    m.advisoryLabels = invalid
    m.advisoryChecked = false
    m.advisoryShown = false
end sub
