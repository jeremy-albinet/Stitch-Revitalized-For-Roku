sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: {}, emoteCache: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()
    __CHAT_SCENARIO__()
    fixtureEnd()
end sub

sub testStorageWaiterLifecycle()
    first = newChat()
    installEmotes(first, 1)
    first.callFunc("fixtureMessage", "E0", "draining-owner", 50)
    worker = pending(first)
    worker.fixtureHoldAfterResponse = true
    first.callFunc("onDestroy")
    m.scene.removeChild(first)
    waitResponse(worker)

    hidden = newChat()
    installEmotes(hidden, 1)
    hidden.callFunc("fixtureMessage", "E0", "hidden-waiter", 50)
    check(hidden.callFunc("fixtureRead").storageObserved, "visible blocked Chat subscribes to shared release")
    hidden.visible = false
    check(not hidden.callFunc("fixtureRead").storageObserved, "hide removes scoped global observer")

    disposed = newChat()
    installEmotes(disposed, 1)
    disposed.callFunc("fixtureMessage", "E0", "disposed-waiter", 50)
    disposed.callFunc("onDestroy")
    m.scene.removeChild(disposed)
    check(not disposed.callFunc("fixtureRead").storageObserved, "disposal removes scoped global observer")

    second = newChat()
    installEmotes(second, 1)
    second.callFunc("fixtureSynchronousStorage", true)
    second.callFunc("fixtureMessage", "E0", "visible-waiter", 50)
    competitor = newChat()
    installEmotes(competitor, 1)
    competitor.callFunc("fixtureMessage", "E0", "other-waiter", 50)
    check(competitor.callFunc("fixtureRead").storageObserved and second.callFunc("fixtureRead").storageObserved, "multiple Chats have independent scoped release observers")
    competitor.visible = false
    check(not competitor.callFunc("fixtureRead").storageObserved and second.callFunc("fixtureRead").storageObserved, "one waiter's cleanup preserves the other observer")
    hiddenCallbacks = hidden.callFunc("fixtureRead").storageCallbacks
    disposedCallbacks = disposed.callFunc("fixtureRead").storageCallbacks
    worker.fixtureHoldAfterResponse = false
    replacement = pending(second)
    state = second.callFunc("fixtureRead")
    check(state.synchronousStorageEvents = 1 and state.workersCreated = 1 and state.serial = 1, "synchronous own-acquire callback cannot reenter admission: workers=" + state.workersCreated.toStr())
    if state.workersCreated <> 1 then return
    check(hidden.callFunc("fixtureRead").storageCallbacks = hiddenCallbacks and disposed.callFunc("fixtureRead").storageCallbacks = disposedCallbacks, "hidden and disposed Chats receive no global release callbacks after scoped cleanup")
    check(not state.storageObserved and worker.getParent() = invalid, "release waiter clears latch before reserving the next completed handoff")
    hidden.callFunc("fixtureStaleStorage")
    disposed.callFunc("fixtureStaleStorage")
    second.callFunc("fixtureStaleStorage")
    settle(40)
    check(hidden.callFunc("fixtureRead").task = invalid and hidden.callFunc("fixtureRead").serial = 0, "hidden stale release callback cannot restart work")
    check(disposed.callFunc("fixtureRead").task = invalid and disposed.callFunc("fixtureRead").serial = 0, "disposed stale release callback cannot restart work")
    check(second.callFunc("fixtureRead").workersCreated = 1 and second.callFunc("fixtureRead").task.isSameNode(replacement), "stale release cannot replace the next owner's worker")
    complete(second, replacement)
    second.visible = false
    hidden.visible = true
    hidden.callFunc("fixtureDelivered")
    check(hidden.callFunc("fixtureRead").storageObserved and hidden.callFunc("fixtureRead").task = invalid, "hidden completed cache retains ownership until acknowledged purge")
    second.callFunc("fixtureHoldTasks", true)
    second.callFunc("onDestroy")
    cleanup = second.callFunc("fixtureRead").task
    waitResponse(cleanup)
    check(hidden.callFunc("fixtureRead").task = invalid, "cleanup response alone cannot wake the waiting Chat")
    cleanup.fixtureHoldAfterResponse = false
    nextWorker = pending(hidden)
    check(hidden.callFunc("fixtureRead").serial = 1 and nextWorker.request.path <> replacement.request.path, "retained cache release wakes another visible waiter after actual cleanup completion")
    m.scene.removeChild(second)
    dispose(hidden)
    dispose(competitor)
