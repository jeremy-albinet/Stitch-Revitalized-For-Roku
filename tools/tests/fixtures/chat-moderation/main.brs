' Actual Chat moderation handling: retained identity, displayed deletion, user
' purge, room clear, in-flight ordering, the bounded window and teardown. The
' ChatJob boundary has the production interface without a socket; comments and
' moderation events come from the production IRC parser.
sub main()
    m.assertions = 0
    m.failures = 0
    m.port = createObject("roMessagePort")
    m.screen = createObject("roSGScreen")
    m.screen.setMessagePort(m.port)
    m.global = m.screen.getGlobalNode()
    setConstants()
    m.global.addFields({ emoteCache: {}, fixtureRegistry: {} })
    scene = m.screen.createScene("ModerationHost")
    m.screen.show()
    m.log = []
    checkDisabledChat(scene)
    checkChatOverload(scene)
    checkRenderOverload(scene)
    checkStartupLifecycle(scene)

    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.channel = "canned"
    waitUntil(chat, "job", true, "chat job starts")
    job = chat.callFunc("fixtureJob")
    if job = invalid
        fail("chat job is unavailable")
        finish()
        return
    end if

    ' Every comment is rendered with the identity later moderation needs.
    deliver(job, privmsg("a1", "101", "alice", "first"), 0)
    deliver(job, privmsg("b2", "202", "bob", "spam"), 0)
    deliver(job, privmsg("c3", "303", "carol", "keep"), 0)
    deliver(job, privmsg("d4", "202", "bob", "again"), 0)
    deliver(job, "@display-name=erin;id=e5 :erin!erin@erin.tmi.twitch.tv PRIVMSG #canned :tagless" + chr(13) + chr(10), 0)
    before = rows(chat)
    check(ids(before) = "a1,b2,c3,d4,e5", "every delivered comment is displayed")
    if before.count() = 5
        check(before[1].userId = "202" and before[1].login = "bob" and before[4].userId = "" and before[4].login = "erin", "displayed messages retain sender ID and login")
        check(before[0].advance > 0 and before[4].y > before[0].y, "displayed messages are stacked oldest first")
    end if

    ' A displayed deletion removes only its message; older ones close the gap.
    moderate(chat, job, "@login=bob;target-msg-id=b2 :tmi.twitch.tv CLEARMSG #canned :spam")
    after = rows(chat)
    check(ids(after) = "a1,c3,d4,e5", "a deleted displayed message is removed")
    if before.count() = 5 and after.count() = 4
        check(near(after[0].y, before[0].y + before[1].advance), "an older message moves down into the removed space")
        check(near(after[1].y, before[2].y) and near(after[3].y, before[4].y), "newer messages keep their place")
    end if

    moderate(chat, job, "@login=x;target-msg-id=ffff-unknown :tmi.twitch.tv CLEARMSG #canned :gone")
    unchanged = rows(chat)
    check(ids(unchanged) = "a1,c3,d4,e5", "an unknown message ID removes nothing")
    if unchanged.count() = 4 and after.count() = 4 then check(near(unchanged[0].y, after[0].y), "an unknown message ID moves nothing")

    ' A purge removes the user's earlier messages by ID, or by login without one.
    moderate(chat, job, "@ban-duration=60;target-user-id=202 :tmi.twitch.tv CLEARCHAT #canned :bob")
    check(ids(rows(chat)) = "a1,c3,e5", "a user purge removes every displayed message by that user")
    moderate(chat, job, ":tmi.twitch.tv CLEARCHAT #canned :erin")
    check(ids(rows(chat)) = "a1,c3", "a purge falls back to login for messages without a user ID")
    deliver(job, privmsg("f6", "202", "bob", "after timeout"), 4)
    check(ids(rows(chat)) = "a1,c3,f6", "a message after the purge is displayed")

    ' Moderation can reach the renderer before an in-flight comment it covers.
    publish(job, "@target-msg-id=g7 :tmi.twitch.tv CLEARMSG #canned :x")
    deliver(job, privmsg("g7", "404", "dave", "deleted in flight"), 4)
    check(ids(rows(chat)) = "a1,c3,f6", "an in-flight comment deleted after delivery is never displayed")
    deliver(job, privmsg("h8", "404", "dave", "other"), 4)
    check(ids(rows(chat)) = "a1,c3,f6,h8", "an in-flight deletion withholds only its own message")
    publish(job, "@target-user-id=303 :tmi.twitch.tv CLEARCHAT #canned :carol")
    deliver(job, privmsg("i9", "303", "carol", "purged in flight"), 5)
    deliver(job, privmsg("j10", "303", "carol", "after purge"), 6)
    check(ids(rows(chat)) = "a1,f6,h8,j10", "an in-flight purge withholds earlier messages and keeps later ones")
    check(chat.callFunc("fixtureRead").seq = 6, "every published event is applied once")

    ' Events lost before the bounded window fail closed.
    job.moderation = { seq: 41, events: [event(40, "message", "zz1"), event(41, "message", "zz2")] }
    waitUntil(chat, "seq", 41, "gap window applied")
    check(rows(chat).count() = 0, "a gap before the published window clears displayed messages")
    deliver(job, privmsg("k11", "505", "frank", "too old to verify"), 30)
    check(rows(chat).count() = 0, "an in-flight comment older than the window is withheld")
    deliver(job, privmsg("l12", "505", "frank", "verified"), 41)
    check(ids(rows(chat)) = "l12", "a comment covered by the window is displayed")

    ' A room clear removes everything and resets the layout.
    m.log = [event(41, "message", "zz2")]
    moderate(chat, job, "@room-id=1 :tmi.twitch.tv CLEARCHAT #canned")
    state = chat.callFunc("fixtureRead")
    check(state.rows.count() = 0 and near(state.translation, state.start), "a room clear removes every message and resets the layout")
    deliver(job, privmsg("m13", "606", "gina", "after clear"), 42)
    check(ids(rows(chat)) = "m13", "a message after a room clear is displayed")

    ' Stopping the job releases its moderation observer.
    chat.visible = false
    waitUntil(chat, "job", false, "chat job stops")
    job.moderation = { seq: 43, events: [event(43, "room", "")] }
    job.nextCommentObj = withIdentity(privmsg("n14", "606", "gina", "stale"), 43)
    settle(300)
    check(ids(rows(chat)) = "m13" and chat.callFunc("fixtureRead").seq = 42, "a stopped job can no longer remove or add messages")

    ' A restarted job numbers its events from one again.
    chat.visible = true
    waitUntil(chat, "job", true, "chat job restarts")
    nextJob = chat.callFunc("fixtureJob")
    m.log = []
    moderate(chat, nextJob, "@target-msg-id=m13 :tmi.twitch.tv CLEARMSG #canned :x")
    check(rows(chat).count() = 0, "a restarted job's first event is applied")
    deliver(nextJob, privmsg("o15", "707", "hana", "last"), 1)

    ' USERNOTICE can contain a system line, a user's message, or both. A known
    ' local emote keeps this fixture offline and proves system text stays text.
    m.global.setField("emoteCache", { Kappa: "pkg:/images/white-square-mask.png" })
    deliver(nextJob, "@id=gift;login=bob;user-id=808;msg-id=subgift;system-msg=Kappa\sgifted\sa\ssub! :tmi.twitch.tv USERNOTICE #canned", 1)
    deliver(nextJob, "@id=resub;login=bob;user-id=808;msg-id=resub;system-msg=Bob\ssubscribed!;emotes=25:0-4 :tmi.twitch.tv USERNOTICE #canned :Kappa thanks!", 1)
    deliver(nextJob, "@id=anonymous;msg-id=anonsubmysterygift;system-msg=An\sanonymous\sviewer\sgifted\s5\ssubs! :tmi.twitch.tv USERNOTICE #canned", 1)
    deliver(nextJob, "@id=multiline;system-msg=Raid\nfrom\rAlice! :tmi.twitch.tv USERNOTICE #canned", 1)
    deliver(nextJob, "@id=announcement;display-name=Alice;login=alice;msg-id=announcement :tmi.twitch.tv USERNOTICE #canned :Welcome everyone!", 1)
    notices = rows(chat)
    check(ids(notices) = "o15,gift,resub,anonymous,multiline,announcement", "system-only and user-message notices render in order")
    if notices.count() = 6
        check(notices[1].text = "Kappa gifted a sub! " and notices[1].posters = 0 and notices[1].parts = 1, "system gift text renders without a fake username or emote substitution")
        check(notices[2].text.instr("Bob subscribed!") >= 0 and notices[2].text.instr("thanks!") >= 0 and notices[2].posters = 1 and notices[2].parts = 2, "resub renders its system line and separate emote-bearing user message")
        check(notices[2].login = "bob" and notices[2].userId = "808", "rendered notices retain the actor for moderation")
        check(notices[3].text = "An anonymous viewer gifted 5 subs! ", "anonymous notices render without account tags")
        check(notices[4].text = "Raid from Alice! ", "escaped newlines become safe spaces in the system line")
        check(notices[5].text.instr("Alice") >= 0 and notices[5].text.instr("Welcome everyone!") >= 0, "user-only announcements preserve sender and message")
        check(notices[2].advance > notices[1].advance, "a notice with user text reserves space for both lines")
    end if
    moderate(chat, nextJob, "@target-user-id=808 :tmi.twitch.tv CLEARCHAT #canned :bob")
    check(ids(rows(chat)) = "o15,anonymous,multiline,announcement", "a user purge removes the user's complete notices")
    deliver(nextJob, "@id=bits;display-name=Alice;bits=100;emotes=25:0-4 :alice!alice@host PRIVMSG #canned :Kappa cheers!", 2)
    deliver(nextJob, "@id=reward;display-name=Alice;custom-reward-id=reward-1 :alice!alice@host PRIVMSG #canned :Hello!", 2)
    events = rows(chat)
    check(events[4].text.instr("100 Bits") >= 0 and events[4].posters = 1 and events[4].parts = 2, "Bits amount is highlighted without shifting the user's emotes")
    check(events[5].text.instr("Channel Points reward") >= 0 and events[5].text.instr("Hello!") >= 0, "reward-tagged messages show their context and original text")
    moderate(chat, nextJob, ":tmi.twitch.tv CLEARCHAT #canned")
    deliver(nextJob, privmsg("o15", "707", "hana", "last"), 3)

    now = createObject("roDateTime").asSeconds()
    chat.hypeTrain = { id: "train", level: 3, percent: 18, expiresAt: now + 90&, observedAt: now, status: "active", shared: false }
    settle(100)
    banner = chat.callFunc("fixtureRead")
    check(banner.hypeVisible and banner.hypeTitle.instr("3") >= 0 and banner.hypeDetail.instr("18%") >= 0, "current Hype Train level and progress render in chat")
    sameHype = chat.hypeTrain
    chat.hypeTrain = sameHype
    check(chat.callFunc("fixtureRead").hypeAgeMs < banner.hypeAgeMs, "an unchanged fresh snapshot refreshes the banner's freshness")
    check(near(banner.hypeProgress, (chat.width - 24) * 0.18), "Hype Train bar uses provider progress and chat width")
    timer = banner.hypeTimer
    check(timer <> invalid and timer.control = "start", "the visible snapshot has a live expiry timer")
    chat.visible = false
    waitUntil(chat, "job", false, "chat hides while a train is active")
    check(not chat.callFunc("fixtureRead").hypeVisible and timer.control = "stop", "hiding chat stops its banner timer")
    chat.visible = true
    waitUntil(chat, "job", true, "chat reopens while a train is active")
    nextJob = chat.callFunc("fixtureJob")
    check(chat.callFunc("fixtureRead").hypeVisible, "a still-fresh train survives chat hide/show")
    chat.hypeTrain = { id: "train", level: 3, percent: 18, expiresAt: now + 90&, observedAt: now - 46, status: "active", shared: false }
    settle(50)
    check(not chat.callFunc("fixtureRead").hypeVisible, "republishing an old source snapshot cannot refresh its freshness")
    chat.hypeTrain = { id: "train", level: 3, percent: 18, expiresAt: createObject("roDateTime").asSeconds() + 1&, observedAt: now, status: "active", shared: false }
    settle(1300)
    check(not chat.callFunc("fixtureRead").hypeVisible and timer.control = "stop", "provider expiry hides the train without requiring another poll")
    chat.hypeTrain = { id: "train", level: 3, percent: 18, expiresAt: now + 90&, observedAt: now, status: "ended", shared: false }
    settle(100)
    check(chat.callFunc("fixtureRead").hypeTitle.instr("ended") >= 0 and chat.callFunc("fixtureRead").hypeDetail = "", "an explicit end displays an end state without a countdown")
    chat.callFunc("onDestroy")
    check(timer.control = "stop" and chat.callFunc("fixtureRead").hypeTimer = invalid and not chat.callFunc("fixtureRead").hypeVisible, "disposal releases the Hype Train timer")
    nextJob.moderation = { seq: 4, events: [event(4, "room", "")] }
    settle(300)
    check(ids(rows(chat)) = "o15" and not chat.callFunc("fixtureRead").job, "disposal releases the moderation observer")
    scene.removeChild(chat)
    checkPins(scene)
    finish()
