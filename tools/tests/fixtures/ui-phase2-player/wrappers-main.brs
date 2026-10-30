' Real remote keys on the actual recorded (CustomVideo) and live (StitchVideo)
' player wrappers: seek preview apply/cancel with the earlier play state, the
' initial hold delay, fade suppression, captions, the quality dialog marker
' and the low-latency tag. No media is loaded: playback state, position and
' duration are fixture inputs; control and seek requests are observed.
sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()

    testPreviewApplyCancel()
    testHoldDelay()
    testRecordedCaptions()
    testLiveControls()
    testInfoRowLines()
    testTimeDialogOnTop()

    fixtureEnd()
end sub

' Jump to time is modal: no visible node drawn after it may cover it, such as
' the raised control overlay with its scrim and title.
sub testTimeDialogOnTop()
    video = recordedVideo(1000)
    press("up")
    waitRead(video, "overlay", true, "the controls")
    press("left")
    press("left")
    waitRead(video, "focused", 1, "focus on Jump to time")
    press("ok")
    waitRead(video, "timeTravelOpen", true, "the time dialog")
    settle(200)
    dialog = video.findNode("timeTravelDialog")
    plate = sceneRect(video.findNode("timeTravelPlate"))
    covered = ""
    after = false
    for i = 0 to video.getChildCount() - 1
        child = video.getChild(i)
        if child.isSameNode(dialog)
            after = true
        else if after and child.visible and overlaps(plate, sceneRect(child))
            covered = covered + " " + child.id
        end if
    end for
    check(plate.height > 0 and after, "the Jump to time dialog is laid out")
    check(covered = "", "nothing visible is drawn over the Jump to time dialog:" + covered)
    press("back")
    waitRead(video, "timeTravelOpen", false, "the time dialog to close")
    removeWrapper(video)
end sub

function overlaps(a as object, b as object) as boolean
    if b.width <= 0 or b.height <= 0 then return false
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end function

' EmojiLabel is positioned by the center of its line, so the title is checked
' through the boxes the engine lays out, not through XML numbers: it must sit
' below the channel name and the LIVE badge, and above the recorded time.
sub testInfoRowLines()
    for each name in ["StitchVideo", "CustomVideo"]
        video = addWrapper(name)
        if name = "CustomVideo"
            video.video_type = "VOD"
            video.duration = 2000
            video.position = 1000
        end if
        video.state = "playing"
        ' Engine boundary: XML alias fields do not reach the child labels here.
        video.findNode("channelUsername").text = "Cubesmith"
        video.findNode("videoTitle").text = "Building the mega base (day 41)"
        press("up")
        waitRead(video, "overlay", true, name + " controls")
        settle(300)
        title = sceneRect(video.findNode("videoTitle"))
        user = sceneRect(video.findNode("channelUsername"))
        check(title.height > 0 and user.height > 0, name + ": the name and title lines are laid out")
        check(title.y >= user.y + user.height, name + ": the title line starts below the channel name")
        if name = "StitchVideo"
            badge = sceneRect(video.findNode("liveBadge"))
            check(title.y >= badge.y + badge.height, name + ": the title line starts below the LIVE badge")
        else
            time = sceneRect(video.findNode("timeProgress"))
            check(title.y + title.height <= time.y, name + ": the title line ends above the time labels")
        end if
        removeWrapper(video)
    end for
end sub

function sceneRect(node as object) as object
    try
        return node.sceneBoundingRect()
    catch e
        fail("sceneBoundingRect failed: " + e.message)
    end try
    return { x: 0, y: 0, width: 0, height: 0 }
end function

function addWrapper(name as string) as object
    video = createObject("roSGNode", name)
    m.scene.appendChild(video)
    video.setFocus(true)
    m.seen = {}
    for each field in ["control", "seek", "toggleChat", "QualityChangeRequestFlag"]
        if video.hasField(field) then video.observeField(field, m.port)
    end for
    return video
end function

sub removeWrapper(video as object)
    for each field in ["control", "seek", "toggleChat", "QualityChangeRequestFlag"]
        if video.hasField(field) then video.unobserveField(field)
    end for
    video.callFunc("onDestroy")
    m.scene.removeChild(video)
