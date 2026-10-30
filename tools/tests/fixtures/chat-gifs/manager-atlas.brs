sub runFixture()
    testAtlasBitmapSizes()
    if m.failures > 0 then return
    m.animateChatEmotes = true
    m.animationSupported = false
    getGlobalAA().elapsed = 0
    uri = "https://media4.giphy.com/media/joSNxeswxuc74Juo8X/giphy.gif?cid=095d7a5dzizsiwgabonagkmigggv8v1spfai91ac3x0dsiy0&ep=v1_gifs_trending&rid=giphy.gif&ct=g"
    m.animatedEmotes[uri] = { provider: "twitch-gif", uri: uri, format: "gif" }
    owner = fixtureWrapper(uri, 0)
    duplicate = fixtureWrapper(uri, 110)
    syncChatAnimation()
    check(m.animationOwner.isSameNode(owner) and m.animationRenderer = "gif-atlas", "GIF owns one visible slot without AnimatedImage capability")
    check(m.animationTask.request.uri = uri and m.animationTask.request.path.right(10) = "/emote.gif", "exact URL and separate local sentinel path")
    check(owner.getChild(0).visible and owner.getChild(0).getChild(0).text = "[GIF title]", "readable Group fallback during download")
    fixtureComplete(fixtureAtlasInfo())
    info = m.animationCache[uri].info
    native = m.animationNative
    check(native.uri.right(10) = "/atlas.png" and native.uri <> m.animationCache[uri].path, "Poster reads one PNG distinct from ownership sentinel")
    check(native.width = 384 and native.height = 384 and m.animationClip.clippingRect.width = 96, "exact atlas display dimensions and one-tile clipping")
    check(owner.getChild(0).visible and m.animationTimer = invalid, "title persists until Poster readiness")
    removeChatAnimationCache(uri)
    check(m.animationPartials.count() = 0 and m.animationCacheBytes = 60000, "loading atlas protected; storage counts actual retained atlas")
    native.bitmapWidth = 170.667
    native.bitmapHeight = 170.667
    native.loadStatus = "ready"
    timer = m.animationTimer
    check(not owner.getChild(0).visible and duplicate.getChild(0).visible and timer <> invalid, "design-scaled bitmap readiness hides only owner title and starts one timer")
    if timer = invalid then return
    check(timer.repeat = false and timer.duration >= 0.02, "one-shot timer is at least twenty milliseconds")
    native.loadStatus = "ready"
    syncChatAnimation()
    check(m.animationNative.isSameNode(native) and m.animationTimer.isSameNode(timer), "repeated ready and duplicate URI do not restart playback")
    getGlobalAA().elapsed = 145
    onChatAnimationAtlasTick(fixtureEvent(timer, invalid))
    check(native.translation[0] = -192 and native.translation[1] = 0 and timer.duration >= 0.02, "elapsed phase selects frame two without URI reload")
    getGlobalAA().elapsed = 2750
    onChatAnimationAtlasTick(fixtureEvent(timer, invalid))
    check(native.translation[0] = -288 and native.translation[1] = -192 and native.uri = info.renderPath, "late callback selects current cycle/frame directly")
    native.loadStatus = "failed"
    check(owner.getChild(0).visible and m.animationNative = invalid and m.animationTimer = invalid and timer.control = "stop", "failure restores title, removes Poster and stops timer")
    check(native.getParent() = invalid and m.animationFailed.doesExist(uri), "failed occurrence removed/suppressed")
    fixtureComplete(invalid)
    check(m.animationCache.count() = 0 and m.animationPartials.count() = 0 and m.global.chatAnimationStorageOwners.count() = 0, "stopped cleanup acknowledgment drains reservation")
    m.animationFailed = {}
    syncChatAnimation()
    fixtureComplete(fixtureAtlasInfo())
    previousNative = m.animationNative
    info = m.animationCache[uri].info
    previousNative.bitmapWidth = 256
    previousNative.bitmapHeight = 256
    previousNative.loadStatus = "ready"
    previousTimer = m.animationTimer
    serial = m.animationSerial
    m.top.visible = false
    syncChatAnimation()
    check(owner.getChild(0).visible and previousTimer.control = "stop" and m.animationTimer = invalid, "hide stops timer and restores text")
    m.top.visible = true
    syncChatAnimation()
    check(m.animationSerial = serial and m.animationTask = invalid and m.animationNative.uri = info.renderPath, "cache hit reuses atlas without reconversion")
    onChatAnimationAtlasStatus(fixtureEvent(previousNative, "ready"))
    onChatAnimationAtlasTick(fixtureEvent(previousTimer, invalid))
    check(owner.getChild(0).visible and m.animationTimer = invalid, "stale Poster/timer cannot activate replacement owner")
    m.animationNative.bitmapWidth = 1
    m.animationNative.bitmapHeight = 1
    m.animationNative.loadStatus = "ready"
    check(owner.getChild(0).visible and m.animationFailed.doesExist(uri), "wrong bitmap dimensions fail closed")
    fixtureComplete(invalid)
    testAtlasAspectRatio(uri)
    testPhases()
    testPeakProtection(uri)
    m.chatPanel.removeChildrenIndex(-1, 0)
    m.animationSupported = invalid
    staticUri = "https://cdn.betterttv.net/emote/example/static/1x.webp"
    m.animatedEmotes[staticUri] = { uri: "https://cdn.betterttv.net/emote/example/1x.webp" }
    owner = fixtureWrapper(staticUri, 0)
    syncChatAnimation()
    check(m.animationTask.request.path.right(11) = "/emote.webp", "provider retains WebP path")
    fixtureComplete({ bytes: 3842, loadWidth: 32, loadHeight: 32 })
    check(m.animationNative.mimeType = "video/webp" and m.animationRenderer = "webp", "WebP native MIME/renderer preserved")
    m.animationNative.state = "first"
    check(not owner.getChild(0).visible and m.animationTimer = invalid, "WebP keeps original readiness contract")
    m.animationNative.state = "error"
    fixtureComplete(invalid)
    check(owner.getChild(0).visible and m.global.chatAnimationStorageOwners.count() = 0, "WebP fallback/cleanup preserved")
    testTwoChats(uri)
    m.animateChatEmotes = true
    m.animationSupported = false
    for index = 0 to 129
        buildChatGif({ uri: "https://media4.giphy.com/media/fixture" + index.toStr() + "/giphy.gif", text: "[bounded title]" })
    end for
    check(m.gifAnimationKeys.count() = 128, "actual Chat GIF builder preserves descriptor bound without native capability")
    preserved = m.gifAnimationKeys[0]
    m.animationOwner = createObject("roSGNode", "Group")
    m.animationOwner.addFields({ chatImageUri: preserved })
    buildChatGif({ uri: "https://media4.giphy.com/media/newfixture/giphy.gif", text: "[new title]" })
    check(m.gifAnimationKeys.count() = 128 and m.animatedEmotes.doesExist(preserved), "descriptor eviction protects current GIF owner")
    mergeChatAnimations({ "provider": { uri: "https://cdn.example/emote.webp" } })
    check(m.animatedEmotes.doesExist(preserved) and m.animatedEmotes.doesExist("provider"), "early provider update retains Chat-owned GIF descriptors")
    m.animationOwner = invalid
    if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
