' Native object/time/wait/send and registry boundaries only. Production decisions execute.
sub main()
    m.assertions = 0
    m.failures = 0
    resetBoundary()
    transport = openChatTransport()
    check(transport <> invalid, "writable TCP with stale connected status must be usable")
    if transport <> invalid then check(not transport.secure, "fallback remains anonymous plaintext")
    check(getGlobalAA().socketCloses = 0 and getGlobalAA().waits = 0, "ready socket returns without an eight-second spin")
    check(not getGlobalAA().notifyWrite and getGlobalAA().notifyRead, "ready socket disables writable events and retains readable events")

    resetBoundary()
    getGlobalAA().readyAt = 2
    transport = openChatTransport()
    check(transport <> invalid and getGlobalAA().waits = 2, "pending connection waits for writable readiness")
    check(getGlobalAA().socketCloses = 0, "pending success keeps socket open for bounded login")

    resetBoundary()
    getGlobalAA().readyAt = 99
    transport = openChatTransport()
    check(transport = invalid, "connection deadline rejects never-writable sockets")
    check(getGlobalAA().socketCloses = 1 and getGlobalAA().waits = 80, "deadline closes socket once after eight seconds")

    resetBoundary()
    getGlobalAA().hardError = true
    transport = openChatTransport()
    check(transport = invalid and getGlobalAA().socketCloses = 1, "writable socket with hard error cannot start login")
    check(getGlobalAA().waits = 0, "hard failure does not spin until deadline")

    resetBoundary()
    m.top = { stopRequested: true }
    transport = openChatTransport()
    check(transport = invalid and getGlobalAA().socketCreated = 0, "stopped caller never creates a fallback socket")

    resetBoundary()
    getGlobalAA().readyAt = 99
    getGlobalAA().stopAt = 1
    transport = openChatTransport()
    check(transport = invalid and getGlobalAA().socketCloses = 1 and getGlobalAA().waits = 1, "stop during wait closes socket without retry")

    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    getGlobalAA().webSocketOpened = true
    transport = openChatTransport()
    check(transport <> invalid and transport.secure, "successful WebSocket keeps secure transport")
    check(getGlobalAA().socketCreated = 0 and getGlobalAA().webSocketCloses = 0, "secure success does not create or close a fallback")
    check(getGlobalAA().peerVerified and getGlobalAA().hostVerified and getGlobalAA().certificates, "secure transport retains certificate and peer/host verification")

    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    transport = openChatTransport()
    check(transport <> invalid and not transport.secure, "unavailable WebSocket falls back to usable TCP")
    check(getGlobalAA().webSocketCloses = 1 and getGlobalAA().socketCreated = 1, "failed WebSocket closes before single fallback creation")
    __CONNECTION_TESTS__
    __SEND_TESTS__
    __JOB_TESTS__
    __MODERATION_TESTS__
    __EMOTE_TESTS__
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

' The production emote sequence executes; each provider's HTTP work is inert.
sub runEmoteTests()
    for canceledAt = 1 to 8
        resetEmoteBoundary()
        getGlobalAA().cancelProviderAt = canceledAt
        runEmoteJob()
        check(getGlobalAA().providerCalls.count() = canceledAt, "canceled emote loading starts no subsequent provider")
        check(not m.top.completed and not m.top.cacheComplete, "canceled emote loading never publishes completion")
    end for
    resetEmoteBoundary()
    m.top.stopRequested = true
    runEmoteJob()
    check(getGlobalAA().providerCalls.count() = 0 and not m.top.completed, "an already canceled emote task starts no provider")

    resetEmoteBoundary()
    runEmoteJob()
    check(getGlobalAA().providerCalls.count() = 8 and m.top.completed and m.top.cacheComplete, "all enabled emote providers finish before successful cache completion")
    resetEmoteBoundary()
    getGlobalAA().failProviderAt = 5
    runEmoteJob()
    check(m.top.completed and not m.top.cacheComplete and getGlobalAA().providerCalls.count() = 8, "partial provider failure finishes without a success cache marker")
    resetEmoteBoundary()
    m.top.channel_id = ""
    runEmoteJob()
    check(m.top.completed and not m.top.cacheComplete and getGlobalAA().providerCalls.count() = 4, "missing channel ID permits global providers but skips malformed channel requests and success marker")

    resetEmoteBoundary()
    m.top.stopRequested = true
    publishEmoteCache({ New: "https://cdn.example/new.png" })
    check(getGlobalAA().cachePublications = 0, "canceled emote task cannot publish late cache updates")
    m.top.stopRequested = false
    publishEmoteCache({ New: "https://cdn.example/new.png" })
    cache = getGlobalAA().publishedCache
    check(getGlobalAA().cachePublications = 1 and cache.IRC = "https://cdn.example/irc.png" and cache.New = "https://cdn.example/new.png", "completed fetch publication keeps emotes learned from IRC")
    check(GetInterface(m.top.animatedEmotes, "ifAssociativeArray") <> invalid, "static-only provider results publish a pin-refresh notification before completion")
    m.top.animatedEmotes = { "https://cdn.example/static.png": { uri: "https://cdn.example/animated.webp" } }
    publishEmoteCache({ New: "https://cdn.example/new.png" })
    check(m.top.animatedEmotes.count() = 1, "static-only publication preserves previously supplied animation descriptors")