end sub

function recordedVideo(position as integer) as object
    video = addWrapper("CustomVideo")
    video.video_type = "VOD"
    video.duration = 2000
    video.position = position
    video.state = "playing"
    return video
end function

sub testPreviewApplyCancel()
    video = recordedVideo(1000)

    ' A tap: the engine releases a key 150 ms after the press, before the
    ' 0.4 s hold delay, so exactly one 10 second step is previewed.
    press("fastforward")
    waitSeen("control", 1, "the preview to pause")
    settle(900)
    s = video.callFunc("fixtureRead")
    check(lastSeen("control") = "pause" and s.seekMode and s.preview = 1010, "a hidden Fast-forward tap pauses and previews exactly one 10 s step")
    check(s.held = invalid, "the tap ends the hold")
    check(s.hintVisible and not s.infoVisible and s.hint = "Press OK or Play to jump to 16:50. Press Back to cancel.", "the instruction replaces the title while previewing")
    check(s.caption = "Jump to 16:50" and s.captionVisible, "Play/Pause names the pending jump")
    check(colorHex(s.knob) = uiNormalizeHex(m.ui.focus), "the knob turns focus purple while a jump is pending")
    check(seen("seek").count() = 0, "previewing does not seek")

    ' The real fade timer (5 s after the last key) fires but cannot hide the
    ' controls while a preview is pending.
    settle(5600)
    s = video.callFunc("fixtureRead")
    check(s.overlay and s.seekMode, "the fade timer keeps the controls during a preview")

    press("back")
    waitSeen("control", 2, "cancel to resume")
    s = video.callFunc("fixtureRead")
    check(lastSeen("control") = "resume", "Back cancels and resumes a video that was playing")
    check(not s.seekMode and s.overlay and s.infoVisible and not s.hintVisible, "after cancel the controls stay and the title returns")
    check(seen("seek").count() = 0 and s.preview = 1000 and s.position = "16:40", "cancel shows the playing position again without seeking")
    check(colorHex(s.knob) = uiNormalizeHex(m.ui.text), "the knob returns to its normal color")

    ' Positive control: without a preview the same timer hides the controls.
    settle(5600)
    check(not video.callFunc("fixtureRead").overlay, "without a preview the controls fade after 5 s")

    ' Paused before the preview: the jump keeps it paused.
    video.state = "paused"
    press("fastforward")
    waitRead(video, "preview", 1010, "the paused preview")
    press("play")
    waitSeen("seek", 1, "the jump")
    settle(400)
    s = video.callFunc("fixtureRead")
    check(seen("seek")[0].data = 1010 and not s.seekMode, "Play applies the previewed position")
    check(lastSeen("control") = "pause", "a video paused before the preview stays paused after the jump")

    ' Down hides the controls and drops a pending preview.
    video.state = "playing"
    video.position = 1200
    press("rewind")
    waitRead(video, "preview", 1190, "the Rewind preview")
    press("down")
    waitRead(video, "overlay", false, "Down to hide the controls")
    settle(300)
    s = video.callFunc("fixtureRead")
    check(lastSeen("control") = "resume" and not s.seekMode and not s.overlay and seen("seek").count() = 1, "Down cancels the preview, resumes and hides the controls")
    removeWrapper(video)
end sub

