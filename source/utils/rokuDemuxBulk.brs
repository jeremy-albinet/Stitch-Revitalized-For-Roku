' Private pure prototype: no URL, filesystem, server, Task or SceneGraph operations.
' Bounds are enforced before allocation, sample loops and integer narrowing.
' All uint32/signed offset arithmetic is LongInteger; accepted buffer indices fit Integer.

function nbContext() as object
    return [0, 0, 0, 0] ' box visits, samples, copied output bytes, plan visits
end function

sub nbCheck(ok as boolean, message as string)
    if not ok then throw "native-demux: " + message
end sub

function nbU32(data as object, offset as integer, limit as integer) as longinteger
    nbCheck(offset >= 0 and offset <= limit - 4, "truncated uint32")
    return data[offset] * 16777216& + data[offset + 1] * 65536& + data[offset + 2] * 256& + data[offset + 3]
end function

function nbSigned32(data as object, offset as integer, limit as integer) as longinteger
    value = nbU32(data, offset, limit)
    if value >= 2147483648& then value -= 4294967296&
    return value
end function

function nbBox(data as object, offset as integer, limit as integer, ctx as object) as object
    ctx[0] += 1
    nbCheck(ctx[0] <= 4096, "box work limit")
    nbCheck(offset >= 0 and offset <= limit - 8, "truncated box header")
    size = nbU32(data, offset, limit)
    header = 8
    if size = 1&
        nbCheck(offset <= limit - 16, "truncated large box header")
        ' A nonzero unsigned high word necessarily exceeds our bounded input.
        nbCheck(nbU32(data, offset + 8, limit) = 0&, "large box exceeds input bound")
        size = nbU32(data, offset + 12, limit)
        header = 16
    else if size = 0&
        size = limit - offset
    end if
    nbCheck(size >= header and size <= limit - offset, "invalid or truncated box size")
    kind = ""
    for index = offset + 4 to offset + 7
        kind += Chr(data[index])
    end for
    nbCheck(kind <> "pssh" and kind <> "senc" and kind <> "saiz" and kind <> "saio" and kind <> "sinf" and kind <> "tenc" and kind <> "uuid", "encrypted or UUID layout unsupported")
    nbCheck(kind <> "sgpd" and kind <> "sbgp", "sample grouping layout unsupported")
    return { offset: offset, body: offset + header, finish: offset + CInt(size), size: CInt(size), header: header, kind: kind }
end function

function nbBoxes(data as object, start as integer, limit as integer, ctx as object) as object
    boxes = []
    offset = start
    while offset < limit
        atom = nbBox(data, offset, limit, ctx)
        boxes.Push(atom)
        offset = atom.finish
    end while
    nbCheck(offset = limit, "child box boundary")
    return boxes
end function

function nbHeader(kind as string, size as integer) as object
    nbCheck(kind.Len() = 4 and size >= 8, "invalid output header")
    bytes = CreateObject("roByteArray")
    bytes.SetResize(8, false)
    bytes[7] = 0 ' Establish logical length on engines where SetResize reserves capacity.
    nbPut32(bytes, 0, size + 0&)
    for index = 0 to 3
        bytes[index + 4] = Asc(kind.Mid(index, 1))
    end for
    return bytes
end function

sub nbPut32(bytes as object, offset as integer, value as longinteger)
    nbCheck(offset >= 0 and offset <= bytes.Count() - 4, "patch exceeds output")
    nbCheck(value >= -2147483648& and value <= 4294967295&, "uint32 patch out of range")
    if value < 0& then value += 4294967296&
    ' Integer division prevents the implicit Float32 result of '/'.
    bytes[offset] = CInt((value \ 16777216&) mod 256&)
    bytes[offset + 1] = CInt((value \ 65536&) mod 256&)
    bytes[offset + 2] = CInt((value \ 256&) mod 256&)
    bytes[offset + 3] = CInt(value mod 256&)
end sub

sub nbRaw(plan as object, start as integer, length as integer)
    if length > 0 then plan.Push([start, length, invalid])
end sub

sub nbGenerated(plan as object, bytes as object)
    plan.Push([0, bytes.Count(), bytes])
end sub

