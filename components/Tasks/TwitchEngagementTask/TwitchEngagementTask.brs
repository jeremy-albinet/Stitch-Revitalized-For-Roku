sub init()
    m.top.functionName = "main"
end sub

sub main()
    try
        runEngagement()
    catch e
        if not m.top.stopRequested
            m.top.response = { owner: m.top.owner, watchState: "unavailable", hypeState: "unavailable", hypeTrain: invalid, pinnedMessage: invalid, pinState: "unavailable" }
        end if
    end try
    m.top.control = "stop"
end sub

sub runEngagement()
    if m.top.stopRequested then return
    m.clock = createObject("roTimespan")
    m.port = createObject("roMessagePort")
    m.account = get_setting("active_user", "$default$")
    m.deviceId = get_user_setting("device_code", "")
    m.token = ""
    m.userId = ""
    m.beacon = invalid
    m.broadcastId = ""
    m.watch = engagementWatchState()
    m.hype = invalid
    m.pin = invalid
    m.pinState = "disabled"
    m.nextPinPoll = 0
    m.attempts = 0
    m.accepted = 0
    m.httpStatus = 0
    m.watchState = "disabled"
    m.hypeState = "disabled"
    m.nextPoll = 0
    m.nextDiscovery = 0
    m.snapshotValid = false
    m.lastAttemptMs = -60000
    m.pendingBroadcast = ""
    m.nextMinute = 1
    m.nextReportCheckMs = 0#
    m.authExpiresMs = 0#
    m.nextValidationMs = 0#
    m.validationRetryMs = 30000
    m.authTerminal = false
    if not engagementLogin(m.top.channel) or not engagementId(m.top.channelId) or m.deviceId = ""
        m.watchState = "unavailable"
        publishEngagement()
        return
    end if
    if m.top.watchEnabled
        m.watchState = "signed_out"
        if m.account <> "$default$"
            m.token = get_user_setting("access_token", "")
            if m.token <> "" then validateEngagementAccount()
        end if
    end if
    publishEngagement()
    while not m.top.stopRequested
        if not engagementAccountCurrent()
            m.watchState = "account_changed"
            m.hype = invalid
            m.pin = invalid
            publishEngagement()
            exit while
        end if
        nowMs = m.clock.totalMilliseconds()
        if m.top.watchEnabled and m.token <> "" and not m.authTerminal and nowMs >= m.nextValidationMs
            validateEngagementAccount()
            publishEngagement()
        end if
        if nowMs >= m.nextPoll and (m.top.hypeEnabled or m.top.pinsEnabled or m.userId <> "")
            pollEngagement()
            interval = 30000
            if m.hype <> invalid then interval = 10000
            m.nextPoll = m.clock.totalMilliseconds() + interval
            publishEngagement()
        end if
        if m.top.pinsEnabled and m.clock.totalMilliseconds() >= m.nextPinPoll
            pollPinnedChat()
            m.nextPinPoll = m.clock.totalMilliseconds() + 15000
            publishEngagement()
        else if not m.top.pinsEnabled and m.pinState <> "disabled"
            m.pin = invalid
            m.pinState = "disabled"
            publishEngagement()
        end if
        if engagementWatchAuthorized() and m.snapshotValid and m.broadcastId <> ""
            if m.beacon = invalid and nowMs >= m.nextDiscovery
                discoverEngagementBeacon()
                m.nextDiscovery = m.clock.totalMilliseconds() + 60000
                publishEngagement()
            end if
            if m.beacon <> invalid
                collectEngagementWatch()
                if m.pendingBroadcast <> "" and m.clock.totalMilliseconds() >= m.nextReportCheckMs and m.clock.totalMilliseconds() - m.lastAttemptMs >= 60000 and m.top.sample?.playing = true
                    ' Refresh the actual broadcast before any submission. A new
                    ' broadcast discards the old partial minute and pending send.
                    earnedBroadcast = m.pendingBroadcast
                    m.nextReportCheckMs = m.clock.totalMilliseconds() + 60000
                    pollEngagement()
                    if m.snapshotValid and m.broadcastId = earnedBroadcast and engagementAccountCurrent() and not m.top.stopRequested
                        reportEngagementMinute()
                    end if
                    publishEngagement()
                end if
            end if
        else
            watch = m.watch
            watch.last = invalid
            m.watch = watch
        end if
        if not m.top.hypeEnabled and m.hype <> invalid
            m.hype = invalid
            m.hypeState = "disabled"
            publishEngagement()
        end if
        wait(250, m.port)
    end while
    m.top.control = "stop"
end sub

function engagementAccountCurrent() as boolean
    if get_setting("active_user", "$default$") <> m.account then return false
    if not m.top.watchEnabled then return true
    return get_user_setting("access_token", "") = m.token
end function

function engagementWatchAuthorized() as boolean
    return m.top.watchEnabled and not m.authTerminal and m.userId <> "" and m.clock.totalMilliseconds() < m.authExpiresMs and engagementAccountCurrent()
end function