end sub

sub resetEmoteBoundary()
    resetBoundary()
    m.top.channel_id = "42"
    m.top.completed = false
    m.top.cacheComplete = false
    m.global = { emoteCache: { IRC: "https://cdn.example/irc.png" }, setField: fixturePublishCache }
    state = getGlobalAA()
    state.providerCalls = []
    state.cancelProviderAt = 0
    state.failProviderAt = 0
    state.cachePublications = 0
    state.publishedCache = invalid
end sub

sub fixturePublishCache(field as string, cache as object)
    getGlobalAA().cachePublications++
    getGlobalAA().publishedCache = cache
end sub

sub fixtureProvider(name as string)
    state = getGlobalAA()
    calls = state.providerCalls
    calls.push(name)
    state.providerCalls = calls
    if calls.count() = state.cancelProviderAt then m.top.stopRequested = true
    if calls.count() = state.failProviderAt then m.fetchFailed = true
end sub

sub getChannelTwitchEmotes(channelId as string)
    if channelId <> "" then fixtureProvider("channelTwitch")
end sub
sub getTwitchBadges()
    fixtureProvider("badges")
end sub
sub getGlobalTwitchEmotes()
    fixtureProvider("globalTwitch")
end sub
sub getGlobalTTVEmotes()
    fixtureProvider("globalTTV")
end sub
sub getChannelTTVEmotes(channelId as string)
    fixtureProvider("channelTTV")
end sub
sub getChannelTTVFrankerEmotes(channelId as string)
    fixtureProvider("FFZ")
end sub
sub getGlobal7tvEmotes()
    fixtureProvider("global7TV")
end sub
sub getChannel7tvEmotes(channelId as string)
    fixtureProvider("channel7TV")
end sub

sub runConnectionTests()
    check(ircParseMessage(privmsg("skip", "101", "alice", "discarded"), false) = invalid, "a full queue rejects chat before decoding its tags")
    notice = "@id=notice;login=alice;system-msg=Alice\sgifted! :tmi.twitch.tv USERNOTICE #canned"
    check(ircParseMessage(notice, false) = invalid, "a full queue also rejects queued notices")
    deletion = ircParseMessage("@target-msg-id=gone :tmi.twitch.tv CLEARMSG #canned :removed", false)
    check(deletion <> invalid and deletion.tags.target_msg_id = "gone", "full-queue admission preserves moderation tags")
    ping = ircParseMessage("PING :tmi.twitch.tv", false)
    check(ping <> invalid and ping.command.command = "PING" and ping.parameters = "tmi.twitch.tv", "full-queue admission keeps transport keepalives")
    resetBoundary()
    getGlobalAA().readMode = "pending"
    getGlobalAA().stopAt = 3
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 3, "pending read must allow subsequent welcome and chat packet")
    check(getGlobalAA().waits = 3, "connection respects caller stop after pending/data reads")
    check(getGlobalAA().readSuccess, "later data clears the pending receive status")

    resetBoundary()
    getGlobalAA().readMode = "eof"
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 1 and getGlobalAA().waits = 1, "empty successful receive closes at actual EOF")

    resetBoundary()
    getGlobalAA().readMode = "error"
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 1 and getGlobalAA().waits = 1, "receive hard error ends without spinning")

    resetBoundary()
    m.top = { stopRequested: true }
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 0 and getGlobalAA().waits = 0, "stopped connection never reads another packet")

    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.liveAt = 8
    state.stopAt = 60
    m.top.delaySeconds = 60.0
    state.script = [
        ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
        privmsg("before", "101", "alice", "hello")
        "@id=gift;login=bob;msg-id=submysterygift;system-msg=Bob\sgifted\s5\ssubs! :tmi.twitch.tv USERNOTICE #canned" + chr(13) + chr(10)
        "@id=resub;login=carol;msg-id=resub;system-msg=Carol\ssubscribed!;emotes=25:0-4 :tmi.twitch.tv USERNOTICE #canned :Kappa thanks!" + chr(13) + chr(10)
        "@id=empty;msg-id=subgift :tmi.twitch.tv USERNOTICE #canned" + chr(13) + chr(10)
        privmsg("after", "404", "dave", "bye")
    ]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(deliveredIds() = "before,gift,resub,after", "USERNOTICE shares the ordered message queue and empty notices are ignored")
    check(state.deliveredBeforeLive = 0, "notices obey the delay and renderer-ready handshake")
    delivered = state.delivered
    if delivered.count() = 4
        check(delivered[1].parameters = "" and delivered[1].tags.system_msg = "Bob gifted 5 subs!", "system-only gift reaches the renderer")
        check(delivered[2].parameters = "Kappa thanks!" and delivered[2].tags.emotes["25"][0].startPosition = 0, "resub delivery preserves user text and emote offsets")
    end if
    runTimingTests()
    runWorkloadTests()
