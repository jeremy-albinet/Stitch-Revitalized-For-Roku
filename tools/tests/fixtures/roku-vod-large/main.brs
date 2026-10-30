sub largeCheck(ok as boolean, label as string)
    m.assertions++
    if not ok then throw "vod-large-fixture:" + label
end sub

function largeBytes(name as string) as object
    print "STITCH_VOD_LARGE_STAGE: read " + name
    bytes = CreateObject("roByteArray")
    largeCheck(bytes.ReadFile("pkg:/" + name), "actual complete binary fixture loads")
    print "STITCH_VOD_LARGE_STAGE: loaded " + name
    return bytes
end function

sub largeReleased(state as object)
    largeCheck(state.input = invalid and state.chunk = invalid and state.video = invalid and state.audio = invalid and state.plan = invalid and state.tracks = invalid, "all source and conversion references released")
end sub

sub largeGolden(source as object, tracks as object, timing as object, expected as object)
    print "STITCH_VOD_LARGE_STAGE: plan"
    plan = rokuVodChunkPlan(source, tracks, timing)
    largeCheck(plan <> invalid, "actual greater4MiB complete input is admitted")
    print "STITCH_VOD_LARGE_STAGE: planned"
    largeCheck(plan.bytes = 9418736 and plan.pairs = expected.pairs and plan.events = expected.events and plan.samples = expected.pairs * 3 and plan.spans.Count() = 3, "observed-size sparse synthetic whole plan retains every pair and metadata root")
    cursor = 0
    for each span in plan.spans
        largeCheck(span.start = cursor and span.length <= 4194304 and span.pairs <= 20 and span.samples <= 8192, "contiguous unchanged Bulk call envelope")
        cursor += span.length
    end for
    largeCheck(cursor = source.Count(), "all whole input bytes have one span owner")
    rejected = false
    try
        unused = nativeDemuxBulkFragment(source, tracks, "video")
    catch error
        rejected = true
    end try
    largeCheck(rejected, "unchanged Bulk still refuses greater4MiB whole calls")
    state = rokuVodChunkBegin(source, tracks, plan)
    print "STITCH_VOD_LARGE_STAGE: began"
    largeCheck(state.phase = "working", "actual large chunk owner begins")
    steps = 0
    while state.phase = "working" and steps < 256
        result = rokuVodChunkStep(state, false)
        print "STITCH_VOD_LARGE_STAGE: step " + steps.ToStr()
        largeCheck(result.phase = "working" or result.phase = "complete", "actual bounded large conversion phase succeeds")
        if result.phase = "working" then largeCheck(result.pair = invalid, "large partial pair never published")
        steps++
    end while
    largeCheck(result.phase = "complete" and steps = 6 and result.pair <> invalid, "large conversion returns one complete atomic pair")
    largeReleased(state)
    pair = result.pair
    largeCheck(pair.video.Count() > 4194304 and pair.video.Count() = expected["videoBytes"] and nbBulkDigest(pair.video) = expected["videoDigest"], "every large video byte payload absolute timing flags and metadata matches independent golden")
    largeCheck(pair.audio.Count() = expected["audioBytes"] and nbBulkDigest(pair.audio) = expected["audioDigest"], "every large audio byte payload absolute timing and flags matches independent golden")
    largeCheck(pair.video.Count() + pair.audio.Count() <= 16777216 and nbBulkDigest(source) = expected["inputDigest"], "aggregate profile and exact original source remain unchanged")
    largeCheck(rokuVodChunkStep(state, false).pair = invalid and rokuVodChunkClose(state), "large output only transfers once and closes")
end sub

