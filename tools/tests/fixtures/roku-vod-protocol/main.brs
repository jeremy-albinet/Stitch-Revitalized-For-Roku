sub main()
    m.assertions = 0
    m.failures = 0
    mode = "__MODE__"
    data = ParseJSON(ReadAsciiFile("pkg:/data.json"))
    sid = data.sessionId
    origin = "https://dfixture123.cloudfront.net"
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(data.small)
    index = rokuVodIndexParse(bytes, origin + "/archive/index.m3u8?sig=fixture%2B%25", origin)
    p2Check(index <> invalid, "recorded small index accepts")
    if index <> invalid
        for each track in ["video", "audio"]
            body = collectManifest(index, track, sid, 7)
            p2Check(body <> invalid, "complete finite span returns")
            if body <> invalid
                p2Check(body = data.smallGoldens[track], "finite manifest matches all full timeline bytes")
                p2Check(rokuVodManifestLength(index, track, sid) = body.Len(), "two-pass exact manifest length")
                p2Check(body.InStr("#EXT-X-TARGETDURATION:30" + Chr(10)) >= 0 and body.Right(15) = "#EXT-X-ENDLIST" + Chr(10), "finite target and ENDLIST retained")
                p2Check(body.InStr("fixture%") < 0 and body.InStr("cloudfront") < 0, "public manifests expose no upstream signed query")
            end if
        end for
        commentedBytes = CreateObject("roByteArray")
        commentedBytes.FromAsciiString(data.commentedSmall)
        commentedIndex = rokuVodIndexParse(commentedBytes, origin + "/archive/index.m3u8?sig=fixture%2B%25", origin)
        p2Check(commentedIndex <> invalid, "non-EXT comments accept without timestamp interpretation")
        if commentedIndex <> invalid
            for each track in ["video", "audio"]
                commentedBody = collectManifest(commentedIndex, track, sid, 16384)
                p2Check(commentedBody <> invalid, "commented complete finite span returns")
                if commentedBody <> invalid then p2Check(commentedBody = data.smallGoldens[track], "comments preserve exact finite protocol bytes without forwarding comment values")
            end for
        end if
        defaultBytes = CreateObject("roByteArray")
        defaultBytes.FromAsciiString(data.defaultPlaylist)
        defaultIndex = rokuVodIndexParse(defaultBytes, origin + "/archive/default.m3u8", origin)
        defaultBody = invalid
        if defaultIndex <> invalid then defaultBody = collectManifest(defaultIndex, "video", sid, 16384)
        p2Check(defaultBody <> invalid, "default sequence CRLF complete index streams")
        if defaultBody <> invalid then p2Check(defaultBody = data.defaultGolden, "default sequence exact golden retained")
        cursor = rokuVodManifestBegin(index, "video", sid)
        if cursor <> invalid
            p2Check(rokuVodManifestSpan(index, "video", sid, cursor, 16385) = invalid, "scratch cap refuses oversize")
            p2Check(rokuVodManifestSpan(index, "video", sid, cursor, 0) = invalid and rokuVodManifestSpan(index, "video", sid, cursor, 1.0) = invalid, "invalid span lengths refuse")
            p2Check(rokuVodManifestSpan(index, "audio", sid, cursor, 128) = invalid, "cursor track identity refuses cross use")
            p2Check(rokuVodManifestSpan(index, "video", data.otherSession, cursor, 128) = invalid, "cursor session identity refuses cross use")
            for each key in ["sequence", "totalUs", "targetDuration"]
                prior = index[key]
                index[key] = prior + 1
                p2Check(rokuVodManifestSpan(index, "video", sid, cursor, 128) = invalid, "changed immutable index metadata refuses")
                index[key] = prior
            end for
            savedPosition = cursor.position
            cursor.position = -1
            p2Check(rokuVodManifestSpan(index, "video", sid, cursor, 128) = invalid, "negative cursor offset refuses")
            cursor.position = savedPosition
            savedLength = cursor.length
            cursor.length = 1048577
            p2Check(rokuVodManifestSpan(index, "video", sid, cursor, 128) = invalid, "oversize response cursor refuses")
            cursor.length = savedLength
            cursor.extra = true
            p2Check(rokuVodManifestSpan(index, "video", sid, cursor, 128) = invalid, "unknown cursor keys refuse")
        end if
        cursor = rokuVodManifestBegin(index, "video", sid)
        if cursor <> invalid
            index.records[8] = 255
            p2Check(rokuVodManifestSpan(index, "video", sid, cursor, 128) = invalid, "changed immutable index digest refuses")
            p2Check(rokuVodManifestBegin(index, "video", sid) = invalid, "packed duration overflow refuses before streaming")
        end if
    end if
    p2Check(rokuVodManifestBegin({}, "video", sid) = invalid and rokuVodManifestLength(invalid, "video", sid) = invalid, "wrong index shape safely refuses")
    p2Check(rokuVodManifestBegin(rokuVodIndexParse(bytes, origin + "/index.m3u8", origin), "master", sid) = invalid, "only media tracks use full index API")
    p2Check(not rokuVodSessionId("ROOT_REPLACE") and not rokuVodSessionId(UCase(sid)) and not rokuVodSessionId(1), "strict typed session identity")
    master = rokuVodMasterManifest(data.metadata, sid)
    p2Check(master <> invalid, "single fixed rendition master accepts")
    if master <> invalid then p2Check(master.ToAsciiString() = data.masterGolden, "master routes and seven hints match golden")
    p2Check(rokuVodMasterManifest({}, sid) = invalid, "invalid master metadata refuses")
    for each path in ["master.m3u8", "video.m3u8", "audio.m3u8", "init/v.mp4", "init/a.mp4", "v/0.m4s", "a/1.m4s", "v/7375.m4s"]
        p2Check(rokuVodRoute("/vod/" + sid + "/" + path, sid, 7376) <> invalid, "strict indexed route accepts " + path)
    end for
    for each item in data.badPaths
        p2Check(rokuVodRoute(item, sid, 7376) = invalid, "route refuses " + item)
    end for
    p2Check(rokuVodRoute("/vod/" + data.otherSession + "/v/0.m4s", sid, 7376) = invalid, "route refuses wrong session")
    p2Check(rokuVodRoute("/vod/" + sid + "/v/0.m4s", sid, 8193) = invalid and rokuVodRoute("/vod/" + sid + "/v/0.m4s", sid, 0) = invalid, "out of bound route counts refuse")
    for each method in ["GET", "HEAD"]
        header = method + " /vod/" + sid + "/v/0.m4s HTTP/1.1" + Chr(13) + Chr(10) + "Host: 127.0.0.1:55000" + Chr(13) + Chr(10) + "Range: bytes=0-9" + Chr(13) + Chr(10) + "User-Agent: Fixture" + Chr(13) + Chr(10) + Chr(13) + Chr(10)
        request = rokuVodRequest(header, sid, 7376, 55000)
        p2Check(request <> invalid, "bounded HTTP accepts " + method)
        if request <> invalid
            p2Check(request.method = method and request.route.kind = "media" and request.route.track = "video" and request.route.entryNo = 0 and request.range = "bytes=0-9", "request retains only typed local addressing")
            response = rokuVodResponseHeader(request, sid, 7376, 100)
            p2Check(response <> invalid, "actual range response header accepts")
            if response <> invalid
                p2Check(response.bytes.ToAsciiString() = data.rangeGolden and response.bytes.Count() <= 512, "truthful range response header exact golden")
                p2Check(response.head = (method = "HEAD") and response.range.start = 0 and response.range.length = 10, "HEAD keeps same length and typed send slice")
            end if
            p2Check(rokuVodResponseHeader(request, data.otherSession, 7376, 100) = invalid, "response refuses wrong session")
            p2Check(rokuVodResponseHeader(request, sid, 7376, 16777217) = invalid, "response refuses asset byte cap")
            request.route.entryNo = 0.0
            p2Check(rokuVodResponseHeader(request, sid, 7376, 100) = invalid, "response refuses floating route identity")
            request.route.entryNo = 0
            request.route.track = "audio"
            p2Check(rokuVodResponseHeader(request, sid, 7376, 100) = invalid, "response refuses mismatched parsed route")
        end if
    end for
    for each tail in ["video.m3u8", "init/a.mp4"]
        request = rokuVodRequest("GET /vod/" + sid + "/" + tail + " HTTP/1.1" + Chr(13) + Chr(10) + "Host: 127.0.0.1:55000" + Chr(13) + Chr(10) + Chr(13) + Chr(10), sid, 7376, 55000)
        response = rokuVodResponseHeader(request, sid, 7376, 100)
        p2Check(response <> invalid, "complete manifest/init response accepts")
        if response <> invalid then p2Check(response.bytes.ToAsciiString() = data.fullGoldens[tail] and not response.head, "complete MIME and length exact golden")
        cap = 1048576
        if tail = "init/a.mp4" then cap = 2097152
        p2Check(rokuVodResponseHeader(request, sid, 7376, cap + 1) = invalid, "response refuses route-specific byte cap")
    end for
    for each header in data.badHeaders
        p2Check(rokuVodRequest(header, sid, 7376, 55000) = invalid, "strict header framing refuses")
    end for
    p2Check(not loopbackRange("", 4194305).ok, "shared LIVE range retains 4MiB cap")
    for each item in data.ranges
        actual = rokuVodRange(item.header, item.size)
        if item.ok
            p2Check(actual <> invalid, "valid bounded range accepts")
            if actual <> invalid then p2Check(actual.start = item.start and actual.length = item.length and actual.status = item.status, "range endpoints match independent golden")
        else
            p2Check(actual = invalid, "bad bounded range refuses")
        end if
    end for
    if mode = "video" or mode = "audio"
        print "VOD_P2_STAGE: small cases complete"
        large = CreateObject("roByteArray")
        p2Check(large.ReadFile("pkg:/large.bin"), "large synthetic recording loads")
        index = rokuVodIndexParse(large, origin + "/archive/index.m3u8?sig=fixture", origin)
        print "VOD_P2_STAGE: large index parsed"
        p2Check(index <> invalid, "large completed recording indexes")
        if index <> invalid
            for each track in [mode]
                body = collectManifest(index, track, sid, 16384)
                p2Check(body <> invalid, "large full timeline streams")
                if body <> invalid
                    out = CreateObject("roByteArray")
                    out.FromAsciiString(body)
                    p2Check(rvdpDigest(out) = data.largeDigests[track], "all 7376 manifest entries match independent golden")
                    p2Check(body.Len() = data.largeLengths[track] and body.Len() <= 1048576, "large response exact length remains bounded")
                    p2Check(body.InStr("#EXT-X-MEDIA-SEQUENCE:17" + Chr(10)) >= 0 and body.InStr("/" + track.Left(1) + "/3688.m4s") >= 0 and body.InStr("/" + track.Left(1) + "/7375.m4s") >= 0, "nonzero sequence middle and final routes retained")
                end if
            end for
            p2Check(index.totalUs = 73760000000&, "full 20 hour timeline is never LIVE tail")
        end if
    end if
    print "VOD_P2_RESULT: __MARKER__ "; FormatJSON({ assertions: m.assertions, failures: m.failures })
end sub

function collectManifest(index as object, track as string, sid as string, size as integer) as dynamic
    cursor = rokuVodManifestBegin(index, track, sid)
    if index.count > 100 then print "VOD_P2_STAGE: first pass complete"
    if cursor = invalid then return invalid
    body = ""
    for calls = 0 to 8192
        span = rokuVodManifestSpan(index, track, sid, cursor, size)
        if span = invalid then return invalid
        p2Check(span.bytes.Count() <= size and span.bytes.Count() <= 16384, "each send span respects scratch cap")
        body += span.bytes.ToAsciiString()
        cursor = span.cursor
        if index.count > 100 and calls mod 10 = 0 then print "VOD_P2_STAGE: bounded span "; calls
        if span.done then return body
    end for
    return invalid
end function

sub p2Check(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "VOD_P2_FAIL: "; label
    end if
end sub
