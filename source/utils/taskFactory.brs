' Creates a TwitchApiTask, configures it, and starts it.
' functionName: the GraphQL function to call (e.g. "getFollowingPageQuery")
' callback: the callback sub name for the response (e.g. "decideRoute")
' params: optional associative array of request parameters
' Returns the task node.
function createApiTask(functionName as string, callback as string, params = invalid) as object
    task = CreateObject("roSGNode", "TwitchApiTask")
    task.observeField("response", callback)
    request = { type: functionName }
    if params <> invalid
        request.append(params)
    end if
    task.request = request
    task.functionName = functionName
    task.control = "run"
    return task
end function

' Creates a GetTwitchContent task for video/clip playback.
' contentFields: the content fields associative array (from content.getFields())
' callback: the callback sub name for the response
' Returns the task node.
function createContentTask(contentFields as object, callback as string) as object
    task = CreateObject("roSGNode", "GetTwitchContent")
    task.observeField("response", callback)
    task.contentRequested = contentFields
    task.functionName = "main"
    task.control = "run"
    return task
end function

' Creates a Timer node, configures it, and starts it.
' duration: timer duration in seconds
' callback: the callback sub name for the "fire" event
' repeat: whether the timer repeats (default false)
' Returns the timer node.
function createTimer(duration as float, callback as string, repeat = false as boolean) as object
    timer = CreateObject("roSGNode", "Timer")
    timer.observeField("fire", callback)
    timer.duration = duration
    timer.repeat = repeat
    timer.control = "start"
    return timer
end function

' Stops a task or timer, unobserves its field, and returns invalid.
' Use: m.task = destroyTask(m.task, "response")
'      m.timer = destroyTask(m.timer, "fire")
function destroyTask(task, observedField as string) as dynamic
    if task <> invalid
        task.unobserveField(observedField)
        task.control = "stop"
    end if
    return invalid
end function
