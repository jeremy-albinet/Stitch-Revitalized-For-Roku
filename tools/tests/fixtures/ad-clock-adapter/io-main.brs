sub main()
    m.assertions = 0
    m.failures = 0
    print "STITCH_AD_CLOCK_BEGIN: __MARKER__"
    for each mode in ["before", "equal", "after", "nonmatching", "stop", "cancel-fails", "config-fails", "foreign-file", "invalid-source", "initial-stop", "malformed-body"]
        runActualMetadata(mode)
    end for
    print "STITCH_AD_CLOCK_END: __MARKER__ "; FormatJson({assertions:m.assertions, failures:m.failures})
end sub
sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_AD_CLOCK_FAIL: __MARKER__ " + message
    end if
end sub
function ioBody() as string
    q = Chr(34)
    return "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:2" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:1" + Chr(10) + "#EXT-X-DATERANGE:ID=" + q + "secret-provider-ID" + q + ",CLASS=" + q + "twitch-stitched-ad" + q + ",START-DATE=" + q + "2026-01-01T00:00:00Z" + q + ",DURATION=2" + Chr(10) + "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00Z" + Chr(10) + "#EXTINF:2," + Chr(10) + "secret-segment.m4s" + Chr(10)
end function
sub runActualMetadata(mode as string)
    m.mode = mode
    m.trace = []
    m.responses = []
    m.times = [0]
    if mode = "before" or mode = "malformed-body" then m.times.Push(4999)
    if mode = "equal" then m.times.Push(5000)
    if mode = "after" then m.times.Push(5001)
    if mode = "nonmatching" or mode = "cancel-fails" then m.times.Push(5000)
    m.file = [false]
    if mode = "foreign-file" then m.file[0] = true
    m.body = ioBody()
    if mode = "malformed-body" then m.body = "not a playlist"
    m.waits = 0
    m.top = {owner:"owned-current", source:"https://fixture.ttvnw.net/current.m3u8?signature=SECRET", sourceKind:"direct", stopRequested:false, ObserveField:ioObserve, UnobserveField:ioUnobserve, trace:m.trace}
    if mode = "invalid-source" then m.top.source = "https://untrusted.invalid/a"
    if mode = "initial-stop" then m.top.stopRequested = true
    readMetadata()
    final = m.responses[m.responses.Count() - 1]
    check(final.closed and final.owner = "owned-current" and final.cues.Count() = 0 and final.bounds.Count() = 0, "actual final typed closed response " + mode)
    check(final.Count() = 5, "actual response sanitized shape " + mode)
    dataCount = 0
    for each response in m.responses
        if not response.DoesExist("closed") and response.cues.Count() > 0 then dataCount += 1
    end for
    check(dataCount = 1 or mode <> "before", "actual before-deadline complete source delivers one sanitized cue")
    check(dataCount = 0 or mode = "before", "actual at/after deadline or unsafe source never supplies cues " + mode)
    cancelCount = 0: completedCount = 0: deleteCount = 0
    for each action in m.trace
        if action = "cancel" then cancelCount += 1
        if action = "getInt" then completedCount += 1
        if action = "delete" then deleteCount += 1
    end for
    needsCancel = mode = "nonmatching" or mode = "stop" or mode = "cancel-fails"
    check(cancelCount = 1 or not needsCancel, "actual sole active IO cancelled once " + mode)
    check(cancelCount = 0 or needsCancel, "completed/unstarted IO is not cancelled " + mode)
    matching = mode = "before" or mode = "equal" or mode = "after" or mode = "malformed-body"
    check(completedCount = 1 or not matching, "matching completion executes GetInt once " + mode)
    check(completedCount = 0 or matching, "nonmatching or stop cannot consume completion " + mode)
    if mode = "foreign-file"
        check(not final.cleanupOk and m.file[0] and deleteCount = 0, "foreign staging file remains blocked and untouched")
    else
        check(not m.file[0], "owned staging file removed before closed ack " + mode)
        check(final.cleanupOk = (mode <> "cancel-fails"), "safe cancellation acknowledgement cannot be fabricated " + mode)
    end if
    safe = FormatJson(m.responses)
    check(safe.InStr("SECRET") < 0 and safe.InStr("secret-provider") < 0 and safe.InStr("secret-segment") < 0, "actual Task never publishes source/ID/body " + mode)
