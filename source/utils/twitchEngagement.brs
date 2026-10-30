' Pure validation and accounting shared by the experimental engagement worker.
function engagementNumber(value as dynamic) as boolean
    kind = type(value, 3)
    if kind <> "Integer" and kind <> "LongInteger" and kind <> "Float" and kind <> "Double" and kind <> "roInt" and kind <> "roFloat" and kind <> "roDouble" then return false
    return value = value and value >= 0 and value <= 1000000000000#
end function

function engagementId(value as dynamic) as boolean
    if GetInterface(value, "ifString") = invalid then return false
    if value.len() < 1 or value.len() > 16 then return false
    if value.left(1) = "0" then return false
    for i = 0 to value.len() - 1
        digit = asc(value.mid(i, 1))
        if digit < 48 or digit > 57 then return false
    end for
    return value <> "0"
end function

function engagementLogin(value as dynamic) as boolean
    if GetInterface(value, "ifString") = invalid then return false
    return createObject("roRegex", "^[a-z0-9_]{1,25}$", "").isMatch(value)
end function

function engagementWatchState() as object
    return { elapsedMs: 0#, minutes: 0, last: invalid }
end function

' Receipt of a fresh playing sample is required. Position jumps, stale samples,
' stalls and lifecycle changes never become watched time or catch-up reports.
function engagementWatchStep(state as object, sample as dynamic) as object
    state.due = false
    if GetInterface(sample, "ifAssociativeArray") = invalid then return state
    if not engagementNumber(sample.sequence) or not engagementNumber(sample.timeMs) then return state
    if state.last <> invalid and sample.sequence <= state.last.sequence then return state
    previous = state.last
    state.last = { sequence: sample.sequence, timeMs: sample.timeMs, generation: sample.generation, position: sample.position, playing: sample.playing = true and engagementNumber(sample.position) }
    if sample.playing <> true or not engagementNumber(sample.position)
        return state
    end if
    if previous = invalid or previous.playing <> true then return state
    if sample.generation <> previous.generation or not engagementNumber(previous.position) then return state
    interval = sample.timeMs - previous.timeMs
    progress = (sample.position - previous.position) * 1000#
    if interval <= 0 or interval > 5000 or progress <= 0 or progress > interval + 1000 then return state
    if progress < interval then interval = progress
    state.elapsedMs += interval
    if state.elapsedMs >= 60000
        state.elapsedMs -= 60000
        state.minutes++
        state.due = true
    end if
    return state
end function

function engagementUtcSeconds(value as dynamic) as dynamic
    if GetInterface(value, "ifString") = invalid then return invalid
    if value.len() > 30 then return invalid
    ' Twitch currently emits nanoseconds; the existing parser validates calendar
    ' dates and microseconds. Truncation does not extend the expiry.
    if value.len() > 27
        if not createObject("roRegex", "^[0-9T:.-]+[.][0-9]{7,9}Z$", "").isMatch(value) then return invalid
        value = value.left(26) + "Z"
    end if
    micros = tadUtcUs(value)
    if micros = invalid then return invalid
    return micros \ 1000000&
end function

function engagementHypeTrain(execution as dynamic, nowSeconds as double) as dynamic
    if GetInterface(execution, "ifAssociativeArray") = invalid then return invalid
    if GetInterface(execution.id, "ifString") = invalid then return invalid
    if not createObject("roRegex", "^[A-Za-z0-9_-]{1,80}$", "").isMatch(execution.id) then return invalid
    progress = execution.progress
    if GetInterface(progress, "ifAssociativeArray") = invalid then return invalid
    if GetInterface(progress.level, "ifAssociativeArray") = invalid then return invalid
    level = progress.level.value
    amount = progress.progression
    goal = progress.goal
    if not engagementNumber(level) or not engagementNumber(amount) or not engagementNumber(goal) then return invalid
    if level < 1 or level > 10000 or level <> int(level) or goal < 1 then return invalid
    level = int(level)
    expiry = engagementUtcSeconds(execution.expiresAt)
    if expiry = invalid then return invalid
    status = "active"
    if execution.endedAt <> invalid
        ended = engagementUtcSeconds(execution.endedAt)
        if ended = invalid or ended > nowSeconds + 5 or ended < nowSeconds - 20 then return invalid
        expiry = ended + 20
        status = "ended"
    else if expiry <= nowSeconds or expiry > nowSeconds + 3600
        return invalid
    end if
    percent = 100
    if amount < goal then percent = int((amount / goal) * 100#)
    return { id: execution.id, level: level, progress: amount, goal: goal, percent: percent, expiresAt: expiry, observedAt: nowSeconds, status: status, shared: execution.sharedHypeTrainDetails <> invalid }
end function

function engagementSnapshot(body as dynamic, channelId as string, nowSeconds as double) as dynamic
    if GetInterface(body, "ifAssociativeArray") = invalid then return invalid
    if body.errors <> invalid then return invalid
    if GetInterface(body.data, "ifAssociativeArray") = invalid then return invalid
    user = body.data.user
    if GetInterface(user, "ifAssociativeArray") = invalid then return invalid
    if user.id <> channelId then return invalid
    broadcastId = ""
    if user.stream <> invalid
        if GetInterface(user.stream, "ifAssociativeArray") = invalid then return invalid
        if not engagementId(user.stream.id) then return invalid
        broadcastId = user.stream.id
    end if
    return { broadcastId: broadcastId, hypeTrain: engagementHypeTrain(user?.channel?.hypeTrain?.execution, nowSeconds) }
end function

' An empty connection is a successful unpin; malformed responses are failures.
function engagementPinSnapshot(body as dynamic, channelId as string, nowSeconds as double) as dynamic
    if GetInterface(body, "ifAssociativeArray") = invalid then return invalid
    if body.errors <> invalid then return invalid
    if GetInterface(body.data, "ifAssociativeArray") = invalid then return invalid
    channel = body.data.channel
    if GetInterface(channel, "ifAssociativeArray") = invalid then return invalid
    if channel.id <> channelId then return invalid
    if GetInterface(channel.pinnedChatMessages, "ifAssociativeArray") = invalid then return invalid
    edges = channel.pinnedChatMessages.edges
    if GetInterface(edges, "ifArray") = invalid then return invalid
    if edges.count() = 0 then return { pinnedMessage: invalid }
    if edges.count() <> 1 then return invalid
    if GetInterface(edges[0], "ifAssociativeArray") = invalid then return invalid
    pin = engagementPinnedMessage(edges[0].node, nowSeconds)
    if pin = invalid then return invalid
    return { pinnedMessage: pin }
end function

function engagementPinId(value as dynamic) as boolean
    if GetInterface(value, "ifString") = invalid then return false
    return createObject("roRegex", "^[A-Za-z0-9_-]{1,80}$", "").isMatch(value)
end function

' Local metadata limits: inspect at most 32 entries and retain 8 unique pairs.
' Optional malformed badges never invalidate a pin; keys only resolve existing catalogs.
function engagementPinBadges(value as dynamic) as object
    badges = []
    if GetInterface(value, "ifArray") = invalid then return badges
    entryCount = value.count()
    if entryCount > 32 then entryCount = 32
    invalidToken = createObject("roRegex", "[^A-Za-z0-9_-]", "")
    for i = 0 to entryCount - 1
        badge = value[i]
        if GetInterface(badge, "ifAssociativeArray") = invalid then continue for
        setId = badge.setID
        version = badge.version
        if GetInterface(setId, "ifString") = invalid or GetInterface(version, "ifString") = invalid then continue for
        if setId.len() < 1 or setId.len() > 80 or version.len() < 1 or version.len() > 80 then continue for
        if invalidToken.isMatch(setId) or invalidToken.isMatch(version) then continue for
        key = setId + "/" + version
        duplicate = false
        for each existing in badges
            if existing = key then duplicate = true
        end for
        if not duplicate then badges.push(key)
        if badges.count() = 8 then exit for
    end for
    return badges
end function

function engagementPinnedMessage(node as dynamic, nowSeconds as double) as dynamic
    if GetInterface(node, "ifAssociativeArray") = invalid then return invalid
    if node.type <> "MOD" or not engagementPinId(node.id) then return invalid
    message = node.pinnedMessage
    if GetInterface(message, "ifAssociativeArray") = invalid then return invalid
    if not engagementPinId(message.id) then return invalid
    sender = message.sender
    if GetInterface(sender, "ifAssociativeArray") = invalid then return invalid
    if not engagementId(sender.id) or not engagementLogin(sender.login) then return invalid
    name = sender.displayName
    if GetInterface(name, "ifString") = invalid or name = "" then name = sender.login
    if name.len() > 128 then return invalid
    if GetInterface(message.content, "ifAssociativeArray") = invalid then return invalid
    text = message.content.text
    if GetInterface(text, "ifString") = invalid then return invalid
    if text.trim() = "" or text.len() > 1500 then return invalid
    startsAt = engagementUtcSeconds(node.startsAt)
    updatedAt = engagementUtcSeconds(node.updatedAt)
    sentAt = engagementUtcSeconds(message.sentAt)
    if startsAt = invalid or updatedAt = invalid or sentAt = invalid then return invalid
    if startsAt > nowSeconds + 5 or updatedAt > nowSeconds + 5 or updatedAt < startsAt or sentAt > startsAt + 5 then return invalid
    if not node.doesExist("endsAt") then return invalid
    expiresAt = invalid
    if node.endsAt <> invalid
        expiresAt = engagementUtcSeconds(node.endsAt)
        if expiresAt = invalid then return invalid
        if expiresAt <= nowSeconds or expiresAt <= startsAt or expiresAt > nowSeconds + 86400 then return invalid
    end if
    return { id: node.id, messageId: message.id, userId: sender.id, login: sender.login, senderName: name.replace(chr(13), " ").replace(chr(10), " "), badges: engagementPinBadges(message.senderBadges), text: text.replace(chr(13), ""), sentAt: sentAt, updatedAt: updatedAt, expiresAt: expiresAt, observedAt: nowSeconds }
end function

function engagementSettingsUrl(page as string) as dynamic
    matches = createObject("roRegex", "https://assets[.]twitch[.]tv/config/settings[.][a-f0-9]{16,64}[.]js", "").match(page)
    if matches.count() = 0 then return invalid
    return matches[0]
end function

function engagementBeaconUrl(settings as string) as dynamic
    matches = createObject("roRegex", chr(34) + "beacon_url" + chr(34) + ":" + chr(34) + "([^" + chr(34) + "]+)" + chr(34), "").match(settings)
    if matches.count() <> 2 then return invalid
    if matches[1] <> "https://beacon.twitch.tv/track" then return invalid
    return matches[1]
end function

function engagementMinuteBody(userId as string, channelId as string, broadcastId as string, login as string, sessionId as string, minutes as integer) as dynamic
    if not engagementId(userId) or not engagementId(channelId) or not engagementId(broadcastId) then return invalid
    if not engagementLogin(login) or sessionId = "" or minutes < 1 then return invalid
    ' The observed telemetry contract uses a numeric user ID. Accumulate in
    ' 64 bits rather than ToInt/Val, which can truncate or round newer IDs.
    userNumber = 0&
    for i = 0 to userId.len() - 1
        userNumber = userNumber * 10& + asc(userId.mid(i, 1)) - 48&
    end for
    ' "site" is the observed telemetry player discriminator. Keep the actual
    ' backend explicit; this is an experimental compatibility request.
    event = {
        "event": "minute-watched",
        "properties": {
            "user_id": userNumber,
            "channel_id": channelId,
            "broadcast_id": broadcastId,
            "channel": login,
            "player": "site",
            "backend": "roku_scenegraph",
            "live": true,
            "play_session_id": sessionId,
            "minutes_logged": minutes,
            "seconds_offset": 0
        }
    }
    bytes = createObject("roByteArray")
    bytes.fromAsciiString(formatJson([event]))
    return "data=" + bytes.toBase64String().encodeUriComponent()
end function
