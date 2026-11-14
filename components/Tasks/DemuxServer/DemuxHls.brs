' Port of fmp4-demux-proxy's manifest.py (same /m3u8 and /s URLs), plus the ad-break count fix for live lists.

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
    ' The host ends at the first path, query, fragment or backslash.
    for each sep in ["/", "?", "#", chr(92)]
        i = s.InStr(sep)
        if i >= 0 then s = s.Left(i)
    end for
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
    r = { byUrl: {}, byId: {}, order: [], max: 100, next: 0, notes: [], noted: {} }
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
        maps.order.Push(url)
        if maps.order.Count() > maps.max
            old = maps.order.Shift()
            maps.byId.Delete(maps.byUrl[old])
            maps.byUrl.Delete(old)
        end if
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

' A plain live list passes through as is; relative piece addresses are made whole so Roku fetches them from Twitch.
function absoluteUris(body as string, baseUrl as string) as string
    lines = body.Split(chr(10))
    for i = 0 to lines.Count() - 1
        line = lines[i].Trim()
        if line <> "" and line.Left(1) <> "#" then lines[i] = resolveUrl(baseUrl, line)
    end for
    return lines.Join(chr(10))
end function

' State for keepBreakCount: one entry per playback session (or per list address without a session id),
' least recently used evicted first.
function newBreakStore() as object
    store = { lists: {}, order: [], notes: [], ads: {}, maxLists: 8 }
    store.lists.SetModeCaseSensitive()
    store.ads.SetModeCaseSensitive()
    return store
end function

' Marks a list as just used and drops the least recently used ones past the limit.
sub touchBreakList(store as object, key as string)
    for i = store.order.Count() - 1 to 0 step -1
        if store.order[i] = key then store.order.Delete(i)
    end for
    store.order.Push(key)
    while store.order.Count() > store.maxLists
        store.lists.Delete(store.order.Shift())
    end while
end sub

' Reads a live media list. Tags apply to the next piece address, so each break is counted on the piece
' it precedes (several in a row count several times). A missing MEDIA-SEQUENCE means 0.
function parseLiveList(lines as object, store as object) as object
    r = { ok: true, first: 0, last: -1, uris: [], marks: {}, hasDsn: false, seqLine: -1, segLine: -1 }
    breaks = []
    pending = 0
    digits = CreateObject("roRegex", "^[0-9]{1,9}$", "")
    for i = 0 to lines.Count() - 1
        line = lines[i].Trim()
        if startsWith(line, "#EXT-X-MEDIA-SEQUENCE:")
            v = line.Mid(22).Trim()
            if digits.IsMatch(v) then r.first = v.ToInt() else r.ok = false
            r.seqLine = i
        else if startsWith(line, "#EXT-X-DISCONTINUITY-SEQUENCE:")
            r.hasDsn = true
        else if line = "#EXT-X-DISCONTINUITY"
            pending = pending + 1
            if r.segLine < 0 then r.segLine = i
        else if line <> "" and line.Left(1) <> "#"
            r.uris.Push(line)
            breaks.Push(pending)
            pending = 0
            if r.segLine < 0 then r.segLine = i
        else if startsWith(line, "#EXTINF:")
            if r.segLine < 0 then r.segLine = i
        else if startsWith(line, "#EXT-X-DATERANGE:") and line.InStr("twitch-stitched-ad") >= 0
            ' Each ad is logged once, so the log shows when ads came in.
            ad = tagAttr(line, "ID")
            if not store.ads.DoesExist(ad)
                if store.ads.Count() > 200 then store.ads.Clear()
                store.ads[ad] = true
                store.notes.Push("Ad in a live list (" + ad + ")")
            end if
        end if
    end for
    r.last = r.first + r.uris.Count() - 1
    for i = 0 to breaks.Count() - 1
        if breaks[i] > 0 then r.marks[(r.first + i).toStr()] = breaks[i]
    end for
    return r
end function

' Folds the lowest marks of a full ledger into a plain count, so the ledger stays small.
sub foldLedger(ss as object)
    seqs = []
    for each k in ss.ledger
        seqs.Push(k.ToInt())
    end for
    seqs.Sort()
    for i = 0 to 63
        k = seqs[i].toStr()
        ss.base = ss.base + ss.ledger[k]
        ss.ledger.Delete(k)
    end for
