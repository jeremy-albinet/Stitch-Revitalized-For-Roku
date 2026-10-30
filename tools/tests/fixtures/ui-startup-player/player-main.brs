' Remote keys on the actual live (StitchVideo) and recorded (CustomVideo)
' player wrappers while their controls are hidden. No media is loaded: the
' playback state, position and duration are fixture inputs, and the wrapper
' outputs (control and seek requests, overlay, time preview) are observed.
sub main()
    m.assertions = 0
    m.failures = 0
    m.port = createObject("roMessagePort")
    screen = createObject("roSGScreen")
    screen.setMessagePort(m.port)
    m.global = screen.getGlobalNode()
    setConstants()
    m.global.addFields({ fixtureRegistry: {} })
    m.scene = screen.createScene("PlayerHost")
    screen.show()

    testPlayKey("StitchVideo")
    testPlayKey("CustomVideo")
    testRecordedSeekKeys()

    screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_UI_FAIL:"; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub testPlayKey(name as string)
    video = addWrapper(name)
    overlay = video.findNode("controlOverlay")
    video.state = "playing"
    press("play")
    waitControl("pause")
    check(m.controls.count() = 1 and m.controls[0] = "pause", name + ": the first hidden Play press pauses")
    check(overlay.visible and video.callFunc("fixtureRead").overlay, name + ": hidden Play also shows the controls")
    settle(400)
    check(m.controls.count() = 1, name + ": releasing Play does not toggle again")

    press("down")
    waitOverlay(video, false)
    video.state = "paused"
    press("play")
    waitControl("resume")
    check(m.controls.count() = 2 and overlay.visible, name + ": the next hidden Play press resumes")

    press("down")
    waitOverlay(video, false)
    press("ok")
    waitOverlay(video, true)
    settle(300)
    check(m.controls.count() = 2, name + ": OK on hidden controls only shows them")
    removeWrapper(video)
end sub

sub testRecordedSeekKeys()
    video = addWrapper("CustomVideo")
    time = video.findNode("timeProgress")
    time.observeField("text", m.port)
    video.duration = 2000
    video.position = 1001
    video.state = "playing"
    m.times = []

    press("rewind")
    waitControl("pause")
    s = video.callFunc("fixtureRead")
    check(s.overlay and video.findNode("controlOverlay").visible and s.seekMode, "hidden Rewind shows the controls and starts a seek preview")
    check(s.held = "left", "hidden Rewind keeps the held-key state")
    settle(400)
    s = video.callFunc("fixtureRead")
    check(s.held = invalid and s.seekMode, "releasing Rewind ends the hold and keeps the preview")
    press("play")
    waitSeek()
    ' A tap can last past the first 0.1 s hold tick, so compare with the preview.
    check(m.seeks.count() = 1 and m.seeks[0] = lastPreview() and m.seeks[0] <= 991, "Play applies the previewed Rewind position")
    check(not video.callFunc("fixtureRead").seekMode, "applying the seek leaves seek mode")

    press("down")
    waitOverlay(video, false)
    count = m.times.count()
    video.position = 1501
    waitTimes(count + 1)
    m.times = [m.times[m.times.count() - 1]]
    hold("rewind", 700)
    waitHeld(video, "left")
    waitHeld(video, invalid)
    steps = timeSteps()
    accelerated = false
    for i = 1 to steps.count() - 1
        if steps[i] < steps[i - 1] then accelerated = true
    end for
    check(steps.count() >= 3 and steps[0] = -10 and accelerated, "holding Rewind speeds up the preview steps")
    count = m.times.count()
    press("rewind")
    waitTimes(count + 1)
    steps = timeSteps()
    check(steps[steps.count() - 1] = -10, "after release the next Rewind press steps 10 seconds again")
    press("play")
    waitSeek()
    check(m.seeks.count() = 2 and m.seeks[1] = lastPreview(), "Play applies the previewed position after a hold")

    press("down")
    waitOverlay(video, false)
    video.position = 1201
    count = m.times.count()
    press("fastforward")
    waitTimes(count + 2)
    s = video.callFunc("fixtureRead")
    check(s.overlay and s.seekMode, "hidden Fast-forward shows the controls and starts a seek preview")
    press("play")
    waitSeek()
    check(m.seeks.count() = 3 and m.seeks[2] = lastPreview() and m.seeks[2] >= 1211, "Play applies the previewed Fast-forward position")
    time.unobserveField("text")
    removeWrapper(video)
end sub

function addWrapper(name as string) as object
    video = createObject("roSGNode", name)
    m.scene.appendChild(video)
    video.setFocus(true)
    m.controls = []
    m.seeks = []
    m.times = []
    video.observeField("control", m.port)
    video.observeField("seek", m.port)
    return video
end function

sub removeWrapper(video as object)
    video.unobserveField("control")
    video.unobserveField("seek")
    video.callFunc("onDestroy")
    m.scene.removeChild(video)
end sub

' Seconds between successive previewed times, oldest first.
function timeSteps() as object
    seconds = []
    for each text in m.times
        seconds.push(toSeconds(text))
    end for
    steps = []
    for i = 1 to seconds.count() - 1
        steps.push(seconds[i] - seconds[i - 1])
    end for
    return steps
end function

function lastPreview() as integer
    if m.times.count() = 0 then return -1
    return toSeconds(m.times[m.times.count() - 1])
end function

function toSeconds(text as string) as integer
    total = 0
    for each part in text.split(":")
        total = total * 60 + part.toInt()
    end for
    return total
end function

sub press(key as string)
    print "FIXTURE_KEY:" + key
end sub

sub hold(key as string, duration as integer)
    print "FIXTURE_HOLD:" + key + ":" + duration.toStr()
end sub

sub waitControl(value as string)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 3000
        if m.controls.count() > 0 and m.controls[m.controls.count() - 1] = value then return
        pump(20)
    end while
    fail("timed out waiting for control " + value)
end sub

sub waitSeek()
    count = m.seeks.count()
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 3000
        if m.seeks.count() > count then return
        pump(20)
    end while
    fail("timed out waiting for a seek")
end sub

' Waits until at least count time-preview texts were observed.
sub waitTimes(count as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 3000
        if m.times.count() >= count then return
        pump(20)
    end while
    fail("timed out waiting for a time preview")
end sub

sub waitOverlay(video as object, visible as boolean)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 3000
        if video.findNode("controlOverlay").visible = visible then return
        pump(20)
    end while
    fail("timed out waiting for overlay visible=" + visible.toStr())
end sub

sub waitHeld(video as object, value as dynamic)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 3000
        if video.callFunc("fixtureRead").held = value then return
        pump(20)
    end while
    fail("timed out waiting for the held key to clear")
end sub

sub settle(duration as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < duration
        pump(20)
    end while
end sub

sub pump(duration as integer)
    msg = wait(duration, m.port)
    if type(msg) <> "roSGNodeEvent" then return
    field = msg.getField()
    if field = "control"
        m.controls.push(msg.getData())
    else if field = "seek"
        m.seeks.push(msg.getData())
    else if field = "text" and msg.getData() <> ""
        m.times.push(msg.getData())
    end if
end sub

sub fail(message as string)
    m.failures += 1
    print "STITCH_UI_FAIL:"; message
end sub

sub check(condition as boolean, message as string)
    if condition
        m.assertions += 1
    else
        fail(message)
    end if
end sub
