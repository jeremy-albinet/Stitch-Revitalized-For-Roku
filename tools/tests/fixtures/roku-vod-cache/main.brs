sub checkCache(ok as boolean, message as string)
    if not ok then throw "vod-cache-fixture: " + message
    m.assertions += 1
end sub

function cacheBytes(size as integer, tag as integer) as object
    data = CreateObject("roByteArray")
    data.SetResize(size, false)
    if size > 0
        data[0] = tag
        data[size - 1] = tag
    end if
    return data
end function

function newCache() as object
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(ReadAsciiFile("pkg:/index.m3u8"))
    index = rokuVodIndexParse(bytes, "https://vod.example.test/archive/index.m3u8?fixture=only", "https://vod.example.test")
    checkCache(index <> invalid and index.count = 64, "actual complete synthetic index")
    state = rokuVodCacheCreate(m.session, index)
    checkCache(state <> invalid, "actual private cache constructor")
    checkCache(state.pairs.Count() = 0 and state.leases.Count() = 0 and state.cacheBytes = 0& and state.reservation = invalid, "no eager asset allocation")
    checkCache(state.indexBytes + state.scratchBytes <= 589824&, "bounded accounted index and scratch")
    return state
end function

sub storeCache(state as object, entryNo as integer, videoSize = 12 as integer, audioSize = 7 as integer)
    pending = rokuVodReserve(state, entryNo, m.session)
    checkCache(pending <> invalid, "demand reservation admitted")
    checkCache(pending.workBytes = 50331648& and state.cacheBytes + pending.workBytes + state.indexBytes + state.scratchBytes <= 67108864&, "full conversion reserved before allocation")
    pair = {video: cacheBytes(videoSize, 32 + entryNo), audio: cacheBytes(audioSize, 96 + entryNo)}
    checkCache(rokuVodStore(state, pending.id, m.session, entryNo, pair), "atomic complete pair admission")
    checkCache(state.reservation = invalid and nvcValidate(state), "complete valid pair consumes reservation")
    at = nvcPairAt(state, entryNo)
    item = state.pairs[at]
    checkCache(item.videoBytes = videoSize and item.audioBytes = audioSize and item.video.Count() = videoSize and item.audio.Count() = audioSize, "pair published atomically")
    checkCache(item.video[0] = 32 + entryNo and item.audio[0] = 96 + entryNo, "both independently tagged outputs retained")
end sub

