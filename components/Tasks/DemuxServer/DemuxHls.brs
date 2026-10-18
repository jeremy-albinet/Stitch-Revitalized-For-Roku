' Port of fmp4-demux-proxy's manifest.py; same /m3u8 and /s URLs.

function startsWith(s as string, prefix as string) as boolean
    return s.Left(prefix.Len()) = prefix
end function

function parseQuery(path as string) as object
    q = {}
    i = path.InStr("?")
    if i < 0 then return q
    for each pair in path.Mid(i + 1).Split("&")
        eq = pair.InStr("=")
        if eq > 0 then q[pair.Left(eq)] = pair.Mid(eq + 1).DecodeUriComponent()
    end for
    return q
end function

function queryValue(q as object, key as string) as string
    v = q[key]
    if v = invalid then return ""
    return v
end function

function classifyManifest(body as string) as string
    hasMedia = false
    hasVariant = false
    variantTags = ["#EXTINF:", "#EXT-X-MAP:", "#EXT-X-TARGETDURATION:", "#EXT-X-PART:", "#EXT-X-PRELOAD-HINT:", "#EXT-X-RENDITION-REPORT:", "#EXT-X-TWITCH-PREFETCH:"]
    for each line in body.Split(chr(10))
        if startsWith(line, "#EXT-X-STREAM-INF:") or startsWith(line, "#EXT-X-I-FRAME-STREAM-INF:") then return "master"
        if startsWith(line, "#EXT-X-MEDIA:")
            hasMedia = true
        else
            for each tag in variantTags
                if startsWith(line, tag)
                    hasVariant = true
                    exit for
                end if
            end for
        end if
    end for
    if hasMedia and not hasVariant then return "master"
    if hasVariant then return "variant"
    return "unknown"
end function

function proxyUrl(base as string, kind as string, upstream as string, track as string) as string
    enc = upstream.EncodeUriComponent()
    if kind = "m3u8"
        url = base + "/m3u8?u=" + enc
    else
        url = base + "/s?u=" + enc + "&k=" + kind
    end if
    if track <> "" then url = url + "&track=" + track
    return url
end function

function uriAttr(line as string) as string
    quote = chr(34)
    p = line.InStr("URI=" + quote)
    if p < 0 then return ""
    rel = line.Mid(p + 5).InStr(quote)
    if rel < 0 then return ""
    return line.Mid(p + 5, rel)
end function

' Value of NAME=value or NAME="value" in a tag line.
function tagAttr(line as string, name as string) as string
    p = line.InStr(name + "=")
    if p < 0 then return ""
    rest = line.Mid(p + name.Len() + 1)
    if rest.Left(1) = chr(34)
        endQuote = rest.Mid(1).InStr(chr(34))
        if endQuote < 0 then return ""
        return rest.Mid(1, endQuote)
    end if
    comma = rest.InStr(",")
    if comma >= 0 then return rest.Left(comma)
    return rest
end function

function hostOf(url as string) as string
    s = url
    p = s.InStr("://")
    if p >= 0 then s = s.Mid(p + 3)
    slash = s.InStr("/")
    if slash >= 0 then s = s.Left(slash)
    return s
end function

function rewriteUriAttr(line as string, baseUrl as string, base as string, kind as string, track as string, extra as string) as string
    quote = chr(34)
    p = line.InStr("URI=" + quote)
    if p < 0 then return line
    startIdx = p + 5
    rel = line.Mid(startIdx).InStr(quote)
    if rel < 0 then return line
    uri = line.Mid(startIdx, rel)
    return line.Left(startIdx) + proxyUrl(base, kind, resolveUrl(baseUrl, uri), track) + extra + line.Mid(startIdx + rel)
end function

' Short ids for EXT-X-MAP URLs so each segment URL can name its init.
function newMapRegistry() as object
    r = { byUrl: {}, byId: {}, next: 0, notes: [], noted: {} }
    r.byUrl.SetModeCaseSensitive()
    r.noted.SetModeCaseSensitive()
    return r
end function

function registerMap(maps as object, url as string) as string
    id = maps.byUrl[url]
    if id = invalid
        maps.next = maps.next + 1
        id = maps.next.toStr()
        maps.byUrl[url] = id
        maps.byId[id] = url
        if maps.next > 1 then noteOnce(maps, "map:" + url, "New starter piece listed, from " + hostOf(url))
    end if
    return id
end function

sub noteOnce(maps as object, key as string, text as string)
    if maps.noted[key] <> invalid then return
    if maps.noted.Count() > 500 then maps.noted.Clear()
    maps.noted[key] = true
    maps.notes.Push(text)
end sub

