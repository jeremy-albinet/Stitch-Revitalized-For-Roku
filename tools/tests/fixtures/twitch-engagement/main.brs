sub main()
    m.assertions = 0
    m.failures = 0
    setup("normal")
    runWorkerMain()
    check(m.attempts = 1 and m.accepted = 1 and m.watch.minutes = 1, "one real minute submits once")
    check(getGlobalAA().gqlCalls > 1 and m.top.control = "stop", "metadata is refreshed and worker stops")
    check(m.top.response.watchState = "telemetry_accepted" and m.top.response.hypeTrain.level = 3, "transport result and real snapshot shape stay separate")
    check(getGlobalAA().posted.properties.broadcast_id = "777" and getGlobalAA().posted.properties.user_id = 900, "validated identity and current broadcast reach the beacon")
    setup("zero-expiry")
    runWorkerMain()
    check(m.attempts = 1 and m.userId = "900", "a successful TV validation with zero expiry can report actual viewing")
    setup("zero-revoked")
    getGlobalAA().limit = 3310
    runWorkerMain()
    check(getGlobalAA().validations = 2 and m.userId = "" and m.watchState = "identity_unavailable", "zero-expiry identities are revalidated within an hour and revocation ends reporting")
    check(m.attempts = 54, "no completed minute is submitted after failed revalidation")
    check(getGlobalAA().tick = 3310 and m.top.response.hypeState <> "disabled", "revoked credentials do not terminate public chat polling")
    setup("initial-retry")
    getGlobalAA().limit = 100
    runWorkerMain()
    check(getGlobalAA().validations = 2 and getGlobalAA().validationTicks[1] >= 30 and m.attempts = 1, "an initial validation timeout retries on backoff and later reports real viewing")
    setup("revalidation-retry")
    getGlobalAA().limit = 3370
    runWorkerMain()
    check(getGlobalAA().validations = 3 and getGlobalAA().validationTicks[2] - getGlobalAA().validationTicks[1] >= 30, "a 503 revalidation retries after backoff")
    check(m.attempts = 56 and m.userId = "900", "a transient revalidation failure preserves the valid identity lease and the following minute")
    for each mode in ["revoked", "client-mismatch", "login-mismatch"]
        setup(mode)
        runWorkerMain()
        check(m.authTerminal and m.attempts = 0 and getGlobalAA().validations = 1, "a refused or mismatched identity cannot retry credentialed reporting")
        check(m.top.response.hypeTrain <> invalid and m.top.response.pinnedMessage <> invalid, "terminal watch refusal leaves both public chat features running")
    end for
    setup("jitter")
    getGlobalAA().limit = 130
    runWorkerMain()
    check(m.attempts = 2 and m.accepted = 2, "minor query jitter delays rather than loses the next completed minute")

    setup("paused")
    runWorkerMain()
    check(m.attempts = 0, "pause does not add a completed minute")
    setup("stalled")
    runWorkerMain()
    check(m.attempts = 0, "playing with no progress never reports")
    setup("seek")
    runWorkerMain()
    check(m.attempts = 0, "seek jumps cannot add viewed minutes")
    setup("logout")
    runWorkerMain()
    check(m.attempts = 0 and m.watchState = "account_changed", "logout stops the old account before a minute is sent")
    setup("broadcast-change")
    runWorkerMain()
    check(m.attempts = 0 and m.watch.minutes = 0 and m.broadcastId = "888", "a changed broadcast discards the pending old minute")
    setup("expiry")
    runWorkerMain()
    check(m.attempts = 0 and m.watchState = "identity_retry" and not engagementWatchAuthorized(), "expired validation lease suspends reporting without killing public polls")
    check(m.top.response.hypeTrain <> invalid, "public polling survives an expired validation lease")
    setup("refused")
    getGlobalAA().limit = 130
    runWorkerMain()
    check(m.attempts = 2 and m.accepted = 0 and m.httpStatus = 503, "ambiguous or rejected telemetry is not retried or counted as credit")
    setup("stop-before-send")
    runWorkerMain()
    check(m.attempts = 0, "a stop during metadata resolution prevents telemetry")
    setup("untrusted-beacon")
    runWorkerMain()
    check(m.attempts = 0 and m.beacon = invalid, "discovery cannot send data to an arbitrary host")
    setup("hype-only")
    runWorkerMain()
    check(getGlobalAA().tokenReads = 0 and getGlobalAA().validations = 0 and getGlobalAA().discoveries = 0 and m.attempts = 0, "anonymous Hype Train reads never touch account credentials or telemetry")
    check(m.top.response.hypeTrain.level = 3, "public Hype Train snapshot works independently of sign-in")
    setup("pins-only")
    runWorkerMain()
    check(getGlobalAA().tokenReads = 0 and getGlobalAA().validations = 0 and getGlobalAA().discoveries = 0 and m.attempts = 0, "anonymous pins never access account credentials or telemetry")
    check(m.top.response.pinnedMessage.text = "Read this first" and getGlobalAA().pinCalls > 1, "pins-only chat polls independently without a Hype Train setting")
    check(m.top.response.pinnedMessage.badges.count() = 0, "pins without badge metadata publish an empty badges array")
    setup("pins-badges")
    runWorkerMain()
    check(m.pinState = "active" and getGlobalAA().pinCalls > 1 and m.top.response.pinnedMessage.senderName = "JOURDA1N", "the actual worker accepts the observed author badge pin")
    check(formatJson(m.top.response.pinnedMessage.badges) = formatJson(["moderator/1", "subscriber/2042", "gamerduo/1"]), "the actual worker publishes observed badge keys in provider order")
    check(getGlobalAA().tokenReads = 0 and getGlobalAA().validations = 0 and getGlobalAA().discoveries = 0 and m.attempts = 0, "observed author badges use only the public pin request")
    setup("pins-refused")
    runWorkerMain()
    check(m.attempts = 1 and m.accepted = 1 and m.top.response.pinnedMessage = invalid and m.pinState = "unavailable", "pin schema failures cannot stop legitimate watch reports")
    setup("pin-metadata-fail")
    getGlobalAA().limit = 12
    runWorkerMain()
    check(m.top.response.pinnedMessage <> invalid and m.pinState = "active" and not m.snapshotValid, "a failed broadcast query preserves the existing independently fetched pin")
    pinTime = m.pin.observedAt
    m.top.stopRequested = false
    pollPinnedChat()
    check(m.pin <> invalid and m.pin.observedAt = pinTime and m.pinState = "active", "unavailable broadcast metadata cannot clear or refresh a cached pin")
    for each mode in ["prequery-fail", "pause-during-submit"]
        setup(mode)
        getGlobalAA().limit = 130
        runWorkerMain()
        check(m.attempts = 1 and getGlobalAA().posted.properties.minutes_logged = 1, "an earned minute survives " + mode)
        check(getGlobalAA().postTimes[0] >= 120000, "pre-submit failure or pause backs off before retrying the same minute")
    end for
    for each mode in ["prequery-change", "prequery-offline"]
        setup(mode)
        runWorkerMain()
        check(m.attempts = 0 and m.pendingBroadcast = "" and m.watch.minutes = 0, "a confirmed broadcast change or offline state discards old earned credit")
    end for
    setup("queued-minutes")
    getGlobalAA().limit = 185
    runWorkerMain()
    check(m.attempts = 1 and getGlobalAA().posted.properties.minutes_logged = 1 and m.watch.minutes = 3 and m.nextMinute = 2 and m.pendingBroadcast <> "", "multiple earned minutes remain queued in order without a catch-up burst")
    setup("slow-io")
    getGlobalAA().limit = 130
    runWorkerMain()
    check(m.watch.minutes = 2 and m.watch.elapsedMs >= 8000 and m.attempts = 2, "fresh samples are collected during slow query and POST waits")
    check(getGlobalAA().postTimes[1] - getGlobalAA().postTimes[0] >= 60000, "slow I/O recovery still obeys the submission floor")
    setup("slow-stall")
    getGlobalAA().limit = 130
    runWorkerMain()
    check(m.watch.minutes = 1, "sampling during HTTP cannot count a real playback stall")
    setup("missing-device")
    runWorkerMain()
    check(getGlobalAA().gqlCalls = 0 and getGlobalAA().validations = 0 and m.watchState = "unavailable", "missing device identity performs no network work")

    ' An immediate second attempt must be refused regardless of accumulated state.
    setup("normal")
    runWorkerMain()
    m.top.stopRequested = false
    m.top.sample = playingSample(65)
    m.watch.minutes++
    reportEngagementMinute()
    check(m.attempts = 1, "a caller cannot burst another submission inside the minute floor")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

