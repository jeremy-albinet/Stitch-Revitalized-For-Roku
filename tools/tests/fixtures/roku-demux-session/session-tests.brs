sub runTests(control as string)
    m.assertions = 0
    m.failures = 0
    m.control = control
    testSourceTransitionClassification()
    ' Actual result summaries preserve useful failure codes, never private input.
    manager = newManager()
    diagnostic = manager.callFunc("fixtureDiagnostic", { reason: "live_helper_failed", elapsedMs: 720000&, requests: 320&, failureCategory: 1, cleanupOk: true, sourceUrl: "https://private.invalid/DIAGNOSTIC_SECRET_TOKEN", helperFailureReason: "native-live: selected map initialization changed" })
    check(diagnostic.reason = "live_helper_failed" and diagnostic.helperReason = "selected_map_initialization_changed", "fixed failure codes survive diagnostic filtering")
    check(diagnostic.elapsedMs = 720000& and diagnostic.requests = 320& and diagnostic.failureCategory = 1 and diagnostic.cleanupOk, "typed diagnostic counters and cleanup acknowledgment survive")
    check(not diagnostic.DoesExist("sourceUrl") and not diagnostic.DoesExist("helperFailureReason") and not diagnostic.DoesExist("sessionId"), "diagnostic has no signed input or raw error fields")
    diagnostic = manager.callFunc("fixtureDiagnostic", { reason: "unexpected_sensitive_error", helperFailureReason: "native-live: unexpected_sensitive_error", elapsedMs: "720000", requests: -1, completedRequests: 4294967296&, clientErrors: 2.5, cleanupOk: "true", listenerClosed: 1 })
    check(diagnostic.reason = "unknown" and diagnostic.Count() = 1, "unknown text and coerced or unbounded diagnostic values omitted")
    diagnostic = manager.callFunc("fixtureDiagnostic", { reason: "accept_failed|actual_init_required" })
    check(diagnostic.reason = "unknown", "diagnostic reason must be a single exact code")
    for each message in ["GET status or range unsupported", "cache byte budget exceeded", "upstream operation deadline", "continuity window crosses map or discontinuity", "selected window crosses map or discontinuity"]
        diagnostic = manager.callFunc("fixtureDiagnostic", { helperFailureReason: "native-live: " + message })
        check(diagnostic.helperReason = message.Replace(" ", "_"), "fixed upstream/cache failure remains distinguishable")
    end for
    for each helper in ["native-live: selected window crosses map or discontinuity extra", "native-live: selected window crosses map or discontinuity https://private.invalid/DIAGNOSTIC_SECRET_TOKEN", "native-live: unexpected_sensitive_error"]
        diagnostic = manager.callFunc("fixtureDiagnostic", { helperFailureReason: helper })
        check(not diagnostic.DoesExist("helperReason") and not diagnostic.DoesExist("helperFailureReason"), "selected-window diagnostics reject nonexact text without raw data")
    end for
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    result = cleanupFor(id)
    result.reason = "live_helper_failed"
    result.sourceUrl = "https://private.invalid/DIAGNOSTIC_SECRET_TOKEN"
    result.helperFailureReason = "native-live: unexpected_sensitive_error"
    worker.result = result
    check(worker.stopRequested and manager.busy, "actual failure result logs while retaining cooperative owner")
    worker.state = "stop"
    check(not manager.busy, "diagnostic logging does not change acknowledged cleanup")
    manager.callFunc("onDestroy")
    ' Invalid descriptors cannot start a Task or opt an otherwise idle manager in.
    manager = newManager()
    check(manager.callFunc("startSession", { fixture: true }) = "", "arbitrary AA rejected before worker creation")
    check(not manager.callFunc("canLeaveBlockedSession", ""), "idle manager cannot authorize blocked UI exit")
    check(not manager.busy and manager.callFunc("fixtureRead").worker = invalid, "invalid descriptor retains idle ownership")
    manager.callFunc("onDestroy")
    check(manager.callFunc("startSession", sessionDescriptor()) = "", "destroyed idle manager cannot create worker")
    check(manager.findNode("cleanupTimer").control = "stop", "idle disposal stops cleanup timer")

    manager = newManager()
    hd = sessionDescriptor("1080")
    hints = hd["metadata"]
    hints["width"] = 1920
    hints["height"] = 1080
    hints["bandwidth"] = 8042999
    hd["metadata"] = hints
    hd["qualityId"] = "1080p60"
    id = manager.callFunc("startSession", hd)
    worker = manager.callFunc("fixtureRead").worker
    check(worker.experimentalMode and worker.cacheBudgetBytes = 33554432 and worker.listenPort = 0, "validated offered1080 uses explicit experimental32MiB policy")
    check((type(worker.enableAdMetadata) = "Boolean" or type(worker.enableAdMetadata) = "roBoolean") and worker.enableAdMetadata, "consented LIVE v1 HD worker has strict Boolean cue forwarding")
    check(worker.inputDescriptor["qualityId"] = "1080p60" and worker.inputDescriptor["metadata"]["height"] = 1080, "1080 identity remains truthful without mutating descriptor")
    finishManager(manager)

    manager = newManager()
    first = manager.callFunc("startSession", sessionDescriptor())
    state = manager.callFunc("fixtureRead")
    worker = state.worker
    check(first.Len() = 32 and state.currentId = first, "fresh request identity")
    check(manager.busy and worker.state = "run", "one worker actually entered run boundary")
    check(worker.inputDescriptor["qualityId"] = "720p60" and worker.sessionId = first, "typed input and identity")
    check(sessionIdentifier(first) and worker.functionName = "runServer", "lowercase hex session namespace and exact worker entry")
    check(worker.experimentalMode and worker.cacheBudgetBytes = 25165824 and worker.listenPort = 0 and not worker.stopRequested, "explicit experimental opt-in and bounded worker options")
    check((type(worker.enableAdMetadata) = "Boolean" or type(worker.enableAdMetadata) = "roBoolean") and worker.enableAdMetadata, "actual running LIVE v1 worker enables observational cue metadata")
    worker.ready = readyFor("00000000000000000000000000000000")
    check(manager.event.status = "starting", "stale ready ignored")
    worker.ready = readyFor(first)
    check(manager.event.status = "ready" and manager.event.id = first, "matching ready emitted")
    check(manager.event.url = "http://127.0.0.1:49371/master.m3u8", "fixed loopback playable URL")
    worker.ready = { sessionId: first, boundPort: 49371, boundAddressText: "10.0.0.1", decoderApproved: true, metadata: {} }
    check(manager.event.status = "ready" and not worker.stopRequested, "duplicate ready suppressed")
    video = CreateObject("roSGNode", "SessionVideoBoundary")
    video.state = "playing"
    check(manager.callFunc("attachVideo", first, video), "real node video stop observer attached")
    otherVideo = CreateObject("roSGNode", "SessionVideoBoundary")
    check(not manager.callFunc("attachVideo", first, otherVideo), "second video reference refused")
    second = manager.callFunc("startSession", sessionDescriptor("second"))
    check(worker.stopRequested and video.control = "stop", "replacement cooperatively stops worker and video")
    third = manager.callFunc("startSession", sessionDescriptor("third"))
    state = manager.callFunc("fixtureRead")
    check(state.pending.id = third and third <> second, "only latest pending replacement retained")
    manager.callFunc("stopSession", first)
    check(manager.callFunc("fixtureRead").pending.id = third, "old current stop cannot cancel a newer queued identity")
    manager.callFunc("stopSession", second)
    check(manager.callFunc("fixtureRead").pending.id = third, "superseded caller cannot cancel latest pending identity")
    worker.result = cleanupFor(second)
    check(manager.callFunc("fixtureRead").workerResult = invalid, "stale cleanup result ignored")
    check(state.worker.isSameNode(worker) and worker.control = "run", "no forced Task stop or second owner before acknowledgment")
    if m.control = "early"
        check(not state.worker.isSameNode(worker), "deliberate early-release control")
        finishTests()
        return
    end if
    worker.result = cleanupFor(first)
    check(manager.busy and manager.callFunc("fixtureRead").currentId = first, "result alone cannot release running Task")
    worker.state = "stop"
    check(manager.busy and manager.callFunc("fixtureRead").currentId = first, "Task stop alone cannot release playing Video")
    video.state = "stopped"
    state = manager.callFunc("fixtureRead")
    check(manager.busy and state.currentId = third, "replacement starts only after all three acknowledgments")
    check(not state.worker.isSameNode(worker) and state.worker.inputDescriptor["sourceUrl"].InStr("/third.m3u8") > 0, "latest pending input used by one fresh worker")
    check((type(state.worker.enableAdMetadata) = "Boolean" or type(state.worker.enableAdMetadata) = "roBoolean") and state.worker.enableAdMetadata, "latest consented LIVE v1 replacement preserves strict cue forwarding")
    check(state.video = invalid and worker.control = "stop", "old observers and reference released through factory after stop")
    worker.ready = readyFor(first)
    check(manager.event.id = third and manager.event.status = "starting", "released worker cannot inject stale ready")
    finishManager(manager)

    ' The polling timer itself must be able to complete the old owner and start
    ' the queued one without dereferencing its cleared clock or cancelling it.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    queuedDescriptor = sessionDescriptor("queued-timer")
    queued = manager.callFunc("startSession", queuedDescriptor)
    queuedDescriptor["sourceUrl"] = "https://use14.playlist.ttvnw.net/canned/caller-mutated.m3u8"
    worker.unobserveField("result")
    worker.unobserveField("state")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    manager.callFunc("fixtureArmResult", cleanupFor(id))
    check(manager.busy and manager.callFunc("fixtureRead").currentId = id, "unobserved acknowledged owner awaits actual timer completer")
    manager.callFunc("fixtureTick")
    state = manager.callFunc("fixtureRead")
    check(state.currentId = queued and state.worker.state = "run" and not state.worker.stopRequested, "timer completer leaves replacement running")
    check(not state.stopping and state.cleanupClock = invalid and state.pending = invalid, "replacement has no inherited cleanup timer state")
    check(state.worker.inputDescriptor["sourceUrl"].InStr("/queued-timer.m3u8") > 0, "queued descriptor is an immutable primitive snapshot")
    check(state.worker.experimentalMode and state.worker.cacheBudgetBytes = 25165824 and state.worker.listenPort = 0, "queued replacement keeps bounded worker options")
    manager.callFunc("stopSession", id)
    check(not state.worker.stopRequested, "old stopped identity cannot stop running replacement")
    finishManager(manager)
    if m.control = "timer"
        finishTests()
        return
    end if

    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    bad = readyFor(id)
    bad.actualInitValidated = false
    worker.ready = bad
    check(worker.stopRequested and manager.event.status <> "ready", "master-only decoder approval cannot satisfy actual init gate")
    finishManager(manager)

    ' Stop-before-ready plus actual state-before-result ordering.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    manager.callFunc("stopSession", id)
    worker.ready = readyFor(id)
    check(manager.event.status = "stopping", "ready suppressed during stop-before-ready")
    worker.state = "stop"
    check(manager.busy, "state before result waits for cleanup acknowledgment")
    worker.result = cleanupFor(id)
    check(not manager.busy and manager.event.status = "stopped", "state-before-result completes after matching cleanup")
    worker.ready = readyFor(id)
    worker.result = cleanupFor(id)
    worker.state = "run"
    check(not manager.busy and manager.callFunc("fixtureRead").worker = invalid and manager.event.status = "stopped", "released worker ready result and state observers are removed")
    manager.callFunc("onDestroy")

    ' Old request cannot stop the newer active owner; cancel a queued choice.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    manager.callFunc("stopSession", first)
    check(not worker.stopRequested, "stale stop identity ignored")
    check(not manager.callFunc("attachVideo", first, CreateObject("roSGNode", "SessionVideoBoundary")), "stale video identity ignored")
    check(not manager.callFunc("attachVideo", id, CreateObject("roSGNode", "Group")), "node without video controls refused")
    queued = manager.callFunc("startSession", sessionDescriptor())
    manager.callFunc("stopSession", queued)
    check(manager.callFunc("fixtureRead").pending = invalid, "queued request cancelled without new worker")
    check(not manager.callFunc("attachVideo", id, CreateObject("roSGNode", "SessionVideoBoundary")), "stopping owner cannot attach a new video")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    check(not manager.busy, "cancelled queued request does not restart")
    manager.callFunc("onDestroy")

    ' A stopped-event subscriber may synchronously request another start.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    queued = manager.callFunc("startSession", sessionDescriptor("older"))
    m.watchManager = manager
    m.reentrantId = ""
    m.reentrantCalled = false
    manager.observeField("event", "onManagerEvent")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    manager.unobserveField("event")
    state = manager.callFunc("fixtureRead")
    check(m.reentrantCalled and m.reentrantId <> "", "stopped subscriber actually requested a replacement")
    check(state.currentId = m.reentrantId and state.worker.inputDescriptor["sourceUrl"].InStr("/reentrant.m3u8") > 0, "reentrant request replaces one pending start after cleanup")
    check(state.pending = invalid, "no second queued owner remains after reentrant start")
    finishManager(manager)
    m.watchManager = invalid

    ' Cleanup timeout never permits a second owner, including later Retry.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    queued = manager.callFunc("startSession", sessionDescriptor())
    manager.callFunc("fixtureTimeout")
    state = manager.callFunc("fixtureRead")
    check(manager.cleanupBlocked and manager.busy and state.pending = invalid, "timeout blocks namespace and cancels pending start")
    check(state.worker.isSameNode(worker) and worker.stopRequested and worker.control = "run", "timeout retains actual resource owner and cooperative stop")
    check(manager.callFunc("startSession", sessionDescriptor()) = "", "Retry cannot start another writer after cleanup timeout")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    check(not manager.busy and manager.cleanupBlocked, "late safe stop releases references but keeps failed session blocked")
    manager.callFunc("onDestroy")

    ' A deadline may permit UI departure after actual Video STOP while the Task
    ' remains owned and busy. Stop control alone can never authorize departure.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    video = CreateObject("roSGNode", "SessionVideoBoundary")
    video.state = "playing"
    check(manager.callFunc("attachVideo", id, video), "deadline owner attaches actual Video node")
    queued = manager.callFunc("startSession", sessionDescriptor("deadline-queued"))
    superseded = queued
    queued = manager.callFunc("startSession", sessionDescriptor("deadline-latest"))
    manager.callFunc("fixtureTimeout")
    check(manager.busy and worker.state = "run" and video.control = "stop", "deadline is not an actual stop acknowledgment")
    check(not manager.callFunc("canLeaveBlockedSession", id), "playing Video refuses blocked UI exit despite stop control")
    video.state = "stopped"
    check(manager.callFunc("canLeaveBlockedSession", id), "actual Video STOP permits UI exit while Task remains running")
    check(manager.callFunc("canLeaveBlockedSession", queued), "known pending ID cancelled by blockage may leave the same stopped Video owner")
    check(not manager.callFunc("canLeaveBlockedSession", superseded) and not manager.callFunc("canLeaveBlockedSession", "00000000000000000000000000000000"), "superseded and arbitrary IDs cannot authorize blocked exit")
    state = manager.callFunc("fixtureRead")
    check(manager.busy and manager.cleanupBlocked and state.worker.isSameNode(worker) and state.video.isSameNode(video) and state.pending = invalid, "blocked exit permission changes no owner or busy acknowledgment")
    check(manager.event.status = "failed" and manager.event.reason = "cleanup_blocked", "late Video STOP notifies blocked UI once")
    check(manager.callFunc("startSession", sessionDescriptor()) = "", "blocked UI departure cannot start a replacement")
    worker.result = cleanupFor(id)
    check(manager.busy, "safe result still requires actual Task STOP after UI permission")
    worker.state = "stop"
    check(not manager.busy and manager.cleanupBlocked and manager.callFunc("fixtureRead").worker = invalid, "late truthful Task ACK safely releases without restarting cancelled owner")
    check(not manager.callFunc("canLeaveBlockedSession", id), "released owner no longer grants blocked exit permission")
    manager.callFunc("onDestroy")

    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    manager.callFunc("stopSession", id)
    manager.callFunc("fixtureTimeout")
    check(manager.busy and manager.callFunc("canLeaveBlockedSession", id), "never-attached Video permits blocked pending-start departure without Task ACK")
    check(manager.callFunc("fixtureRead").worker.isSameNode(worker) and worker.state = "run", "pending-start UI permission retains unacknowledged Task")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    manager.callFunc("onDestroy")

    ' One final result may end UI waiting only after actual Task and Video stop.
    ' Unsafe flags never free ownership, reset blockage, or start a queued owner.
    for each name in ["cleanupOk", "listenerClosed", "connectionClosed", "helperClosed", "cacheReferencesReleased"]
        for each badValue in [false, invalid, "true", 1]
            manager = newManager()
            id = manager.callFunc("startSession", sessionDescriptor())
            worker = manager.callFunc("fixtureRead").worker
            video = CreateObject("roSGNode", "SessionVideoBoundary")
            video.state = "playing"
            check(manager.callFunc("attachVideo", id, video), "terminal unsafe owner has actual Video reference")
            queued = manager.callFunc("startSession", sessionDescriptor("unsafe-queued"))
            result = cleanupFor(id)
            if badValue = invalid
                result.Delete(name)
            else
                result[name] = badValue
            end if
            worker.result = result
            check(manager.busy, "unsafe final result alone still waits for Task stop: " + name)
            worker.state = "stop"
            check(manager.busy and not manager.cleanupBlocked, "unsafe flags cannot stand in for actual Video stop: " + name)
            video.state = "stopped"
            state = manager.callFunc("fixtureRead")
            check(not manager.busy and manager.cleanupBlocked, "one-shot unsafe stop ends UI wait: " + name)
            check(manager.callFunc("canLeaveBlockedSession", id) and manager.callFunc("canLeaveBlockedSession", queued) and not manager.callFunc("canLeaveBlockedSession", "00000000000000000000000000000000"), "blocked UI exit requires exact retained owner or its known cancelled pending ID: " + name)
            check(state.worker.isSameNode(worker) and state.video.isSameNode(video) and state.currentId = id, "unsafe actual owners and namespace remain retained: " + name)
            check(state.pending = invalid and manager.event.status = "failed" and manager.event.id = id, "unsafe cleanup cancels replacement before completion: " + name)
            check(worker.control = "run" and state.stopping and state.cleanupClock = invalid, "no factory destruction or continuing terminal clock: " + name)
            check(manager.findNode("cleanupTimer").control = "stop", "terminal acknowledgment stops polling timer: " + name)
            if m.control = "cleanup" and name = "cleanupOk" and badValue = false
                check(state.worker = invalid, "deliberate false-cleanup control")
                finishTests()
                return
            end if
            check(manager.callFunc("startSession", sessionDescriptor()) = "", "Retry refused after terminal unsafe acknowledgment: " + name)
            manager.callFunc("stopSession", queued)
            check(state.worker.isSameNode(manager.callFunc("fixtureRead").worker), "old cancelled request cannot release retained owner: " + name)
            manager.callFunc("onDestroy")
            state = manager.callFunc("fixtureRead")
            check(state.disposed and state.worker.isSameNode(worker) and state.video.isSameNode(video) and not manager.busy, "permanent disposal cooperates without unsafe release: " + name)
        end for
    end for

    ' Invalid ready on a fresh worker causes cooperative stop, never playback.
    for each port in [0, 8060, 49151, 65536]
        manager = newManager()
        id = manager.callFunc("startSession", sessionDescriptor())
        worker = manager.callFunc("fixtureRead").worker
        bad = readyFor(id)
        bad.boundPort = port
        worker.ready = bad
        check(worker.stopRequested and manager.event.status = "stopping", "bad port rejected: " + port.ToStr())
        finishManager(manager)
    end for
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    signed = readyFor(id)
    signed.boundAddressText = "127.0.0.1:-16165"
    worker.ready = signed
    check(manager.event.status = "ready", "native signed port address is recognized without changing actual unsigned URL")
    finishManager(manager)

    for each port in [49152, 65535, 49371&]
        manager = newManager()
        id = manager.callFunc("startSession", sessionDescriptor())
        worker = manager.callFunc("fixtureRead").worker
        ready = readyFor(id)
        ready.boundPort = port
        ready.boundAddressText = "127.0.0.1:" + port.ToStr()
        worker.ready = ready
        check(manager.event.status = "ready" and manager.event.url = "http://127.0.0.1:" + port.ToStr() + "/master.m3u8", "validated high-port boundary accepted")
        finishManager(manager)
    end for
    for each field in ["actualInitValidated", "decoderApproved", "metadata", "boundAddressText", "boundPort"]
        manager = newManager()
        id = manager.callFunc("startSession", sessionDescriptor())
        worker = manager.callFunc("fixtureRead").worker
        ready = readyFor(id)
        ready[field] = invalid
        worker.ready = ready
        check(worker.stopRequested and manager.event.status <> "ready", "missing ready proof refused: " + field)
        finishManager(manager)
    end for
    for each badProof in [false, "true", 1]
        manager = newManager()
        id = manager.callFunc("startSession", sessionDescriptor())
        worker = manager.callFunc("fixtureRead").worker
        ready = readyFor(id)
        ready.decoderApproved = badProof
        worker.ready = ready
        check(worker.stopRequested and manager.event.status <> "ready", "coerced decoder ready proof refused")
        finishManager(manager)
    end for
    for each change in [{ field: "boundPort", value: 49371.0 }, { field: "boundPort", value: "49371" }, { field: "boundAddressText", value: "10.0.0.1" }, { field: "boundAddressText", value: "127.0.0.1:49372" }, { field: "boundAddressText", value: "127.0.0.1:-16164" }, { field: "actualInitValidated", value: "true" }, { field: "actualInitValidated", value: 1 }, { field: "metadata", value: [] }]
        manager = newManager()
        id = manager.callFunc("startSession", sessionDescriptor())
        worker = manager.callFunc("fixtureRead").worker
        ready = readyFor(id)
        ready[change.field] = change.value
        worker.ready = ready
        check(worker.stopRequested and manager.event.status <> "ready", "non-loopback text or coerced ready value refused")
        finishManager(manager)
    end for
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    worker.ready = { sessionId: {} }
    worker.result = { sessionId: 1 }
    check(not worker.stopRequested and manager.event.status = "starting", "malformed foreign identities ignored without a crash")
    worker.state = "stop"
    check(worker.stopRequested and manager.busy, "unacknowledged unexpected worker stop retains ownership")
    worker.result = cleanupFor(id)
    check(not manager.busy, "unexpected worker stop releases after real cleanup only")
    manager.callFunc("onDestroy")

    ' Removed caller does not abandon Task, pending start or Video stop.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    video = CreateObject("roSGNode", "SessionVideoBoundary")
    video.state = "playing"
    check(manager.callFunc("attachVideo", id, video), "disposal video observer attached")
    queued = manager.callFunc("startSession", sessionDescriptor())
    manager.callFunc("onDestroy")
    check(manager.busy and worker.stopRequested and video.control = "stop", "disposal retains manager until worker and video stop")
    check(manager.callFunc("startSession", sessionDescriptor()) = "" and manager.callFunc("fixtureRead").pending = invalid, "disposed manager cannot start or preserve queued replacement")
    worker.ready = readyFor(id)
    check(manager.event.status <> "ready", "late ready cannot recreate disposed UI")
    worker.result = cleanupFor(id)
    worker.state = "stop"
    check(manager.busy, "disposal still requires real Video stop")
    video.state = "stopped"
    check(not manager.busy and manager.callFunc("fixtureRead").worker = invalid, "disposal completes only after actual acknowledgment")
    check(manager.findNode("cleanupTimer").control = "stop", "disposal timer stopped after safe release")
    manager.callFunc("onDestroy")
    check(not manager.busy and manager.callFunc("fixtureRead").disposed, "repeated disposal is idempotent")

    ' The Player's ordinary observer teardown must not remove the separate
    ' manager-owned scoped observation needed to acknowledge actual Video STOP.
    manager = newManager()
    id = manager.callFunc("startSession", sessionDescriptor())
    worker = manager.callFunc("fixtureRead").worker
    video = CreateObject("roSGNode", "SessionVideoBoundary")
    m.callerVideoChanges = 0
    video.observeField("state", "onCallerVideoState")
    check(manager.callFunc("attachVideo", id, video), "independent scoped manager video observer attached")
    video.state = "playing"
    check(m.callerVideoChanges = 1, "Player-owned state observer actually fires")
    video.unobserveField("state")
    manager.callFunc("stopSession", id)
    worker.result = cleanupFor(id)
    worker.state = "stop"
    check(manager.busy, "Player observer removal does not fake video stop")
    video.state = "stopped"
    check(not manager.busy and manager.callFunc("fixtureRead").video = invalid, "manager scoped listener still completes real stop after Player teardown")
    check(m.callerVideoChanges = 1, "removed Player callback stays removed")
    manager.callFunc("onDestroy")

    finishTests()
