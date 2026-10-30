' Actual relay functions run with stand-in sockets and a canned upstream; this
' is not evidence of native socket or network behavior.
sub checkRelay(ok as boolean, message as string)
    if not ok then throw "low-latency-relay: " + message
    m.assertions += 1
end sub

function fakeAddress() as object
    return { text: "", SetAddress: fakeAddressSet }
end function

function fakeAddressSet(value as string) as boolean
    m.text = value
    return true
end function

' The address the OS reports for each bind, in attempt order.
function fakeBound(text as string, port as integer) as object
    return { text: text, port: port, GetAddress: fakeBoundText, GetPort: fakeBoundPort }
end function

function fakeBoundText() as string
    return m.text
end function

function fakeBoundPort() as integer
    return m.port
end function

function fakeListener() as object
    listener = { bound: invalid, closed: false, listening: false, SetMessagePort: fakeIgnore, SetReuseAddr: fakeIgnore, SetAddress: fakeListenerSet, GetAddress: fakeListenerAddress, NotifyReadable: fakeIgnore, Listen: fakeListen, IsListening: fakeIsListening, Close: fakeClose }
    GetGlobalAA().listeners.Push(listener)
    return listener
end function

sub fakeIgnore(value as dynamic)
end sub

function fakeListenerSet(address as object) as boolean
    plan = GetGlobalAA().plan
    index = GetGlobalAA().listeners.Count() - 1
    if index < plan.Count() then m.bound = plan[index]
    return true
end function

function fakeListenerAddress() as dynamic
    return m.bound
end function

function fakeListen(backlog as integer) as boolean
    m.listening = true
    return true
end function

function fakeIsListening() as boolean
    return m.listening
end function

sub fakeClose()
    m.closed = true
end sub

sub fakeObserve(field as string, port as object)
end sub

function relayMediaText(sequence as integer, ended as boolean) as string
    nl = Chr(10)
    text = "#EXTM3U" + nl + "#EXT-X-VERSION:3" + nl + "#EXT-X-TARGETDURATION:2" + nl + "#EXT-X-MEDIA-SEQUENCE:" + sequence.ToStr() + nl
    for index = 0 to 5
        text += "#EXTINF:2.000,live" + nl + "https://edge.example.ttvnw.net/v1/segment/s" + (sequence + index).ToStr() + ".ts" + nl
    end for
    if ended then text += "#EXT-X-ENDLIST" + nl
    return text
end function

sub relayReset(plan as object)
    m.plan = plan
    m.listeners = []
    m.listener = invalid
    m.port = CreateObject("roMessagePort")
end sub

sub listenRelay()
    ' 49381 is reported in the signed form some firmware uses above 32767.
    relayReset([fakeBound("0.0.0.0:49380", 49380), fakeBound("127.0.0.1:-16155", 49381)])
    checkRelay(relayListen() = 49381, "a bind the OS does not report on exact loopback is skipped")
    checkRelay(m.listeners[0].closed and not m.listeners[0].listening, "the wider bind is closed without listening")
    checkRelay(m.listeners[1].listening and m.listener <> invalid and m.listener.bound.port = 49381, "the exact loopback bind listens")

    relayReset([invalid, fakeBound("127.0.0.1:49390", 49390), fakeBound("10.0.1.81:49382", 49382), fakeBound("127.0.0.1:49383", 49383)])
    checkRelay(relayListen() = 49383, "a missing address or another port is not exact loopback")
    checkRelay(m.listeners[0].closed and m.listeners[1].closed and m.listeners[2].closed and m.listeners.Count() = 4, "every refused bind is closed")

    relayReset([])
    checkRelay(relayListen() = 0 and m.listener = invalid and m.listeners.Count() = 10, "no loopback bind means no listener")

    ' The URL is published only after the bind check.
    m.upstream = "#EXTM3U" + Chr(10) + "#EXT-X-STREAM-INF:BANDWIDTH=8000000" + Chr(10) + "https://edge.example.ttvnw.net/v1/playlist/a.m3u8" + Chr(10)
    plan = []
    for port = 49380 to 49389
        plan.Push(fakeBound("0.0.0.0:" + port.ToStr(), port))
    end for
    relayReset(plan)
    m.top = { sourceUrl: "https://edge.example.ttvnw.net/master.m3u8", startCount: 3, maxCount: 15, stopRequested: true, ended: false, status: invalid, ObserveField: fakeObserve }
    runRelay()
    checkRelay(m.top.status <> invalid and m.top.status.failure = "listen_failed" and m.top.status.url = invalid, "a relay without an exact loopback bind publishes no URL")
    relayReset([fakeBound("127.0.0.1", 49380)])
    m.top.status = invalid
    runRelay()
    checkRelay(m.top.status <> invalid and m.top.status.url = "http://127.0.0.1:49380/live.m3u8" and m.listeners[0].closed, "an exact loopback bind publishes its URL and closes on stop")
end sub

sub budgetRelay()
    m.top = { startCount: 3, maxCount: 15, ended: false }
    m.state = { anchor: -1& }
    m.lastGood = {}
    m.failures = {}
    first = relayMediaBody("/v/0.m3u8", relayMediaText(100, false))
    checkRelay(first <> invalid and relayMediaBody("/v/1.m3u8", relayMediaText(100, false)) <> invalid, "both variants start")
    for attempt = 1 to 5
        checkRelay(relayMediaBody("/v/0.m3u8", invalid) = first, "a failed refresh re-serves that path's last good playlist")
        checkRelay(relayMediaBody("/v/1.m3u8", relayMediaText(100 + attempt, false)) <> invalid, "the healthy variant keeps refreshing")
    end for
    checkRelay(relayMediaBody("/v/0.m3u8", invalid) = invalid, "a healthy variant does not refresh a failing one's budget")
    healthy = relayMediaBody("/v/1.m3u8", relayMediaText(106, false))
    checkRelay(relayMediaBody("/v/1.m3u8", invalid) = healthy, "the other variant has its own budget")
    checkRelay(relayMediaBody("/v/2.m3u8", invalid) = invalid, "a path never served has nothing to re-serve")
    checkRelay(relayMediaBody("/v/0.m3u8", relayMediaText(107, false)) <> invalid and relayMediaBody("/v/0.m3u8", invalid) <> invalid, "a good refresh restores that path's budget")
    checkRelay(not m.top.ended, "a live playlist is not reported as ended")
    checkRelay(relayMediaBody("/v/0.m3u8", relayMediaText(108, true)) <> invalid and m.top.ended, "an upstream end of stream is reported")
end sub

sub main()
    m.assertions = 0
    try
        mode = "__MODE__"
        if mode = "listen" then listenRelay()
        if mode = "budget" then budgetRelay()
        print "STITCH_RELAY_CASE: " + mode
        print "STITCH_RELAY_PASS: __MARKER__ " + FormatJson({ assertions: m.assertions, failures: 0 })
    catch error
        print "STITCH_RELAY_FAIL: __MARKER__ " + error.message
        print "STITCH_RELAY_PASS: __MARKER__ " + FormatJson({ assertions: m.assertions, failures: 1 })
    end try
end sub