function nbPlanSize(plan as object, ctx as object) as integer
    ctx[3] += plan.Count()
    nbCheck(ctx[3] <= 131072, "plan work limit")
    total = 0&
    for each piece in plan
        total += piece[1]
    end for
    nbCheck(total <= 4194304&, "output exceeds buffer bound")
    return CInt(total)
end function

function nbBuild(data as object, plan as object, patches as object, ctx as object, limit as integer) as object
    size = nbPlanSize(plan, ctx)
    nbCheck(size <= limit, "output exceeds operation bound")
    nbCheck(size > 0 and plan.Count() > 0, "bulk empty output plan")
    nbCheck(plan.Count() <= 4096, "bulk span count limit")
    nbBulkGate()
    inputCount = data.Count()
    inputDigest = nbBulkDigest(data)
    out = CreateObject("roByteArray")
    nbCheck(out.Count() = 0, "bulk output must start empty")
    target = 0
    sliced = 0
    for each piece in plan
        start = piece[0]
        length = piece[1]
        generated = piece[2]
        source = data
        if generated <> invalid then source = generated
        nbCheck(Type(source) = "roByteArray", "bulk source must be bytearray")
        nbCheck(start >= 0 and length <= source.Count() - start, "copy span exceeds input")
        nbCheck(length > 0, "bulk empty copy span")
        ctx[2] += length
        nbCheck(ctx[2] <= 4194304, "copy work limit")
        nbCheck(length <= size - target, "bulk append exceeds output plan")
        before = source.Count()
        if generated = invalid
            span = source.Slice(start, start + length)
            nbCheck(Type(span, 3) = "roByteArray", "bulk Slice result must be bytearray")
            nbCheck(span.Count() = length, "bulk Slice count mismatch")
            sliced += length
            nbCheck(sliced <= 4194304, "bulk slice work limit")
        else
            nbCheck(start = 0 and length = before, "bulk generated span must be complete")
            span = generated
        end if
        nbCheck(source.Count() = before, "bulk Slice mutated source count")
        out.Append(span)
        target += length
        nbCheck(out.Count() = target and target <= size, "bulk Append count mismatch")
        nbCheck(span.Count() = length and source.Count() = before, "bulk Append mutated source count")
        span = invalid ' Native GC may retain released slices; total slice bytes are bounded.
    end for
    nbCheck(target = size and out.Count() = size, "bulk output plan count mismatch")
    out.SetResize(size, false)
    for each patch in patches
        nbPut32(out, patch[0], patch[1])
    end for
    nbCheck(data.Count() = inputCount, "bulk input count changed")
    nbCheck(nbBulkDigest(data) = inputDigest, "bulk input identity changed")
    return out
end function

function nbBulkDigest(data as object) as string
    digest = CreateObject("roEVPDigest")
    nbCheck(digest <> invalid, "bulk digest API unavailable")
    nbCheck(digest.Setup("sha256") = 0, "bulk SHA256 setup failed")
    hash = digest.Process(data)
    nbCheck(Len(hash) = 64, "bulk SHA256 result invalid")
    return LCase(hash)
end function

sub nbBulkGate()
    source = CreateObject("roByteArray")
    source.FromHexString("10203040")
    span = source.Slice(1, 3)
    nbCheck(Type(span, 3) = "roByteArray", "bulk Slice API unavailable")
    nbCheck(span.Count() = 2 and span[0] = 32 and span[1] = 48, "bulk Slice range mismatch")
    ' Prove the tiny copied span can change without modifying its source.
    span[0] = 153
    nbCheck(source.Count() = 4 and source[1] = 32, "bulk Slice aliases source")
    span[0] = 32
    out = CreateObject("roByteArray")
    nbCheck(out.Count() = 0, "bulk gate output must start empty")
    out.Append(span)
    nbCheck(out.Count() = 2 and out[0] = 32 and out[1] = 48, "bulk Append API unavailable")
    suffix = CreateObject("roByteArray")
    suffix.FromHexString("aa")
    out.Append(suffix)
    nbCheck(out.Count() = 3 and out[2] = 170, "bulk Append growth mismatch")
    out[0] = 85
    nbCheck(span.Count() = 2 and span[0] = 32 and span[1] = 48, "bulk Append aliases source")
    nbCheck(suffix.Count() = 1 and suffix[0] = 170, "bulk Append mutated suffix")
    nbCheck(LCase(source.ToHexString()) = "10203040", "bulk gate source mutated")
