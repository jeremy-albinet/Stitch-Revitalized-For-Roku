' Offline SceneGraph input ownership: production Following, ChannelPage,
' StatusPanelHost and Hero navigation. Registry, API and playback are inert.
sub main()
    m.port = createObject("roMessagePort")
    m.assertions = 0
    m.failures = 0
    screen = createObject("roSGScreen")
    screen.setMessagePort(m.port)
    scene = screen.createScene("FixtureScene")
    screen.show()
    testRetainedFollowing(scene, false, "valid", false, false)
    for each signedIn in [false, true]
        for each result in ["valid", "empty", "error"]
            testRetainedFollowing(scene, signedIn, result, false)
            if m.failures > 0 then exit for
        end for
        if m.failures > 0 then exit for
        ' Leave from a focused status action, then hide it via a late success.
        testRetainedFollowing(scene, signedIn, "valid", true)
    end for
    screen.close()
    if m.failures = 0 then print "__PASS_MARKER__:"; m.assertions; " assertions"
end sub

sub testRetainedFollowing(scene as object, signedIn as boolean, result as string, statusBeforeOpen as boolean, dirtyReturn = true as boolean)
    print "FOLLOWING_FOCUS_CASE:"; signedIn; ":"; result; ":statusBeforeOpen="; statusBeforeOpen; ":dirtyReturn="; dirtyReturn
    following = scene.callFunc("fixtureFollowing", signedIn)
    pause(50)
    before = following.callFunc("fixtureRead")
    pending = before.task
    check(pending.control = "run" and following.isInFocusChain(), "Following starts with a pending mock request and input focus")
    if statusBeforeOpen
        pending.response = invalid
        pause(50)
        check(before.status.isInFocusChain() and before.status.state = "error", "visible Following error focuses its status action")
    end if
    profile = scene.callFunc("fixtureStart")
    pause(50)
    check(profile.isInFocusChain() and not following.isInFocusChain(), "opening the profile transfers input away from pending Following")

    ' brs-node does not naturally deliver the losing-page notification here.
    ' Replay that ordering after focus moved, before and after mock responses.
    following.followRefreshPending = dirtyReturn
    following.callFunc("fixtureDeliverFocusChange")
    pause(50)
    check(profile.isInFocusChain() and not following.isInFocusChain(), "retained Following focus-loss callback cannot reclaim input")
    check(following.followRefreshPending = dirtyReturn and following.callFunc("fixtureRead").task.isSameNode(pending), "losing focus preserves refresh state without replacing the pending task")

    ' Early OK while the profile is loading must not start playback.
    print "FIXTURE_KEY:ok"
    pause(300)
    check(profile.contentSelected = invalid and scene.callFunc("fixtureRead").active.isSameNode(profile), "early OK on a loading profile cannot select a player")
    profile.callFunc("fixtureRead").task.response = fixtureResponse()
    pause(100)
    pending.response = followingResponse(signedIn, result)
    pause(50)
    check(profile.isInFocusChain() and not following.isInFocusChain(), "late Following valid empty or error response preserves visible profile focus")
    following.callFunc("fixtureDeliverFocusChange")
    pause(50)
    check(profile.isInFocusChain() and not before.rowlist.drawFocusFeedback, "post-response losing-page callback leaves input and focus feedback on the profile")
    check(following.followRefreshPending = dirtyReturn and following.callFunc("fixtureRead").task.isSameNode(pending), "late responses and status transitions preserve refresh state")
    expectedState = result
    if result = "valid" then expectedState = "hidden"
    check(before.status.state = expectedState, "late response still updates retained Following content or status")

    print "FIXTURE_KEY:ok"
    selected = awaitProfileSelection(profile)
    if selected then selected = profile.playContent and profile.contentSelected.contentType = "LIVE" and profile.contentSelected.streamerLogin = "fixture-channel"
    check(selected, "first real OK on the loaded profile selects its playable LIVE card")
    print "FIXTURE_KEY:back"
    returned = awaitFollowing(scene, following)
    check(returned and following.isInFocusChain(), "one real Back returns input from profile to retained Following")
    after = following.callFunc("fixtureRead")
    if dirtyReturn
        check(not following.followRefreshPending and not after.task.isSameNode(pending) and pending.control = "stop" and after.task.control = "run", "returning to dirty Following refreshes once and destroys its old request")
    else
        check(not following.followRefreshPending and after.task.isSameNode(pending), "returning to clean Following reuses its original request")
    end if
    refreshed = after.task
    following.callFunc("fixtureDeliverFocusChange")
    check(following.callFunc("fixtureRead").task.isSameNode(refreshed), "additional focus notification does not duplicate the refresh")
    refreshed.response = followingResponse(signedIn, "valid")
    pause(100)
    check(following.isInFocusChain() and after.rowlist.isInFocusChain() and after.rowlist.numRows = 1 and after.status.state = "hidden", "refreshed Following returns to populated content with input focus")
end sub

function followingResponse(signedIn as boolean, result as string) as dynamic
    if result = "error" then return invalid
    streams = []
    if result = "valid" then streams.push({ contentType: "LIVE", streamerLogin: "other-channel", streamerDisplayName: "Other Channel", previewImageURL: "pkg:/images/default_banner.png", streamerProfileImageUrl: "pkg:/images/default_banner.png" })
    if signedIn then return { liveFollows: streams, offlineFollows: [] }
    shelves = []
    if streams.count() > 0 then shelves.push({ title: "Popular", streams: streams })
    return { shelves: shelves }
end function

function awaitProfileSelection(profile as object) as boolean
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 1000
        if profile.contentSelected <> invalid then return true
        wait(25, m.port)
    end while
    return false
end function

function awaitFollowing(scene as object, following as object) as boolean
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 1000
        if scene.callFunc("fixtureRead").active.isSameNode(following) then return true
        wait(25, m.port)
    end while
    return false
end function