end sub

' Actual parsing executes; only its elapsed cost is a controlled clock boundary.
sub runWorkloadTests()
    for each parseCost in [0, 10, -1]
        resetBoundary()
        state = getGlobalAA()
        state.readMode = "script"
        state.stopAt = 20
        state.parseCostMs = parseCost
        if parseCost = -1
            state.parseCostMs = 0
            state.receiveCostMs = 1000
        end if
        m.top.delaySeconds = 60.0
        state.script = [":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)]
        for batch = 1 to 16
            chunk = ""
            for index = 1 to 100
                chunk += privmsg(batch.toStr() + "-" + index.toStr(), "101", "alice", "held for Sync")
            end for
            state.script.push(chunk)
        end for
        runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
        check(state.delivered.count() = 0, "work measurements do not bypass the Sync hold")
        if parseCost = 0
            check(m.top.workload = invalid, "fast ingress and queued Sync messages alone produce no costly work window")
        else
            workload = m.top.workload
            check(workload <> invalid, "actual receive/parse loop publishes measured work windows")
            if workload <> invalid
                check(workload.highWindows = 2 and workload.busyMs * 4 >= workload.windowMs, "two consecutive costly windows qualify as sustained ingress load")
                if parseCost = -1
                    check(workload.parseMs = 0 and workload.receiveMs = workload.busyMs, "receive cost is measured separately from parsing and socket waits")
                else
                    check(workload.receiveMs = 0 and workload.parseMs = workload.busyMs, "parse cost is measured separately from receiving and socket waits")
                end if
                check(workload.events >= 50 and workload.windowMs >= 5000 and workload.windowMs <= 10000, "published workload retains actual input counts and bounded elapsed duration")
                check(wallSeconds() - workload.observedAt <= 5, "work observation has a fresh wall-clock timestamp")
            end if
        end if
    end for
end sub

function fixtureParseMessage(line as string, acceptChat = true as boolean) as dynamic
    parsed = ircParseMessage(line, acceptChat)
    getGlobalAA().clock += getGlobalAA().parseCostMs
    return parsed
end function

' Each timespan has its own origin; time advances only at wait/sleep boundaries.
' Both server timestamps and receipt-only messages must survive the full delay.
sub runTimingTests()
    resetBoundary()
    first = fixtureCreateObject("roTimespan")
    getGlobalAA().clock = 400
    second = fixtureCreateObject("roTimespan")
    check(first.totalMilliseconds() = 400 and first.totalMilliseconds() = 400, "reading a clock never advances it")
    getGlobalAA().clock = 700
    second.mark()
    check(first.totalMilliseconds() = 700 and second.totalMilliseconds() = 0, "marking one clock leaves every other clock unchanged")

    for each live in [false, true]
        resetBoundary()
        state = getGlobalAA()
        state.readMode = "script"
        state.stopAt = 145
        m.top.delaySeconds = 13.0
        m.top.forceLive = live
        m.top.readyForNextComment = true
        state.script = [
            ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
            "@tmi-sent-ts=1700000000000;display-name=alice;id=timestamp :alice!alice@host PRIVMSG #canned :timed" + chr(13) + chr(10) + ":bob!bob@host PRIVMSG #canned :receipt only" + chr(13) + chr(10)
        ]
        runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
        check(state.delivered.count() = 2, "both timestamp and tagless messages eventually deliver")
        if state.deliveredAt.count() = 2
            if live
                check(state.deliveredAt[0] = 300 and state.deliveredAt[1] = 600, "Live delivers timestamp and tagless messages at the readable render cadence")
                check(not sawDeliveryState("syncing"), "Live never adds a video sync hold")
            else
                check(state.deliveredAt[0] = 13000 and state.deliveredAt[1] = 13300, "Sync holds server-timed and tagless messages for thirteen real seconds")
                check(sawDeliveryState("syncing") and state.liveAt = 0 and not m.top.forceLive, "Sync proof never switches forceLive to release messages")
            end if
        end if
        if state.delivered.count() = 2 then check(state.delivered[1].identity.login = "bob", "receipt-only delivery preserves tagless identity")
    end for

    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.stopAt = 145
    m.top.delaySeconds = 13.0
    m.top.readyForNextComment = true
    state.script = [
        ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
        privmsg("deleted", "101", "alice", "held")
        "@target-msg-id=deleted :tmi.twitch.tv CLEARMSG #canned :held" + chr(13) + chr(10)
    ]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(state.delivered.count() = 0 and publishedSeq() = 1, "deletion during the real Sync hold prevents delivery")
    check(sawDeliveryState("syncing") and m.top.deliveryState = "waiting", "removing the last held message returns the producer to waiting")

    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.stopAt = 405
    state.readyAtWait = 150
    m.top.delaySeconds = 13.0
    burst = ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
    for index = 1 to 260
        burst += privmsg("m" + index.toStr(), "101", "alice", "held")
    end for
    state.script = [burst]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(state.delivered.count() = 4, "busy chat keeps a short eligible backlog instead of replaying hundreds of stale messages")
    if state.delivered.count() = 4
        check(state.delivered[0].identity.id = "m247" and state.delivered[3].identity.id = "m250", "the bounded pending queue catches up only after messages become eligible")
        check(state.deliveredAt[0] = 15000 and state.deliveredAt[3] = 15900, "backpressure releases at most four messages per second without erasing receipt age")
    end if
    check(not m.top.forceLive, "backpressure fixture stays in Sync mode throughout")

    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.stopAt = 100
    m.top.delaySeconds = 1.3
    m.top.readyForNextComment = true
    state.script = [":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)]
    for index = 1 to 60
        state.script.push(privmsg(index.toStr(), "101", "alice", "fast chat"))
    end for
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(state.delivered.count() > 4 and state.delivered.count() < 30, "sustained fast chat samples messages at a bounded render rate")
    previousId = 0
    previousTime = -1000
    for index = 0 to state.delivered.count() - 1
        id = state.delivered[index].identity.id.toInt()
        deliveredAt = state.deliveredAt[index]
        check(id > previousId and deliveredAt - previousTime >= 250, "sampled messages retain order and leave time between rendering callbacks")
        check(deliveredAt - (id + 1) * 100 >= 1300, "catching up never discards the selected message's Sync hold")
        previousId = id
        previousTime = deliveredAt
    end for
    check(previousId = 60 and previousTime <= 8500, "sustained fast chat reaches the latest message without an accumulating delay")

    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.stopAt = 4000
    state.script = [":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(state.clock = 360200 and state.delivered.count() = 0, "quiet welcomed chat waits six minutes after last activity before recovery")
    check(m.top.deliveryState = "waiting" and not sawDeliveryState("syncing"), "quiet chat waits for future messages without an invented sync countdown")

    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.stopAt = 4000
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(state.clock = 15100, "missing IRC welcome expires after fifteen seconds independent of other clocks")
end sub

function sawDeliveryState(value as string) as boolean
    for each state in getGlobalAA().stateHistory
        if state = value then return true
    end for
    return false
end function

sub runSendTests()
    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    socket = fixtureCreateObject("roWebSocket")
    sent = sendChatLine({ socket: socket, secure: true }, "CAP REQ :twitch.tv/tags")
    check(not sent and getGlobalAA().sendCalls = 1, "invalid secure send must not count as sent")
    check(getGlobalAA().sendTimeout = 1000, "secure send preserves its finite one-second wait")
    check(getGlobalAA().sentText = "CAP REQ :twitch.tv/tags" + chr(13) + chr(10), "secure send passes exactly one framed IRC line")

    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    socket = fixtureCreateObject("roWebSocket")
    check(not loginToChat({ socket: socket, secure: true }), "invalid secure send must fail login before credentials are sent")
    check(getGlobalAA().sendCalls = 1 and getGlobalAA().sentText.instr("oauth:") < 0, "failed CAP aborts login before PASS NICK and JOIN")
    check(getGlobalAA().registryReads = 2, "secure authenticated login reads only its account settings")

    resetBoundary()
    getGlobalAA().writeLimit = 4
    socket = fixtureCreateObject("roStreamSocket")
    sent = sendChatLine({ socket: socket, secure: false }, "PONG :fixture")
    check(sent and getGlobalAA().sendCalls > 1, "TCP partial writes must complete the actual line")
    check(getGlobalAA().sentText = "PONG :fixture" + chr(13) + chr(10), "TCP partial writes preserve every byte and final CRLF")

    resetBoundary()
    getGlobalAA().sendHardError = true
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "JOIN #canned"), "TCP send hard error fails immediately")
    check(getGlobalAA().sendCalls = 1 and getGlobalAA().sleeps = 0, "TCP hard error never sleeps until the deadline")

    resetBoundary()
    getGlobalAA().readyAt = 99
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "PONG :fixture"), "TCP stalled send expires")
    check(getGlobalAA().sendCalls = 0 and getGlobalAA().sleeps = 100 and getGlobalAA().clock = 1000, "TCP stalled send expires after one second")

    resetBoundary()
    m.top.stopRequested = true
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "JOIN #canned"), "stopped TCP send fails without another write")
    check(getGlobalAA().sendCalls = 0, "stopped TCP send never writes")

    resetBoundary()
    socket = fixtureCreateObject("roStreamSocket")
    check(loginToChat({ socket: socket, secure: false }), "plaintext login preserves anonymous read-only access")
    check(getGlobalAA().registryReads = 0, "plaintext login never reads account credentials")
    check(getGlobalAA().sentText.instr("PASS SCHMOOPIIE") >= 0 and getGlobalAA().sentText.instr("NICK justinfan") >= 0, "plaintext login uses only anonymous credentials")
    check(getGlobalAA().sentText.instr("oauth:") < 0 and getGlobalAA().sentText.instr("FixtureSentinelA1") < 0, "plaintext login never writes an OAuth token")

    resetBoundary()
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "PONG :fixture" + chr(13) + chr(10) + "JOIN #other"), "IRC line injection fails before sending")
    check(getGlobalAA().sendCalls = 0, "rejected IRC line injection writes no bytes")