end sub

function nbTrackKind(tracks as object, id as longinteger) as string
    for each track in tracks
        if track[0] = id then return track[1]
    end for
    return ""
end function

sub nbTrackMapValid(tracks as object, keep as string)
    nbCheck(keep = "video" or keep = "audio", "invalid requested track")
    nbCheck(Type(tracks) = "roArray", "invalid track map type")
    nbCheck(tracks.Count() >= 1 and tracks.Count() <= 8, "invalid track map")
    ids = []
    wanted = 0
    for each track in tracks
        nbCheck(Type(track) = "roArray", "invalid track entry type")
        nbCheck(track.Count() = 2, "invalid track entry")
        id = track[0]
        nbCheck(Type(id) = "LongInteger" or Type(id) = "Integer", "track ID must be integral")
        nbCheck(id > 0& and id <= 4294967295&, "invalid track ID")
        nbCheck(Type(track[1]) = "String" or Type(track[1]) = "roString", "invalid track handler type")
        nbCheck(track[1] = "audio" or track[1] = "video", "unknown track handler")
        for each previous in ids
            nbCheck(previous <> id, "duplicate track ID")
        end for
        ids.Push(id)
        if track[1] = keep then wanted += 1
    end for
    nbCheck(wanted = 1, "must have exactly one requested track")
end sub

function nbTrakInfo(data as object, trak as object, ctx as object) as object
    id = invalid
    kind = ""
    handlerSeen = false
    idOffset = -1
    for each child in nbBoxes(data, trak.body, trak.finish, ctx)
        if child.kind = "tkhd"
            nbCheck(id = invalid and child.body < child.finish, "missing or duplicate tkhd")
            version = data[child.body]
            nbCheck(version = 0 or version = 1, "unknown tkhd version")
            skip = 12
            if version = 1 then skip = 20
            idOffset = child.body + skip
            id = nbU32(data, idOffset, child.finish)
        else if child.kind = "mdia"
            for each media in nbBoxes(data, child.body, child.finish, ctx)
                if media.kind = "hdlr"
                    nbCheck(not handlerSeen and media.finish - media.body >= 12, "missing or duplicate handler")
                    handlerSeen = true
                    code = ""
                    for i = media.body + 8 to media.body + 11
                        code += Chr(data[i])
                    end for
                    if code = "vide" then kind = "video"
                    if code = "soun" then kind = "audio"
                    nbCheck(kind <> "", "unknown track handler")
                else if media.kind = "minf"
                    nbInspectMinf(data, media, ctx)
                end if
            end for
        end if
    end for
    nbCheck(id <> invalid, "missing track ID")
    nbCheck(id > 0& and kind <> "", "invalid track ID or unknown handler")
    return [id, kind, idOffset]
end function

sub nbInspectMinf(data as object, minf as object, ctx as object)
    for each child in nbBoxes(data, minf.body, minf.finish, ctx)
        if child.kind = "stbl"
            for each table in nbBoxes(data, child.body, child.finish, ctx)
                if table.kind = "stsd"
                    nbCheck(table.finish - table.body >= 8, "truncated sample descriptions")
                    count = nbU32(data, table.body + 4, table.finish)
                    nbCheck(count <= 16&, "sample description limit")
                    entries = nbBoxes(data, table.body + 8, table.finish, ctx)
                    nbCheck(entries.Count() = count, "invalid sample description count")
                    for each entry in entries
                        nbInspectSampleEntry(data, entry, ctx)
                    end for
                end if
            end for
        end if
    end for
end sub