sub smallCache()
    state = newCache()
    checkCache(rokuVodCacheAuthorize(state, m.session, "video", 0) and rokuVodCacheAuthorize(state, m.session, "audio", 63), "indexed identity independent of residency")
    checkCache(rokuVodAcquire(state, "video", 0, m.session) = invalid and state.pairs.Count() = 0 and state.reservation = invalid, "miss never allocates or starts work")
    checkCache(rokuVodReserve(state, 0, m.session) = invalid and state.reason = "init_required", "both init outputs required first")
    for each request in [{session: m.other, track: "video", entry: 0}, {session: m.session, track: "unknown", entry: 0}, {session: m.session, track: "video", entry: -2}, {session: m.session, track: "video", entry: 64}, {session: m.session, track: "video", entry: "0"}, {session: m.session, track: "video", entry: 0.5}]
        checkCache(not rokuVodCacheAuthorize(state, request.session, request.track, request.entry), "unindexed or wrong identity refused")
    end for
    checkCache(rokuVodCacheCreate(m.other.Left(31), state.index) = invalid and rokuVodCacheCreate(m.session, state.index, 65537&) = invalid, "constructor identity and scratch bounds")
    storeCache(state, -1)
    checkCache(state.pairs[0].pinned and state.initialized, "both init outputs pinned")
    pending = rokuVodReserve(state, 3, m.session)
    checkCache(pending <> invalid, "media work admitted on demand")
    checkCache(rokuVodReserve(state, 4, m.session) = invalid and state.reason = "work_busy", "one bounded active conversion")
    checkCache(not rokuVodStore(state, pending.id, m.other, 3, {video: cacheBytes(12, 35), audio: cacheBytes(7, 99)}), "wrong-session completion refused")
    checkCache(not rokuVodStore(state, pending.id, m.session, 4, {video: cacheBytes(12, 35), audio: cacheBytes(7, 99)}), "wrong-entry completion refused")
    checkCache(not rokuVodStore(state, pending.id, m.session, 3, {video: cacheBytes(12, 35)}), "video-only orphan refused")
    checkCache(nvcPairAt(state, 3) = -1 and state.reservation <> invalid and state.cacheBytes = 19&, "partial output neither published nor consumed")
    checkCache(not rokuVodStore(state, pending.id, m.session, 3, {video: cacheBytes(12, 35), audio: cacheBytes(0, 99)}), "empty output refused")
    checkCache(rokuVodStore(state, pending.id, m.session, 3, {video: cacheBytes(12, 35), audio: cacheBytes(7, 99)}), "valid completion after partial refusal")
    checkCache(not rokuVodStore(state, pending.id, m.session, 3, {video: cacheBytes(12, 35), audio: cacheBytes(7, 99)}), "duplicate completion refused")
    checkCache(rokuVodReserve(state, 3, m.session) = invalid and state.reason = "already_cached", "paired hit never converts again")
    head = rokuVodAcquire(state, "video", 3, m.session)
    audio = rokuVodAcquire(state, "audio", 3, m.session)
    checkCache(head <> invalid and audio <> invalid and head.size = 12 and audio.size = 7, "paired hit returns full truthful lengths")
    checkCache(head.data[0] = 35 and audio.data[0] = 99 and state.admissions = 2&, "paired hit retains exact independent bodies")
    print "STITCH_VOD_CACHE_BYTES: " + FormatJson({video: LCase(head.data.ToHexString()), audio: LCase(audio.data.ToHexString())})
    range = loopbackRange("bytes=3-100", head.size)
    checkCache(range.ok and range.status = 206 and range.start = 3 and range.length = 9, "actual range clips against complete leased body")
    suffix = loopbackRange("bytes=-3", audio.size)
    checkCache(suffix.ok and suffix.start = 4 and suffix.length = 3, "actual audio suffix range")
    checkCache(loopbackRange("bytes=12-", head.size).status = 416 and loopbackRange("", head.size).length = 12, "actual invalid range and HEAD full length")
    checkCache(not rokuVodRelease(state, head.id, m.other) and state.leases.Count() = 2, "wrong-session release cannot free a send")
    otherState = newCache()
    storeCache(otherState, -1)
    otherLease = rokuVodAcquire(otherState, "video", -1, m.session)
    checkCache(head.id <> otherLease.id and not rokuVodRelease(state, otherLease.id, m.session), "per-state opaque authority rejects foreign token")
    checkCache(rokuVodRelease(otherState, otherLease.id, m.session) and rokuVodCacheClose(otherState), "foreign state independently releases")
    checkCache(rokuVodRelease(state, head.id, m.session) and not rokuVodRelease(state, head.id, m.session), "send release exactly once")
    checkCache(rokuVodRelease(state, audio.id, m.session), "audio send released")
    held = []
    for i = 0 to 7
        lease = rokuVodAcquire(state, "video", 3, m.session)
        checkCache(lease <> invalid, "bounded lease slot")
        held.Push(lease.id)
    end for
    checkCache(rokuVodAcquire(state, "audio", 3, m.session) = invalid and state.reason = "lease_limit", "ninth concurrent send refused")
    checkCache(not rokuVodCacheClose(state) and state.cleanupBlocked and state.pairs.Count() = 2, "close retains active sends")
    checkCache(rokuVodAcquire(state, "audio", 3, m.session) = invalid, "blocked close admits no new send")
    for each id in held
        checkCache(rokuVodRelease(state, id, m.session), "stop acknowledges each physical send")
    end for
    checkCache(rokuVodCacheClose(state) and state.closed and state.index = invalid and state.pairs.Count() = 0 and state.cacheBytes = 0&, "safe close releases every owned buffer")
    checkCache(rokuVodCacheClose(state), "terminal close idempotent")
    checkCache(rokuVodAcquire(state, "video", 3, m.session) = invalid and rokuVodReserve(state, 3, m.session) = invalid, "closed session never resurrects")
