sub main(args as object)
    m.failures = 0
    m.assertions = 0
    m.top = { stopRequested: false }
    m.port = createObject("roMessagePort")
    baseUrl = args.fixtureUrl
    getGlobalAA().rejectTLS = true
    result = engagementHttp(baseUrl + "/tls-refused", "GET", {}, invalid, 100)
    check(result = invalid, "TLS setup refusal cannot start a transfer")
    getGlobalAA().rejectTLS = false
    m.top.watchEnabled = true
    m.top.sample = { sequence: 1, generation: 1, timeMs: 1000, position: 1, playing: true }
    m.watch = engagementWatchState()
    m.watch = engagementWatchStep(m.watch, { sequence: 0, generation: 1, timeMs: 0, position: 0, playing: true })
    m.clock = createObject("roTimespan")
    m.account = "viewer"
    m.token = "fixture-token"
    m.userId = "900"
    m.authTerminal = false
    m.authExpiresMs = 60000
    m.beacon = "https://beacon.twitch.tv/track"
    m.broadcastId = "777"
    m.snapshotValid = true
    result = engagementHttp(baseUrl + "/ok", "GET", {}, invalid, 100)
    check(result <> invalid, "actual async HTTP GET completes")
    if result <> invalid then check(result.status = 200 and result.body = "ok", "actual HTTP status and body preserved")
    check(m.watch.elapsedMs = 1000, "the actual HTTP wait collects an independently advancing playback sample")
    result = engagementHttp(baseUrl + "/post", "POST", { "Content-Type": "application/x-www-form-urlencoded" }, "data=fixture", 100)
    check(result <> invalid, "actual async HTTP POST completes")
    if result <> invalid then check(result.status = 200 and result.body = "POST:data=fixture", "actual method and form body preserved")
    result = engagementHttp(baseUrl + "/large", "GET", {}, invalid, 16)
    check(result = invalid, "oversized responses cannot be admitted")
    result = engagementHttp(baseUrl + "/refused", "GET", {}, invalid, 100)
    check(result <> invalid, "HTTP refusal is returned to the caller")
    if result <> invalid then check(result.status = 503, "HTTP refusal is not converted to success")
    elapsed = createObject("roTimespan")
    result = engagementHttp(baseUrl + "/slow", "GET", {}, invalid, 100)
    ' brs-node blocks inside AsyncGetToString; native Roku returns immediately.
    ' This verifies refusal of late completion, not native cancellation latency.
    check(result = invalid and elapsed.totalMilliseconds() >= 6000 and elapsed.totalMilliseconds() < 11000, "actual six-second request deadline refuses a late response")
    m.top.stopRequested = true
    result = engagementHttp(baseUrl + "/stopped", "GET", {}, invalid, 100)
    check(result = invalid, "stop requested before HTTP performs no transfer")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

function get_setting(key as string, fallback as dynamic) as dynamic
    return "viewer"
end function

function get_user_setting(key as string, fallback as dynamic) as dynamic
    return "fixture-token"
end function

function fixtureTlsBoundary(transfer as object, kind as string) as boolean
    if kind = "peer"
        transfer.enablePeerVerification(true)
    else
        transfer.enableHostVerification(true)
    end if
    return not getGlobalAA().rejectTLS
end function

sub check(condition as boolean, description as string)
    m.assertions++
    if not condition
        m.failures++
        print "STITCH_ENGAGEMENT_FAIL: " + description
    end if
end sub