end sub

sub checkChatOverload(scene as object)
    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.channel = "performance"
    waitUntil(chat, "job", true, "performance chat starts")
    job = chat.callFunc("fixtureJob")
    job.connectionState = "connected"
    now = createObject("roDateTime").asSeconds()
    job.workload = { observedAt: now, windowMs: 5000, busyMs: 10, events: 500, highWindows: 0 }
    chat.delaySeconds = 60
    check(not chat.callFunc("suspendIfOverloaded"), "healthy fast chat and a Sync hold do not pause processing")
    job.workload = { observedAt: now, windowMs: 5000, busyMs: 2000, events: 500, highWindows: 1 }
    check(not chat.callFunc("suspendIfOverloaded"), "one costly window is insufficient to pause chat")
    job.workload = { observedAt: now - 20, windowMs: 5000, busyMs: 2000, events: 500, highWindows: 2 }
    check(not chat.callFunc("suspendIfOverloaded"), "stale pressure cannot pause current playback")
    job.workload = { observedAt: now, windowMs: 5000, busyMs: 2000, events: 500, highWindows: 2 }
    chat.visible = false
    chat.visible = true
    waitUntil(chat, "job", true, "performance chat reopens")
    current = chat.callFunc("fixtureJob")
    current.connectionState = "connected"
    check(not chat.callFunc("suspendIfOverloaded"), "a replaced worker's old pressure is ignored")
    current.workload = { observedAt: now, windowMs: 5000, busyMs: 2000, events: 500, highWindows: 2 }
    check(chat.callFunc("suspendIfOverloaded"), "fresh sustained expensive chat can pause for an accepted playback recovery")
    state = chat.callFunc("fixtureRead")
    check(chat.visible and chat.pausedForPerformance and not state.job and state.emoteJob = invalid and state.statusVisible and state.status = "Chat is too fast for this TV. Chat is paused for this stream.", "automatic pause stops work and keeps an explanatory notice")
    chat.visible = false
    chat.visible = true
    check(not chat.callFunc("fixtureRead").job, "reopening cannot silently restart a performance-paused chat")
    set_user_setting("chat.enabled", "false")
    chat.visible = false
    chat.visible = true
    check(chat.callFunc("fixtureRead").status = "Chat is disabled in Settings.", "manual Off takes precedence over the performance notice")
    chat.callFunc("onDestroy")
    scene.removeChild(chat)
    set_user_setting("chat.enabled", "true")