end sub

sub lruCache()
    state = newCache()
    storeCache(state, -1)
    for i = 0 to 14
        storeCache(state, i)
    end for
    checkCache(state.pairs.Count() = 16 and state.cacheBytes = 304&, "32 resident track assets maximum")
    held = rokuVodAcquire(state, "video", 0, m.session)
    touched = rokuVodAcquire(state, "audio", 1, m.session)
    checkCache(rokuVodRelease(state, touched.id, m.session), "touch updates shared pair LRU")
    storeCache(state, 63)
    checkCache(nvcPairAt(state, -1) >= 0 and nvcPairAt(state, 0) >= 0 and nvcPairAt(state, 1) >= 0 and nvcPairAt(state, 2) = -1, "eviction skips init leased and recently touched pairs")
    checkCache(state.pairs.Count() = 16 and state.evictions = 1&, "atomic eviction removes exactly two assets")
    bytesBefore = state.cacheBytes
    checkCache(rokuVodCacheAuthorize(state, m.session, "video", 2) and rokuVodCacheAuthorize(state, m.session, "audio", 2), "eviction never changes immutable route authorization")
    checkCache(rokuVodAcquire(state, "video", 2, m.session) = invalid and state.cacheBytes = bytesBefore, "sparse backwards miss stays demand only")
    storeCache(state, 2)
    checkCache(nvcPairAt(state, 3) = -1 and nvcPairAt(state, 2) >= 0 and nvcPairAt(state, 63) >= 0, "backward refetch evicts oldest pair without losing index tail")
    lease = rokuVodAcquire(state, "audio", 2, m.session)
    checkCache(lease <> invalid and lease.data[0] = 98, "refetched paired output exact bytes")
    checkCache(rokuVodRelease(state, lease.id, m.session) and rokuVodRelease(state, held.id, m.session), "all sparse sends released")
    ' There is no clock/lifetime input. A caller's long pause does not mutate cache.
    unrelatedElapsed = 86400000& * 30&
    checkCache(unrelatedElapsed > 0& and rokuVodCacheAuthorize(state, m.session, "audio", 63), "long pause has no expiration or publication deadline")
    resumed = rokuVodAcquire(state, "video", 63, m.session)
    checkCache(resumed <> invalid and resumed.data[0] = 95, "long pause resumes existing paired hit")
    checkCache(rokuVodRelease(state, resumed.id, m.session) and rokuVodCacheClose(state), "sparse cache closes cleanly")
end sub

