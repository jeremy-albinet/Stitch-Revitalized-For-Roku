sub initChatAnimations()
    m.animatedEmotes = {}
    m.animateChatEmotes = false
    m.animationSupported = invalid
    m.animationOwner = invalid
    m.animationNative = invalid
    m.animationRenderer = ""
    m.animationClip = invalid
    m.animationCell = invalid
    m.animationTimer = invalid
    m.animationAsset = invalid
    m.animationClock = invalid
    m.animationTask = invalid
    m.animationRequest = invalid
    m.animationGeneration = 0
    m.animationSerial = 0
    m.animationSession = ""
    m.animationCache = {}
    m.animationCacheOrder = []
    m.animationCacheBytes = 0
    m.animationFailed = {}
    m.animationPartials = {}
    m.animationCleanupBlocked = false
    m.animationStorageObserved = false
end sub

sub openChatAnimations()
    m.animateChatEmotes = get_user_setting("chat.animatedEmotes", "true") = "true"
    ' A reopen permits one cleanup retry, never a retry on every chat message.
    m.animationCleanupBlocked = false
    syncChatAnimation()
end sub

' Capability is probed lazily; the manifest remains compatible with OS 15.1.
function createChatAnimatedImage() as dynamic
    if m.animationSupported = false then return invalid
    node = invalid
    try
        nodeType = "AnimatedImage"
        node = createObject("roSGNode", nodeType)
        if node <> invalid
            for each field in ["uri", "mimeType", "control", "state", "width", "height", "loadWidth", "loadHeight", "mediaWidth", "mediaHeight"]
                if not node.hasField(field)
                    node = invalid
                    exit for
                end if
            end for
        end if
        if node <> invalid
            for each field in ["uri", "mimeType", "control", "state"]
                if GetInterface(node[field], "ifString") = invalid then node = invalid
                if node = invalid then exit for
            end for
        end if
        if node <> invalid
            for each field in ["width", "height", "loadWidth", "loadHeight", "mediaWidth", "mediaHeight"]
                value = node[field]
                if GetInterface(value, "ifInt") = invalid and GetInterface(value, "ifFloat") = invalid and GetInterface(value, "ifDouble") = invalid
                    node = invalid
                    exit for
                end if
            end for
        end if
    catch e
        node = invalid
    end try
    m.animationSupported = node <> invalid
    return node
end function

' Coordinates are accumulated relative to the masked chat panel. A partially
' clipped emote stays static. Header overlays also count as out of view.
sub collectChatAnimations(node as object, x as float, y as float, candidates as object)
    if not node.visible then return
    x += node.translation[0]
    y += node.translation[1]
    if node.hasField("chatImageUri")
        poster = node.getChild(0)
        top = 0
        if m.hypePanel.visible then top += 76
        if m.pinPanel.visible then top += 176
        if m.chatContentTop <> invalid then top = m.chatContentTop
        if x < 0 or y < top or x + poster.width > m.chatPanel.width or y + poster.height > m.chatPanel.height then return
        uri = node.chatImageUri
        if m.animationOwner <> invalid
            if node.isSameNode(m.animationOwner) then candidates.ownerVisible = true
        end if
        descriptor = m.animatedEmotes[uri]
        if descriptor = invalid then return
        if descriptor.format <> "gif" and m.animationSupported = false then return
        if m.animationFailed.doesExist(descriptor.uri) then return
        if not candidates.seen.doesExist(descriptor.uri) and candidates.items.count() < 8
            candidates.seen[descriptor.uri] = true
            candidates.items.push(node)
        end if
        return
    end if
    for each child in node.getChildren(-1, 0)
        collectChatAnimations(child, x, y, candidates)
    end for
end sub

