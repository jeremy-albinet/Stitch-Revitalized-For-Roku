sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: {}, fixtureWrites: 0, fixtureDeletes: 0, fixtureContentTasks: 0, emoteCache: {} })
    set_setting("active_user", "$default$")
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()
    testSettings()
    testLayout()
    testControls()
    fixtureEnd()
end sub

sub testSettings()
    settings = createObject("roSGNode", "Settings")
    m.scene.appendChild(settings)
    settings.setFocus(true)
    menu = settings.findNode("settingsMenu")
    track = settings.findNode("scrollTrack")
    thumb = settings.findNode("scrollThumb")
    position = settings.findNode("scrollPosition")
    check(not track.visible and not position.visible and menu.content.getChildCount() = 7, "grouped Settings root fits without scroll cues")
    scrollItems = []
    for i = 1 to 12
        scrollItems.push({ title: "Fixture row " + i.toStr() })
    end for
    settings.callFunc("fixtureSection", { title: "Scroll list", children: scrollItems })
    total = menu.content.getChildCount()
    check(track.visible and position.visible and total > menu.numRows, "Settings shows cues for a scrollable list")
    check(abs(thumb.height - track.height * menu.numRows / total) < 1, "thumb size reflects the actual visible row count")
    check(position.text = "1 of " + total.toStr(), "first row indicator")
    settings.callFunc("fixtureFocus", total - 1)
    check(abs(thumb.translation[1] + thumb.height - track.height) < 1, "last row moves the thumb to the bottom")
    check(position.text = total.toStr() + " of " + total.toStr(), "last row indicator")
    settings.callFunc("fixtureFocus", 4)
    settings.callFunc("fixtureSection", { title: "Short list", children: [{ title: "Short list" }] })
    check(not track.visible and not position.visible, "short submenu hides both scroll cues")
    settings.callFunc("fixtureKey", "back")
    check(track.visible and menu.itemFocused = 4, "returning restores the parent list focus and indicator")
    settings.callFunc("fixtureSection", { title: "Empty list", children: [] })
    check(not track.visible and not position.visible, "empty submenu hides indicators without division by zero")
    settings.callFunc("fixtureKey", "back")
    for each choice in [{ key: "chat.layout", value: "overlay" }, { key: "chat.overlayPosition", value: "top-left" }, { key: "chat.overlayOpacity", value: "0.75" }]
        settings.callFunc("fixtureChoose", choice.key, choice.value)
        check(registry_read(choice.key, "$default$") = choice.value, "actual Settings callback persists " + choice.key)
        settings.callFunc("fixtureKey", "left")
        check(menu.isInFocusChain(), "Left restores settings list focus")
    end for
    settings.callFunc("onDestroy")
    m.scene.removeChild(settings)
    settings = createObject("roSGNode", "Settings")
    m.scene.appendChild(settings)
    menu = settings.findNode("settingsMenu")
    settings.callFunc("fixtureFocus", 2)
    settings.callFunc("fixtureKey", "right")
    check(menu.content.getChildCount() = 9 and settings.findNode("sectionTitle").text = "Settings / Chat", "reopened Chat panel contains saved layout options")
    for each row in menu.content.getChildren(-1, 0)
        if row.id = "chat.layout" then check(row.shortDescriptionLine1 = "Over video", "reopened Settings displays saved layout")
        if row.id = "chat.overlayPosition" then check(row.shortDescriptionLine1 = "Top left", "reopened Settings displays saved corner")
        if row.id = "chat.overlayOpacity" then check(row.shortDescriptionLine1 = "75%", "reopened Settings displays saved opacity")
    end for
    settings.callFunc("onDestroy")
    m.scene.removeChild(settings)
end sub