end sub

sub runJobTests()
    resetBoundary()
    getGlobalAA().stopAt = 10000
    getGlobalAA().webSocketAvailable = true
    getGlobalAA().webSocketOpened = true
    runChatJob()
    check(m.top.connectionState = "unavailable", "failed login exhausts the actual finite retry budget")
    check(getGlobalAA().sendCalls = 6 and getGlobalAA().webSocketCloses = 6, "failed login closes each of six connection attempts")
    check(m.connectionLifetime = invalid and getGlobalAA().receiveCalls = 0, "failed login never starts the connection loop")
    check(getGlobalAA().sentText.instr("oauth:") < 0 and getGlobalAA().sentText.instr("FixtureSentinelA1") < 0, "failed first send never transmits account credentials")
end sub

' Twitch moderation through the actual parser, connection loop and publisher.
' The socket returns scripted lines; the wait boundary stands in for the renderer.
sub runModerationTests()
    deleted = ircModerationEvent(ircParseMessage("@login=bob;room-id=1;target-msg-id=B2-ID :tmi.twitch.tv CLEARMSG #canned :FixtureDeletedText"))
    check(deleted <> invalid and deleted.kind = "message" and deleted.id = "b2-id", "CLEARMSG targets one normalized message ID")
    check(ircModerationEvent(ircParseMessage("@login=bob;room-id=1 :tmi.twitch.tv CLEARMSG #canned :FixtureDeletedText")) = invalid, "CLEARMSG without a target is ignored")
    room = ircModerationEvent(ircParseMessage("@room-id=1;tmi-sent-ts=1642715695392 :tmi.twitch.tv CLEARCHAT #canned"))
    check(room <> invalid and room.kind = "room", "CLEARCHAT naming nobody clears the room")
    purge = ircModerationEvent(ircParseMessage("@ban-duration=350;room-id=1;target-user-id=202 :tmi.twitch.tv CLEARCHAT #canned :Bob"))
    check(purge <> invalid and purge.kind = "user" and purge.userId = "202" and purge.login = "bob", "CLEARCHAT naming a user purges by ID and login")
    check(ircModerationEvent(ircParseMessage(":tmi.twitch.tv CLEARCHAT #canned :bad login")) = invalid, "a malformed purge target is ignored, never widened to the room")
    check(ircModerationEvent(ircParseMessage("@target-user-id= :tmi.twitch.tv CLEARCHAT #canned")) = invalid, "an empty purge target is ignored, never widened to the room")
    check(ircModerationEvent(ircParseMessage(":a!a@a PRIVMSG #canned :hi")) = invalid, "chat messages are not moderation")
    tagless = ircMessageIdentity(ircParseMessage(":Fallback!fallback@host PRIVMSG #canned :no tags"))
    check(tagless.id = "" and tagless.userId = "" and tagless.login = "fallback", "tagless messages keep only their login identity")
    check(not ircModerationMatches(tagless, { kind: "message", id: "", userId: "", login: "" }), "an absent message ID matches no deletion")
    check(not ircModerationMatches(tagless, { kind: "user", id: "", userId: "", login: "other" }), "a purge of another login keeps the message")
    check(ircModerationMatches(tagless, { kind: "user", id: "", userId: "202", login: "fallback" }), "a purge without a retained user ID falls back to login")
    check(ircModerationMatches(invalid, room) and not ircModerationMatches(invalid, purge), "only a room clear matches a message without identity")

    ' Messages wait behind a 60-second delay while the renderer is busy. Deletion,
    ' purge, unknown and malformed notices arrive; later messages must survive.
    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.liveAt = 8
    state.stopAt = 60
    m.top.delaySeconds = 60.0
    state.script = [
        ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
        privmsg("a1", "101", "alice", "first") + privmsg("b2", "202", "bob", "spam") + privmsg("c3", "303", "carol", "keep")
        "@login=bob;room-id=1;target-msg-id=b2 :tmi.twitch.tv CLEARMSG #canned :FixtureDeletedText" + chr(13) + chr(10) + "@login=x;target-msg-id=ffff-unknown :tmi.twitch.tv CLEARMSG #canned :gone" + chr(13) + chr(10) + ":tmi.twitch.tv CLEARMSG #canned :untargeted" + chr(13) + chr(10) + ":tmi.twitch.tv CLEARCHAT #canned :bad login" + chr(13) + chr(10)
        privmsg("d4", "202", "bob", "again") + privmsg("e5", "404", "dave", "hello") + "@ban-duration=60;room-id=1;target-user-id=202 :tmi.twitch.tv CLEARCHAT #canned :bob" + chr(13) + chr(10)
        privmsg("f6", "202", "bob", "after timeout")
    ]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(state.publishedBeforeLive = 3, "moderation publishes while the renderer is busy and the delay holds every message")
    check(deliveredIds() = "a1,c3,e5,f6", "deleted queued message must never be delivered; purge removes only earlier messages")
    check(stampsEqual(3), "delivered comments carry the moderation they survived")
    events = publishedEvents()
    check(publishedSeq() = 3 and events.count() = 3, "malformed notices publish nothing")
    if events.count() = 3
        check(events[0].kind = "message" and events[0].id = "b2" and events[0].seq = 1, "deletion publishes its message ID first")
        check(events[1].kind = "message" and events[1].id = "ffff-unknown", "an unknown ID still reaches displayed messages harmlessly")
        check(events[2].kind = "user" and events[2].userId = "202" and events[2].login = "bob" and events[2].seq = 3, "purge publishes user ID and login in order")
    end if

    ' A room clear empties the queue; a message after it is delivered.
    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.liveAt = 5
    state.stopAt = 30
    m.top.delaySeconds = 60.0
    state.script = [
        ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
        privmsg("a1", "101", "alice", "first") + privmsg("b2", "202", "bob", "second") + "@room-id=1 :tmi.twitch.tv CLEARCHAT #canned" + chr(13) + chr(10) + privmsg("g7", "505", "erin", "after clear")
    ]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(deliveredIds() = "g7", "room clear removes every queued message and keeps later ones")
    events = publishedEvents()
    check(publishedSeq() = 1 and events.count() = 1 and stampsEqual(1), "room clear is published before later delivery")
    if events.count() = 1 then check(events[0].kind = "room", "room clear publishes a room event")

    ' The published window stays bounded; numbering continues across reconnects.
    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.stopAt = 3
    burst = ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
    for index = 1 to 40
        burst += "@target-msg-id=m" + index.toStr() + " :tmi.twitch.tv CLEARMSG #canned :x" + chr(13) + chr(10)
    end for
    state.script = [burst]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    events = publishedEvents()
    check(m.moderationLog.count() = 32 and events.count() = 32 and publishedSeq() = 40, "the moderation window holds the latest 32 events")
    if events.count() = 32 then check(events[0].seq = 9 and events[0].id = "m9" and events[31].id = "m40", "the window drops only the oldest events")
    state.receiveCalls = 0
    state.waits = 0
    state.readMode = "script"
    state.script = ["@target-msg-id=late :tmi.twitch.tv CLEARMSG #canned :x" + chr(13) + chr(10)]
    m.top.stopRequested = false
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(publishedSeq() = 41 and m.moderationLog.count() = 32, "a reconnect continues numbering instead of repeating applied sequences")
end sub

