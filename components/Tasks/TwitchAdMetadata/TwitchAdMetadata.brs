sub init()
    m.top.functionName = "readMetadata"
end sub

function adMetadataSource(source as dynamic, kind as dynamic) as string
    if not tadString(source) or not tadString(kind) then return ""
    if source.Len() < 1 or source.Len() > 8192 then return ""
    for i = 0 to source.Len() - 1
        code = Asc(source.Mid(i, 1))
        if code < 33 or code > 126 or code = 92 then return ""
    end for
    if source.InStr("#") >= 0 then return ""
    if kind = "direct"
        valid = CreateObject("roRegex", "^https://[A-Za-z0-9.-]+\.(ttvnw\.net|twitchcdn\.net)/[^ ]+$", "").IsMatch(source)
        if valid then return source
    else if kind = "loopback"
        match = CreateObject("roRegex", "^http://127\.0\.0\.1:([0-9]{1,5})/master\.m3u8$", "").Match(source)
        if match.Count() <> 2 then return ""
        port = tadNatural(match[1], 65535&)
        if port = invalid then return ""
        if port < 1024& then return ""
        return source.Left(source.Len() - 12) + "/video.m3u8"
    else if kind = "relay"
        ' The lower-latency relay keeps every date range of its source.
        if CreateObject("roRegex", "^http://127\.0\.0\.1:49[0-9]{3}/live\.m3u8$", "").IsMatch(source) then return source
    end if
    return ""
end function

sub readMetadata()
    owner = m.top.owner
    uri = adMetadataSource(m.top.source, m.top.sourceKind)
    if not tadOwner(owner) then return
    if uri = "" or m.top.stopRequested
        m.top.response = { owner: owner, cues: [], bounds: [], closed: true, cleanupOk: true }
        return
    end if
    m.path = "tmp:/stitch-ad-" + owner + ".m3u8"
    m.ownPath = false
    m.cleanupOk = true
    fs = CreateObject("roFileSystem")
    if fs.Exists(m.path)
        m.top.response = { owner: owner, cues: [], bounds: [], closed: true, cleanupOk: false }
        return
    end if
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("stopRequested", m.port)
    m.clock = CreateObject("roTimespan")
    m.transfer = invalid
    m.active = false
    m.identity = invalid
    m.nextPoll = 0
    m.deadline = 0
    m.stopped = false
    try
        while not m.top.stopRequested and not m.stopped
            now = m.clock.TotalMilliseconds()
            if m.transfer <> invalid
                if now >= m.deadline
                    adMetadataCancel()
                    adMetadataEmpty(owner)
                    exit while
                end if
                ' Async IO may not have created its destination yet. The
                ' deadline still applies while absent; present files stay strict.
                if fs.Exists(m.path)
                    stat = fs.Stat(m.path)
                    if type(stat) <> "roAssociativeArray" or stat.type <> "file" or stat.size > 262144
                        adMetadataCancel()
                        adMetadataEmpty(owner)
                        exit while
                    end if
                end if
            else if now >= m.nextPoll
                m.transfer = CreateObject("roUrlTransfer")
                m.transfer.SetMessagePort(m.port)
                if not m.transfer.SetCertificatesFile("common:/certs/ca-bundle.crt") then exit while
                if not m.transfer.EnablePeerVerification(true) or not m.transfer.EnableHostVerification(true) then exit while
                if not m.transfer.EnableEncodings(false) or not m.transfer.EnableResume(false) then exit while
                if not m.transfer.SetMinimumTransferRate(1, 2) then exit while
                if not m.transfer.SetHeaders({ "Accept-Encoding": "identity", "Range": "bytes=0-262143" }) then exit while
                m.transfer.SetUrl(uri)
                if m.transfer.GetUrl() <> uri then exit while
                m.identity = m.transfer.GetIdentity()
                m.deadline = now + 5000
                m.ownPath = true
                if not m.transfer.AsyncGetToFile(m.path)
                    adMetadataCancel()
                    adMetadataEmpty(owner)
                    exit while
                end if
                m.active = true
            end if
            event = wait(50, m.port)
            if m.top.stopRequested then exit while
            if type(event) = "roUrlEvent" and m.transfer <> invalid
                if event.GetSourceIdentity() = m.identity
                    now = m.clock.TotalMilliseconds()
                    code = event.GetResponseCode()
                    ' A matching URL completion ends the retained operation even
                    ' when its body/framing is refused. Do not cancel completed IO.
                    completed = event.GetInt()
                    m.active = false
                    m.transfer = invalid
                    m.identity = invalid
                    stat = fs.Stat(m.path)
                    if completed <> 1 or now >= m.deadline or (code <> 200 and code <> 206)
                        adMetadataEmpty(owner)
                        exit while
                    end if
                    if type(stat) <> "roAssociativeArray" then exit while
                    if stat.type <> "file" or stat.size < 1 or stat.size > 262144 then exit while
                    if not adMetadataHeaders(event.GetResponseHeadersArray(), code, stat.size) then exit while
                    text = ReadAsciiFile(m.path)
                    if text.Len() <> stat.size then exit while
                    timeline = twitchAdClockTimeline(text)
                    if m.top.stopRequested then exit while
                    if not twitchAdClockTimelineValid(timeline)
                        ' Optional timing may disappear while media stays valid.
                        ' Hide the badge, then follow the same cleanup/poll path.
                        adMetadataEmpty(owner)
                    else
                        ' The exact five-field cues and segment bounds alone cross
                        ' this boundary; signed source text and IDs never do.
                        bounds = []
                        for each segment in timeline.segments
                            bounds.Push({ startUs: segment.startUs, endUs: segment.startUs + segment.durationUs })
                        end for
                        m.top.response = { owner: owner, cues: timeline.cues, bounds: bounds }
                    end if
                    m.transfer = invalid
                    m.identity = invalid
                    if not fs.Delete(m.path) then exit while
                    m.ownPath = false
                    m.nextPoll = now + 2000
                end if
            end if
        end while
    catch e
        ' Metadata failure never drives a playback retry or exposes provider data.
        adMetadataEmpty(owner)
    end try
    clean = adMetadataCancel()
    m.top.UnobserveField("stopRequested")
    m.top.response = { owner: owner, cues: [], bounds: [], closed: true, cleanupOk: clean }
