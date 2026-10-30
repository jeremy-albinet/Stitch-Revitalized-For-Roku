' Current production Fetch/Core bodies with native transfer/event boundaries only.
sub checkTF(ok as boolean, message as string)
    if not ok then throw "fetch-timeout-fixture: " + message
    m.assertions += 1
end sub

function stateTF(phase as string) as object
    checkTF(nativeLiveInputCleanup(), "fresh fixture staging file")
    m.io = [0, 0, 0, true]
    m.top = { stopRequested: false }
    state = nativeLiveCreate("https://cdn.example.invalid/live.m3u8", 0&, 0, invalid, phase = "get")
    state.adClockEnabled = false
    nlStart(state, nlIntent(state, 0&), phase, invalid, 0&)
    checkTF(state.op.deadline = 6000&, "original six-second deadline retained")
    return state
end function

sub stageTF(state as object, text = "partial" as string)
    if state.op.phase = "get"
        checkTF(WriteAsciiFile(nlInputPath(), text), "write real staging file")
        checkTF(state.ownInputFile and CreateObject("roFileSystem").Exists(nlInputPath()), "GET owns real staging file")
    end if
end sub

function eventTF(identity as dynamic, length = 0 as integer) as object
    return { identity: identity, length: length, GetSourceIdentity: tfIdentity, GetInt: tfOne, GetResponseCode: tfStatus, GetResponseHeadersArray: tfHeaders }
end function

function expireTF(state as object, nowMs as dynamic, eventFirst as boolean) as object
    old = state.op
    stageTF(state)
    oldEvent = eventTF(old.identity)
    oldEvent.GetInt = tfUnexpected ' Overdue responses cannot be parsed or accepted.
    if eventFirst
        checkTF(nativeLiveHandleUrlEvent(state, oldEvent, nowMs), "matching overdue event is consumed")
    else
        unused = nativeLiveTick(state, invalid, nowMs)
    end if
    checkTF(state.phase = "playlist" and state.error = "" and state.op = invalid, "first overdue dispatch keeps retry intent")
    checkTF(state.timedOutUrl = old.url and state.transfers = 1, "timeout preserves one same URL retry")
    checkTF(m.io[1] = 1, "timeout cancels exactly one retained transfer")
    checkTF(not state.ownInputFile and not CreateObject("roFileSystem").Exists(nlInputPath()), "timeout deletes owned staging file")
    if old.phase = "get" then checkTF(m.io[2] = 1, "cancellation precedes owned file cleanup")
    if not eventFirst then checkTF(not nativeLiveHandleUrlEvent(state, oldEvent, nowMs), "late event after Tick timeout is ignored")
    unused = nativeLiveTick(state, invalid, nowMs)
    checkTF(state.op <> invalid and state.op.identity <> old.identity and state.transfers = 2, "next Tick starts one fresh transfer")
    checkTF(state.op.url = old.url and state.op.kind = old.kind and state.op.limit = old.limit and state.op.phase = old.phase, "retry retains exact URL and input intent")
    checkTF(state.op.deadline = nowMs + 6000&, "retry retains original deadline duration")
    checkTF(not nativeLiveHandleUrlEvent(state, oldEvent, state.op.deadline + 1&), "late old identity cannot expire retry")
    checkTF(state.phase = "playlist" and state.op <> invalid and state.lastNow = nowMs and m.io[1] = 1, "late old event leaves retry clock and ownership untouched")
    return oldEvent
end function

function playlistTF() as string
    nl = Chr(10)
    return "#EXTM3U" + nl + "#EXT-X-TARGETDURATION:2" + nl + "#EXT-X-MEDIA-SEQUENCE:10" + nl + "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34) + nl + "#EXTINF:2.000000," + nl + "10.m4s" + nl + "#EXTINF:2.000000," + nl + "11.m4s" + nl + "#EXTINF:2.000000," + nl + "12.m4s" + nl
end function

sub headTF(state as object, text as string, nowMs as dynamic)
    identity = state.op.identity
    checkTF(nativeLiveHandleUrlEvent(state, eventTF(identity, text.Len()), nowMs), "retry HEAD completion consumed")
    checkTF(state.phase = "playlist" and state.op <> invalid and state.op.phase = "get" and state.op.identity <> identity, "successful retry HEAD starts fresh GET")
    checkTF(state.timedOutUrl = state.op.url, "HEAD completion retains same URL retry cap")
    checkTF(not nativeLiveHandleUrlEvent(state, eventTF(identity), nowMs), "late retry HEAD identity is ignored")
end sub

sub successTF(phase as string, nowMs as dynamic, eventFirst as boolean)
    state = stateTF(phase)
    old = expireTF(state, nowMs, eventFirst)
    text = playlistTF()
    if phase = "head" then headTF(state, text, nowMs + 10&)
    stageTF(state, text)
    checkTF(nativeLiveHandleUrlEvent(state, eventTF(state.op.identity, text.Len()), nowMs + 20&), "retry GET completion consumed")
    checkTF(state.phase = "init" and state.playlistCount = 1 and state.window.segments.Count() = 3, "successful retry reaches actual Core playlist acceptance")
    checkTF(state.op = invalid and not state.ownInputFile and not CreateObject("roFileSystem").Exists(nlInputPath()), "successful retry deletes completed input")
    checkTF(state.timedOutUrl = "" and m.io[1] = 1, "successful GET resets retry cap without another cancel")
    checkTF(not nativeLiveHandleUrlEvent(state, old, nowMs + 30&), "late first event ignored after successful retry")
    checkTF(nativeLiveClose(state), "successful retry closes cleanly")
