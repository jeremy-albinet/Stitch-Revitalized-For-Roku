' On-device fmp4-demux-proxy at 127.0.0.1: /m3u8 playlists, /s single-track segments, /health.

sub init()
    m.top.functionName = "runServer"
end sub

sub runServer()
    m.port = CreateObject("roMessagePort")
    m.conns = {}
    m.xfers = {}
    m.segs = {}
    m.segs.SetModeCaseSensitive()
    m.segOrder = []
    m.trackMaps = {}
    m.trackMaps.SetModeCaseSensitive()
    m.trackMapOrder = []
    m.MAX_TRACK_MAPS = 100
    m.maps = newMapRegistry()
    m.nextFile = 0
    m.CRLF = chr(13) + chr(10)
    m.MAX_SEGS = 12
    m.TIMEOUT_MS = 30000
    m.ALLOWED_HOSTS = ["ttvnw.net", "twitch.tv", "twitchcdn.net", "cloudfront.net"]

    addr = CreateObject("roSocketAddress")
    addr.setAddress("127.0.0.1")
    addr.setPort(m.top.port)
    m.listen = CreateObject("roStreamSocket")
    m.listen.setMessagePort(m.port)
    m.listen.setReuseAddr(true)
    m.listen.setAddress(addr)
    m.listen.notifyReadable(true)
    m.listen.listen(8)
    if not m.listen.eOK()
        logLine("Could not open port " + m.top.port.toStr() + ", Enhanced streams will need the Proxy URL setting")
        m.top.control = "STOP"
        return
    end if
    logLine("Built-in splitter listening on 127.0.0.1:" + m.top.port.toStr())
    m.top.ready = true

    while true
        msg = wait(5000, m.port)
        t = type(msg)
        if t = "roSocketEvent"
            onSocketEvent(msg)
        else if t = "roUrlEvent"
            onUrlEvent(msg)
        end if
        dropStalledDownloads()
    end while
end sub

sub logLine(s as string)
    print "[demux] "; s
end sub

function newTmpFile(tag as string) as string
    m.nextFile = m.nextFile + 1
    return "tmp:/demux_" + tag + "_" + m.nextFile.toStr()
end function

' Upstream allowlist, same as fmp4-demux-proxy: http(s) on Twitch domains only.
function isAllowedUpstream(url as string) as boolean
    lower = LCase(url)
    if not startsWith(lower, "https://") and not startsWith(lower, "http://") then return false
    host = hostOf(lower)
    at = host.InStr("@")
    if at >= 0 then host = host.Mid(at + 1)
    colon = host.InStr(":")
    if colon >= 0 then host = host.Left(colon)
    for each suffix in m.ALLOWED_HOSTS
        if host = suffix or host.Right(suffix.Len() + 1) = "." + suffix then return true
    end for
    return false
end function

' ---------- sockets ----------

sub onSocketEvent(msg as object)
    id = msg.getSocketID()
    if id = m.listen.getID()
        if m.listen.isReadable()
            sock = m.listen.accept()
            if sock <> invalid
                sock.setMessagePort(m.port)
                sock.notifyReadable(true)
                c = { id: sock.getID().toStr(), sock: sock, req: "", out: invalid, offset: 0, busy: false, headOnly: false }
                m.conns[c.id] = c
                readConn(c, false)
            end if
        end if
        return
    end if

    c = m.conns[id.toStr()]
    if c = invalid then return
    if c.sock.isException()
        closeConn(c)
        return
    end if
    if c.out <> invalid
        if c.sock.isWritable() then pump(c)
        return
    end if
    if c.sock.isReadable() then readConn(c, true)
end sub

' Reads the request until the blank line that ends the headers.
sub readConn(c as object, fromEvent as boolean)
    if c.busy then return
    n = c.sock.getCountRcvBuf()
    if n <= 0
        if fromEvent then closeConn(c)
        return
    end if
    c.req = c.req + c.sock.receiveStr(n)
    if c.req.InStr(m.CRLF + m.CRLF) >= 0
        c.busy = true
        c.sock.notifyReadable(false)
        handleRequest(c)
    end if
end sub

