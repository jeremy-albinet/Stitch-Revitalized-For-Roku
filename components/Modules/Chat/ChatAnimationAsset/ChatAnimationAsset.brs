sub init()
    m.top.functionName = "fetchAnimation"
end sub

sub fetchAnimation()
    request = m.top.request
    fs = createObject("roFileSystem")
    result = { generation: request.generation, uri: request.uri, path: request.path, info: invalid, removed: [], cleanupOk: true }
    for each path in request.paths
        if deleteChatAnimationFile(fs, path)
            result.removed.push(path)
        else
            result.cleanupOk = false
        end if
    end for
    if request.path <> "" and result.cleanupOk
        result.info = fetchChatAnimationFile(fs, request)
        if result.info = invalid or m.top.stopRequested
            result.info = invalid
            result.cleanupOk = deleteChatAnimationFile(fs, request.path)
            if result.cleanupOk then result.removed.push(request.path)
        end if
    end if
    ' The owner also waits for actual thread completion, before any next job.
    m.top.response = result
end sub

' This helper is called only by the Task function, never through callFunc.
function fetchChatAnimationFile(fs as object, request as object) as dynamic
    transfer = invalid
    info = invalid
    try
        if not chatAnimationPath(request.path) then return invalid
        isGif = request.path.right(4) = ".gif"
        if isGif and ircGifUri(request.uri) = invalid then return invalid
        directory = chatAnimationDirectory(request.path)
        if m.top.stopRequested then return invalid
        port = createObject("roMessagePort")
        transfer = createObject("roUrlTransfer")
        transfer.setMessagePort(port)
        transfer.setCertificatesFile("common:/certs/ca-bundle.crt")
        transfer.initClientCertificates()
        transfer.setUrl(request.uri)
        clock = createObject("roTimespan")
        if not m.top.stopRequested and transfer.asyncHead()
            event = waitChatAnimationTransfer(transfer, port, clock, fs, "", 0)
            expectedBytes = chatAnimationContentLength(event)
            if expectedBytes > 0 and not m.top.stopRequested and clock.totalMilliseconds() < 8000
                if fs.createDirectory(directory)
                    if not m.top.stopRequested and clock.totalMilliseconds() < 8000 and transfer.asyncGetToFile(request.path)
                        event = waitChatAnimationTransfer(transfer, port, clock, fs, request.path, expectedBytes)
                        stat = fs.stat(request.path)
                        if chatAnimationContentLength(event) = expectedBytes and stat <> invalid
                            size = stat.size
                            if GetInterface(size, "ifInt") <> invalid or GetInterface(size, "ifLongInt") <> invalid or GetInterface(size, "ifFloat") <> invalid or GetInterface(size, "ifDouble") <> invalid
                                if size = expectedBytes and not m.top.stopRequested and clock.totalMilliseconds() < 8000
                                    bytes = createObject("roByteArray")
                                    if bytes.readFile(request.path, 0, 1048577)
                                        if isGif
                                            info = chatConvertGif(fs, bytes, request.path, clock)
                                        else
                                            info = chatAdmitWebp(bytes)
                                        end if
                                    end if
                                end if
                            end if
                        end if
                    end if
                end if
            end if
        end if
    catch e
        info = invalid
    end try
    ' Release the only possible producer before deleting its unique directory.
    ' The owner cooperatively cancels; it never force-stops this thread.
    if transfer <> invalid then transfer.asyncCancel()
    transfer = invalid
    return info
end function

' HEAD and GET share one deadline and producer. HEAD prevents known oversize
' downloads; a GET that violates HEAD may still write excess bytes before polling.
function waitChatAnimationTransfer(transfer as object, port as object, clock as object, fs as object, path as string, expectedBytes as integer) as dynamic
    while not m.top.stopRequested and clock.totalMilliseconds() < 8000
        event = wait(50, port)
        if m.top.stopRequested or clock.totalMilliseconds() >= 8000 then return invalid
        if path <> ""
            stat = fs.stat(path)
            ' Native downloads may expose no numeric file size until a later poll.
            if stat <> invalid
                size = stat.size
                if GetInterface(size, "ifInt") <> invalid or GetInterface(size, "ifLongInt") <> invalid or GetInterface(size, "ifFloat") <> invalid or GetInterface(size, "ifDouble") <> invalid
                    if size > expectedBytes then return invalid
                end if
            end if
        end if
        if type(event) = "roUrlEvent"
            if event.getSourceIdentity() = transfer.getIdentity() then return event
        end if
    end while
    return invalid
end function

function chatAnimationContentLength(event as dynamic) as integer
    if event = invalid then return 0
    if event.getResponseCode() <> 200 then return 0
    headers = event.getResponseHeadersArray()
    if GetInterface(headers, "ifArray") = invalid then return 0
    length = 0
    for each header in headers
        if GetInterface(header, "ifAssociativeArray") = invalid then return 0
        for each name in header
            value = header[name]
            key = lcase(name)
            if key = "content-length"
                if length <> 0 or GetInterface(value, "ifString") = invalid then return 0
                value = value.trim()
                if not createObject("roRegex", "^[0-9]{1,7}$", "").isMatch(value) then return 0
                length = value.toInt()
                if length < 1 or length > 1048576 then return 0
            else if key = "transfer-encoding"
                return 0
            else if key = "location"
                ' No application-level redirect/rewrite of Twitch's supplied URL.
                return 0
            else if key = "content-encoding"
                if GetInterface(value, "ifString") = invalid then return 0
                if lcase(value.trim()) <> "identity" then return 0
            end if
        end for
    end for
    return length
end function

function chatAnimationPath(path as string) as boolean
    if path.left(18) <> "tmp:/stitch-emote-" then return false
    directory = chatAnimationDirectory(path)
    if directory = "" then return false
    suffix = directory.mid(18)
    return createObject("roRegex", "^[A-Za-z0-9-]{1,96}$", "").isMatch(suffix)
end function

function chatAnimationDirectory(path as string) as string
    if path.right(11) = "/emote.webp" then return path.left(path.len() - 11)
    if path.right(10) = "/emote.gif" then return path.left(path.len() - 10)
    return ""
end function

function deleteChatAnimationFile(fs as object, path as string) as boolean
    if not chatAnimationPath(path) then return false
    directory = chatAnimationDirectory(path)
    ' Finite attempts even for unrecoverable filesystem failures.
    for attempt = 1 to 2
        fs.delete(path)
        if path.right(4) = ".gif"
            fs.delete(directory + "/frame.gif")
            fs.delete(directory + "/atlas.png")
        end if
        fs.delete(directory)
        if not fs.exists(directory) then return true
    end for
    return false
end function