end sub

sub testAtlasBitmapSizes()
    poster = createObject("roSGNode", "PosterBoundary")
    for each size in [[256, 256, true], [170.667, 170.667, true], [384, 384, true], [0, 0, false], [1, 1, false], [170, 170, false], [256, 128, false], [170.667, 256, false], [-256, -256, false]]
        poster.bitmapWidth = size[0]
        poster.bitmapHeight = size[1]
        check(chatAnimationAtlasBitmapSize(poster, { atlasWidth: 256, atlasHeight: 256 }) = size[2], "design-scaled bitmap readiness dimensions: " + size[0].toStr() + "/" + size[1].toStr())
    end for
    for each size in [[256, 128], [170.667, 85.3333], [384, 192]]
        poster.bitmapWidth = size[0]
        poster.bitmapHeight = size[1]
        check(chatAnimationAtlasBitmapSize(poster, { atlasWidth: 256, atlasHeight: 128 }), "non-square design-scaled bitmap readiness")
    end for
end sub

sub testAtlasAspectRatio(uri as string)
    starts = [0, 70, 130, 200, 270, 330, 400, 470, 530, 600, 670, 730, 800, 870, 930]
    cells = [[0, 0], [1, 0], [2, 0], [3, 0], [0, 1], [1, 1], [2, 1], [3, 1], [0, 2], [1, 2], [2, 2], [3, 2], [0, 3], [1, 3], [2, 3]]
    for each size in [[64, 32, 96, 48, 0, 24], [32, 64, 48, 96, 24, 0]]
        m.animationFailed = {}
        syncChatAnimation()
        info = fixtureAtlasInfo()
        info.width = size[0] * 2
        info.height = size[1] * 2
        info.loadWidth = size[0]
        info.loadHeight = size[1]
        info.atlasWidth = size[0] * 4
        info.atlasHeight = size[1] * 4
        fixtureComplete(info)
        native = m.animationNative
        clip = m.animationClip
        owner = m.animationOwner
        fallback = owner.getChild(0)
        path = native.uri
        label = size[0].toStr() + "x" + size[1].toStr()
        check(native.width = size[2] * 4 and native.height = size[3] * 4, "aspect-preserving Poster cells: " + label)
        check(clip.clippingRect.width = size[2] and clip.clippingRect.height = size[3], "clipping matches displayed cell: " + label)
        check(clip.translation[0] = size[4] and clip.translation[1] = size[5], "cell centered inside reserved slot: " + label)
        check(fallback.visible and fallback.width = 96 and fallback.height = 96, "fixed title/row slot retained before ready: " + label)
        getGlobalAA().elapsed = 0
        native.bitmapWidth = info.atlasWidth
        native.bitmapHeight = info.atlasHeight
        native.loadStatus = "ready"
        timer = m.animationTimer
        for index = 0 to 14
            getGlobalAA().elapsed = starts[index]
            onChatAnimationAtlasTick(fixtureEvent(timer, invalid))
            check(native.translation[0] = -cells[index][0] * size[2] and native.translation[1] = -cells[index][1] * size[3], "full movie cell position " + label + ":" + index.toStr())
            check(timer.duration = (info.frameEnds[index] - starts[index]) / 1000.0, "full movie timing " + label + ":" + index.toStr())
        end for
        getGlobalAA().elapsed = 990
        onChatAnimationAtlasTick(fixtureEvent(timer, invalid))
        check(native.translation[0] = 0 and native.translation[1] = 0 and timer.duration = 0.07, "990ms movie loop seam: " + label)
        getGlobalAA().elapsed = 2750
        onChatAnimationAtlasTick(fixtureEvent(timer, invalid))
        check(native.translation[0] = -3 * size[2] and native.translation[1] = -2 * size[3] and timer.duration = 0.03, "late phase keeps aspect and timing: " + label)
        check(native.uri = path and m.animationNative.isSameNode(native) and m.animationTimer.isSameNode(timer), "one Poster load and one timer for whole movie: " + label)
        check(fallback.width = 96 and fallback.height = 96 and owner.translation[0] = 0 and m.chatPanel.getChild(1).translation[0] = 110, "movie leaves reserved slot and adjacent row placement unchanged: " + label)
        check(info.loadWidth = size[0] and info.loadHeight = size[1] and info.durationMs = 990 and m.animationCacheBytes = 60000, "display geometry leaves asset metadata/storage unchanged: " + label)
        native.loadStatus = "failed"
        fixtureComplete(invalid)
        check(fallback.visible and m.animationTimer = invalid and m.animationCacheBytes = 0, "aspect movie restores title and releases renderer: " + label)
    end for