sub syncChatAnimation()
    if m.disposed or not m.top.visible or not m.animateChatEmotes
        setChatAnimationStorageWaiting(false)
        releaseChatAnimation()
        pumpChatAnimationCleanup()
        return
    end if
    if chatAnimationStorageBlocked()
        setChatAnimationStorageWaiting(true)
        releaseChatAnimation()
        pumpChatAnimationCleanup()
        return
    end if
    setChatAnimationStorageWaiting(false)
    candidates = { items: [], seen: {}, ownerVisible: false }
    for each row in m.chatPanel.getChildren(-1, 0)
        collectChatAnimations(row, 0, 0, candidates)
    end for
    ' Keep this occurrence until it leaves view, even as new emotes arrive.
    if candidates.ownerVisible
        ensureChatAnimationAsset()
        return
    end if
    releaseChatAnimation()
    pumpChatAnimationCleanup()
    if m.animationTask <> invalid or m.animationCleanupBlocked then return
    for each owner in candidates.items
        descriptor = m.animatedEmotes[owner.chatImageUri]
        isGif = descriptor.format = "gif" or ircGifUri(descriptor.uri) <> invalid
        native = invalid
        if isGif
            native = createObject("roSGNode", "Poster")
        else
            native = createChatAnimatedImage()
        end if
        if native = invalid then continue for
        m.animationOwner = owner
        m.animationNative = native
        if isGif
            m.animationRenderer = "gif-atlas"
            m.animationClip = createObject("roSGNode", "Group")
            owner.appendChild(m.animationClip)
            m.animationClip.appendChild(native)
            native.observeField("loadStatus", "onChatAnimationAtlasStatus")
        else
            m.animationRenderer = "webp"
            owner.appendChild(native)
            native.observeField("state", "onChatAnimationState")
        end if
        ensureChatAnimationAsset()
        return
    end for
end sub

sub ensureChatAnimationAsset()
    if m.animationTask <> invalid or m.animationCleanupBlocked or m.animationOwner = invalid then return
    if m.animationNative.uri <> "" then return
    descriptor = m.animatedEmotes[m.animationOwner.chatImageUri]
    if descriptor = invalid then return
    cached = m.animationCache[descriptor.uri]
    if cached <> invalid and not m.animationPartials.doesExist(cached.path)
        playChatAnimation(cached)
        return
    end if
    ' Leave room for one admitted asset: at most 16 entries / 4 MiB cached.
    ' HEAD and polling mitigate transfer overshoot, but cannot cap native writes.
    peakBytes = 1048576
    if descriptor.format = "gif" or ircGifUri(descriptor.uri) <> invalid then peakBytes = 3145728
    if not trimChatAnimationCache(peakBytes)
        pumpChatAnimationCleanup()
        return
    end if
    if m.animationSession = "" then m.animationSession = createObject("roDeviceInfo").getRandomUUID()
    m.animationSerial++
    directory = "tmp:/stitch-emote-" + m.animationSession + "-" + m.animationSerial.toStr()
    extension = ".webp"
    if descriptor.format = "gif" or ircGifUri(descriptor.uri) <> invalid then extension = ".gif"
    startChatAnimationTask({ uri: descriptor.uri, path: directory + "/emote" + extension, generation: m.animationGeneration, paths: [] })
end sub

' Only visible blocked instances observe the ledger. Scoped cleanup preserves
' other Chats' observers; clear the latch before sync because callbacks recurse.
sub setChatAnimationStorageWaiting(waiting as boolean)
    if waiting = m.animationStorageObserved then return
    m.animationStorageObserved = waiting
    if waiting
        m.global.observeFieldScoped("chatAnimationStorageOwners", "onChatAnimationStorageOwners")
    else
        m.global.unobserveFieldScoped("chatAnimationStorageOwners")
    end if
end sub

sub onChatAnimationStorageOwners(event as object)
    if not m.animationStorageObserved then return
    if m.disposed or not m.top.visible or not m.animateChatEmotes
        setChatAnimationStorageWaiting(false)
        return
    end if
    if chatAnimationStorageBlocked() then return
    setChatAnimationStorageWaiting(false)
    syncChatAnimation()
end sub

