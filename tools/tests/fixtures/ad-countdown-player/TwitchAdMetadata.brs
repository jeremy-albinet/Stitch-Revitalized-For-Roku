sub init()
    m.top.functionName = "fixtureWait"
end sub

sub fixtureWait()
    port = CreateObject("roMessagePort")
    m.top.observeField("stopRequested", port)
    clock = CreateObject("roTimespan")
    while (not m.top.stopRequested or m.top.fixtureHoldStop) and clock.TotalMilliseconds() < 4000
        wait(10, port)
    end while
    m.top.fixtureReceivedStop = m.top.stopRequested
    m.top.unobserveField("stopRequested")
    if m.top.fixtureMode = "no-response" then return
    m.top.response = {owner: m.top.owner, cues: [], bounds: [], closed: true, cleanupOk: m.top.fixtureMode <> "unsafe"}
end sub