' Also called from HTTP waits: network latency must not coalesce otherwise
' fresh Video samples into a gap that looks like a playback stall.
sub collectEngagementWatch()
    if m.top.stopRequested or m.beacon = invalid or not m.snapshotValid or m.broadcastId = "" then return
    if not engagementWatchAuthorized() then return
    m.watch = engagementWatchStep(m.watch, m.top.sample)
    if m.watch.due then m.pendingBroadcast = m.broadcastId
end sub

sub validateEngagementAccount()
    rsp = engagementHttp("https://id.twitch.tv/oauth2/validate", "GET", { Authorization: "OAuth " + m.token }, invalid, 32768)
    ' A transport failure cannot revoke a previously validated identity. Its
    ' original lease still bounds reporting; failures never extend that lease.
    m.watchState = "identity_retry"
    m.nextValidationMs = m.clock.totalMilliseconds() + m.validationRetryMs
    m.validationRetryMs *= 2
    if m.validationRetryMs > 300000 then m.validationRetryMs = 300000
    if rsp <> invalid
        if rsp.status = 401 or rsp.status = 403
            refuseEngagementIdentity()
            return
        end if
    end if
    if rsp = invalid or rsp.status <> 200 then return
    identity = parseJson(rsp.body)
    if GetInterface(identity, "ifAssociativeArray") = invalid then return
    if not engagementId(identity.user_id) then return
    if identity.client_id <> "ue6666qo983tsx6so1t0vnawi233wa" or identity.login <> m.account or (m.userId <> "" and identity.user_id <> m.userId)
        refuseEngagementIdentity()
        return
    end if
    if not engagementNumber(identity.expires_in) then return
    if identity.expires_in > 0 and identity.expires_in < 60
        refuseEngagementIdentity()
        return
    end if
    ' The TV grant can validate with a zero expiry. Trust the successful
    ' validation for a bounded hour and revalidate before that lease ends.
    lifetime = identity.expires_in
    if lifetime = 0 then lifetime = 3600
    m.userId = identity.user_id
    m.authExpiresMs = m.clock.totalMilliseconds() + (lifetime - 30) * 1000#
    m.nextValidationMs = m.clock.totalMilliseconds() + 3300000#
    if m.nextValidationMs > m.authExpiresMs then m.nextValidationMs = m.authExpiresMs
    m.validationRetryMs = 30000
    m.watchState = "initializing"
end sub

sub refuseEngagementIdentity()
    m.userId = ""
    m.authTerminal = true
    m.authExpiresMs = 0#
    m.pendingBroadcast = ""
    m.watch = engagementWatchState()
    m.watchState = "identity_unavailable"
end sub

sub pollEngagement()
    if m.top.stopRequested then return
    headers = { "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa", "Device-ID": m.deviceId, "Content-Type": "application/json" }
    rsp = engagementHttp("https://gql.twitch.tv/gql", "POST", headers, formatJson({
        "query": "query StitchEngagement($login: String!, $includeHype: Boolean!) { user(login: $login) { id stream { id } channel @include(if: $includeHype) { hypeTrain { execution { id startedAt expiresAt endedAt endReason progress { progression goal total level { value goal } } sharedHypeTrainDetails { id } } } } } }",
        "variables": { "login": m.top.channel, "includeHype": m.top.hypeEnabled }
    }), 131072)
    snapshot = invalid
    if rsp <> invalid and rsp.status = 200
        snapshot = engagementSnapshot(parseJson(rsp.body), m.top.channelId, createObject("roDateTime").asSeconds())
    end if
    m.snapshotValid = snapshot <> invalid
    if snapshot = invalid
        m.hype = invalid
        m.hypeState = "unavailable"
        watch = m.watch
        watch.last = invalid
        m.watch = watch
        return
    end if
    if m.broadcastId <> snapshot.broadcastId
        m.broadcastId = snapshot.broadcastId
        m.watch = engagementWatchState()
        m.pendingBroadcast = ""
        m.nextMinute = 1
        m.nextReportCheckMs = 0#
        m.pin = invalid
        m.pinState = "disabled"
        if m.top.pinsEnabled then m.pinState = "inactive"
        m.nextPinPoll = 0
    end if
    if m.userId <> "" and m.broadcastId = "" then m.watchState = "stream_offline"
    m.hype = snapshot.hypeTrain
    m.hypeState = "inactive"
    if not m.top.hypeEnabled then m.hypeState = "disabled"
    if m.hype <> invalid then m.hypeState = m.hype.status
end sub

