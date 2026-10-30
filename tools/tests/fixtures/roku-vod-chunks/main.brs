sub checkVodChunks(ok as boolean, message as string)
    if not ok then throw "vod-chunks-fixture: " + message
    m.assertions += 1
end sub

function bytesVodChunks(hex as string) as object
    data = CreateObject("roByteArray")
    data.FromHexString(hex)
    return data
end function

sub goldenVodChunks(data as object, expected as object, message as string)
    checkVodChunks(data.Count() = expected.count, message + " byte count")
    checkVodChunks(nbBulkDigest(data) = expected.sha256, message + " complete digest")
    checkVodChunks(LCase(data.ToHexString()) = expected.hex, message + " every byte")
end sub

sub releasedVodChunks(state as object)
    checkVodChunks(state.input = invalid and state.chunk = invalid and state.video = invalid and state.audio = invalid, "all owned byte buffers released")
    checkVodChunks(state.plan = invalid and state.tracks = invalid, "plan and source identity released")
end sub

' Deliberate negative control only; called exclusively by a mutated temporary
' production copy. It changes one absolute tfdt tick and nothing else.
sub rewriteVodChunksTime(data as object)
    ctx = nbContext()
    for each atom in nbBoxes(data, 0, data.Count(), ctx)
        if atom.kind = "moof"
            for each child in nbBoxes(data, atom.body, atom.finish, ctx)
                if child.kind = "traf"
                    for each part in nbBoxes(data, child.body, child.finish, ctx)
                        if part.kind = "tfdt"
                            at = part.body + 7
                            if data[part.body] = 1 then at += 4
                            data[at] = (data[at] + 1) mod 256
                            return
                        end if
                    end for
                end if
            end for
        end if
    end for
end sub

function convertVodChunks(item as object, timing as object, tracks as object, suppliedPlan = invalid as dynamic) as object
    source = bytesVodChunks(item.input.hex)
    plan = suppliedPlan
    if plan = invalid then plan = rokuVodChunkPlan(source, tracks, timing)
    checkVodChunks(plan <> invalid, "accepted synthetic whole input")
    state = rokuVodChunkBegin(source, tracks, plan)
    checkVodChunks(state.phase = "working", "actual validated begin")
    steps = 0
    result = invalid
    while state.phase = "working" and steps < 15
        beforeIndex = state.index
        beforeTrack = state.track
        result = rokuVodChunkStep(state, false)
        steps += 1
        checkVodChunks(result.phase <> "failed" and result.phase <> "cancelled", "bounded conversion succeeds")
        if result.phase = "working"
            if beforeTrack = "video"
                checkVodChunks(state.index = beforeIndex and state.track = "audio", "one track only per step")
            else
                checkVodChunks(state.index = beforeIndex + 1 and state.track = "video" and state.chunk = invalid, "one complete chunk and scratch release")
            end if
            checkVodChunks(result.pair = invalid, "no partial pair returned")
        end if
    end while
    checkVodChunks(result.phase = "complete" and result.reason = "" and steps = plan.spans.Count() * 2, "fresh complete pair at exact bounded step count")
    releasedVodChunks(state)
    goldenVodChunks(result.pair.video, item.video, "video golden")
    goldenVodChunks(result.pair.audio, item.audio, "audio golden")
    goldenVodChunks(source, item.input, "caller input remains unchanged")
    again = rokuVodChunkStep(state, false)
    checkVodChunks(again.phase = "complete" and again.pair = invalid, "completed pair transferred only once")
    checkVodChunks(rokuVodChunkClose(state) and state.closed, "idempotent terminal close")
    checkVodChunks(rokuVodChunkClose(state), "second terminal close")
    return result.pair
end function

