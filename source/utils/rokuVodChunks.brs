' Pure Task-private recorded-media caller. Import unchanged rokuDemuxBulk.brs
' and rokuDemuxInitMetadata.brs explicitly; this file performs no I/O.

sub rvdcCheck(ok as boolean)
    if not ok then throw "vod-chunks: invalid input"
end sub

function rvdcInteger(value as dynamic) as boolean
    kind = Type(value, 3)
    return kind = "Integer" or kind = "LongInteger" or kind = "roInt"
end function

function rvdcKeys(value as dynamic, keys as object) as boolean
    if Type(value) <> "roAssociativeArray" then return false
    if value.Count() <> keys.Count() then return false
    for each key in keys
        if not value.DoesExist(key) then return false
    end for
    return true
end function

function rvdcUnsigned64(data as object, start as integer, finish as integer) as longinteger
    high = nbU32(data, start, finish)
    low = nbU32(data, start + 4, finish)
    ' Exact on both native LongInteger and the offline engine's number storage.
    rvdcCheck(high <= 2097151&)
    return high * 4294967296& + low
end function

function rvdcBoxes(data as object, start as integer, finish as integer, ctx as object) as object
    boxes = nbBoxes(data, start, finish, ctx)
    for each childBox in boxes
        rvdcCheck(nbU32(data, childBox.offset, finish) <> 0&)
    end for
    return boxes
end function

function rvdcOne(boxes as object, kind as string) as object
    result = invalid
    for each childBox in boxes
        if childBox.kind = kind
            rvdcCheck(result = invalid)
            result = childBox
        end if
    end for
    rvdcCheck(result <> invalid)
    return result
end function

function rvdcCString(data as object, start as integer, finish as integer) as integer
    cursor = start
    while cursor < finish and cursor - start <= 4096
        if data[cursor] = 0 then return cursor + 1
        cursor += 1
    end while
    rvdcCheck(false)
    return -1
end function

sub rvdcEmsg(data as object, atom as object)
    rvdcCheck(atom.size <= 65536 and atom.finish - atom.body >= 4)
    flags = nbU32(data, atom.body, atom.finish)
    rvdcCheck(flags = 0& or flags = 16777216&)
    if flags = 16777216&
        rvdcCheck(atom.finish - atom.body >= 26)
        rvdcCheck(nbU32(data, atom.body + 4, atom.finish) > 0&)
        cursor = atom.body + 24
        cursor = rvdcCString(data, cursor, atom.finish)
        cursor = rvdcCString(data, cursor, atom.finish)
    else
        cursor = rvdcCString(data, atom.body + 4, atom.finish)
        cursor = rvdcCString(data, cursor, atom.finish)
        rvdcCheck(atom.finish - cursor >= 16 and nbU32(data, cursor, atom.finish) > 0&)
    end if
end sub