end sub

sub testPhases()
    info = { frames: 3, durationMs: 120, frameEnds: [20, 60, 120], loopCount: -1 }
    for each spec in [[-1, 0, false, 20], [0, 0, false, 20], [19, 0, false, 20], [20, 1, false, 40], [59, 1, false, 20], [60, 2, false, 60], [120, 2, true, 20], [900, 2, true, 20]]
        phase = chatAnimationAtlasPhase(info, spec[0])
        check(phase.index = spec[1] and phase.done = spec[2] and phase.waitMs = spec[3], "absent-loop elapsed boundary " + spec[0].toStr())
    end for
    info.loopCount = 2
    check(not chatAnimationAtlasPhase(info, 359).done and chatAnimationAtlasPhase(info, 360).done, "finite extension repeats exactly n additional cycles")
    info.loopCount = 0
    check(chatAnimationAtlasPhase(info, 120).index = 0 and not chatAnimationAtlasPhase(info, 120000).done, "infinite seam and late phase")
end sub

sub testPeakProtection(uri as string)
    m.animationFailed = {}
    syncChatAnimation()
    fixtureComplete(fixtureAtlasInfo())
    asset = m.animationCache[uri]
    m.animationCache["old"] = { path: "tmp:/stitch-emote-old/emote.webp", info: { bytes: 4194304 - 60000 } }
    m.animationCacheOrder.push("old")
    m.animationCacheBytes = 4194304
    check(not trimChatAnimationCache(3145728), "GIF 3 MiB peak reserved before next download")
    check(not m.animationPartials.doesExist(asset.path) and m.animationPartials.doesExist("tmp:/stitch-emote-old/emote.webp"), "loading atlas protected while an unowned file is evicted")
    check(m.animationCacheBytes = 4194304, "queued eviction releases no bytes before acknowledgment")
    forgetChatAnimationFile("tmp:/stitch-emote-old/emote.webp")
    check(trimChatAnimationCache(3145728) and m.animationCacheBytes + 3145728 <= 4194304, "acknowledged eviction makes conversion headroom")
    m.animationNative.loadStatus = "failed"
    fixtureComplete(invalid)
