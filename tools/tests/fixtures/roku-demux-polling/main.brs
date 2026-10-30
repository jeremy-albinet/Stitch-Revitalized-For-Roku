' Actual production scheduling, Fetch dispatch/completion, Core and binary split.
' Only native URL/filesystem input and device approval are fixture boundaries.
sub checkPF(ok as boolean, message as string)
    if not ok then throw "polling-fixture: " + message
    m.assertions += 1
end sub

sub casePF(name as string)
    m.cases += 1
    print "STITCH_POLL_CASE: " + name
end sub

function bytesPF(record as object) as object
    bytes = CreateObject("roByteArray")
    bytes.FromHexString(record.hex)
    return bytes
end function

function newPF(opted = true as boolean, transitions = true as boolean, nowMs = 0& as dynamic) as object
    m.io = [false, true, 0]
    m.top = { stopRequested: false }
    options = { mode: "steady", sessionId: "0123456789abcdef0123456789abcdef" }
    if transitions then options.sourceTransitions = true
    state = nativeLiveCreate("https://cdn.example.invalid/live.m3u8", nowMs, 0, invalid, true, 16777216&, options)
    state.pollFromRequest = opted
    state.windowUs = 6000000&
    state.adClockEnabled = false
    return state
end function

function playlistPF(first = 10 as integer, count = 3 as integer, target = 6 as integer, alias = false as boolean, ended = false as boolean, duration = "2.002000" as string) as string
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:" + target.ToStr() + Chr(10)
    text += "#EXT-X-MEDIA-SEQUENCE:" + first.ToStr() + Chr(10)
    epoch = 0
    if first >= 13 then epoch = 1
    text += "#EXT-X-DISCONTINUITY-SEQUENCE:" + epoch.ToStr() + Chr(10)
    previous = ""
    for offset = 0 to count - 1
        sequence = first + offset
        name = "content"
        if sequence >= 13 then name = "ad"
        if alias then name = "content-alias"
        if name <> previous
            if previous <> "" then text += "#EXT-X-DISCONTINUITY" + Chr(10)
            text += "#EXT-X-MAP:URI=" + Chr(34) + name + ".mp4" + Chr(34) + Chr(10)
        end if
        text += "#EXTINF:" + duration + "," + Chr(10) + "segment-" + sequence.ToStr() + ".m4s" + Chr(10)
        previous = name
    end for
    text += "# PRIVATE_SNAPSHOT" + Chr(10)
    if ended then text += "#EXT-X-ENDLIST" + Chr(10)
    return text
end function

sub startPF(state as object, nowMs as dynamic, phase = "get" as string)
    intent = nlIntent(state, nowMs)
    checkPF(intent <> invalid and intent.kind = "playlist", "only due source playlist starts")
    nlStart(state, intent, phase, invalid, nowMs)
    m.starts += 1
    if state.pollFromRequest and phase = "get"
        checkPF(state.DoesExist("playlistRequestStartedAt"), "successful actual GET records request dispatch")
        checkPF(state.playlistRequestStartedAt = nowMs and state.playlistRequestPending, "successful actual GET records request dispatch")
    end if
end sub

sub completePF(state as object, text as string, nowMs as dynamic)
    m.fixtureBody = text
    m.io[0] = true
    event = { identity: state.op.identity, length: text.Len(), GetSourceIdentity: pfIdentity, GetInt: pfOne, GetResponseCode: pfStatus, GetResponseHeadersArray: pfHeaders }
    checkPF(nativeLiveHandleUrlEvent(state, event, nowMs), "actual Fetch consumes matching completed playlist")
    checkPF(state.phase <> "failed" and state.op = invalid and not state.ownInputFile and not m.io[0], "completed input cleanup precedes source acceptance")
end sub

sub validateLiveInitOutput(payload as object)
    checkPF(nativeDemuxBulkInspectInit(payload).Count() = 2, "actual binary initialization inspected before approval boundary")
end sub

function twitchAdClockBoolean(value as dynamic) as boolean
    return false
end function