end sub

sub testSourceTransitionClassification()
    cases = [
        { ready: true, reason: "live_helper_failed", helper: "native-live: selected discontinuity change unsupported", expected: "source_transition", label: "selected epoch" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: continuity window crosses map or discontinuity", expected: "source_transition", label: "continuity window" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: selected window crosses map or discontinuity", expected: "source_transition", label: "selected window" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported", expected: "source_transition", label: "GET status or range unsupported" }
        { ready: false, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported", expected: "worker_finished", label: "GET before ready" }
        { ready: true, vod: true, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported", expected: "worker_finished", label: "GET on ready VOD" }
        { ready: true, reason: "native_exception", helper: "native-live: GET status or range unsupported", expected: "worker_finished", label: "GET wrong result reason" }
        { ready: true, reason: {}, helper: "native-live: GET status or range unsupported", expected: "worker_finished", label: "GET nonstring result reason" }
        { ready: true, reason: "live_helper_failed", helper: "native-demux: GET status or range unsupported", expected: "worker_finished", label: "GET foreign helper prefix" }
        { ready: true, reason: "live_helper_failed", helper: "prefix native-live: GET status or range unsupported", expected: "worker_finished", label: "GET extra prefix" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported extra", expected: "worker_finished", label: "GET extra suffix" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported https://private.invalid/DIAGNOSTIC_SECRET_TOKEN", expected: "worker_finished", label: "GET private suffix" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: HEAD status or range unsupported", expected: "worker_finished", label: "HEAD stays outside GET recovery" }
        { ready: false, reason: "live_helper_failed", helper: "native-live: selected discontinuity change unsupported", expected: "worker_finished" }
        { ready: false, reason: "live_helper_failed", helper: "native-live: continuity window crosses map or discontinuity", expected: "worker_finished" }
        { ready: false, reason: "live_helper_failed", helper: "native-live: selected window crosses map or discontinuity", expected: "worker_finished" }
        { ready: true, reason: "native_exception", helper: "native-live: selected discontinuity change unsupported", expected: "worker_finished" }
        { ready: true, reason: "native_exception", helper: "native-live: continuity window crosses map or discontinuity", expected: "worker_finished" }
        { ready: true, reason: "native_exception", helper: "native-live: selected window crosses map or discontinuity", expected: "worker_finished" }
        { ready: true, reason: {}, helper: "native-live: continuity window crosses map or discontinuity", expected: "worker_finished" }
        { ready: true, reason: {}, helper: "native-live: selected window crosses map or discontinuity", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: selected map initialization changed", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: upstream operation deadline", expected: "source_transition", label: "upstream operation deadline" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: upstream progress deadline", expected: "source_transition", label: "upstream progress deadline" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: continuity window segment bound", expected: "source_transition", label: "continuity span" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: continuity history unavailable", expected: "source_transition", label: "continuity history" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: source sequence gap", expected: "source_transition", label: "sequence gap" }
        { ready: false, reason: "live_helper_failed", helper: "native-live: upstream operation deadline", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-demux: selected discontinuity change unsupported", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-demux: continuity window crosses map or discontinuity", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-demux: selected window crosses map or discontinuity", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: selected discontinuity change unsupported extra", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: continuity window crosses map or discontinuity extra", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: selected window crosses map or discontinuity extra", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: "native-live: selected window crosses map or discontinuity https://private.invalid/DIAGNOSTIC_SECRET_TOKEN", expected: "worker_finished" }
        { ready: true, reason: {}, helper: "native-live: selected discontinuity change unsupported", expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: {}, expected: "worker_finished" }
        { ready: true, reason: "live_helper_failed", helper: invalid, expected: "worker_finished" }
    ]
    for each status in [401, 403, 500, 502, 503, 599]
        cases.push({ ready: true, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported", status: status, expected: "source_transition", label: "recoverable HTTP status " + status.ToStr() })
    end for
    for each status in [200, 206, 301, 400, 404, 416, 429, 0, -1, 600, "503", true, {}, 503.5]
        cases.push({ ready: true, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported", status: status, hasRange: true, expected: "worker_finished", label: "deterministic or malformed HTTP result" })
    end for
    cases.push({ ready: true, reason: "live_helper_failed", helper: "native-live: GET status or range unsupported", status: 200, hasRange: false, expected: "worker_finished", label: "inconsistent successful GET result" })
    for each helper in ["native-live: selected discontinuity change unsupported", "native-live: continuity window crosses map or discontinuity", "native-live: selected window crosses map or discontinuity", "native-live: GET status or range unsupported"]
        for each field in ["cleanupOk", "listenerClosed", "connectionClosed", "helperClosed", "cacheReferencesReleased"]
            for each value in [false, invalid, "true", 1]
                cases.push({ ready: true, reason: "live_helper_failed", helper: helper, expected: "worker_finished", badField: field, badValue: value })
            end for
        end for
    end for
    for each item in cases
        manager = newManager()
        descriptor = sessionDescriptor()
        if item.DoesExist("vod") then descriptor = vodSessionDescriptor()
        id = manager.callFunc("startSession", descriptor)
        worker = manager.callFunc("fixtureRead").worker
        if item.ready
            ready = readyFor(id)
            if item.DoesExist("vod") then ready = vodReadyFor(id, descriptor)
            worker.ready = ready
            check(manager.event.status = "ready", "classification matrix uses an actually ready session")
        end if
        port = CreateObject("roMessagePort")
        manager.observeField("event", port)
        result = cleanupFor(id)
        result.reason = item.reason
        result.helperFailureReason = item.helper
        if item.DoesExist("status") then result.upstreamStatus = item.status
        if item.DoesExist("hasRange") then result.upstreamHasRange = item.hasRange
        if item.DoesExist("badField")
            if item.badValue = invalid
                result.Delete(item.badField)
            else
                result[item.badField] = item.badValue
            end if
        end if
        worker.result = result
        failed = nextFailure(port)
        check(failed <> invalid, "actual result handler emits a failure event")
        label = "transition classification requires exact ready reason and safe cleanup"
        if item.DoesExist("label") then label += ": " + item.label
        if failed <> invalid then check(failed.reason = item.expected and failed.id = id, label)
        check(worker.stopRequested and manager.busy, "classified failure still retains the cooperative worker owner")
        manager.unobserveField("event")
        finishManager(manager)
    end for

    for each helper in ["native-live: selected discontinuity change unsupported", "native-live: continuity window crosses map or discontinuity", "native-live: selected window crosses map or discontinuity", "native-live: GET status or range unsupported"]
        manager = newManager()
        first = manager.callFunc("startSession", sessionDescriptor("old-epoch"))
        worker = manager.callFunc("fixtureRead").worker
        worker.ready = readyFor(first)
        video = CreateObject("roSGNode", "SessionVideoBoundary")
        video.state = "playing"
        check(manager.callFunc("attachVideo", first, video), "transition has a real manager-owned playing Video boundary")
        port = CreateObject("roMessagePort")
        manager.observeField("event", port)
        stale = cleanupFor("00000000000000000000000000000000")
        stale.reason = "live_helper_failed"
        stale.helperFailureReason = helper
        worker.result = stale
        check(not worker.stopRequested and nextFailure(port) = invalid, "foreign transition identity cannot stop or classify the current owner")
        worker.result = { sessionId: 1, reason: "live_helper_failed", helperFailureReason: helper }
        check(not worker.stopRequested and nextFailure(port) = invalid, "malformed transition identity cannot affect the current owner")
        result = cleanupFor(first)
        result.reason = "live_helper_failed"
        result.helperFailureReason = helper
        worker.result = result
        failed = nextFailure(port)
        check(failed <> invalid, "ready transition publishes its fixed failure event")
        if failed <> invalid then check(failed.reason = "source_transition", "ready exact transition publishes only the static restart reason")
        check(video.control = "stop" and worker.stopRequested and manager.busy, "transition requests actual Video and worker stop before replacement")
        second = manager.callFunc("startSession", sessionDescriptor("fresh-epoch"))
        state = manager.callFunc("fixtureRead")
        check(second <> first and state.currentId = first and state.worker.isSameNode(worker), "fresh descriptor queues behind the stopped old timeline")
        worker.result = result
        check(nextFailure(port) = invalid, "repeated stopping result cannot publish another transition")
        worker.state = "stop"
        check(manager.busy and manager.callFunc("fixtureRead").worker.isSameNode(worker), "actual worker STOP cannot replace a still-playing Video")
        video.state = "stopped"
        state = manager.callFunc("fixtureRead")
        check(state.currentId = second and not state.worker.isSameNode(worker) and state.worker.control = "run", "fresh worker starts only after old worker and Video STOP")
        check(worker.control = "stop" and state.worker.inputDescriptor.sourceUrl.InStr("fresh-epoch") >= 0 and state.video = invalid, "replacement uses fresh descriptor without old owner or cache references")
        check(not state.worker.stopRequested and manager.busy, "old transition cleanup never stops the fresh worker")
        manager.unobserveField("event")
        finishManager(manager)
    end for

    ' Video's error state and the worker result may notify in either order.
    for each errorFirst in [false, true]
        manager = newManager()
        first = manager.callFunc("startSession", sessionDescriptor("selected-window-old"))
        worker = manager.callFunc("fixtureRead").worker
        worker.ready = readyFor(first)
        video = CreateObject("roSGNode", "SessionVideoBoundary")
        video.state = "playing"
        check(manager.callFunc("attachVideo", first, video), "selected-window error ordering has real Video owner")
        port = CreateObject("roMessagePort")
        manager.observeField("event", port)
        if errorFirst
            video.state = "error"
            check(not worker.stopRequested and nextFailure(port) = invalid, "Video error before result does not fabricate a transition")
        end if
        result = cleanupFor(first)
        result.reason = "live_helper_failed"
        result.helperFailureReason = "native-live: selected window crosses map or discontinuity"
        worker.result = result
        failed = nextFailure(port)
        check(failed <> invalid, "selected-window result emits one failure in either callback ordering")
        if failed <> invalid then check(failed.reason = "source_transition" and failed.id = first, "selected-window callback ordering keeps exact ready classification")
        if not errorFirst then video.state = "error"
        check(nextFailure(port) = invalid and video.control = "stop" and worker.stopRequested, "Video error after result cannot duplicate classification or acknowledge STOP")
        second = manager.callFunc("startSession", sessionDescriptor("selected-window-superseded"))
        third = manager.callFunc("startSession", sessionDescriptor("selected-window-fresh"))
        check(third <> second and manager.callFunc("fixtureRead").pending.id = third, "selected-window recovery retains only latest pending identity")
        worker.result = result
        check(nextFailure(port) = invalid, "selected-window duplicate result during stop cannot reconnect again")
        worker.state = "stop"
        check(manager.busy and manager.callFunc("fixtureRead").worker.isSameNode(worker), "Video error never replaces truthful Video STOP acknowledgment")
        video.state = "stopped"
        state = manager.callFunc("fixtureRead")
        check(state.currentId = third and not state.worker.isSameNode(worker) and state.video = invalid, "selected-window replacement waits for both STOP acknowledgments")
        check(state.worker.inputDescriptor.sourceUrl.InStr("selected-window-fresh") >= 0 and not state.worker.stopRequested, "selected-window reconnect uses only fresh descriptor and cooperative owner")
        worker.result = result
        check(state.worker.isSameNode(manager.callFunc("fixtureRead").worker) and nextFailure(port) = invalid, "released old result cannot affect the selected-window replacement")
        manager.unobserveField("event")
        finishManager(manager)
    end for
end sub

function nextFailure(port as object) as dynamic
    ' Port events retain the failed payload even when stopping is published next.
    while true
        event = port.GetMessage()
        if event = invalid then return invalid
        if type(event) = "roSGNodeEvent"
            data = event.GetData()
            if type(data) = "roAssociativeArray"
                if data.status = "failed" then return data
            end if
        end if
    end while
end function

sub onManagerEvent()
    if m.watchManager = invalid or m.reentrantCalled then return
    if m.watchManager.event.status = "stopped"
        m.reentrantCalled = true
        m.reentrantId = m.watchManager.callFunc("startSession", sessionDescriptor("reentrant"))
    end if
end sub

sub onCallerVideoState()
    m.callerVideoChanges++
end sub

function newManager() as object
    node = CreateObject("roSGNode", "RokuDemuxSession")
    m.top.appendChild(node)
    return node
end function

sub finishManager(manager as object)
    state = manager.callFunc("fixtureRead")
    if state.worker <> invalid
        manager.callFunc("stopSession", "")
        state.worker.result = cleanupFor(state.currentId)
        state.worker.state = "stop"
        if state.video <> invalid then state.video.state = "stopped"
    end if
    check(not manager.busy, "fixture cleanup acknowledged")
    manager.callFunc("onDestroy")
    m.top.removeChild(manager)
end sub

function readyFor(id as string) as object
    return { sessionId: id, boundPort: 49371, boundAddressText: "127.0.0.1", decoderApproved: true, actualInitValidated: true, metadata: { width: 1920, height: 1080 } }
end function

function cleanupFor(id as string) as object
    return { sessionId: id, cleanupOk: true, listenerClosed: true, connectionClosed: true, helperClosed: true, cacheReferencesReleased: true }
end function

function sessionDescriptor(choice = "default" as string) as object
    return { "version": 1, "sourceUrl": "https://use14.playlist.ttvnw.net/canned/" + choice + ".m3u8?token=canned%2B", "qualityId": "720p60", "approvedOrigins": ["https://use14.playlist.ttvnw.net"], "metadata": { "videoCodec": "avc1.4D4020", "audioCodec": "mp4a.40.2", "width": 1280, "height": 720, "frameRate": "60.000", "bandwidth": 3322199, "isHD": true } }
end function

function vodSessionDescriptor() as object
    live = sessionDescriptor()
    return { version: 2, mode: "vod", vodId: "123456789", usherUrl: "https://usher.ttvnw.net/vod/v2/123456789.m3u8?fixture=canned", sourceUrl: "https://d123.cloudfront.net/vod/720.m3u8?fixture=canned", qualityId: "720p60", approvedOrigin: "https://d123.cloudfront.net", metadata: live.metadata }
end function

function vodReadyFor(id as string, descriptor as object) as object
    return { sessionId: id, boundAddressText: "127.0.0.1", boundPort: 49371, metadata: descriptor.metadata, decoderApproved: true, actualInitValidated: true, requestedDecoderFormat: { codec: "mpeg4 avc", profile: "main", level: "3.2" }, mode: "vod", totalDurationUs: 60000000&, masterPath: "/vod/" + id + "/master.m3u8" }
end function

function sessionIdentifier(value as string) as boolean
    return CreateObject("roRegex", "^[0-9a-f]{32}$", "").IsMatch(value)
end function

sub check(value as boolean, message as string)
    m.assertions += 1
    if not value
        m.failures += 1
        print "SESSION_ASSERT_FAIL: "; message
    end if
end sub

sub finishTests()
    m.top.testResult = { assertions: m.assertions, failures: m.failures }
end sub