end sub

sub testChatAnimations()
    ' The dense testCacheLimits case runs through its own child entry.
    testOwnership()
    if m.failures > 0 then return
    testCleanupFailure()
    testStaleGeneration()
    testVisibilityAndBounds()
    testProviderHandoff()
    for each support in ["unsupported", "missing-fields", "wrong-field-types"]
        chat = newChat(support)
        installEmotes(chat, 1)
        row = chat.callFunc("fixtureMessage", "E0", support, 50)
        chat.callFunc("fixtureSync")
        state = chat.callFunc("fixtureRead")
        check(state.supported = false and state.probes = 1 and state.task = invalid and state.native = invalid, "capability failure is cached without downloading: " + support)
        check(row.getChild(0).getChild(0).visible, "unsupported runtime keeps static Poster")
        dispose(chat)
    end for
end sub

sub testSharedOwnership()
    first = newChat()
    installEmotes(first, 1)
    first.callFunc("fixtureMessage", "E0", "disposed-download", 50)
    worker = pending(first)
    path = worker.request.path
    worker.fixtureLockedPath = path
    worker.fixtureHoldAfterResponse = true
    first.callFunc("onDestroy")
    m.scene.removeChild(first)
    waitResponse(worker)
    check(worker.state = "run" and not worker.response.cleanupOk and exists(path), "disposed worker is held after failed real-file deletion before thread completion")

    second = newChat()
    installEmotes(second, 1)
    row = second.callFunc("fixtureMessage", "E0", "new-owner", 50)
    settle(40)
    nextWorker = second.callFunc("fixtureRead").task
    workers = 1
    files = 1
    if nextWorker <> invalid
        waitField(nextWorker, "fixtureStarted", true)
        if nextWorker.state = "run" then workers++
        if exists(nextWorker.request.path) then files++
    end if
    blocked = nextWorker = invalid and second.callFunc("fixtureRead").serial = 0
    check(blocked, "disposed draining worker must reserve global admission: workers=" + workers.toStr() + " files=" + files.toStr())
    if not blocked then return
    check(second.callFunc("fixtureRead").native = invalid and row.getChild(0).getChild(0).visible, "another Chat keeps its static fallback while shared ownership drains")
    worker.fixtureHoldAfterResponse = false
    waitRead(first, "task", invalid, "failed disposed worker completion")
    check(first.callFunc("fixtureRead").blocked and exists(path), "thread completion alone cannot release an unacknowledged file")
    second.visible = false
    second.visible = true
    second.callFunc("fixtureDelivered")
    second.callFunc("fixtureStaleAsset", worker)
    second.callFunc("fixtureSync")
    check(second.callFunc("fixtureRead").task = invalid and second.callFunc("fixtureRead").serial = 0, "reopening and stale completion cannot bypass failed shared cleanup")
    first.callFunc("fixtureRetryCleanup")
    waitRead(first, "task", invalid, "acknowledged disposed cleanup")
    check(not exists(path), "same owner can release storage after completed acknowledged cleanup")
    settle(80)
    check(second.callFunc("fixtureRead").task <> invalid, "visible waiting Chat wakes automatically after acknowledged ownership release")
    if second.callFunc("fixtureRead").task = invalid then return
    replacement = pending(second)
    check(replacement.request.path <> path and worker.getParent() = invalid, "new Chat downloads only after prior thread and file cleanup finish")
    second.callFunc("fixtureStaleAsset", worker)
    check(second.callFunc("fixtureRead").task.isSameNode(replacement), "old completion cannot release another Chat's reserved worker")
    dispose(second)
    check(not exists(replacement.request.path), "canceled replacement is acknowledged and deleted before its reservation is released")

    first = newChat()
    installEmotes(first, 4)
    first.callFunc("fixtureSource", "one-mib.webp")
    paths = []
    for index = 0 to 3
        first.callFunc("fixtureClear")
        first.callFunc("fixtureMessage", "E" + index.toStr(), "full-cache" + index.toStr(), 50)
        worker = pending(first)
        paths.push(worker.request.path)
        complete(first, worker)
    end for
    first.visible = false
    state = first.callFunc("fixtureRead")
    check(state.task = invalid and state.native = invalid and state.cacheBytes = 4194304 and state.cacheCount = 4, "hidden Chat retains the complete 4 MiB compressed budget without a worker")
    second = newChat()
    installEmotes(second, 4)
    row = second.callFunc("fixtureMessage", "E0", "retained-cache", 50)
    second.callFunc("fixtureSource", "one-mib.webp")
    second.callFunc("fixtureSync")
    check(second.callFunc("fixtureRead").task = invalid and second.callFunc("fixtureRead").serial = 0, "completed cache in another Chat reserves the shared byte and entry budget")
    first.visible = true
    first.callFunc("fixtureDelivered")
    settle(20)
    state = first.callFunc("fixtureRead")
    check(state.serial = 4 and state.native.uri = paths[3] and state.cacheBytes = 4194304, "hide/show reuses the owning Chat's completed cache inside the global reservation")
    second.callFunc("fixtureSync")
    check(second.callFunc("fixtureRead").native = invalid and row.getChild(0).getChild(0).visible, "only the reserved Chat can display a native animation across instances")
    first.callFunc("fixtureHoldTasks", true)
    first.callFunc("onDestroy")
    m.scene.removeChild(first)
    cleanup = first.callFunc("fixtureRead").task
    waitResponse(cleanup)
    check(cleanup.state = "run" and cleanup.response.cleanupOk and cleanup.response.removed.count() = 4, "cleanup acknowledgment can precede actual Task completion across Chat instances")
    for each path in paths
        check(not exists(path), "cleanup worker deletes each completed cache file before acknowledging it")
    end for
    second.visible = false
    second.visible = true
    second.callFunc("fixtureDelivered")
    second.callFunc("fixtureStaleAsset", cleanup)
    second.callFunc("fixtureSync")
    check(second.callFunc("fixtureRead").task = invalid and second.callFunc("fixtureRead").serial = 0, "even acknowledged deletion cannot release a still-running global worker")
    cleanup.fixtureHoldAfterResponse = false
    waitRead(first, "task", invalid, "completed shared cache cleanup")
    check(first.callFunc("fixtureRead").cacheBytes = 0 and first.callFunc("fixtureRead").partials = 0, "completed cleanup retires all retained cache accounting")
    replacement = pending(second)
    check(first.callFunc("fixtureRead").cacheBytes + 1048576 <= 4194304, "new Chat's admitted asset allowance fits after prior cached bytes are released")
    complete(second, replacement)
    check(second.callFunc("fixtureRead").cacheBytes = 1048576, "new Chat owns and accounts its completed cache after shared handoff")
    first.callFunc("fixtureStaleAsset", cleanup)
    first.callFunc("fixtureSync")
    check(first.callFunc("fixtureRead").task = invalid and second.callFunc("fixtureRead").native.uri = replacement.request.path, "disposed stale completion cannot clear or replace the next owner's active cache")
    dispose(second)