sub drainPF(state as object, nowMs as dynamic)
    steps = 0
    while state.phase <> "ready" and state.phase <> "ended"
        checkPF(steps < 40, "bounded actual split drain")
        if state.phase = "init" or state.phase = "init-rotation"
            intent = nlIntent(state, nowMs)
            name = "content"
            if intent.url.InStr("/ad.mp4") >= 0 then name = "ad"
            checkPF(rokuDemuxFeedInput(state, "init", bytesPF(m.corpus.inits[name].input), nowMs), "actual approved init feed")
        else if state.phase = "segment" and nlMissing(state) <> invalid
            missing = nlMissing(state)
            record = m.corpus.media[CInt(missing.sequence - 10&)]
            nativeLiveFeed(state, "segment", bytesPF(record.input), nowMs)
            m.pairs += 1
        else
            nativeLiveAdvance(state, nowMs)
        end if
        steps += 1
    end while
end sub

sub closePF(state as object)
    held = []
    for each generation in state.generations
        if generation.advertised then held.Push(generation.id)
    end for
    for each id in held
        nativeLiveRetire(state, id)
    end for
    checkPF(nativeLiveClose(state), "actual helper close releases input assets and source")
    checkPF(not state.DoesExist("playlistSnapshot") and not state.DoesExist("playlistRequestStartedAt") and not state.DoesExist("playlistRequestPending") and not state.DoesExist("playlistLastTail"), "close releases bounded private snapshot tail and request timing")
end sub

sub wiringPF()
    casePF("default-and-trusted-server-wiring")
    for each opted in [false, true]
        state = newPF(false)
        m.top.lowLatency = opted
        configureLiveLatency(state)
        if opted
            checkPF(state.pollFromRequest and state.windowUs = 6000000&, "trusted lowLatency selects6s and request polling")
        else
            checkPF(not state.pollFromRequest and state.windowUs = 14000000&, "trusted default retains14s and original polling")
            startPF(state, 1000&)
            completePF(state, playlistPF(), 1400&)
            drainPF(state, 5000&)
            checkPF(state.nextPoll = 8000& and not state.DoesExist("playlistSnapshot") and not state.DoesExist("playlistRequestStartedAt"), "default retains publication relative half target without snapshot")
        end if
        closePF(state)
        state = newPF(false)
        m.top.lowLatency = opted
        configureLiveLatency(state)
        startPF(state, 1000&)
        completePF(state, playlistPF(10, 8, 6, true), 1400&)
        window = state.window
        if opted
            checkPF(window.segments.Count() = 3 and window.durationUs = 6006000& and window.segments[0].sequence = 15&, "lowLatency actually selects the newest three complete segments")
        else
            checkPF(window.segments.Count() = 7 and window.durationUs = 14014000& and window.segments[0].sequence = 11&, "default actually retains its fourteen second window")
        end if
        checkPF(window.segments[window.segments.Count() - 1].sequence = 17& and window.sourceOffsetUs = 0&, "both modes preserve the newest source tail with no added source delay")
        closePF(state)
    end for
end sub