sub startChatAnimationTask(request as object)
    if m.animationTask <> invalid then return
    if not reserveChatAnimationStorage() then return
    m.animationRequest = request
    m.animationTask = createObject("roSGNode", "ChatAnimationAsset")
    m.top.appendChild(m.animationTask)
    m.animationTask.request = request
    ' Observe actual thread completion, not an early response/cleanup claim.
    m.animationTask.observeField("state", "onChatAnimationAsset")
    m.animationTask.control = "run"
end sub

sub pumpChatAnimationCleanup()
    if m.animationTask <> invalid or m.animationCleanupBlocked or m.animationPartials.count() = 0 then return
    startChatAnimationTask({ uri: "", path: "", generation: m.animationGeneration, paths: m.animationPartials.keys() })
end sub

sub playChatAnimation(asset as object)
    native = m.animationNative
    if native = invalid or m.animationOwner = invalid then return
    poster = m.animationOwner.getChild(0)
    try
        if m.animationRenderer = "gif-atlas"
            if not chatAnimationAtlasAsset(asset) then throw "Invalid GIF atlas"
            m.animationAsset = asset
            displayScale = poster.width / asset.info.loadWidth
            if asset.info.loadHeight * displayScale > poster.height then displayScale = poster.height / asset.info.loadHeight
            cell = { width: asset.info.loadWidth * displayScale, height: asset.info.loadHeight * displayScale }
            m.animationCell = cell
            m.animationClip.translation = [(poster.width - cell.width) / 2, (poster.height - cell.height) / 2]
            m.animationClip.clippingRect = [0, 0, cell.width, cell.height]
            native.width = cell.width * asset.info.columns
            native.height = cell.height * int(asset.info.atlasHeight / asset.info.loadHeight)
            native.loadDisplayMode = "noScale"
            native.uri = asset.info.renderPath
            return
        end if
        native.width = poster.width
        native.height = poster.height
        native.loadWidth = asset.info.loadWidth
        native.loadHeight = asset.info.loadHeight
        native.mimeType = ""
        if asset.path.right(5) = ".webp" then native.mimeType = "video/webp"
        native.uri = asset.path
        if m.animationNative <> invalid
            if native.isSameNode(m.animationNative) then native.control = "loop"
        end if
    catch e
        failChatAnimation()
    end try
end sub

' No filesystem access here. The Task admitted exact local bytes and dimensions.
function chatAnimationAtlasAsset(asset as object) as boolean
    info = asset.info
    if info.renderer <> "gif-atlas" then return false
    if info.renderPath <> asset.path.left(asset.path.len() - 9) + "atlas.png" then return false
    if info.frames < 2 or info.frames > 32 or info.frameEnds.count() <> info.frames then return false
    if info.loadWidth < 1 or info.loadWidth > 64 or info.loadHeight < 1 or info.loadHeight > 64 then return false
    if info.columns <> 4 and info.columns <> 8 then return false
    if info.atlasWidth <> info.columns * info.loadWidth then return false
    if info.atlasHeight <> int((info.frames + info.columns - 1) / info.columns) * info.loadHeight then return false
    if info.atlasWidth * info.atlasHeight > 131072 or info.bytes < 57 or info.bytes > 525312 then return false
    previous = 0
    for each ending in info.frameEnds
        if ending - previous < 20 then return false
        previous = ending
    end for
    return previous = info.durationMs and previous >= 100 and previous <= 20000 and info.loopCount >= -1 and info.loopCount <= 65535
end function

sub onChatAnimationAtlasStatus(event as object)
    if m.disposed or m.animationNative = invalid or m.animationOwner = invalid or m.animationAsset = invalid then return
    if not event.getRoSGNode().isSameNode(m.animationNative) then return
    if m.animationRenderer <> "gif-atlas" or m.animationNative.uri <> m.animationAsset.info.renderPath then return
    status = event.getData()
    if status = "ready"
        if m.animationClock <> invalid then return
        info = m.animationAsset.info
        if not chatAnimationAtlasBitmapSize(m.animationNative, info)
            failChatAnimation()
            syncChatAnimation()
            return
        end if
        m.animationClock = createObject("roTimespan")
        m.animationTimer = createObject("roSGNode", "Timer")
        m.animationTimer.repeat = false
        m.animationClip.appendChild(m.animationTimer)
        m.animationTimer.observeField("fire", "onChatAnimationAtlasTick")
        m.animationOwner.getChild(0).visible = false
        advanceChatAnimationAtlas()
    else if status = "failed"
        failChatAnimation()
        syncChatAnimation()
    end if