end sub

sub testOwnership()
    chat = newChat()
    installEmotes(chat, 20)
    provider = chat.callFunc("fixtureRead").emoteJob
    row = chat.callFunc("fixtureMessage", "E0", "first", 50)
    firstTask = pending(chat)
    firstPath = firstTask.request.path
    state = chat.callFunc("fixtureRead")
    firstOwner = state.owner
    firstNative = state.native
    check(exists(firstPath) and firstTask.fixtureStarted, "actual Task allocated its directory and wrote the HTTP fixture file")
    check(firstOwner.getChild(0).visible and firstNative.uri = "", "static remains until admission and thread completion")
    second = chat.callFunc("fixtureMessage", "E1", "second", 100)
    duplicate = chat.callFunc("fixtureMessage", "E0", "duplicate", 150)
    alias = chat.callFunc("fixtureMessage", "E19", "alias", 175)
    state = chat.callFunc("fixtureRead")
    stable = state.owner <> invalid and state.task <> invalid
    if stable then stable = state.owner.isSameNode(firstOwner) and state.task.isSameNode(firstTask) and state.serial = 1
    check(stable, "new messages and duplicate URIs cannot restart or hop the active owner")
    if not stable then return
    check(state.candidates = 2, "visible queue deduplicates animated source URIs")
    firstTask.fixtureHoldAfterResponse = true
    firstTask.fixtureRelease = true
    waitField(firstTask, "fixtureCancelled", true)
    waitResponse(firstTask)
    check(firstTask.response.info <> invalid and firstTask.state = "run", "Task can publish response before its thread returns")
    state = chat.callFunc("fixtureRead")
    held = state.task <> invalid
    if held then held = state.task.isSameNode(firstTask) and state.cacheCount = 0 and firstNative.uri = ""
    check(held, "render waits for real thread termination before file handoff")
    if not held then return
    firstTask.fixtureHoldAfterResponse = false
    waitRead(chat, "cacheCount", 1, "admitted cache")
    state = chat.callFunc("fixtureRead")
    check(state.task = invalid and state.cacheBytes = 3842, "admitted file is counted once including active cache")
    check(firstNative.uri = firstPath and firstNative.mimeType = "video/webp" and firstNative.control = "loop", "native decoder receives admitted local WebP")
    check(firstNative.loadWidth = 32 and firstNative.loadHeight = 32, "small source decode is not upscaled")
    for each loading in ["downloading", "init", "ready"]
        firstNative.state = loading
        settle(20)
        check(firstOwner.getChild(0).visible, "still remains during native loading " + loading)
    end for
    firstNative.state = "first"
    settle(20)
    check(not firstOwner.getChild(0).visible, "first native frame hides static beneath transparent animation")
    chat.callFunc("fixtureEvict", firstTask.request.uri)
    check(chat.callFunc("fixtureRead").partials = 0 and exists(firstPath), "active cached file is protected against eviction")
    chat.callFunc("fixtureMove", row, -100)
    canceled = pending(chat)
    canceled.fixtureWriteOnCancel = true
    canceled.fixtureHoldAfterResponse = true
    chat.callFunc("fixtureRemove", "second")
    waitResponse(canceled)
    state = chat.callFunc("fixtureRead")
    check(canceled.stopRequested and state.task.isSameNode(canceled) and canceled.control = "run", "moderation cooperatively cancels but retains the running Task")
    check(canceled.fixtureLateWrite and canceled.fixtureCancelled and not exists(canceled.request.path), "last producer write is removed inside Task after cancellation")
    check(state.serial = 2 and state.native = invalid, "no replacement download or decoder while old worker still runs")
    canceled.fixtureHoldAfterResponse = false
    waitRead(chat, "task", invalid, "canceled task completion")
    state = chat.callFunc("fixtureRead")
    check(state.serial = 2 and state.owner.isSameNode(duplicate.getChild(0)), "duplicate occurrence reuses complete compressed cache")
    check(firstNative.control = "pause" and firstNative.uri = "" and firstNative.getParent() = invalid and firstOwner.getChild(0).visible, "offscreen decoder releases its native resources and restores still")
    chat.callFunc("fixtureMove", duplicate, -100)
    state = chat.callFunc("fixtureRead")
    check(state.owner.isSameNode(alias.getChild(0)) and state.serial = 2, "static URI aliases share animated source cache")
    currentNative = state.native
    chat.callFunc("fixtureStaleAsset", canceled)
    check(chat.callFunc("fixtureRead").native.isSameNode(currentNative), "stale Task generation cannot replace current owner")
    chat.visible = false
    settle(20)
    check(chat.callFunc("fixtureRead").cacheCount = 1 and exists(firstPath), "hiding retains only the completed bounded cache")
    chat.visible = true
    chat.callFunc("fixtureDelivered")
    settle(20)
    check(chat.callFunc("fixtureRead").serial = 2 and chat.callFunc("fixtureRead").native.uri = firstPath, "reopening reuses completed cache without a download")
    chat.callFunc("fixtureStaleMetadata", provider)
    check(chat.callFunc("fixtureRead").descriptors.count() = 20, "old provider generation cannot replace descriptors")
    native = chat.callFunc("fixtureRead").native
    native.state = "error"
    waitRead(chat, "cacheCount", 0, "native failure cleanup")
    check(not exists(firstPath) and chat.callFunc("fixtureRead").failed = 1, "native error restores static and schedules Task-owned deletion")
    chat.callFunc("fixtureClear")
    chat.callFunc("fixtureMessage", "E2", "reject", 50)
    rejected = pending(chat)
    chat.callFunc("fixtureReject", rejected)
    waitRead(chat, "task", invalid, "rejected download")
    check(chat.callFunc("fixtureRead").failed = 2 and not exists(rejected.request.path), "rejected file removed by Task without retry storm")
    set_user_setting("chat.animatedEmotes", "false")
    chat.visible = false
    chat.visible = true
    chat.callFunc("fixtureDelivered")
    settle(40)
    check(not chat.callFunc("fixtureRead").enabled and chat.callFunc("fixtureRead").task = invalid, "disabled setting keeps static emotes")
    set_user_setting("chat.animatedEmotes", "true")
    chat.visible = false
    chat.visible = true
    chat.callFunc("fixtureDelivered")
    task = pending(chat)
    ' Rapid toggles retain one producer and its cancellation until it returns.
    rapidSerial = chat.callFunc("fixtureRead").serial
    task.fixtureHoldAfterResponse = true
    for index = 1 to 6
        chat.visible = false
        chat.visible = true
        chat.callFunc("fixtureDelivered")
    end for
    settle(80)
    rapid = chat.callFunc("fixtureRead")
    check(rapid.task.isSameNode(task) and task.stopRequested and rapid.serial = rapidSerial, "rapid toggles cannot spawn hidden producers")
    task.fixtureHoldAfterResponse = false
    replacement = pending(chat, task)
    check(replacement.request.path <> task.request.path and not exists(task.request.path), "old directory is removed before allocating a unique replacement")
    chat.callFunc("fixtureComplete", replacement)
    waitRead(chat, "cacheCount", 1, "reopened download")
    path = chat.callFunc("fixtureRead").native.uri
    chat.channel = "next-channel"
    waitRead(chat, "cacheCount", 0, "channel cleanup")
    check(chat.callFunc("fixtureRead").native = invalid and not exists(path) and chat.callFunc("fixtureRead").descriptors.count() = 0, "channel change purges files and provider metadata")
    dispose(chat)
