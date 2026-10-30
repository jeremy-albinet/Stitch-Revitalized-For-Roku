' Production Fetch completion, Core, gate, Protocol and Server decisions run.
' boundary.brs supplies only native socket/decoder and completed-file primitives.
sub adFeedPlaylist(state as object, payload as string, nowMs as dynamic)
    m.adIO = [payload, true]
    state.op = { identity: "owned", kind: "playlist", url: state.sourceUrl, limit: 262144, phase: "get", deadline: nowMs + 6000&, transfer: { AsyncCancel: eiCancel } }
    state.ownInputFile = true
    event = { nativeType: "roUrlEvent", GetSourceIdentity: adIdentity, GetInt: adInt, GetResponseCode: adStatus, GetResponseHeadersArray: adHeaders, body: payload }
    checkEI(nativeLiveHandleUrlEvent(state, event, nowMs), "actual Fetch consumes validated completed playlist event")
    checkEI(state.phase <> "failed" and state.op = invalid and not state.ownInputFile and not m.adIO[1], "actual framing/feed/metadata capture cleans completed input")
    m.liveState = state
end sub

function adExpected(track as string, name as string, pub as object) as string
    canonical = m.corpus.manifests[name][track]
    output = ""
    index = 0
    for each line in canonical.Split(Chr(10))
        if line.Left(8) = "#EXTINF:"
            output += "#EXT-X-PROGRAM-DATE-TIME:" + m.adDates[CInt(pub.mediaSequence - 10&) + index] + Chr(10)
            if index = 0 then output += "#EXT-X-DATERANGE:ID=" + Chr(34) + "stitch-ad-1767225606006000" + Chr(34) + ",CLASS=" + Chr(34) + "twitch-stitched-ad" + Chr(34) + ",START-DATE=" + Chr(34) + "2026-01-01T00:00:06.006000Z" + Chr(34) + ",DURATION=6.006000" + Chr(10)
            index += 1
        end if
        if line <> "" then output += line + Chr(10)
    end for
    return output
end function

sub adSocket(state as object, track as string, method as string)
    incoming = CreateObject("roByteArray")
    incoming.FromAsciiString(eiRequest("/" + track + ".m3u8", method))
    m.io = [incoming, 0, CreateObject("roByteArray"), m.events, state.assets, [false], ""]
    m.connection = { io: m.io, GetCountRcvBuf: eiReceiveCount, IsReadable: eiReadable, Receive: eiReceive, IsWritable: eiWritable, Send: eiSend, eOK: eiSocketOk, NotifyReadable: eiNotify, NotifyWritable: eiNotify, Close: eiSocketClose }
    m.result.reason = "not_started"
    m.result.connectionClosed = false
end sub

