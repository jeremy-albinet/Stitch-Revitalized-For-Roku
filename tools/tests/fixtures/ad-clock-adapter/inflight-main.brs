sub main()
    m.assertions = 0
    m.failures = 0
    print "STITCH_AD_CLOCK_BEGIN: __MARKER__"
    for each mode in ["second-delayed", "present-empty", "present-invalid", "present-type", "present-oversize", "missing-deadline", "late-event", "missing-completion", "cancel-blocked", "delete-blocked", "typed-stop"]
        runActualInflightMetadata(mode)
    end for
    print "STITCH_AD_CLOCK_END: __MARKER__ "; FormatJson({ assertions: m.assertions, failures: m.failures })
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

sub runActualInflightMetadata(mode as string)
    m.mode = mode
    m.trace = []
    m.responses = []
    m.times = [0, 50, 2000, 2050, 2100, 2150, 2200]
    if mode = "missing-deadline" or mode = "cancel-blocked" then m.times = [0, 50, 2000, 2050, 7050]
    if mode = "late-event" then m.times = [0, 50, 2000, 2050, 2100, 7050]
    m.file = [false]
    m.poll = [0]
    m.body = ioBody()
    m.waits = 0
    m.top = { owner: "owned-current", source: "https://fixture.ttvnw.net/current.m3u8?signature=SECRET", sourceKind: "direct", stopRequested: false, ObserveField: ioObserve, UnobserveField: ioUnobserve, trace: m.trace }
    readMetadata()
    final = m.responses[m.responses.Count() - 1]
    check(final.closed and final.owner = "owned-current" and final.cues.Count() = 0 and final.bounds.Count() = 0 and final.Count() = 5, "actual safe closed shape " + mode)
    dataCount = 0
    for each response in m.responses
        if not response.DoesExist("closed") and response.cues.Count() > 0 then dataCount += 1
    end for
    successful = mode = "second-delayed" or mode = "delete-blocked"
    expectedData = 1
    if successful then expectedData = 2
    check(dataCount = expectedData, "actual independent two-poll publication count " + mode)
    cancelCount = 0
    completedCount = 0
    deleteCount = 0
    absentStatCount = 0
    observeCount = 0
    unobserveCount = 0
    for each action in m.trace
        if action = "cancel" then cancelCount += 1
        if action = "getInt" then completedCount += 1
        if action = "delete" then deleteCount += 1
        if action = "stat-absent" then absentStatCount += 1
        if action = "observe" then observeCount += 1
        if action = "unobserve" then unobserveCount += 1
    end for
    check(m.poll[0] = 2, "actual second async operation started " + mode)
    check(absentStatCount = 0, "absent in-flight destination never receives Stat " + mode)
    needsCancel = mode = "present-empty" or mode = "present-invalid" or mode = "present-type" or mode = "present-oversize" or mode = "missing-deadline" or mode = "cancel-blocked" or mode = "typed-stop"
    expectedCancel = 0
    if needsCancel then expectedCancel = 1
    check(cancelCount = expectedCancel, "actual sole pending cancellation and no completed cancellation " + mode)
    matchingSecond = successful or mode = "late-event" or mode = "missing-completion"
    expectedCompleted = 1
    if matchingSecond then expectedCompleted = 2
    check(completedCount = expectedCompleted, "actual completion GetInt exactly once per matching event " + mode)
    check(observeCount = 1 and unobserveCount = 1, "actual Task stop observer paired " + mode)
    blocked = mode = "cancel-blocked" or mode = "delete-blocked"
    check(final.cleanupOk = not blocked, "unsafe cancellation/deletion cannot acknowledge success " + mode)
    if mode = "delete-blocked"
        check(m.file[0] and deleteCount = 3, "blocked own file remains after actual two failed deletions")
    else
        check(not m.file[0], "actual owned path absent before final closed ack " + mode)
    end if
    if mode = "second-delayed"
        check(m.top.stopRequested and m.waits = 5 and cancelCount = 0 and deleteCount = 2, "delayed file permits two publications then typed stop without premature cancel")
        check(m.responses.Count() = 3 and not m.responses[0].DoesExist("closed") and not m.responses[1].DoesExist("closed"), "actual publication/publication/closed order without empty or early closed response")
    end if
    if mode = "missing-deadline" or mode = "cancel-blocked"
        check(m.waits = 3 and completedCount = 1, "missing file cannot bypass five-second deadline before another wait")
    end if
    safe = FormatJson(m.responses)
    check(safe.InStr("SECRET") < 0 and safe.InStr("secret-provider") < 0 and safe.InStr("secret-segment") < 0, "actual response remains sanitized " + mode)
