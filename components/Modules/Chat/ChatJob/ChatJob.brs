sub init()
    m.top.functionName = "main"
end sub

function openChatTransport() as dynamic
    ' OS 16 added roWebSocket. Older devices keep anonymous, read-only TCP.
    websocket = invalid
    try
        ' The compiler's component catalog predates OS 16; lookup stays runtime gated.
        websocketType = "roWebSocket"
        websocket = createObject(websocketType)
    catch e
    end try
    if websocket <> invalid
        try
            websocket.setMessagePort(m.port)
            websocket.setCertificatesFile("common:/certs/ca-bundle.crt")
            websocket.enablePeerVerification(true)
            websocket.enableHostVerification(true)
            websocket.setAutoPingReply(true)
            websocket.setUrl("wss://irc-ws.chat.twitch.tv:443")
            if websocket.open(8000)
                return { socket: websocket, secure: true }
            end if
        catch e
        end try
        websocket.close()
    end if
    if m.top.stopRequested then return invalid
    socket = createObject("roStreamSocket")
    address = createObject("roSocketAddress")
    address.setAddress("irc.chat.twitch.tv:6667")
    socket.setMessagePort(m.port)
    socket.setSendToAddress(address)
    socket.notifyReadable(true)
    socket.notifyWritable(true)
    socket.connect()
    deadline = createObject("roTimespan")
    while deadline.totalMilliseconds() < 8000 and not m.top.stopRequested
        ' Some Roku OS versions keep isConnected() false after a successful TCP
        ' handshake. Writable readiness starts our bounded login/welcome checks.
        if socket.isWritable() and socket.eOK()
            socket.notifyWritable(false)
            return { socket: socket, secure: false }
        end if
        if not socket.eOK() then exit while
        wait(100, m.port)
    end while
    socket.close()
    return invalid
end function

function sendChatLine(transport as object, line as string) as boolean
    if line.instr(chr(13)) >= 0 or line.instr(chr(10)) >= 0 then return false
    text = line + chr(13) + chr(10)
    if transport.secure
        return transport.socket.send(text, 1000) <> invalid
    end if
    ' Partial nonblocking writes must not truncate CAP, login, JOIN or PONG.
    pending = createObject("roByteArray")
    pending.fromAsciiString(text)
    offset = 0
    deadline = createObject("roTimespan")
    while offset < pending.count() and deadline.totalMilliseconds() < 1000 and not m.top.stopRequested
        if transport.socket.isWritable()
            written = transport.socket.send(pending, offset, pending.count() - offset)
            if written > 0 then offset += written
            if not transport.socket.eOK() then return false
        end if
        if offset < pending.count() then sleep(10)
    end while
    return offset = pending.count()
end function

function loginToChat(transport as object) as boolean
    username = ""
    token = ""
    ' Never even read account credentials for the plaintext transport.
    if transport.secure and not m.anonymousOnly
        username = get_user_setting("login", "")
        token = get_user_setting("access_token", "")
    end if
    nickname = "justinfan" + stri(10000 + rnd(90000)).trim()
    lines = ircLoginLines(lcase(m.top.channel), transport.secure, lcase(username), token, nickname)
    if lines.count() = 0 then return false
    for each line in lines
        if not sendChatLine(transport, line) then return false
    end for
    return true
end function

sub main()
    if m.top.channel = "" then return
    m.port = createObject("roMessagePort")
    m.anonymousOnly = false
    ' Sequence numbers span reconnects so the renderer never reapplies or skips one.
    m.moderationSeq = 0
    m.moderationLog = []
    failures = 0
    while not m.top.stopRequested and failures < 6
        m.top.connectionState = "connecting"
        m.connectionLifetime = invalid
        transport = openChatTransport()
        if transport <> invalid
            if loginToChat(transport)
                runChatConnection(transport)
            end if
            transport.socket.close()
            transport = invalid
            if m.connectionLifetime <> invalid and m.connectionLifetime.totalMilliseconds() >= 60000
                failures = 0
            end if
        end if
        if m.top.stopRequested then exit while
        failures++
        if failures >= 6 then exit while
        m.top.connectionState = "reconnecting"
        backoff = 1000 * (2 ^ (failures - 1))
        if backoff > 30000 then backoff = 30000
        deadline = createObject("roTimespan")
        while deadline.totalMilliseconds() < backoff and not m.top.stopRequested
            wait(200, m.port)
        end while
    end while
    if m.top.stopRequested
        m.top.connectionState = "stopped"
    else
        m.top.connectionState = "unavailable"
    end if
end sub