end sub

function chatAnimationAtlasBitmapSize(poster as object, info as object) as boolean
    ' Poster reports design-space dimensions when HD/FHD autoscaling is active.
    ' The Task validates the original PNG dimensions and bytes before publication.
    for each scale in [1.0, 2.0 / 3.0, 1.5]
        if abs(poster.bitmapWidth - info.atlasWidth * scale) < 0.01 and abs(poster.bitmapHeight - info.atlasHeight * scale) < 0.01 then return true
    end for
    return false
end function

sub onChatAnimationAtlasTick(event as object)
    if m.disposed or m.animationTimer = invalid or m.animationOwner = invalid or not m.top.visible then return
    if not event.getRoSGNode().isSameNode(m.animationTimer) then return
    advanceChatAnimationAtlas()
end sub

sub advanceChatAnimationAtlas()
    if m.animationClock = invalid or m.animationAsset = invalid then return
    info = m.animationAsset.info
    phase = chatAnimationAtlasPhase(info, m.animationClock.totalMilliseconds())
    cell = m.animationCell
    m.animationNative.translation = [- (phase.index mod info.columns) * cell.width, -int(phase.index / info.columns) * cell.height]
    m.animationTimer.control = "stop"
    if not phase.done
        m.animationTimer.duration = phase.waitMs / 1000.0
        m.animationTimer.control = "start"
    end if
end sub

' NETSCAPE 0 = infinite, positive = repeat count; absent (-1) plays once.
' Late callbacks choose elapsed phase directly, never replay missed ticks.
function chatAnimationAtlasPhase(info as object, elapsed as integer) as object
    if elapsed < 0 then elapsed = 0
    cycles = 1
    if info.loopCount > 0 then cycles = info.loopCount + 1
    if info.loopCount <> 0 and elapsed >= info.durationMs * cycles then return { index: info.frames - 1, done: true, waitMs: 20 }
    position = elapsed mod info.durationMs
    for index = 0 to info.frames - 1
        if position < info.frameEnds[index]
            waitMs = info.frameEnds[index] - position
            if waitMs < 20 then waitMs = 20
            return { index: index, done: false, waitMs: waitMs }
        end if
    end for
    return { index: info.frames - 1, done: true, waitMs: 20 }
end function

sub onChatAnimationAsset(event as object)
    if m.animationTask = invalid or m.animationRequest = invalid then return
    if not event.getRoSGNode().isSameNode(m.animationTask) then return
    state = m.animationTask.state
    if state <> "stop" and state <> "done" then return
    response = m.animationTask.response
    request = m.animationRequest
    task = m.animationTask
    m.animationTask = destroyTask(task, "state")
    m.top.removeChild(task)
    m.animationRequest = invalid
    if request.path <> "" then m.animationPartials[request.path] = true
    if response = invalid
        setChatAnimationCleanupBlocked(true)
        releaseChatAnimation()
        return
    end if
    if response.generation <> request.generation or response.path <> request.path or response.uri <> request.uri
        setChatAnimationCleanupBlocked(true)
        releaseChatAnimation()
        return
    end if
    for each path in response.removed
        forgetChatAnimationFile(path)
    end for
    setChatAnimationCleanupBlocked(not response.cleanupOk)
    if request.path = ""
        syncChatAnimation()
        return
    end if
    ' Layout may have changed while the file was downloaded.
    candidates = { items: [], seen: {}, ownerVisible: false }
    for each row in m.chatPanel.getChildren(-1, 0)
        collectChatAnimations(row, 0, 0, candidates)
    end for
    current = not m.disposed and m.top.visible and m.animateChatEmotes and candidates.ownerVisible and response.generation = m.animationGeneration
    if current and response.info <> invalid and response.cleanupOk
        uri = response.uri
        m.animationCache[uri] = response
        m.animationCacheOrder.push(uri)
        m.animationCacheBytes += response.info.bytes
        m.animationPartials.delete(response.path)
        playChatAnimation(response)
    else if current
        failChatAnimation()
    end if
    syncChatAnimation()
