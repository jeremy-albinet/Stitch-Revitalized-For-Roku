' Pure Task-private completed-recording cache. Import rokuVodIndex.brs and
' unchanged rokuDemuxBulk.brs. No network, clock, file or SceneGraph operations.

sub nvcCheck(ok as boolean)
    if not ok then throw "vod-cache: invalid state"
end sub

function nvcKeys(value as dynamic, keys as object) as boolean
    if type(value) <> "roAssociativeArray" then return false
    if value.Count() <> keys.Count() then return false
    for each key in keys
        if not value.DoesExist(key) then return false
    end for
    return true
end function

function nvcString(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "String" or kind = "roString"
end function

function nvcSession(value as dynamic) as boolean
    if not nvcString(value) then return false
    if value.Len() <> 32 then return false
    for i = 0 to 31
        if "0123456789abcdef".InStr(value.Mid(i, 1)) < 0 then return false
    end for
    return true
end function

function nvcRandomId() as string
    value = lcase(CreateObject("roDeviceInfo").GetRandomUUID()).Replace("-", "")
    nvcCheck(nvcSession(value))
    return value
end function

function nvcIndexSnapshot(index as object) as object
    copy = {}
    for each key in ["version", "raw", "records", "count", "sequence", "totalUs", "targetDuration", "mapUri", "sourceUrl", "approvedOrigin"]
        copy[key] = index[key]
    end for
    return copy
end function

function nvcIndexIdentity(index as object) as string
    primitive = { count: index.count, sequence: index.sequence, totalUs: index.totalUs, targetDuration: index.targetDuration, mapUri: index.mapUri, sourceUrl: index.sourceUrl, approvedOrigin: index.approvedOrigin }
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(FormatJson(primitive))
    nvcCheck(bytes.Count() > 0 and bytes.Count() <= 24576)
    return nbBulkDigest(bytes)
end function

function rokuVodCacheCreate(sessionId as dynamic, index as dynamic, scratchBytes = 65536& as dynamic) as dynamic
    try
        if not nvcSession(sessionId) or not nviIndexValid(index) then return invalid
        if not nviInteger(scratchBytes) then return invalid
        if scratchBytes < 32768& or scratchBytes > 65536& then return invalid
        if rokuVodIndexEntry(index, 0) = invalid or rokuVodIndexEntry(index, index.count - 1) = invalid then return invalid
        indexBytes = index.raw.Count() + index.records.Count() + index.sourceUrl.Len() + index.mapUri.Len() + index.approvedOrigin.Len() + 0&
        if indexBytes > 524288& then return invalid
        snapshot = nvcIndexSnapshot(index)
        return {
            version: 1, sessionId: sessionId, authority: nvcRandomId(), index: snapshot,
            rawDigest: nbBulkDigest(snapshot.raw), recordsDigest: nbBulkDigest(snapshot.records), indexIdentity: nvcIndexIdentity(snapshot), indexBytes: indexBytes, scratchBytes: scratchBytes,
            cacheBudgetBytes: 25165824&, logicalBudgetBytes: 67108864&, workBudgetBytes: 50331648&,
            pairs: [], leases: [], reservation: invalid, cacheBytes: 0&, peakCacheBytes: 0&, stamp: 0&, serial: 0&,
            hits: 0&, admissions: 0&, evictions: 0&, initialized: false, closed: false, faulted: false, cleanupBlocked: false, reason: ""
        }
    catch error
        return invalid
    end try
end function

function nvcShape(state as dynamic) as boolean
    keys = ["version", "sessionId", "authority", "index", "rawDigest", "recordsDigest", "indexIdentity", "indexBytes", "scratchBytes", "cacheBudgetBytes", "logicalBudgetBytes", "workBudgetBytes", "pairs", "leases", "reservation", "cacheBytes", "peakCacheBytes", "stamp", "serial", "hits", "admissions", "evictions", "initialized", "closed", "faulted", "cleanupBlocked", "reason"]
    if not nvcKeys(state, keys) then return false
    if type(state.pairs) <> "roArray" or type(state.leases) <> "roArray" then return false
    if state.pairs.Count() > 16 or state.leases.Count() > 8 then return false
    for each key in ["version", "indexBytes", "scratchBytes", "cacheBudgetBytes", "logicalBudgetBytes", "workBudgetBytes", "cacheBytes", "peakCacheBytes", "stamp", "serial", "hits", "admissions", "evictions"]
        if not nviInteger(state[key]) then return false
    end for
    for each key in ["initialized", "closed", "faulted", "cleanupBlocked"]
        kind = type(state[key], 3)
        if kind <> "Boolean" and kind <> "roBoolean" then return false
    end for
    if state.version <> 1 or state.cacheBudgetBytes <> 25165824& or state.logicalBudgetBytes <> 67108864& or state.workBudgetBytes <> 50331648& then return false
    if state.indexBytes < 0& or state.indexBytes > 524288& or state.scratchBytes < 32768& or state.scratchBytes > 65536& then return false
    for each key in ["cacheBytes", "peakCacheBytes"]
        if state[key] < 0& or state[key] > state.cacheBudgetBytes then return false
    end for
    for each key in ["stamp", "serial", "hits", "admissions", "evictions"]
        if state[key] < 0& or state[key] > 4294967295& then return false
    end for
    if not nvcString(state.reason) then return false
    return state.reason.Len() <= 64
end function

sub nvcFault(state as object, reason as string)
    state.faulted = true
    state.cleanupBlocked = true
    state.reason = reason
end sub

function nvcToken(state as object) as string
    nvcCheck(state.serial < 4294967295&)
    nextSerial = state.serial + 1&
    token = state.authority + ":" + nextSerial.ToStr() + ":" + nvcRandomId()
    nvcCheck(token.Len() >= 67 and token.Len() <= 76)
    state.serial = nextSerial
    return token
end function

function nvcPairAt(state as object, entryNo as integer) as integer
    for i = 0 to state.pairs.Count() - 1
        if state.pairs[i].entryNo = entryNo then return i
    end for
    return -1
end function

function nvcLeased(state as object, entryNo as integer) as boolean
    for each lease in state.leases
        if lease.entryNo = entryNo then return true
    end for
    return false
end function

function nvcIndexUnchanged(state as object) as boolean
    if not nviIndexValid(state.index) then return false
    actualBytes = state.index.raw.Count() + state.index.records.Count() + state.index.sourceUrl.Len() + state.index.mapUri.Len() + state.index.approvedOrigin.Len() + 0&
    if actualBytes <> state.indexBytes then return false
    if nbBulkDigest(state.index.raw) <> state.rawDigest or nbBulkDigest(state.index.records) <> state.recordsDigest then return false
    return nvcIndexIdentity(state.index) = state.indexIdentity
end function

function nvcOpaqueId(state as object, value as dynamic) as boolean
    if not nvcString(value) then return false
    if value.Len() < 67 or value.Len() > 76 or value.Left(33) <> state.authority + ":" then return false
    parts = value.Split(":")
    if parts.Count() <> 3 or not nvcSession(parts[2]) then return false
    number = 0&
    digits = parts[1]
    if digits.Len() < 1 or digits.Len() > 10 or digits.Left(1) = "0" then return false
    for i = 0 to digits.Len() - 1
        digit = Asc(digits.Mid(i, 1)) - 48
        if digit < 0 or digit > 9 then return false
        if number > (4294967295& - digit) \ 10& then return false
        number = number * 10& + digit
    end for
    return number >= 1& and number <= state.serial
end function

function nvcLeaseRegistryValid(state as object) as boolean
    tokens = {}
    for each lease in state.leases
        if not nvcKeys(lease, ["id", "entryNo", "track"]) then return false
        if not nvcOpaqueId(state, lease.id) or tokens.DoesExist(lease.id) then return false
        if not nviInteger(lease.entryNo) then return false
        if lease.track <> "video" and lease.track <> "audio" then return false
        if nvcPairAt(state, lease.entryNo) < 0 then return false
        tokens[lease.id] = true
    end for
    return true
end function

function nvcValidate(state as object, checkIndex = true as boolean) as boolean
    try
        if not nvcShape(state) or state.closed then return false
        if not nvcSession(state.sessionId) or not nvcSession(state.authority) then return false
        if checkIndex and not nvcIndexUnchanged(state) then return false
        total = 0&
        initCount = 0
        seen = {}
        for each item in state.pairs
            if not nvcKeys(item, ["entryNo", "video", "audio", "videoBytes", "audioBytes", "videoDigest", "audioDigest", "stamp", "pinned"]) then return false
            if not nviInteger(item.entryNo) or not nviInteger(item.videoBytes) or not nviInteger(item.audioBytes) or not nviInteger(item.stamp) then return false
            if item.entryNo < -1 or item.entryNo >= state.index.count or item.stamp < 1& or item.stamp > state.stamp then return false
            if seen.DoesExist(item.entryNo.ToStr()) then return false
            seen[item.entryNo.ToStr()] = true
            if type(item.video) <> "roByteArray" or type(item.audio) <> "roByteArray" then return false
            if item.videoBytes < 1 or item.videoBytes > 16777216 or item.audioBytes < 1 or item.audioBytes > 16777216 then return false
            if item.video.Count() <> item.videoBytes or item.audio.Count() <> item.audioBytes then return false
            if item.videoBytes + item.audioBytes > 16777216 then return false
            if not nvcString(item.videoDigest) or not nvcString(item.audioDigest) then return false
            if item.videoDigest.Len() <> 64 or item.audioDigest.Len() <> 64 then return false
            if type(item.pinned, 3) <> "Boolean" and type(item.pinned, 3) <> "roBoolean" then return false
            if item.entryNo = -1
                initCount += 1
                if item.pinned <> true or item.videoBytes > 2097152 or item.audioBytes > 2097152 then return false
            else if item.pinned <> false
                return false
            end if
            total += item.videoBytes + item.audioBytes
        end for
        if total <> state.cacheBytes or total > state.cacheBudgetBytes or state.peakCacheBytes < total then return false
        if state.initialized <> (initCount = 1) or initCount > 1 then return false
        if not nvcLeaseRegistryValid(state) then return false
        work = 0&
        if state.reservation <> invalid
            pending = state.reservation
            if not nvcKeys(pending, ["id", "entryNo", "workBytes", "maxPairBytes"]) then return false
            if not nvcOpaqueId(state, pending.id) then return false
            for each lease in state.leases
                if lease.id = pending.id then return false
            end for
            if not nviInteger(pending.entryNo) or pending.entryNo < -1 or pending.entryNo >= state.index.count then return false
            if not nviInteger(pending.workBytes) or not nviInteger(pending.maxPairBytes) then return false
            if pending.workBytes <> state.workBudgetBytes then return false
            expected = 16777216&
            if pending.entryNo = -1 then expected = 4194304&
            if pending.maxPairBytes <> expected or nvcPairAt(state, pending.entryNo) >= 0 then return false
            if total > state.cacheBudgetBytes - pending.maxPairBytes then return false
            work = pending.workBytes
        end if
        return total + work + state.indexBytes + state.scratchBytes <= state.logicalBudgetBytes
    catch error
        return false
    end try
end function

function rokuVodCacheAuthorize(state as dynamic, sessionId as dynamic, track as dynamic, entryNo as dynamic) as boolean
    try
        if not nvcShape(state) then return false
        if state.closed or state.faulted or state.cleanupBlocked then return false
        if not nvcValidate(state) then
            nvcFault(state, "cache_corrupt")
            return false
        end if
        if not nvcSession(sessionId) or sessionId <> state.sessionId then return false
        if track <> "video" and track <> "audio" then return false
        if not nviInteger(entryNo) then return false
        if entryNo = -1 then return true
        if entryNo < 0 or entryNo >= state.index.count then return false
        return rokuVodIndexEntry(state.index, entryNo) <> invalid
    catch error
        return false
    end try
end function

function rokuVodReserve(state as dynamic, entryNo as dynamic, sessionId as dynamic) as dynamic
    try
        if not rokuVodCacheAuthorize(state, sessionId, "video", entryNo) then return invalid
        if state.reservation <> invalid then
            state.reason = "work_busy"
            return invalid
        end if
        if nvcPairAt(state, entryNo) >= 0 then
            state.reason = "already_cached"
            return invalid
        end if
        if entryNo >= 0 and not state.initialized then
            state.reason = "init_required"
            return invalid
        end if
        if state.serial >= 4294967295& or state.evictions > 4294967295& - state.pairs.Count() then
            state.reason = "counter_exhausted"
            return invalid
        end if
        maxPair = 16777216&
        if entryNo = -1 then maxPair = 4194304&
        byteLimit = state.cacheBudgetBytes - maxPair
        workLimit = state.logicalBudgetBytes - state.workBudgetBytes - state.indexBytes - state.scratchBytes
        if workLimit < byteLimit then byteLimit = workLimit
        remainingBytes = state.cacheBytes
        remainingPairs = state.pairs.Count()
        remove = []
        while remainingBytes > byteLimit or remainingPairs > 15
            chosen = invalid
            for each item in state.pairs
                excluded = false
                for each prior in remove
                    if prior = item.entryNo then excluded = true
                end for
                if not excluded and not item.pinned and not nvcLeased(state, item.entryNo)
                    if chosen = invalid
                        chosen = item
                    else if item.stamp < chosen.stamp
                        chosen = item
                    end if
                end if
            end for
            if chosen = invalid
                state.reason = "work_budget"
                return invalid
            end if
            remove.Push(chosen.entryNo)
            remainingBytes -= chosen.videoBytes + chosen.audioBytes
            remainingPairs -= 1
        end while
        token = nvcToken(state)
        retained = []
        for each item in state.pairs
            keep = true
            for each entry in remove
                if entry = item.entryNo then keep = false
            end for
            if keep then retained.Push(item)
        end for
        ' No removal happens until the complete eviction plan and opaque token
        ' exist. Both tracks of each unleased pair leave in the same assignment.
        state.pairs = retained
        state.cacheBytes = remainingBytes
        state.evictions += remove.Count()
        state.reservation = { id: token, entryNo: entryNo, workBytes: state.workBudgetBytes, maxPairBytes: maxPair }
        state.reason = ""
        return { id: token, entryNo: entryNo, workBytes: state.workBudgetBytes, maxPairBytes: maxPair }
    catch error
        if nvcShape(state) then nvcFault(state, "cache_corrupt")
        return invalid
    end try
end function

function rokuVodStore(state as dynamic, reservationId as dynamic, sessionId as dynamic, entryNo as dynamic, pair as dynamic) as boolean
    try
        if not nvcShape(state) then return false
        if state.closed or state.faulted or state.cleanupBlocked then return false
        if not nvcValidate(state) then
            nvcFault(state, "cache_corrupt")
            return false
        end if
        if not nvcString(reservationId) or not nvcSession(sessionId) or sessionId <> state.sessionId or state.reservation = invalid then return false
        pending = state.reservation
        if pending.id <> reservationId or not nviInteger(entryNo) or entryNo <> pending.entryNo then return false
        if not nvcKeys(pair, ["video", "audio"]) then
            state.reason = "invalid_pair"
            return false
        end if
        if type(pair.video) <> "roByteArray" or type(pair.audio) <> "roByteArray" then
            state.reason = "invalid_pair"
            return false
        end if
        video = pair.video
        audio = pair.audio
        limit = 16777216
        if entryNo = -1 then limit = 2097152
        if video.Count() < 1 or video.Count() > limit or audio.Count() < 1 or audio.Count() > limit then
            state.reason = "invalid_pair"
            return false
        end if
        pairBytes = video.Count() + audio.Count() + 0&
        if pairBytes > pending.maxPairBytes or pairBytes > state.cacheBudgetBytes - state.cacheBytes or state.pairs.Count() > 15 then
            state.reason = "cache_budget"
            return false
        end if
        if state.cacheBytes + pairBytes + state.indexBytes + state.scratchBytes > state.logicalBudgetBytes then
            state.reason = "cache_budget"
            return false
        end if
        if state.stamp >= 4294967295& or state.admissions >= 4294967295& then
            state.reason = "counter_exhausted"
            return false
        end if
        newStamp = state.stamp + 1&
        item = { entryNo: entryNo, video: video, audio: audio, videoBytes: video.Count(), audioBytes: audio.Count(), videoDigest: nbBulkDigest(video), audioDigest: nbBulkDigest(audio), stamp: newStamp, pinned: entryNo = -1 }
        updated = []
        for each existing in state.pairs
            updated.Push(existing)
        end for
        updated.Push(item)
        ' Caller must have released all source/chunk/helper work except this
        ' complete pair before consuming the reservation into cache ownership.
        state.pairs = updated
        state.cacheBytes += pairBytes
        if state.cacheBytes > state.peakCacheBytes then state.peakCacheBytes = state.cacheBytes
        state.stamp = newStamp
        state.admissions += 1&
        state.initialized = true
        state.reservation = invalid
        state.reason = ""
        return true
    catch error
        if nvcShape(state) then nvcFault(state, "cache_corrupt")
        return false
    end try
end function

function rokuVodAcquire(state as dynamic, track as dynamic, entryNo as dynamic, sessionId as dynamic) as dynamic
    try
        if not rokuVodCacheAuthorize(state, sessionId, track, entryNo) then return invalid
        at = nvcPairAt(state, entryNo)
        if at < 0
            state.reason = "cache_miss"
            return invalid
        end if
        if state.leases.Count() >= 8 then
            state.reason = "lease_limit"
            return invalid
        end if
        if state.stamp >= 4294967295& or state.serial >= 4294967295& or state.hits >= 4294967295& then
            state.reason = "counter_exhausted"
            return invalid
        end if
        item = state.pairs[at]
        if nbBulkDigest(item.video) <> item.videoDigest or nbBulkDigest(item.audio) <> item.audioDigest
            nvcFault(state, "asset_mutated")
            return invalid
        end if
        token = nvcToken(state)
        item.stamp = state.stamp + 1&
        entries = state.pairs
        entries[at] = item
        state.pairs = entries
        state.stamp = item.stamp
        leases = state.leases
        leases.Push({ id: token, entryNo: entryNo, track: track })
        state.leases = leases
        state.hits += 1&
        state.reason = ""
        data = item.video
        if track = "audio" then data = item.audio
        return { id: token, entryNo: entryNo, track: track, size: data.Count(), data: data }
    catch error
        if nvcShape(state) then nvcFault(state, "cache_corrupt")
        return invalid
    end try
end function

function rokuVodRelease(state as dynamic, leaseId as dynamic, sessionId as dynamic) as boolean
    try
        if not nvcShape(state) or state.closed then return false
        if not nvcString(leaseId) or not nvcSession(sessionId) or sessionId <> state.sessionId then return false
        if not nvcOpaqueId(state, leaseId) or not nvcLeaseRegistryValid(state) then return false
        kept = []
        found = false
        for each lease in state.leases
            if lease.id = leaseId
                found = true
            else
                kept.Push(lease)
            end if
        end for
        if not found then return false
        ' Release is permitted during a blocked stop or integrity failure, so
        ' completed physical sends can acknowledge their borrowed references.
        state.leases = kept
        return true
    catch error
        return false
    end try
end function

function rokuVodCancelReservation(state as dynamic, reservationId as dynamic, workReleased as dynamic, sessionId as dynamic) as boolean
    try
        if not nvcShape(state) or state.closed or state.reservation = invalid then return false
        if not nvcString(reservationId) or not nvcSession(sessionId) or sessionId <> state.sessionId then return false
        if not nvcKeys(state.reservation, ["id", "entryNo", "workBytes", "maxPairBytes"]) or not nvcOpaqueId(state, reservationId) then return false
        if state.reservation.id <> reservationId then return false
        if type(workReleased, 3) <> "Boolean" and type(workReleased, 3) <> "roBoolean" then return false
        if not workReleased
            state.cleanupBlocked = true
            state.reason = "work_not_released"
            return false
        end if
        state.reservation = invalid
        if not state.faulted then state.cleanupBlocked = false
        return true
    catch error
        return false
    end try
end function

function rokuVodCacheClose(state as dynamic) as boolean
    try
        if not nvcShape(state) then return false
        if state.closed then return state.pairs.Count() = 0 and state.leases.Count() = 0 and state.reservation = invalid and state.index = invalid
        if state.leases.Count() > 0 or state.reservation <> invalid
            state.cleanupBlocked = true
            state.reason = "cleanup_busy"
            return false
        end if
        state.pairs = []
        state.index = invalid
        state.cacheBytes = 0&
        state.initialized = false
        state.sessionId = ""
        state.authority = ""
        state.rawDigest = ""
        state.recordsDigest = ""
        state.indexIdentity = ""
        state.indexBytes = 0&
        state.closed = true
        state.cleanupBlocked = false
        return true
    catch error
        return false
    end try
end function