end sub

sub testCleanupFailure()
    chat = newChat()
    installEmotes(chat, 1)
    chat.callFunc("fixtureMessage", "E0", "locked", 50)
    task = pending(chat)
    path = task.request.path
    task.fixtureLockedPath = path
    chat.visible = false
    waitRead(chat, "blocked", true, "failed deletion")
    state = chat.callFunc("fixtureRead")
    check(state.partials = 1 and state.task = invalid and exists(path) and task.fixtureDeleteCount = 4, "failed delete stays tracked after exactly two finite attempts")
    for index = 1 to 8
        chat.callFunc("fixtureSync")
    end for
    settle(60)
    check(chat.callFunc("fixtureRead").serial = 1 and task.getParent() = invalid, "cleanup failure blocks downloads and leaves no running orphan Task")
    chat.visible = true
    chat.callFunc("fixtureDelivered")
    replacement = pending(chat)
    check(not exists(path) and replacement.request.path <> path and chat.callFunc("fixtureRead").partials = 0, "reopen retries cleanup before a replacement download")
    replacement.fixtureHoldAfterResponse = true
    chat.callFunc("onDestroy")
    m.scene.removeChild(chat)
    settle(80)
    check(chat.callFunc("fixtureRead").task.isSameNode(replacement), "detached disposed owner retains exactly its draining worker")
    replacement.fixtureHoldAfterResponse = false
    waitRead(chat, "task", invalid, "detached owner disposal")
    check(not exists(replacement.request.path) and replacement.getParent() = invalid, "disposal removes partial and unobserves/detaches completed worker")
    chat.callFunc("fixtureStaleAsset", replacement)
    check(chat.callFunc("fixtureRead").task = invalid, "late disposed callback cannot start new work")

    chat = newChat()
    installEmotes(chat, 1)
    chat.callFunc("fixtureMessage", "E0", "unrecoverable", 50)
    task = pending(chat)
    complete(chat, task)
    path = task.request.path
    chat.callFunc("fixtureLockFile", path)
    chat.callFunc("onDestroy")
    waitRead(chat, "blocked", true, "unrecoverable disposal failure")
    state = chat.callFunc("fixtureRead")
    check(state.task = invalid and state.cacheCount = 1 and state.partials = 1 and exists(path), "unrecoverable cleanup preserves accounting and fails closed without orphan jobs")
    chat.callFunc("onDestroy")
    chat.callFunc("fixtureSync")
    settle(60)
    check(chat.callFunc("fixtureRead").task = invalid and chat.callFunc("fixtureRead").serial = 1, "permanent disposal failure has no infinite retry loop")
    newcomer = newChat()
    installEmotes(newcomer, 1)
    newcomer.callFunc("fixtureMessage", "E0", "blocked-owner", 50)
    settle(40)
    check(newcomer.callFunc("fixtureRead").serial = 0 and newcomer.callFunc("fixtureRead").task = invalid, "a failed disposed owner also blocks downloads in a new Chat instance")
    dispose(newcomer)
    check(m.global.chatAnimationStorageOwners.count() = 1, "another owner's disposal cannot clear the failed session ledger")
    chat.callFunc("fixtureLockFile", "")
    chat.callFunc("fixtureRetryCleanup")
    waitRead(chat, "task", invalid, "explicit fixture recovery of failed disposed owner")
    check(not exists(path) and m.global.chatAnimationStorageOwners.count() = 0, "only actual successful cleanup by the failed owner releases shared storage")
    m.scene.removeChild(chat)
