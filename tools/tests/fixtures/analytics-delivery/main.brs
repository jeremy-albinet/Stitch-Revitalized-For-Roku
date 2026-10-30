sub main()
    m.failures = 0
    m.deviceInfo = CreateObject("roDeviceInfo")
    m.config = { apiKey: "fixture-key", captureUrl: "https://fixture.invalid/capture" }
    m.global = { appInfo: { version: { version: "fixture" }, isDev: true } }
    m.distinctId = "fixture-session"
    m.rateLimits = {}
    m.requests = []
    m.responseCode = 200
    m.top = {
        identify: { set: { app_version: "fixture" } },
        capture: { event: "app_opened" },
        captureException: { message: "fixture exception", location: "Fixture/main" }
    }
    flushStartupAnalytics()
    analyticsCheck(m.requests.count() = 3, "pre-observer startup values are delivered")
    if m.requests.count() = 3
        analyticsCheck(m.requests[0].event = "$identify" and m.requests[1].event = "app_opened", "startup identify precedes app event")
        fingerprint = m.requests[2].properties["$exception_fingerprint"]
        analyticsCheck(fingerprint = "BrightScriptException:fixture exception:Fixture/main", "exception fingerprint is accepted string form")
    end if
    flushStartupAnalytics()
    analyticsCheck(m.requests.count() = 3, "queued duplicates do not resend startup values")

    m.responseCode = 503
    sendIdentify({ set: { app_version: "changed" } })
    analyticsCheck(m.lastIdentify = FormatJson({ app_version: "fixture" }), "failed identify does not advance delivery marker")
    m.responseCode = 200
    sendIdentify({ set: { app_version: "changed" } })
    analyticsCheck(m.requests.count() = 5, "failed identify retries the same properties")
    sendIdentify({ set: { app_version: "changed" } })
    analyticsCheck(m.requests.count() = 5, "successful identify suppresses its duplicate")
    m.lastIdentify = invalid
    m.distinctId = "second-fixture-session"
    sendIdentify({ set: { app_version: "changed" } })
    analyticsCheck(m.requests.count() = 6 and m.requests[5].distinct_id = "second-fixture-session", "new anonymous session is not suppressed by previous session")

    m.responseCode = invalid
    analyticsCheck(not postToPostHog({ event: "fixture" }), "missing transport result is not delivery")
    if m.failures = 0 then print "STITCH_TEST_PASS: analytics startup and delivery"
end sub

function HttpRequest(params as object) as object
    m.requests.push(params.data)
    response = invalid
    if m.responseCode <> invalid
        response = {
            code: m.responseCode,
            GetResponseCode: function() as integer
                return m.code
            end function
        }
    end if
    return {
        response: response,
        send: function() as dynamic
            return m.response
        end function
    }
end function

function get_setting(key, default = invalid)
    return default
end function

function get_user_setting(key, default = invalid)
    return default
end function

function getAnalyticsConfiguration() as dynamic
    return invalid
end function

sub analyticsCheck(condition as boolean, label as string)
    if not condition
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