sub nbInspectSampleEntry(data as object, entry as object, ctx as object)
    nbCheck(entry.kind <> "encv" and entry.kind <> "enca", "encrypted sample description")
    skip = 78 ' VisualSampleEntry fields precede child codec boxes.
    if entry.kind = "mp4a"
        skip = 28
        nbCheck(entry.finish - entry.body >= skip, "truncated audio sample entry")
        nbCheck(data[entry.body + 8] = 0 and data[entry.body + 9] = 0, "only version-zero audio sample entries")
    else
        nbCheck(entry.kind = "avc1" or entry.kind = "avc3" or entry.kind = "hvc1" or entry.kind = "hev1" or entry.kind = "av01", "unknown sample entry")
    end if
    nbCheck(entry.finish - entry.body >= skip, "truncated visual/audio sample entry")
    ' Parse structural children so clear-named entries cannot conceal a sinf box.
    children = nbBoxes(data, entry.body + skip, entry.finish, ctx)
end sub

function nativeDemuxBulkInspectInit(data as object) as object
    nbCheck(Type(data) = "roByteArray", "init input type")
    nbCheck(data.Count() <= 2097152, "init input bound")
    ctx = nbContext()
    tracks = []
    for each atom in nbBoxes(data, 0, data.Count(), ctx)
        if atom.kind = "moov"
            for each child in nbBoxes(data, atom.body, atom.finish, ctx)
                if child.kind = "trak"
                    info = nbTrakInfo(data, child, ctx)
                    nbCheck(tracks.Count() < 8 and nbTrackKind(tracks, info[0]) = "", "track limit or duplicate ID")
                    tracks.Push([info[0], info[1]])
                end if
            end for
        end if
    end for
    nbCheck(tracks.Count() > 0, "init contains no valid tracks")
    return tracks
end function

function nativeDemuxBulkInit(data as object, keep as string) as object
    tracks = nativeDemuxBulkInspectInit(data)
    nbTrackMapValid(tracks, keep)
    ctx = nbContext()
    plan = []
    patches = []
    kept = 0
    trexIds = []
    for each atom in nbBoxes(data, 0, data.Count(), ctx)
        if atom.kind <> "moov"
            nbRaw(plan, atom.offset, atom.size)
        else
            bodyPlan = []
            bodyPatches = []
            for each child in nbBoxes(data, atom.body, atom.finish, ctx)
                if child.kind = "trak"
                    info = nbTrakInfo(data, child, ctx)
                    if nbTrackKind(tracks, info[0]) = keep
                        kept += 1
                        base = nbPlanSize(bodyPlan, ctx)
                        nbGenerated(bodyPlan, nbHeader("trak", 8 + child.finish - child.body))
                        nbRaw(bodyPlan, child.body, child.finish - child.body)
                        bodyPatches.Push([base + 8 + info[2] - child.body, 1&])
                    end if
                else if child.kind = "mvex"
                    mvexPlan = []
                    mvexPatches = []
                    for each entry in nbBoxes(data, child.body, child.finish, ctx)
                        if entry.kind <> "trex"
                            nbRaw(mvexPlan, entry.offset, entry.size)
                        else
                            nbCheck(entry.finish - entry.body >= 24 and data[entry.body] = 0, "truncated or unknown trex")
                            id = nbU32(data, entry.body + 4, entry.finish)
                            nbCheck(nbTrackKind(tracks, id) <> "", "trex track absent from init")
                            for each previous in trexIds
                                nbCheck(previous <> id, "duplicate trex track")
                            end for
                            trexIds.Push(id)
                            if nbTrackKind(tracks, id) = keep
                                cursor = nbPlanSize(mvexPlan, ctx)
                                nbRaw(mvexPlan, entry.offset, entry.size)
                                mvexPatches.Push([cursor + entry.header + 4, 1&])
                            end if
                        end if
                    end for
                    base = nbPlanSize(bodyPlan, ctx) + 8
                    nbGenerated(bodyPlan, nbHeader("mvex", 8 + nbPlanSize(mvexPlan, ctx)))
                    bodyPlan.Append(mvexPlan)
                    for each patch in mvexPatches
                        bodyPatches.Push([base + patch[0], patch[1]])
                    end for
                else
                    nbRaw(bodyPlan, child.offset, child.size)
                end if
            end for
            base = nbPlanSize(plan, ctx) + 8
            nbGenerated(plan, nbHeader("moov", 8 + nbPlanSize(bodyPlan, ctx)))
            plan.Append(bodyPlan)
            for each patch in bodyPatches
                patches.Push([base + patch[0], patch[1]])
            end for
        end if
    end for
    nbCheck(kept = 1, "init requested track missing or repeated")
    return nbBuild(data, plan, patches, ctx, 2097152)
