' Pure production Protocol/Common bodies; no Core/Server/URL/decoder stand-ins.
sub checkEpoch(ok as boolean, message as string)
    if not ok then throw "epoch-fixture: " + message
    m.assertions += 1
end sub

function assetEpoch(serial as dynamic, legacy = false as boolean) as string
    if legacy then return "live-" + serial.ToStr()
    return "live-0123456789abcdef0123456789abcdef-" + serial.ToStr()
end function

function segmentEpoch(sequence as dynamic, epoch as dynamic, initVideo as integer, initAudio as integer, video as integer, audio as integer, duration = "2.002000" as string, micros = 2002000 as integer) as object
    return { sequence: sequence, duration: duration, durationUs: micros, videoId: assetEpoch(video), audioId: assetEpoch(audio), epoch: epoch, initVideoId: assetEpoch(initVideo), initAudioId: assetEpoch(initAudio) }
end function

function publicationEpoch(name = "content-ad-content" as string) as object
    segments = [segmentEpoch(10&, 0&, 1, 2, 7, 8), segmentEpoch(11&, 1&, 3, 4, 9, 10), segmentEpoch(12&, 2&, 1, 2, 11, 12)]
    generation = 1&
    ended = false
    if name = "short-boundaries"
        segments = []
        pairs = [[1, 2], [3, 4], [5, 6], [1, 2], [3, 4]]
        for i = 0 to 4
            segments.Push(segmentEpoch(20& + i, 3& + i, pairs[i][0], pairs[i][1], 7 + i * 2, 8 + i * 2, "1.200000", 1200000))
        end for
    else if name = "rolled-ad"
        generation = 2&
        segments = [segmentEpoch(11&, 1&, 3, 4, 9, 10), segmentEpoch(12&, 2&, 1, 2, 11, 12), segmentEpoch(13&, 2&, 1, 2, 13, 14)]
    else if name = "rolled-return"
        generation = 3&
        segments = [segmentEpoch(12&, 2&, 1, 2, 11, 12), segmentEpoch(13&, 2&, 1, 2, 13, 14), segmentEpoch(14&, 2&, 1, 2, 15, 16)]
    else if name = "same-pair-discontinuity"
        segments = [segmentEpoch(30&, 0&, 1, 2, 7, 8, "2.000000", 2000000), segmentEpoch(31&, 1&, 1, 2, 9, 10, "2.000000", 2000000), segmentEpoch(32&, 1&, 1, 2, 11, 12, "2.000000", 2000000)]
    else if name = "maximum-identities"
        generation = 4294967295&
        segments = [segmentEpoch(4294967293&, 4294967294&, 1, 2, 7, 8, "2.000000", 2000000), segmentEpoch(4294967294&, 4294967295&, 3, 4, 9, 10, "2.000000", 2000000), segmentEpoch(4294967295&, 4294967295&, 3, 4, 11, 12, "2.000000", 2000000)]
    else if name = "ended-single"
        segments = [segmentEpoch(10&, 0&, 1, 2, 7, 8, "0.250000", 250000)]
        ended = true
    else if name = "rounded-fraction"
        segments = [segmentEpoch(10&, 0&, 1, 2, 7, 8, "2.499999", 2499999), segmentEpoch(11&, 1&, 3, 4, 9, 10, "2.499999", 2499999), segmentEpoch(12&, 2&, 1, 2, 11, 12, "2.499999", 2499999)]
    else if name = "legacy-finite" or name = "legacy-session"
        segments = []
        for i = 0 to 2
            segments.Push({ sequence: 10& + i, duration: "2.000000", durationUs: 2000000, videoId: assetEpoch(3 + i * 2, name = "legacy-finite"), audioId: assetEpoch(4 + i * 2, name = "legacy-finite") })
        end for
        return { generation: generation, mediaSequence: 10&, targetDuration: 2, initVideoId: assetEpoch(1, name = "legacy-finite"), initAudioId: assetEpoch(2, name = "legacy-finite"), durationUs: 6000000, sourceOffsetUs: 0&, ended: false, segments: segments }
    end if
    total = 0&
    for each segment in segments
        total += segment.durationUs
    end for
    first = segments[0]
    return { version: 2, discontinuitySequence: first.epoch, generation: generation, mediaSequence: first.sequence, targetDuration: 2, initVideoId: first.initVideoId, initAudioId: first.initAudioId, durationUs: total, sourceOffsetUs: 0&, ended: ended, segments: segments }