end sub

sub checkRenderOverload(scene as object)
    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.channel = "render-performance"
    waitUntil(chat, "job", true, "render performance chat starts")
    job = chat.callFunc("fixtureJob")
    job.connectionState = "connected"
    for window = 1 to 2
        chat.callFunc("fixtureRenderCost", 1000, 800)
        deliver(job, privmsg("first" + window.toStr(), "101", "alice", "a rendered comment"), 0)
        chat.callFunc("fixtureRenderCost", 5000, 800)
        deliver(job, privmsg("second" + window.toStr(), "101", "alice", "another rendered comment"), 0)
        if window = 1 then check(not chat.callFunc("suspendIfOverloaded"), "one costly actual-render window does not pause chat")
    end for
    check(job.workload = invalid and chat.callFunc("suspendIfOverloaded"), "actual rendering can establish sustained pressure independently of ingress")
    check(chat.pausedForPerformance and rows(chat).count() = 0 and not chat.callFunc("fixtureRead").job, "render-triggered pause clears messages and stops its worker")
    chat.callFunc("onDestroy")
    scene.removeChild(chat)
end sub

sub checkDisabledChat(scene as object)
    set_user_setting("chat.enabled", "false")
    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.channel_id = "42"
    chat.channel = "disabled"
    chat.control = true
    settle(80)
    state = chat.callFunc("fixtureRead")
    check(not state.job and state.emoteJob = invalid and state.statusVisible and state.status = "Chat is disabled in Settings.", "disabled chat opens its notice without a connection or emote worker")
    m.global.setField("emoteCache", { previousChannelOnly: "pkg:/images/iconLogin.png" })
    chat.channel_id = "43"
    chat.channel = "still-disabled"
    check(m.global.emoteCache.count() = 0, "a channel change clears the previous channel's emotes even while chat processing is disabled")
    chat.visible = false
    chat.visible = true
    settle(80)
    state = chat.callFunc("fixtureRead")
    check(not state.job and state.emoteJob = invalid and not chat.findNode("chatPanel").visible, "channel and visibility changes cannot restart disabled chat")
    now = createObject("roDateTime").asSeconds()
    chat.hypeTrain = { id: "train", level: 3, percent: 18, expiresAt: now + 90&, observedAt: now, status: "active", shared: false }
    check(not chat.callFunc("fixtureRead").hypeVisible, "disabled chat does not render a late chat-event banner")
    set_user_setting("chat.enabled", "true")
    chat.visible = false
    chat.visible = true
    waitUntil(chat, "job", true, "enabled chat can open again")
    job = chat.callFunc("fixtureJob")
    emotes = chat.callFunc("fixtureRead").emoteJob
    check(emotes <> invalid, "enabling chat restores its emote loader")
    check(not m.global.emoteCache.doesExist("previousChannelOnly"), "re-enabling chat cannot resolve an emote left by the previous channel")
    m.global.setField("emoteCache", { currentChannelOnly: "pkg:/images/iconLogin.png" })
    set_user_setting("chat.enabled", "false")
    chat.visible = false
    chat.visible = true
    settle(80)
    state = chat.callFunc("fixtureRead")
    check(not state.job and state.emoteJob = invalid and job.stopRequested and emotes.stopRequested and job.getParent() = invalid and emotes.getParent() = invalid, "turning processing off drains and detaches existing chat workers")
    job.nextCommentObj = withIdentity(privmsg("late-disabled", "101", "alice", "late"), 0)
    job.connectionState = "connected"
    settle(50)
    state = chat.callFunc("fixtureRead")
    check(rows(chat).count() = 0 and state.status = "Chat is disabled in Settings." and state.statusVisible, "old workers cannot replace the disabled notice or render late messages")
    set_user_setting("chat.enabled", "true")
    chat.visible = false
    chat.visible = true
    waitUntil(chat, "job", true, "same-channel chat can restart")
    check(m.global.emoteCache.doesExist("currentChannelOnly"), "same-channel disable and re-enable retains its emote cache")
    chat.callFunc("onDestroy")
    scene.removeChild(chat)
    set_user_setting("chat.enabled", "true")