end sub

sub testCacheLimits()
    chat = newChat()
    installEmotes(chat, 20)
    firstPath = ""
    for index = 0 to 17
        chat.callFunc("fixtureClear")
        chat.callFunc("fixtureMessage", "E" + index.toStr(), "cache" + index.toStr(), 50)
        task = pending(chat)
        state = chat.callFunc("fixtureRead")
        check(state.cacheCount + 1 <= 16 and state.cacheBytes + 1048576 <= 4194304, "entry/byte quotas leave room for an admitted asset " + index.toStr())
        complete(chat, task)
        state = chat.callFunc("fixtureRead")
        if index = 0 then firstPath = state.native.uri
        check(state.cacheCount <= 16 and state.cacheBytes <= 4194304 and exists(state.native.uri), "cache quota includes active file " + index.toStr())
    end for
    check(state.cacheCount = 16 and not exists(firstPath), "old unused entries are evicted through actual Task deletion")
    dispose(chat)
    check(chat.callFunc("fixtureRead").cacheBytes = 0, "disposal removes admitted cache files")
    chat = newChat()
    installEmotes(chat, 20)
    chat.callFunc("fixtureSource", "one-mib.webp")
    for index = 0 to 5
        chat.callFunc("fixtureClear")
        chat.callFunc("fixtureMessage", "E" + index.toStr(), "large" + index.toStr(), 50)
        task = pending(chat)
        check(chat.callFunc("fixtureRead").cacheBytes + 1048576 <= 4194304, "4 MiB cache leaves room for the next admitted asset")
        complete(chat, task)
        state = chat.callFunc("fixtureRead")
        check(state.cacheCount <= 4 and state.cacheBytes <= 4194304 and exists(state.native.uri), "4 MiB compressed cache protects active file")
    end for
    dispose(chat)