end function

sub rejectedEpoch(pub as object, label as string)
    checkEpoch(not loopbackPublicationValid(pub), "strict publication rejects " + label)
    checkEpoch(loopbackManifest("video", pub) = invalid and loopbackManifest("audio", pub) = invalid, "invalid publication emits neither track " + label)
    checkEpoch(loopbackPublicationAssets(pub) = invalid, "invalid publication advertises no assets " + label)
    m.rejections += 1
end sub

sub goldenEpoch(name as string)
    pub = publicationEpoch(name)
    checkEpoch(loopbackPublicationValid(pub), "valid publication " + name)
    for each track in ["video", "audio"]
        body = loopbackManifest(track, pub)
        checkEpoch(body <> invalid, "real manifest emitted " + name + " " + track)
        expected = ReadAsciiFile("pkg:/goldens/" + name + "-" + track + ".m3u8")
        checkEpoch(body.ToAsciiString() = expected and body.Count() = expected.Len(), "literal complete byte golden " + name + " " + track)
        checkEpoch(body.Count() <= 16384, "bounded ASCII manifest " + name + " " + track)
        m.goldens += 1
    end for
    records = loopbackPublicationAssets(pub)
    checkEpoch(type(records) = "roArray" and records.Count() <= 64, "validated deduplicated assets " + name)
    seen = {}
    for each record in records
        checkEpoch(loopbackKeys(record, ["id", "track"]) and (record.track = "video" or record.track = "audio"), "exact asset record shape " + name)
        checkEpoch(not seen.DoesExist(record.id), "asset record unique " + name)
        seen[record.id] = record.track
    end for
    checkEpoch(seen[pub.initVideoId] = "video" and seen[pub.initAudioId] = "audio", "initial complete pair advertised " + name)
    for each segment in pub.segments
        checkEpoch(seen[segment.videoId] = "video" and seen[segment.audioId] = "audio", "every media pair advertised " + name)
        if pub.DoesExist("version") then checkEpoch(seen[segment.initVideoId] = "video" and seen[segment.initAudioId] = "audio", "every epoch init pair advertised " + name)
    end for
    if name = "content-ad-content" then checkEpoch(records.Count() = 10, "old returning init pair deduplicated")
    if name = "short-boundaries" then checkEpoch(records.Count() = 16, "all three reused complete init pairs retained")
    if name = "same-pair-discontinuity" then checkEpoch(records.Count() = 8, "same-pair PTS discontinuity remains legal")
    m.cases += 1
    print "STITCH_ROKU_EPOCH_CASE: " + name
end sub