end sub

' One Chat reserves the entire bounded cache, including its active/pending files
' and draining worker. Other instances stay static until that owner cleans up.
function chatAnimationStorageBlocked() as boolean
    if not m.global.hasField("chatAnimationStorageOwners") then return false
    owners = m.global.chatAnimationStorageOwners
    return owners.count() > 1 or (owners.count() = 1 and not owners.doesExist(m.animationSession))
end function

function reserveChatAnimationStorage() as boolean
    if chatAnimationStorageBlocked() then return false
    if m.animationSession = "" then m.animationSession = createObject("roDeviceInfo").getRandomUUID()
    owners = {}
    if m.global.hasField("chatAnimationStorageOwners") then owners = m.global.chatAnimationStorageOwners
    owners[m.animationSession] = true
    ' Render handlers serialize admission; reserve before creating/running a Task.
    if m.global.hasField("chatAnimationStorageOwners")
        m.global.setField("chatAnimationStorageOwners", owners)
    else
        m.global.addFields({ chatAnimationStorageOwners: owners })
    end if
    return true
end function

sub setChatAnimationCleanupBlocked(blocked as boolean)
    m.animationCleanupBlocked = blocked
    ' Only a validated acknowledgment after thread completion may release storage.
    ' Retained caches, partials and failed cleanup all keep the shared reservation.
    if blocked or m.animationTask <> invalid or m.animationPartials.count() > 0 or m.animationCache.count() > 0 then return
    if not m.global.hasField("chatAnimationStorageOwners") then return
    owners = m.global.chatAnimationStorageOwners
    owners.delete(m.animationSession)
    m.global.setField("chatAnimationStorageOwners", owners)
end sub

sub onChatAnimationState(event as object)
    if m.disposed or m.animationNative = invalid or m.animationOwner = invalid then return
    if not event.getRoSGNode().isSameNode(m.animationNative) then return
    state = event.getData()
    if state = "first" or state = "decode"
        ' Transparent animated frames must not be composited over the still.
        m.animationOwner.getChild(0).visible = false
    else if state = "error" or state = "stop"
        failChatAnimation()
        syncChatAnimation()
    end if
end sub

sub failChatAnimation()
    if m.animationOwner <> invalid
        descriptor = m.animatedEmotes[m.animationOwner.chatImageUri]
        if GetInterface(descriptor, "ifAssociativeArray") = invalid
            releaseChatAnimation()
            return
        end if
        uri = descriptor.uri
        if GetInterface(uri, "ifString") = invalid or uri = ""
            releaseChatAnimation()
            return
        end if
        if m.animationFailed.count() >= 256 then m.animationFailed = {}
        m.animationFailed[uri] = true
        releaseChatAnimation()
        removeChatAnimationCache(uri)
    end if
end sub

sub releaseChatAnimation()
    m.animationGeneration++
    timer = m.animationTimer
    m.animationTimer = invalid
    if timer <> invalid
        timer.control = "stop"
        timer.unobserveField("fire")
    end if
    m.animationClock = invalid
    m.animationAsset = invalid
    native = m.animationNative
    m.animationNative = invalid
    if native <> invalid
        if m.animationRenderer = "gif-atlas"
            native.unobserveField("loadStatus")
        else
            native.unobserveField("state")
            native.control = "pause"
        end if
        native.uri = ""
        parent = native.getParent()
        if parent <> invalid then parent.removeChild(native)
    end if
    if m.animationClip <> invalid
        parent = m.animationClip.getParent()
        if parent <> invalid then parent.removeChild(m.animationClip)
    end if
    m.animationClip = invalid
    m.animationCell = invalid
    m.animationRenderer = ""
    if m.animationOwner <> invalid then m.animationOwner.getChild(0).visible = true
    m.animationOwner = invalid
    ' Keep the single worker and its state observer until it actually returns.
    ' It cancels the producer before deleting; no second worker can race it.
    if m.animationRequest <> invalid
        if m.animationRequest.path <> "" then m.animationTask.stopRequested = true
    end if