end sub

sub testTwoChats(uri as string)
    m.chatPanel.removeChildrenIndex(-1, 0)
    m.animationFailed = {}
    fixtureWrapper(uri, 0)
    syncChatAnimation()
    contender = createObject("roSGNode", "GifChatBoundary")
    m.top.appendChild(contender)
    contender.callFunc("configureContender", uri)
    probe = contender.callFunc("probe")
    check(probe.task = invalid and probe.owner = invalid and probe.waiting, "second GIF Chat cannot acquire worker/visible owner")
    fixtureComplete(fixtureAtlasInfo())
    stopChatAnimations(true)
    check(m.animationTask <> invalid, "purge keeps one cleanup worker while second waits")
    task = m.animationTask
    request = task.request
    task.response = { generation: request.generation, uri: request.uri, path: request.path, info: invalid, removed: [], cleanupOk: false }
    task.state = "done"
    probe = contender.callFunc("probe")
    check(m.animationCleanupBlocked and m.global.chatAnimationStorageOwners.count() = 1 and probe.task = invalid, "failed deletion retains ledger across Chats")
    m.animationCleanupBlocked = false
    pumpChatAnimationCleanup()
    fixtureComplete(invalid)
    probe = contender.callFunc("probe")
    check(probe.task <> invalid and probe.owner <> invalid and m.global.chatAnimationStorageOwners.count() = 1, "acknowledged cleanup wakes one waiting GIF owner")
    contender.callFunc("disposeContender")
    probe = contender.callFunc("probe")
    check(probe.task = invalid and probe.owner = invalid and not probe.waiting and m.global.chatAnimationStorageOwners.count() = 0, "dispose drains worker, observers and global ledger")
    m.top.removeChild(contender)
end sub

sub configureContender(uri as string)
    m.animateChatEmotes = true
    m.animationSupported = false
    m.animatedEmotes[uri] = { provider: "twitch-gif", uri: uri, format: "gif" }
    fixtureWrapper(uri, 0)
    syncChatAnimation()
end sub
function probe() as object
    return { task: m.animationTask, owner: m.animationOwner, waiting: m.animationStorageObserved }
end function
sub disposeContender()
    m.disposed = true
    stopChatAnimations(true)
    if m.animationTask <> invalid then fixtureComplete(invalid)
    if m.animationTask <> invalid then fixtureComplete(invalid)
end sub
function fixtureAtlasInfo() as object
    return { format: "gif", renderer: "gif-atlas", bytes: 60000, sourceBytes: 998959, width: 480, height: 480, loadWidth: 64, loadHeight: 64, frames: 15, durationMs: 990, loopCount: 0, frameEnds: [70, 130, 200, 270, 330, 400, 470, 530, 600, 670, 730, 800, 870, 930, 990], columns: 4, atlasWidth: 256, atlasHeight: 256 }
end function
function fixtureEvent(node as object, data as dynamic) as object
    return { node: node, data: data, getRoSGNode: fixtureEventNode, getData: fixtureEventData }
end function
function fixtureEventNode() as object
    return m.node
end function
function fixtureEventData() as dynamic
    return m.data
end function
function fixtureElapsedClock() as object
    return { totalMilliseconds: fixtureMilliseconds }
end function
function fixtureMilliseconds() as integer
    return getGlobalAA().elapsed
end function