sub handleRequest(c as object)
    lines = c.req.Split(chr(10))
    first = lines[0].Trim().Split(" ")
    if first.Count() < 2
        sendSimple(c, 400, "Bad Request")
        return
    end if
    method = UCase(first[0])
    path = first[1]
    host = ""
    for each ln in lines
        t = ln.Trim()
        if LCase(t.Left(5)) = "host:" then host = t.Mid(5).Trim()
    end for
    if host = "" then host = "127.0.0.1:" + m.top.port.toStr()

    if method <> "GET" and method <> "HEAD"
        sendSimple(c, 405, "Method Not Allowed")
        return
    end if
    c.headOnly = (method = "HEAD")
    c.base = "http://" + host
    c.q = parseQuery(path)
    route = path
    qi = route.InStr("?")
    if qi >= 0 then route = route.Left(qi)

    if route = "/health"
        body = CreateObject("roByteArray")
        body.FromAsciiString("{" + chr(34) + "status" + chr(34) + ":" + chr(34) + "ok" + chr(34) + "}")
        sendResponse(c, 200, "OK", "application/json", body)
        return
    end if

    c.upstream = queryValue(c.q, "u")
    if c.upstream = "" or not isAllowedUpstream(c.upstream)
        logLine("Refused an address that is not Twitch: " + hostOf(c.upstream))
        sendSimple(c, 400, "Bad Request")
        return
    end if

    if route = "/s"
        handleSegment(c)
    else if route = "/m3u8"
        if not startDownload(c.upstream, newTmpFile("pl"), { mode: "conn", c: c })
            sendSimple(c, 502, "Bad Gateway")
        end if
    else
        sendSimple(c, 404, "Not Found")
    end if
end sub

' ---------- downloads ----------

function startDownload(url as string, file as string, job as object) as boolean
    x = CreateObject("roUrlTransfer")
    x.SetMessagePort(m.port)
    x.SetUrl(url)
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.EnableEncodings(true)
    x.RetainBodyOnError(true)
    x.AddHeader("User-Agent", "Mozilla/5.0")
    job.xfer = x
    job.url = url
    job.file = file
    job.timer = CreateObject("roTimespan")
    m.xfers[x.GetIdentity().toStr()] = job
    if x.AsyncGetToFile(file) then return true
    m.xfers.Delete(x.GetIdentity().toStr())
    logLine("Could not start a download from " + hostOf(url))
    return false
end function

sub onUrlEvent(msg as object)
    key = msg.GetSourceIdentity().toStr()
    job = m.xfers[key]
    if job = invalid then return
    if msg.GetInt() <> 1 then return
    m.xfers.Delete(key)
    job.xfer = invalid
    code = msg.GetResponseCode()
    if code <> 200
        DeleteFile(job.file)
        logLine("Twitch gave " + code.toStr() + " " + msg.GetFailureReason() + " (" + hostOf(job.url) + ")")
        failJob(job)
        return
    end if
    if job.mode = "seg"
        entry = m.segs[job.key]
        if entry = invalid
            DeleteFile(job.file)
        else
            processPiece(job.key, entry, job.file)
        end if
    else
        onPlaylistDownloaded(job)
    end if
end sub

' Cancels downloads stuck over 30 s so the player never waits forever.
sub dropStalledDownloads()
    for each key in m.xfers.Keys()
        job = m.xfers[key]
        if job.timer.TotalMilliseconds() > m.TIMEOUT_MS
            job.xfer.AsyncCancel()
            m.xfers.Delete(key)
            DeleteFile(job.file)
            logLine("A download took over 30 seconds and was dropped")
            failJob(job)
        end if
    end for
end sub

sub failJob(job as object)
    if job.mode = "seg"
        entry = m.segs[job.key]
        if entry <> invalid then failEntry(job.key, entry)
    else
        sendSimple(job.c, 502, "Bad Gateway")
    end if
end sub

sub onPlaylistDownloaded(job as object)
    c = job.c
    body = CreateObject("roByteArray")
    body.ReadFile(job.file)
    DeleteFile(job.file)
    try
        out = rewriteManifest(body.ToAsciiString(), c.upstream, c.base, queryValue(c.q, "track"), c.q, m.maps)
    catch e
        m.maps.notes.Clear()
        logLine("Playlist rewrite failed: " + e.message)
        sendSimple(c, 502, "Bad Gateway")
        return
    end try
    for each note in m.maps.notes
        logLine(note)
    end for
    m.maps.notes.Clear()
    body = CreateObject("roByteArray")
    body.FromAsciiString(out)
    sendResponse(c, 200, "OK", "application/vnd.apple.mpegurl", body)