end sub

sub testStaleGeneration()
    chat = newChat()
    installEmotes(chat, 1)
    chat.callFunc("fixtureMessage", "E0", "stale", 50)
    task = pending(chat)
    task.fixtureHoldAfterResponse = true
    task.fixtureRelease = true
    waitResponse(task)
    check(task.response.info <> invalid, "stale generation fixture holds a fully admitted response")
    chat.visible = false
    chat.visible = true
    chat.callFunc("fixtureDelivered")
    check(chat.callFunc("fixtureRead").generation <> task.request.generation and chat.callFunc("fixtureRead").native = invalid, "new visible generation cannot adopt old Task's published file")
    task.fixtureHoldAfterResponse = false
    replacement = pending(chat, task)
    check(not exists(task.request.path) and chat.callFunc("fixtureRead").cacheCount = 0, "stale valid result is deleted before next generation downloads")
    replacement.fixtureDropResponse = true
    replacement.fixtureRelease = true
    waitRead(chat, "blocked", true, "missing cleanup acknowledgment")
    check(chat.callFunc("fixtureRead").partials = 1 and chat.callFunc("fixtureRead").task = invalid, "missing worker acknowledgment fails closed and retains file ownership")
    dispose(chat)
    check(not exists(replacement.request.path), "disposal cleans a stopped worker's unacknowledged file")
