sub main()
    m.assertions = 0
    m.failures = 0
    for each mode in ["idle", "ad-only", "dual", "ad-after-session", "deadline", "blocked", "home", "closed"]
        runCase(mode)
    end for
    if m.failures = 0 then print "__MARKER__: "; m.assertions; " assertions, 8 cases"
end sub

sub check(value as boolean, label as string)
    m.assertions++
    if not value
        m.failures++
        print "AD_EXIT_FAIL: " + label
    end if
end sub

sub runCase(mode as string)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    screen.CreateScene("Scene")
    screen.Show()
    state = CreateObject("roSGNode", "Node")
    state.AddFields({ mode: mode, elapsed: 0, waits: 0, closes: 0, requested: false, alive: true, lookups: 0, reads: 0 })
    state.AddField("session", "node", false)
    state.AddField("ad", "node", false)
    session = CreateObject("roSGNode", "Node")
    session.AddFields({ busy: mode = "dual" or mode = "ad-after-session", stopRequested: false })
    ad = CreateObject("roSGNode", "Node")
    ad.AddFields({ busy: mode <> "idle" and mode <> "closed", stopRequested: false, closed: false, cleanupBlocked: mode = "blocked" })
    state.session = session
    if mode = "ad-only" then state.session = invalid
    state.ad = ad
    m.fixtureState = state
    m.fixtureScreen = screen
    sceneBoundary = {
        state: state,
        GetField: function(name as string) as dynamic
            check(m.state.alive and name = "localPlaybackSession", "capture session before teardown")
            m.state.reads++
            return m.state.session
        end function,
        findNode: function(id as string) as dynamic
            check(m.state.alive and id = "stitchAdMetadataOwner", "capture retained metadata owner before teardown")
            m.state.lookups++
            return m.state.ad
        end function,
        unobserveField: sub(name as string)
            check(m.state.alive and name = "exitApp", "remove exit observer before teardown")
        end sub,
        callFunc: sub(name as string)
            check(m.state.alive and name = "onDestroy", "request cooperative scene destruction")
            m.state.requested = true
            if m.state.session <> invalid then m.state.session.stopRequested = true
            m.state.ad.stopRequested = true
        end sub
    }
    screenBoundary = {
        state: state,
        close: sub()
            check(m.state.alive and m.state.requested, "close follows cleanup request")
            pending = m.state.ad.busy
            if m.state.session <> invalid then pending = pending or m.state.session.busy
            check(not pending or m.state.elapsed >= 15000, "cannot close while either owner remains busy before deadline")
            m.state.closes++
            m.state.alive = false
        end sub
    }
    if mode = "closed" then state.alive = false
    finishMainScene(screenBoundary, sceneBoundary, port, mode = "closed")
    if mode = "closed"
        check(state.reads = 0 and state.lookups = 0 and state.waits = 0 and state.closes = 0, "already closed screen makes no render calls")
    else if mode = "home"
        check(state.waits = 1 and state.closes = 0 and not state.alive, "external screen closure returns without a second close or cleanup claim")
    else if mode = "deadline" or mode = "blocked"
        check(state.elapsed = 15000 and state.closes = 1 and ad.busy, "deadline ends bounded drain without fabricating cleanup")
        check(not ad.closed and ad.stopRequested, "failed or pending cleanup never receives force stop")
    else if mode = "idle"
        check(state.waits = 0 and state.closes = 1, "idle owners do not delay exit")
    else
        expected = 2
        if mode = "dual" then expected = 4
        check(state.waits = expected and state.closes = 1 and not ad.busy, "drain waits for the last actual owner busy acknowledgment")
    end if
    if state.alive then state.alive = false
    if mode <> "home" then screen.Close()
end sub

function adExitClock() as object
    return {
        state: m.fixtureState,
        Mark: sub()
            check(m.state.alive, "clock starts before screen closure")
        end sub,
        TotalMilliseconds: function() as integer
            check(m.state.alive, "clock remains on live render side")
            return m.state.elapsed
        end function
    }
end function

function adExitWait(timeout as integer, port as object) as dynamic
    state = m.fixtureState
    check(state.alive and state.requested and timeout > 0 and timeout <= 100, "drain uses bounded positive waits after stop request")
    state.elapsed += timeout
    state.waits++
    check(state.ad.stopRequested, "metadata owner receives cooperative stop")
    if state.mode = "home"
        m.fixtureScreen.Close()
        event = wait(1, port)
        check(type(event) = "roSGScreenEvent" and event.isScreenClosed(), "external close is an actual screen event")
        state.alive = false
        return event
    end if
    if state.mode = "deadline" or state.mode = "blocked"
        if state.elapsed > 15000
            check(false, "missing deadline exceeded bound")
            state.ad.busy = false
        end if
    else
        if state.session <> invalid
            if state.waits = 1 then state.session.busy = false
        end if
        releaseAt = 2
        if state.mode = "dual" then releaseAt = 4
        if state.waits >= releaseAt
            state.ad.busy = false
            state.ad.closed = true
        end if
    end if
    return invalid
end function