end sub

sub secondTF(phase as string, nowMs as dynamic, eventFirst as boolean, completeHead = false as boolean)
    state = stateTF(phase)
    old = expireTF(state, nowMs, eventFirst)
    if completeHead then headTF(state, playlistTF(), nowMs + 10&)
    stageTF(state)
    identity = state.op.identity
    overdue = state.op.deadline + nowMs - 6000&
    if eventFirst
        checkTF(nativeLiveHandleUrlEvent(state, eventTF(identity), overdue), "second overdue event consumed")
    else
        unused = nativeLiveTick(state, invalid, overdue)
        checkTF(not nativeLiveHandleUrlEvent(state, eventTF(identity), overdue), "second event ignored after Tick abort")
    end if
    checkTF(state.phase = "failed" and state.error = "native-live: upstream operation deadline", "second timeout fails closed")
    checkTF(state.op = invalid and not state.ownInputFile and not CreateObject("roFileSystem").Exists(nlInputPath()) and m.io[1] = 2, "second timeout cancels and deletes staging")
    transfers = state.transfers
    unused = nativeLiveTick(state, invalid, overdue + 1&)
    checkTF(state.phase = "failed" and state.op = invalid and state.transfers = transfers, "no third transfer after second timeout")
    checkTF(not nativeLiveHandleUrlEvent(state, old, overdue + 1&), "late first event ignored after fatal timeout")
    checkTF(nativeLiveClose(state), "fatal timeout closes cleanly")
end sub

sub cancelFailureTF(eventFirst as boolean)
    state = stateTF("get")
    stageTF(state)
    m.io[3] = false
    if eventFirst
        checkTF(nativeLiveHandleUrlEvent(state, eventTF(state.op.identity), 6000&), "overdue cancellation failure event consumed")
    else
        unused = nativeLiveTick(state, invalid, 6000&)
    end if
    checkTF(state.phase = "failed" and state.error = "native-live: cancellation or input cleanup failed", "cancellation refusal fails closed")
    checkTF(state.op = invalid and not state.ownInputFile and not CreateObject("roFileSystem").Exists(nlInputPath()) and m.io[1] = 1, "cancellation refusal still cleans real staging input")
    checkTF(nativeLiveClose(state), "cancellation refusal closes cleanly")
end sub

function tfTransfer() as object
    m.io[0] += 1
    return { io: m.io, identity: m.io[0], SetMessagePort: tfPort, GetMessagePort: tfGetPort, SetCertificatesFile: tfString, EnablePeerVerification: tfBool, EnableHostVerification: tfBool, EnableEncodings: tfBool, EnableResume: tfBool, SetMinimumTransferRate: tfRate, SetHeaders: tfSetHeaders, SetUrl: tfUrl, GetIdentity: tfIdentity, AsyncGetToFile: tfString, AsyncHead: tfOne, AsyncCancel: tfCancel }
end function

sub tfPort(port as dynamic)
end sub

function tfGetPort() as dynamic
    return invalid
end function

sub tfUrl(url as string)
end sub

function tfString(value as string) as boolean
    return true
end function

function tfBool(value as boolean) as boolean
    return true
end function

function tfRate(rate as integer, seconds as integer) as boolean
    return rate = 1 and seconds = 2
end function

function tfSetHeaders(headers as object) as boolean
    return headers["Accept-Encoding"] = "identity"
end function

function tfIdentity() as dynamic
    return m.identity
end function

function tfCancel() as boolean
    m.io[1] += 1
    if CreateObject("roFileSystem").Exists(nlInputPath()) then m.io[2] += 1
    return m.io[3]
end function

function tfEventType(event as object) as string
    return "roUrlEvent"
end function

function tfOne() as integer
    return 1
end function

function tfUnexpected() as integer
    throw "fetch-timeout-fixture: overdue event body inspected"
end function

function tfStatus() as integer
    return 200
end function

function tfHeaders() as object
    return [{"Content-Length": m.length.ToStr()}]
end function

function twitchAdClockBoolean(value as dynamic) as boolean
    return false
end function

sub main()
    m.assertions = 0
    try
        for each phase in ["get", "head"]
            for each nowMs in [6000&, 6001&]
                for each eventFirst in [true, false]
                    successTF(phase, nowMs, eventFirst)
                    secondTF(phase, nowMs, eventFirst)
                end for
            end for
        end for
        secondTF("head", 6000&, true, true)
        secondTF("head", 6001&, false, true)
        cancelFailureTF(true)
        cancelFailureTF(false)
        print "STITCH_FETCH_TIMEOUT_PASS: __MARKER__ "; FormatJson({ assertions: m.assertions, failures: 0 })
    catch e
        print "STITCH_FETCH_TIMEOUT_FAIL: "; e.message
    end try
end sub