end sub

' After an ad, Twitch drops the ad's breaks (#EXT-X-DISCONTINUITY) off the top of a live list without
' counting them in #EXT-X-DISCONTINUITY-SEQUENCE, so Roku loses its place and freezes. This keeps that count.
' Quality variants of one playback share piece numbers but switch from ad to live a second or two apart, and
' Roku needs the same discontinuity number for a piece in every variant (RFC 8216 4.3.3.3). So all variants of
' a session (key) share one ledger of breaks seen; a list gets the number of ledger breaks before its first piece.
' Per variant (default: the key itself): the newest list served (stale or late copies get that one back) and
' the pieces seen (tells a late copy from a stream that started over).
function keepBreakCount(body as string, key as string, store as object, variant = "" as string) as string
    if variant = "" then variant = key
    lines = body.Split(chr(10))
    pl = parseLiveList(lines, store)
    if pl.uris.Count() = 0 or not pl.ok then return body

    ss = store.lists[key]
    if pl.hasDsn or (ss <> invalid and ss.native)
        ' Twitch counts for itself: pass it through and never mix our base into this session.
        if ss = invalid or not ss.native
            store.lists[key] = { native: true }
            store.notes.Push("Live list brings its own break count, left as is")
        end if
        touchBreakList(store, key)
        return body
    end if

    st = invalid
    if ss <> invalid then st = ss.variants[variant]
    if st <> invalid and (pl.first < st.first or pl.last < st.last)
        ' Older than what was already served. Only a list that is back near 0 with no piece seen before
        ' is a stream that started over; anything else is a late copy and gets the newest list instead.
        seenBefore = false
        for each u in pl.uris
            if st.seen.DoesExist(u) then seenBefore = true
        end for
        if pl.first < st.first and pl.first <= 10 and not seenBefore
            store.notes.Push("Live list started over, break count reset")
            ss = invalid
            st = invalid
        else
            touchBreakList(store, key)
            store.notes.Push("Late copy of a live list (first " + pl.first.toStr() + ", newest " + st.first.toStr() + "), served the newest")
            return st.out
        end if
    end if

    if ss = invalid
        ss = { native: false, base: 0, ledger: {}, variants: {} }
        store.lists[key] = ss
    end if
    touchBreakList(store, key)
    if st = invalid
        if ss.variants.Count() >= 16 then ss.variants.Clear()
        st = { first: 0, last: -1, disc: 0, seen: {}, out: body }
        ss.variants[variant] = st
    end if

    for each k in pl.marks
        ss.ledger[k] = pl.marks[k]
    end for
    if ss.ledger.Count() > 256 then foldLedger(ss)
    disc = ss.base
    for each k in ss.ledger
        if k.ToInt() < pl.first then disc = disc + ss.ledger[k]
    end for
    if st.seen.Count() > 256 then st.seen.Clear()
    for each u in pl.uris
        st.seen[u] = true
    end for
    st.first = pl.first
    st.last = pl.last

    out = body
    if disc > 0
        ' The count must come before the first piece or break: after MEDIA-SEQUENCE when that is first.
        at = pl.segLine
        if pl.seqLine >= 0 and pl.seqLine < at then at = pl.seqLine + 1
        tag = "#EXT-X-DISCONTINUITY-SEQUENCE:" + disc.toStr()
        if at <= 0
            lines[0] = tag + chr(10) + lines[0]
        else
            lines[at - 1] = lines[at - 1] + chr(10) + tag
        end if
        out = lines.Join(chr(10))
    end if
    if disc > st.disc then store.notes.Push("Ad breaks dropped off the top of a live list, now serving #EXT-X-DISCONTINUITY-SEQUENCE:" + disc.toStr())
    st.disc = disc
    st.out = out
    return out
end function

' Variant without a track: synthesize a master with separate audio and video renditions.
function synthesizeMaster(upstreamUrl as string, base as string, hints as object) as string
    quote = chr(34)
    lf = chr(10)
    audioUri = proxyUrl(base, "m3u8", upstreamUrl, "audio")
    videoUri = proxyUrl(base, "m3u8", upstreamUrl, "video")

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