sub testHoldDelay()
    video = recordedVideo(2000)
    video.duration = 4000
    ' Capture the timer's effective duration at the actual progress changes,
    ' in the component callback. Main-port dequeue timestamps can bunch up
    ' when a busy worker drains queued events and do not measure this delay.
    video.callFunc("fixtureObserveHold")
    hold("fastforward", 1300)
    waitRead(video, "held", "right", "the hold to start")
    waitRead(video, "held", invalid, "the hold to end")
    texts = video.callFunc("fixtureFinishHold")
    steps = []
    for i = 1 to texts.count() - 1
        steps.push(toSeconds(texts[i].data) - toSeconds(texts[i - 1].data))
    end for
    check(texts.count() > 0 and toSeconds(texts[0].data) = 2010, "the press itself steps 10 s at once")
    growing = steps.count() >= 4
    if growing then growing = steps[0] = 10 and steps[1] = 15 and steps[2] = 20 and steps[3] = 25
    check(growing, "a held key repeats 10, 15, 20, 25 s ... after the delay")
    initialDelay = texts.count() >= 2
    if initialDelay then initialDelay = texts[0].duration = 0.4 and texts[1].duration = 0.4
    check(initialDelay, "the initial step and first repeat use the actual 0.4 s hold timer")
    fastRepeats = texts.count() >= 3
    for i = 2 to texts.count() - 1
        if texts[i].duration <> 0.1 then fastRepeats = false
    end for
    check(fastRepeats, "later accelerated repeats use the actual 0.1 s hold timer")
    preview = video.callFunc("fixtureRead").preview
    settle(300)
    check(video.callFunc("fixtureRead").preview = preview, "release stops the accelerated preview steps")
    press("play")
    waitSeen("seek", 1, "the held jump")
    waitSeen("control", 2, "resume after the held jump")
    check(seen("seek")[0].data = preview and lastSeen("control") = "resume", "Play applies the held preview and resumes")
    removeWrapper(video)
end sub

sub testRecordedCaptions()
    video = recordedVideo(1500)
    press("up")
    waitRead(video, "overlay", true, "the controls")
    s = video.callFunc("fixtureRead")
    check(s.focused = 3 and s.caption = "Pause" and s.captionVisible, "Play/Pause names its action")
    check(s.controlsX = 418, "six controls form one group centered in the video area")

    press("left")
    waitRead(video, "focused", 2, "focus on -10")
    check(video.callFunc("fixtureRead").caption = "Back 10 seconds", "-10 names itself")
    press("ok")
    waitRead(video, "preview", 1490, "the -10 preview")
    s = video.callFunc("fixtureRead")
    check(s.hint = "Press Play to jump to 24:50. Press Back to cancel." and s.caption = "Back 10 seconds", "away from Play/Pause the instruction points to the Play key")

    press("left")
    waitRead(video, "focused", 1, "focus on Jump to time")
    check(video.callFunc("fixtureRead").caption = "Jump to time", "Jump to time names itself")
    press("ok")
    waitRead(video, "timeTravelOpen", true, "the time dialog")
    settle(300)
    s = video.callFunc("fixtureRead")
    check(not s.seekMode and lastSeen("control") = "resume", "opening Jump to time cancels the pending preview")
    check(s.lengthText = "Video length: 33:20", "the time dialog states the video length")
    press("back")
    waitRead(video, "timeTravelOpen", false, "the time dialog to close")

    for i = 1 to 4
        press("right")
    end for
    waitRead(video, "focused", 5, "focus on chat")
    check(video.callFunc("fixtureRead").caption = "Chat replay unavailable", "the recorded chat button says replay is unavailable")
    press("ok")
    waitSeen("toggleChat", 1, "the chat request")
    check(lastSeen("toggleChat") = true, "the chat button still asks the player for the notice")
    press("right")
    waitRead(video, "focused", 0, "focus on Back")
    check(video.callFunc("fixtureRead").caption = "Exit player", "Back names itself")
    press("down")
    waitRead(video, "overlay", false, "the controls to hide")
    check(not video.callFunc("fixtureRead").captionVisible, "the caption hides with the controls")
    removeWrapper(video)
end sub

