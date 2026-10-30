sub main()
    m.assertions = 0
    m.failures = 0
    print "STITCH_AD_CLOCK_BEGIN: __MARKER__"
    for each mode in ["timing-missing", "timing-malformed", "gap-stop", "gap-active-stop", "gap-cancel-blocked", "gap-delete-blocked", "gap-location", "gap-length", "gap-short-read", "gap-stale", "gap-expired", "gap-missing-completion"]
        runActualGapMetadata(mode)
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

function gapBody(poll as integer, mode as string) as string
    date = "2026-01-01T00:00:00Z"
    if poll = 3 then date = "2026-01-01T00:00:04Z"
    q = Chr(34)
    nl = Chr(10)
    body = "#EXTM3U" + nl + "#EXT-X-TARGETDURATION:2" + nl + "#EXT-X-MEDIA-SEQUENCE:" + poll.ToStr() + nl
    body += "#EXT-X-DATERANGE:ID=" + q + "secret-provider-ID" + q + ",CLASS=" + q + "twitch-stitched-ad" + q + ",START-DATE=" + q + date + q + ",DURATION=2" + nl
    if poll <> 2 or mode = "timing-malformed" then body += "#EXT-X-PROGRAM-DATE-TIME:" + date + nl
    if poll = 2 and mode = "timing-malformed" then body = body.Replace(",DURATION=2", ",DURATION=bad")
    return body + "#EXTINF:2," + nl + "secret-segment.m4s" + nl
end function

sub runActualGapMetadata(mode as string)
    m.mode = mode
    m.now = [0]
    m.poll = [0]
    m.file = [false]
    m.delivered = [false]
    m.raw = [""]
    m.trace = []
    m.responses = []
    m.publications = []
    m.starts = []
    m.creations = []
    m.waits = 0
    m.top = { owner: "owned-current", source: "https://fixture.ttvnw.net/current.m3u8?signature=SECRET", sourceKind: "direct", stopRequested: false, ObserveField: gapObserve, UnobserveField: gapUnobserve, trace: m.trace }
    readMetadata()
    final = m.responses[m.responses.Count() - 1]
    check(final.Count() = 5 and final.closed and final.owner = "owned-current" and final.cues.Count() = 0 and final.bounds.Count() = 0, "final exact sanitized closed acknowledgment " + mode)
    data = []
    empties = 0
    for each publication in m.publications
        response = publication.response
        check(response.Count() = 3 and response.owner = "owned-current", "same owner primitive publication " + mode)
        if response.cues.Count() > 0
            data.Push(publication)
        else
            check(response.bounds.Count() = 0, "unknown timing has no retained bounds " + mode)
            if publication.poll = 2 then empties += 1
        end if
    end for
    recover = mode = "timing-missing" or mode = "timing-malformed"
    expectedData = 1
    if recover then expectedData = 2
    check(data.Count() = expectedData, "hard response cannot supply later cues " + mode)
    check(empties = 1, "actual gap explicitly publishes empty cues and bounds " + mode)
    if data.Count() > 0
        first = data[0].response
        check(first.cues.Count() = 1 and first.cues[0].Count() = 5 and first.cues[0].startUs = 1767225600000000& and first.cues[0].durationUs = 2000000&, "independent first cue timing golden " + mode)
    end if
    if recover
        check(data.Count() = 2 and m.publications.Count() = 3, "same worker resumes valid metadata after optional gap " + mode)
        if data.Count() = 2
            check(data[1].poll = 3 and data[1].response.cues[0].startUs = 1767225604000000&, "recovered cue uses fresh current timing " + mode)
        end if
    end if
    expectedPoll = 3
    if mode = "gap-stop" or mode = "gap-delete-blocked" then expectedPoll = 2
    check(m.poll[0] = expectedPoll, "same invocation starts exact demand polls " + mode)
    check(m.creations.Count() = m.poll[0], "fresh transfer object per poll without replacement worker " + mode)
    check(m.starts.Count() = m.poll[0], "every poll uses an owned fresh staging file " + mode)
    if m.starts.Count() >= 2 then check(m.starts[1] = 2050, "first post-completion poll keeps exact two-second cadence " + mode)
    if m.starts.Count() >= 3 then check(m.starts[2] = 4100, "gap continuation keeps exact two-second cadence " + mode)
    deletes = 0
    cancels = 0
    completions = 0
    observed = 0
    unobserved = 0
    overwrites = 0
    missingStats = 0
    for each action in m.trace
        if action = "delete" then deletes += 1
        if action = "cancel" then cancels += 1
        if action = "getInt" then completions += 1
        if action = "observe" then observed += 1
        if action = "unobserve" then unobserved += 1
        if action = "start-overwrite" then overwrites += 1
        if action = "stat-absent" then missingStats += 1
    end for
    check(overwrites = 0, "fresh poll must not overwrite an undeleted staging file " + mode)
    check(missingStats = 0, "actual Stat never observes a missing staging file " + mode)
    check(observed = 1 and unobserved = 1, "one worker invocation pairs actual stop observer " + mode)
    expectedCancel = 0
    if mode = "gap-active-stop" or mode = "gap-cancel-blocked" or mode = "gap-stale" then expectedCancel = 1
    check(cancels = expectedCancel, "only pending operation receives sole cancellation " + mode)
    expectedCompleted = expectedPoll
    if expectedCancel = 1 then expectedCompleted -= 1
    check(completions = expectedCompleted, "only matching completed event is consumed " + mode)
    unsafe = mode = "gap-cancel-blocked" or mode = "gap-delete-blocked"
    check(final.cleanupOk = not unsafe, "unsafe cleanup remains a terminal refusal " + mode)
    if mode = "gap-delete-blocked"
        check(m.file[0] and deletes = 3, "failed gap deletion retries cleanup and retains unsafe file")
    else
        check(not m.file[0] and deletes = expectedPoll, "each owned fresh file is deleted before final acknowledgment " + mode)
    end if
    if recover or mode = "gap-stop" or mode = "gap-active-stop" or mode = "gap-cancel-blocked" then check(m.top.stopRequested, "only explicit stop ends healthy or paused gap lifetime " + mode)
    if mode = "gap-stale" then check(m.now[0] = 9100, "stale completion remains pending until original five-second deadline")
    safe = FormatJson(m.responses)
    check(safe.InStr("SECRET") < 0 and safe.InStr("secret-provider") < 0 and safe.InStr("secret-segment") < 0, "gap and recovery retain no raw provider data " + mode)
