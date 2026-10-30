' Separate entry: never add these cases to the existing renderer/cache entries.
sub testPlayerDisposal()
    testPlayerCachedPurge()
    if m.failures > 0 then return
    testPlayerResponseBeforeExit()
    if m.failures > 0 then return
    testPlayerFailedDelete()
end sub

function playerDisposalChat() as object
    player = m.scene.callFunc("fixtureMount")
    chat = player.findNode("chat")
    chat.height = 300
    chat.channel = "fixture"
    chat.channel_id = "42"
    chat.callFunc("fixtureSupport", "native")
    chat.visible = true
    chat.callFunc("fixtureDelivered")
    installEmotes(chat, 1)
    return player
end function

' A missing completion fails normally; pending() in the older fixture uses stop.
function playerDisposalTask(chat as object, previous = invalid as dynamic, cleanup = false as boolean) as dynamic
    clock = createObject("roTimespan")
    while clock.totalMilliseconds() < 4000
        task = chat.callFunc("fixtureRead").task
        if task <> invalid
            different = true
            if previous <> invalid then different = not previous.isSameNode(task)
            if different
                if cleanup and task.request.path = "" then return task
                if not cleanup and task.request.path <> "" and task.fixtureStarted then return task
            end if
        end if
        pump(20)
    end while
    fail("enclosing Player: timed out waiting for tracked Task after terminal callback")
    return invalid
end function

function playerDisposalWaiter() as object
    chat = newChat()
    installEmotes(chat, 1)
    chat.callFunc("fixtureMessage", "E0", "waiting-player", 50)
    check(chat.callFunc("fixtureRead").task = invalid and chat.callFunc("fixtureRead").storageObserved, "enclosing Player: visible second Chat waits for original owner")
    return chat
end function

sub testPlayerCachedPurge()
    player = playerDisposalChat()
    chat = player.findNode("chat")
    chat.callFunc("fixtureMessage", "E0", "cached-parent", 50)
    worker = playerDisposalTask(chat)
    if worker = invalid then return
    path = worker.request.path
    complete(chat, worker)
    if m.failures > 0 then return
    check(chat.callFunc("fixtureRead").cacheCount = 1 and exists(path), "cached: original asset entered completed cache")
    chat.callFunc("fixtureHoldTasks", true)
    player.callFunc("requestBack")
    cleanup = playerDisposalTask(chat, worker, true)
    if cleanup = invalid then return
    waitResponse(cleanup)
    if m.failures > 0 then return
    check(player.getParent() = invalid and player.callFunc("fixtureReadPlayer").disposed, "cached: actual Hero Back removed Player")
    check(chat.getParent().isSameNode(player), "cached: Chat remains a child of detached Player")
    check(cleanup.state = "run" and cleanup.response.cleanupOk and not exists(path), "cached: detached purge acknowledged deletion but still running")
    check(m.global.chatAnimationStorageOwners.count() = 1, "cached: reservation retained through purge epilogue")
    if m.failures > 0 then return
    second = playerDisposalWaiter()
    if m.failures > 0 then return
    cleanup.fixtureHoldAfterResponse = false
    replacement = playerDisposalTask(second)
    if replacement = invalid then return
    check(cleanup.getParent() = invalid and chat.callFunc("fixtureRead").task = invalid, "cached: detached purge final callback completed")
    check(chat.callFunc("fixtureRead").cacheCount = 0 and chat.callFunc("fixtureRead").partials = 0, "cached: old cache and partial accounting cleared")
    check(replacement.request.path <> path and m.global.chatAnimationStorageOwners.count() = 1, "cached: visible second Chat automatically acquires its sole reservation")
    dispose(second)
    check(m.global.chatAnimationStorageOwners.count() = 0, "cached: final disposal leaves no reservation")
end sub