end function

function nbTfhd(data as object, atom as object) as object
    nbCheck(atom.finish - atom.body >= 8 and data[atom.body] = 0, "truncated or unknown tfhd")
    flags = CInt(nbU32(data, atom.body, atom.finish) mod 16777216&)
    nbCheck((flags and 1) = 0 and (flags and &h020000) <> 0, "only movie-fragment-relative addressing")
    nbCheck((flags and &hfdffc4) = 0, "unsupported tfhd flags")
    id = nbU32(data, atom.body + 4, atom.finish)
    cursor = atom.body + 8
    if (flags and 2) <> 0 then cursor += 4
    if (flags and 8) <> 0 then cursor += 4
    size = 0&
    if (flags and 16) <> 0
        size = nbU32(data, cursor, atom.finish)
        cursor += 4
    end if
    if (flags and 32) <> 0 then cursor += 4
    nbCheck(cursor <= atom.finish, "truncated tfhd optional fields")
    return [id, size]
end function

function nbTrun(data as object, atom as object, defaultSize as longinteger, moofOffset as integer, ctx as object) as object
    nbCheck(atom.finish - atom.body >= 8, "truncated trun")
    version = data[atom.body]
    nbCheck(version = 0 or version = 1, "unknown trun version")
    flags = CInt(nbU32(data, atom.body, atom.finish) mod 16777216&)
    nbCheck((flags and &hfff0fa) = 0, "unsupported trun flags")
    count = nbU32(data, atom.body + 4, atom.finish)
    nbCheck(count <= 65536&, "sample count limit")
    ctx[1] += CInt(count)
    nbCheck(ctx[1] <= 65536, "sample work limit")
    cursor = atom.body + 8
    offset = 0&
    patch = -1
    if (flags and 1) <> 0
        offset = nbSigned32(data, cursor, atom.finish)
        patch = cursor
        cursor += 4
    end if
    if (flags and 4) <> 0 then cursor += 4
    stride = 0
    for each flag in [256, 512, 1024, 2048]
        if (flags and flag) <> 0 then stride += 4
    end for
    nbCheck(cursor <= atom.finish and count * stride <= atom.finish - cursor, "truncated trun samples")
    total = 0&
    if (flags and 512) = 0
        total = count * defaultSize
        nbCheck(total <= 4194304&, "sample byte limit")
    else
        for i = 1 to CInt(count)
            if (flags and 256) <> 0 then cursor += 4
            total += nbU32(data, cursor, atom.finish)
            nbCheck(total <= 4194304&, "sample byte limit")
            cursor += 4
            if (flags and 1024) <> 0 then cursor += 4
            if (flags and 2048) <> 0 then cursor += 4
        end for
    end if
    if total > 0& then nbCheck(patch >= 0, "sample runs need explicit offsets")
    return { atom: atom, start: moofOffset + offset, length: CInt(total), patch: patch }
end function

