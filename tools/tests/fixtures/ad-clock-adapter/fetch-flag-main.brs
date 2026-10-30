' Full production URL handler/feed/Core run; only native URL event/filesystem are unavailable.
sub main()
    m.assertions = 0
    m.failures = 0
    print "STITCH_AD_CLOCK_BEGIN: __MARKER__"
    for each mode in ["absent", "invalid", "string-true", "string-false", "number-one", "number-zero", "object", "array", "false", "true"]
        testActualFetchFlag(mode)
    end for
    print "STITCH_AD_CLOCK_END: __MARKER__ "; FormatJson({assertions:m.assertions,failures:m.failures})
end sub
sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_AD_CLOCK_FAIL: __MARKER__ " + message
    end if
end sub
function fetchFlagBody() as string
    q = Chr(34)
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:2" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:41" + Chr(10)
    text += "#EXT-X-MAP:URI=" + q + "init.mp4" + q + Chr(10)
    text += "#EXT-X-DATERANGE:ID=" + q + "PRIVATE_PROVIDER_ID" + q + ",CLASS=" + q + "twitch-stitched-ad" + q + ",START-DATE=" + q + "2026-01-01T00:00:01.500001Z" + q + ",DURATION=4.250001" + Chr(10)
    for i = 0 to 3
        text += "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:0" + (i * 2).ToStr() + ".000000Z" + Chr(10)
        text += "#EXTINF:2.000," + Chr(10) + "segment-" + i.ToStr() + ".m4s" + Chr(10)
    end for
    return text
end function
sub testActualFetchFlag(mode as string)
    m.top = {stopRequested:false}
    m.file = [true]
    m.trace = []
    m.body = fetchFlagBody()
    state = nativeLiveCreate("https://fixture.ttvnw.net/current.m3u8", 0&, 0)
    if mode = "invalid" then state.adClockEnabled = invalid
    if mode = "string-true" then state.adClockEnabled = "true"
    if mode = "string-false" then state.adClockEnabled = "false"
    if mode = "number-one" then state.adClockEnabled = 1
    if mode = "number-zero" then state.adClockEnabled = 0
    if mode = "object" then state.adClockEnabled = {}
    if mode = "array" then state.adClockEnabled = []
    if mode = "false" then state.adClockEnabled = false
    if mode = "true" then state.adClockEnabled = true
    state.ownInputFile = true
    state.op = {identity:"owned",kind:"playlist",url:state.sourceUrl,limit:262144,phase:"get",deadline:5000&,transfer:{AsyncCancel:fetchFlagCancel,trace:m.trace}}
    event = {nativeType:"roUrlEvent",GetSourceIdentity:fetchFlagIdentity,GetInt:fetchFlagInt,GetResponseCode:fetchFlagStatus,GetResponseHeadersArray:fetchFlagHeaders,trace:m.trace,body:m.body}
    check(nativeLiveHandleUrlEvent(state,event,4999&), "actual matching completed URL event consumed " + mode)
    check(state.phase = "init" and state.playlistCount = 1 and state.epoch = 0 and state.lastPlaylistSequence = 41, "actual Core playlist feed unaffected by flag boundary " + mode)
    check(state.op = invalid and not state.ownInputFile and not m.file[0], "actual completed transfer/input cleanup unchanged " + mode)
    check(state.error = "" and state.failureCategory = 0 and not state.closed, "disabled or malformed metadata flag cannot abort actual playback " + mode)
    getIntCount = 0:cancelCount = 0:deleteCount = 0
    for each action in m.trace
        if action = "getInt" then getIntCount += 1
        if action = "cancel" then cancelCount += 1
        if action = "delete" then deleteCount += 1
    end for
    check(getIntCount = 1 and cancelCount = 0 and deleteCount = 1, "actual transfer method and owned cleanup executes once " + mode)
    if mode = "true"
        check(twitchAdClockTimelineValid(state.adClockTimeline) and state.adClockSource = state.sourceUrl, "typed true captures actual current-source timeline")
        check(state.adClockTimeline.cues[0].startUs = 1767225601500001& and state.adClockTimeline.cues[0].durationUs = 4250001&, "typed true preserves exact sanitized cue precision")
        check(FormatJson(state.adClockTimeline).InStr("PRIVATE_PROVIDER_ID") < 0, "typed true never forwards raw cue identity")
    else
        check(state.adClockTimeline = invalid and state.adClockSource = invalid, "all absent/malformed/false flags leave metadata disabled " + mode)
    end if
end sub
function fetchFlagType(value as dynamic) as string
    if type(value) = "roAssociativeArray" then return value.nativeType
    return type(value)
end function
function fetchFlagCreateObject(name as string) as object
    if name = "roFileSystem" then return {Exists:fetchFlagExists,Stat:fetchFlagStat,Delete:fetchFlagDelete,file:m.file,body:m.body,trace:m.trace}
    return CreateObject(name)
end function
function fetchFlagRead(path as string) as string
    m.trace.Push("read")
    return m.body
end function
function fetchFlagExists(path as string) as boolean
    m.trace.Push("exists")
    return m.file[0]
end function
function fetchFlagStat(path as string) as object
    m.trace.Push("stat")
    return {type:"file",size:m.body.Len()}
end function
function fetchFlagDelete(path as string) as boolean
    m.trace.Push("delete")
    m.file[0] = false
    return true
end function
function fetchFlagIdentity() as string
    m.trace.Push("identity")
    return "owned"
end function
function fetchFlagInt() as integer
    m.trace.Push("getInt")
    return 1
end function
function fetchFlagStatus() as integer
    m.trace.Push("status")
    return 200
end function
function fetchFlagHeaders() as object
    m.trace.Push("headers")
    return [{"Content-Length":m.body.Len().ToStr()}]
end function
function fetchFlagCancel() as boolean
    m.trace.Push("cancel")
    return true
end function
