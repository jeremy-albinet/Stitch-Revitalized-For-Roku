sub main()
m.assertions = 0
m.failures = 0
modes = ["valid", "valid-catjam", "valid-sourpls", "limit", "head-oversize", "head-missing", "head-zero", "head-negative", "head-decimal", "head-exponent", "head-junk", "head-huge", "head-duplicate", "head-encoded", "head-chunked", "head-nonstring", "head-invalid-array", "head-http-error", "head-start-failed", "head-timeout", "head-cancel", "head-late-event", "head-wrong-event", "get-empty", "get-oversize", "get-truncated", "get-http-error", "get-timeout", "get-start-failed", "get-cancel", "get-wrong-event", "get-missing-length", "get-changed-length", "get-changed-body", "get-duplicate", "get-encoded", "get-chunked", "shared-deadline", "get-late-event", "stop-before-start"]
for each metadata in ["stat-missing", "stat-empty", "size-invalid", "size-string", "size-bool", "size-object", "size-array"]
    modes.push("pending-" + metadata)
    modes.push("final-" + metadata)
end for
for each metadata in ["stat-missing", "stat-empty"]
    modes.push("timeout-" + metadata)
    modes.push("cancel-" + metadata)
end for
modes.push("pending-stat-oversize")
for each mode in modes
    state = getGlobalAA()
    state.mode = mode
    state.nowMs = 0
    state.canceled = 0
    state.waits = 0
    state.getWaits = 0
    state.getEvents = 0
    state.stats = 0
    state.statGaps = 0
    state.heads = 0
    state.gets = 0
    state.writes = 0
    state.phase = ""
    state.headDoneMs = 0
    state.peakBytes = 0
    m.top = { request: { path: "tmp:/stitch-emote-asset-" + mode + "/emote.webp", paths: [], uri: "https://cdn.example/emote.webp", generation: 7 }, stopRequested: mode = "stop-before-start", response: invalid }
    state.task = m.top
    fetchAnimation()
    fs = createObject("roFileSystem")
    directory = m.top.request.path.left(m.top.request.path.len() - 11)
    if mode = "stop-before-start"
        check(state.heads = 0 and state.gets = 0 and state.writes = 0, "already canceled Task starts no network or writer")
    else
        check(state.canceled = 1, "transfer canceled/released for " + mode)
    end if
    if mode = "valid" or mode = "valid-catjam" or mode = "valid-sourpls" or mode = "limit" or (mode.left(8) = "pending-" and mode <> "pending-stat-oversize")
        check(m.top.response <> invalid and m.top.response.info <> invalid, "admitted download is published: " + mode)
        if m.top.response.info <> invalid then check(m.top.response.path = m.top.request.path and m.top.response.generation = 7 and m.top.response.info.bytes = fixtureLength(), "response retains exact request ownership and parsed actual size: " + mode)
        check(m.top.response.removed.count() = 0 and fs.exists(m.top.request.path), "completed admitted file remains owned by Chat: " + mode)
        check(state.heads = 1 and state.gets = 1 and state.writes = 1, "one HEAD precedes the only GET writer: " + mode)
        fs.delete(m.top.request.path)
        fs.delete(directory)
    else
        check(m.top.response <> invalid and m.top.response.info = invalid, "rejected transfer publishes static fallback for " + mode)
        check(m.top.response.removed.count() = 1 and not fs.exists(directory), "rejected partial/completed file and directory deleted for " + mode)
    end if
    if mode.left(5) = "head-"
        check(state.gets = 0 and state.writes = 0 and state.peakBytes = 0, "invalid/oversized HEAD produces ZERO GETs/files: " + mode)
    end if
    if mode.instr("timeout") >= 0 or mode.instr("wrong-event") >= 0 or mode.instr("late-event") >= 0 or mode = "shared-deadline"
        check(state.nowMs = 8000, "HEAD and GET share the inclusive eight-second deadline: " + mode)
    end if
    if mode = "shared-deadline"
        check(state.headDoneMs = 7950 and state.gets = 1, "GET receives only the remaining HEAD deadline")
    end if
    if mode = "get-oversize"
        check(state.peakBytes = 2097152 and m.top.response.info = invalid, "lying GET can overshoot before polling but is never admitted or decoded")
        check(state.getWaits = 1 and state.getEvents = 0 and state.nowMs = 100, "oversized pending file is rejected before URL completion")
    end if
    if mode.left(8) = "pending-"
        check(state.statGaps = 1 and state.getWaits = 2, "pending metadata gap is polled before final real stat: " + mode)
    end if
    if mode.left(6) = "final-"
        check(state.statGaps = 1 and state.getEvents = 1 and state.getWaits = 1, "unusable metadata is injected only at final admission: " + mode)
    end if
    if mode.left(8) = "timeout-"
        check(state.statGaps > 1 and state.getEvents = 0, "missing metadata continues bounded polling without URL completion: " + mode)
    end if
    if mode.left(7) = "cancel-"
        check(state.statGaps > 0 and state.getWaits = 2 and state.getEvents = 1 and state.nowMs = 150, "cancellation after metadata gap beats racing URL completion: " + mode)
    end if
    if mode = "pending-stat-oversize"
        check(state.peakBytes = 2097152 and state.getEvents = 0 and state.nowMs = 150, "real oversized file after metadata gap is rejected without URL completion")
    end if
