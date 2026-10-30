sub checkLow(ok as boolean, message as string)
    if not ok then throw "low-latency-fixture: " + message
    m.assertions += 1
end sub

function lowMedia(sequence as integer, count as integer, extra as object) as string
    nl = Chr(10)
    text = "#EXTM3U" + nl + "#EXT-X-VERSION:3" + nl + "#EXT-X-TARGETDURATION:6" + nl + "#EXT-X-MEDIA-SEQUENCE:" + sequence.ToStr() + nl
    text += "#EXT-X-TWITCH-ELAPSED-SECS:100.000" + nl
    text += "#EXT-X-DATERANGE:ID=" + Chr(34) + "source-1" + Chr(34) + ",CLASS=" + Chr(34) + "twitch-stream-source" + Chr(34) + ",START-DATE=" + Chr(34) + "2026-10-10T00:00:00.000Z" + Chr(34) + nl
    for index = 0 to count - 1
        number = sequence + index
        if extra.DoesExist(number.ToStr()) then text += extra[number.ToStr()] + nl
        text += "#EXT-X-PROGRAM-DATE-TIME:2026-10-10T00:00:" + Right("0" + (number Mod 60).ToStr(), 2) + ".000Z" + nl
        text += "#EXTINF:2.000,live" + nl + "https://edge.example.ttvnw.net/v1/segment/s" + number.ToStr() + ".ts" + nl
    end for
    text += "#EXT-X-TWITCH-PREFETCH:https://edge.example.ttvnw.net/v1/segment/p1.ts" + nl
    return text
end function

function lowLines(text as dynamic) as object
    lines = []
    if text = invalid then return lines
    for each line in text.Split(Chr(10))
        if line <> "" then lines.Push(line)
    end for
    return lines
end function

function lowValue(text as dynamic, prefix as string) as string
    for each line in lowLines(text)
        if line.Left(prefix.Len()) = prefix then return line.Mid(prefix.Len())
    end for
    return ""
end function

function lowSegments(text as dynamic) as object
    names = []
    for each line in lowLines(text)
        if line.Left(8) = "https://" then names.Push(line.Mid(line.InStr("segment/s") + 9).Replace(".ts", ""))
    end for
    return names
end function

function lowCount(text as dynamic, value as string) as integer
    count = 0
    for each line in lowLines(text)
        if line = value then count += 1
    end for
    return count
end function

sub masterLow()
    nl = Chr(10)
    q = Chr(34)
    master = "#EXTM3U" + nl + "#EXT-X-SESSION-DATA:DATA-ID=" + q + "NODE" + q + ",VALUE=" + q + "x" + q + nl
    master += "#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID=" + q + "chunked" + q + ",NAME=" + q + "1080p60" + q + ",AUTOSELECT=YES,DEFAULT=YES" + nl
    master += "#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080,CODECS=" + q + "avc1.64002A,mp4a.40.2" + q + ",VIDEO=" + q + "chunked" + q + nl
    master += "https://use1.playlist.ttvnw.net/v1/playlist/a.m3u8" + Chr(13) + nl
    master += "#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720" + nl + "720p.m3u8" + nl
    master += "#EXT-X-STREAM-INF:BANDWIDTH=600000,RESOLUTION=640x360" + nl + "/root/360p.m3u8" + nl
    result = lowLatencyMaster(master, "https://usher.ttvnw.net/api/v2/channel/hls/x.m3u8?token=t")
    checkLow(result <> invalid and result.variants.Count() = 3, "master keeps every variant")
    checkLow(result.variants[0] = "https://use1.playlist.ttvnw.net/v1/playlist/a.m3u8", "absolute variant kept and CR trimmed")
    checkLow(result.variants[1] = "https://usher.ttvnw.net/api/v2/channel/hls/720p.m3u8" and result.variants[2] = "https://usher.ttvnw.net/root/360p.m3u8", "relative variants resolve against the master")
    lines = lowLines(result.text)
    checkLow(lines[0] = "#EXTM3U" and lines[4] = "/v/0.m3u8" and lines[6] = "/v/1.m3u8" and lines[8] = "/v/2.m3u8", "variant URIs become relay paths in order")
    checkLow(result.text.InStr("ttvnw") < 0, "signed upstream URLs never reach the local master")
    checkLow(lowCount(result.text, "#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID=" + q + "chunked" + q + ",NAME=" + q + "1080p60" + q + ",AUTOSELECT=YES,DEFAULT=YES") = 1, "URI-less rendition groups are kept")
    audio = master + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + q + "aud" + q + ",URI=" + q + "https://a/b.m3u8" + q + nl
    checkLow(lowLatencyMaster(audio, "https://usher.ttvnw.net/x.m3u8") = invalid, "separate audio renditions are refused")
    checkLow(lowLatencyMaster(master + "#EXT-X-STREAM-INF:BANDWIDTH=1" + nl, "https://usher.ttvnw.net/x.m3u8") = invalid, "dangling variant refused")
    checkLow(lowLatencyMaster("#EXTM3U" + nl + "#EXT-X-STREAM-INF:BANDWIDTH=1" + nl + "http://plain/a.m3u8" + nl, "https://usher.ttvnw.net/x.m3u8") = invalid, "plain http variant refused")
    checkLow(lowLatencyMaster("#EXTM3U" + nl, "https://usher.ttvnw.net/x.m3u8") = invalid and lowLatencyMaster(42, "https://u/x") = invalid, "empty and non-string masters refused")
