sub main()
    m.checks = 0
    m.failures = 0
    uri = "https://media4.giphy.com/media/joSNxeswxuc74Juo8X/giphy.gif?cid=095d7a5dzizsiwgabonagkmigggv8v1spfai91ac3x0dsiy0&ep=v1_gifs_trending&rid=giphy.gif&ct=g"
    fs = createObject("roFileSystem")
    for each mode in ["valid", "official", "head-oversize", "head-redirect", "get-redirect", "get-truncated", "get-oversize", "get-webp", "final-stat-invalid", "pending-stat-invalid", "cancel", "shared-deadline", "stop-before-start", "invalid-uri"]
        state = getGlobalAA()
        state.mode = mode
        state.url = ""
        state.heads = 0
        state.gets = 0
        state.cancels = 0
        state.phase = ""
        state.nowMs = 0
        state.stats = 0
        path = "tmp:/stitch-emote-gif-" + mode + "/emote.gif"
        request = { generation: 123, path: path, uri: uri, paths: [] }
        if mode = "invalid-uri" then request.uri = "https://127.0.0.1/media/a/giphy.gif"
        m.top = { request: request, stopRequested: mode = "stop-before-start", response: invalid }
        state.task = m.top
        fetchAnimation()
        response = m.top.response
        admitted = mode = "valid" or mode = "official" or mode = "pending-stat-invalid"
        check(response <> invalid and (response.info <> invalid) = admitted, "Task GIF admission: " + mode)
        if admitted
            check(response.path = path and response.uri = uri and response.generation = 123, "exact URI, path, generation ownership: " + mode)
            check(response.info.format = "gif" and response.info.renderer = "gif-atlas" and response.info.sourceBytes = fixtureLength(), "GIF conversion keeps exact source size: " + mode)
            check(response.info.loadWidth <= 64 and response.info.loadHeight <= 64 and not fs.exists(path) and fs.exists(response.info.renderPath), "only the admitted atlas is retained: " + mode)
            check(response.removed.count() = 0 and response.cleanupOk, "owned final file is not deleted early: " + mode)
        else
            check(response.cleanupOk and response.removed.count() = 1 and not fs.exists(chatAnimationDirectory(path)), "rejected/canceled file and directory are removed: " + mode)
        end if
        if mode = "head-oversize" or mode = "head-redirect"
            check(state.heads = 1 and state.gets = 0, "failed HEAD never starts GET: " + mode)
        else if mode = "stop-before-start" or mode = "invalid-uri"
            check(state.heads = 0 and state.gets = 0 and state.url = "", "canceled or unsafe GIF starts no request: " + mode)
        else
            check(state.heads = 1 and state.gets = 1 and state.url = uri, "one HEAD/GET uses supplied complete URL unchanged: " + mode)
        end if
        if mode <> "stop-before-start" and mode <> "invalid-uri" then check(state.cancels = 1, "producer canceled/released once: " + mode)
        if mode = "shared-deadline" then check(state.nowMs = 8000, "HEAD and GET share eight seconds")
        if admitted
            m.top = { request: { generation: 124, path: "", uri: "", paths: [path] }, response: invalid, stopRequested: false }
            fetchAnimation()
            check(m.top.response.cleanupOk and m.top.response.removed.count() = 1 and not fs.exists(chatAnimationDirectory(path)), "Task cleanup acknowledges .gif and directory removal: " + mode)
        end if
    end for
    for each name in ["emote.webp", "emote.gif"]
        check(chatAnimationPath("tmp:/stitch-emote-owned/" + name), "allowed owned path " + name)
    end for
    for each path in ["tmp:/other/emote.gif", "tmp:/stitch-emote-../emote.gif", "tmp:/stitch-emote-a/b/emote.gif", "tmp:/stitch-emote-a\b/emote.gif", "tmp:/stitch-emote-/emote.gif", "tmp:/stitch-emote-a/emote.gif/extra", "tmp:/stitch-emote-a/emote.png", "pkg:/stitch-emote-a/emote.gif"]
        check(not chatAnimationPath(path), "unsafe deletion path rejected: " + path)
    end for
    if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
end sub

function fixtureCreateObject(kind as string) as object
    if kind = "roMessagePort" then return {}
    if kind = "roTimespan" then return { totalMilliseconds: fixtureMilliseconds }
    if kind = "roUrlTransfer" then return {
        setMessagePort: fixtureSetObject, setCertificatesFile: fixtureSetString,
        initClientCertificates: fixtureNothing, setUrl: fixtureSetUrl,
        asyncHead: fixtureHead, asyncGetToFile: fixtureStart,
        asyncCancel: fixtureCancel, getIdentity: fixtureIdentity
    }
    return createObject(kind)
end function

function fixtureLength() as integer
    source = "tiny.gif"
    if getGlobalAA().mode = "official" then source = "twitch-official.gif"
    if getGlobalAA().mode = "get-webp" then source = "petpet.webp"
    return createObject("roFileSystem").stat("pkg:/" + source).size
end function

function fixtureHead() as boolean
    state = getGlobalAA()
    state.phase = "head"
    state.heads++
    return true
end function

function fixtureStart(path as string) as boolean
    state = getGlobalAA()
    state.phase = "get"
    state.gets++
    bytes = createObject("roByteArray")
    source = "tiny.gif"
    if state.mode = "official" then source = "twitch-official.gif"
    if state.mode = "get-webp" then source = "petpet.webp"
    bytes.readFile("pkg:/" + source)
    if state.mode = "get-truncated" then bytes.pop()
    if state.mode = "get-oversize" then bytes.push(0)
    return bytes.writeFile(path)
end function

function fixtureStat(fs as object, path as string) as dynamic
    state = getGlobalAA()
    state.stats++
    if state.mode = "pending-stat-invalid" and state.stats = 1 then return {}
    if state.mode = "final-stat-invalid" and state.stats = 2 then return { size: "string-is-not-size" }
    return fs.stat(path)
end function

function fixtureWait(duration as integer, port as object) as dynamic
    state = getGlobalAA()
    state.nowMs += duration
    if state.mode = "shared-deadline"
        if state.phase = "head" and state.nowMs < 7950 then return invalid
        if state.phase = "get" then return invalid
    end if
    if state.mode = "cancel" and state.phase = "get" then state.task.stopRequested = true
    if state.mode = "pending-stat-invalid" and state.nowMs = 100 then return invalid
    return { getSourceIdentity: fixtureIdentity, getResponseCode: fixtureCode, getResponseHeadersArray: fixtureHeaders }
end function

function fixtureHeaders() as object
    state = getGlobalAA()
    length = fixtureLength()
    if state.mode = "head-oversize" and state.phase = "head" then length = 1048577
    headers = [{ "Content-Length": length.toStr() }, { "Content-Type": "image/gif" }]
    if state.mode = state.phase + "-redirect" then headers.push({ "Location": "http://127.0.0.1/private" })
    return headers
end function

function fixtureCode() as integer
    return 200
end function

function fixtureIsUrlEvent(event as dynamic) as boolean
    return event <> invalid
end function

function fixtureIdentity() as integer
    return 42
end function

function fixtureMilliseconds() as integer
    return getGlobalAA().nowMs
end function

sub fixtureCancel()
    getGlobalAA().cancels++
end sub

sub fixtureSetUrl(uri as string)
    getGlobalAA().url = uri
end sub

sub fixtureSetObject(value as object)
end sub

sub fixtureSetString(value as string)
end sub

sub fixtureNothing()
end sub

sub check(ok as boolean, label as string)
    m.checks++
    if not ok
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