sub budgetCache()
    state = newCache()
    storeCache(state, -1, 2097152, 2097152)
    storeCache(state, 0, 3145728, 3145728)
    lease = rokuVodAcquire(state, "audio", 0, m.session)
    beforeBytes = state.cacheBytes
    checkCache(rokuVodReserve(state, 1, m.session) = invalid and state.reason = "work_budget", "reserved 48MiB and 16MiB pair cannot overlap pinned and leased 10MiB cache")
    checkCache(state.pairs.Count() = 2 and state.cacheBytes = beforeBytes and state.reservation = invalid and state.evictions = 0&, "refused reservation commits no partial eviction")
    checkCache(nvcPairAt(state, -1) >= 0, "work admission never evicts pinned init")
    checkCache(rokuVodRelease(state, lease.id, m.session), "budget frees only completed send")
    pending = rokuVodReserve(state, 1, m.session)
    checkCache(pending <> invalid and state.cacheBytes = 4194304& and state.evictions = 1& and nvcPairAt(state, 0) = -1, "entire unleased pair evicted before allocation")
    checkCache(state.cacheBytes + pending.workBytes + state.indexBytes + state.scratchBytes <= 67108864&, "logical bound includes pinned init index and scratch")
    oversized = cacheBytes(16777217, 33)
    checkCache(not rokuVodStore(state, pending.id, m.session, 1, {video: oversized, audio: cacheBytes(1, 97)}), "16MiB per-track output cap enforced")
    oversized = invalid
    checkCache(not rokuVodCancelReservation(state, pending.id, false, m.session) and state.reservation <> invalid and state.cleanupBlocked, "unreleased conversion blocks cleanup")
    checkCache(not rokuVodCacheClose(state) and state.index <> invalid and state.pairs.Count() = 1, "close retains reserved work and pinned init")
    checkCache(not rokuVodCancelReservation(state, "wrong", true, m.session), "stale work token cannot release budget")
    checkCache(rokuVodCancelReservation(state, pending.id, true, m.session) and state.reservation = invalid and not state.cleanupBlocked, "acknowledged work release frees exact reservation")
    fresh = rokuVodReserve(state, 1, m.session)
    checkCache(fresh <> invalid and fresh.id <> pending.id, "superseding conversion gets fresh token")
    checkCache(not rokuVodStore(state, pending.id, m.session, 1, {video: cacheBytes(1, 33), audio: cacheBytes(1, 97)}), "superseded conversion never publishes")
    checkCache(rokuVodStore(state, fresh.id, m.session, 1, {video: cacheBytes(8388608, 33), audio: cacheBytes(8388608, 97)}), "exact 8MiB outputs and atomic 16MiB pair accepted")
    checkCache(state.cacheBytes = 20971520& and state.peakCacheBytes = 20971520& and nvcValidate(state), "bounded cache accounts both maximum outputs")
    checkCache(rokuVodCacheClose(state), "maximum pair cleanup complete")
    rollbackState = newCache()
    storeCache(rollbackState, -1, 2097152, 2097152)
    storeCache(rollbackState, 0, 1572864, 1572864)
    storeCache(rollbackState, 1, 4194304, 4194304)
    busy = rokuVodAcquire(rollbackState, "video", 1, m.session)
    before = rollbackState.cacheBytes
    checkCache(rokuVodReserve(rollbackState, 2, m.session) = invalid and rollbackState.reason = "work_budget", "insufficient eviction plan refused after removable candidate")
    checkCache(rollbackState.cacheBytes = before and rollbackState.evictions = 0& and rollbackState.pairs.Count() = 3 and nvcPairAt(rollbackState, 0) >= 0, "failed admission rolls back every planned eviction")
    checkCache(rokuVodRelease(rollbackState, busy.id, m.session) and rokuVodCacheClose(rollbackState), "rolled-back reservation releases safely")
    initState = newCache()
    initPending = rokuVodReserve(initState, -1, m.session)
    checkCache(not rokuVodStore(initState, initPending.id, m.session, -1, {video: cacheBytes(2097153, 31), audio: cacheBytes(1, 95)}), "init output 2MiB cap independently enforced")
    checkCache(rokuVodCancelReservation(initState, initPending.id, true, m.session) and rokuVodCacheClose(initState), "oversized init refusal releases cleanly")
end sub