sub adManifests(state as object, name as string)
    pub = m.currentPublication
    original = FormatJson(pub)
    entry = m.publications[pub.generation.ToStr()]
    checkEI(entry.adProjection <> invalid, "actual Server freezes verified mixed source timing")
    for each track in ["video", "audio"]
        expected = adExpected(track, name, pub)
        for each method in ["GET", "HEAD"]
            adSocket(state, track, method)
            checkEI(serveLiveRequest(m.requestClock), "actual Server serves projected track " + track + method)
            wire = m.io[2].ToAsciiString()
            headerEnd = wire.InStr(Chr(13) + Chr(10) + Chr(13) + Chr(10))
            checkEI(headerEnd >= 0 and wire.Left(15) = "HTTP/1.1 200 OK", "actual manifest response succeeds")
            checkEI(wire.InStr("Content-Length: " + expected.Len().ToStr() + Chr(13) + Chr(10)) >= 0, "HEAD/GET exact projected content length")
            if method = "GET"
                text = wire.Mid(headerEnd + 4)
                checkEI(text = expected, "complete independent PDT/cue/canonical manifest golden " + name + track)
                timeline = twitchAdClockTimeline(text)
                checkEI(twitchAdClockTimelineValid(timeline), "actual emitted timeline parser accepts source-verified local boundaries")
                checkEI(timeline.cues.Count() = 1 and timeline.cues[0].startUs = 1767225606006000& and timeline.cues[0].durationUs = 6006000&, "exact sanitized ad cue round-trips")
                for i = 0 to timeline.segments.Count() - 1
                    segment = timeline.segments[i]
                    checkEI(segment.epoch = pub.segments[i].epoch and segment.startUs = 1767225600000000& + (segment.sequence - 10&) * 2002000&, "exact independent segment UTC and local epoch")
                end for
                m.manifests += 1
            else
                checkEI(wire.Right(4) = Chr(13) + Chr(10) + Chr(13) + Chr(10), "manifest HEAD carries no body")
            end if
            closeLiveConnection()
            checkEI(m.activeGeneration = 0& and m.activeBody = invalid, "projected request retains and releases generation normally")
        end for
    end for
    checkEI(FormatJson(pub) = original and FormatJson(m.currentPublication) = original, "HTTP projection preserves immutable publication")
    entry = m.publications[pub.generation.ToStr()]
    originalProjection = entry.adProjection
    originalCue = originalProjection.cues[0]
    changed = { cues: [{ startUs: originalCue.startUs + 1&, endUs: originalCue.endUs + 1&, durationUs: originalCue.durationUs, podCount: originalCue.podCount, podPosition: originalCue.podPosition }], segments: [] }
    anchors = []
    for each originalAnchor in originalProjection.segments
        anchors.Push({ sequence: originalAnchor.sequence, epoch: originalAnchor.epoch, startUs: originalAnchor.startUs, durationUs: originalAnchor.durationUs, date: originalAnchor.date })
    end for
    changed.segments = anchors
    checkEI(twitchAdClockTimelineValid(changed), "seal mutation control remains valid optional timing shape")
    entry.adProjection = changed
    ' Keep original seal: tampered metadata may not replace accepted bytes.
    m.publications[pub.generation.ToStr()] = entry
    response = prepareLiveResponse({ track: "video", assetId: "", head: false, range: "" })
    checkEI(response.data.ToAsciiString() = loopbackManifest("video", pub).ToAsciiString(), "actual Server rejects changed frozen timing sidecar")
    closeLiveConnection()
    entry = m.publications[pub.generation.ToStr()]
    entry.adProjection = twitchAdClockServerPublication(state, pub)
    m.publications[pub.generation.ToStr()] = entry
end sub

sub adRolling()
    caseEI("mixed-source-local-PDT-cue-http-and-leases")
    state = preparedEI()
    checkEI(state.epoch = 27& and m.currentPublication.discontinuitySequence = 0&, "actual nonzero source epoch has independent local zero")
    adManifests(state, "initial")
    oldId = m.currentPublication.initVideoId
    held = nativeLiveAcquire(state, oldId)
    m.adHeldId = oldId
    for sequence = 13 to 18
        nowMs = (sequence - 12) * 3000&
        feedEI(state, "playlist", playlistEI(10, sequence - 9), nowMs)
        drainEI(state, nowMs)
        admitEI(state, nowMs)
        checkEI(state.epoch = 27& + state.localEpoch, "actual source and local epochs remain separately validated")
        if sequence = 13 then adManifests(state, "first-ad")
        if sequence = 16 then adManifests(state, "return")
        if sequence = 18 then adManifests(state, "rolled")
        checkEI(nlBodyDigest(held.data) = m.corpus.inits.content.video.sha256 and state.assets[nlAssetIndex(state, oldId)].leases = 1, "old leased initialization remains exact across projected boundaries")
    end for
    checkEI(state.initPairCount = 3 and state.segmentPairCount = 9 and m.decodeCount = 3, "metadata does not change decoder or conversion decisions")
    nativeLiveRelease(state, oldId)
    m.adHeldId = ""
    closeEI(state)