end sub

function removeChatAnimationCache(uri as string) as boolean
    asset = m.animationCache[uri]
    if asset = invalid then return true
    ' A playing file cannot be queued for eviction.
    if m.animationNative <> invalid
        if m.animationNative.uri = asset.path then return false
        if asset.info.renderPath <> invalid
            if m.animationNative.uri = asset.info.renderPath then return false
        end if
    end if
    m.animationPartials[asset.path] = true
    return false
end function

sub forgetChatAnimationFile(path as string)
    m.animationPartials.delete(path)
    for each uri in m.animationCache.keys()
        asset = m.animationCache[uri]
        if asset.path = path
            m.animationCacheBytes -= asset.info.bytes
            m.animationCache.delete(uri)
            for index = m.animationCacheOrder.count() - 1 to 0 step -1
                if m.animationCacheOrder[index] = uri then m.animationCacheOrder.delete(index)
            end for
        end if
    end for
end sub

function trimChatAnimationCache(peakBytes = 1048576 as integer) as boolean
    ' GIF reserves 3 MiB BEFORE download: input + wrapper + bounded PNG coexist.
    if m.animationCacheOrder.count() >= 16 or m.animationCacheBytes + peakBytes > 4194304
        for each uri in m.animationCacheOrder
            removeChatAnimationCache(uri)
            if m.animationPartials.count() > 0 then exit for
        end for
        ' Retained bytes are released only by the stopped Task's deletion ack.
        return false
    end if
    return m.animationPartials.count() = 0
end function

sub stopChatAnimations(purge = false as boolean)
    setChatAnimationStorageWaiting(false)
    releaseChatAnimation()
    if purge or m.disposed
        for each uri in m.animationCache.keys()
            removeChatAnimationCache(uri)
        end for
        ' One bounded final attempt is allowed after an earlier failed cleanup.
        m.animationCleanupBlocked = false
    end if
    m.animationFailed = {}
    m.animateChatEmotes = false
    ' This tracked child may outlive the detached Chat only until completion.
    ' Its final state callback destroys the Task, including during disposal.
    pumpChatAnimationCleanup()
end sub

sub onAnimatedEmotes(event as object)
    if m.disposed or not m.top.visible or m.EmoteJob = invalid then return
    if not event.getRoSGNode().isSameNode(m.EmoteJob) then return
    if m.EmoteJob.channel <> m.top.channel or m.EmoteJob.channel_id <> m.top.channel_id then return
    descriptors = event.getData()
    mergeChatAnimations(descriptors)
    refreshPinnedEmotes()
    syncChatAnimation()
end sub

' GIF occurrences belong to Chat, never to a provider Task's older snapshot.
function chatProviderAnimations() as object
    descriptors = {}
    for each uri in m.animatedEmotes
        descriptor = m.animatedEmotes[uri]
        if isChatProviderAnimation(uri, descriptor) then descriptors[uri] = descriptor
    end for
    return descriptors
end function

function isChatProviderAnimation(uri as string, descriptor as dynamic) as boolean
    if GetInterface(descriptor, "ifAssociativeArray") = invalid then return false
    if descriptor.provider = "twitch-gif" or descriptor.format = "gif" then return false
    return ircGifUri(uri) = invalid
end function

sub mergeChatAnimations(descriptors as dynamic)
    if GetInterface(descriptors, "ifAssociativeArray") = invalid then return
    for each uri in descriptors
        descriptor = descriptors[uri]
        if isChatProviderAnimation(uri, descriptor) then m.animatedEmotes[uri] = descriptor
    end for
end sub