sub floorsPF()
    casePF("changed-unchanged-source-target-floor")
    state = newPF()
    text = playlistPF()
    startPF(state, 1000&)
    completePF(state, text, 1400&)
    checkPF(state.nextPoll = 7000&, "first changed source waits full target from dispatch")
    checkPF(rokuDemuxFeedInput(state, "init", bytesPF(m.corpus.inits.content.input), 2000&), "initial approval feeds actual Core before pending split")
    nativeLiveAdvance(state, 3000&)
    checkPF(nlIntent(state, 4000&) = invalid, "pending binary conversion never starts another playlist")
    drainPF(state, 5000&)
    pub = nativeLivePublication(state)
    checkPF(state.nextPoll = 7000& and pub.targetDuration = 2, "publication preserves successful request source floor")
    checkPF(nlIntent(state, 6999&) = invalid, "first changed source suppresses early reload")
    startPF(state, 7000&)
    completePF(state, text, 7500&)
    nativeLiveAdvance(state, 7600&)
    checkPF(state.nextPoll = 10000& and state.latest = pub.generation and state.segmentPairCount = 3 and state.lastPublicationProgress = 5000&, "identical source uses half target without fabricated publication")
    startPF(state, 10000&)
    changed = playlistPF(10, 3, 4)
    completePF(state, changed, 10400&)
    nativeLiveAdvance(state, 10500&)
    ' A changed target header does not advance completed media after startup.
    checkPF(state.nextPoll = 12000&, "header-only target change uses half new declared target")
    startPF(state, 12000&)
    completePF(state, changed, 12400&)
    nativeLiveAdvance(state, 12500&)
    checkPF(state.nextPoll = 14000& and state.lastPublicationProgress = 5000&, "unchanged source uses half new source target")
    closePF(state)
    for each target in [1, 2, 8]
        state = newPF()
        startPF(state, 1000&)
        count = 3
        duration = "2.002000"
        if target = 1
            count = 8
            duration = "0.750000"
        end if
        completePF(state, playlistPF(10, count, target, true, false, duration), 1100&)
        checkPF(state.pollFromRequest and state.nextPoll = 1000& + target * 1000&, "supported source target keeps its exact request start floor")
        closePF(state)
    end for
    for each target in [9, 30]
        state = newPF()
        startPF(state, 1000&)
        completePF(state, playlistPF(10, 3, target), 1400&)
        checkPF(not state.pollFromRequest and not state.DoesExist("playlistSnapshot") and not state.DoesExist("playlistRequestStartedAt") and not state.DoesExist("playlistLastTail"), "long source target disables optimization and releases snapshot and tail")
        drainPF(state, 5000&)
        checkPF(state.nextPoll = 5000& + target * 500& and state.deadline = 45000&, "long source target retains original schedule and health bounds")
        if target = 30
            reason = ""
            try
                nlTime(state, 20000&)
            catch e
                reason = e.message
            end try
            checkPF(reason = "native-live: upstream progress deadline", "long target cannot extend original upstream deadline")
        end if
        closePF(state)
    end for
end sub

sub tailCadencePF()
    casePF("advancing-media-tail-header-unchanged-stale-and-recovery")
    state = newPF()
    startPF(state, 0&)
    completePF(state, playlistPF(), 100&)
    drainPF(state, 500&)
    checkPF(state.playlistLastTail = 12&, "startup records completed source tail before steady cadence")
    forward = playlistPF(10, 4)
    startPF(state, 6000&)
    identity = state.op.identity
    transfers = state.transfers
    status = nativeLiveTick(state, invalid, 6050&)
    checkPF(status.transferActive and state.op.identity = identity and state.transfers = transfers, "pending playlist has exactly one Fetch transfer")
    completePF(state, forward, 6100&)
    checkPF(state.nextPoll = 8002& and state.playlistLastTail = 13&, "advancing short tail schedules its duration from dispatch")
    drainPF(state, 6500&)
    current = nativeLivePublication(state)
    checkPF(current.targetDuration = 2 and current.durationUs = 6006000& and current.sourceOffsetUs = 0& and state.nextPoll = 8002&, "short cadence preserves exact full-segment publication and source target distinction")
    checkPF(nlIntent(state, 8001&) = invalid, "short tail cadence suppresses early source reload")
    header = forward + "#EXT-X-TWITCH-ELAPSED-SECS:123.5" + Chr(10)
    startPF(state, 8002&)
    completePF(state, header, 8102&)
    nativeLiveAdvance(state, 8202&)
    checkPF(state.nextPoll = 11002& and state.playlistLastTail = 13&, "header-only change uses half declared target without media advance")
    checkPF(state.lastUpstreamProgress = 8102& and state.lastPublicationProgress = 6500& and state.segmentPairCount = 4 and FormatJson(nativeLivePublication(state)) = FormatJson(current), "header-only response cannot fabricate publication progress")
    startPF(state, 11002&)
    completePF(state, header, 11102&)
    nativeLiveAdvance(state, 11202&)
    checkPF(state.nextPoll = 14002&, "unchanged short profile uses half declared source target")
    beforeWindow = FormatJson(state.window)
    beforeBytes = state.cacheBytes
    startPF(state, 14002&)
    completePF(state, playlistPF(), 14102&)
    checkPF(state.phase = "ready" and state.nextPoll = 17002& and state.playlistLastTail = 13&, "stale response keeps maximum tail and half declared target")
    checkPF(FormatJson(state.window) = beforeWindow and FormatJson(nativeLivePublication(state)) = FormatJson(current) and state.cacheBytes = beforeBytes and state.segmentPairCount = 4 and state.lastUpstreamProgress = 11102& and state.lastPublicationProgress = 6500&, "stale response preserves publication cache and both progress deadlines")
    startPF(state, 17002&)
    completePF(state, forward, 17102&)
    nativeLiveAdvance(state, 17202&)
    checkPF(state.nextPoll = 20002& and state.playlistLastTail = 13& and state.latest = current.generation, "return to maximum tail after stale response is not new media")
    startPF(state, 20002&)
    completePF(state, playlistPF(10, 5), 20102&)
    checkPF(state.nextPoll = 22004& and state.playlistLastTail = 14&, "forward recovery resumes short cadence only past maximum tail")
    drainPF(state, 20502&)
    checkPF(state.latest = current.generation + 1& and state.segmentPairCount = 5 and state.initPairCount = 2 and state.publishedLast = 14& and state.nextPoll = 22004&, "forward recovery publishes exactly one complete media pair")
    closePF(state)