sub testLayout()
    unset_user_setting("chat.layout")
    unset_user_setting("chat.overlayPosition")
    unset_user_setting("chat.overlayOpacity")
    set_user_setting("ChatOption", "false")
    player = createObject("roSGNode", "VideoPlayer")
    m.scene.appendChild(player)
    request = createObject("roSGNode", "TwitchContentNode")
    request.setFields({ contentType: "LIVE", contentId: "fixture", streamerId: "42", streamerLogin: "fixture", streamerDisplayName: "Fixture" })
    player.contentRequested = request
    state = player.callFunc("fixtureRead")
    playable = createObject("roSGNode", "TwitchContentNode")
    playable.setFields({ url: "http://fixture.invalid/live", QualityID: "720p60", streamFormat: "hls" })
    state.task.response = playable
    settle(100)
    state = player.callFunc("fixtureRead")
    video = state.video
    chat = state.chat
    video.state = "playing"
    settle(80)
    chat.visible = true
    settle(80)
    check(video.width = 960 and video.height = 720 and chat.width = 320 and chat.height = 720, "default visible chat preserves side-by-side geometry")
    check(chat.translation[0] = 960 and chat.translation[1] = 0 and not chat.overlayMode and chat.backgroundOpacity = 1, "default column stays opaque on the right")
    check(video.findNode("scrim").width = 960, "side-by-side controls stay inside the video")
    check(video.findNode("controlsHint").width = 864, "controls hint fits beside chat")
    check(chat.opacity = 1, "Chat root remains opaque")
    job = chat.callFunc("fixtureRead").job
    emote = chat.callFunc("fixtureRead").emote
    job.moderation = { events: [{ seq: 1, kind: "message", id: "deleted", userId: "99", login: "deleted" }] }
    set_user_setting("chat.pinnedMessages", "true")
    player.callFunc("fixtureLayout")
    worker = player.callFunc("fixtureRead").worker
    now = createObject("roDateTime").asSeconds()
    pin = { id: "kept-pin", messageId: "kept", userId: "7", login: "viewer", senderName: "Viewer", text: "Keep this pin", sentAt: now - 10, updatedAt: now, expiresAt: invalid, observedAt: now }
    worker.response = { owner: worker.owner, pinnedMessage: pin, hypeTrain: invalid }
    message = ircParseMessage("@id=kept;user-id=7;display-name=Viewer;color=#FF0000 :viewer!viewer@host PRIVMSG #fixture :Keep this message")
    message.identity = { id: "kept", userId: "7", login: "viewer" }
    message.moderationSeq = 1
    job.nextCommentObj = message
    m.global.emoteCache = { keep: "fixture-cache" }
    settle(50)
    before = chat.callFunc("fixtureRead")
    check(before.seq = 1 and before.colors > 0 and chat.findNode("pinPanel").visible, "actual chat callbacks establish moderation, color cache and pinned state")
    video.observeField("control", m.port)
    video.observeField("seek", m.port)
    video.observeField("content", m.port)
    video.observeField("QualityChangeRequestFlag", m.port)
    m.seen = {}
    for each corner in [{ id: "top-left", x: 48, y: 36 }, { id: "top-right", x: 872, y: 36 }, { id: "bottom-left", x: 48, y: 204 }, { id: "bottom-right", x: 872, y: 204 }]
        set_user_setting("chat.layout", "overlay")
        set_user_setting("chat.overlayPosition", corner.id)
        player.callFunc("fixtureLayout")
        settle(30)
        check(video.width = 1280 and video.height = 720 and video.findNode("scrim").width = 1280, "overlay keeps video and controls full size: " + corner.id)
        check(video.findNode("controlsHint").width = 1184, "overlay controls hint stays full width")
        check(chat.width = 360 and chat.height = 480 and chat.translation[0] = corner.x and chat.translation[1] = corner.y, "overlay fits the selected safe corner: " + corner.id)
        check(chat.overlayMode and chat.backgroundOpacity = 0.5 and chat.opacity = 1, "only background opacity is configured: " + corner.id)
        check(player.getChild(0).isSameNode(video) and chat.getParent().isSameNode(player), "existing chat stays above the single video")
        after = chat.callFunc("fixtureRead")
        check(job.isSameNode(after.job) and emote.isSameNode(after.emote), "resizing preserves chat and emote workers")
        check(after.seq = before.seq and m.global.emoteCache.keep = "fixture-cache", "resizing preserves moderation state and provider cache")
        check(after.colors >= before.colors, "resizing preserves populated color cache")
        check(chat.pinnedMessage.id = "kept-pin", "resizing preserves pinned metadata")
        check(chat.findNode("pinPanel").visible, "resizing preserves visible pinned message")
        check(worker.isSameNode(player.callFunc("fixtureRead").worker) and chat.findNode("pinText").opacity = 1, "layout retains the metadata worker and opaque pinned text")
    end for
    for each choice in [{ id: "0.25", value: 0.25 }, { id: "0.75", value: 0.75 }, { id: "1", value: 1.0 }, { id: "bad", value: 0.5 }]
        set_user_setting("chat.overlayOpacity", choice.id)
        player.callFunc("fixtureLayout")
        check(chat.backgroundOpacity = choice.value and chat.opacity = 1, "valid background opacity or safe fallback: " + choice.id)
        check(chat.findNode("chatPanel").color = &h00000000 and chat.findNode("pinPanel").color = &h18181B00 and chat.findNode("hypePanel").color = &h18181B00, "overlay headers and message panel do not stack extra background opacity")
        check(chat.findNode("chatBackground").opacity = choice.value, "one backdrop applies the selected opacity")
    end for
    for each invalidValue in ["bad", "", invalid, {}, [], true, 123]
        set_user_setting("chat.layout", invalidValue)
        set_user_setting("chat.overlayPosition", invalidValue)
        set_user_setting("chat.overlayOpacity", invalidValue)
        player.callFunc("fixtureLayout")
        check(video.width = 960 and not chat.overlayMode and chat.backgroundOpacity = 1, "invalid saved layout falls back to side")
        set_user_setting("chat.layout", "overlay")
        player.callFunc("fixtureLayout")
        check(chat.translation[0] = 872 and chat.translation[1] = 204 and chat.backgroundOpacity = 0.5, "invalid corner and opacity fall back safely")
        geometry = player.callFunc("fixtureGeometry", "overlay", invalidValue, invalidValue, invalidValue)
        check(geometry.videoWidth = 1280 and geometry.videoHeight = 720 and geometry.chatWidth = 360 and geometry.chatHeight = 480, "invalid dimensions use HD fallback")
    end for
    geometry = player.callFunc("fixtureGeometry", "overlay", "bottom-right", 640, 320)
    check(geometry.chatTranslation[0] + geometry.chatWidth <= 592 and geometry.chatTranslation[1] + geometry.chatHeight <= 284, "smaller valid canvas clamps overlay size inside its insets")
    check(seen("control").count() = 0 and seen("seek").count() = 0 and seen("content").count() = 0 and seen("QualityChangeRequestFlag").count() = 0, "layout changes never control, seek, reload or change quality")
    for each field in ["control", "seek", "content", "QualityChangeRequestFlag"]
        video.unobserveField(field)
    end for
    set_user_setting("chat.layout", "overlay")
    player.callFunc("fixtureReplace")
    settle(60)
    replacement = player.callFunc("fixtureRead").video
    check(not replacement.isSameNode(video) and replacement.width = 1280 and replacement.findNode("scrim").width = 1280, "replacement wrapper reapplies full overlay geometry")
    check(player.getChild(0).isSameNode(replacement) and player.callFunc("fixtureRead").chat.isSameNode(chat), "replacement preserves existing chat above the new video")
    check(job.isSameNode(chat.callFunc("fixtureRead").job), "replacement does not reconnect chat")
    for each mode in ["side", "overlay"]
        set_user_setting("chat.layout", mode)
        chat.visible = false
        settle(40)
        check(replacement.width = 1280 and replacement.findNode("scrim").width = 1280 and not replacement.chatIsVisible, "hidden chat restores full video and controls: " + mode)
        chat.visible = true
        settle(40)
        expected = 960
        if mode = "overlay" then expected = 1280
        check(replacement.width = expected and replacement.chatIsVisible, "showing chat applies selected layout: " + mode)
    end for
    check(player.callFunc("fixtureKey", "back") and player.backPressed, "player still exits on Back after hidden controls pass it through")
    player.callFunc("onDestroy")
    m.scene.removeChild(player)
