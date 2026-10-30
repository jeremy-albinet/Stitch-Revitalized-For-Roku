' Executes the production Main exit helper and actual session manager. Clock,
' port waits, screen/hero and worker/video/socket acknowledgments are IO inputs.
sub main()
    m.assertions = 0
    m.failures = 0
    for each mode in ["ack", "idle", "missing", "disposed", "retained", "deadline", "home", "closed"]
        runExitCase(mode)
    end for
    if "__NEGATIVE_CONTROL__" = "yes" then check(false, "deliberate assertion control")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions, 8 cases"
end sub

sub check(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "EXIT_CLEANUP_FAIL: " + label
    end if
end sub

sub runExitCase(mode as string)
    realScreen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    realScreen.SetMessagePort(port)
    host = realScreen.CreateScene("ExitHost")
    realScreen.Show()
    session = CreateObject("roSGNode", "RokuDemuxSession")
    host.AppendChild(session)
    state = CreateObject("roSGNode", "Node")
    state.AddField("worker", "node", false)
    state.AddField("video", "node", false)
    state.AddFields({ mode: mode, elapsed: 0, waits: 0, closes: 0, reads: 0, destroys: 0, unobserves: 0, clockReads: 0, alive: true, homeSeen: false, acknowledged: false, session: session, visibleSession: session })
    if mode = "missing"
        state.session = invalid
        state.visibleSession = invalid
    else if mode <> "idle" and mode <> "closed"
        descriptor = { "version": 1, "sourceUrl": "https://use14.playlist.ttvnw.net/canned/media.m3u8", "qualityId": "720p60", "approvedOrigins": ["https://use14.playlist.ttvnw.net"], "metadata": { "videoCodec": "avc1.4D401F", "audioCodec": "mp4a.40.2", "width": 1280, "height": 720, "frameRate": "60.000", "bandwidth": 3322199, "isHD": true } }
        sessionId = session.CallFunc("startSession", descriptor)
        owned = session.CallFunc("fixtureOwner")
        state.worker = owned.worker
        video = CreateObject("roSGNode", "ExitVideoBoundary")
        video.state = "playing"
        state.video = video
        check(sessionId <> "" and session.busy and state.worker.state = "run", "actual session owns a running worker")
        check(session.CallFunc("attachVideo", sessionId, video), "actual session attaches the Video state boundary")
        if mode = "disposed"
            session.CallFunc("onDestroy")
            check(session.busy and session.CallFunc("fixtureOwner").disposed, "already disposed owner retains pending cleanup")
        end if
    end if
    m.fixtureState = state
    m.fixtureScreen = realScreen
    sceneBoundary = {
        state: state,
        GetField: function(field as string) as dynamic
            m.state.reads++
            check(m.state.alive and field = "localPlaybackSession", "scene is read only before screen closure")
            return m.state.visibleSession
        end function,
        findNode: function(id as string) as dynamic
            check(m.state.alive and id = "stitchAdMetadataOwner", "optional ad owner is captured before scene destruction")
            return invalid
        end function,
        unobserveField: sub(field as string)
            m.state.unobserves++
            check(m.state.alive and field = "exitApp", "exit observer is removed only while screen is alive")
        end sub,
        callFunc: sub(name as string)
            m.state.destroys++
            check(m.state.alive and name = "onDestroy", "hero destruction is requested before screen closure")
            owner = m.state.session
            if owner <> invalid then owner.CallFunc("onDestroy")
            if m.state.mode = "retained" then m.state.visibleSession = CreateObject("roSGNode", "RokuDemuxSession")
        end sub
    }
    screenBoundary = {
        state: state,
        close: sub()
            m.state.closes++
            check(m.state.alive, "helper does not close after an actual closed event")
            owner = m.state.session
            if owner <> invalid
                if owner.busy then check(m.state.elapsed >= 15000, "screen cannot close before cooperative acknowledgment or deadline")
            end if
            m.state.alive = false
        end sub
    }
    if mode = "closed"
        realScreen.Close()
        event = wait(1, port)
        check(type(event) = "roSGScreenEvent" and event.isScreenClosed(), "already closed case supplies actual screen event")
        state.alive = false
    end if
    finishMainScene(screenBoundary, sceneBoundary, port, mode = "closed")
    if mode = "closed"
        check(state.reads = 0 and state.unobserves = 0 and state.destroys = 0 and state.waits = 0 and state.closes = 0 and state.clockReads = 0, "already closed screen makes no scene clock or close calls")
    else
        check(state.reads = 1 and state.unobserves = 1 and state.destroys = 1, "same owner is retained before one hero destruction request")
        if mode = "home"
            check(state.homeSeen and state.waits = 1 and state.closes = 0 and state.elapsed = 100, "Home screen event ends Main drain without subsequent close")
            check(session.busy and state.worker.state = "run", "external closure makes no cooperative cleanup guarantee")
        else if mode = "deadline"
            check(state.elapsed = 15000 and state.waits = 150 and state.closes = 1, "Main drain stops at bounded fifteen second deadline")
            check(session.busy and state.worker.state = "run" and state.worker.control = "run" and state.worker.stopRequested, "deadline retains running worker without force stop or cleanup claim")
            check(state.video.control = "stop" and state.video.state = "playing", "deadline does not fabricate native Video stop")
        else if mode = "idle" or mode = "missing"
            check(state.waits = 0 and state.elapsed = 0 and state.closes = 1, "idle or absent owner closes without artificial delay")
        else
            check(state.waits = 3 and state.elapsed = 300 and state.closes = 1 and state.acknowledged, "screen remains alive until actual worker Video and cleanup acknowledgment")
            owned = session.CallFunc("fixtureOwner")
            check(not session.busy and owned.worker = invalid and owned.video = invalid and owned.disposed, "actual disposed manager releases safe stopped ownership")
            check(state.worker.state = "stop" and state.video.state = "stopped", "real stop fields establish acknowledgment")
        end if
    end if
    if state.worker <> invalid
        if session.busy then acknowledgeExitOwner(state)
        check(not session.busy, "fixture releases its own remaining boundary owner after helper returns")
    end if
    if mode <> "home" and mode <> "closed" then realScreen.Close()
end sub

function exitFixtureClock() as object
    return {
        state: m.fixtureState,
        Mark: sub()
            check(m.state.alive, "clock starts while render is alive")
            m.state.elapsed = 0
        end sub,
        TotalMilliseconds: function() as integer
            m.state.clockReads++
            check(m.state.alive, "clock is not accessed after screen closed event")
            return m.state.elapsed
        end function
    }
end function

function exitFixtureWait(timeout as integer, port as object) as dynamic
    state = m.fixtureState
    state.waits++
    check(state.alive and timeout > 0 and timeout <= 100, "Main polls are positive bounded waits while render is alive")
    state.elapsed += timeout
    worker = state.worker
    check(worker <> invalid and worker.stopRequested and worker.control = "run", "cooperative wait keeps running worker and stop request")
    if state.mode = "home"
        m.fixtureScreen.Close()
        event = wait(1, port)
        check(type(event) = "roSGScreenEvent" and event.isScreenClosed(), "Home boundary returns actual roSGScreenEvent")
        state.homeSeen = true
        state.alive = false
        return event
    end if
    if state.mode <> "deadline"
        if state.waits = 1
            worker.result = exitCleanupResult(worker.sessionId)
            check(state.session.busy and worker.state = "run", "cleanup flags alone cannot release running worker")
        else if state.waits = 2
            worker.state = "stop"
            check(state.session.busy and state.video.state = "playing", "worker stop still waits for real Video stop")
        else if state.waits = 3
            state.video.state = "stopped"
            state.acknowledged = not state.session.busy
        end if
    else if state.elapsed > 15000
        check(false, "Main drain exceeded bounded deadline")
        ' Make a deadline-removal mutant terminate; this is fixture-only IO.
        acknowledgeExitOwner(state)
    end if
    return invalid
end function

sub acknowledgeExitOwner(state as object)
    state.worker.result = exitCleanupResult(state.worker.sessionId)
    state.worker.state = "stop"
    state.video.state = "stopped"
end sub

function exitCleanupResult(sessionId as string) as object
    ' Socket/cache flags are an IO boundary, never a physical cleanup claim.
    return { sessionId: sessionId, reason: "stop_requested", cleanupOk: true, listenerClosed: true, connectionClosed: true, helperClosed: true, cacheReferencesReleased: true }
end function
