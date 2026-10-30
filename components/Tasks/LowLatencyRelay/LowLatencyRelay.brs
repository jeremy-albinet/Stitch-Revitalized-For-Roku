' Serves Twitch live playlists trimmed to their newest segments on a loopback
' port (see lowLatencyPlaylist.brs). The Video still fetches segments directly.
sub init()
    m.top.functionName = "runRelay"
end sub

sub runRelay()
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("stopRequested", m.port)
    m.state = { anchor: -1& }
    m.variants = invalid
    m.masterText = ""
    m.mediaUrl = ""
    m.lastGood = {}
    m.failures = {}
    m.fetches = {}
    m.listener = invalid
    try
        ' An unsupported source is refused before advertising; it plays directly.
        if relayPrepare()
            listenPort = relayListen()
            if listenPort = 0
                m.top.status = { failure: "listen_failed" }
            else
                m.top.status = { url: "http://127.0.0.1:" + listenPort.ToStr() + "/live.m3u8" }
                while not m.top.stopRequested
                    event = wait(250, m.port)
                    if type(event) = "roUrlEvent" then relayFetched(event)
                    relayExpire()
                    while not m.top.stopRequested and m.listener.IsReadable()
                        connection = m.listener.Accept()
                        if connection = invalid then exit while
                        relayAccept(connection)
                    end while
                end while
            end if
        end if
    catch error
        m.top.status = { failure: "relay_exception" }
    end try
    for each id in m.fetches
        m.fetches[id].transfer.AsyncCancel()
        for each client in m.fetches[id].clients
            relayDisconnect(client)
        end for
    end for
    m.fetches = {}
    if m.listener <> invalid
        m.listener.NotifyReadable(false)
        m.listener.Close()
        m.listener = invalid
    end if
end sub

function relayPrepare() as boolean
    source = m.top.sourceUrl
    text = relayFetch(source)
    if text = invalid
        m.top.status = { failure: "source_unavailable" }
        return false
    end if
    if text.InStr("#EXT-X-STREAM-INF:") >= 0
        master = lowLatencyMaster(text, source)
        if master <> invalid
            m.variants = master.variants
            m.masterText = master.text
            return true
        end if
    else if lowLatencyMedia(text, { anchor: -1& }, m.top.startCount, m.top.maxCount) <> invalid
        m.mediaUrl = source
        return true
    end if
    m.top.status = { failure: "unsupported_playlist" }
    return false
end function

' A closed relay's port can linger briefly, so a few neighbours are tried.
function relayListen() as integer
    for listenPort = 49380 to 49389
        address = CreateObject("roSocketAddress")
        listener = CreateObject("roStreamSocket")
        if address.SetAddress("127.0.0.1:" + listenPort.ToStr()) and listener <> invalid
            listener.SetMessagePort(m.port)
            ' Reuses a closed relay's lingering port; an active listener still refuses the bind.
            listener.SetReuseAddr(true)
            if listener.SetAddress(address) and relayOnLoopback(listener.GetAddress(), listenPort)
                listener.NotifyReadable(true)
                if listener.Listen(4) and listener.IsListening()
                    m.listener = listener
                    return listenPort
                end if
            end if
            listener.Close()
        end if
    end for
    return 0
end function

' Playlists carry signed segment URLs, so only an exact loopback bind serves them.
function relayOnLoopback(bound as dynamic, listenPort as integer) as boolean
    if bound = invalid then return false
    return loopbackExactAddress(bound.GetAddress(), bound.GetPort(), listenPort)
end function

' Upstream refreshes run asynchronously, so one slow fetch does not hold the
' other client's request; requests for a path already being fetched share it.
sub relayAccept(connection as object)
    port = CreateObject("roMessagePort")
    connection.SetMessagePort(port)
    connection.NotifyReadable(true)
    request = relayReadRequest(connection, port)
    if request = invalid
        relayDisconnect({ connection: connection })
        return
    end if
    client = { connection: connection, port: port, headOnly: request.method = "HEAD" }
    if request.path = "/live.m3u8" and m.masterText <> ""
        relayRespond(client, "200 OK", m.masterText)
        return
    end if
    url = ""
    if request.path = "/live.m3u8"
        url = m.mediaUrl
    else if m.variants <> invalid and request.path.Left(3) = "/v/" and request.path.Right(5) = ".m3u8"
        index = lowLatencyNatural(request.path.Mid(3, request.path.Len() - 8))
        if index >= 0 and index < m.variants.Count() then url = m.variants[CInt(index)]
    end if
    if url = ""
        relayRespond(client, "404 Not Found", "")
        return
    end if
    for each id in m.fetches
        if m.fetches[id].path = request.path
            m.fetches[id].clients.Push(client)
            return
        end if
    end for
    transfer = relayTransfer(url, m.port)
    if not transfer.AsyncGetToString()
        relayComplete(request.path, invalid, [client])
        return
    end if
    m.fetches[transfer.GetIdentity().ToStr()] = { transfer: transfer, path: request.path, clients: [client], clock: CreateObject("roTimespan") }