end sub

sub checkStartupLifecycle(scene as object)
    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.visible = false
    chat.channel_id = "42"
    chat.channel = "startup"
    settle(80)
    state = chat.callFunc("fixtureRead")
    check(not state.job and state.emoteJob = invalid, "hidden startup creates neither chat nor emote worker")
    chat.visible = true
    waitUntil(chat, "job", true, "opening hidden chat starts its job")
    state = chat.callFunc("fixtureRead")
    job = chat.callFunc("fixtureJob")
    emotes = state.emoteJob
    check(emotes <> invalid and state.presentation = "connecting" and state.statusVisible, "opening chat starts both workers and shows connecting")

    job.connectionState = "connected"
    waitUntil(chat, "presentation", "waiting", "welcome waits for new messages")
    check(chat.callFunc("fixtureRead").statusVisible, "IRC welcome keeps the empty-panel status visible")
    job.deliveryState = "syncing"
    waitUntil(chat, "presentation", "syncing", "queued messages show their video sync hold")
    check(chat.callFunc("fixtureRead").status = "Syncing chat with video…", "sync status explains the intentional video delay")
    chat.callFunc("fixtureTryRender", { tags: {}, parameters: "", command: { command: "USERNOTICE" }, moderationSeq: 0 })
    settle(50)
    check(chat.callFunc("fixtureRead").statusVisible and rows(chat).count() = 0, "an empty notice cannot dismiss the startup status")
    chat.callFunc("fixtureTryRender", { tags: invalid, parameters: "bad" })
    settle(50)
    check(job.readyForNextComment and chat.callFunc("fixtureRead").statusVisible, "a failed render keeps the status visible and acknowledges the message")
    job.moderation = { seq: 1, events: [event(1, "message", "removed")] }
    waitUntil(chat, "seq", 1, "startup deletion arrives")
    deliver(job, privmsg("removed", "101", "alice", "deleted"), 0)
    check(rows(chat).count() = 0 and chat.callFunc("fixtureRead").statusVisible, "an in-flight deleted first message cannot dismiss the status")
    deliver(job, privmsg("approved", "101", "alice", "first visible"), 1)
    check(ids(rows(chat)) = "approved" and not chat.callFunc("fixtureRead").statusVisible, "only the first approved successful render dismisses the status")
    job.deliveryState = "waiting"
    settle(30)
    check(not chat.callFunc("fixtureRead").statusVisible, "later quiet periods do not cover messages with startup status")

    chat.visible = false
    waitUntil(chat, "job", false, "hiding chat stops its job")
    state = chat.callFunc("fixtureRead")
    check(state.emoteJob = invalid and emotes.stopRequested and emotes.control = "stop" and emotes.getParent() = invalid, "hiding chat cancels and detaches an unfinished emote fetch")
    check(state.emoteChannel = "", "canceled emote fetch is never marked complete")
    emotes.completed = true
    job.connectionState = "unavailable"
    job.deliveryState = "syncing"
    job.moderation = { seq: 2, events: [event(2, "room", "")] }
    job.nextCommentObj = withIdentity(privmsg("hidden", "101", "alice", "late"), 2)
    settle(50)
    check(chat.callFunc("fixtureRead").presentation = "stopped" and ids(rows(chat)) = "approved", "hidden workers cannot publish status, completion, moderation or messages")

    chat.visible = true
    waitUntil(chat, "job", true, "reopening chat starts fresh jobs")
    state = chat.callFunc("fixtureRead")
    fresh = chat.callFunc("fixtureJob")
    freshEmotes = state.emoteJob
    check(freshEmotes <> invalid and not freshEmotes.isSameNode(emotes) and not fresh.isSameNode(job), "unfinished emote loading retries on reopen")
    chat.callFunc("fixtureStaleEvent", job)
    chat.callFunc("fixtureStaleEvent", emotes)
    check(chat.callFunc("fixtureRead").presentation = "connecting" and ids(rows(chat)) = "approved", "already-queued callbacks from old workers are rejected by node identity")
    check(chat.callFunc("fixtureRead").emoteJob.isSameNode(freshEmotes), "stale completion cannot release the replacement emote fetch")
    freshEmotes.cacheComplete = true
    freshEmotes.completed = true
    settle(50)
    state = chat.callFunc("fixtureRead")
    check(state.emoteJob = invalid and state.emoteChannel = "startup" and freshEmotes.getParent() = invalid, "completed emote loading releases its observer and remembers its cache")
    chat.visible = false
    waitUntil(chat, "job", false, "completed chat hides")
    chat.visible = true
    waitUntil(chat, "job", true, "completed chat reopens")
    check(chat.callFunc("fixtureRead").emoteJob = invalid, "completed emote cache survives hide and reopen without another fetch")
    chat.callFunc("onDestroy")
    freshEmotes.completed = false
    freshEmotes.completed = true
    check(not chat.callFunc("fixtureRead").job and chat.callFunc("fixtureRead").emoteJob = invalid, "disposal leaves no worker and ignores completion")
    scene.removeChild(chat)
    checkEmoteIdentity(scene)
    m.log = []