end sub

sub adReset()
    caseEI("same-map-timestamp-reset-keeps-exact-anchors")
    state = preparedEI()
    calls = m.decodeCount
    oldIds = FormatJson(state.initIds)
    feedEI(state, "playlist", playlistEI(10, 4, "pts"), 3000&)
    feedEI(state, "segment", bytesEI(m.corpus.ptsMedia.input), 3000&)
    nativeLiveAdvance(state, 3000&)
    nativeLiveAdvance(state, 3000&)
    admitEI(state, 3000&)
    checkEI(m.decodeCount = calls and FormatJson(state.initIds) = oldIds and m.currentPublication.segments[2].epoch = 1&, "same-map actual reset needs no invented initialization approval")
    entry = m.publications[m.currentGeneration.ToStr()]
    for each track in ["video", "audio"]
        text = twitchAdClockManifest(track, m.currentPublication, entry.adProjection).ToAsciiString()
        reloaded = twitchAdClockTimeline(text)
        checkEI(reloaded <> invalid and reloaded.segments[2].date = "2026-01-01T00:00:06.006000Z" and reloaded.segments[2].epoch = 1&, "actual reset boundary preserves exact source anchor in both tracks")
        id = m.currentPublication.segments[2].videoId
        if track = "audio" then id = m.currentPublication.segments[2].audioId
        body = nativeLiveAcquire(state, id)
        checkEI(nlBodyDigest(body.data) = m.corpus.ptsMedia[track].sha256, "reset TFDT/sample bytes remain independent golden")
        nativeLiveRelease(state, id)
        m.goldens += 1
    end for
    closeEI(state)
end sub

sub adOverlap()
    caseEI("ambiguous-UTC-is-optional-canonical-fallback")
    state = preparedEI()
    text = playlistEI(10, 4).Replace("00:00:06.006000Z", "00:00:04.000000Z")
    feedEI(state, "playlist", text, 3000&)
    checkEI(state.adClockTimeline = invalid and state.phase = "init-rotation", "actual valid media feed rejects ambiguous optional UTC only")
    drainEI(state, 3000&)
    admitEI(state, 3000&)
    entry = m.publications[m.currentGeneration.ToStr()]
    checkEI(entry.adProjection = invalid and state.initPairCount = 2, "optional failure never rejects valid changed initialization/media")
    for each track in ["video", "audio"]
        response = prepareLiveResponse({ track: track, assetId: "", head: false, range: "" })
        checkEI(response.data.ToAsciiString() = m.corpus.manifests["first-ad"][track], "actual Server preserves complete canonical manifest on ambiguous clock")
        closeLiveConnection()
    end for
    closeEI(state)
end sub

sub main()
    m.assertions = 0
    m.cases = []
    m.goldens = 0
    m.pairs = 0
    m.manifests = 0
    m.admissions = 0
    m.adDates = ["2026-01-01T00:00:00.000000Z", "2026-01-01T00:00:02.002000Z", "2026-01-01T00:00:04.004000Z", "2026-01-01T00:00:06.006000Z", "2026-01-01T00:00:08.008000Z", "2026-01-01T00:00:10.010000Z", "2026-01-01T00:00:12.012000Z", "2026-01-01T00:00:14.014000Z", "2026-01-01T00:00:16.016000Z"]
    m.corpus = ParseJson(ReadAsciiFile("pkg:/corpus.json"))
    try
        adRolling()
        adReset()
        adOverlap()
    catch error
        print "STITCH_AD_EPOCH_FAIL: __MARKER__ "; error.message
        return
    end try
    print "STITCH_AD_EPOCH_PASS: __MARKER__ "; FormatJson({ assertions: m.assertions, cases: m.cases.Count(), goldens: m.goldens, pairs: m.pairs, manifests: m.manifests, admissions: m.admissions })
end sub