' Pin failures never invalidate the separate playback/broadcast snapshot.
sub pollPinnedChat()
    if m.top.stopRequested then return
    if not m.snapshotValid or m.broadcastId = "" then return
    m.pin = invalid
    m.pinState = "unavailable"
    try
        headers = { "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa", "Device-ID": m.deviceId, "Content-Type": "application/json" }
        rsp = engagementHttp("https://gql.twitch.tv/gql", "POST", headers, formatJson({
            "query": "query StitchPinnedChat($channelID: ID!) { channel(id: $channelID) { id pinnedChatMessages(first: 1, messageType: MOD) { edges { node { id type startsAt updatedAt endsAt pinnedMessage { id sentAt content { text } sender { id login displayName } senderBadges { setID version } } } } } } }",
            "variables": { "channelID": m.top.channelId }
        }), 131072)
        if rsp = invalid or rsp.status <> 200 then return
        snapshot = engagementPinSnapshot(parseJson(rsp.body), m.top.channelId, createObject("roDateTime").asSeconds())
        if snapshot = invalid then return
        m.pin = snapshot.pinnedMessage
        m.pinState = "inactive"
        if m.pin <> invalid then m.pinState = "active"
    catch e
        m.pin = invalid
        m.pinState = "unavailable"
    end try
end sub

sub discoverEngagementBeacon()
    m.watchState = "discovery_failed"
    page = engagementHttp("https://www.twitch.tv/" + m.top.channel, "GET", {}, invalid, 2097152)
    if page = invalid or page.status <> 200 then return
    settingsUrl = engagementSettingsUrl(page.body)
    if settingsUrl = invalid then return
    settings = engagementHttp(settingsUrl, "GET", {}, invalid, 2097152)
    if settings = invalid or settings.status <> 200 then return
    m.beacon = engagementBeaconUrl(settings.body)
    if m.beacon <> invalid then m.watchState = "ready"
end sub

sub reportEngagementMinute()
    if not engagementWatchAuthorized() or m.top.sample?.playing <> true or m.top.stopRequested then return
    nowMs = m.clock.totalMilliseconds()
    ' No replay, catch-up burst or retry of an ambiguous POST.
    if nowMs - m.lastAttemptMs < 60000 then return
    if m.nextMinute > m.watch.minutes then return
    body = engagementMinuteBody(m.userId, m.top.channelId, m.broadcastId, m.top.channel, m.top.owner, m.nextMinute)
    if body = invalid then return
    m.lastAttemptMs = nowMs
    m.attempts++
    m.nextMinute++
    if m.nextMinute > m.watch.minutes then m.pendingBroadcast = ""
    m.httpStatus = 0
    rsp = engagementHttp(m.beacon, "POST", { "Content-Type": "application/x-www-form-urlencoded" }, body, 4096)
    m.watchState = "network_error"
    if rsp = invalid then return
    m.httpStatus = rsp.status
    m.watchState = "telemetry_refused"
    if rsp.status >= 200 and rsp.status < 300
        m.accepted++
        m.watchState = "telemetry_accepted"
    end if
end sub

sub publishEngagement()
    if m.top.stopRequested then return
    summary = m.watchState + ":" + m.attempts.toStr() + ":" + m.accepted.toStr() + ":" + m.hypeState + ":" + m.pinState
    if summary <> m.lastPublishedSummary
        ? "[TwitchEngagement] watch="; m.watchState; " completed="; m.watch.minutes; " attempted="; m.attempts; " accepted="; m.accepted; " http="; m.httpStatus; " hype="; m.hypeState; " pin="; m.pinState
        m.lastPublishedSummary = summary
    end if
    m.top.response = { owner: m.top.owner, watchState: m.watchState, completedMinutes: m.watch.minutes, attemptedMinutes: m.attempts, acceptedMinutes: m.accepted, lastHttpStatus: m.httpStatus, hypeState: m.hypeState, hypeTrain: m.hype, pinState: m.pinState, pinnedMessage: m.pin }
end sub

' Only Task-local asynchronous transfers. Credentials are sent solely to the
' fixed OAuth validation endpoint, never to a discovered destination.
function engagementHttp(url as string, method as string, headers as object, body as dynamic, maxBytes as integer) as dynamic
    if m.top.stopRequested then return invalid
    transfer = createObject("roUrlTransfer")
    if transfer = invalid then return invalid
    transfer.setMessagePort(m.port)
    transfer.setCertificatesFile("common:/certs/ca-bundle.crt")
    if not transfer.enablePeerVerification(true) or not transfer.enableHostVerification(true) then return invalid
    transfer.setUrl(url)
    transfer.setHeaders(headers)
    transfer.setRequest(method)
    transfer.retainBodyOnError(true)
    deadline = createObject("roTimespan")
    started = false
    if body = invalid
        started = transfer.asyncGetToString()
    else
        started = transfer.asyncPostFromString(body)
    end if
    if not started then return invalid
    while not m.top.stopRequested and deadline.totalMilliseconds() < 6000
        event = wait(100, m.port)
        if m.watch <> invalid then collectEngagementWatch()
        if deadline.totalMilliseconds() >= 6000 then exit while
        if type(event) = "roUrlEvent" and event.getSourceIdentity() = transfer.getIdentity()
            text = event.getString()
            if GetInterface(text, "ifString") = invalid then return invalid
            if text.len() > maxBytes then return invalid
            return { status: event.getResponseCode(), body: text }
        end if
    end while
    transfer.asyncCancel()
    return invalid
end function