end sub

sub testVisibilityAndBounds()
    chat = newChat()
    installEmotes(chat, 20)
    row = chat.callFunc("fixtureMessage", "E0", "offscreen", -100)
    check(chat.callFunc("fixtureRead").serial = 0 and chat.callFunc("fixtureRead").probes = invalid, "offscreen images cause no probe or fetch")
    chat.callFunc("fixtureMove", row, 295)
    check(chat.callFunc("fixtureRead").task = invalid, "partially clipped image stays static")
    chat.callFunc("fixtureMove", row, 50)
    task = pending(chat)
    chat.callFunc("fixtureMove", row, -100, false)
    task.fixtureRelease = true
    waitRead(chat, "task", invalid, "offscreen admitted cleanup")
    check(chat.callFunc("fixtureRead").native = invalid and not exists(task.request.path), "admitted response rechecks visibility and deletes unused file in Task")
    chat.callFunc("fixtureClear")
    for index = 0 to 11
        chat.callFunc("fixtureMessage", "E" + index.toStr(), "queue" + index.toStr(), 10 + index * 20)
    end for
    task = pending(chat)
    check(chat.callFunc("fixtureRead").candidates = 8 and chat.callFunc("fixtureRead").serial = 2, "candidate queue is bounded to eight and only one fetch")
    chat.width = 260
    waitRead(chat, "task", invalid, "resize cancellation")
    check(task.stopRequested and not exists(task.request.path), "resize clears rows and Task-owned partial")
    comment = ircParseMessage("@id=actual;display-name=Viewer :viewer!viewer@host PRIVMSG #fixture :E0")
    comment.identity = { id: "actual", userId: "viewer", login: "viewer" }
    comment.moderationSeq = 0
    chat.callFunc("fixtureRead").chatJob.nextCommentObj = comment
    task = pending(chat)
    check(chat.callFunc("fixtureRead").panel.getChildCount() = 1, "actual IRC renderer hands off provider emote to actual asset Task")
    dispose(chat)
    check(not exists(task.request.path), "explicit disposal cleans final in-flight partial")