sub setup(mode as string)
    state = getGlobalAA()
    state.mode = mode
    state.tick = 0
    state.limit = 65
    state.nowMs = 0
    state.registryAccount = "viewer"
    state.gqlCalls = 0
    state.validations = 0
    state.validationTicks = []
    state.discoveries = 0
    state.tokenReads = 0
    state.posted = invalid
    state.pinCalls = 0
    state.prequeryCalls = 0
    state.prequeryHandled = false
    state.slowPoll = false
    state.slowPost = false
    state.postTimes = []
    m.top = { owner: "fixture-owner", channel: "canned", channelId: "101", watchEnabled: true, hypeEnabled: true, pinsEnabled: false, stopRequested: false, sample: playingSample(0) }
    if mode = "hype-only"
        m.top.watchEnabled = false
        state.registryAccount = "$default$"
    end if
    if mode = "pins-only" or mode = "pins-refused" or mode = "pins-badges"
        m.top.hypeEnabled = false
        m.top.pinsEnabled = true
        if mode <> "pins-refused"
            m.top.watchEnabled = false
            state.registryAccount = "$default$"
        end if
    end if
    if mode = "pins-badges"
        state.pinFixture = parseJson(readAsciiFile("pkg:/pinned-author-badges.json"))
        m.top.channelId = "155586958"
    end if
    if mode = "initial-retry" then m.top.hypeEnabled = false
    if mode = "revoked" or mode = "client-mismatch" or mode = "login-mismatch" or mode = "pin-metadata-fail" then m.top.pinsEnabled = true
