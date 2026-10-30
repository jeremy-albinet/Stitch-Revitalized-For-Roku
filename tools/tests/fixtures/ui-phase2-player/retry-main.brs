' The actual VideoPlayer error dialog and Try again: one fresh content request
' per explicit retry, ignored duplicates, no stale work from the old wrapper
' or after disposal, retained recorded position and live quality, fail-closed
' errors, the recorded-chat notice and truthful authorization copy. The
' content task is an inert boundary; the fixture supplies its responses.
sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: { ChatOption: "false", ChatFontSize: "16" }, fixtureContentTasks: 0, emoteCache: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()

    testRecordedRetry()
    testFailClosedAndBack()
    testLiveRetryKeepsQuality()
    testDisposedRetryIgnored()
    testChatNotice()
    testAuthorizationCopy()
    testBookmarkStart()

    fixtureEnd()
end sub

sub testBookmarkStart()
    set_setting("active_user", "fixture-user")
    for each order in ["bookmarks-first", "content-first", "failed", "timeout", "explicit"]
        set_user_setting("VideoBookmarks", FormatJson({ v1: "15" }))
        player = openPlayer("VOD")
        books = player.callFunc("fixtureRead").bookmarksTask
        if order = "bookmarks-first"
            set_user_setting("VideoBookmarks", FormatJson({ v1: "42" }))
            books.response = { bookmarks: { v1: "42" } }
        end if
        task = contentTask(player)
        task.response = playable("720p60")
        if order <> "bookmarks-first"
            check(player.callFunc("fixtureRead").bookmarkPending and player.callFunc("fixtureRead").video = invalid, "signed-in VOD waits for bookmarks: " + order)
            if order = "content-first"
                set_user_setting("VideoBookmarks", FormatJson({ v1: "42" }))
                books.response = { bookmarks: { v1: "42" } }
            else if order = "failed"
                books.response = invalid
            else if order = "explicit"
                player.callFunc("fixtureResume", 77)
            end if
        end if
        video = waitVideo(player, invalid)
        expected = 15
        if order = "bookmarks-first" or order = "content-first" then expected = 42
        if order = "explicit" then expected = 77
        check(video.content.PlayStart = expected, "first VOD position honors bookmarks or finite fallback: " + order)
        check(not player.callFunc("fixtureRead").bookmarkPending and player.callFunc("fixtureRead").bookmarkTimer = invalid, "bookmark wait is released after starting: " + order)
        if order = "timeout" or order = "explicit"
            set_user_setting("VideoBookmarks", FormatJson({ v1: "99" }))
            books.response = { bookmarks: { v1: "99" } }
            settle(100)
            check(player.callFunc("fixtureRead").video.isSameNode(video) and video.content.PlayStart = expected, "late bookmarks never replace or seek active playback: " + order)
        end if
        closePlayer(player)
    end for

    for each contentType in ["LIVE", "CLIP", "VOD"]
        if contentType = "VOD" then set_setting("active_user", "$default$")
        player = openPlayer(contentType)
        task = contentTask(player)
        task.response = playable("720p60")
        video = waitVideo(player, invalid)
        check(video <> invalid and not player.callFunc("fixtureRead").bookmarkPending, "anonymous VOD, LIVE and CLIP never wait: " + contentType)
        closePlayer(player)
    end for

    set_setting("active_user", "fixture-user")
    for each action in ["back", "dispose", "replace"]
        player = openPlayer("VOD")
        books = player.callFunc("fixtureRead").bookmarksTask
        task = contentTask(player)
        task.response = playable("720p60")
        timer = player.callFunc("fixtureRead").bookmarkTimer
        if action = "back"
            player.callFunc("requestBack")
        else if action = "dispose"
            player.callFunc("onDestroy")
        else
            player.contentRequested = request("LIVE")
        end if
        check(not player.callFunc("fixtureRead").bookmarkPending and timer.control = "stop", "leaving a pending VOD cancels its timer: " + action)
        books.response = { bookmarks: { v1: "99" } }
        settle(100)
        check(player.callFunc("fixtureRead").video = invalid, "late bookmark completion cannot play abandoned content: " + action)
        closePlayer(player)
    end for
    set_setting("active_user", "$default$")
end sub

function request(contentType as string) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields({ contentType: contentType, contentId: "v1", streamerLogin: "fixturechannel", streamerDisplayName: "Fixture Channel", streamerId: "42", contentTitle: "Fixture title" })
    return node
end function

function playable(quality as string) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields({ url: "http://fixture.invalid/" + quality, QualityID: quality, streamFormat: "hls" })
    return node
end function