sub largePlanning(tracks as object, timing as object)
    exact = largeBytes("maximum.bin")
    largeCheck(exact.Count() = 12582912 and rokuVodChunkPlan(exact, tracks, timing) <> invalid, "exact12MiB complete input admitted")
    exact = invalid
    beyond = largeBytes("oversize.bin")
    largeCheck(beyond.Count() = 12582913 and rokuVodChunkPlan(beyond, tracks, timing) = invalid, "complete whole input above12MiB refused")
    beyond = invalid
    pair = largeBytes("one-pair.bin")
    largeCheck(pair.Count() > 4194304 and rokuVodChunkPlan(pair, tracks, timing) = invalid, "one indivisible pair above unchanged Bulk span refuses")
    pair = invalid
    spans = []
    for i = 0 to 127
        spans.Push({start: i * 16, length: 16, pairs: 1, samples: 1})
    end for
    shape = {version: 1, spans: spans, timing: timing, tracks: tracks, digest: "0000000000000000000000000000000000000000000000000000000000000000", bytes: 2048, pairs: 128, samples: 128, events: 0}
    accepted = true
    try
        rvdcPlanShape(shape)
    catch error
        accepted = false
    end try
    largeCheck(accepted, "actual structural validator accepts128 finite contiguous spans")
    ' This is the structural envelope only; ChunkBegin still reparses exact bytes.
    spans = shape.spans
    spans.Push({start: 2048, length: 16, pairs: 1, samples: 1})
    shape.spans = spans
    shape.bytes = 2064
    rejected = false
    try
        rvdcPlanShape(shape)
    catch error
        rejected = true
    end try
    largeCheck(rejected, "structural envelope refuses129 spans")
    source = largeBytes("media.bin")
    plan = rokuVodChunkPlan(source, tracks, timing)
    for stopAt = 1 to 2
        state = rokuVodChunkBegin(source, tracks, plan)
        for stepNo = 1 to stopAt
            result = rokuVodChunkStep(state, false)
            largeCheck(result.phase = "working" and result.pair = invalid, "large cancellation reaches actual bounded track phase")
        end for
        result = rokuVodChunkStep(state, true)
        largeCheck(result.phase = "cancelled" and result.pair = invalid, "stop after large video or audio phase emits no partial pair")
        largeReleased(state)
        largeCheck(rokuVodChunkClose(state), "cancelled large owner acknowledges cleanup")
    end for
    ' Genuine owned ByteArrays test defensive aggregate admission independently
    ' of each track cap. No Count/digest/native conversion function is replaced.
    state = rokuVodChunkBegin(source, tracks, plan)
    video = CreateObject("roByteArray")
    audio = CreateObject("roByteArray")
    video.SetResize(8388608, true)
    audio.SetResize(8388608, true)
    video[8388607] = 0
    audio[8388607] = 0
    largeCheck(video.Count() = 8388608 and audio.Count() = 8388608, "real aggregate boundary buffers have exact counts")
    state.video = video
    state.audio = audio
    result = rokuVodChunkStep(state, false)
    largeCheck(result.phase = "failed" and result.pair = invalid and result.reason = "conversion_failed", "combined outputs above16MiB refuse despite each track below16MiB")
    largeReleased(state)
    largeCheck(rokuVodChunkClose(state), "aggregate refusal retains exact close acknowledgement")
end sub

sub main()
    m.assertions = 0
    try
        init = largeBytes("init.bin")
        tracks = nativeDemuxBulkInspectInit(init)
        timing = rokuVodInitTiming(init)
        largeCheck(tracks <> invalid and timing <> invalid, "actual init creates unchanged track and timing maps")
        mode = "__MODE__"
        if mode = "golden"
            expected = ParseJson(ReadAsciiFile("pkg:/expected.json"))
            largeGolden(largeBytes("media.bin"), tracks, timing, expected)
        else if mode = "planning"
            largePlanning(tracks, timing)
        end if
        print "STITCH_VOD_LARGE_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 0})
    catch error
        print "STITCH_VOD_LARGE_FAIL: __MARKER__ " + error.message
        print "STITCH_VOD_LARGE_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 1})
    end try
end sub