function privmsg(id as string, userId as string, login as string, text as string) as string
    return "@display-name=" + login + ";id=" + id + ";user-id=" + userId + " :" + login + "!" + login + "@" + login + ".tmi.twitch.tv PRIVMSG #canned :" + text + chr(13) + chr(10)
end function

' Stands in for Chat.onNewCommentObj: records each delivery and acknowledges it.
sub scriptedRenderer(state as object)
    history = state.stateHistory
    if history.count() = 0 or history[history.count() - 1] <> m.top.deliveryState then history.push(m.top.deliveryState)
    state.stateHistory = history
    if state.waits < state.liveAt and m.top.moderation <> invalid then state.publishedBeforeLive = m.top.moderation.seq
    if m.top.nextCommentObj <> invalid
        if state.waits < state.liveAt then state.deliveredBeforeLive++
        delivered = state.delivered
        delivered.push(m.top.nextCommentObj)
        state.delivered = delivered
        times = state.deliveredAt
        times.push(state.clock - 100)
        state.deliveredAt = times
        m.top.nextCommentObj = invalid
        m.top.readyForNextComment = true
    end if
    if state.waits = state.liveAt
        m.top.forceLive = true
        m.top.readyForNextComment = true
    end if
    if state.readyAtWait > 0 and state.waits >= state.readyAtWait then m.top.readyForNextComment = true
    if state.waits >= state.stopAt then m.top.stopRequested = true
