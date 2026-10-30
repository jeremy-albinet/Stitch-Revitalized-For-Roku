' Shared helpers for the phase-two player, retry and chat fixtures. Remote
' keys are requested from the key driver by printing FIXTURE_KEY/FIXTURE_HOLD.

sub fixtureBegin()
    m.assertions = 0
    m.failures = 0
    m.seen = {}
    m.clock = createObject("roTimespan")
    m.port = createObject("roMessagePort")
    m.screen = createObject("roSGScreen")
    m.screen.setMessagePort(m.port)
    m.global = m.screen.getGlobalNode()
    setConstants()
    m.ui = m.global.constants.ui.color
end sub

sub fixtureEnd()
    m.screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_UI_FAIL:"; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub press(key as string)
    print "FIXTURE_KEY:" + key
end sub

sub hold(key as string, duration as integer)
    print "FIXTURE_HOLD:" + key + ":" + duration.toStr()
end sub

' Records every observed field change on the port, oldest first, with the
' fixture clock time in milliseconds.
sub pump(duration as integer)
    msg = wait(duration, m.port)
    if type(msg) <> "roSGNodeEvent" then return
    field = msg.getField()
    if m.seen[field] = invalid then m.seen[field] = []
    events = m.seen[field]
    events.push({ data: msg.getData(), ms: m.clock.totalMilliseconds() })
    m.seen[field] = events
end sub

function seen(field as string) as object
    if m.seen[field] = invalid then return []
    return m.seen[field]
end function

function lastSeen(field as string) as dynamic
    events = seen(field)
    if events.count() = 0 then return invalid
    return events[events.count() - 1].data
end function

sub settle(duration as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < duration
        pump(20)
    end while
end sub

' Waits until at least count changes of field were observed.
sub waitSeen(field as string, count as integer, what as string)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        if seen(field).count() >= count then return
        pump(20)
    end while
    fail("timed out waiting for " + what)
end sub

' Waits until node.callFunc("fixtureRead")[key] equals value.
sub waitRead(node as object, key as string, value as dynamic, what as string)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        state = node.callFunc("fixtureRead")
        if sameValue(state[key], value) then return
        pump(20)
    end while
    fail("timed out waiting for " + what)
end sub

' Equality that never raises a type mismatch: strings, booleans and numbers
' only compare with their own kind.
function sameValue(a as dynamic, b as dynamic) as boolean
    if a = invalid or b = invalid then return a = invalid and b = invalid
    for each kind in ["ifString", "ifBoolean"]
        aKind = GetInterface(a, kind) <> invalid
        bKind = GetInterface(b, kind) <> invalid
        if aKind or bKind
            if aKind and bKind then return a = b
            return false
        end if
    end for
    return a = b
end function

' Native color fields read back as signed RGBA integers in the engine and as
' strings on some firmware; both become "RRGGBB".
function colorHex(value as dynamic) as string
    if value = invalid then return ""
    if GetInterface(value, "ifString") <> invalid then return uiNormalizeHex(value)
    number& = value
    if number& < 0 then number& = number& + 4294967296&
    digits = "0123456789ABCDEF"
    text = ""
    for i = 1 to 8
        digit% = CInt(number& mod 16)
        text = digits.mid(digit%, 1) + text
        number& = number& \ 16
    end for
    return text.left(6)
end function

function toSeconds(text as string) as integer
    total = 0
    for each part in text.split(":")
        total = total * 60 + part.toInt()
    end for
    return total
end function

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