end sub

function newChat(support = "native" as string) as object
    chat = createObject("roSGNode", "Chat")
    chat.visible = false
    m.scene.appendChild(chat)
    chat.height = 300
    chat.channel = "fixture"
    chat.channel_id = "42"
    chat.callFunc("fixtureSupport", support)
    chat.visible = true
    chat.callFunc("fixtureDelivered")
    settle(20)
    return chat
end function

sub testProviderHandoff()
    chat = newChat()
    m.global.emoteCache = {}
    provider = chat.callFunc("fixtureStartProvider")
    waitField(provider, "completed", true)
    settle(40)
    state = chat.callFunc("fixtureRead")
    check(state.descriptors.count() = 2, "actual BTTV/7TV producer Task publishes descriptors to actual renderer observer")
    check(GetInterface(m.global.emoteCache.BTTV, "ifString") <> invalid and GetInterface(m.global.emoteCache.Seven, "ifString") <> invalid, "producer handoff preserves static word cache strings")
    for each word in ["BTTV", "Seven"]
        chat.callFunc("fixtureClear")
        row = chat.callFunc("fixtureMessage", word, word, 50)
        task = pending(chat)
        check(task.request.uri = state.descriptors[row.getChild(0).chatImageUri].uri, "provider URI identity survives renderer handoff for " + word)
        complete(chat, task)
    end for
    dispose(chat)
end sub

sub installEmotes(chat as object, count as integer)
    cache = {}
    descriptors = {}
    for index = 0 to count - 1
        uri = "https://cdn.example/" + index.toStr() + "/static.webp"
        cache["E" + index.toStr()] = uri
        descriptors[uri] = { uri: "https://cdn.example/" + index.toStr() + "/animated.webp" }
    end for
    if count = 20 then descriptors["https://cdn.example/19/static.webp"] = descriptors["https://cdn.example/0/static.webp"]
    m.global.emoteCache = cache
    chat.callFunc("fixtureRead").emoteJob.animatedEmotes = descriptors
    settle(20)
end sub

function pending(chat as object, previous = invalid as dynamic) as dynamic
    clock = createObject("roTimespan")
    while clock.totalMilliseconds() < 4000
        task = chat.callFunc("fixtureRead").task
        if task <> invalid
            different = true
            if previous <> invalid then different = not previous.isSameNode(task)
            if different and task.request.path <> "" and task.fixtureStarted then return task
        end if
        pump(20)
    end while
    state = chat.callFunc("fixtureRead")
    fail("timed out waiting for an actual downloading Task; " + FormatJson({ serial: state.serial, candidates: state.candidates, descriptors: state.descriptors.count(), top: state.contentTop, presentation: state.presentation, statusVisible: state.statusVisible }))
    stop
    return invalid
end function

sub complete(chat as object, task as object)
    task.fixtureRelease = true
    waitRead(chat, "task", invalid, "admitted asset")
end sub

sub dispose(chat as object)
    chat.callFunc("onDestroy")
    waitRead(chat, "task", invalid, "final cleanup Task")
    m.scene.removeChild(chat)
end sub

sub waitField(node as object, field as string, value as dynamic)
    clock = createObject("roTimespan")
    while clock.totalMilliseconds() < 4000
        if sameValue(node[field], value) then return
        pump(20)
    end while
    fail("timed out waiting for " + field)
end sub

sub waitResponse(task as object)
    clock = createObject("roTimespan")
    while clock.totalMilliseconds() < 4000
        if task.response <> invalid then return
        pump(20)
    end while
    fail("timed out waiting for Task response")
end sub

function exists(path as string) as boolean
    return createObject("roFileSystem").exists(path)
end function
