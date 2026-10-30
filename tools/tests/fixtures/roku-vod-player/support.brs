' Test-only finite event pump and assertion summary. No network or registry IO.
sub fixtureBegin()
    m.assertions = 0
    m.failures = 0
    m.port = CreateObject("roMessagePort")
    m.screen = CreateObject("roSGScreen")
    m.screen.SetMessagePort(m.port)
    m.global = m.screen.GetGlobalNode()
    setConstants()
end sub

sub fixtureEnd()
    m.screen.Close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_UI_FAIL:"; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub settle(duration as integer)
    elapsed = CreateObject("roTimespan")
    while elapsed.TotalMilliseconds() < duration
        ignored = wait(20, m.port)
    end while
end sub

sub fail(message as string)
    m.failures++
    print "STITCH_UI_FAIL:"; message
end sub

sub check(condition as boolean, message as string)
    if condition
        m.assertions++
    else
        fail(message)
    end if
end sub