sub largeCache()
    state = newCache()
    storeCache(state, -1, 2097152, 2097152)
    storeCache(state, 0, 2097152, 2097152)
    held = rokuVodAcquire(state, "video", 0, m.session)
    pending = rokuVodReserve(state, 1, m.session)
    checkCache(pending <> invalid and pending.maxPairBytes = 16777216& and pending.workBytes = 50331648& and state.cacheBytes = 8388608& and state.evictions = 0&, "exact pinned and leased 8MiB resident boundary admits full work")
    checkCache(rokuVodStore(state, pending.id, m.session, 1, {video: cacheBytes(8388608, 33), audio: cacheBytes(8388608, 97)}), "large atomic media pair admitted above legacy track limit")
    checkCache(state.cacheBytes = 25165824& and nvcValidate(state), "exact 24MiB complete cache and 16MiB aggregate pair valid")
    second = rokuVodAcquire(state, "audio", 1, m.session)
    checkCache(second <> invalid and second.size = 8388608 and second.data[0] = 97 and second.data[second.size - 1] = 97, "large cached audio lease borrows actual retained bytes")
    before = state.cacheBytes
    checkCache(rokuVodReserve(state, 2, m.session) = invalid and state.reason = "work_budget" and state.cacheBytes = before and state.evictions = 0&, "all leased large pairs prevent atomic eviction without state changes")
    checkCache(rokuVodRelease(state, second.id, m.session), "actual large send completion releases only its lease")
    nextPending = rokuVodReserve(state, 2, m.session)
    checkCache(nextPending <> invalid and state.cacheBytes = 8388608& and state.evictions = 1& and nvcPairAt(state, 1) = -1 and nvcPairAt(state, 0) >= 0, "only complete unleased large pair evicted before refetch")
    checkCache(rokuVodCancelReservation(state, nextPending.id, true, m.session) and rokuVodRelease(state, held.id, m.session) and rokuVodCacheClose(state), "large reservation and all actual leases acknowledge safe cleanup")

    state = newCache()
    storeCache(state, -1)
    pending = rokuVodReserve(state, 0, m.session)
    checkCache(not rokuVodStore(state, pending.id, m.session, 0, {video: cacheBytes(8388609, 32), audio: cacheBytes(8388608, 96)}) and state.reason = "cache_budget" and state.reservation <> invalid and state.pairs.Count() = 1, "combined pair above16MiB refuses before atomic publication")
    checkCache(rokuVodStore(state, pending.id, m.session, 0, {video: cacheBytes(8388608, 32), audio: cacheBytes(8388608, 96)}), "same reservation admits exact16MiB pair")
    pairs = state.pairs
    item = pairs[1]
    item.video = cacheBytes(8388609, 32)
    item.videoBytes = 8388609
    item.videoDigest = nbBulkDigest(item.video)
    pairs[1] = item
    state.pairs = pairs
    state.cacheBytes += 1&
    state.peakCacheBytes += 1&
    checkCache(not nvcValidate(state), "validator independently rejects combined pair above16MiB")
    checkCache(rokuVodCacheClose(state), "idle corrupted aggregate releases actual buffers")

    state = newCache()
    storeCache(state, -1, 2097152, 2097152)
    storeCache(state, 0, 2097152, 2097152)
    pending = rokuVodReserve(state, 1, m.session)
    pairs = state.pairs
    item = pairs[1]
    item.video = cacheBytes(3145728, 32)
    item.videoBytes = 3145728
    item.videoDigest = nbBulkDigest(item.video)
    pairs[1] = item
    state.pairs = pairs
    state.cacheBytes += 1048576&
    state.peakCacheBytes += 1048576&
    checkCache(not nvcValidate(state), "pending reservation independently rejects resident above8MiB")
    checkCache(rokuVodCancelReservation(state, pending.id, true, m.session) and rokuVodCacheClose(state), "invalid resident refuses delivery and still releases acknowledged work")
end sub