function qualities() as object
    return [{ QualityID: "1080p60", url: "http://fixture.invalid/1080p60" }, { QualityID: "720p60", url: "http://fixture.invalid/720p60" }]
end function

function openPlayer(contentType as string) as object
    player = createObject("roSGNode", "VideoPlayer")
    m.scene.appendChild(player)
    player.setFocus(true)
    m.seen = {}
    player.observeField("state", m.port)
    tasks = m.global.fixtureContentTasks
    player.contentRequested = request(contentType)
    waitTasks(tasks + 1, "the first content request")
    return player
end function

sub closePlayer(player as object)
    player.unobserveField("state")
    player.callFunc("onDestroy")
    m.scene.removeChild(player)
    m.scene.dialog = invalid
end sub

function contentTask(player as object) as object
    return player.callFunc("fixtureRead").task
end function

sub waitTasks(count as integer, what as string)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        if m.global.fixtureContentTasks >= count then return
        pump(20)
    end while
    fail("timed out waiting for " + what)
end sub

sub waitDialog(present as boolean, what as string)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        if (m.scene.dialog <> invalid) = present then return
        pump(20)
    end while
    fail("timed out waiting for " + what)
end sub

' Waits for the player to show a wrapper other than previous.
function waitVideo(player as object, previous as dynamic) as dynamic
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        video = player.callFunc("fixtureRead").video
        if video <> invalid
            if previous = invalid then return video
            if not video.isSameNode(previous) then return video
        end if
        pump(20)
    end while
    fail("timed out waiting for a new player wrapper")
    return invalid
end function

sub failPlayback(video as object, code as integer)
    video.state = "playing"
    video.errorCode = code
    video.errorStr = "fixture playback error"
    video.state = "error"
end sub

sub testRecordedRetry()
    player = openPlayer("VOD")
    contentTask(player).response = invalid
    waitDialog(true, "the load error dialog")
    d = m.scene.dialog
    check(d.subtype() = "StandardMessageDialog" and d.title = "Couldn't load this video", "a failed load opens the error dialog")
    check(d.buttons.count() = 2 and d.buttons[0] = "Try again" and d.buttons[1] = "Back", "the dialog offers Try again and Back")

    tasks = m.global.fixtureContentTasks
    press("ok")
    waitTasks(tasks + 1, "the Try again request")
    waitDialog(false, "the dialog to close")
    check(player.callFunc("fixtureRead").pending, "Try again waits for one fresh content request")
    player.callFunc("fixtureButtonAgain")
    player.callFunc("fixtureRetryAgain")
    settle(300)
    check(m.global.fixtureContentTasks = tasks + 1, "a repeated choice or retry while pending starts nothing")

    contentTask(player).response = playable("source")
    video = waitVideo(player, invalid)
    check(video <> invalid and video.subtype() = "CustomVideo" and not player.callFunc("fixtureRead").pending, "the answered retry plays the video")

    ' Playback fails later at 5:21 after some automatic recovery was spent.
    player.callFunc("fixtureSpendRecovery", 4)
    video.position = 321
    failPlayback(video, 404)
    waitDialog(true, "the playback error dialog")
    d = m.scene.dialog
    check(d.title = "Couldn't find this stream" and d.buttons[0] = "Try again", "a playback error offers Try again")
    check(d.message.count() = 2 and d.message[1] = "Go back and choose another stream.", "an error that was not retried gives advice, not a recovery claim")

    tasks = m.global.fixtureContentTasks
    press("ok")
    waitTasks(tasks + 1, "the second Try again")
    settle(200)
    s = player.callFunc("fixtureRead")
    check(s.recovery = 0 and s.reconnect = 0, "an explicit Try again starts a fresh recovery budget")
    message = video.findNode("messageText")
    check(message <> invalid and message.text = "Trying again…", "the stopped wrapper says it is trying again")
    ' The old wrapper is detached: its late error starts neither recovery nor a dialog.
    failPlayback(video, -1)
    settle(400)
    s = player.callFunc("fixtureRead")
    check(m.scene.dialog = invalid and s.retryTimer = invalid and s.reconnectTask = invalid and m.global.fixtureContentTasks = tasks + 1, "a late error from the old wrapper is ignored")

    contentTask(player).response = playable("source")
    retried = waitVideo(player, video)
    check(retried <> invalid and player.content.PlayStart = 321, "the retried video resumes where playback failed")
    check(video.getParent() = invalid, "the old wrapper is removed")
    closePlayer(player)
end sub