function rokuVodInitTiming(data as dynamic) as dynamic
    try
        metadata = nativeLiveInspectInitMetadata(data)
        ctx = nbContext()
        roots = rvdcBoxes(data, 0, data.Count(), ctx)
        moov = rvdcOne(roots, "moov")
        children = rvdcBoxes(data, moov.body, moov.finish, ctx)
        mvex = rvdcOne(children, "mvex")
        defaults = []
        for each entry in rvdcBoxes(data, mvex.body, mvex.finish, ctx)
            rvdcCheck(entry.kind = "trex" and entry.finish - entry.body = 24)
            rvdcCheck(nbU32(data, entry.body, entry.finish) = 0&)
            id = nbU32(data, entry.body + 4, entry.finish)
            rvdcCheck(id > 0& and nbU32(data, entry.body + 8, entry.finish) = 1&)
            for each prior in defaults
                rvdcCheck(prior.id <> id)
            end for
            rvdcCheck(defaults.Count() < 2)
            defaults.Push({ id: id, duration: nbU32(data, entry.body + 12, entry.finish), size: nbU32(data, entry.body + 16, entry.finish), flags: nbU32(data, entry.body + 20, entry.finish) })
        end for
        rvdcCheck(defaults.Count() = 2)
        result = []
        for each trak in children
            if trak.kind = "trak"
                rvdcCheck(result.Count() < 2)
                info = nbTrakInfo(data, trak, ctx)
                mdia = rvdcOne(rvdcBoxes(data, trak.body, trak.finish, ctx), "mdia")
                mdhd = rvdcOne(rvdcBoxes(data, mdia.body, mdia.finish, ctx), "mdhd")
                rvdcCheck(mdhd.finish - mdhd.body >= 4)
                version = data[mdhd.body]
                rvdcCheck((version = 0 or version = 1) and nbU32(data, mdhd.body, mdhd.finish) mod 16777216& = 0&)
                skip = 12
                required = 24
                if version = 1
                    skip = 20
                    required = 36
                end if
                rvdcCheck(mdhd.finish - mdhd.body = required)
                scale = nbU32(data, mdhd.body + skip, mdhd.finish)
                rvdcCheck(scale > 0& and scale <= 1000000000&)
                wanted = metadata.audioTrackId
                if info[1] = "video" then wanted = metadata.videoTrackId
                rvdcCheck(info[0] = wanted)
                found = invalid
                for each item in defaults
                    if item.id = wanted then found = item
                end for
                rvdcCheck(found <> invalid)
                rvdcCheck(found.duration <= scale * 30& and found.size <= 4194304&)
                result.Push({ id: wanted, kind: info[1], timescale: scale, duration: found.duration, size: found.size, flags: found.flags })
            end if
        end for
        rvdcCheck(result.Count() = 2)
        return result
    catch e
        return invalid
    end try
end function

function rvdcTimingSnapshot(tracks as dynamic, timing as dynamic) as object
    rvdcCheck(Type(tracks) = "roArray" and Type(timing) = "roArray")
    rvdcCheck(tracks.Count() = 2 and timing.Count() = 2)
    nbTrackMapValid(tracks, "video")
    nbTrackMapValid(tracks, "audio")
    copy = []
    for each item in timing
        rvdcCheck(rvdcKeys(item, ["id", "kind", "timescale", "duration", "size", "flags"]))
        for each key in ["id", "timescale", "duration", "size", "flags"]
            rvdcCheck(rvdcInteger(item[key]))
        end for
        rvdcCheck(item.id > 0& and item.id <= 4294967295&)
        rvdcCheck(item.timescale > 0& and item.timescale <= 1000000000&)
        rvdcCheck(item.duration >= 0& and item.duration <= 4294967295& and item.size >= 0& and item.size <= 4194304& and item.flags >= 0& and item.flags <= 4294967295&)
        rvdcCheck((item.kind = "video" or item.kind = "audio") and nbTrackKind(tracks, item.id) = item.kind)
        for each prior in copy
            rvdcCheck(prior.id <> item.id and prior.kind <> item.kind)
        end for
        copy.Push({ id: item.id, kind: item.kind, timescale: item.timescale, duration: item.duration, size: item.size, flags: item.flags })
    end for
    return copy
end function