end sub

function publishedEvents() as object
    if m.top.moderation = invalid then return []
    return m.top.moderation.events
end function

function publishedSeq() as integer
    if m.top.moderation = invalid then return 0
    return m.top.moderation.seq
end function

function deliveredIds() as string
    ids = []
    for each comment in getGlobalAA().delivered
        ids.push(comment.identity.id)
    end for
    return ids.join(",")
end function

function stampsEqual(seq as integer) as boolean
    delivered = getGlobalAA().delivered
    if delivered.count() = 0 then return false
    for each comment in delivered
        if comment.moderationSeq <> seq then return false
    end for
    return true
end function

sub resetBoundary()
    m.top = { stopRequested: false, readyForNextComment: false, delaySeconds: 0, forceLive: false, channel: "canned", connectionState: "connecting" }
    m.port = invalid
    m.anonymousOnly = false
    m.moderationSeq = 0
    m.moderationLog = []
    state = getGlobalAA()
    state.socketCreated = 0
    state.socketCloses = 0
    state.webSocketCloses = 0
    state.webSocketAvailable = false
    state.webSocketOpened = false
    state.clock = 0
    state.parseCostMs = 0
    state.receiveCostMs = 0
    state.waits = 0
    state.readyAt = 0
    state.stopAt = 99
    state.hardError = false
    state.notifyRead = false
    state.notifyWrite = true
    state.peerVerified = false
    state.hostVerified = false
    state.certificates = false
    state.readMode = ""
    state.receiveCalls = 0
    state.readSuccess = false
    state.sendCalls = 0
    state.sendTimeout = 0
    state.sentText = ""
    state.sendHardError = false
    state.writeLimit = 4096
    state.sleeps = 0
    state.registryReads = 0
    state.script = []
    state.liveAt = 0
    state.delivered = []
    state.deliveredBeforeLive = 0
    state.publishedBeforeLive = 0
    state.deliveredAt = []
    state.stateHistory = []
    state.readyAtWait = 0
    state.wallBase = 1700000000