end sub

' ---------- segments ----------

' Audio and video request the same segment: download and split once, serve both.
sub handleSegment(c as object)
    track = queryValue(c.q, "track")
    kind = queryValue(c.q, "k")
    if track <> "video" and track <> "audio"
        sendSimple(c, 400, "Bad Request")
        return
    end if
    if kind <> "init" and kind <> "media" and kind <> "part" and kind <> "prefetch"
        sendSimple(c, 400, "Bad Request")
        return
    end if

    entry = m.segs[c.upstream]
    if entry = invalid
        mapUrl = invalid
        mapId = queryValue(c.q, "map")
        if mapId <> "" then mapUrl = m.maps.byId[mapId]
        entry = startPiece(c.upstream, (kind = "init"), mapUrl)
        if entry = invalid
            sendSimple(c, 502, "Bad Gateway")
            return
        end if
    end if

    if entry.state = "loading"
        entry.waiters.Push({ c: c, track: track })
    else
        serveEntry(c, entry, track)
    end if
end sub

' Creates a cache entry and starts its download; mapUrl is the segment's EXT-X-MAP init.
function startPiece(url as string, isInit as boolean, mapUrl as dynamic) as dynamic
    entry = { state: "loading", isInit: isInit, mapUrl: mapUrl, waiters: [], after: [], files: {}, passFile: invalid, ctype: "video/mp4" }
    m.segs[url] = entry
    m.segOrder.Push(url)
    if not startDownload(url, newTmpFile("seg"), { mode: "seg", key: url })
        m.segs.Delete(url)
        return invalid
    end if
    evictOldSegments()
    return entry
end function

sub processPiece(key as string, entry as object, file as string)
    data = CreateObject("roByteArray")
    data.ReadFile(file)
    try
        if data.Count() = 0 then throw "empty piece"
        if isMpegTs(data)
            logLine("A piece from " + hostOf(key) + " came as MPEG-TS, passed through unchanged")
            entry.passFile = file
            entry.ctype = "video/mp2t"
        else if entry.isInit
            tm = extractTrackMap(data)
            rememberTrackMap(key, tm)
            writeTrack(entry, splitInit(data, file, tm, "video"), "video")
            writeTrack(entry, splitInit(data, file, tm, "audio"), "audio")
            DeleteFile(file)
            logLine("Starter piece split (" + hostOf(key) + "). Tracks: " + FormatJson(tm))
        else
            tm = invalid
            if entry.mapUrl <> invalid
                tm = m.trackMaps[entry.mapUrl]
                if tm = invalid
                    ' Init not split yet: fetch it first, then finish this segment.
                    initEntry = ensureInitPiece(entry.mapUrl)
                    if initEntry <> invalid
                        initEntry.after.Push({ key: key, file: file })
                        logLine("A piece from " + hostOf(key) + " is waiting for its starter piece")
                        return
                    end if
                end if
            end if
            if tm = invalid
                logLine("No starter piece known for a piece from " + hostOf(key) + ", passed through unchanged")
                entry.passFile = file
            else
                writeTrack(entry, splitMedia(data, file, tm, "video"), "video")
                writeTrack(entry, splitMedia(data, file, tm, "audio"), "audio")
                DeleteFile(file)
            end if
        end if
    catch e
        DeleteFile(file)
        logLine("Split failed: " + e.message)
        failEntry(key, entry)
        return
    end try

    entry.state = "ready"
    for each w in entry.waiters
        serveEntry(w.c, entry, w.track)
    end for
    entry.waiters = []

    ' Finish segments that were waiting on this init.
    waiting = entry.after
    entry.after = []
    for each a in waiting
        e2 = m.segs[a.key]
        if e2 = invalid
            DeleteFile(a.file)
        else
            processPiece(a.key, e2, a.file)
        end if
    end for
end sub