function rvdcTraf(data as object, traf as object, moof as object, mdat as object, timing as object, ctx as object) as object
    children = rvdcBoxes(data, traf.body, traf.finish, ctx)
    for each child in children
        rvdcCheck(child.kind = "tfhd" or child.kind = "tfdt" or child.kind = "trun" or child.kind = "free")
    end for
    tfhd = rvdcOne(children, "tfhd")
    tfdt = rvdcOne(children, "tfdt")
    info = nbTfhd(data, tfhd)
    defaults = invalid
    for each item in timing
        if item.id = info[0] then defaults = item
    end for
    rvdcCheck(defaults <> invalid)
    flags = CInt(nbU32(data, tfhd.body, tfhd.finish) mod 16777216&)
    cursor = tfhd.body + 8
    if (flags and 2) <> 0
        rvdcCheck(nbU32(data, cursor, tfhd.finish) = 1&)
        cursor += 4
    end if
    duration = defaults.duration
    size = defaults.size
    sampleFlags = defaults.flags
    if (flags and 8) <> 0
        duration = nbU32(data, cursor, tfhd.finish)
        cursor += 4
    end if
    if (flags and 16) <> 0
        size = nbU32(data, cursor, tfhd.finish)
        cursor += 4
    end if
    if (flags and 32) <> 0
        sampleFlags = nbU32(data, cursor, tfhd.finish)
        cursor += 4
    end if
    rvdcCheck(cursor = tfhd.finish)
    rvdcCheck(tfdt.finish - tfdt.body >= 4)
    version = data[tfdt.body]
    rvdcCheck((version = 0 or version = 1) and nbU32(data, tfdt.body, tfdt.finish) mod 16777216& = 0&)
    if version = 0
        rvdcCheck(tfdt.finish - tfdt.body = 8)
        decode = nbU32(data, tfdt.body + 4, tfdt.finish)
    else
        rvdcCheck(tfdt.finish - tfdt.body = 12)
        decode = rvdcUnsigned64(data, tfdt.body + 4, tfdt.finish)
    end if
    startDecode = decode
    ranges = []
    samples = 0
    for each sampleRun in children
        if sampleRun.kind = "trun"
            rvdcCheck(ranges.Count() < 128 and sampleRun.finish - sampleRun.body >= 8)
            version = data[sampleRun.body]
            flags = CInt(nbU32(data, sampleRun.body, sampleRun.finish) mod 16777216&)
            rvdcCheck((version = 0 or version = 1) and (flags and &hfff0fa) = 0 and (flags and 1) <> 0)
            rvdcCheck((flags and 4) = 0 or (flags and 1024) = 0)
            count = nbU32(data, sampleRun.body + 4, sampleRun.finish)
            rvdcCheck(count > 0& and count <= 65536&)
            rvdcCheck(samples + count <= 8192&)
            ' The unchanged bulk helper does not apply a trex size default.
            rvdcCheck((flags and 512) <> 0 or (info[1] > 0& and info[1] = size))
            ctx[1] += CInt(count)
            rvdcCheck(ctx[1] <= 65536)
            samples += CInt(count)
            cursor = sampleRun.body + 8
            dataStart = moof.offset + nbSigned32(data, cursor, sampleRun.finish)
            cursor += 4
            if (flags and 4) <> 0
                firstFlags = nbU32(data, cursor, sampleRun.finish)
                cursor += 4
            end if
            stride = 0
            for each flag in [256, 512, 1024, 2048]
                if (flags and flag) <> 0 then stride += 4
            end for
            rvdcCheck(cursor <= sampleRun.finish and count * stride = sampleRun.finish - cursor)
            payload = dataStart
            for i = 1 to CInt(count)
                sampleDuration = duration
                sampleSize = size
                composition = 0&
                if (flags and 256) <> 0
                    sampleDuration = nbU32(data, cursor, sampleRun.finish)
                    cursor += 4
                end if
                if (flags and 512) <> 0
                    sampleSize = nbU32(data, cursor, sampleRun.finish)
                    cursor += 4
                end if
                if (flags and 1024) <> 0
                    value = nbU32(data, cursor, sampleRun.finish)
                    cursor += 4
                end if
                if (flags and 2048) <> 0
                    composition = nbU32(data, cursor, sampleRun.finish)
                    if version = 1 then composition = nbSigned32(data, cursor, sampleRun.finish)
                    cursor += 4
                end if
                rvdcCheck(sampleDuration > 0& and sampleDuration <= defaults.timescale * 30&)
                rvdcCheck(sampleSize > 0& and sampleSize <= 4194304&)
                rvdcCheck(payload >= mdat.body and payload <= mdat.finish - sampleSize)
                rvdcCheck(decode <= 9007199254740991& - sampleDuration)
                rvdcCheck(composition >= -decode and composition <= 9007199254740991& - decode)
                payload += sampleSize
                decode += sampleDuration
            end for
            ranges.Push([dataStart, payload])
        end if
    end for
    rvdcCheck(ranges.Count() > 0)
    return { id: info[0], kind: defaults.kind, startDecode: startDecode, endDecode: decode, ranges: ranges, samples: samples }