sub testPlayerResponseBeforeExit()
    player = playerDisposalChat()
    chat = player.findNode("chat")
    chat.callFunc("fixtureMessage", "E0", "response-before-exit", 50)
    worker = playerDisposalTask(chat)
    if worker = invalid then return
    path = worker.request.path
    worker.fixtureHoldAfterResponse = true
    worker.fixtureRelease = true
    waitResponse(worker)
    if m.failures > 0 then return
    check(worker.state = "run" and worker.response.info <> invalid and exists(path), "early-response: successful response precedes Task return and exit")
    chat.callFunc("fixtureHoldTasks", true)
    player.callFunc("requestBack")
    check(player.getParent() = invalid and player.callFunc("fixtureReadPlayer").disposed, "early-response: Hero removed Player before first final callback")
    check(m.global.chatAnimationStorageOwners.count() = 1 and exists(path), "early-response: pending file retains original reservation")
    second = playerDisposalWaiter()
    if m.failures > 0 then return
    worker.fixtureHoldAfterResponse = false
    cleanup = playerDisposalTask(chat, worker, true)
    if cleanup = invalid then return
    waitResponse(cleanup)
    if m.failures > 0 then return
    check(worker.getParent() = invalid and cleanup.getParent().isSameNode(chat), "early-response: detached owner final callback starts tracked purge Task")
    check(chat.getParent().getParent() = invalid, "early-response: newly started purge belongs to detached Player")
    check(cleanup.state = "run" and cleanup.response.cleanupOk and not exists(path), "early-response: Task started after detachment deletes original file")
    check(m.global.chatAnimationStorageOwners.count() = 1 and second.callFunc("fixtureRead").task = invalid, "early-response: second Chat remains blocked until purge thread ends")
    if m.failures > 0 then return
    cleanup.fixtureHoldAfterResponse = false
    replacement = playerDisposalTask(second)
    if replacement = invalid then return
    check(chat.callFunc("fixtureRead").task = invalid and cleanup.getParent() = invalid, "early-response: detached second final callback retires purge")
    check(replacement.request.path <> path and m.global.chatAnimationStorageOwners.count() = 1, "early-response: waiting Chat automatically acquires sole reservation")
    dispose(second)
    check(m.global.chatAnimationStorageOwners.count() = 0, "early-response: final disposal clears ledger")
end sub

sub testPlayerFailedDelete()
    player = playerDisposalChat()
    chat = player.findNode("chat")
    chat.callFunc("fixtureMessage", "E0", "failed-delete", 50)
    worker = playerDisposalTask(chat)
    if worker = invalid then return
    path = worker.request.path
    worker.fixtureLockedPath = path
    worker.fixtureHoldAfterResponse = true
    player.callFunc("requestBack")
    waitResponse(worker)
    if m.failures > 0 then return
    check(player.getParent() = invalid and player.callFunc("fixtureReadPlayer").disposed, "failure: actual Hero Back removed Player")
    check(worker.state = "run" and not worker.response.cleanupOk and exists(path), "failure: controlled delete failure retains file before Task return")
    check(m.global.chatAnimationStorageOwners.count() = 1, "failure: reservation retained while worker runs")
    second = playerDisposalWaiter()
    if m.failures > 0 then return
    worker.fixtureHoldAfterResponse = false
    waitRead(chat, "task", invalid, "failed deletion final callback")
    if m.failures > 0 then return
    check(worker.getParent() = invalid, "failure: detached callback destroyed and removed completed Task")
    check(chat.callFunc("fixtureRead").blocked and exists(path), "failure: detached callback deliberately recorded unsuccessful cleanup")
    check(m.global.chatAnimationStorageOwners.count() = 1, "failure: unacknowledged file retains reservation after Task completion")
    chat.callFunc("onDestroy")
    settle(40)
    check(second.callFunc("fixtureRead").task = invalid and second.callFunc("fixtureRead").storageObserved, "failure: idempotent disposal cannot bypass blocked owner")
    check(chat.callFunc("fixtureRead").task = invalid, "failure: no automatic unbounded cleanup retries")
    if m.failures > 0 then return
    ' Diagnostic-only same-owner retry, absent from the production interface.
    chat.callFunc("fixtureRetryCleanup")
    replacement = playerDisposalTask(second)
    if replacement = invalid then return
    check(not exists(path), "failure: same-owner diagnostic retry acknowledges deletion")
    check(not chat.callFunc("fixtureRead").blocked and chat.callFunc("fixtureRead").partials = 0, "failure: successful retry clears original blocked accounting")
    check(replacement.request.path <> path and m.global.chatAnimationStorageOwners.count() = 1, "failure: waiting Chat acquires only after successful retry completion")
    dispose(second)
    check(m.global.chatAnimationStorageOwners.count() = 0, "failure: final disposal leaves zero reservations")
end sub