end sub

sub relayFetched(event as object)
    if event.GetInt() <> 1 then return
    id = event.GetSourceIdentity().ToStr()
    if not m.fetches.DoesExist(id) then return
    fetch = m.fetches[id]
    m.fetches.Delete(id)
    text = invalid
    if event.GetResponseCode() = 200 then text = event.GetString()
    relayComplete(fetch.path, text, fetch.clients)
end sub

sub relayExpire()
    for each id in m.fetches.Keys()
        fetch = m.fetches[id]
        if fetch.clock.TotalMilliseconds() >= 4000
            fetch.transfer.AsyncCancel()
            m.fetches.Delete(id)
            relayComplete(fetch.path, invalid, fetch.clients)
        end if
    end for
end sub

sub relayComplete(path as string, text as dynamic, clients as object)
    body = relayMediaBody(path, text)
    for each client in clients
        if body = invalid
            relayRespond(client, "502 Bad Gateway", "")
        else
            relayRespond(client, "200 OK", body)
        end if
    end for
end sub

' A failed refresh can end Roku's live playback, so a brief upstream failure
' re-serves that path's last good playlist. Each path has its own budget; once
' spent, the 502 lets the player's own recovery fetch a fresh source.
function relayMediaBody(path as string, text as dynamic) as dynamic
    body = lowLatencyMedia(text, m.state, m.top.startCount, m.top.maxCount)
    if body <> invalid
        m.lastGood[path] = body
        m.failures[path] = 0
        if text.InStr("#EXT-X-ENDLIST") >= 0 then m.top.ended = true
        return body
    end if
    failures = 0
    if m.failures.DoesExist(path) then failures = m.failures[path]
    if failures >= 5 or not m.lastGood.DoesExist(path) then return invalid
    m.failures[path] = failures + 1
    return m.lastGood[path]
end function

function relayReadRequest(connection as object, port as object) as dynamic
    crlf = Chr(13) + Chr(10)
    text = ""
    clock = CreateObject("roTimespan")
    while not m.top.stopRequested and clock.TotalMilliseconds() < 3000
        if connection.IsReadable() or connection.GetCountRcvBuf() > 0
            chunk = connection.ReceiveStr(2048)
            if chunk = invalid or chunk = "" then return invalid
            text += chunk
            if text.InStr(crlf + crlf) >= 0
                parts = text.Left(text.InStr(crlf)).Split(" ")
                if parts.Count() <> 3 then return invalid
                if parts[0] <> "GET" and parts[0] <> "HEAD" then return invalid
                path = parts[1]
                if path.InStr("?") >= 0 then path = path.Left(path.InStr("?"))
                return { method: parts[0], path: path }
            end if
            if text.Len() > 8192 then return invalid
        else
            wait(20, port)
        end if
    end while
    return invalid
end function

sub relayRespond(client as object, status as string, body as string)
    crlf = Chr(13) + Chr(10)
    payload = CreateObject("roByteArray")
    payload.FromAsciiString(body)
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString("HTTP/1.1 " + status + crlf + "Content-Type: application/vnd.apple.mpegurl" + crlf + "Content-Length: " + payload.Count().ToStr() + crlf + "Cache-Control: no-store" + crlf + "Connection: close" + crlf + crlf)
    if not client.headOnly then bytes.Append(payload)
    connection = client.connection
    offset = 0
    clock = CreateObject("roTimespan")
    while offset < bytes.Count() and not m.top.stopRequested and clock.TotalMilliseconds() < 3000
        sent = 0
        if connection.IsWritable() then sent = connection.Send(bytes, offset, bytes.Count() - offset)
        if sent > 0
            offset += sent
        else
            if not connection.eOK() then exit while
            wait(10, client.port)
        end if
    end while
    relayDisconnect(client)
end sub

sub relayDisconnect(client as object)
    client.connection.NotifyReadable(false)
    client.connection.NotifyWritable(false)
    client.connection.Close()
end sub

function relayTransfer(url as string, port as object) as object
    transfer = CreateObject("roUrlTransfer")
    transfer.SetMessagePort(port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.SetHeaders({ Accept: "*/*", Origin: "https://android.tv.twitch.tv", Referer: "https://android.tv.twitch.tv/", "User-Agent": "Stitch Roku", "Client-ID": "kimne78kx3ncx6brgo4mv6wki5h1ko" })
    transfer.SetUrl(url)
    return transfer
end function

function relayFetch(url as string) as dynamic
    port = CreateObject("roMessagePort")
    transfer = relayTransfer(url, port)
    if not transfer.AsyncGetToString() then return invalid
    clock = CreateObject("roTimespan")
    while not m.top.stopRequested and clock.TotalMilliseconds() < 4000
        event = wait(100, port)
        if type(event) = "roUrlEvent"
            if event.GetInt() = 1
                if event.GetResponseCode() = 200 then return event.GetString()
                return invalid
            end if
        end if
    end while
    transfer.AsyncCancel()
    return invalid
end function