end sub

function fixtureCreateObject(name as string) as dynamic
    state = getGlobalAA()
    if name = "roWebSocket"
        if not state.webSocketAvailable then return invalid
        return {
            setMessagePort: noop
            setCertificatesFile: setCertificates
            enablePeerVerification: peerVerification
            enableHostVerification: hostVerification
            setAutoPingReply: noop
            setUrl: noop
            open: openWebSocket
            send: sendData
            close: closeWebSocket
        }
    else if name = "roStreamSocket"
        state.socketCreated++
        return {
            setMessagePort: noop
            setSendToAddress: noop
            notifyReadable: notifyRead
            notifyWritable: notifyWrite
            connect: accepted
            isConnected: staleConnected
            isWritable: writable
            eOK: okay
            eSuccess: receiveSuccess
            isReadable: accepted
            getCountRcvBuf: emptyCount
            receiveStr: receiveData
            send: sendData
            close: closeSocket
        }
    else if name = "roSocketAddress"
        return { setAddress: noop }
    else if name = "roTimespan"
        return { startedAt: state.clock, totalMilliseconds: elapsed, mark: markClock }
    else if name = "roDateTime"
        return { asSeconds: wallSeconds }
    else if name = "roByteArray" or name = "roMessagePort"
        return createObject(name)
    end if
    print "STITCH_CHAT_TRANSPORT_FAIL: unexpected object " + name
    return invalid
