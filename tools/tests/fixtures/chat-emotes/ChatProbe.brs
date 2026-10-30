function fixtureBuild(text as string, start = -1 as float) as object
    if start < 0 then start = m.left_bound
    group = buildMessage(text, start)
    m.top.appendChild(group)
    return group
end function

function fixtureState() as object
    builds = 0
    if m.fixtureBuilds <> invalid then builds = m.fixtureBuilds
    return { left: m.left_bound, right: m.right_bound, failed: m.failedChatImages.count(), builds: builds, compiled: m.emojiRegex <> invalid, panel: m.chatPanel, job: m.chat }
end function

function fixturePinPreview() as object
    return m.pinRichText
end function

function fixturePinAuthor() as object
    return m.pinAuthorRichText
end function

function fixtureGifs(text as string, tags as object, enabled as boolean) as object
    m.animateChatEmotes = enabled
    attachments = ircGifAttachments(tags, text)
    group = buildMessage(text, m.left_bound, false, -1, attachments)
    m.top.appendChild(group)
    return group
end function

function fixtureGifState() as object
    return { descriptors: m.animatedEmotes, keys: m.gifAnimationKeys.count() }
end function

sub fixtureProviderUpdate(descriptors as object)
    saved = m.EmoteJob
    m.EmoteJob = createObject("roSGNode", "EmoteJob")
    m.top.appendChild(m.EmoteJob)
    m.EmoteJob.channel = m.top.channel
    m.EmoteJob.channel_id = m.top.channel_id
    m.animateChatEmotes = false
    onAnimatedEmotes({ node: m.EmoteJob, descriptors: descriptors, getRoSGNode: fixtureEventNode, getData: fixtureAnimationData })
    job = m.EmoteJob
    m.top.removeChild(job)
    destroyTask(job, "animatedEmotes")
    m.EmoteJob = saved
end sub

function fixtureAnimationData() as object
    return m.descriptors
end function

function fixturePublishProvider(cache as object) as object
    m.global.setField("emoteCache", cache)
    if m.EmoteJob = invalid
        m.EmoteJob = createObject("roSGNode", "EmoteJob")
        m.top.appendChild(m.EmoteJob)
        m.EmoteJob.channel = m.top.channel
        m.EmoteJob.channel_id = m.top.channel_id
        m.EmoteJob.observeField("animatedEmotes", "onAnimatedEmotes")
    end if
    m.EmoteJob.animatedEmotes = {}
    return { job: m.EmoteJob, completed: m.EmoteJob.completed, rendered: m.hasRenderedComment, presentation: m.chatPresentationState, statusVisible: m.chatStatus.visible }
end function

function fixtureMissingDescriptor() as boolean
    owner = createObject("roSGNode", "Group")
    owner.addFields({ chatImageUri: "missing-descriptor" })
    owner.appendChild(createObject("roSGNode", "Poster"))
    m.top.appendChild(owner)
    m.animationOwner = owner
    failChatAnimation()
    released = m.animationOwner = invalid and owner.getChild(0).visible
    m.top.removeChild(owner)
    return released
end function

function fixtureChatStatus(state as string, rendered as boolean) as object
    m.hasRenderedComment = rendered
    updateChatStatus(state)
    clip = m.chatPanel.clippingRect
    top = 0
    if GetInterface(clip, "ifAssociativeArray") <> invalid then top = clip.y
    if GetInterface(clip, "ifArray") <> invalid then top = clip[1]
    return { clipTop: top, panelVisible: m.chatPanel.visible, statusVisible: m.chatStatus.visible, statusHeight: m.chatStatus.height, pinVisible: m.pinPanel.visible }
end function

sub fixtureCompleteEmotes(cache as object)
    m.global.emoteCache = cache
    if m.EmoteJob = invalid
        m.EmoteJob = createObject("roSGNode", "EmoteJob")
        m.top.appendChild(m.EmoteJob)
    end if
    m.EmoteJob.cacheComplete = true
    m.EmoteJob.completed = true
    onEmotesCompleted()
end sub

sub fixturePrune(group as object)
    releaseChatImages(group)
    m.top.removeChild(group)
end sub

sub fixtureImageStatus(poster as object, status as string)
    onChatImageStatus({ node: poster, status: status, getRoSGNode: fixtureEventNode, getData: fixtureEventData })
end sub

function fixtureEventNode() as object
    return m.node
end function

function fixtureEventData() as string
    return m.status
end function

sub fixtureModerateRoom()
    removeModerated({ kind: "room", id: "", userId: "", login: "" })
end sub