end sub

sub cadenceBoundsPF()
    casePF("short-fragment-profile-duration-clamps-and-legacy-manual-calls")
    for each profile in ["six", "eight", "long-window", "missing-window", "delay", "no-transitions", "default"]
        state = newPF(profile <> "default", profile <> "no-transitions")
        startPF(state, 0&)
        completePF(state, playlistPF(), 100&)
        drainPF(state, 500&)
        if profile = "eight" then state.windowUs = 8000000&
        if profile = "long-window" then state.windowUs = 14000000&
        if profile = "missing-window" then state.Delete("windowUs")
        if profile = "delay" then state.delayUs = 2002000&
        stamp = state.nextPoll
        startPF(state, stamp)
        count = 4
        if profile = "delay" then count = 5
        completePF(state, playlistPF(10, count, 6, profile = "no-transitions"), stamp + 100&)
        if profile = "six" or profile = "eight"
            checkPF(state.nextPoll = stamp + 2002&, "explicit six to eight second source-transition profile uses short cadence")
        else if profile = "default"
            drainPF(state, stamp + 500&)
            checkPF(state.nextPoll = stamp + 3500& and not state.DoesExist("playlistLastTail"), "default polling keeps publication-relative half target without tail state")
        else
            checkPF(state.nextPoll = stamp + 6000&, "long missing delayed or nontransition profile keeps changed full target")
        end if
        closePF(state)
    end for
    for each sample in [{duration: "0.000001", target: 6, interval: 1000&}, {duration: "2.002001", target: 6, interval: 2003&}, {duration: "2.499999", target: 2, interval: 2000&}]
        state = newPF()
        startPF(state, 0&)
        completePF(state, playlistPF(10, 3, sample.target), 100&)
        drainPF(state, 500&)
        text = playlistPF(10, 4, sample.target)
        last = "#EXTINF:2.002000," + Chr(10) + "segment-13.m4s"
        text = text.Replace(last, "#EXTINF:" + sample.duration + "," + Chr(10) + "segment-13.m4s")
        stamp = state.nextPoll
        startPF(state, stamp)
        completePF(state, text, stamp + 100&)
        checkPF(state.nextPoll = stamp + sample.interval and state.playlistLastTail = 13&, "advancing tail uses integer ceiling with one second floor and declared target cap")
        closePF(state)
    end for
    ' Omitted scalar arguments retain the existing manual snapshot contract.
    state = newPF()
    startPF(state, 0&)
    completePF(state, playlistPF(), 100&)
    drainPF(state, 500&)
    startPF(state, 6000&)
    checkPF(nlCancelInput(state), "manual polling fixture cancels native input before direct acceptance")
    nlAcceptPlaylistPoll(state, "manual", 6, 6100&)
    checkPF(state.nextPoll = 12000& and state.playlistLastTail = 12&, "legacy manual changed call retains full target and previous tail")
    startPF(state, 12000&)
    checkPF(nlCancelInput(state), "manual polling fixture cancels repeated native input")
    nlAcceptPlaylistPoll(state, "manual", 6, 12100&)
    checkPF(state.nextPoll = 15000& and state.playlistLastTail = 12&, "legacy manual unchanged call retains half target")
    closePF(state)
    state = newPF()
    startPF(state, 0&)
    completePF(state, playlistPF(), 100&)
    drainPF(state, 500&)
    startPF(state, 6000&)
    checkPF(nlCancelInput(state), "long fragment manual fixture cancels native input")
    nlAcceptPlaylistPoll(state, "longer fragment", 6, 6100&, 13&, 2500000&)
    checkPF(state.nextPoll = 12000&, "longer fragment scalar retains changed full target")
    closePF(state)