end sub

sub mediaLow()
    state = { anchor: -1& }
    first = lowLatencyMedia(lowMedia(100, 15, {}), state, 3, 15)
    checkLow(first <> invalid and lowLines(first)[0] = "#EXTM3U", "valid media playlist")
    checkLow(FormatJson(lowSegments(first)) = FormatJson(["112", "113", "114"]), "startup keeps the newest three segments")
    checkLow(lowValue(first, "#EXT-X-MEDIA-SEQUENCE:") = "112" and state.anchor = 112&, "sequence and anchor follow the first kept segment")
    checkLow(lowValue(first, "#EXT-X-TARGETDURATION:") = "2", "target duration matches the two-second segments")
    checkLow(lowValue(first, "#EXT-X-VERSION:") = "3" and lowValue(first, "#EXT-X-TWITCH-ELAPSED-SECS:") = "100.000", "header tags are kept")
    checkLow(first.InStr("PREFETCH") < 0 and first.InStr("p1.ts") < 0, "prefetch hints are dropped")
    checkLow(first.InStr("#EXT-X-DATERANGE:ID=" + Chr(34) + "source-1") >= 0, "date ranges are kept")
    checkLow(first.InStr("DISCONTINUITY") < 0 and first.InStr("ENDLIST") < 0, "no discontinuity or end is invented")
    second = lowLatencyMedia(lowMedia(101, 15, {}), state, 3, 15)
    checkLow(FormatJson(lowSegments(second)) = FormatJson(["112", "113", "114", "115"]), "later refreshes keep the first segment and grow")
    checkLow(lowValue(second, "#EXT-X-MEDIA-SEQUENCE:") = "112" and state.anchor = 112&, "anchor is unchanged by refreshes")
    full = lowLatencyMedia(lowMedia(115, 15, {}), state, 3, 15)
    checkLow(lowSegments(full).Count() = 15 and lowValue(full, "#EXT-X-MEDIA-SEQUENCE:") = "115", "anchor older than the upstream window starts at its first segment")
    sliding = lowLatencyMedia(lowMedia(120, 20, {}), { anchor: 120& }, 3, 15)
    checkLow(lowSegments(sliding).Count() = 15 and lowValue(sliding, "#EXT-X-MEDIA-SEQUENCE:") = "125", "window slides once it reaches the maximum")
    ahead = { anchor: 500& }
    behind = lowLatencyMedia(lowMedia(100, 15, {}), ahead, 3, 15)
    checkLow(FormatJson(lowSegments(behind)) = FormatJson(["112", "113", "114"]) and ahead.anchor = 500&, "a lagging variant serves its newest segments without moving the anchor")
    short = lowLatencyMedia(lowMedia(7, 2, {}), { anchor: -1& }, 3, 15)
    checkLow(FormatJson(lowSegments(short)) = FormatJson(["7", "8"]), "short playlists are served whole")
end sub

