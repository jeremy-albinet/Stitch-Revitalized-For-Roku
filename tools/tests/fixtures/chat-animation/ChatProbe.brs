' Native creation and Task test controls are adapted by the harness. Lifecycle
' handlers and filesystem work are production code; no render-side file IO.
function fixtureNativeNode(nodeType as string) as dynamic
    if m.fixtureProbes = invalid then m.fixtureProbes = 0
    m.fixtureProbes++
    if m.fixtureSupport = "unsupported" then return invalid
    if m.fixtureSupport = "missing-fields" then return createObject("roSGNode", "Group")
    if m.fixtureSupport = "wrong-field-types"
        node = createObject("roSGNode", "Group")
        node.addFields({ uri: 1, mimeType: 1, control: 1, state: 1, width: 0, height: 0, loadWidth: 0, loadHeight: 0, mediaWidth: 0, mediaHeight: 0 })
        return node
    end if
    return createObject("roSGNode", "AnimatedImageBoundary")
end function

sub fixtureSupport(mode as string)
    m.fixtureSupport = mode
end sub

function fixtureStartProvider() as object
    stopEmoteJob()
    m.EmoteJob = createObject("roSGNode", "ProviderProbe")
    m.top.appendChild(m.EmoteJob)
    m.EmoteJob.channel = m.top.channel
    m.EmoteJob.channel_id = m.top.channel_id
    m.EmoteJob.observeField("animatedEmotes", "onAnimatedEmotes")
    m.EmoteJob.observeField("completed", "onEmotesCompleted")
    m.EmoteJob.functionName = "fixtureProviders"
    task = m.EmoteJob
    task.control = "run"
    return task
end function

function fixtureRead() as object
    if m.fixtureStorageCallbacks = invalid then m.fixtureStorageCallbacks = 0
    candidates = { items: [], seen: {}, ownerVisible: false }
    for each row in m.chatPanel.getChildren(-1, 0)
        collectChatAnimations(row, 0, 0, candidates)
    end for
    return {
        owner: m.animationOwner, native: m.animationNative, task: m.animationTask,
        serial: m.animationSerial, generation: m.animationGeneration,
        storageObserved: m.animationStorageObserved, workersCreated: m.fixtureWorkersCreated,
        storageCallbacks: m.fixtureStorageCallbacks,
        synchronousStorageEvents: m.fixtureSynchronousStorageEvents,
        cacheCount: m.animationCache.count(), cacheBytes: m.animationCacheBytes,
        failed: m.animationFailed.count(), supported: m.animationSupported,
        enabled: m.animateChatEmotes, descriptors: m.animatedEmotes,
        candidates: candidates.items.count(), probes: m.fixtureProbes, partials: m.animationPartials.count(),
        blocked: m.animationCleanupBlocked, request: m.animationRequest, panel: m.chatPanel, chatJob: m.chat, emoteJob: m.EmoteJob,
        contentTop: m.chatContentTop, presentation: m.chatPresentationState, statusVisible: m.chatStatus.visible
    }
end function

sub fixtureRecordStorageCallback()
    if m.fixtureStorageCallbacks = invalid then m.fixtureStorageCallbacks = 0
    m.fixtureStorageCallbacks++
end sub

sub fixtureLockFile(path as string)
    m.fixtureLockedPath = path
end sub

sub fixtureRetryCleanup()
    m.animationCleanupBlocked = false
    pumpChatAnimationCleanup()
end sub

function fixtureAssetTask() as object
    if m.fixtureWorkersCreated = invalid then m.fixtureWorkersCreated = 0
    m.fixtureWorkersCreated++
    task = createObject("roSGNode", "ChatAnimationAsset")
    if m.fixtureLockedPath <> invalid then task.fixtureLockedPath = m.fixtureLockedPath
    if m.fixtureSource <> invalid then task.fixtureSource = m.fixtureSource
    if m.fixtureHoldTasks <> invalid then task.fixtureHoldAfterResponse = m.fixtureHoldTasks
    return task
end function

sub fixtureSynchronousStorage(enable as boolean)
    m.fixtureSynchronousStorage = enable
end sub

sub fixturePublishStorageOwners(owners as object)
    m.global.setField("chatAnimationStorageOwners", owners)
    ' Deliver an own-acquisition/stale event synchronously before Task creation,
    ' even if already unobserved. A latch bounds a broken handler to two workers.
    if m.fixtureSynchronousStorage = true and owners.doesExist(m.animationSession) and m.fixtureDispatchingStorage <> true
        m.fixtureDispatchingStorage = true
        if m.fixtureSynchronousStorageEvents = invalid then m.fixtureSynchronousStorageEvents = 0
        m.fixtureSynchronousStorageEvents++
        onChatAnimationStorageOwners({ node: m.global, getRoSGNode: fixtureEventNode })
        m.fixtureDispatchingStorage = false
    end if
end sub

sub fixtureStaleStorage()
    onChatAnimationStorageOwners({ node: m.global, getRoSGNode: fixtureEventNode })
end sub

sub fixtureHoldTasks(hold as boolean)
    m.fixtureHoldTasks = hold
end sub

sub fixtureSource(source as string)
    m.fixtureSource = source
end sub

sub fixtureEvict(uri as string)
    removeChatAnimationCache(uri)
end sub

function fixtureMessage(text as string, id as string, y as float) as object
    row = buildMessage(text, m.left_bound)
    row.addFields({ chatIdentity: { id: id, userId: "viewer", login: "viewer" }, chatAdvance: row.localBoundingRect().height + m.line_gap })
    row.translation = [0, y]
    m.chatPanel.appendChild(row)
    ' This fixture bypasses renderComment; publish the same first-render status.
    fixtureDelivered()
    syncChatAnimation()
    return row
end function

sub fixtureDelivered()
    if m.chat <> invalid then m.chat.connectionState = "connected"
    m.hasRenderedComment = true
    updateChatStatus("connected")
end sub

sub fixtureMove(row as object, y as float, sync = true as boolean)
    row.translation = [0, y]
    if sync then syncChatAnimation()
end sub

sub fixtureSync()
    syncChatAnimation()
end sub

sub fixtureComplete(task as object)
    task.fixtureRelease = true
end sub

sub fixtureReject(task as object)
    task.fixtureMode = "reject"
    task.fixtureRelease = true
end sub

sub fixtureStaleAsset(task as object)
    onChatAnimationAsset({ node: task, getRoSGNode: fixtureEventNode })
end sub

sub fixtureStaleMetadata(task as object)
    onAnimatedEmotes({ node: task, data: { "https://cdn.example/late-static.webp": { uri: "https://cdn.example/late.webp" } }, getRoSGNode: fixtureEventNode, getData: fixtureEventData })
end sub

function fixtureEventNode() as object
    return m.node
end function

function fixtureEventData() as object
    return m.data
end function

sub fixtureRemove(id as string)
    removeModerated({ kind: "message", id: id, userId: "", login: "" })
end sub

sub fixtureClear()
    removeModerated({ kind: "room", id: "", userId: "", login: "" })
end sub