end sub

sub retryPF()
    casePF("successful-dispatch-failure-and-timeout-retry")
    state = newPF()
    m.io[1] = false
    refused = false
    try
        startPF(state, 0&)
    catch e
        refused = e.message = "native-live: GET could not start"
    end try
    checkPF(refused and not state.DoesExist("playlistRequestStartedAt"), "failed native GET cannot establish dispatch floor")
    closePF(state)
    state = newPF()
    startPF(state, 0&)
    status = nativeLiveTick(state, invalid, 6000&)
    checkPF(status.phase = "playlist" and state.op = invalid and state.timedOutUrl <> "", "first timeout retains existing single retry policy")
    status = nativeLiveTick(state, invalid, 6100&)
    m.starts += 1
    checkPF(state.op <> invalid and state.playlistRequestStartedAt = 6100& and state.transfers = 2, "actual retry replaces successful GET dispatch time")
    completePF(state, playlistPF(), 6200&)
    drainPF(state, 6500&)
    checkPF(state.nextPoll = 12100&, "retry floor uses fresh start rather than expired first request")
    closePF(state)
    state = newPF(false)
    startPF(state, 1000&, "head")
    checkPF(not state.DoesExist("playlistRequestStartedAt"), "default HEAD never enables source polling")
    checkPF(nlCancelInput(state), "default HEAD cancellation remains unchanged")
    startPF(state, 1100&)
    checkPF(not state.DoesExist("playlistRequestStartedAt"), "default following GET remains disabled")
    closePF(state)
end sub

sub epochsPF()
    casePF("mixed-startup-and-epoch-conversion")
    state = newPF()
    mixed = playlistPF(12, 3)
    startPF(state, 1000&)
    completePF(state, mixed, 1400&)
    checkPF(state.phase = "playlist" and state.window = invalid and state.assets.Count() = 0 and not state.started and state.nextPoll = 7000&, "mixed startup keeps full source floor without fake readiness")
    startPF(state, 7000&)
    completePF(state, mixed, 7400&)
    checkPF(state.nextPoll = 10000& and state.deadline = 45000&, "unchanged mixed startup uses half target without extending startup")
    closePF(state)
    state = newPF()
    startPF(state, 1000&)
    completePF(state, playlistPF(), 1400&)
    drainPF(state, 5000&)
    old = nativeLivePublication(state)
    startPF(state, 7000&)
    completePF(state, playlistPF(10, 4), 7400&)
    ' Steady short fragments schedule from the advancing tail even across an epoch.
    checkPF(state.phase = "init-rotation" and state.nextPoll = 9002& and FormatJson(nativeLivePublication(state)) = FormatJson(old), "epoch early return retains short tail cadence and old publication")
    oldIds = state.initIds
    checkPF(rokuDemuxFeedInput(state, "init", bytesPF(m.corpus.inits.ad.input), 8000&), "genuine ad initialization approval feeds actual Core")
    transfers = state.transfers
    status = nativeLiveTick(state, invalid, 10000&)
    checkPF(status.phase = "init-audio" and state.initIds[0] = oldIds[0] and state.nextPoll = 9002& and state.op = invalid and state.transfers = transfers, "expired short cadence cannot overlap pending track conversion")
    nativeLiveAdvance(state, 11000&)
    drainPF(state, 14000&)
    checkPF(state.nextPoll = 9002& and state.segmentPairCount = 4 and state.initPairCount = 2, "long conversion consumes short cadence without resetting it")
    intent = nlIntent(state, 14000&)
    checkPF(intent <> invalid and intent.kind = "playlist", "expired source floor permits one post-conversion reload")
    closePF(state)
end sub