end sub

sub adMetadataEmpty(owner as string)
    if not m.top.stopRequested then m.top.response = { owner: owner, cues: [], bounds: [] }
end sub

function adMetadataCancel() as boolean
    cancelled = true
    if m.transfer <> invalid
        if m.active then cancelled = m.transfer.AsyncCancel()
        if not cancelled then m.cleanupOk = false
        m.transfer = invalid
    end if
    m.active = false
    m.identity = invalid
    if m.ownPath
        fs = CreateObject("roFileSystem")
        if fs.Exists(m.path)
            if not fs.Delete(m.path)
                m.cleanupOk = false
                return false
            end if
            if fs.Exists(m.path)
                m.cleanupOk = false
                return false
            end if
        end if
        m.ownPath = false
    end if
    return m.cleanupOk and cancelled
end function

function adMetadataHeaders(array as dynamic, status as integer, count as integer) as boolean
    if type(array) <> "roArray" or array.Count() > 64 or count < 1 or count > 262144 then return false
    headers = {}
    total = 0
    for each entry in array
        if type(entry) <> "roAssociativeArray" or entry.Count() <> 1 then return false
        for each name in entry
            value = entry[name]
            if not tadString(value) or name.Len() < 1 or name.Len() > 128 or value.Len() > 4096 then return false
            if not CreateObject("roRegex", "^[A-Za-z0-9-]+$", "").IsMatch(name) then return false
            for i = 0 to value.Len() - 1
                code = Asc(value.Mid(i, 1))
                if (code < 32 or code > 126) and code <> 9 then return false
            end for
            total += name.Len() + value.Len()
            if total > 8192 then return false
            key = LCase(name)
            if key = "location" then return false
            if key = "content-length" or key = "content-range" or key = "content-encoding" or key = "transfer-encoding"
                if headers.DoesExist(key) then return false
                headers[key] = value.Trim()
            end if
        end for
    end for
    if headers.DoesExist("content-encoding")
        if LCase(headers["content-encoding"]) <> "identity" then return false
    end if
    if headers.DoesExist("transfer-encoding") then return false
    if not headers.DoesExist("content-length") then return false
    length = tadNatural(headers["content-length"], 262144&)
    if length = invalid then return false
    if length <> count then return false
    if status = 200 then return not headers.DoesExist("content-range")
    if status <> 206 or not headers.DoesExist("content-range") then return false
    expected = "bytes 0-" + (count - 1).ToStr() + "/" + count.ToStr()
    return headers["content-range"] = expected
end function