end function

function rokuVodChunkPlan(data as dynamic, tracks as dynamic, timing as dynamic) as dynamic
    try
        rvdcCheck(Type(data) = "roByteArray" and data.Count() >= 16 and data.Count() <= 12582912)
        snapshot = rvdcTimingSnapshot(tracks, timing)
        ctx = nbContext()
        roots = rvdcBoxes(data, 0, data.Count(), ctx)
        ' Reject a bad tail and global root-work excess before sample parsing.
        rootPending = false
        rootPairs = 0
        rootEvents = 0
        for each root in roots
            if root.kind = "moof"
                rvdcCheck(not rootPending)
                rootPending = true
            else if root.kind = "mdat"
                rvdcCheck(rootPending)
                rootPending = false
                rootPairs += 1
                rvdcCheck(rootPairs <= 128)
            else if root.kind = "emsg"
                rvdcCheck(not rootPending)
                rootEvents += 1
                rvdcCheck(rootEvents <= 16)
                rvdcEmsg(data, root)
            else
                rvdcCheck(false)
            end if
        end for
        rvdcCheck(not rootPending and rootPairs > 0)
        pending = invalid
        pairs = 0
        events = 0
        spans = []
        chunkStart = 0
        chunkFinish = 0
        chunkPairs = 0
        chunkSamples = 0
        priorDecode = [-1&, -1&]
        for each atom in roots
            rvdcCheck(atom.kind = "emsg" or atom.kind = "moof" or atom.kind = "mdat")
            if atom.kind = "emsg"
                rvdcCheck(pending = invalid)
                events += 1
                rvdcCheck(events <= 16)
            else if atom.kind = "moof"
                rvdcCheck(pending = invalid)
                pending = atom
            else
                rvdcCheck(pending <> invalid)
                pairs += 1
                rvdcCheck(pairs <= rootPairs)
                children = rvdcBoxes(data, pending.body, pending.finish, ctx)
                mfhd = rvdcOne(children, "mfhd")
                rvdcCheck(mfhd.finish - mfhd.body = 8 and nbU32(data, mfhd.body, mfhd.finish) = 0&)
                seen = []
                ranges = []
                pairSamples = 0
                for each child in children
                    rvdcCheck(child.kind = "mfhd" or child.kind = "traf")
                    if child.kind = "traf"
                        info = rvdcTraf(data, child, pending, atom, snapshot, ctx)
                        rvdcCheck(seen.Count() < 2)
                        for each prior in seen
                            rvdcCheck(prior <> info.kind)
                        end for
                        seen.Push(info.kind)
                        slot = 0
                        if info.kind = "audio" then slot = 1
                        rvdcCheck(priorDecode[slot] = -1& or priorDecode[slot] = info.startDecode)
                        priorDecode[slot] = info.endDecode
                        pairSamples += info.samples
                        for each span in info.ranges
                            at = 0
                            while at < ranges.Count()
                                if ranges[at][0] > span[0] then exit while
                                at += 1
                            end while
                            ranges.Push(span)
                            move = ranges.Count() - 1
                            while move > at
                                ranges[move] = ranges[move - 1]
                                move -= 1
                            end while
                            ranges[at] = span
                        end for
                    end if
                end for
                rvdcCheck(seen.Count() = 2)
                finish = atom.body + 0&
                for each span in ranges
                    rvdcCheck(span[0] >= finish and span[0] < span[1] and span[1] <= atom.finish)
                    finish = span[1]
                end for
                ' Include every root byte exactly once. Metadata between pairs
                ' belongs to the next chunk; trailing metadata stays in the last.
                if chunkPairs > 0 and (chunkPairs = 20 or atom.finish - chunkStart > 4194304 or chunkSamples + pairSamples > 8192)
                    rvdcCheck(spans.Count() < 127)
                    spans.Push({ start: chunkStart, length: chunkFinish - chunkStart, pairs: chunkPairs, samples: chunkSamples })
                    chunkStart = chunkFinish
                    chunkPairs = 0
                    chunkSamples = 0
                end if
                rvdcCheck(atom.finish - chunkStart <= 4194304 and pairSamples <= 8192)
                chunkPairs += 1
                chunkSamples += pairSamples
                chunkFinish = atom.finish
                pending = invalid
            end if
        end for
        rvdcCheck(pending = invalid and pairs = rootPairs and pairs > 0 and chunkPairs > 0)
        rvdcCheck(data.Count() - chunkStart <= 4194304 and spans.Count() < 128)
        spans.Push({ start: chunkStart, length: data.Count() - chunkStart, pairs: chunkPairs, samples: chunkSamples })
        trackCopy = []
        for each item in tracks
            trackCopy.Push([item[0], item[1]])
        end for
        return { version: 1, spans: spans, timing: snapshot, tracks: trackCopy, digest: nbBulkDigest(data), bytes: data.Count(), pairs: pairs, samples: ctx[1], events: events }
    catch e
        return invalid
    end try
