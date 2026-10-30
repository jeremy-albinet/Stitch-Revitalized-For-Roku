sub main()
    m.assertions = 0
    m.failures = 0
    print "STITCH_AD_CLOCK_BEGIN: __MARKER__"
    testNativeArithmetic()
    testSourceProjection()
    testBoundaries()
    testHeaders()
    testSourceEpochAgreement()
    testMixedEpochProjection()
    print "STITCH_AD_CLOCK_END: __MARKER__ "; FormatJson({assertions: m.assertions, failures: m.failures})
end sub

function mixedEpochSource() as string
    text = sourceText().Replace("#EXT-X-MEDIA-SEQUENCE:41" + Chr(10), "#EXT-X-MEDIA-SEQUENCE:41" + Chr(10) + "#EXT-X-DISCONTINUITY-SEQUENCE:27" + Chr(10))
    for each suffix in ["04", "06"]
        tag = "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:" + suffix + ".000000Z"
        text = text.Replace(tag, "#EXT-X-DISCONTINUITY" + Chr(10) + tag)
    end for
    return text
end function

function mixedEpochPublication(localBase = 0 as integer) as object
    base = publication()
    segments = []
    for i = 0 to 3
        localEpoch = localBase
        if i >= 2 then localEpoch += i - 1
        initVideo = 1
        if i = 2 then initVideo = 3
        prefix = "live-0123456789abcdef0123456789abcdef-"
        segments.Push({ sequence: 41 + i, duration: "2.000", durationUs: 2000000, videoId: prefix + (7 + i * 2).ToStr(), audioId: prefix + (8 + i * 2).ToStr(), epoch: localEpoch, initVideoId: prefix + initVideo.ToStr(), initAudioId: prefix + (initVideo + 1).ToStr() })
    end for
    base.version = 2
    base.discontinuitySequence = localBase
    base.initVideoId = segments[0].initVideoId
    base.initAudioId = segments[0].initAudioId
    base.segments = segments
    return base
end function

function mixedEpochState(pub as object) as object
    state = { sourceUrl: "https://test.ttvnw.net/current.m3u8", closed: false, phase: "ready", sourceTransitions: true, epoch: 29, segments: [] }
    text = mixedEpochSource()
    state.window = nativeLiveParsePlaylist(text, state.sourceUrl)
    saved = []
    for i = 0 to pub.segments.Count() - 1
        selected = state.window.segments[i]
        target = pub.segments[i]
        saved.Push({ sequence: selected.sequence, duration: selected.duration, durationUs: selected.durationUs, url: selected.url, mapUrl: selected.mapUrl, sourceEpoch: selected.epoch, localEpoch: target.epoch, videoId: target.videoId, audioId: target.audioId, initVideoId: target.initVideoId, initAudioId: target.initAudioId })
    end for
    state.segments = saved
    twitchAdClockCapture(state, "playlist", text, state.sourceUrl)
    return state
end function

