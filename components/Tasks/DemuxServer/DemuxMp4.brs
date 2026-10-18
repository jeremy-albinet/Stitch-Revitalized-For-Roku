' Port of fmp4-demux-proxy's fmp4.py: splits muxed fMP4 into single-track segments.

function u32(b as object, i as integer) as integer
    return (b[i] << 24) or (b[i + 1] << 16) or (b[i + 2] << 8) or b[i + 3]
end function

sub putU32(b as object, i as integer, v as integer)
    b[i] = (v >> 24) and &hFF
    b[i + 1] = (v >> 16) and &hFF
    b[i + 2] = (v >> 8) and &hFF
    b[i + 3] = v and &hFF
end sub

sub pushU32(b as object, v as integer)
    b.Push((v >> 24) and &hFF)
    b.Push((v >> 16) and &hFF)
    b.Push((v >> 8) and &hFF)
    b.Push(v and &hFF)
end sub

sub pushType(b as object, t as string)
    for i = 0 to 3
        b.Push(Asc(t.Mid(i, 1)))
    end for
end sub

' Lists the boxes between start and finish: { off, hdr, size, name }.
function listBoxes(b as object, start as integer, finish as integer) as object
    boxes = []
    off = start
    while off < finish
        if finish - off < 8 then throw "box header cut off at " + off.toStr()
        size = u32(b, off)
        hdr = 8
        if size = 1
            ' 64-bit size: only the low 32 bits are supported.
            if u32(b, off + 8) <> 0 then throw "box too large at " + off.toStr()
            size = u32(b, off + 12)
            hdr = 16
        else if size = 0
            size = finish - off
        end if
        if size < hdr or off + size > finish then throw "bad box size at " + off.toStr()
        typ = chr(b[off + 4]) + chr(b[off + 5]) + chr(b[off + 6]) + chr(b[off + 7])
        boxes.Push({ off: off, hdr: hdr, size: size, name: typ })
        off = off + size
    end while
    return boxes
end function

function trackIs(tm as object, id as integer, keep as string) as boolean
    kind = tm[id.toStr()]
    if kind = invalid then return false
    return kind = keep
end function

function findChild(b as object, parent as object, typ as string) as object
    for each ch in listBoxes(b, parent.off + parent.hdr, parent.off + parent.size)
        if ch.name = typ then return ch
    end for
    return invalid
end function

' Appends a byte range; large ranges are read straight from the file.
sub appendRange(out as object, b as object, file as string, off as integer, size as integer)
    if size > 4096
        chunk = CreateObject("roByteArray")
        chunk.ReadFile(file, off, size)
        out.Append(chunk)
    else
        last = off + size - 1
        for i = off to last
            out.Push(b[i])
        end for
    end if
end sub

function tkhdTrackId(b as object, trak as object) as dynamic
    tk = findChild(b, trak, "tkhd")
    if tk = invalid then return invalid
    body = tk.off + tk.hdr
    if b[body] = 0 then return u32(b, body + 12)
    return u32(b, body + 20)
end function

function trakKind(b as object, trak as object) as string
    mdia = findChild(b, trak, "mdia")
    if mdia = invalid then return "other"
    hdlr = findChild(b, mdia, "hdlr")
    if hdlr = invalid or hdlr.size - hdlr.hdr < 12 then return "other"
    body = hdlr.off + hdlr.hdr
    h = chr(b[body + 8]) + chr(b[body + 9]) + chr(b[body + 10]) + chr(b[body + 11])
    if h = "vide" then return "video"
    if h = "soun" then return "audio"
    return "other"
end function

' { "trackId": "video" | "audio" | "other" } from an init segment.
function extractTrackMap(b as object) as object
    tm = {}
    for each bx in listBoxes(b, 0, b.Count())
        if bx.name = "moov"
            for each ch in listBoxes(b, bx.off + bx.hdr, bx.off + bx.size)
                if ch.name = "trak"
                    tid = tkhdTrackId(b, ch)
                    if tid <> invalid then tm[tid.toStr()] = trakKind(b, ch)
                end if
            end for
        end if
    end for
    return tm
end function

' Init segment: keep only the wanted track's trak and trex, renumbered to track 1.
function splitInit(b as object, file as string, tm as object, keep as string) as object
    out = CreateObject("roByteArray")
    for each bx in listBoxes(b, 0, b.Count())
        if bx.name <> "moov"
            appendRange(out, b, file, bx.off, bx.size)
        else
            moovStart = out.Count()
            pushU32(out, 0)
            pushType(out, "moov")
            for each ch in listBoxes(b, bx.off + bx.hdr, bx.off + bx.size)
                if ch.name = "trak"
                    tid = tkhdTrackId(b, ch)
                    if tid <> invalid and trackIs(tm, tid, keep)
                        start = out.Count()
                        appendRange(out, b, file, ch.off, ch.size)
                        tk = findChild(b, ch, "tkhd")
                        idPos = start + (tk.off - ch.off) + tk.hdr + 12
                        if b[tk.off + tk.hdr] <> 0 then idPos = idPos + 8
                        putU32(out, idPos, 1)
                    end if
                else if ch.name = "mvex"
                    mvexStart = out.Count()
                    pushU32(out, 0)
                    pushType(out, "mvex")
                    for each t in listBoxes(b, ch.off + ch.hdr, ch.off + ch.size)
                        if t.name <> "trex"
                            appendRange(out, b, file, t.off, t.size)
                        else if t.size - t.hdr >= 8 and trackIs(tm, u32(b, t.off + t.hdr + 4), keep)
                            start = out.Count()
                            appendRange(out, b, file, t.off, t.size)
                            putU32(out, start + t.hdr + 4, 1)
                        end if
                    end for
                    putU32(out, mvexStart, out.Count() - mvexStart)
                else
                    appendRange(out, b, file, ch.off, ch.size)
                end if
            end for
            putU32(out, moovStart, out.Count() - moovStart)
        end if
    end for
    return out