end sub

function adFixtureCreateObject(name as string) as object
    if name = "roMessagePort" then return {}
    if name = "roTimespan" then return { TotalMilliseconds: gapClock, now: m.now }
    if name = "roFileSystem" then return { Exists: gapExists, Stat: gapStat, Delete: gapDelete, file: m.file, raw: m.raw, trace: m.trace, poll: m.poll, mode: m.mode }
    if name = "roUrlTransfer"
        m.creations.Push(m.poll[0] + 1)
        return { SetMessagePort: gapSetPort, SetCertificatesFile: gapCertificates, EnablePeerVerification: gapTrue, EnableHostVerification: gapTrue, EnableEncodings: gapTrue, EnableResume: gapTrue, SetMinimumTransferRate: gapRate, SetHeaders: gapHeaders, SetUrl: gapSetUrl, GetUrl: gapGetUrl, GetIdentity: gapIdentity, AsyncGetToFile: gapStart, AsyncCancel: gapCancel, identity: "operation-" + (m.poll[0] + 1).ToStr(), trace: m.trace, file: m.file, poll: m.poll, mode: m.mode, raw: m.raw, now: m.now, starts: m.starts, delivered: m.delivered }
    end if
    return CreateObject(name)
end function

function adFixtureWait(duration as integer, port as object) as dynamic
    m.waits += 1
    m.now[0] += duration
    if m.now[0] > 12000
        check(false, "finite fixture cannot hide an unbounded metadata loop")
        m.top.stopRequested = true
        return invalid
    end if
    if m.delivered[0] then return invalid
    if m.poll[0] = 3 and (m.mode = "gap-active-stop" or m.mode = "gap-cancel-blocked")
        m.file[0] = true
        m.top.stopRequested = true
        return invalid
    end if
    if m.poll[0] = 3 and m.mode = "gap-expired" then m.now[0] += 4950
    m.delivered[0] = true
    m.file[0] = true
    identity = "operation-" + m.poll[0].ToStr()
    if m.poll[0] = 3 and m.mode = "gap-stale" then identity = "operation-1"
    return { nativeType: "roUrlEvent", GetSourceIdentity: gapEventIdentity, GetInt: gapEventInt, GetResponseCode: gapEventCode, GetResponseHeadersArray: gapEventHeaders, identity: identity, trace: m.trace, raw: m.raw, poll: m.poll, mode: m.mode }
