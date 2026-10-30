' @include source/utils/http.brs
' @include source/utils/authState.brs
sub main(args as object)
    m.failures = 0
    baseUrl = args.fixtureUrl
    httpFixtureAssert(getInterface(baseUrl, "ifString") <> invalid, "fixture server address")
    if m.failures > 0 then return

    event = HttpRequest({ url: baseUrl + "/ok", timeout: 2000 }).send()
    decoded = decodeJsonResponse(event)
    httpFixtureAssert(type(event) = "roUrlEvent", "request preserves roUrlEvent contract")
    if decoded <> invalid
        httpFixtureAssert(decoded.ok = true and decoded.values.Count() = 3, "actual JSON body")
    else
        httpFixtureAssert(false, "successful event decodes")
    end if

    event = HttpRequest({ url: baseUrl + "/pending", timeout: 2000 }).send()
    httpFixtureAssert(decodeJsonResponse(event) = invalid, "HTTP error rejected by default")
    errorBody = decodeJsonResponse(event, true)
    httpFixtureAssert(getOAuthPollState(400, errorBody) = "pending", "Twitch device-flow pending response")
    httpFixtureAssert(getOAuthPollState(400, { error: "slow_down" }) = "slow_down", "RFC slow-down response")
    httpFixtureAssert(getOAuthPollState(429, invalid) = "slow_down", "rate limited polling")
    httpFixtureAssert(getOAuthPollState(200, { access_token: "fixture-token" }) = "success", "successful poll")
    httpFixtureAssert(getOAuthPollState(200, { message: "not a token" }) = "error", "malformed success is terminal")
    httpFixtureAssert(getOAuthPollState(400, { message: "invalid device code" }) = "expired", "expired/reused code")
    httpFixtureAssert(getOAuthPollState(400, { error: "access_denied" }) = "denied", "user denied sign-in")
    httpFixtureAssert(getOAuthPollState(503, invalid) = "network", "temporary service outage")

    httpFixtureAssert(getOAuthValidationState(401, invalid) = "invalid", "invalid token")
    httpFixtureAssert(getOAuthValidationState(503, invalid) = "indeterminate", "outage preserves account")
    httpFixtureAssert(getOAuthValidationState(200, {}) = "indeterminate", "unknown body preserves account")
    httpFixtureAssert(getOAuthValidationState(200, { expires_in: 3600 }) = "valid", "valid token")
    httpFixtureAssert(getOAuthValidationState(200, { expires_in: 0 }) = "valid", "non-expiring token keeps the account")
    httpFixtureAssert(getOAuthValidationState(200, { expires_in: -1 }) = "indeterminate", "malformed expiry preserves account")

    event = HttpRequest({ url: baseUrl + "/invalid-json", timeout: 2000 }).send()
    httpFixtureAssert(decodeJsonResponse(event) = invalid, "non-JSON response")
    httpFixtureAssert(decodeJsonResponse(invalid) = invalid, "missing response")
    httpFixtureAssert(decodeJsonBody("", 200) = invalid, "empty body")
    httpFixtureAssert(decodeJsonBody("{}", -1, true) = invalid, "failed transfer")

    elapsed = CreateObject("roTimeSpan")
    elapsed.Mark()
    event = HttpRequest({ url: baseUrl + "/slow", timeout: 100 }).send()
    httpFixtureAssert(decodeJsonResponse(event) = invalid, "hung request cannot return a successful body")
    httpFixtureAssert(elapsed.TotalMilliseconds() < 3000, "request deadline is finite")
    httpFixtureAssert(HttpRequest().send() = invalid, "missing URL returns safely")
    httpFixtureAssert(boundedHttpOption(0, 15000, 50, 30000) = 15000, "zero timeout stays finite")
    httpFixtureAssert(boundedHttpOption(100, 1, 1, 3) = 3, "retry count is capped")
    httpFixtureAssert(boundedHttpOption("forever", 15000, 50, 30000) = 15000, "invalid timeout")
    if m.failures = 0 then print "STITCH_TEST_PASS: http and authentication"
end sub

sub httpFixtureAssert(condition as boolean, message as string)
    if condition then return
    m.failures++
    print "STITCH_TEST_FAIL: " + message
end sub