sub main()
    m.assertions = 0
    m.cases = 0
    try
        corpus = ParseJson(ReadAsciiFile("pkg:/corpus.json"))
        mode = "__MODE__"
        init = bytesVodChunks(corpus.init.hex)
        timing = rokuVodInitTiming(init)
        tracks = nativeDemuxBulkInspectInit(init)
        checkVodChunks(timing <> invalid and timing.Count() = 2, "actual clear init timing")
        checkVodChunks(timing[0].id = 7& and timing[0].kind = "video" and timing[0].timescale = 1000000& and timing[0].duration = 1000&, "actual video mdhd and trex")
        checkVodChunks(timing[1].id = 8& and timing[1].kind = "audio" and timing[1].timescale = 48000& and timing[1].duration = 96&, "actual audio mdhd and trex")
        goldenVodChunks(init, corpus.init, "init immutable")
        for each item in corpus.initNegative
            checkVodChunks(rokuVodInitTiming(bytesVodChunks(item.input.hex)) = invalid, "malformed init " + item.name)
        end for
        m.cases += 1
        print "STITCH_VOD_CHUNKS_CASE: init-timing-defaults-and-refusals"

        if mode = "goldens"
        source = bytesVodChunks(corpus.media.input.hex)
        plan = rokuVodChunkPlan(source, tracks, timing)
        checkVodChunks(plan <> invalid and plan.pairs = 95 and plan.events = 5 and plan.samples = 285 and plan.spans.Count() = 5, "full 95-pair 5-emsg plan")
        cursor = 0
        for index = 0 to 4
            span = plan.spans[index]
            checkVodChunks(span.start = cursor and span.length > 0 and span.length <= 4194304 and span.samples <= 8192, "contiguous bounded chunk " + index.ToStr())
            wanted = 20
            if index = 4 then wanted = 15
            checkVodChunks(span.pairs = wanted, "original pair partition " + index.ToStr())
            cursor += span.length
        end for
        checkVodChunks(cursor = source.Count(), "every source root byte assigned exactly once")
        reason = ""
        try
            unused = nativeDemuxBulkFragment(source, tracks, "video")
        catch e
            reason = e.message
        end try
        checkVodChunks(reason = "native-demux: fragment count limit", "unchanged native 64-pair whole-call guard")
        pair = convertVodChunks(corpus.media, timing, tracks, plan)
        print "STITCH_VOD_CHUNKS_BYTES: " + FormatJson({ video: LCase(pair.video.ToHexString()), audio: LCase(pair.audio.ToHexString()) })
        m.cases += 1
        print "STITCH_VOD_CHUNKS_CASE: actual-bulk-full-byte-and-absolute-timing-goldens"

        tail = convertVodChunks(corpus.tail, timing, tracks)
        m.cases += 1
        print "STITCH_VOD_CHUNKS_CASE: trailing-metadata-preserved-video-only"
        end if

        if mode = "refusals" or mode = "work"
        for each item in corpus.negatives
            isWork = item.name = "one-pair-sample-work" or item.name = "one-pair-byte-work"
            if (mode = "work") = isWork
            print "STITCH_VOD_CHUNKS_STAGE: refusal " + item.name
            bad = bytesVodChunks(item.input.hex)
            checkVodChunks(rokuVodChunkPlan(bad, tracks, timing) = invalid, "whole-input refusal " + item.name)
            goldenVodChunks(bad, item.input, "refused source immutable " + item.name)
            end if
        end for
        if mode = "refusals"
        oversized = CreateObject("roByteArray")
        oversized.SetResize(12582913, false)
        oversized[12582912] = 0
        checkVodChunks(rokuVodChunkPlan(oversized, tracks, timing) = invalid, "12MiB whole input limit")
        oversized = invalid
        source = bytesVodChunks(corpus.tail.input.hex)
        checkVodChunks(rokuVodChunkPlan(source, [[7&, "video"], [9&, "audio"]], timing) = invalid, "timing map must match exactly the clear tracks")
        checkVodChunks(rokuVodChunkPlan(source, tracks, invalid) = invalid, "missing init timing refused")
        end if
        m.cases += 1
        print "STITCH_VOD_CHUNKS_CASE: entire-tail-addressing-layout-and-work-refusals"
        end if

        if mode = "states"
        source = bytesVodChunks(corpus.cancel.input.hex)
        plan = rokuVodChunkPlan(source, tracks, timing)
        forged = ParseJson(FormatJson(plan))
        forgedSpans = forged.spans
        forgedFirst = forgedSpans[0]
        forgedFirst.length -= 1
        forgedSpans[0] = forgedFirst
        forged.spans = forgedSpans
        state = rokuVodChunkBegin(source, tracks, forged)
        checkVodChunks(state.phase = "failed" and state.reason = "invalid_plan", "forged plan cannot skip a root byte")
        releasedVodChunks(state)
        other = bytesVodChunks(corpus.cancel.input.hex)
        other[other.Count() - 1] = (other[other.Count() - 1] + 1) mod 256
        state = rokuVodChunkBegin(other, tracks, plan)
        checkVodChunks(state.phase = "failed" and state.reason = "invalid_plan", "changed source cannot reuse a validated plan")
        releasedVodChunks(state)
        forged = ParseJson(FormatJson(plan))
        forged.digest = corpus.media.input.hex
        state = rokuVodChunkBegin(source, tracks, forged)
        checkVodChunks(state.phase = "failed" and state.reason = "invalid_plan", "unbounded claimed digest rejected before JSON serialization")
        releasedVodChunks(state)
        forged = ParseJson(FormatJson(plan))
        forgedSpans = forged.spans
        while forgedSpans.Count() < 8
            forgedSpans.Push(forgedSpans[0])
        end while
        forged.spans = forgedSpans
        state = rokuVodChunkBegin(source, tracks, forged)
        checkVodChunks(state.phase = "failed" and state.reason = "invalid_plan", "oversized plan cannot hide outside whole-input bounds")
        releasedVodChunks(state)
        checkVodChunks(rokuVodChunkStep(invalid, false).reason = "invalid_state", "invalid state returns fixed refusal without runtime error")
        cancelSource = bytesVodChunks(corpus.cancel.input.hex)
        cancelPlan = rokuVodChunkPlan(cancelSource, tracks, timing)
        for stopAt = 0 to 3
            state = rokuVodChunkBegin(cancelSource, tracks, cancelPlan)
            for stepNo = 1 to stopAt
                nextResult = rokuVodChunkStep(state, false)
            end for
            stopped = rokuVodChunkStep(state, true)
            checkVodChunks(stopped.phase = "cancelled" and stopped.reason = "cancelled" and stopped.pair = invalid, "cancel between bounded phases " + stopAt.ToStr())
            releasedVodChunks(state)
            checkVodChunks(rokuVodChunkClose(state), "cancel close acknowledgement")
            checkVodChunks(rokuVodChunkStep(state, false).pair = invalid, "cancel never emits partial outputs")
        end for
        state = rokuVodChunkBegin(cancelSource, tracks, cancelPlan)
        checkVodChunks(rokuVodChunkClose(state) and state.phase = "cancelled" and state.reason = "closed", "close cancels unused source")
        releasedVodChunks(state)
        checkVodChunks(not rokuVodChunkClose(invalid), "invalid close does not claim cleanup")
        m.cases += 1
        print "STITCH_VOD_CHUNKS_CASE: stale-plan-cancel-and-close-release"

        smallSource = bytesVodChunks(corpus.tail.input.hex)
        smallPlan = rokuVodChunkPlan(smallSource, tracks, timing)
        state = rokuVodChunkBegin(smallSource, tracks, smallPlan)
        enlarged = CreateObject("roByteArray")
        enlarged.SetResize(16777216, false)
        enlarged[16777215] = 0
        state.video = enlarged
        refused = rokuVodChunkStep(state, false)
        checkVodChunks(refused.phase = "failed" and refused.reason = "output_limit" and refused.pair = invalid, "aggregate track output bound enforced before append")
        releasedVodChunks(state)
        changed = bytesVodChunks(corpus.tail.input.hex)
        state = rokuVodChunkBegin(changed, tracks, smallPlan)
        changed[changed.Count() - 1] = (changed[changed.Count() - 1] + 1) mod 256
        refused = rokuVodChunkStep(state, false)
        checkVodChunks(refused.phase = "failed" and refused.reason = "conversion_failed" and refused.pair = invalid, "caller source mutation between phases fails before conversion")
        releasedVodChunks(state)
        state = rokuVodChunkBegin(smallSource, tracks, smallPlan)
        state.track = "unknown"
        refused = rokuVodChunkStep(state, false)
        checkVodChunks(refused.phase = "failed" and refused.reason = "conversion_failed", "native refusal becomes fixed failure code")
        releasedVodChunks(state)
        m.cases += 1
        print "STITCH_VOD_CHUNKS_CASE: actual-output-bound-and-helper-failure-release"
        end if

        print "STITCH_VOD_CHUNKS_PASS: __MARKER__ cases="; m.cases; " assertions="; m.assertions
    catch e
        print "STITCH_VOD_CHUNKS_FAIL: __MARKER__ "; e.message
    end try
end sub