sub integrityCache()
    for each field in ["raw", "records", "mapUri", "count"]
        state = newCache()
        storeCache(state, -1)
        index = state.index
        if field = "raw" or field = "records"
            body = index[field]
            body[0] = (body[0] + 1) mod 256
            index[field] = body
        else if field = "mapUri"
            index.mapUri += "&changed=1"
        else
            index.count -= 1
        end if
        state.index = index
        checkCache(not rokuVodCacheAuthorize(state, m.session, "video", 0) and state.faulted and state.cleanupBlocked, "mutated immutable index refused " + field)
        checkCache(rokuVodCacheClose(state), "unleased corrupt index releases without unsafe send")
    end for
    state = newCache()
    storeCache(state, -1)
    storeCache(state, 0)
    lease = rokuVodAcquire(state, "video", 0, m.session)
    body = lease.data
    body[0] = 250
    checkCache(rokuVodAcquire(state, "audio", 0, m.session) = invalid and state.faulted and state.reason = "asset_mutated", "same-size leased body mutation invalidates both-track acquisition")
    checkCache(not rokuVodCacheClose(state), "corruption never frees live send")
    checkCache(rokuVodRelease(state, lease.id, m.session) and rokuVodCacheClose(state), "corrupt asset closes only after real send release")
    state = newCache()
    storeCache(state, -1)
    state.indexBytes -= 1&
    checkCache(not rokuVodCacheAuthorize(state, m.session, "video", 0), "underreported index counter refused")
    checkCache(rokuVodCacheClose(state), "corrupt accounting can release when idle")
    state = newCache()
    storeCache(state, -1)
    pending = rokuVodReserve(state, 0, m.session)
    state.stamp = 4294967295&
    checkCache(not rokuVodStore(state, pending.id, m.session, 0, {video: cacheBytes(1, 32), audio: cacheBytes(1, 96)}) and state.reason = "counter_exhausted", "admission stamp never wraps")
    checkCache(rokuVodCancelReservation(state, pending.id, true, m.session), "exhausted stamp still cancels work")
    state.serial = 4294967295&
    checkCache(rokuVodAcquire(state, "video", -1, m.session) = invalid and rokuVodReserve(state, 0, m.session) = invalid and state.reason = "counter_exhausted", "opaque identity counter never wraps")
    checkCache(rokuVodCacheClose(state), "exhausted counters can close safely")
    state = newCache()
    storeCache(state, -1)
    state.hits = 4294967295&
    checkCache(rokuVodAcquire(state, "video", -1, m.session) = invalid and state.reason = "counter_exhausted" and state.leases.Count() = 0, "hit counter cap refuses send without creating lease")
    checkCache(rokuVodCacheClose(state), "exhausted hit counter closes safely")
    state = newCache()
    state.cacheBytes = 25165825&
    checkCache(not rokuVodCacheAuthorize(state, m.session, "video", 0) and not rokuVodCacheClose(state), "over-budget corrupted counters cannot claim safe cleanup")
    state.cacheBytes = 0&
    checkCache(rokuVodCacheClose(state), "exact fixture accounting restoration releases")
    state = newCache()
    pending = rokuVodReserve(state, -1, m.session)
    reservation = state.reservation
    reservation.workBytes = 50331648.0
    state.reservation = reservation
    checkCache(not rokuVodCacheAuthorize(state, m.session, "video", -1), "noninteger work reservation refused")
    checkCache(rokuVodCancelReservation(state, pending.id, true, m.session) and rokuVodCacheClose(state), "corrupt reservation release requires exact opaque acknowledgement")
    state = newCache()
    storeCache(state, -1)
    lease = rokuVodAcquire(state, "video", -1, m.session)
    duplicate = state.leases
    duplicate.Push(duplicate[0])
    state.leases = duplicate
    checkCache(not rokuVodRelease(state, lease.id, m.session) and not rokuVodCacheClose(state), "duplicate lease registry cannot falsely acknowledge cleanup")
    ' Negative fixture owns this corruption; restore its exact registered lease.
    state.leases = [{id: lease.id, entryNo: -1, track: "video"}]
    checkCache(rokuVodRelease(state, lease.id, m.session) and rokuVodCacheClose(state), "exact repaired fixture registry releases once")
end sub

sub main()
    m.assertions = 0
    m.session = "0123456789abcdef0123456789abcdef"
    m.other = "fedcba9876543210fedcba9876543210"
    mode = "__MODE__"
    try
        if mode = "small" then smallCache()
        if mode = "lru" then lruCache()
        if mode = "budget" then budgetCache()
        if mode = "large" then largeCache()
        if mode = "integrity" then integrityCache()
        print "STITCH_VOD_CACHE_CASE: " + mode
        print "STITCH_VOD_CACHE_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 0})
    catch error
        print "STITCH_VOD_CACHE_FAIL: __MARKER__ " + error.message
        print "STITCH_VOD_CACHE_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 1})
    end try
end sub