end for
if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

function fixtureCreateObject(kind as string) as object
    if kind = "roMessagePort" then return {}
    if kind = "roTimespan" then return { totalMilliseconds: fixtureMilliseconds }
    if kind = "roUrlTransfer" then return {
        setMessagePort: fixtureSetObject, setCertificatesFile: fixtureSetString,
        initClientCertificates: fixtureNothing, setUrl: fixtureSetString,
        asyncHead: fixtureHead, asyncGetToFile: fixtureStart,
        asyncCancel: fixtureCancel, getIdentity: fixtureIdentity
    }
    return createObject(kind)
end function

function fixtureHead() as boolean
    state = getGlobalAA()
    state.phase = "head"
    state.heads++
    return state.mode <> "head-start-failed"
end function

function fixtureLength() as integer
    mode = getGlobalAA().mode
    if mode = "limit" then return 1048576
    if mode = "valid-catjam" then return createObject("roFileSystem").stat("pkg:/catjam.webp").size
    if mode = "valid-sourpls" then return createObject("roFileSystem").stat("pkg:/sourpls.webp").size
    return 3842
end function

function fixtureStart(path as string) as boolean
    state = getGlobalAA()
    state.phase = "get"
    state.gets++
    if state.mode = "get-start-failed" then return false
    ' Real file operations and admission execute; HTTP/clock and deliberate stat gaps are boundaries.
    source = "petpet.webp"
    if state.mode = "valid-catjam" then source = "catjam.webp"
    if state.mode = "valid-sourpls" then source = "sourpls.webp"
    if state.mode = "limit" then source = "one-mib.webp"
    if state.mode = "get-oversize" or state.mode = "pending-stat-oversize" then source = "oversize.webp"
    bytes = createObject("roByteArray")
    bytes.readFile("pkg:/" + source)
    if state.mode = "get-truncated" or state.mode = "get-changed-body" then bytes.pop()
    if state.mode = "get-empty" then bytes.clear()
    state.peakBytes = bytes.count()
    state.writes++
    return bytes.writeFile(path)
end function

' Only this stat boundary models the native pending-file metadata gap. Normal
' polling and completion still use actual engine filesystem stat, not native proof.
function fixtureStat(fs as object, path as string) as dynamic
    state = getGlobalAA()
    mode = state.mode
    state.stats++
    missing = mode.left(8) = "pending-" and state.getWaits = 1
    missing = missing or (mode.left(6) = "final-" and state.stats = 2)
    missing = missing or mode.left(8) = "timeout-" or mode.left(7) = "cancel-"
    if missing
        state.statGaps++
        if mode.instr("stat-empty") >= 0 or mode = "pending-stat-oversize" then return {}
        if mode.instr("size-invalid") >= 0 then return { size: invalid }
        if mode.instr("size-string") >= 0 then return { size: "3842" }
        if mode.instr("size-bool") >= 0 then return { size: true }
        if mode.instr("size-object") >= 0 then return { size: {} }
        if mode.instr("size-array") >= 0 then return { size: [] }
        return invalid
    end if
    return fs.stat(path)