sub negativeEpoch()
    controls = ["missing-version", "version-zero", "version-one", "version-unknown", "version-float", "unknown-top-key", "missing-top-key", "disc-negative", "disc-float", "disc-overflow", "disc-first-mismatch", "generation-zero", "generation-float", "generation-overflow", "sequence-negative", "sequence-overflow", "sequence-last-overflow", "sequence-float", "target-one", "target-ten", "target-float", "sum-mismatch", "sum-overflow", "ended-string", "segments-empty", "segments-type", "segments-nine", "top-init-mismatch", "top-legacy-id", "top-other-session", "offset-negative", "offset-float", "offset-overflow", "offset-delay-floor", "short-live", "epoch-backward", "epoch-jump", "epoch-negative", "epoch-float", "epoch-overflow", "same-epoch-map-change", "partial-video-pair", "partial-audio-pair", "init-track-collision", "init-media-collision", "media-duplicate", "media-track-collision", "media-other-session", "media-legacy-id", "segment-gap", "segment-float", "segment-unknown-key", "segment-missing-key", "duration-half-second", "duration-mismatch", "duration-exponent", "duration-negative", "duration-newline", "duration-extra-precision", "duration-zero"]
    for each label in controls
        pub = publicationEpoch()
        checkEpoch(loopbackPublicationValid(pub), "typed valid baseline before " + label)
        segments = pub.segments
        segment = segments[1]
        if label = "missing-version" then pub.Delete("version")
        if label = "version-zero" then pub.version = 0
        if label = "version-one" then pub.version = 1
        if label = "version-unknown" then pub.version = 3
        if label = "version-float" then pub.version = 2.0#
        if label = "unknown-top-key" then pub.tracking = "forbidden"
        if label = "missing-top-key" then pub.Delete("durationUs")
        if label = "disc-negative" then pub.discontinuitySequence = -1&
        if label = "disc-float" then pub.discontinuitySequence = 0.0#
        if label = "disc-overflow" then pub.discontinuitySequence = 4294967296&
        if label = "disc-first-mismatch" then pub.discontinuitySequence = 1&
        if label = "generation-zero" then pub.generation = 0
        if label = "generation-float" then pub.generation = 1.0#
        if label = "generation-overflow" then pub.generation = 4294967296&
        if label = "sequence-negative" then pub.mediaSequence = -1&
        if label = "sequence-overflow" then pub.mediaSequence = 4294967296&
        if label = "sequence-last-overflow"
            pub.mediaSequence = 4294967294&
            for i = 0 to 2
                item = segments[i]
                item.sequence = pub.mediaSequence + i
                segments[i] = item
            end for
            segment = segments[1]
        end if
        if label = "sequence-float" then pub.mediaSequence = 10.0#
        if label = "target-one" then pub.targetDuration = 1
        if label = "target-ten" then pub.targetDuration = 10
        if label = "target-float" then pub.targetDuration = 2.0#
        if label = "sum-mismatch" then pub.durationUs += 1&
        if label = "sum-overflow" then pub.durationUs = 80000001&
        if label = "ended-string" then pub.ended = "false"
        if label = "top-init-mismatch" then pub.initVideoId = assetEpoch(5)
        if label = "top-legacy-id" then pub.initVideoId = "live-1"
        if label = "top-other-session" then pub.initAudioId = "live-ffffffffffffffffffffffffffffffff-2"
        if label = "offset-negative" then pub.sourceOffsetUs = -1&
        if label = "offset-float" then pub.sourceOffsetUs = 0.0#
        if label = "offset-overflow" then pub.sourceOffsetUs = 4294967296&
        if label = "offset-delay-floor" then m.config = { sourceDelaySeconds: 1 }
        if label = "epoch-jump" then segment.epoch = 2&
        if label = "epoch-negative" then segment.epoch = -2&
        if label = "epoch-float" then segment.epoch = 1.0#
        if label = "epoch-overflow" then segment.epoch = 4294967296&
        if label = "same-epoch-map-change" then segment.epoch = 0&
        if label = "partial-video-pair" then segment.initVideoId = assetEpoch(1)
        if label = "partial-audio-pair" then segment.initAudioId = assetEpoch(2)
        if label = "init-track-collision" then segment.initVideoId = assetEpoch(2)
        if label = "init-media-collision" then segment.initVideoId = assetEpoch(7)
        if label = "media-duplicate" then segment.videoId = assetEpoch(7)
        if label = "media-track-collision" then segment.audioId = segment.videoId
        if label = "media-other-session" then segment.videoId = "live-ffffffffffffffffffffffffffffffff-9"
        if label = "media-legacy-id" then segment.videoId = "live-9"
        if label = "segment-gap" then segment.sequence = 12&
        if label = "segment-float" then segment.sequence = 11.0#
        if label = "segment-unknown-key" then segment.url = "forbidden"
        if label = "segment-missing-key" then segment.Delete("initAudioId")
        if label = "duration-half-second"
            segment.duration = "2.500000"
            segment.durationUs = 2500000
            pub.durationUs += 498000
        end if
        if label = "duration-mismatch" then segment.durationUs += 1
        if label = "duration-exponent" then segment.duration = "2e0"
        if label = "duration-negative" then segment.duration = "-2.002"
        if label = "duration-newline" then segment.duration = "2.002" + Chr(10)
        if label = "duration-extra-precision" then segment.duration = "2.0020000"
        if label = "duration-zero" then segment.duration = "0.000000"
        segments[1] = segment
        pub.segments = segments
        if label = "epoch-backward"
            item = segments[2]
            item.epoch = 0&
            segments[2] = item
            pub.segments = segments
        end if
        if label = "same-epoch-map-change"
            item = segments[2]
            item.epoch = 1&
            segments[2] = item
            pub.segments = segments
        end if
        if label = "segments-empty" then pub.segments = []
        if label = "segments-type" then pub.segments = {}
        if label = "segments-nine"
            for i = 3 to 8
                segments.Push(segmentEpoch(10& + i, 2&, 1, 2, 11 + i * 2, 12 + i * 2))
            end for
            pub.segments = segments
            pub.durationUs = 18018000&
        end if
        if label = "short-live" then pub = publicationEpoch("ended-single")
        if label = "short-live" then pub.ended = false
        rejectedEpoch(pub, label)
        m.config = { sourceDelaySeconds: 0 }
    end for
    for each field in ["version", "discontinuitySequence", "generation", "mediaSequence", "targetDuration", "durationUs", "sourceOffsetUs", "ended", "initVideoId", "initAudioId"]
        pub = publicationEpoch()
        checkEpoch(loopbackPublicationValid(pub), "valid baseline before wrong top-level type " + field)
        pub[field] = []
        rejectedEpoch(pub, "wrong top-level type " + field)
    end for
    for each field in ["sequence", "duration", "durationUs", "videoId", "audioId", "epoch", "initVideoId", "initAudioId"]
        pub = publicationEpoch()
        segments = pub.segments
        segment = segments[1]
        segment[field] = {}
        segments[1] = segment
        pub.segments = segments
        rejectedEpoch(pub, "wrong segment type " + field)
    end for
    for each sourceDelay in [-1, 61, 0.0#]
        pub = publicationEpoch()
        m.config = { sourceDelaySeconds: sourceDelay }
        rejectedEpoch(pub, "invalid configured source delay")
    end for
    m.config = { sourceDelaySeconds: 0 }
    m.cases += 1
    print "STITCH_ROKU_EPOCH_CASE: strict-malformed"
end sub

sub main()
    m.assertions = 0
    m.cases = 0
    m.goldens = 0
    m.rejections = 0
    m.config = { sourceDelaySeconds: 0 }
    try
        for each name in ["legacy-finite", "legacy-session", "content-ad-content", "short-boundaries", "rolled-ad", "rolled-return", "same-pair-discontinuity", "maximum-identities", "ended-single", "rounded-fraction"]
            goldenEpoch(name)
        end for
        negativeEpoch()
        checkEpoch(loopbackPublicationValid(invalid) = false and loopbackPublicationAssets(invalid) = invalid, "invalid input fails closed")
        checkEpoch(loopbackManifest("foreign", publicationEpoch()) = invalid and loopbackEpochManifest("foreign", publicationEpoch()) = invalid, "unknown track emits nothing")
        checkEpoch(loopbackAsciiBuffer(String(16385, "a")) = invalid, "ASCII output ceiling remains finite")
        print "STITCH_ROKU_EPOCH_PASS: __MARKER__ cases="; m.cases; " assertions="; m.assertions; " goldens="; m.goldens; " rejections="; m.rejections
    catch e
        print "STITCH_ROKU_EPOCH_FAIL: "; e.message
    end try
end sub