end sub

sub checkEmoteIdentity(scene as object)
    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.channel = "late-id"
    waitUntil(chat, "job", true, "chat starts before its channel ID arrives")
    originalChat = chat.callFunc("fixtureJob")
    initial = chat.callFunc("fixtureRead").emoteJob
    check(initial <> invalid and initial.channel_id = "", "missing channel ID still permits global emotes and login-based badges")
    initial.completed = true
    settle(30)
    check(chat.callFunc("fixtureRead").emoteChannel = "", "partial loading is never marked as a completed cache")
    chat.channel_id = "42"
    settle(30)
    loading = chat.callFunc("fixtureRead").emoteJob
    check(loading <> invalid and loading.channel_id = "42" and originalChat.isSameNode(chat.callFunc("fixtureJob")), "a late channel ID restarts only the emote loader")
    chat.channel_id = "43"
    settle(30)
    updated = chat.callFunc("fixtureRead").emoteJob
    check(loading.stopRequested and loading.getParent() = invalid and updated.channel_id = "43", "an updated channel ID cancels the old loader before starting its replacement")
    updated.completed = true
    settle(30)
    check(chat.callFunc("fixtureRead").emoteJob = invalid and chat.callFunc("fixtureRead").emoteChannel = "", "provider partial failure releases the worker without caching a success marker")
    chat.visible = false
    waitUntil(chat, "job", false, "partial cache hides")
    chat.visible = true
    waitUntil(chat, "job", true, "partial cache retries on reopen")
    retry = chat.callFunc("fixtureRead").emoteJob
    check(retry <> invalid and retry.channel_id = "43", "provider partial failure can retry on a later reopen")
    retry.cacheComplete = true
    retry.completed = true
    settle(30)
    chat.callFunc("onDestroy")
    scene.removeChild(chat)