sub aliasesPF()
    casePF("map-alias-terminal-and-private-snapshot-release")
    state = newPF(true, false)
    startPF(state, 1000&)
    completePF(state, playlistPF(), 1400&)
    drainPF(state, 5000&)
    startPF(state, 7000&)
    completePF(state, playlistPF(10, 3, 6, true), 7400&)
    checkPF(state.phase = "init-rotation" and state.nextPoll = 13000&, "map alias acceptance preserves full request floor")
    drainPF(state, 8000&)
    checkPF(state.initAliasCount = 1 and state.initPairCount = 1 and state.nextPoll = 13000&, "byte alias commit cannot reset source floor")
    startPF(state, 13000&)
    completePF(state, playlistPF(10, 3, 6, true, true), 13400&)
    nativeLiveAdvance(state, 14000&)
    checkPF(state.phase = "ended" and nlIntent(state, 20000&) = invalid, "terminal source never reloads after deadline")
    closePF(state)
    state = newPF()
    startPF(state, 0&)
    completePF(state, playlistPF(), 100&)
    nlAbort(state, "native-live: fixture-stop")
    checkPF(not state.DoesExist("playlistSnapshot") and not state.DoesExist("playlistRequestStartedAt") and not state.DoesExist("playlistLastTail"), "failure teardown releases bounded private snapshot and tail")
    closePF(state)
end sub

sub boundsPF()
    casePF("unchanged-publication-deadline-and-clock-quota-bounds")
    state = newPF()
    startPF(state, 0&)
    text = playlistPF()
    completePF(state, text, 100&)
    drainPF(state, 500&)
    for pass = 0 to 8
        stamp = 6000& + pass * 3000&
        startPF(state, stamp)
        completePF(state, text, stamp + 100&)
        nativeLiveAdvance(state, stamp + 200&)
    end for
    reason = ""
    try
        nlTime(state, 30500&)
    catch e
        reason = e.message
    end try
    checkPF(reason = "native-live: publication progress deadline" and state.lastPublicationProgress = 500&, "frequent identical snapshots cannot hide publication stall")
    closePF(state)
    state = newPF()
    startPF(state, 0&)
    completePF(state, playlistPF(), 100&)
    drainPF(state, 500&)
    startPF(state, 6000&)
    completePF(state, playlistPF(10, 4), 6100&)
    drainPF(state, 6500&)
    for each stamp in [8002&, 11002&, 14002&, 17002&, 20002&]
        startPF(state, stamp)
        completePF(state, playlistPF(), stamp + 100&)
        checkPF(state.nextPoll = stamp + 3000& and state.playlistLastTail = 13& and state.lastUpstreamProgress = 6500& and state.lastPublicationProgress = 6500&, "repeated stale tails retain half target and original health clocks")
    end for
    checkPF(nlIntent(state, 21499&) = invalid, "stale short cadence remains bounded before upstream deadline")
    status = nativeLiveTick(state, invalid, 21500&)
    checkPF(status.phase = "failed" and state.error = "native-live: upstream progress deadline" and not state.DoesExist("playlistLastTail"), "stale short cadence fails at original health deadline and releases tail")
    closePF(state)
    base = 2147483640&
    state = newPF(true, true, base)
    startPF(state, base)
    completePF(state, playlistPF(), base + 100&)
    checkPF(state.nextPoll = base + 6000& and Type(state.nextPoll, 3) = "LongInteger", "request due time retains long clock across Integer boundary")
    drainPF(state, base + 500&)
    startPF(state, base + 6000&)
    completePF(state, playlistPF(10, 4), base + 6100&)
    checkPF(state.nextPoll = base + 8002& and Type(state.nextPoll, 3) = "LongInteger", "short tail cadence retains LongInteger dispatch arithmetic")
    state.quotaTransfers = 256
    reason = ""
    try
        nlUseWork(state, "transfer", base + 6200&)
    catch e
        reason = e.message
    end try
    checkPF(reason = "native-live: steady work interval bound" and state.quotaTransfers = 256, "request scheduling keeps exact existing transfer quota")
    closePF(state)
    base = 4294967225000&
    state = newPF(true, true, base)
    startPF(state, base)
    completePF(state, playlistPF(), base + 50&)
    checkPF(state.nextPoll = base + 6000&, "terminal clock due time remains long without wrapping")
    drainPF(state, base + 500&)
    startPF(state, base + 6000&)
    completePF(state, playlistPF(10, 4), base + 6100&)
    checkPF(state.nextPoll = base + 8002& and Type(state.nextPoll, 3) = "LongInteger", "short cadence stays exact near terminal long clock cap")
    reason = ""
    try
        nlTime(state, 4294967235001&)
    catch e
        reason = e.message
    end try
    checkPF(reason = "native-live: integer bound", "source scheduling cannot enlarge terminal clock bound")
    closePF(state)
    state = newPF()
    reason = ""
    try
        nlAcceptPlaylistPoll(state, playlistPF(), 6, 0&)
    catch e
        reason = e.message
    end try
    checkPF(reason = "native-live: playlist polling start missing", "accepted snapshot requires actual successful request start")
    state.phase = "playlist"
    state.op = {kind: "playlist", phase: "get", deadline: 6000&}
    nativeLivePlaylistStarted(state, 0&)
    reason = ""
    try
        nlAcceptPlaylistPoll(state, String(262145, "x"), 6, 1&)
    catch e
        reason = e.message
    end try
    checkPF(reason = "native-live: playlist polling snapshot invalid" and not state.DoesExist("playlistSnapshot"), "retained source text cannot exceed262144 bytes")
    state.op = invalid
    closePF(state)
    state = newPF()
    state.op = {kind: "playlist", phase: "head", deadline: 6000&}
    reason = ""
    try
        nativeLivePlaylistStarted(state, 0&)
    catch e
        reason = e.message
    end try
    checkPF(reason = "native-live: playlist polling operation invalid" and not state.DoesExist("playlistRequestStartedAt"), "optimized dispatch cannot use a HEAD start")
    state.op = invalid
    closePF(state)