sub testLiveControls()
    video = addWrapper("StitchVideo")
    video.qualityOptions = ["1080p60", "720p60", "480p"]
    video.selectedQuality = "1080p60"
    video.state = "playing"
    s = video.callFunc("fixtureRead")
    check(not s.tagVisible and s.live = "LIVE", "a stable session shows LIVE without the low-latency tag")

    press("up")
    waitRead(video, "overlay", true, "the live controls")
    s = video.callFunc("fixtureRead")
    check(s.caption = "Pause" and s.controlsX = 494 and s.scrimWidth = 1280, "live controls are centered across the full video area")
    video.chatIsVisible = true
    waitRead(video, "controlsX", 334, "the chat layout")
    check(video.callFunc("fixtureRead").scrimWidth = 960, "with chat shown the scrim and controls fit the 960 px video area")
    press("left")
    waitRead(video, "focused", 1, "focus on chat")
    check(video.callFunc("fixtureRead").caption = "Hide chat", "the chat button names hiding chat")
    video.chatIsVisible = false
    waitRead(video, "caption", "Show chat", "the chat caption")
    check(video.callFunc("fixtureRead").controlsX = 494, "hidden chat restores the full-width layout")

    press("right")
    press("right")
    waitRead(video, "focused", 3, "focus on quality")
    check(video.callFunc("fixtureRead").caption = "Quality · 1080p60", "the quality button names the current quality")
    press("ok")
    waitRead(video, "dialogVisible", true, "the quality dialog")
    s = video.callFunc("fixtureRead")
    buttons = s.dialogButtons
    marked = buttons.count() = 4
    if marked then marked = buttons[0] = "1080p60 (current)" and buttons[1] = "720p60" and buttons[2] = "480p" and buttons[3] = "Cancel"
    check(s.dialogTitle = "Video quality" and s.dialogMessage.count() = 1 and s.dialogMessage[0] = "Now playing: 1080p60", "the dialog is titled and states the playing quality")
    check(marked, "options keep their order, the current one is marked and Cancel is last")
    check(s.ownsDialog, "the quality picker is registered as the Scene modal for native Back handling")
    ' Exercise the dialog's selection callback independently of native button rendering.
    s.dialog.buttonSelected = 1
    waitSeen("QualityChangeRequestFlag", 1, "the quality request")
    check(video.QualityChangeRequest = 1 and video.selectedQuality = "720p60" and not video.callFunc("fixtureRead").dialogVisible, "choosing the second option requests index 1 as before")

    press("ok")
    waitRead(video, "dialogVisible", true, "the quality dialog again")
    buttons = video.callFunc("fixtureRead").dialogButtons
    check(buttons[0] = "1080p60" and buttons[1] = "720p60 (current)", "the marker follows the new quality")
    press("back")
    waitRead(video, "dialogVisible", false, "Back to close the dialog")
    check(seen("QualityChangeRequestFlag").count() = 1, "closing the dialog requests no change")
    check(not video.callFunc("fixtureRead").ownsDialog and video.callFunc("fixtureRead").fade = "start", "Back releases the modal and restarts the controls timer")
    press("ok")
    waitRead(video, "dialogVisible", true, "the quality dialog after Back")
    video.callFunc("fixtureRead").dialog.close = true
    waitRead(video, "dialogVisible", false, "the native dialog close event")
    check(not video.callFunc("fixtureRead").ownsDialog and seen("QualityChangeRequestFlag").count() = 1, "native dialog dismissal cancels without requesting a quality")
    press("ok")
    waitRead(video, "dialogVisible", true, "the quality dialog before replacement")
    replacement = createObject("roSGNode", "StandardMessageDialog")
    replacement.title = "Playback error"
    replacement.buttons = ["Try again"]
    m.scene.dialog = replacement
    waitRead(video, "dialogVisible", false, "quality dismissal after another modal replaces it")
    settle(200)
    check(m.scene.dialog.isSameNode(replacement), "quality dismissal preserves a replacement modal")
    check(replacement.isInFocusChain(), "a replacement modal receives focus after the quality picker closes")
    m.scene.dialog = invalid
    video.setFocus(true)
    press("ok")
    waitRead(video, "dialogVisible", true, "the quality dialog before disposal")
    video.callFunc("onDestroy")
    check(not video.callFunc("fixtureRead").ownsDialog, "disposal releases an open quality modal")
    removeWrapper(video)
    video = addWrapper("StitchVideo")

    ' The tag reflects this wrapper's session only.
    video.lowLatency = true
    video.content = createObject("roSGNode", "ContentNode")
    waitRead(video, "tagVisible", true, "the low-latency tag")
    check(video.callFunc("fixtureRead").tagText = "Low-latency mode (experimental)", "the tag names the experiment without claiming a result")
    video.lowLatency = false
    video.content = createObject("roSGNode", "ContentNode")
    waitRead(video, "tagVisible", false, "the tag to hide")
    check(not video.callFunc("fixtureRead").tagVisible, "a recovery or stable session hides the tag")
    removeWrapper(video)
end sub