end function

function fixtureWait(duration as integer, port as object) as dynamic
    state = getGlobalAA()
    state.nowMs += duration
    state.waits++
    if state.phase = "get"
        state.getWaits++
        if state.mode.left(8) = "pending-" and state.getWaits = 1 then return invalid
        if state.mode.left(8) = "timeout-" or state.mode = "get-oversize" or state.mode = "pending-stat-oversize" then return invalid
        if state.mode.left(7) = "cancel-"
            if state.getWaits = 1 then return invalid
            state.task.stopRequested = true
        end if
    end if
    if state.mode = state.phase + "-cancel"
        state.task.stopRequested = true
        ' A completed event racing cancellation must still be rejected.
    end if
    if state.mode = state.phase + "-timeout" then return invalid
    if state.mode = state.phase + "-late-event" and state.nowMs < 8000 then return invalid
    if state.mode = "shared-deadline"
        if state.phase = "head" and state.nowMs < 7950 then return invalid
        if state.phase = "get" then return invalid
    end if
    if state.phase = "head" then state.headDoneMs = state.nowMs
    if state.phase = "get" then state.getEvents++
    return { getSourceIdentity: fixtureSourceIdentity, getResponseCode: fixtureResponseCode, getResponseHeadersArray: fixtureHeaders }
end function

function fixtureHeaders() as dynamic
    state = getGlobalAA()
    length = fixtureLength().toStr()
    if state.mode = "head-oversize" then length = "2097152"
    if state.mode = state.phase + "-missing" or state.mode = "get-missing-length" then return []
    if state.mode = "head-zero" then length = "0"
    if state.mode = "head-negative" then length = "-1"
    if state.mode = "head-decimal" then length = "3842.0"
    if state.mode = "head-exponent" then length = "3.842e3"
    if state.mode = "head-junk" then length = "3842junk"
    if state.mode = "head-huge" then length = "18446744073709551616"
    if state.mode = "head-nonstring" then return [{ "Content-Length": 3842 }]
    if state.mode = "head-invalid-array" then return invalid
    if state.mode = "get-changed-length" and state.phase = "get" then length = "3841"
    headers = [{ "cOnTeNt-LeNgTh": " " + length + chr(9) }]
    if state.mode = state.phase + "-duplicate" then headers.push({ "Content-Length": length })
    if state.mode = state.phase + "-encoded" then headers.push({ "Content-Encoding": "gzip" })
    if state.mode = state.phase + "-chunked" then headers.push({ "Transfer-Encoding": "chunked" })
    return headers
end function

function fixtureIsUrlEvent(event as dynamic) as boolean
    return event <> invalid
end function

function fixtureIdentity() as integer
    return 42
end function

function fixtureSourceIdentity() as integer
    state = getGlobalAA()
    if state.mode = state.phase + "-wrong-event" then return 99
    return 42
end function

function fixtureResponseCode() as integer
    state = getGlobalAA()
    if state.mode = state.phase + "-http-error" then return 404
    return 200
end function

sub fixtureCancel()
    getGlobalAA().canceled++
end sub

function fixtureMilliseconds() as integer
    return getGlobalAA().nowMs
end function

sub fixtureSetObject(value as object)
end sub
sub fixtureSetString(value as string)
end sub
sub fixtureNothing()
end sub

sub check(ok as boolean, message as string)
    m.assertions++
    if not ok
        m.failures++
        print "CHAT_ANIMATION_FAIL: " + message
    end if
end sub