end function

sub fixtureSleep(milliseconds as integer)
    getGlobalAA().sleeps++
    getGlobalAA().clock += milliseconds
end sub

function sendData(data as dynamic, first as integer, length = -1 as integer) as dynamic
    state = getGlobalAA()
    state.sendCalls++
    if length < 0
        state.sendTimeout = first
        state.sentText += data
        return invalid
    end if
    if state.sendHardError
        state.hardError = true
        return 0
    end if
    written = length
    if written > state.writeLimit then written = state.writeLimit
    state.sentText += data.toAsciiString().mid(first, written)
    return written
end function

function get_user_setting(key as string, fallback as dynamic) as string
    getGlobalAA().registryReads++
    if key = "login" then return "fixtureuser"
    if key = "access_token" then return "FixtureSentinelA1"
    return fallback
end function

function fixtureWait(milliseconds as integer, port as dynamic) as dynamic
    state = getGlobalAA()
    state.waits++
    state.clock += milliseconds
    if state.readMode = "script"
        scriptedRenderer(state)
        return invalid
    end if
    if state.waits >= state.stopAt then m.top = { stopRequested: true, readyForNextComment: false, delaySeconds: 0, forceLive: false }
    return invalid
end function

sub noop(value as dynamic)
end sub

function accepted() as boolean
    return true
end function

function staleConnected() as boolean
    return false
end function

function writable() as boolean
    state = getGlobalAA()
    return state.waits >= state.readyAt
end function

function okay() as boolean
    return not getGlobalAA().hardError
end function

function emptyCount() as integer
    return 0
end function

function receiveSuccess() as boolean
    return getGlobalAA().readSuccess
end function

function receiveData(limit as integer) as string
    state = getGlobalAA()
    state.receiveCalls++
    state.readSuccess = false
    if state.readMode = "script"
        ' Past the script every read is EAGAIN, never EOF.
        if state.receiveCalls > state.script.count() then return ""
        state.readSuccess = true
        state.clock += state.receiveCostMs
        return state.script[state.receiveCalls - 1]
    end if
    if state.readMode = "error"
        state.hardError = true
        return ""
    end if
    if state.readMode = "pending" and state.receiveCalls = 1 then return ""
    state.readSuccess = true
    if state.readMode = "eof" then return ""
    if state.receiveCalls = 2 then return ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
    return "@display-name=FixtureUser :fixtureuser!fixtureuser@fixtureuser.tmi.twitch.tv PRIVMSG #canned :hello" + chr(13) + chr(10)
end function

sub notifyRead(value as boolean)
    getGlobalAA().notifyRead = value
end sub

sub notifyWrite(value as boolean)
    getGlobalAA().notifyWrite = value
end sub

sub closeSocket()
    getGlobalAA().socketCloses++
end sub

sub closeWebSocket()
    getGlobalAA().webSocketCloses++
end sub

function elapsed() as integer
    return getGlobalAA().clock - m.startedAt
end function

sub markClock()
    m.startedAt = getGlobalAA().clock
end sub

function wallSeconds() as integer
    return getGlobalAA().wallBase + int(getGlobalAA().clock / 1000)
end function

function openWebSocket(timeout as integer) as boolean
    return getGlobalAA().webSocketOpened
end function

sub setCertificates(value as string)
    getGlobalAA().certificates = value = "common:/certs/ca-bundle.crt"
end sub

sub peerVerification(value as boolean)
    getGlobalAA().peerVerified = value
end sub

sub hostVerification(value as boolean)
    getGlobalAA().hostVerified = value
end sub

sub check(condition as boolean, description as string)
    m.assertions++
    if not condition
        m.failures++
        print "STITCH_CHAT_TRANSPORT_FAIL: " + description
    end if
end sub