sub runChatConnection(transport as object)
    bufferState = { buffer: "", discarding: false }
    queue = []
    m.top.workload = invalid
    workWindow = createObject("roTimespan")
    parseClock = createObject("roTimespan")
    receiveMs = 0
    parseMs = 0
    inputEvents = 0
    highWindows = 0
    m.connectionLifetime = createObject("roTimespan")
    lastActivity = createObject("roTimespan")
    lastDelivery = createObject("roTimespan")
    welcomed = false
    updateDeliveryState("waiting")
    while not m.top.stopRequested
        event = wait(100, m.port)
        parseClock.mark()
        chunk = ""
        if transport.secure
            if type(event) = "roWebSocketEvent" and event.getSocketId() = transport.socket.getSocketId()
                eventType = event.getType()
                if eventType = 2 or eventType = 3 then return
                if eventType = 5
                    chunk = ircWebSocketText(event.getInfo())
                    if chunk = invalid then return
                end if
            end if
        else
            if transport.socket.getCountRcvBuf() > 0 or transport.socket.isReadable()
                chunk = transport.socket.receiveStr(4096)
                ' Readiness can remain set after draining a packet. Only an empty
                ' successful receive is EOF; EAGAIN still allows later messages.
                if chunk = "" and transport.socket.eSuccess() then return
            end if
            if not transport.socket.eOK() then return
        end if
        if chunk <> ""
            if chunk.len() > 65536 then return
            receiveMs += parseClock.totalMilliseconds()
            lastActivity.mark()
            parseClock.mark()
            consumed = ircConsumeChunk(bufferState, chunk)
            bufferState = { buffer: consumed.buffer, discarding: consumed.discarding }
            for each line in consumed.lines
                message = ircParseMessage(line, queue.count() < 250)
                if message = invalid then continue for
                command = message.command.command
                if command = "PING"
                    parseMs += parseClock.totalMilliseconds()
                    if not sendChatLine(transport, "PONG :" + message.parameters) then return
                    parseClock.mark()
                else if command = "RECONNECT"
                    return
                else if command = "001" or command = "ROOMSTATE"
                    welcomed = true
                    if m.top.connectionState <> "connected" then m.top.connectionState = "connected"
                else if command = "NOTICE"
                    if message.parameters.instr("authentication failed") >= 0 or message.parameters.instr("Improperly formatted auth") >= 0
                        m.anonymousOnly = true
                        return
                    end if
                else if command = "PRIVMSG" or command = "USERNOTICE"
                    ' Retain pending messages until their delay elapses. Dropping the oldest
                    ' on a busy channel would keep every message perpetually too young.
                    if queue.count() < 250
                        message.identity = ircMessageIdentity(message)
                        queue.push({ comment: message, receivedAt: createObject("roTimespan") })
                    end if
                else if command = "CLEARMSG" or command = "CLEARCHAT"
                    moderation = ircModerationEvent(message)
                    if moderation <> invalid then publishModeration(queue, moderation)
                end if
            end for
            parseMs += parseClock.totalMilliseconds()
            inputEvents += consumed.lines.count()
        end if
        workElapsed = workWindow.totalMilliseconds()
        if workElapsed >= 5000
            ' Elapsed receive/dispatch work excludes socket waits and Sync holds.
            busyMs = receiveMs + parseMs
            if workElapsed <= 10000 and busyMs * 4 >= workElapsed and inputEvents * 100 >= workElapsed
                if highWindows < 2 then highWindows++
            else
                highWindows = 0
            end if
            m.top.workload = { observedAt: createObject("roDateTime").asSeconds(), windowMs: workElapsed, busyMs: busyMs, receiveMs: receiveMs, parseMs: parseMs, events: inputEvents, highWindows: highWindows }
            workWindow.mark()
            receiveMs = 0
            parseMs = 0
            inputEvents = 0
        end if
        ' A missing welcome or dead connection gets a finite retry rather than a frozen panel.
        if not welcomed and m.connectionLifetime.totalMilliseconds() > 15000 then return
        ' Allow keepalive delivery jitter while retaining finite dead-connection recovery.
        if lastActivity.totalMilliseconds() > 360000 then return
        deliveryState = "waiting"
        if queue.count() > 0
            oldest = queue[0]
            delay = ircBoundedDelay(m.top.delaySeconds, m.top.forceLive)
            nowSeconds = createObject("roDateTime").asSeconds()
            age = queuedChatAge(oldest, nowSeconds)
            if age < delay then deliveryState = "syncing"
            updateDeliveryState(deliveryState)
            if m.top.readyForNextComment and lastDelivery.totalMilliseconds() >= 250 and age >= delay
                ' Bound render work and catch up within the eligible prefix only.
                ' Messages still waiting for video sync must keep their receipt age.
                eligible = 0
                for each pending in queue
                    if queuedChatAge(pending, nowSeconds) < delay then exit for
                    eligible++
                end for
                while eligible > 4
                    queue.shift()
                    eligible--
                end while
                nextComment = queue.shift()
                lastDelivery.mark()
                ' The renderer checks moderation newer than this stamp while the comment is in flight.
                nextComment.comment.moderationSeq = m.moderationSeq
                m.top.readyForNextComment = false
                m.top.nextCommentObj = nextComment.comment
            end if
        else
            updateDeliveryState(deliveryState)
        end if
    end while
end sub

function queuedChatAge(entry as object, nowSeconds as integer) as float
    age = entry.receivedAt.totalMilliseconds() / 1000.0
    ircTimestamp = entry.comment.tags.tmi_sent_ts
    if ircTimestamp <> invalid and ircIsDigits(ircTimestamp) and ircTimestamp.len() >= 10
        sentAt = ircTimestamp.left(10).toInt()
        serverAge = nowSeconds - sentAt
        ' Ignore implausible server/device clock differences; receipt age is bounded.
        if serverAge >= 0 and serverAge <= 120 then age = serverAge
    end if
    return age
end function

sub updateDeliveryState(state as string)
    if m.top.deliveryState <> state then m.top.deliveryState = state
end sub

' Moderation bypasses the stream delay and the comment handshake. The bounded
' recent window is republished whole so a coalesced field update loses nothing.
sub publishModeration(queue as object, event as object)
    for index = queue.count() - 1 to 0 step -1
        if ircModerationMatches(queue[index].comment.identity, event) then queue.delete(index)
    end for
    m.moderationSeq++
    event.seq = m.moderationSeq
    m.moderationLog.push(event)
    if m.moderationLog.count() > 32 then m.moderationLog.shift()
    m.top.moderation = { seq: m.moderationSeq, events: m.moderationLog }
end sub