end sub
function adFixtureCreateObject(name as string) as object
    if name = "roMessagePort" then return {}
    if name = "roTimespan" then return {TotalMilliseconds:ioClock, times:m.times}
    if name = "roFileSystem" then return {Exists:ioExists, Stat:ioStat, Delete:ioDelete, file:m.file, body:m.body, trace:m.trace}
    if name = "roUrlTransfer"
        return {SetMessagePort:ioSetPort, SetCertificatesFile:ioCertificates, EnablePeerVerification:ioTrue, EnableHostVerification:ioTrue, EnableEncodings:ioTrue, EnableResume:ioTrue, SetMinimumTransferRate:ioRate, SetHeaders:ioHeaders, SetUrl:ioSetUrl, GetUrl:ioGetUrl, GetIdentity:ioIdentity, AsyncGetToFile:ioStart, AsyncCancel:ioCancel, trace:m.trace, file:m.file, mode:m.mode}
    end if
    return CreateObject(name)
end function
function adFixtureWait(duration as integer, port as object) as dynamic
    m.waits += 1
    if m.mode = "stop" or m.waits > 1
        m.top.stopRequested = true
        return invalid
    end if
    identity = "matching"
    if m.mode = "nonmatching" or m.mode = "cancel-fails" then identity = "stale"
    return {nativeType:"roUrlEvent", GetSourceIdentity:ioEventIdentity, GetInt:ioEventInt, GetResponseCode:ioEventCode, GetResponseHeadersArray:ioEventHeaders, identity:identity, trace:m.trace, body:m.body}
end function
function adFixtureType(event as dynamic) as string
    if type(event) = "roAssociativeArray" then return event.nativeType
    return type(event)
end function
function adFixtureRead(path as string) as string
    return m.body
end function
sub adFixtureEmit(response as object)
    m.responses.Push(response)
    m.top.response = response
end sub
sub ioObserve(name as string, port as object)
    m.trace.Push("observe")
end sub
sub ioUnobserve(name as string)
    m.trace.Push("unobserve")
end sub
function ioClock() as integer
    if m.times.Count() > 0 then return m.times.Shift()
    return 4999
end function
function ioExists(path as string) as boolean
    return m.file[0]
end function
function ioStat(path as string) as dynamic
    if not m.file[0] then return invalid
    return {type:"file", size:m.body.Len()}
end function
function ioDelete(path as string) as boolean
    m.trace.Push("delete")
    m.file[0] = false
    return true
end function
sub ioSetPort(port as object)
    m.trace.Push("port")
end sub
function ioCertificates(path as string) as boolean
    m.trace.Push("certificates")
    return m.mode <> "config-fails"
end function
function ioTrue(enable as boolean) as boolean
    m.trace.Push("tls-option")
    return true
end function
function ioRate(rate as integer, seconds as integer) as boolean
    m.trace.Push("rate")
    return true
end function
function ioHeaders(headers as object) as boolean
    m.trace.Push("headers")
    return true
end function
sub ioSetUrl(url as string)
    m.url = url
end sub
function ioGetUrl() as string
    return m.url
end function
function ioIdentity() as string
    return "matching"
end function
function ioStart(path as string) as boolean
    m.trace.Push("start")
    m.file[0] = true
    return true
end function
function ioCancel() as boolean
    m.trace.Push("cancel")
    return m.mode <> "cancel-fails"
end function
function ioEventIdentity() as string
    return m.identity
end function
function ioEventInt() as integer
    m.trace.Push("getInt")
    return 1
end function
function ioEventCode() as integer
    return 200
end function
function ioEventHeaders() as object
    return [{"Content-Length":m.body.Len().ToStr()}]
end function