' Returns the loading init entry, starting its download if needed, or invalid.
' A ready entry with no track map (fetched as media, or its map was evicted) is
' fetched again; an init that came back as MPEG-TS is left as is.
function ensureInitPiece(url as string) as dynamic
    e = m.segs[url]
    if e <> invalid
        if e.state = "loading"
            if e.isInit then return e
            return invalid
        end if
        if e.isInit and e.passFile <> invalid then return invalid
        dropPiece(url)
    end if
    logLine("Fetching a starter piece the player has not asked for (" + hostOf(url) + ")")
    return startPiece(url, true, invalid)
end function

sub rememberTrackMap(url as string, tm as object)
    if m.trackMaps[url] = invalid then m.trackMapOrder.Push(url)
    m.trackMaps[url] = tm
    if m.trackMapOrder.Count() > m.MAX_TRACK_MAPS then m.trackMaps.Delete(m.trackMapOrder.Shift())
end sub

sub writeTrack(entry as object, ba as object, track as string)
    path = newTmpFile("sp")
    if not ba.WriteFile(path) then throw "could not write " + track + " piece"
    entry.files[track] = path
end sub

sub serveEntry(c as object, entry as object, track as string)
    path = entry.passFile
    if path = invalid then path = entry.files[track]
    body = CreateObject("roByteArray")
    body.ReadFile(path)
    sendResponse(c, 200, "OK", entry.ctype, body)
end sub

sub failEntry(key as string, entry as object)
    m.segs.Delete(key)
    for each w in entry.waiters
        sendSimple(w.c, 502, "Bad Gateway")
    end for
    entry.waiters = []
    waiting = entry.after
    entry.after = []
    for each a in waiting
        DeleteFile(a.file)
        e2 = m.segs[a.key]
        if e2 <> invalid then failEntry(a.key, e2)
    end for
end sub

' Keeps the newest segments; never drops one still downloading.
sub evictOldSegments()
    while m.segOrder.Count() > m.MAX_SEGS
        key = m.segOrder[0]
        e = m.segs[key]
        if e <> invalid and e.state = "loading" then exit while
        dropPiece(key)
    end while
end sub

' Deletes a cached piece and its files, and forgets its place in the order.
sub dropPiece(key as string)
    for i = m.segOrder.Count() - 1 to 0 step -1
        if m.segOrder[i] = key then m.segOrder.Delete(i)
    end for
    e = m.segs[key]
    if e = invalid then return
    if e.passFile <> invalid then DeleteFile(e.passFile)
    for each t in e.files
        DeleteFile(e.files[t])
    end for
    m.segs.Delete(key)
end sub

' ---------- responses ----------

sub sendSimple(c as object, code as integer, reason as string)
    body = CreateObject("roByteArray")
    body.FromAsciiString(reason)
    sendResponse(c, code, reason, "text/plain", body)
end sub

sub sendResponse(c as object, code as integer, reason as string, ctype as string, body as object)
    hdr = "HTTP/1.1 " + code.toStr() + " " + reason + m.CRLF
    hdr = hdr + "Content-Type: " + ctype + m.CRLF
    hdr = hdr + "Content-Length: " + body.Count().toStr() + m.CRLF
    hdr = hdr + "Cache-Control: no-store" + m.CRLF
    hdr = hdr + "Connection: close" + m.CRLF + m.CRLF
    out = CreateObject("roByteArray")
    out.FromAsciiString(hdr)
    if not c.headOnly then out.Append(body)
    c.out = out
    c.offset = 0
    pump(c)
end sub

' Sends what the socket accepts, then waits for writable.
sub pump(c as object)
    total = c.out.Count()
    while c.offset < total
        chunk = total - c.offset
        if chunk > 65536 then chunk = 65536
        n = c.sock.send(c.out, c.offset, chunk)
        if n > 0
            c.offset = c.offset + n
        else if n = 0 or c.sock.eWouldBlock()
            c.sock.notifyWritable(true)
            return
        else
            closeConn(c)
            return
        end if
    end while
    closeConn(c)
end sub

sub closeConn(c as object)
    c.sock.notifyReadable(false)
    c.sock.notifyWritable(false)
    c.sock.close()
    m.conns.Delete(c.id)
end sub