end function

sub rvdcRelease(state as object)
    state.input = invalid
    state.chunk = invalid
    state.video = invalid
    state.audio = invalid
    state.plan = invalid
    state.tracks = invalid
end sub

sub rvdcPlanShape(plan as dynamic)
    rvdcCheck(rvdcKeys(plan, ["version", "spans", "timing", "tracks", "digest", "bytes", "pairs", "samples", "events"]))
    for each key in ["version", "bytes", "pairs", "samples", "events"]
        rvdcCheck(rvdcInteger(plan[key]))
    end for
    rvdcCheck(plan.version = 1 and plan.bytes >= 16 and plan.bytes <= 12582912)
    rvdcCheck(plan.pairs >= 1 and plan.pairs <= 128 and plan.samples >= 1 and plan.samples <= 65536 and plan.events >= 0 and plan.events <= 16)
    rvdcCheck(Type(plan.digest) = "String" or Type(plan.digest) = "roString")
    rvdcCheck(plan.digest.Len() = 64)
    for i = 0 to 63
        rvdcCheck("0123456789abcdef".InStr(plan.digest.Mid(i, 1)) >= 0)
    end for
    rvdcCheck(Type(plan.spans) = "roArray" and plan.spans.Count() >= 1 and plan.spans.Count() <= 128)
    rvdcCheck(Type(plan.tracks) = "roArray" and plan.tracks.Count() = 2)
    nbTrackMapValid(plan.tracks, "video")
    nbTrackMapValid(plan.tracks, "audio")
    cursor = 0
    pairs = 0
    samples = 0
    for each span in plan.spans
        rvdcCheck(rvdcKeys(span, ["start", "length", "pairs", "samples"]))
        for each key in ["start", "length", "pairs", "samples"]
            rvdcCheck(rvdcInteger(span[key]))
        end for
        rvdcCheck(span.start = cursor and span.length >= 16 and span.length <= 4194304)
        rvdcCheck(span.length <= plan.bytes - cursor and span.pairs >= 1 and span.pairs <= 20 and span.samples >= 1 and span.samples <= 8192)
        cursor += span.length
        pairs += span.pairs
        samples += span.samples
    end for
    rvdcCheck(cursor = plan.bytes and pairs = plan.pairs and samples = plan.samples)
