' Full production Server + Fetch + Core + metadata helpers. Only native IO,
' clock samples and device decoder availability are explicit boundaries.
sub main()
    m.assertions = 0
    m.failures = 0
    m.configSnapshot = ParseJson(ReadAsciiFile("pkg:/worker-config.json"))
    m.corpus = ParseJson(ReadAsciiFile("pkg:/corpus.json"))
    m.trace = []
    m.file = [false]
    m.nativeClock = [0]
    print "AD_LIVE_BEGIN: __MARKER__"
    for each flag in ["session", "absent", "false", "string", "number", "invalid"]
        bootstrap(flag)
    end for
    for each mode in ["valid", "crlf", "missing-pdt", "malformed-pdt", "unknown-class", "missing-duration"]
        pipeline(mode)
    end for
    print "AD_LIVE_END: __MARKER__ "; FormatJson({assertions:m.assertions,failures:m.failures})
end sub

sub check(ok as boolean, reason as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "AD_LIVE_FAIL: __MARKER__ " + reason
    end if
end sub

function descriptor() as object
    return {"version":m.configSnapshot.version,"sourceUrl":"https://fixture.ttvnw.net/current.m3u8","qualityId":"720p60","approvedOrigins":["https://fixture.ttvnw.net"],
        "metadata":{"videoCodec":"avc1.4D4020","audioCodec":"mp4a.40.2","width":1280,"height":720,"frameRate":"60.000","bandwidth":3322199,"isHD":true}}
end function

sub bootstrap(mode as string)
    m.nativeClock[0] = 0
    m.capture = []
    m.trace = []
    m.top = {sessionId:"0123456789abcdef0123456789abcdef",inputDescriptor:descriptor(),stopRequested:false,
        experimentalMode:m.configSnapshot.experimentalMode,enableSourceTransitions:false,cacheBudgetBytes:m.configSnapshot.cacheBudgetBytes,
        listenPort:m.configSnapshot.listenPort,ObserveField:ioObserve,UnobserveField:ioUnobserve,trace:m.trace}
    if mode = "session" then m.top.enableAdMetadata = m.configSnapshot.enableAdMetadata
    if mode = "false" then m.top.enableAdMetadata = false
    if mode = "string" then m.top.enableAdMetadata = "true"
    if mode = "number" then m.top.enableAdMetadata = 1
    if mode = "invalid" then m.top.enableAdMetadata = invalid
    ' The fake native transfer captures its actual state and refuses native IO.
    ' The real error/cleanup path executes; no network or listener is opened.
    runServer()
    check(m.capture.Count() = 1, "actual server starts exactly one bounded upstream transfer " + mode)
    if m.capture.Count() = 1
        actual = m.capture[0]
        check(GetInterface(actual, "ifBoolean") <> invalid and actual = (mode = "session"), "actual Server forwards strict Session opt-in to Fetch state " + mode)
        if mode = "session" then m.enabledSnapshot = actual
    end if
    r = m.top.result
    check(r.status = "failed" and r.reason = "live_helper_failed", "actual deliberately refused native transfer preserves failure " + mode)
    check(r.cleanupOk and r.listenerClosed and r.connectionClosed and r.helperClosed and r.cacheReferencesReleased, "actual bootstrap cleanup remains fully acknowledged " + mode)
    check(m.liveState = invalid and m.top.inputDescriptor = invalid, "actual bootstrap retains no live state/input " + mode)
    check(m.trace.Count() >= 3 and m.trace[0] = "observe" and m.trace[m.trace.Count()-1] = "unobserve", "actual bootstrap observer pairing " + mode)
    if mode = "session" then m.resultSnapshot = ParseJson(FormatJson(r))
end sub

function body(mode as string) as string
    q = Chr(34)
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:2" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:10" + Chr(10)
    text += "#EXT-X-MAP:URI=" + q + "init.mp4" + q + Chr(10)
    cue = "#EXT-X-DATERANGE:ID=" + q + "PRIVATE_ID" + q + ",CLASS=" + q + "twitch-stitched-ad" + q + ",START-DATE=" + q + "2026-01-01T00:00:01.500001Z" + q + ",DURATION=4.250001,X-TV-TWITCH-AD-URL=" + q + "https://private.invalid/SECRET" + q
    if mode = "unknown-class" then cue = cue.Replace("twitch-stitched-ad", "future-source-cue")
    if mode = "missing-duration" then cue = cue.Replace(",DURATION=4.250001", "")
    text += cue + Chr(10)
    for i = 0 to 2
        date = "2026-01-01T00:00:0" + (i * 2).ToStr() + ".000000Z"
        if mode = "malformed-pdt" and i = 0 then date = "UNKNOWN"
        if mode <> "missing-pdt" then text += "#EXT-X-PROGRAM-DATE-TIME:" + date + Chr(10)
        text += "#EXTINF:2.000000," + Chr(10) + "segment-" + (10+i).ToStr() + ".m4s" + Chr(10)
    end for
    if mode = "crlf" then text = text.Replace(Chr(10), Chr(13)+Chr(10))
    return text
end function

sub pipeline(mode as string)
    m.top = {stopRequested:false}
    m.trace = []
    m.file[0] = true
    m.body = body(mode)
    m.nativeClock[0] = 4999
    state = nativeLiveCreate("https://fixture.ttvnw.net/current.m3u8",0&,0,invalid,true,16777216&,{mode:"steady",sessionId:"0123456789abcdef0123456789abcdef"})
    state.adClockEnabled = m.enabledSnapshot
    state.ownInputFile = true
    state.op = {identity:"owned",kind:"playlist",url:state.sourceUrl,limit:262144,phase:"get",deadline:5000&,transfer:{AsyncCancel:ioCancel,trace:m.trace}}
    event = {nativeType:"roUrlEvent",GetSourceIdentity:ioIdentity,GetInt:ioInt,GetResponseCode:ioStatus,GetResponseHeadersArray:ioHeaders,body:m.body}
    check(nativeLiveHandleUrlEvent(state,event,4999&), "actual Fetch completion consumed " + mode)
    check(state.phase = "init" and state.playlistCount = 1 and state.epoch = 0 and state.error = "", "metadata never changes actual Core playlist decisions " + mode)
    check(state.op = invalid and not state.ownInputFile and not m.file[0], "completed transfer ownership cleanup unchanged " + mode)
    init = CreateObject("roByteArray")
    init.FromHexString(m.corpus.init.input.hex)
    nativeLiveFeed(state,"init",init,4999&)
    nativeLiveAdvance(state,4999&)
    nativeLiveAdvance(state,4999&)
    for i = 0 to 2
        segment = CreateObject("roByteArray")
        segment.FromHexString(m.corpus.media[i].input.hex)
        nativeLiveFeed(state,"segment",segment,4999&)
        nativeLiveAdvance(state,4999&)
        nativeLiveAdvance(state,4999&)
    end for
    check(state.phase = "ready" and state.initPairCount = 1 and state.segmentPairCount = 3, "independent binary corpus creates actual split publication " + mode)
    m.clock = {TotalMilliseconds:ioClock,nativeClock:m.nativeClock}
    m.monotonicClock = nativeLiveClockCreate(0)
    m.lastNowMs = 0&
    m.steadyMode = true
    m.counterExhausted = false
    m.closing = false
    m.sessionId = state.sessionId
    m.liveState = state
    m.port = invalid
    m.cacheBudgetBytes = 16777216
    m.httpQuota = liveQuotaCreate(0&)
    m.result = ParseJson(FormatJson(m.resultSnapshot))
    m.result.reason = "not_started"
    m.publications = {}
    m.currentPublication = invalid
    m.currentGeneration = 0&
    m.activeLease = ""
    m.activeGeneration = 0
    m.connection = invalid
    m.adMetadataEnabled = m.enabledSnapshot
    m.config = {sourceDelaySeconds:0,metadata:descriptor()["metadata"]}
    check(pumpLiveServer(1), "actual Server pump accepts actual Core publication " + mode)
    pub = m.currentPublication
    check(pub <> invalid and loopbackPublicationValid(pub) and m.result.publicationsObserved = 1, "immutable publication validated without metadata policy changes " + mode)
    if pub = invalid then return
    key = pub.generation.ToStr()
    initial = FormatJson(pub)
    projection = m.publications[key].adProjection
    for each track in ["video", "audio", "master"]
        response = prepareLiveResponse({track:track})
        check(response <> invalid and response.bytes = response.data.Count(), "actual response length remains truthful " + mode + track)
        text = response.data.ToAsciiString()
        check(text.InStr("PRIVATE_ID") < 0 and text.InStr("SECRET") < 0 and text.InStr("private.invalid") < 0, "only sanitized cues enter local manifest " + mode + track)
        if track = "master"
            check(text = loopbackManifest(track,pub).ToAsciiString(), "master remains exactly canonical " + mode)
        else
            reload = twitchAdClockTimeline(text)
            countdown = twitchAdCountdownBegin("actual-owner")
            ignored = twitchAdCountdownSet(countdown,"actual-owner",text)
            utc = twitchAdClockUtc({epoch:1,video:1767225602#})
            view = twitchAdCountdownView(countdown,"actual-owner",utc,"playing")
            valid = mode = "valid" or mode = "crlf"
            check(view.visible = valid, "actual projected feed and presented frame alone determine visible countdown " + mode + track)
            if valid
                check(reload <> invalid, "valid projected media retains an actual clock timeline " + mode + track)
                if reload <> invalid
                    check(reload.cues.Count() = 1, "valid projected media retains one actual cue " + mode + track)
                    if reload.cues.Count() = 1 then check(reload.cues[0].Count() = 5 and reload.cues[0].startUs = 1767225601500001& and reload.cues[0].durationUs = 4250001&, "independent exact cue timing survives whole pipeline " + mode + track)
                end if
                check(view.remainingSeconds = 4, "independent 3.750002 second remaining duration rounds upward " + mode + track)
            else
                check(countdown.cues.Count() = 0, "unseen/unknown/malformed timing has no fabricated cue " + mode + track)
            end if
            check(not twitchAdCountdownView(countdown,"old-owner",utc,"playing").visible and not twitchAdCountdownView(countdown,"actual-owner",twitchAdClockUtc({epoch:0,video:1767225602#}),"playing").visible, "stale owner or unknown render epoch stays hidden " + mode + track)
            closeLiveConnection()
        end if
    end for
    check(FormatJson(pub) = initial and m.publications[key].activeRequests = 0, "canonical publication and request lease remain unchanged " + mode)
    if projection <> invalid
        entry = m.publications[key]
        changed = {cues:entry.adProjection.cues,segments:[]}
        shifted = []
        for i = 0 to entry.adProjection.segments.Count() - 1
            source = entry.adProjection.segments[i]
            item = {sequence:source.sequence,epoch:source.epoch,startUs:source.startUs,durationUs:source.durationUs,date:source.date}
            item.startUs += 1000000&
            item.date = "2026-01-01T00:00:0" + (i*2+1).ToStr() + ".000000Z"
            shifted.Push(item)
        end for
        changed.segments = shifted
        check(twitchAdClockTimelineValid(changed), "negative seal control changes a separately valid sidecar " + mode)
        entry.adProjection = changed
        m.publications[key] = entry
        response = prepareLiveResponse({track:"video"})
        check(response.data.ToAsciiString() = loopbackManifest("video",pub).ToAsciiString(), "mutated sealed sidecar cannot change playback manifest " + mode)
        closeLiveConnection()
    end if
    nativeLiveRetire(state,pub.generation)
    check(nativeLiveClose(state) and state.closed and state.assets.Count() = 0 and state.cacheBytes = 0, "actual helper retirement and final typed stop release all assets " + mode)
end sub

function ioCreate(name as string) as object
    if name = "roTimespan" then return {TotalMilliseconds:ioClock,nativeClock:m.nativeClock}
    if name = "roMessagePort" then return {}
    if name = "roFileSystem" then return {Exists:ioExists,Stat:ioStat,Delete:ioDelete,file:m.file,body:m.body,trace:m.trace}
    if name = "roUrlTransfer"
        return {SetMessagePort:ioSetPort,SetCertificatesFile:ioStringOk,EnablePeerVerification:ioBoolOk,EnableHostVerification:ioBoolOk,
            EnableEncodings:ioBoolOk,EnableResume:ioBoolOk,SetMinimumTransferRate:ioRate,SetHeaders:ioHeadersOk,SetUrl:ioSetUrl,GetIdentity:ioIdentity,
            AsyncGetToFile:ioStart,AsyncHead:ioHead,AsyncCancel:ioCancel,capture:m.capture,trace:m.trace,enabledFlag:m.liveState.adClockEnabled}
    end if
    return CreateObject(name)
end function
function ioClock() as integer
    return m.nativeClock[0]
end function
sub ioObserve(field as string, port as object)
    m.trace.Push("observe")
end sub
sub ioUnobserve(field as string)
    m.trace.Push("unobserve")
end sub
sub ioSetPort(port as object)
end sub
function ioStringOk(value as string) as boolean
    return true
end function
function ioBoolOk(value as boolean) as boolean
    return true
end function
function ioRate(rate as integer, seconds as integer) as boolean
    return true
end function
function ioHeadersOk(value as object) as boolean
    return true
end function
sub ioSetUrl(value as string)
end sub
function ioStart(path as string) as boolean
    m.capture.Push(m.enabledFlag)
    m.trace.Push("start")
    return false
end function
function ioHead() as boolean
    throw "unexpected HEAD fixture boundary"
end function
function ioCancel() as boolean
    m.trace.Push("cancel")
    return true
end function
function ioExists(path as string) as boolean
    return m.file[0]
end function
function ioStat(path as string) as object
    return {type:"file",size:m.body.Len()}
end function
function ioDelete(path as string) as boolean
    m.file[0] = false
    m.trace.Push("delete")
    return true
end function
function ioType(value as dynamic) as string
    if type(value) = "roAssociativeArray" then return value.nativeType
    return type(value)
end function
function ioRead(path as string) as string
    return m.body
end function
function ioIdentity() as string
    return "owned"
end function
function ioInt() as integer
    return 1
end function
function ioStatus() as integer
    return 200
end function
function ioHeaders() as object
    return [{"Content-Length":m.body.Len().ToStr()}]
end function
function ioWait(delay as integer, port as dynamic) as dynamic
    return invalid
end function
function isTwitchVariantSupported(variant as object) as boolean
    return true
end function
