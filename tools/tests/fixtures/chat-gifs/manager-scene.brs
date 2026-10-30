sub init()
    initChatAnimations()
    m.disposed = false
    m.chatPanel = createObject("roSGNode", "Group")
    m.chatPanel.addFields({ width: 600.0, height: 400.0 })
    m.top.appendChild(m.chatPanel)
    m.hypePanel = createObject("roSGNode", "Group")
    m.hypePanel.visible = false
    m.pinPanel = createObject("roSGNode", "Group")
    m.pinPanel.visible = false
    m.checks = 0
    m.failures = 0
    m.font_size = 18
    m.gifAnimationKeys = []
end sub


function fixtureWrapper(uri as string, x as integer) as object
    ' Exercise the actual production admission/title builder in Chat.brs.
    wrapper = buildChatGif({ uri: uri, text: "[GIF title]" })
    wrapper.translation = [x, 0]
    m.chatPanel.appendChild(wrapper)
    return wrapper
end function

' No worker/decoder runs here. The production manager handles native state and
' completion boundaries; Task filesystem/network behavior has its own suite.
function fixtureAssetTask() as object
    task = createObject("roSGNode", "Group")
    task.addFields({ request: {}, response: {}, state: "", control: "", stopRequested: false })
    return task
end function

sub fixtureComplete(info as dynamic)
    task = m.animationTask
    check(task <> invalid, "expected bounded worker/cleanup slot")
    if task = invalid then return
    request = task.request
    if info <> invalid and info.renderer = "gif-atlas" then info.renderPath = request.path.left(request.path.len() - 9) + "atlas.png"
    task.response = { generation: request.generation, uri: request.uri, path: request.path, info: info, removed: request.paths, cleanupOk: true }
    task.state = "done"
end sub

sub check(ok as boolean, label as string)
    m.checks++
    if not ok
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