sub boundaryLow()
    map = "#EXT-X-MAP:URI=" + Chr(34) + "https://edge.example.ttvnw.net/v1/init/a.mp4" + Chr(34)
    extra = { "101": "#EXT-X-DISCONTINUITY", "110": "#EXT-X-DISCONTINUITY" + Chr(10) + "#EXT-X-DATERANGE:ID=" + Chr(34) + "ad" + Chr(34) + ",CLASS=" + Chr(34) + "twitch-stitched-ad" + Chr(34) + ",START-DATE=" + Chr(34) + "2026-10-10T00:01:50.000Z" + Chr(34) + ",DURATION=30.000", "100": map }
    text = lowLatencyMedia(lowMedia(100, 15, extra), { anchor: -1& }, 3, 15)
    checkLow(lowValue(text, "#EXT-X-DISCONTINUITY-SEQUENCE:") = "2" and text.InStr("#EXT-X-DISCONTINUITY" + Chr(10)) < 0, "dropped discontinuities move into the sequence")
    checkLow(text.InStr(Chr(34) + "twitch-stitched-ad" + Chr(34)) >= 0, "ad cues survive when their segments are trimmed")
    checkLow(lowCount(text, map) = 1 and text.InStr(map) < text.InStr("#EXTINF"), "the map in effect is carried before the first segment")
    leading = lowLatencyMedia(lowMedia(100, 15, { "112": "#EXT-X-DISCONTINUITY" }), { anchor: -1& }, 3, 15)
    checkLow(lowValue(leading, "#EXT-X-DISCONTINUITY-SEQUENCE:") = "1" and leading.InStr("#EXT-X-DISCONTINUITY" + Chr(10)) < 0, "a discontinuity on the first kept segment is counted, not emitted")
    inner = lowLatencyMedia(lowMedia(100, 15, { "113": "#EXT-X-DISCONTINUITY" }), { anchor: -1& }, 3, 15)
    checkLow(lowValue(inner, "#EXT-X-DISCONTINUITY-SEQUENCE:") = "" and lowCount(inner, "#EXT-X-DISCONTINUITY") = 1, "kept discontinuities stay in place")
    based = lowMedia(100, 15, { "105": "#EXT-X-DISCONTINUITY" }).Replace("#EXT-X-MEDIA-SEQUENCE:100", "#EXT-X-MEDIA-SEQUENCE:100" + Chr(10) + "#EXT-X-DISCONTINUITY-SEQUENCE:4")
    checkLow(lowValue(lowLatencyMedia(based, { anchor: -1& }, 3, 15), "#EXT-X-DISCONTINUITY-SEQUENCE:") = "5", "upstream discontinuity sequence is the base")
    ended = lowLatencyMedia(lowMedia(100, 15, {}) + "#EXT-X-ENDLIST" + Chr(10), { anchor: -1& }, 3, 15)
    checkLow(lowCount(ended, "#EXT-X-ENDLIST") = 1, "an ended stream stays ended")
    long = lowLatencyMedia(lowMedia(100, 15, { "114": "#EXT-X-BITRATE:1" }).Replace("#EXTINF:2.000,live" + Chr(10) + "https://edge.example.ttvnw.net/v1/segment/s114.ts", "#EXTINF:2.600,live" + Chr(10) + "https://edge.example.ttvnw.net/v1/segment/s114.ts"), { anchor: -1& }, 3, 15)
    checkLow(lowValue(long, "#EXT-X-TARGETDURATION:") = "3" and lowCount(long, "#EXT-X-BITRATE:1") = 1, "target covers a longer kept segment")
end sub

sub refusalLow()
    good = lowMedia(100, 15, {})
    state = { anchor: -1& }
    checkLow(lowLatencyMedia(invalid, state, 3, 15) = invalid and lowLatencyMedia(7, state, 3, 15) = invalid, "non-string refused")
    checkLow(lowLatencyMedia(good.Replace("#EXT-X-MEDIA-SEQUENCE:100" + Chr(10), ""), state, 3, 15) = invalid, "missing media sequence refused")
    checkLow(lowLatencyMedia(good.Replace("https://edge.example.ttvnw.net/v1/segment/s105.ts", "http://edge/s105.ts"), state, 3, 15) = invalid, "plain http segment refused")
    checkLow(lowLatencyMedia(good.Replace("#EXTINF:2.000,live" + Chr(10) + "https://edge.example.ttvnw.net/v1/segment/s105.ts", "https://edge.example.ttvnw.net/v1/segment/s105.ts"), state, 3, 15) = invalid, "segment without duration refused")
    checkLow(lowLatencyMedia(good + "#EXT-X-BYTERANGE:10@0" + Chr(10) + "#EXTINF:2.000," + Chr(10) + "https://e/x.ts" + Chr(10), state, 3, 15) = invalid, "byte ranges refused")
    checkLow(lowLatencyMedia(good + "#EXT-X-KEY:METHOD=AES-128" + Chr(10), state, 3, 15) = invalid, "encryption refused")
    checkLow(lowLatencyMedia(good + "#EXTINF:2.000," + Chr(10), state, 3, 15) = invalid, "trailing segment tags refused")
    checkLow(lowLatencyMedia("#EXT-X-VERSION:3" + Chr(10) + good, state, 3, 15) = invalid, "missing header refused")
    checkLow(state.anchor = -1&, "refused playlists never set the anchor")
    checkLow(lowLatencyNatural("4294967295") = 4294967295& and lowLatencyNatural("4294967296") = -1& and lowLatencyNatural("1x") = -1& and lowLatencyNatural("") = -1&, "bounded natural numbers")
end sub

sub main()
    m.assertions = 0
    try
        mode = "__MODE__"
        if mode = "master" then masterLow()
        if mode = "media" then mediaLow()
        if mode = "boundary" then boundaryLow()
        if mode = "refusal" then refusalLow()
        print "STITCH_LOW_CASE: " + mode
        print "STITCH_LOW_PASS: __MARKER__ " + FormatJson({ assertions: m.assertions, failures: 0 })
    catch error
        print "STITCH_LOW_FAIL: __MARKER__ " + error.message
        print "STITCH_LOW_PASS: __MARKER__ " + FormatJson({ assertions: m.assertions, failures: 1 })
    end try
end sub