end function

function tfhdDefaultSize(b as object, body as integer) as integer
    flags = (b[body + 1] << 16) or (b[body + 2] << 8) or b[body + 3]
    off = body + 8
    if (flags and &h1) <> 0 then off = off + 8
    if (flags and &h2) <> 0 then off = off + 4
    if (flags and &h8) <> 0 then off = off + 4
    if (flags and &h10) <> 0 then return u32(b, off)
    return 0
end function

' { dataOffset, total, hasOffset } for one trun.
function trunInfo(b as object, body as integer, defSize as integer) as object
    flags = (b[body + 1] << 16) or (b[body + 2] << 8) or b[body + 3]
    count = u32(b, body + 4)
    off = body + 8
    dataOffset = 0
    hasOffset = (flags and &h1) <> 0
    if hasOffset
        dataOffset = u32(b, off)
        off = off + 4
    end if
    if (flags and &h4) <> 0 then off = off + 4
    total = 0
    if (flags and &h200) <> 0
        stride = 4
        sizeAt = 0
        if (flags and &h100) <> 0
            stride = stride + 4
            sizeAt = 4
        end if
        if (flags and &h400) <> 0 then stride = stride + 4
        if (flags and &h800) <> 0 then stride = stride + 4
        p = off + sizeAt
        for s = 1 to count
            total = total + u32(b, p)
            p = p + stride
        end for
    else
        total = count * defSize
    end if
    return { dataOffset: dataOffset, total: total, hasOffset: hasOffset }
end function

' Media segment: for each moof+mdat pair keep only the wanted track's traf and data.
function splitMedia(b as object, file as string, tm as object, keep as string) as object
    out = CreateObject("roByteArray")
    pendingMoof = invalid
    for each bx in listBoxes(b, 0, b.Count())
        if bx.name = "emsg"
            if keep = "video" then appendRange(out, b, file, bx.off, bx.size)
        else if bx.name = "moof"
            pendingMoof = bx
        else if bx.name = "mdat" and pendingMoof <> invalid
            splitFragment(out, b, file, tm, keep, pendingMoof, bx)
            pendingMoof = invalid
        else
            appendRange(out, b, file, bx.off, bx.size)
        end if
    end for
    return out
end function

sub splitFragment(out as object, b as object, file as string, tm as object, keep as string, moof as object, mdat as object)
    nonTraf = []
    kept = invalid
    for each ch in listBoxes(b, moof.off + moof.hdr, moof.off + moof.size)
        if ch.name <> "traf"
            nonTraf.Push(ch)
        else
            tfhd = findChild(b, ch, "tfhd")
            if tfhd <> invalid and trackIs(tm, u32(b, tfhd.off + tfhd.hdr + 4), keep) then kept = ch
        end if
    end for

    if kept = invalid
        appendRange(out, b, file, moof.off, moof.size)
        appendRange(out, b, file, mdat.off, mdat.size)
        return
    end if

    kids = listBoxes(b, kept.off + kept.hdr, kept.off + kept.size)
    defSize = 0
    for each k in kids
        if k.name = "tfhd"
            defSize = tfhdDefaultSize(b, k.off + k.hdr)
            exit for
        end if
    end for

    moofSize = 8 + kept.size
    for each ch in nonTraf
        moofSize = moofSize + ch.size
    end for

    pushU32(out, moofSize)
    pushType(out, "moof")
    for each ch in nonTraf
        appendRange(out, b, file, ch.off, ch.size)
    end for
    trafStart = out.Count()
    appendRange(out, b, file, kept.off, kept.size)

    ' Renumber to track 1 and point each trun at its data in the new mdat.
    running = moofSize + 8
    ranges = []
    dataTotal = 0
    for each k in kids
        at = trafStart + (k.off - kept.off)
        if k.name = "tfhd"
            putU32(out, at + k.hdr + 4, 1)
        else if k.name = "trun"
            info = trunInfo(b, k.off + k.hdr, defSize)
            if info.total > 0
                ranges.Push({ start: moof.off + info.dataOffset, size: info.total })
                dataTotal = dataTotal + info.total
            end if
            if info.hasOffset
                putU32(out, at + k.hdr + 8, running)
                running = running + info.total
            end if
        end if
    end for

    pushU32(out, 8 + dataTotal)
    pushType(out, "mdat")
    for each r in ranges
        appendRange(out, b, file, r.start, r.size)
    end for
end sub

function isMpegTs(b as object) as boolean
    if b.Count() < 1 or b[0] <> &h47 then return false
    return b.Count() < 189 or b[188] = &h47
end function
