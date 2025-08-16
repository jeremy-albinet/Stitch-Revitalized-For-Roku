' ChatReconnectHandler.brs - Handles reconnection logic for chat system

sub init()
    m.maxReconnectAttempts = 5
    m.reconnectDelay = 2000 ' 2 seconds
    m.maxReconnectDelay = 60000 ' 60 seconds
    m.currentReconnectAttempt = 0
    m.lastConnectionTime = 0
    m.connectionState = "disconnected"
    m.reconnectTimer = invalid
end sub

function handleChatDisconnection(tcpSocket as object, channel as string) as object
    m.connectionState = "reconnecting"
    m.currentReconnectAttempt = m.currentReconnectAttempt + 1

    ' ? "[ChatReconnect] Connection lost, attempting reconnect ("; m.currentReconnectAttempt; " of "; m.maxReconnectAttempts; ")"

    result = {
        success: false,
        socket: invalid,
        shouldRetry: true
    }

    if m.currentReconnectAttempt > m.maxReconnectAttempts
        ' ? "[ChatReconnect] Max reconnect attempts reached"
        m.connectionState = "failed"
        result.shouldRetry = false
        return result
    end if

    ' Calculate exponential backoff delay
    delay = calculateReconnectDelay()
    ' ? "[ChatReconnect] Waiting "; delay; "ms before reconnect"
    sleep(delay)

    ' Attempt to reconnect
    newSocket = attemptReconnection(channel)

    if newSocket <> invalid
        ' ? "[ChatReconnect] Reconnection successful"
        m.connectionState = "connected"
        m.currentReconnectAttempt = 0
        m.lastConnectionTime = CreateObject("roDateTime").AsSeconds()
        result.success = true
        result.socket = newSocket
    else
        ' ? "[ChatReconnect] Reconnection failed"
        ' Recursive retry
        if m.currentReconnectAttempt < m.maxReconnectAttempts
            return handleChatDisconnection(tcpSocket, channel)
        end if
    end if

    return result
end function

function attemptReconnection(channel as string) as object
    try
        tcpSocket = CreateObject("roStreamSocket")
        addr = CreateObject("roSocketAddress")
        addr.SetAddress("irc.chat.twitch.tv:6667")

        tcpSocket.SetSendToAddress(addr)
        tcpSocket.SetMessagePort(CreateObject("roMessagePort"))
        tcpSocket.notifyReadable(true)
        tcpSocket.SetKeepAlive(true)

        ' Set connection timeout
        tcpSocket.SetConnectTimeout(10000) ' 10 seconds

        if tcpSocket.Connect()
            ' Authenticate
            if authenticateChat(tcpSocket)
                ' Join channel
                tcpSocket.SendStr("JOIN #" + channel + Chr(13) + Chr(10))

                ' Verify connection
                if verifyConnection(tcpSocket)
                    return tcpSocket
                end if
            end if
        end if
    catch e
        ' ? "[ChatReconnect] Error during reconnection: "; e
    end try

    return invalid
end function

function authenticateChat(tcpSocket as object) as boolean
    try
        tcpSocket.SendStr("CAP REQ :twitch.tv/tags twitch.tv/commands" + Chr(13) + Chr(10))

        user_auth_token = get_user_setting("access_token")
        username = get_user_setting("login")

        if username <> "" and user_auth_token <> invalid and user_auth_token <> ""
            tcpSocket.SendStr("PASS oauth:" + user_auth_token + Chr(13) + Chr(10))
            tcpSocket.SendStr("USER " + username + " 8 * :" + username + Chr(13) + Chr(10))
            tcpSocket.SendStr("NICK " + username + Chr(13) + Chr(10))
        else
            ' Use anonymous connection
            randomId = CreateObject("roDeviceInfo").GetRandomUUID().Replace("-", "").Left(8)
            tcpSocket.SendStr("PASS SCHMOOPIIE" + Chr(13) + Chr(10))
            tcpSocket.SendStr("NICK justinfan" + randomId + Chr(13) + Chr(10))
        end if

        return true
    catch e
        return false
    end try
end function

function verifyConnection(tcpSocket as object) as boolean
    ' Send PING and wait for PONG to verify connection
    tcpSocket.SendStr("PING :tmi.twitch.tv" + Chr(13) + Chr(10))

    timeout = 5000 ' 5 seconds
    startTime = CreateObject("roDateTime").AsSeconds() * 1000

    while (CreateObject("roDateTime").AsSeconds() * 1000 - startTime) < timeout
        if tcpSocket.GetCountRcvBuf() > 0
            received = ""
            get = ""
            while not get = Chr(10) and tcpSocket.GetCountRcvBuf() > 0
                get = tcpSocket.ReceiveStr(1)
                received += get
            end while

            if received.InStr("PONG") > -1
                return true
            end if
        end if
        sleep(100)
    end while

    return false
end function

function calculateReconnectDelay() as integer
    ' Exponential backoff with jitter
    baseDelay = m.reconnectDelay * (2 ^ (m.currentReconnectAttempt - 1))
    jitter = Rnd(500) ' Random jitter up to 500ms
    delay = baseDelay + jitter

    if delay > m.maxReconnectDelay
        delay = m.maxReconnectDelay
    end if

    return delay
end function

sub resetReconnectState()
    m.currentReconnectAttempt = 0
    m.connectionState = "disconnected"
    if m.reconnectTimer <> invalid
        m.reconnectTimer.control = "stop"
        m.reconnectTimer = invalid
    end if
end sub

function isHealthyConnection(tcpSocket as object) as boolean
    if tcpSocket = invalid
        return false
    end if

    if not tcpSocket.IsConnected()
        return false
    end if

    ' Check if socket is still responsive
    if tcpSocket.IsException()
        return false
    end if

    return true
end function

function monitorConnection(tcpSocket as object) as object
    ' Health check for connection
    status = {
        isHealthy: true,
        needsReconnect: false,
        lastActivity: CreateObject("roDateTime").AsSeconds()
    }

    if not isHealthyConnection(tcpSocket)
        status.isHealthy = false
        status.needsReconnect = true
        return status
    end if

    ' Check for activity timeout (no messages for 5 minutes)
    currentTime = CreateObject("roDateTime").AsSeconds()
    if m.lastActivityTime <> invalid
        if currentTime - m.lastActivityTime > 300 ' 5 minutes
            ' Send PING to check if connection is alive
            tcpSocket.SendStr("PING :tmi.twitch.tv" + Chr(13) + Chr(10))
            m.lastActivityTime = currentTime
        end if
    else
        m.lastActivityTime = currentTime
    end if

    return status
end function

sub updateLastActivity()
    m.lastActivityTime = CreateObject("roDateTime").AsSeconds()
end sub