function nbTraf(data as object, traf as object, moof as object, mdat as object, tracks as object, ctx as object) as object
    children = nbBoxes(data, traf.body, traf.finish, ctx)
    info = invalid
    tfhdBox = invalid
    for each child in children
        nbCheck(child.kind = "tfhd" or child.kind = "tfdt" or child.kind = "trun" or child.kind = "free", "unsupported traf child")
        if child.kind = "tfhd"
            nbCheck(info = invalid, "duplicate tfhd")
            info = nbTfhd(data, child)
            tfhdBox = child
        else if child.kind = "tfdt"
            nbCheck(child.finish - child.body >= 4, "truncated tfdt")
            version = data[child.body]
            nbCheck(version = 0 or version = 1, "unknown tfdt version")
            required = 8
            if version = 1 then required = 12
            nbCheck(child.finish - child.body >= required, "truncated tfdt decode time")
        end if
    end for
    nbCheck(info <> invalid, "fragment missing tfhd")
    kind = nbTrackKind(tracks, info[0])
    nbCheck(kind <> "", "fragment track absent from init")
    runs = []
    sortedRuns = []
    total = 0
    for each child in children
        if child.kind = "trun"
            nbCheck(runs.Count() < 128, "run count limit")
            sampleRun = nbTrun(data, child, info[1], moof.offset, ctx)
            runs.Push(sampleRun)
            if sampleRun.length > 0
                nbCheck(sampleRun.start >= mdat.body and sampleRun.start <= mdat.finish - sampleRun.length, "sample data outside mdat")
                ' At most 128 runs; retain source declaration order separately.
                at = 0
                while at < sortedRuns.Count()
                    if sortedRuns[at].start > sampleRun.start then exit while
                    at += 1
                end while
                sortedRuns.Push(sampleRun)
                moveIndex = sortedRuns.Count() - 1
                while moveIndex > at
                    sortedRuns[moveIndex] = sortedRuns[moveIndex - 1]
                    moveIndex -= 1
                end while
                sortedRuns[at] = sampleRun
                total += sampleRun.length
                nbCheck(total <= 4194304, "retained sample limit")
            end if
        end if
    end for
    nbCheck(total > 0, "fragment has no sample data")
    finish = mdat.body + 0&
    for each sampleRun in sortedRuns
        nbCheck(sampleRun.start >= finish, "overlapping sample runs")
        finish = sampleRun.start + sampleRun.length
    end for
    return { kind: kind, children: children, runs: runs, tfhd: tfhdBox, traf: traf, total: total }
end function

function nativeDemuxBulkFragment(data as object, tracks as object, keep as string) as object
    nbCheck(Type(data) = "roByteArray", "fragment input type")
    nbCheck(data.Count() <= 4194304, "fragment input bound")
    nbTrackMapValid(tracks, keep)
    ctx = nbContext()
    plan = []
    patches = []
    pending = invalid
    fragments = 0
    for each atom in nbBoxes(data, 0, data.Count(), ctx)
        if atom.kind = "moof"
            nbCheck(pending = invalid, "moof missing following mdat")
            pending = atom
        else if atom.kind = "mdat"
            nbCheck(pending <> invalid, "mdat has no moof")
            fragments += 1
            nbCheck(fragments <= 64, "fragment count limit")
            nonTraf = []
            kept = invalid
            for each child in nbBoxes(data, pending.body, pending.finish, ctx)
                if child.kind <> "traf"
                    nbRaw(nonTraf, child.offset, child.size)
                else
                    info = nbTraf(data, child, pending, atom, tracks, ctx)
                    if info.kind = keep
                        nbCheck(kept = invalid, "multiple requested trafs")
                        kept = info
                    end if
                end if
            end for
            nbCheck(kept <> invalid, "fragment requested track missing")
            traf = kept.traf
            moofSize = 8 + nbPlanSize(nonTraf, ctx) + 8 + traf.finish - traf.body
            nbGenerated(plan, nbHeader("moof", moofSize))
            plan.Append(nonTraf)
            trafBase = nbPlanSize(plan, ctx)
            nbGenerated(plan, nbHeader("traf", 8 + traf.finish - traf.body))
            nbRaw(plan, traf.body, traf.finish - traf.body)
            tfhd = kept.tfhd
            patches.Push([trafBase + 8 + tfhd.body + 4 - traf.body, 1&])
            running = moofSize + 8&
            for each sampleRun in kept.runs
                if sampleRun.patch >= 0
                    patches.Push([trafBase + 8 + sampleRun.patch - traf.body, running])
                    running += sampleRun.length
                end if
            end for
            nbGenerated(plan, nbHeader("mdat", kept.total + 8))
            for each sampleRun in kept.runs
                nbRaw(plan, CInt(sampleRun.start), sampleRun.length)
            end for
            pending = invalid
        else if atom.kind = "emsg"
            if keep = "video" then nbRaw(plan, atom.offset, atom.size)
        else if atom.kind <> "sidx" and atom.kind <> "mfra"
            nbRaw(plan, atom.offset, atom.size)
        end if
    end for
    nbCheck(pending = invalid and fragments > 0, "media has no complete requested fragment")
    return nbBuild(data, plan, patches, ctx, 4194304)
end function