function rewriteManifest(body as string, baseUrl as string, base as string, track as string, hints as object, maps as object) as string
    kind = classifyManifest(body)
    if kind = "unknown" then return body
    if kind = "variant" and track = "" then return synthesizeMaster(baseUrl, base, hints)

    knownMarks = { "timestamp": true, "twitch-session": true, "twitch-stream-source": true, "twitch-trigger": true }
    prefetch = "#EXT-X-TWITCH-PREFETCH:"
    out = []
    expect = ""
    mapParam = ""
    mapHost = ""
    afterBreak = false
    for each line in body.Split(chr(10))
        if line.Right(1) = chr(13) then line = line.Left(line.Len() - 1)
        if line = "" or (line.Left(1) = "#" and not startsWith(line, "#EXT"))
            out.Push(line)
        else if expect <> "" and line.Left(1) <> "#"
            full = resolveUrl(baseUrl, line)
            if expect = "media"
                if mapParam = "" then noteOnce(maps, "nomap:" + full, "A piece is listed with no starter piece before it")
                if mapHost <> "" and hostOf(full) <> mapHost then noteOnce(maps, "host:" + full, "A piece comes from " + hostOf(full) + ", its starter piece from " + mapHost)
                if afterBreak then noteOnce(maps, "break:" + full, "Playlist break before a piece from " + hostOf(full))
                afterBreak = false
                out.Push(proxyUrl(base, expect, full, track) + mapParam)
            else
                out.Push(proxyUrl(base, expect, full, track))
            end if
            expect = ""
        else if kind = "master"
            if startsWith(line, "#EXT-X-STREAM-INF:")
                expect = "m3u8"
                out.Push(line)
            else if startsWith(line, "#EXT-X-MEDIA:") or startsWith(line, "#EXT-X-I-FRAME-STREAM-INF:") or startsWith(line, "#EXT-X-SESSION-DATA:")
                out.Push(rewriteUriAttr(line, baseUrl, base, "m3u8", "", ""))
            else
                out.Push(line)
            end if
        else
            if startsWith(line, "#EXTINF:")
                expect = "media"
                out.Push(line)
            else if startsWith(line, "#EXT-X-MAP:")
                uri = uriAttr(line)
                if uri <> ""
                    initUrl = resolveUrl(baseUrl, uri)
                    mapParam = "&map=" + registerMap(maps, initUrl)
                    mapHost = hostOf(initUrl)
                end if
                out.Push(rewriteUriAttr(line, baseUrl, base, "init", track, ""))
            else if startsWith(line, "#EXT-X-PART:")
                out.Push(rewriteUriAttr(line, baseUrl, base, "part", track, mapParam))
            else if startsWith(line, "#EXT-X-PRELOAD-HINT:")
                if UCase(line).InStr("TYPE=MAP") >= 0
                    out.Push(rewriteUriAttr(line, baseUrl, base, "init", track, ""))
                else
                    out.Push(rewriteUriAttr(line, baseUrl, base, "part", track, mapParam))
                end if
            else if startsWith(line, "#EXT-X-RENDITION-REPORT:")
                out.Push(rewriteUriAttr(line, baseUrl, base, "m3u8", "", ""))
            else if startsWith(line, prefetch)
                out.Push(prefetch + proxyUrl(base, "prefetch", resolveUrl(baseUrl, line.Mid(prefetch.Len())), track) + mapParam)
            else
                if line = "#EXT-X-DISCONTINUITY" then afterBreak = true
                if startsWith(line, "#EXT-X-DATERANGE:")
                    mark = tagAttr(line, "CLASS")
                    if not knownMarks.DoesExist(mark) then noteOnce(maps, "mark:" + tagAttr(line, "ID"), "Playlist mark: " + mark + " (" + tagAttr(line, "ID") + ")")
                end if
                out.Push(line)
            end if
        end if
    end for
    return out.Join(chr(10))
end function

' Variant without a track: synthesize a master with separate audio and video renditions.
function synthesizeMaster(upstreamUrl as string, base as string, hints as object) as string
    quote = chr(34)
    lf = chr(10)
    enc = upstreamUrl.EncodeUriComponent()
    audioUri = base + "/m3u8?u=" + enc + "&track=audio"
    videoUri = base + "/m3u8?u=" + enc + "&track=video"

    codecs = queryValue(hints, "codecs")
    if codecs = "" or not CreateObject("roRegex", "^[A-Za-z0-9.,_\-]+$", "").IsMatch(codecs) then codecs = "avc1.64001f,mp4a.40.2"
    bandwidth = Val(queryValue(hints, "bw"))
    if bandwidth <= 0 then bandwidth = 4000000
    resAttr = ""
    res = queryValue(hints, "res")
    if CreateObject("roRegex", "^[0-9]+x[0-9]+$", "").IsMatch(res) then resAttr = ",RESOLUTION=" + res

    s = "#EXTM3U" + lf + "#EXT-X-VERSION:6" + lf
    s = s + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + quote + "aac" + quote + ",NAME=" + quote + "Audio" + quote
    s = s + ",DEFAULT=YES,AUTOSELECT=YES,URI=" + quote + audioUri + quote + lf
    s = s + "#EXT-X-STREAM-INF:BANDWIDTH=" + Int(bandwidth).toStr() + resAttr + ",CODECS=" + quote + codecs + quote + ",AUDIO=" + quote + "aac" + quote + lf
    s = s + videoUri + lf
    return s
end function

' Resolves a playlist URI against the playlist's URL.
function resolveUrl(base as string, ref as string) as string
    lowerRef = LCase(ref)
    if lowerRef.Left(7) = "http://" or lowerRef.Left(8) = "https://" then return ref
    b = base
    q = b.InStr("?")
    if q >= 0 then b = b.Left(q)
    schemeEnd = b.InStr("://")
    if schemeEnd < 0 then return ref
    if ref.Left(2) = "//" then return b.Left(schemeEnd + 1) + ref
    hostEnd = b.Mid(schemeEnd + 3).InStr("/")
    if hostEnd < 0
        origin = b
        dir = b + "/"
    else
        origin = b.Left(schemeEnd + 3 + hostEnd)
        lastSlash = schemeEnd + 3 + hostEnd
        while true
            rel = b.Mid(lastSlash + 1).InStr("/")
            if rel < 0 then exit while
            lastSlash = lastSlash + 1 + rel
        end while
        dir = b.Left(lastSlash + 1)
    end if
    if ref.Left(1) = "/" then return origin + ref
    return dir + ref
end function