end function

function adFixtureType(event as dynamic) as string
    if type(event) = "roAssociativeArray" then return event.nativeType
    return type(event)
end function

function adFixtureRead(path as string) as string
    if m.poll[0] = 3 and m.mode = "gap-short-read" then return m.raw[0].Left(m.raw[0].Len() - 1)
    return m.raw[0]
end function

sub adFixtureEmit(response as object)
    m.responses.Push(response)
    m.top.response = response
    if response.DoesExist("closed") then return
    m.publications.Push({ response: response, poll: m.poll[0] })
    if m.poll[0] = 2 and m.mode = "gap-stop" then m.top.stopRequested = true
    if m.poll[0] = 3 and (m.mode = "timing-missing" or m.mode = "timing-malformed") then m.top.stopRequested = true
end sub

sub gapObserve(name as string, port as object)
    m.trace.Push("observe")
end sub

sub gapUnobserve(name as string)
    m.trace.Push("unobserve")
end sub

function gapClock() as integer
    return m.now[0]
end function

function gapExists(path as string) as boolean
    return m.file[0]
end function

function gapStat(path as string) as object
    if not m.file[0] then m.trace.Push("stat-absent")
    return { type: "file", size: m.raw[0].Len() }
end function

function gapDelete(path as string) as boolean
    m.trace.Push("delete")
    if m.poll[0] = 2 and m.mode = "gap-delete-blocked" then return false
    m.file[0] = false
    return true
end function

sub gapSetPort(port as object)
end sub

function gapCertificates(path as string) as boolean
    return path = "common:/certs/ca-bundle.crt"
end function

function gapTrue(enable as boolean) as boolean
    return true
end function

function gapRate(rate as integer, seconds as integer) as boolean
    return rate = 1 and seconds = 2
end function

function gapHeaders(headers as object) as boolean
    return headers.Count() = 2 and headers["Accept-Encoding"] = "identity" and headers["Range"] = "bytes=0-262143"
end function

sub gapSetUrl(url as string)
    m.url = url
end sub

function gapGetUrl() as string
    return m.url
end function

function gapIdentity() as string
    return m.identity
end function

function gapStart(path as string) as boolean
    if m.file[0] then m.trace.Push("start-overwrite")
    m.poll[0] += 1
    m.starts.Push(m.now[0])
    m.raw[0] = gapBody(m.poll[0], m.mode)
    m.delivered[0] = false
    return true
end function

function gapCancel() as boolean
    m.trace.Push("cancel")
    return m.mode <> "gap-cancel-blocked"
end function

function gapEventIdentity() as string
    return m.identity
end function

function gapEventInt() as integer
    m.trace.Push("getInt")
    if m.poll[0] = 3 and m.mode = "gap-missing-completion" then return 0
    return 1
end function

function gapEventCode() as integer
    return 200
end function

function gapEventHeaders() as object
    size = m.raw[0].Len()
    if m.poll[0] = 3 and m.mode = "gap-length" then size += 1
    headers = [{ "Content-Length": size.ToStr() }]
    if m.poll[0] = 3 and m.mode = "gap-location" then headers.Push({ "Location": "https://untrusted.invalid/redirect" })
    return headers
end function
