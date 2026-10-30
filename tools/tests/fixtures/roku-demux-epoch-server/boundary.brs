' Native socket/Core/decoder boundaries are explicit; all Server/Protocol/
' actual initialization parsers/gate handlers execute unchanged production code.
function esClock() as dynamic
    return m.values[m.index]
end function

function esReadable() as boolean
    return true
end function

function esReceiveCount() as integer
    return m.io[0].Count() - m.io[1]
end function

function esReceive(data as object, start as integer, amount as integer) as integer
    size = amount
    if size > m.io[0].Count() - m.io[1] then size = m.io[0].Count() - m.io[1]
    for i = 0 to size - 1
        data[start + i] = m.io[0][m.io[1] + i]
    end for
    m.io[1] += size
    return size
end function

function esWritable() as boolean
    return true
end function

function esSend(data as object, start as integer, amount as integer) as integer
    if m.io[5][0] then return -1
    if m.io[6] <> ""
        leased = false
        for each record in m.io[4]
            if record[0] = m.io[6] and record[3] > 0 then leased = true
        end for
        if not leased then throw "fixture-boundary: lease remains acquired through actual send"
    end if
    m.io[3].Push("send")
    for i = 0 to amount - 1
        m.io[2].Push(data[start + i])
    end for
    return amount
end function

function esSocketOk() as boolean
    return not m.io[5][0]
end function

sub esNotify(value as boolean)
end sub

sub esSocketClose()
    m.io[3].Push("socket-close")
end sub

sub esObserve(field as string, port as object)
    m.observers.Push("observe:" + field)
end sub

sub esUnobserve(field as string)
    m.observers.Push("unobserve:" + field)
end sub

function nativeLiveCreate(url as string, nowMs as dynamic, delaySeconds as integer, origins as object, trusted as boolean, cacheBudget as dynamic, options as dynamic) as object
    m.createCount += 1
    m.createOptions = options
    throw "explicit Core/network creation boundary"
end function

sub nativeLiveTick(state as object, port as object, nowMs as dynamic)
    m.tickCount += 1
end sub

function nativeLiveHandleUrlEvent(state as object, event as object, nowMs as dynamic) as boolean
    return false
end function

function nativeLiveDiagnostics(state as object) as object
    result = { phase: "ready", failed: false, failureCategory: 0, generation: 1,
        cacheBytes: 4, peakCacheBytes: 4, assetCount: m.cache.Count(), fetchCount: 1, playlistCount: 1,
        initPairCount: 1, segmentPairCount: 3, transferActive: false, inputRetained: false, inputFilePresent: false, closed: false }
    if m.coreClosed
        result.closed = true
        result.cacheBytes = 0
        result.peakCacheBytes = 4
        result.assetCount = 0
    end if
    return result
end function

function nativeLivePublication(state as object) as dynamic
    return m.nextPublication
end function

sub nativeLiveRetire(state as object, generation as dynamic)
    m.events.Push("retire:" + generation.ToStr())
end sub

function esFind(id as string) as dynamic
    for each record in m.cache
        if record[0] = id then return record
    end for
    return invalid
end function

function esLeases(id as string) as integer
    record = esFind(id)
    if record = invalid then return 0
    return record[3]
end function

function nativeLiveAcquire(state as object, id as string) as dynamic
    record = esFind(id)
    if record = invalid then return invalid
    record[3] += 1
    m.events.Push("acquire:" + id)
    result = { id: id, kind: record[1], mime: record[1] + "/mp4", size: record[2].Count(), data: record[2] }
    if m.corruptAsset = id then result.kind = "wrong"
    if m.stopOnAcquire then m.top.stopRequested = true
    return result
end function

sub nativeLiveRelease(state as object, id as string)
    record = esFind(id)
    esAssert(record <> invalid and record[3] > 0, "release has an actual corresponding acquisition")
    record[3] -= 1
    m.events.Push("release:" + id)
end sub

function nativeLiveClose(state as object) as boolean
    m.coreClosed = true
    for each record in m.cache
        esAssert(record[3] = 0, "worker close has no unclosed lease")
    end for
    m.cache.Clear()
    return true
end function

function isTwitchVariantSupported(variant as object, device = invalid as dynamic) as boolean
    m.decodeCount += 1
    m.events.Push("decoder")
    if m.stopDuringDecode then m.top.stopRequested = true
    return m.decoderAllowed
end function

function twitchVariantVideoFormat(variant as object) as string
    return "h264"
end function

' Current base Core still rejects true options. Only this explicitly labeled
' future-Core identity boundary permits a genuine next source epoch here.
function nlInitDigest(state as object, payload as object) as string
    m.events.Push("identity")
    digest = nbBulkDigest(payload)
    if state.phase = "init-rotation"
        if state.pendingWindow.epoch = state.epoch
            nlCheck(payload.Count() = state.initByteCount and digest = state.initDigest, "selected map initialization changed")
        else
            nlCheck(state.pendingWindow.epoch = state.epoch + 1&, "selected epoch invalid")
        end if
    end if
    return digest
end function

sub nativeLiveFeed(state as object, kind as string, payload as dynamic, nowMs as dynamic)
    m.feedCount += 1
    m.events.Push("feed")
end sub