end sub

sub checkPins(scene as object)
    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.channel = "pins"
    waitUntil(chat, "job", true, "pinned chat starts")
    job = chat.callFunc("fixtureJob")
    m.log = []
    now = createObject("roDateTime").asSeconds()
    pin = fixturePin("pin-1", now)
    chat.pinnedMessage = pin
    state = chat.callFunc("fixtureRead")
    check(state.pinVisible and state.pinText = pin.text and state.pinAuthor = "Moderator", "pin preview retains the author and complete source text")
    timer = state.pinTimer
    check(timer <> invalid and timer.control = "start", "a visible pin owns an expiry timer")
    chat.hypeTrain = { id: "train", level: 2, percent: 25, expiresAt: now + 90&, observedAt: now, status: "active" }
    state = chat.callFunc("fixtureRead")
    check(state.hypeVisible and state.pinVisible and state.pinY = 76, "pins and Hype Trains occupy separate chat headers")
    check(chat.callFunc("showPinnedMessage"), "the full pinned message can be opened")
    dialog = scene.dialog
    check(dialog <> invalid and chat.callFunc("fixtureRead").pinDialog <> invalid, "the chat owns its full-text dialog")
    check(not chat.callFunc("showPinnedMessage"), "a second full-text dialog is not opened over the first")
    chat.pinnedMessage = invalid
    check(not chat.callFunc("fixtureRead").pinVisible and scene.dialog = invalid and timer.control = "stop", "unpinning closes the full text and stops its timer")

    chat.pinnedMessage = pin
    check(chat.callFunc("showPinnedMessage"), "a newly visible pin can be opened again")
    dialog = scene.dialog
    dialog.buttonSelected = 0
    settle(50)
    check(scene.dialog = invalid, "the continue-watching button closes the dialog")
    chat.visible = false
    waitUntil(chat, "job", false, "pinned chat hides")
    check(not chat.callFunc("fixtureRead").pinVisible and timer.control = "stop", "hiding chat hides its pin and stops the timer")
    chat.visible = true
    waitUntil(chat, "job", true, "pinned chat reopens")
    job = chat.callFunc("fixtureJob")
    check(chat.callFunc("fixtureRead").pinVisible, "a fresh pin survives chat hide and show")
    old = fixturePin("old", now - 46)
    chat.pinnedMessage = old
    chat.pinnedMessage = old
    check(not chat.callFunc("fixtureRead").pinVisible, "repeated publication cannot make an old pin fresh")
    expired = fixturePin("expired", now)
    expired.expiresAt = createObject("roDateTime").asSeconds() + 1&
    chat.pinnedMessage = expired
    check(chat.callFunc("showPinnedMessage"), "a timed pin opens while it is current")
    settle(1350)
    check(not chat.callFunc("fixtureRead").pinVisible and scene.dialog = invalid and timer.control = "stop", "expiry hides the pin and closes its dialog without another poll")

    chat.pinnedMessage = pin
    check(chat.callFunc("showPinnedMessage"), "the current pin opens before moderation")
    moderate(chat, job, "@target-msg-id=pin-1 :tmi.twitch.tv CLEARMSG #pins :deleted")
    chat.pinnedMessage = pin
    check(not chat.callFunc("fixtureRead").pinVisible and scene.dialog = invalid, "message deletion suppresses a delayed pin snapshot and closes its dialog")
    for i = 1 to 33
        moderate(chat, job, "@target-msg-id=other" + i.toStr() + " :tmi.twitch.tv CLEARMSG #pins :deleted")
    end for
    chat.pinnedMessage = pin
    check(not chat.callFunc("fixtureRead").pinVisible, "a deleted current pin stays suppressed after the moderation window rolls")
    userPin = fixturePin("user-pin", now)
    chat.pinnedMessage = userPin
    check(chat.callFunc("fixtureRead").pinVisible, "deleting one message does not suppress another pin")
    moderate(chat, job, "@target-user-id=202 :tmi.twitch.tv CLEARCHAT #pins :moderator")
    check(not chat.callFunc("fixtureRead").pinVisible, "a user purge hides that user's earlier pinned message")
    newPin = fixturePin("new-pin", now)
    newPin.sentAt = createObject("roDateTime").asSeconds() + 1&
    chat.pinnedMessage = newPin
    check(chat.callFunc("fixtureRead").pinVisible, "a pin of a new message after a purge remains eligible")
    newPin.sentAt = now - 10
    newPin.userId = "303"
    newPin.login = "another"
    chat.pinnedMessage = newPin
    moderate(chat, job, ":tmi.twitch.tv CLEARCHAT #pins")
    check(not chat.callFunc("fixtureRead").pinVisible, "a room clear removes earlier pins from every user")
    chat.channel = "replacement"
    check(chat.pinnedMessage = invalid and not chat.callFunc("fixtureRead").pinVisible, "channel replacement clears the previous pin")
    chat.pinnedMessage = pin
    check(chat.callFunc("fixtureRead").pinVisible, "channel replacement releases old-channel moderation tombstones")
    chat.callFunc("showPinnedMessage")
    chat.callFunc("onDestroy")
    state = chat.callFunc("fixtureRead")
    check(timer.control = "stop" and state.pinTimer = invalid and not state.pinVisible and scene.dialog = invalid, "disposal releases the pin timer and full-text dialog")
    scene.removeChild(chat)