sub testFailClosedAndBack()
    player = openPlayer("VOD")
    restricted = createObject("roSGNode", "TwitchContentNode")
    restricted.setFields({ contentType: "ERROR", description: "Restricted", errorCode: "vod_manifest_restricted" })
    contentTask(player).response = restricted
    waitDialog(true, "the restricted dialog")
    d = m.scene.dialog
    check(d.buttons.count() = 1 and d.buttons[0] = "Back" and d.message[0] = "This video is only available to subscribers", "a subscriber-only video offers only Back")
    tasks = m.global.fixtureContentTasks
    press("ok")
    waitSeen("state", 1, "the player to finish")
    check(lastSeen("state") = "done" and m.global.fixtureContentTasks = tasks and m.scene.dialog = invalid, "Back leaves the player without another request")
    closePlayer(player)

    player = openPlayer("VOD")
    contentTask(player).response = invalid
    waitDialog(true, "a retryable dialog")
    press("back")
    waitSeen("state", 1, "remote Back to leave")
    check(lastSeen("state") = "done" and m.scene.dialog = invalid, "remote Back on the dialog leaves the player as before")
    closePlayer(player)
end sub

sub testLiveRetryKeepsQuality()
    m.global.fixtureRegistry = { ChatOption: "true", ChatFontSize: "16" }
    player = openPlayer("LIVE")
    task = contentTask(player)
    task.metadata = qualities()
    task.response = playable("1080p60")
    first = waitVideo(player, invalid)
    settle(300)
    check(first.subtype() = "StitchVideo" and first.selectedQuality = "1080p60", "live playback starts at the delivered quality")
    check(first.chatIsVisible = true and first.findNode("scrim").width = 960, "with chat open the live controls use the 960 px video area")

    first.QualityChangeRequest = 1
    first.QualityChangeRequestFlag = true
    second = waitVideo(player, first)
    settle(300)
    check(second.selectedQuality = "720p60", "a quality change plays the chosen entry")
    check(second.chatIsVisible = true and second.findNode("scrim").width = 960, "the recreated wrapper keeps the chat-shown layout")

    failPlayback(second, 404)
    waitDialog(true, "the live error dialog")
    tasks = m.global.fixtureContentTasks
    press("ok")
    waitTasks(tasks + 1, "the live Try again")
    task = contentTask(player)
    task.metadata = qualities()
    task.response = playable("1080p60")
    third = waitVideo(player, second)
    settle(300)
    check(third.selectedQuality = "720p60" and player.content.url = "http://fixture.invalid/720p60", "Try again keeps the quality that was playing, with its stream URL")
    check(third.chatIsVisible = true, "chat stays open across Try again")
    closePlayer(player)
    m.global.fixtureRegistry = { ChatOption: "false", ChatFontSize: "16" }
end sub

sub testDisposedRetryIgnored()
    player = openPlayer("VOD")
    contentTask(player).response = invalid
    waitDialog(true, "the dialog before disposal")
    tasks = m.global.fixtureContentTasks
    press("ok")
    waitTasks(tasks + 1, "the pending retry")
    pending = contentTask(player)
    player.callFunc("onDestroy")
    pending.response = playable("source")
    settle(500)
    s = player.callFunc("fixtureRead")
    check(s.video = invalid and m.scene.dialog = invalid and m.global.fixtureContentTasks = tasks + 1, "a response after disposal creates no player, dialog or request")
    player.unobserveField("state")
    m.scene.removeChild(player)
end sub

sub testChatNotice()
    player = openPlayer("VOD")
    contentTask(player).response = playable("source")
    video = waitVideo(player, invalid)
    video.toggleChat = true
    waitDialog(true, "the chat notice")
    d = m.scene.dialog
    check(d.title = "Chat is unavailable for this video" and d.buttons.count() = 1 and d.buttons[0] = "Continue watching", "recorded chat still opens the unavailable notice")
    press("back")
    waitDialog(false, "the notice to close")
    settle(200)
    check(video.hasFocus() and video.toggleChat = false, "closing the notice returns focus to the video")
    closePlayer(player)
end sub

sub testAuthorizationCopy()
    handler = createObject("roSGNode", "VideoErrorHandler")
    kind = handler.callFunc("classifyError", 403, "Forbidden")
    info = handler.callFunc("getUserFriendlyErrorMessage", 403, kind)
    text = LCase(info.title + " " + info.message + " " + info.suggestion)
    check(kind = "authentication_error", "403 keeps its authorization classification")
    check(text.instr("sign in again") < 0 and text.instr("sign in to continue") < 0 and text.instr("authentication required") < 0, "a 403 does not claim the viewer must sign in")
    check(text.instr("without signing in") >= 0, "the copy keeps public playback without an account")
end sub