end sub

function adFixtureCreateObject(name as string) as object
    if name = "roMessagePort" then return {}
    if name = "roTimespan" then return { TotalMilliseconds: ioClock, times: m.times }
    if name = "roFileSystem" then return { Exists: ioExists, Stat: ioStat, Delete: ioDelete, file: m.file, body: m.body, trace: m.trace, poll: m.poll, mode: m.mode }
    if name = "roUrlTransfer"
        return { SetMessagePort: ioSetPort, SetCertificatesFile: ioCertificates, EnablePeerVerification: ioTrue, EnableHostVerification: ioTrue, EnableEncodings: ioTrue, EnableResume: ioTrue, SetMinimumTransferRate: ioRate, SetHeaders: ioHeaders, SetUrl: ioSetUrl, GetUrl: ioGetUrl, GetIdentity: ioIdentity, AsyncGetToFile: ioStart, AsyncCancel: ioCancel, trace: m.trace, file: m.file, poll: m.poll, mode: m.mode }
    end if
    return CreateObject(name)
end function

function adFixtureWait(duration as integer, port as object) as dynamic
    m.waits += 1
    if m.waits = 2 then return invalid ' Poll interval before second operation.
    if m.waits = 3
        if m.mode.Left(8) = "present-" then m.file[0] = true
        if m.mode = "typed-stop" then m.top.stopRequested = true
        return invalid ' Actual second download has not created a file yet.
    end if
    if m.waits > 4
        m.top.stopRequested = true
        return invalid
    end if
    m.file[0] = true
    return { nativeType: "roUrlEvent", GetSourceIdentity: ioEventIdentity, GetInt: ioEventInt, GetResponseCode: ioEventCode, GetResponseHeadersArray: ioEventHeaders, trace: m.trace, body: m.body, poll: m.poll, mode: m.mode }
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
    return 7050
end function

function ioExists(path as string) as boolean
    return m.file[0]
end function

function ioStat(path as string) as dynamic
    if not m.file[0]
        m.trace.Push("stat-absent")
        return {} ' Actual R5 native empty-AA result for absent async destination.
    end if
    if m.poll[0] = 2
        if m.mode = "present-empty" then return {}
        if m.mode = "present-invalid" then return invalid
        if m.mode = "present-type" then return { type: "directory", size: 0 }
        if m.mode = "present-oversize" then return { type: "file", size: 262145 }
    end if
    return { type: "file", size: m.body.Len() }
end function

function ioDelete(path as string) as boolean
    m.trace.Push("delete")
    if m.poll[0] = 2 and m.mode = "delete-blocked" then return false
    m.file[0] = false
    return true
end function

sub ioSetPort(port as object)
end sub

function ioCertificates(path as string) as boolean
    return true
end function

function ioTrue(enable as boolean) as boolean
    return true
end function

function ioRate(rate as integer, seconds as integer) as boolean
    return true
end function

function ioHeaders(headers as object) as boolean
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
    m.poll[0] += 1
    m.file[0] = false
    return true
end function

function ioCancel() as boolean
    m.trace.Push("cancel")
    return m.mode <> "cancel-blocked"
end function

function ioEventIdentity() as string
    return "matching"
end function

function ioEventInt() as integer
    m.trace.Push("getInt")
    if m.poll[0] = 2 and m.mode = "missing-completion" then return 0
    return 1
end function

function ioEventCode() as integer
    return 200
end function

function ioEventHeaders() as object
    return [{ "Content-Length": m.body.Len().ToStr() }]
end function