end sub

function fixturePin(id as string, now as longinteger) as object
    return { id: id, messageId: id, userId: "202", login: "moderator", senderName: "Moderator", text: "Read this pinned message in full.", sentAt: now - 10, updatedAt: now, expiresAt: invalid, observedAt: now }
end function

function privmsg(id as string, userId as string, login as string, text as string) as string
    return "@display-name=" + login + ";id=" + id + ";user-id=" + userId + " :" + login + "!" + login + "@" + login + ".tmi.twitch.tv PRIVMSG #canned :" + text + chr(13) + chr(10)
end function

' The comment exactly as the transport delivers it.
function withIdentity(line as string, seq as integer) as object
    comment = ircParseMessage(line)
    comment.identity = ircMessageIdentity(comment)
    comment.moderationSeq = seq
    return comment
end function

' Waits for Chat.onNewCommentObj to finish its ready handshake.
sub deliver(job as object, line as string, seq as integer)
    job.readyForNextComment = false
    job.nextCommentObj = withIdentity(line, seq)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        if job.readyForNextComment then return
        pump(20)
    end while
    fail("timed out rendering a comment")
end sub

function event(seq as integer, kind as string, id as string) as object
    return { seq: seq, kind: kind, id: id, userId: "", login: "" }
end function

' Publishes the transport's bounded window shape for one parsed notice.
sub publish(job as object, line as string)
    parsed = ircModerationEvent(ircParseMessage(line))
    if parsed = invalid
        fail("fixture notice did not parse")
        return
    end if
    seq = 1
    if m.log.count() > 0 then seq = m.log[m.log.count() - 1].seq + 1
    parsed.seq = seq
    m.log.push(parsed)
    if m.log.count() > 32 then m.log.shift()
    job.moderation = { seq: seq, events: m.log }
end sub

sub moderate(chat as object, job as object, line as string)
    publish(job, line)
    waitUntil(chat, "seq", m.log[m.log.count() - 1].seq, "moderation applied")
end sub

function rows(chat as object) as object
    return chat.callFunc("fixtureRead").rows
end function

function ids(list as object) as string
    result = []
    for each row in list
        result.push(row.id)
    end for
    return result.join(",")
end function

function near(a as float, b as float) as boolean
    return abs(a - b) < 0.01
end function

sub waitUntil(chat as object, key as string, value as dynamic, what as string)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        if chat.callFunc("fixtureRead")[key] = value then return
        pump(20)
    end while
    fail("timed out waiting for " + what)
end sub

sub settle(duration as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < duration
        pump(20)
    end while
end sub

sub pump(duration as integer)
    wait(duration, m.port)
end sub

sub finish()
    m.screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_CHAT_MODERATION_FAIL:"; m.failures; " failures"
    end if
end sub

sub fail(message as string)
    m.failures += 1
    print "STITCH_CHAT_MODERATION_FAIL: " + message
end sub

sub check(condition as boolean, message as string)
    if condition
        m.assertions += 1
    else
        fail(message)
    end if
end sub