end sub

function rokuVodChunkBegin(data as dynamic, tracks as dynamic, plan as dynamic) as object
    state = { phase: "failed", reason: "invalid_plan", input: invalid, chunk: invalid, video: invalid, audio: invalid, plan: invalid, tracks: invalid, index: 0, track: "video", closed: false }
    try
        rvdcPlanShape(plan)
        checked = rokuVodChunkPlan(data, tracks, plan.timing)
        rvdcCheck(checked <> invalid and FormatJson(checked) = FormatJson(plan))
        state.phase = "working"
        state.reason = ""
        state.input = data
        state.tracks = checked.tracks
        state.plan = checked
        state.video = CreateObject("roByteArray")
        state.audio = CreateObject("roByteArray")
    catch e
        rvdcRelease(state)
    end try
    return state
end function

function rokuVodChunkStep(state as object, stopRequested as boolean) as object
    if not rvdcKeys(state, ["phase", "reason", "input", "chunk", "video", "audio", "plan", "tracks", "index", "track", "closed"])
        return { phase: "failed", pair: invalid, reason: "invalid_state" }
    end if
    if stopRequested and state.phase = "working"
        state.phase = "cancelled"
        state.reason = "cancelled"
        rvdcRelease(state)
    end if
    result = { phase: state.phase, pair: invalid, reason: state.reason }
    if state.closed or state.phase <> "working" then return result
    try
        rvdcCheck(state.plan <> invalid and state.input <> invalid)
        rvdcCheck(state.input.Count() = state.plan.bytes and nbBulkDigest(state.input) = state.plan.digest)
        span = state.plan.spans[state.index]
        if state.chunk = invalid
            state.chunk = state.input.Slice(span.start, span.start + span.length)
            rvdcCheck(Type(state.chunk, 3) = "roByteArray" and state.chunk.Count() = span.length)
        end if
        ' Reserve unchanged bulk's independent output/copy bounds in addition
        ' to actual caller-owned buffers. This is not a native heap guarantee.
        workingBytes = state.input.Count() + state.chunk.Count() + state.video.Count() + state.audio.Count() + 8388608&
        rvdcCheck(workingBytes <= 50331648&)
        converted = nativeDemuxBulkFragment(state.chunk, state.tracks, state.track)
        rvdcCheck(Type(converted, 3) = "roByteArray" and converted.Count() > 0 and converted.Count() <= 4194304)
        target = state.video
        if state.track = "audio" then target = state.audio
        if target.Count() + converted.Count() > 16777216
            state.reason = "output_limit"
            throw "vod-chunks: output limit"
        end if
        rvdcCheck(workingBytes + converted.Count() <= 50331648&)
        expected = target.Count() + converted.Count()
        target.Append(converted)
        rvdcCheck(target.Count() = expected)
        if state.track = "video"
            state.video = target
            state.track = "audio"
        else
            state.audio = target
            state.track = "video"
            state.chunk = invalid
            state.index += 1
        end if
        rvdcCheck(state.video.Count() + state.audio.Count() <= 16777216)
        if state.index = state.plan.spans.Count()
            state.phase = "complete"
            result.pair = { video: state.video, audio: state.audio }
            rvdcRelease(state)
        end if
    catch e
        state.phase = "failed"
        if state.reason = "" then state.reason = "conversion_failed"
        rvdcRelease(state)
    end try
    result.phase = state.phase
    result.reason = state.reason
    return result
end function

function rokuVodChunkClose(state as dynamic) as boolean
    if Type(state) <> "roAssociativeArray" then return false
    try
        rvdcRelease(state)
        state.closed = true
        if state.phase = "working"
            state.phase = "cancelled"
            state.reason = "closed"
        end if
        return state.input = invalid and state.chunk = invalid and state.video = invalid and state.audio = invalid and state.plan = invalid and state.tracks = invalid
    catch e
        return false
    end try
end function