sub testMixedEpochProjection()
    m.config = { sourceDelaySeconds: 2, metadata: { bandwidth: 6000000, width: 1920, height: 1080, frameRate: "60.000", videoCodec: "avc1.64002a" } }
    for each localBase in [0, 4]
        pub = mixedEpochPublication(localBase)
        state = mixedEpochState(pub)
        original = FormatJson(pub)
        sourceOriginal = FormatJson(state.adClockTimeline)
        check(loopbackPublicationValid(pub), "mixed source fixture uses valid actual v2 publication")
        projection = twitchAdClockServerPublication(state, pub)
        check(projection <> invalid, "mixed source epochs project against actual window/cache binding")
        if projection <> invalid
            for i = 0 to 3
                check(projection.segments[i].epoch = pub.segments[i].epoch and projection.segments[i].startUs = 1767225600000000& + i * 2000000&, "projection adopts exact local labels and unchanged UTC")
                check(state.adClockTimeline.segments[i].epoch = 27 + pub.segments[i].epoch - localBase, "original source labels remain unchanged")
            end for
            for each track in ["video", "audio"]
                canonical = loopbackManifest(track, pub).ToAsciiString()
                text = twitchAdClockManifest(track, pub, projection).ToAsciiString()
                reloaded = twitchAdClockTimeline(text)
                check(reloaded <> invalid and FormatJson(reloaded) = FormatJson(projection), "both real emitted media playlists round-trip exact anchors/cues/local boundaries")
                stripped = ""
                for each line in text.Split(Chr(10))
                    if line <> "" and line.Left(25) <> "#EXT-X-PROGRAM-DATE-TIME:" and line.Left(17) <> "#EXT-X-DATERANGE:" then stripped += line + Chr(10)
                end for
                check(stripped = canonical, "PDT overlay preserves every canonical MAP/discontinuity/media byte")
                changed = ParseJson(FormatJson(projection))
                entries = changed.segments
                for i = 0 to entries.Count() - 1
                    entry = entries[i]
                    entry.epoch += 1
                    entries[i] = entry
                end for
                changed.segments = entries
                check(twitchAdClockManifest(track, pub, changed).ToAsciiString() = canonical, "wrong frozen local labels fall back to canonical")
            end for
        end if
        check(FormatJson(pub) = original and FormatJson(state.adClockTimeline) = sourceOriginal, "projection never mutates source timeline or publication")
    end for
    pub = mixedEpochPublication()
    for each field in ["sourceEpoch", "localEpoch", "durationUs", "sequence", "mapUrl", "url", "duration", "videoId", "audioId", "initVideoId", "initAudioId"]
        state = mixedEpochState(pub)
        entries = state.segments
        entry = entries[2]
        if loopbackInteger(entry[field])
            entry[field] += 1
        else
            entry[field] += "changed"
        end if
        entries[2] = entry
        state.segments = entries
        check(twitchAdClockServerPublication(state, pub) = invalid, "changed converted cache binding refused " + field)
    end for
    for each field in ["sourceEpoch", "localEpoch", "durationUs", "sequence"]
        for each bad in [28.0#, "28", invalid, 4294967296&]
            state = mixedEpochState(pub)
            entries = state.segments
            entry = entries[2]
            entry[field] = bad
            entries[2] = entry
            state.segments = entries
            check(twitchAdClockServerPublication(state, pub) = invalid, "malformed converted cache numeric binding refused " + field)
        end for
    end for
    state = mixedEpochState(pub)
    timeline = state.adClockTimeline
    entries = timeline.segments
    for i = 0 to entries.Count() - 1
        entry = entries[i]
        entry.epoch += 1
        entries[i] = entry
    end for
    timeline.segments = entries
    state.adClockTimeline = timeline
    check(twitchAdClockServerPublication(state, pub) = invalid, "correct local labels cannot substitute for wrong source epochs")
    for each suffix in ["03.999999", "02.000000"]
        bad = mixedEpochSource().Replace("00:00:04.000000Z", "00:00:" + suffix + "Z")
        check(not twitchAdClockTimelineValid(twitchAdClockTimeline(bad)), "cross-epoch overlapping or backward UTC refused")
    end for
    gap = mixedEpochSource().Replace("00:00:04.000000Z", "00:00:05.000000Z").Replace("00:00:06.000000Z", "00:00:08.000000Z")
    check(twitchAdClockTimelineValid(twitchAdClockTimeline(gap)), "explicit positive cross-epoch gaps stay valid without extrapolation")
    for each mode in ["closed", "failed", "stale", "disabled", "missing", "duplicate", "window"]
        state = mixedEpochState(pub)
        if mode = "closed" then state.closed = true
        if mode = "failed" then state.phase = "failed"
        if mode = "stale" then state.sourceUrl += "?replacement"
        if mode = "disabled" then state.sourceTransitions = false
        if mode = "missing" then state.adClockTimeline = twitchAdClockTimeline(mixedEpochSource().Replace("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:04.000000Z", "# missing anchor"))
        if mode = "duplicate"
            entries = state.segments
            entries.Push(entries[2])
            state.segments = entries
        end if
        if mode = "window"
            window = state.window
            entries = window.segments
            entry = entries[2]
            entry.epoch += 1
            entries[2] = entry
            window.segments = entries
            state.window = window
        end if
        check(twitchAdClockServerPublication(state, pub) = invalid, "optional metadata owner/selected proof refused " + mode)
    end for
end sub

sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_AD_CLOCK_FAIL: __MARKER__ " + message
    end if
end sub

sub testNativeArithmetic()
    values = [1767225600#, 1767225600.125#, 1767225600.999999#, 1767225601.000001#, 1791583200.238999#, 1791583200.239#]
    goldens = [1767225600000000&, 1767225600125000&, 1767225600999999&, 1767225601000001&, 1791583200238999&, 1791583200239000&]
    for i = 0 to values.Count() - 1
        check(twitchAdClockUtc({epoch: 1, video: values[i]}) = goldens[i], "independent exact UTC microsecond golden " + i.ToStr())
    end for
    for each epoch in [0, 2, -1, 1.0, "1", invalid]
        check(twitchAdClockUtc({epoch: epoch, video: 1767225600#}) = invalid, "unproven/noninteger epoch refuses UTC")
    end for
    imprecise! = 1767225600#
    check(type(imprecise!, 3) = "Float", "negative control is actual single precision")
    for each video in [imprecise!, -1#, 2147483648#, "1767225600", invalid]
        check(twitchAdClockUtc({epoch: 1, video: video}) = invalid, "imprecise or invalid rendered value refuses UTC")
    end for
    check(twitchAdClockUtc(invalid) = invalid, "missing native frame refused")
    check(twitchAdClockUtc({epoch: 1}) = invalid, "missing native video track refused")
end sub

function sourceText() as string
    q = Chr(34)
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:2" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:41" + Chr(10)
    text += "#EXT-X-MAP:URI=" + q + "init.mp4" + q + Chr(10)
    text += "#EXT-X-DATERANGE:ID=" + q + "PRIVATE_ID" + q + ",CLASS=" + q + "twitch-stitched-ad" + q + ",START-DATE=" + q + "2026-01-01T00:00:01.500001Z" + q + ",DURATION=4.250001,X-TV-TWITCH-AD-POD-LENGTH=2,X-TV-TWITCH-AD-POD-POSITION=0,X-TV-TWITCH-AD-URL=" + q + "https://private.invalid/SECRET" + q + Chr(10)
    for i = 0 to 3
        text += "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:0" + (i * 2).ToStr() + ".000000Z" + Chr(10)
        text += "#EXTINF:2.000," + Chr(10) + "private-segment-" + i.ToStr() + ".m4s" + Chr(10)
    end for
    return text
end function

function publication() as object
    segments = []
    for i = 0 to 3
        segments.Push({sequence: 41 + i, duration: "2.000", durationUs: 2000000, videoId: "live-" + (i * 2 + 3).ToStr(), audioId: "live-" + (i * 2 + 4).ToStr()})
    end for
    return {generation: 1, mediaSequence: 41, targetDuration: 2, initVideoId: "live-1", initAudioId: "live-2", durationUs: 8000000, sourceOffsetUs: 2000000, ended: false, segments: segments}
end function

sub testSourceProjection()
    m.config = {sourceDelaySeconds: 2, metadata: {bandwidth: 6000000, width: 1920, height: 1080, frameRate: "60.000", videoCodec: "avc1.64002a"}}
    text = sourceText()
    timeline = twitchAdClockTimeline(text)
    check(twitchAdClockTimelineValid(timeline), "actual explicit PDT media timeline accepted")
    if timeline = invalid then return
    check(timeline.segments.Count() = 4 and timeline.cues.Count() = 1, "four anchors/one exact ad range")
    for i = 0 to 3
        entry = timeline.segments[i]
        check(entry.Count() = 5 and entry.sequence = 41 + i and entry.epoch = 0 and entry.startUs = 1767225600000000& + i * 2000000&, "independent source sequence/UTC golden")
    end for
    cue = timeline.cues[0]
    check(cue.startUs = 1767225601500001& and cue.durationUs = 4250001& and cue.endUs = 1767225605750002&, "exact independent fractional ad timing")
    safe = FormatJson(timeline)
    check(safe.InStr("PRIVATE_ID") < 0 and safe.InStr("SECRET") < 0 and safe.InStr("private-segment") < 0 and safe.InStr("init.mp4") < 0, "provider URI/identity/tracking never retained")
    pub = publication()
    check(loopbackPublicationValid(pub), "actual unchanged publication validator accepts golden")
    original = FormatJson(pub)
    projection = twitchAdClockProject(timeline, pub, 0)
    check(projection <> invalid, "matching exact source epoch projects")
    check(twitchAdClockProject(timeline, pub, 1) = invalid, "wrong epoch projection refused")
    canonical = loopbackManifest("video", pub).ToAsciiString()
    projected = twitchAdClockManifest("video", pub, projection).ToAsciiString()
    check(projected.InStr("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00.000000Z") >= 0, "actual manifest has exact first anchor")
    check(projected.InStr("START-DATE=" + Chr(34) + "2026-01-01T00:00:01.500001Z" + Chr(34) + ",DURATION=4.250001") >= 0, "projected metadata round-trips exact fractional cue")
    check(projected.InStr("PRIVATE_ID") < 0 and projected.InStr("SECRET") < 0, "projected manifest has sanitized synthetic cue identity only")
    check(FormatJson(pub) = original and loopbackManifest("video", pub).ToAsciiString() = canonical, "canonical publication/bytes remain unchanged")
    check(twitchAdClockManifest("master", pub, projection).ToAsciiString() = loopbackManifest("master", pub).ToAsciiString(), "master remains canonical")
    reload = twitchAdClockTimeline(projected)
    check(reload <> invalid and twitchAdClockTimelineValid(reload), "actual projected media manifest can supply trusted cue Task")
    if reload <> invalid then check(FormatJson(reload.cues) = FormatJson(timeline.cues), "exact five-field cues round-trip")
    mutated = ParseJson(FormatJson(projection))
    mutated.segments[0].date = "2026-01-01T00:00:01.000000Z"
    check(twitchAdClockManifest("video", pub, mutated).ToAsciiString() = canonical, "projection mutation refuses overlay and preserves ordinary playback")
    short = publication()
    short.segments[0].durationUs = 1999999
    check(twitchAdClockProject(timeline, short, 0) = invalid, "duration mismatch refuses projection")
    wrong = publication()
    wrong.segments[0].sequence = 40
    check(twitchAdClockProject(timeline, wrong, 0) = invalid, "missing selected sequence refuses projection")
    for each bad in [text.Replace("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00.000000Z", "# no anchor"), text.Replace("#EXT-X-MEDIA-SEQUENCE:41", "# no sequence"), text.Replace("00:00:02.000000Z", "00:00:01.999999Z"), text.Replace("#EXTINF:2.000,", "#EXTINF:bogus,"), text.Replace("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:02.000000Z", "#EXT-X-DISCONTINUITY")]
        candidate = twitchAdClockTimeline(bad)
        check(not twitchAdClockTimelineValid(candidate), "missing/malformed/overlap/discontinuity anchor refused")
    end for
    crlf = twitchAdClockTimeline(text.Replace(Chr(10), Chr(13) + Chr(10)))
    check(FormatJson(crlf) = FormatJson(timeline), "LF/CRLF source timeline is identical")
    state = {sourceUrl: "https://test.ttvnw.net/current.m3u8", closed: false, phase: "segment", epoch: 0}
    twitchAdClockCapture(state, "playlist", text, state.sourceUrl)
    check(twitchAdClockTimelineValid(state.adClockTimeline), "captured timeline validated")
    check(state.adClockSource = state.sourceUrl, "captured source binding exact")
    check(twitchAdClockPublication(state, pub) <> invalid, "actual current source feed sidecar publication")
    twitchAdClockCapture(state, "playlist", text, "https://test.ttvnw.net/old.m3u8")
    check(twitchAdClockPublication(state, pub) = invalid, "stale signed-source feed cannot bind a cue")
    state.closed = true
    twitchAdClockCapture(state, "playlist", text, state.sourceUrl)
    check(twitchAdClockPublication(state, pub) = invalid, "closed source cannot publish metadata")
end sub

sub testBoundaries()
    bounds = [{startUs: 1767225600000000&, endUs: 1767225602000000&}]
    check(twitchAdClockBoundsValid(bounds), "strict sanitized anchor bounds")
    check(twitchAdClockInBounds(1767225600000000&, bounds), "exact first frame anchor included")
    check(twitchAdClockInBounds(1767225601999999&, bounds), "last actual frame included")
    check(not twitchAdClockInBounds(1767225602000000&, bounds), "half-open end refuses future frame")
    check(not twitchAdClockInBounds(1767225599999999&, bounds), "unanchored old frame refused")
    for each bad in [[{startUs: 0, endUs: 2000000, secret: "TOKEN"}], [{startUs: 1.0, endUs: 2000000}], [{startUs: 0, endUs: 0}], [{startUs: 0, endUs: 10000001}], [{startUs: 0, endUs: 2000000}, {startUs: 1999999, endUs: 4000000}], "raw body", invalid]
        check(not twitchAdClockBoundsValid(bad), "malformed/noninteger/secret/overlap bounds rejected")
    end for
    check(adMetadataSource("https://test.ttvnw.net/live.m3u8?sig=abc", "direct") = "https://test.ttvnw.net/live.m3u8?sig=abc", "exact trusted signed media source retained only inside Task")
    check(adMetadataSource("http://127.0.0.1:54321/master.m3u8", "loopback") = "http://127.0.0.1:54321/video.m3u8", "positively selected own loopback video path")
    for each bad in ["http://127.0.0.1:80/master.m3u8", "http://localhost:54321/master.m3u8", "http://127.0.0.1:54321/arbitrary", "http://127.0.0.1:54321/master.m3u8?secret=x", "https://test.ttvnw.net/live.m3u8#fragment", "https://test.ttvnw.net@evil.invalid/a", "https://evil.invalid/a"]
        check(adMetadataSource(bad, "direct") = "" and adMetadataSource(bad, "loopback") = "", "arbitrary/ambiguous URI rejected")
    end for
end sub

sub testHeaders()
    check(adMetadataHeaders([{ "Content-Length": "123" }], 200, 123), "exact complete identity response framing")
    check(adMetadataHeaders([{ "Content-Length": "123" }, { "Content-Encoding": "identity" }, { "Content-Range": "bytes 0-122/123" }], 206, 123), "complete exact finite range framing")
    for each bad in [[], [{ "Content-Length": "123" }, { "content-length": "123" }], [{ "Content-Length": "123" }, { "Location": "https://SECRET.invalid" }], [{ "Content-Length": "123" }, { "Transfer-Encoding": "chunked" }], [{ "Content-Length": "123" }, { "Content-Encoding": "gzip" }], [{ "Content-Length": "122" }], [{ "Content-Length": "123", "X": "duplicate-shape" }], [{ "Content-Length": "123" }, { "X-Bad": Chr(10) }], [{ "Content-Length": 123 }]]
        check(not adMetadataHeaders(bad, 200, 123), "malformed/redirect/duplicate/compressed/count/secret framing refused")
    end for
    check(not adMetadataHeaders([{ "Content-Length": "123" }, { "Content-Range": "bytes 0-122/124" }], 206, 123), "partial range cannot become trusted complete metadata")
    check(not adMetadataHeaders([{ "Content-Length": "123" }, { "Content-Range": "bytes 0-122/123" }], 200, 123), "unexpected Content-Range on full response refused")
    check(not adMetadataHeaders([{ "Content-Length": "123" }], 302, 123), "redirect response code cannot supply cues")
    check(not adMetadataHeaders([{ "Content-Length": "262145" }], 200, 262145), "retained framing count bound unchanged")
end sub

sub testSourceEpochAgreement()
    for each prefix in ["", "#EXT-X-DISCONTINUITY-SEQUENCE:27" + Chr(10)]
        source = sourceText().Replace("#EXT-X-MEDIA-SEQUENCE:41" + Chr(10), "#EXT-X-MEDIA-SEQUENCE:41" + Chr(10) + prefix)
        source = source.Replace("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:04.000000Z", "#EXT-X-DISCONTINUITY" + Chr(10) + "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:04.000000Z")
        for each suffix in ["08", "10"]
            source += "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:" + suffix + ".000000Z" + Chr(10) + "#EXTINF:2.000," + Chr(10) + "extra" + suffix + ".m4s" + Chr(10)
        end for
        original = nativeLiveParsePlaylist(source, "https://test.ttvnw.net/current.m3u8")
        observational = twitchAdClockTimeline(source)
        check(twitchAdClockTimelineValid(observational), "explicit original discontinuity source timeline is valid")
        for i = 0 to 3
            check(original.segments[i].epoch = observational.segments[i].epoch and original.segments[i].sequence = observational.segments[i].sequence and original.segments[i].durationUs = observational.segments[i].durationUs, "actual unchanged Core parser and sidecar agree on source epoch/seq/duration")
        end for
        pub = publication()
        selected = pub.segments
        selected.Shift(): selected.Shift()
        pub.segments = selected
        selectedSource = original.segments
        selectedSource.Shift(): selectedSource.Shift()
        original.segments = selectedSource
        actualSelected = nlWindow(original, 0&)
        check(twitchAdClockProject(observational, pub, actualSelected.epoch) <> invalid, "actual selected-window source epoch supports matching sidecar")
        check(twitchAdClockProject(observational, pub, 1&) = invalid or actualSelected.epoch = 1&, "native Video UTC epoch must not substitute for source-window epoch")
    end for
end sub