end sub

sub testControls()
    for each name in ["StitchVideo", "CustomVideo"]
        video = createObject("roSGNode", name)
        m.scene.appendChild(video)
        overlay = video.findNode("controlOverlay")
        hint = video.findNode("controlsHint")
        check(hint.text = "Press Down or Back to hide controls" and hint.getParent().isSameNode(overlay), "localized hint belongs to the controls overlay: " + name)
        check(not overlay.visible, "hint is hidden with controls initially: " + name)
        for each key in ["down", "back"]
            video.callFunc("fixtureKey", "up")
            check(overlay.visible, "opening controls shows the hint: " + name)
            video.callFunc("fixtureKey", key)
            check(not overlay.visible and not video.back, "advertised key hides controls without exiting: " + name + "/" + key)
        end for
        check(not video.callFunc("fixtureKey", "back"), "hidden-controls Back is passed to the parent exit handler: " + name)
        if name = "CustomVideo"
            video.callFunc("fixtureKey", "up")
            video.callFunc("fixturePreview")
            check(not hint.visible and video.findNode("seekHint").visible, "seek preview replaces the hide-controls hint with its cancel instructions")
            video.callFunc("fixtureKey", "back")
            check(overlay.visible and hint.visible and not video.findNode("seekHint").visible, "Back cancels preview and restores the normal controls hint")
        end if
        video.callFunc("onDestroy")
        m.scene.removeChild(video)
    end for
end sub