end sub

function pfCreateObject(name as string) as object
    if name = "roFileSystem" then return {io: m.io, body: m.fixtureBody, Exists: pfExists, Stat: pfStat, Delete: pfDelete}
    if name = "roUrlTransfer"
        m.io[2] += 1
        return {io: m.io, identity: m.io[2], SetMessagePort: pfSetPort, SetCertificatesFile: pfStringOk, EnablePeerVerification: pfBoolOk, EnableHostVerification: pfBoolOk, EnableEncodings: pfBoolOk, EnableResume: pfBoolOk, SetMinimumTransferRate: pfRate, SetHeaders: pfHeadersOk, SetUrl: pfSetUrl, GetIdentity: pfIdentity, AsyncGetToFile: pfGet, AsyncHead: pfHead, AsyncCancel: pfCancel}
    end if
    return CreateObject(name)
end function

function pfExists(path as string) as boolean
    return m.io[0]
end function

function pfStat(path as string) as object
    return {type: "file", size: m.body.Len()}
end function

function pfDelete(path as string) as boolean
    m.io[0] = false
    return true
end function

sub pfSetPort(port as dynamic)
end sub

sub pfSetUrl(url as string)
end sub

function pfStringOk(value as string) as boolean
    return true
end function

function pfBoolOk(value as boolean) as boolean
    return true
end function

function pfRate(rate as integer, seconds as integer) as boolean
    return rate = 1 and seconds = 2
end function

function pfHeadersOk(headers as object) as boolean
    return headers["Accept-Encoding"] = "identity"
end function

function pfIdentity() as dynamic
    return m.identity
end function

function pfGet(path as string) as boolean
    return m.io[1]
end function

function pfHead() as boolean
    return true
end function

function pfCancel() as boolean
    return true
end function

function pfEventType(event as object) as string
    return "roUrlEvent"
end function

function pfReadInput(path as string) as string
    return m.fixtureBody
end function

function pfOne() as integer
    return 1
end function

function pfStatus() as integer
    return 200
end function

function pfHeaders() as object
    return [{"Content-Length": m.length.ToStr()}]
end function

sub main()
    m.assertions = 0
    m.cases = 0
    m.starts = 0
    m.pairs = 0
    m.config = {sourceDelaySeconds: 0}
    try
        m.corpus = ParseJSON(ReadAsciiFile("pkg:/corpus.json"))
        wiringPF()
        floorsPF()
        tailCadencePF()
        cadenceBoundsPF()
        retryPF()
        epochsPF()
        aliasesPF()
        boundsPF()
        print "STITCH_POLL_PASS: __MARKER__ "; FormatJson({cases: m.cases, assertions: m.assertions, starts: m.starts, pairs: m.pairs})
    catch e
        print "STITCH_POLL_FAIL: "; e.message
    end try
end sub