end sub

function playingSample(tick as integer) as object
    position = tick
    if getGlobalAA().mode = "stalled" then position = 0
    if getGlobalAA().mode = "seek" then position = tick + int(tick / 10) * 100
    if getGlobalAA().mode = "slow-stall" and tick >= 60 and tick <= 72 then position = 59
    playing = true
    if getGlobalAA().mode = "paused" and tick >= 10 and tick <= 35 then playing = false
    if getGlobalAA().mode = "pause-during-submit" and getGlobalAA().prequeryHandled and tick >= 60 and tick < 75 then playing = false
    return { sequence: tick, generation: 1, timeMs: tick * 1000#, position: position, playing: playing }
end function

function fixtureWait(milliseconds as integer, port as dynamic) as dynamic
    state = getGlobalAA()
    state.tick++
    state.nowMs = state.tick * 1000#
    if state.mode = "logout" and state.tick = 59 then state.registryAccount = "$default$"
    m.top.sample = playingSample(state.tick)
    if state.tick >= state.limit then m.top.stopRequested = true
    return invalid
end function

function fixtureCreateObject(name as string) as dynamic
    if name = "roMessagePort" then return invalid
    if name = "roTimespan" then return { totalMilliseconds: fixtureMilliseconds }
    if name = "roDateTime" then return { asSeconds: fixtureSeconds }
    check(false, "unexpected native object at worker boundary")
    return invalid
end function

function fixtureMilliseconds() as double
    return getGlobalAA().nowMs
end function

function fixtureSeconds() as double
    if getGlobalAA().mode = "pins-badges" then return getGlobalAA().pinFixture.fixtureNowSeconds + getGlobalAA().tick
    return engagementUtcSeconds("2026-10-24T03:45:00Z") + getGlobalAA().tick
end function

function get_setting(key as string, fallback as dynamic) as dynamic
    return getGlobalAA().registryAccount
end function

function get_user_setting(key as string, fallback as dynamic) as dynamic
    if key = "device_code"
        if getGlobalAA().mode = "missing-device" then return ""
        return "fixture-device"
    end if
    if key = "access_token"
        getGlobalAA().tokenReads++
        return "FixturePrivateToken"
    end if
    return fallback
end function

function fixtureHttp(url as string, method as string, headers as object, body as dynamic, maxBytes as integer) as dynamic
    state = getGlobalAA()
    if url = "https://id.twitch.tv/oauth2/validate"
        state.validations++
        state.validationTicks.push(state.tick)
        if state.mode = "initial-retry" and state.validations = 1 then return invalid
        if state.mode = "revalidation-retry" and state.validations = 2 then return { status: 503, body: "{}" }
        if state.mode = "expiry" and state.validations > 1 then return { status: 503, body: "{}" }
        if state.mode = "revoked" then return { status: 403, body: "{}" }
        expiry = 3600
        if state.mode = "expiry" then expiry = 61
        if state.mode = "zero-expiry" or state.mode = "zero-revoked" then expiry = 0
        if state.mode = "zero-revoked" and state.validations > 1 then return { status: 401, body: "{}" }
        login = "viewer"
        client = "ue6666qo983tsx6so1t0vnawi233wa"
        if state.mode = "client-mismatch" then client = "another-client"
        if state.mode = "login-mismatch" then login = "another-viewer"
        return { status: 200, body: formatJson({ user_id: "900", login: login, client_id: client, expires_in: expiry }) }
    else if url = "https://gql.twitch.tv/gql"
        state.gqlCalls++
        if state.mode = "jitter" and state.tick = 60 then state.nowMs += 25
        check(headers["Client-Id"] = "ue6666qo983tsx6so1t0vnawi233wa" and headers["Device-ID"] = "fixture-device", "metadata carries both required headers")
        request = parseJson(body)
        if request.query.instr("StitchPinnedChat") >= 0
            state.pinCalls++
            check(request.variables.doesExist("channelID") and request.variables.channelID = m.top.channelId, "pin queries preserve the native channelID wire key")
            check(request.query.instr("sender { id login displayName } senderBadges { setID version }") >= 0, "pin query selects message sender badge pairs")
            check(not headers.doesExist("Authorization"), "public pin query carries no viewer credential")
            if state.mode = "pins-refused" then return { status: 200, body: formatJson({ errors: [{ message: "schema changed" }] }) }
            if state.mode = "pins-badges" then return { status: 200, body: formatJson(state.pinFixture.response) }
            pin = { id: "pin-1", type: "MOD", startsAt: "2026-10-24T03:44:00Z", updatedAt: "2026-10-24T03:44:00Z", endsAt: invalid, pinnedMessage: { id: "message-1", sentAt: "2026-10-24T03:43:00Z", content: { text: "Read this first" }, sender: { id: "202", login: "moderator", displayName: "Moderator" } } }
            return { status: 200, body: formatJson({ data: { channel: { id: "101", pinnedChatMessages: { edges: [{ node: pin }] } } } }) }
        end if
        if state.mode = "pin-metadata-fail" and state.tick >= 10 then return { status: 503, body: "{}" }
        if (state.mode = "slow-io" or state.mode = "slow-stall") and state.tick >= 60 and not state.slowPoll
            state.slowPoll = true
            fixtureNetworkSeconds(6)
        end if
        check(request.variables.doesExist("includeHype"), "current metadata request preserves includeHype wire case")
        broadcastId = "777"
        if state.mode = "broadcast-change" and state.tick >= 45 then broadcastId = "888"
        if m.pendingBroadcast <> "" then state.prequeryCalls++
        if m.pendingBroadcast <> "" and not state.prequeryHandled
            state.prequeryHandled = true
            if state.mode = "prequery-fail" then return { status: 503, body: "{}" }
            if state.mode = "pause-during-submit" then m.top.sample = playingSample(state.tick)
        end if
        if state.mode = "queued-minutes" and m.pendingBroadcast <> "" and state.tick < 180 and m.nextReportCheckMs = state.nowMs + 60000
            pause = playingSample(state.tick)
            pause.playing = false
            m.top.sample = pause
        end if
        if state.prequeryHandled and state.mode = "prequery-change" then broadcastId = "888"
        stream = { id: broadcastId }
        if state.prequeryHandled and state.mode = "prequery-offline" then stream = invalid
        if state.mode = "stop-before-send" and state.tick >= 60 then m.top.stopRequested = true
        execution = { id: "train", startedAt: "2026-10-24T03:40:35Z", expiresAt: "2026-10-24T03:48:12.519249618Z", endedAt: invalid, progress: { goal: 5300, level: { value: 3 }, progression: 1000 }, sharedHypeTrainDetails: invalid }
        channel = invalid
        if request.variables.includeHype then channel = { hypeTrain: { execution: execution } }
        return { status: 200, body: formatJson({ data: { user: { id: m.top.channelId, stream: stream, channel: channel } } }) }
    else if url = "https://www.twitch.tv/canned"
        state.discoveries++
        return { status: 200, body: "https://assets.twitch.tv/config/settings.0123456789abcdef.js" }
    else if url = "https://assets.twitch.tv/config/settings.0123456789abcdef.js"
        target = "https://beacon.twitch.tv/track"
        if state.mode = "untrusted-beacon" then target = "https://evil.test/track"
        return { status: 200, body: formatJson({ beacon_url: target }) }
    else if url = "https://beacon.twitch.tv/track"
        state.postTimes.push(state.nowMs)
        if (state.mode = "slow-io" or state.mode = "slow-stall") and not state.slowPost
            state.slowPost = true
            fixtureNetworkSeconds(6)
        end if
        check(method = "POST" and not headers.doesExist("Authorization"), "beacon receives no authorization header")
        check(body.instr("FixturePrivateToken") < 0 and body.instr("fixture-device") < 0, "beacon body excludes credentials")
        bytes = createObject("roByteArray")
        bytes.fromBase64String(body.mid(5).replace("%3D", "=").replace("%2B", "+").replace("%2F", "/"))
        event = parseJson(bytes.toAsciiString())[0]
        check(not event.properties.doesExist("access_token") and not event.properties.doesExist("device_code"), "decoded beacon event excludes credentials")
        state.posted = event
        status = 204
        if state.mode = "refused" then status = 503
        return { status: status, body: "" }
    end if
    check(false, "unexpected external request")
    return invalid
end function

sub fixtureNetworkSeconds(seconds as integer)
    for i = 1 to seconds
        fixtureWait(1000, invalid)
        collectEngagementWatch()
    end for
end sub

sub check(condition as boolean, description as string)
    m.assertions++
    if not condition
        m.failures++
        print "STITCH_ENGAGEMENT_FAIL: " + description
    end if
end sub
