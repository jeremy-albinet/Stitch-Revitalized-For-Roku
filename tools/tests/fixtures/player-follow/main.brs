' Actual compiled SDK functions; only HTTP and registry I/O are canned.
' No roUrlTransfer, credentials, account writes, or Twitch request is used.
sub main()
    cases = ParseJson(ReadAsciiFile("pkg:/source/cases.json"))
    calls = { getPlayerFollowState: getPlayerFollowState, setPlayerFollowState: setPlayerFollowState, followChannel: followChannel, unfollowChannel: unfollowChannel }
    completed = 0
    for each fixture in cases
        m.fixture = fixture
        m.requests = []
        m.top = { request: { params: fixture.params }, response: "unset", control: "", followStopRequested: fixture.cancelBefore }
        invoke = calls[fixture.fn]
        invoke()
        headersValid = true
        requests = []
        for each request in m.requests
            headersValid = headersValid and request.headers["Authorization"] = "OAuth canned-token" and request.headers["Device-ID"] = "canned-device" and request.headers["Client-Id"] = "ue6666qo983tsx6so1t0vnawi233wa"
            requests.Push({ data: request.data, timeout: request.timeout, retries: request.retries, method: request.method })
        end for
        print "FOLLOW_WIRE_CASE: " + FormatJson({ name: fixture.name, response: m.top.response, control: m.top.control, requests: requests, headersValid: headersValid })
        completed++
    end for
    print "__PASS_MARKER__: "; completed; " cases"
end sub

function get_setting(key as string, fallback = invalid) as dynamic
    if key = "active_user"
        if m.fixture.switchAfter <> invalid and m.requests.Count() >= m.fixture.switchAfter and m.fixture.switchKey = "account" then return "bob"
        return m.fixture.account
    end if
    return fallback
end function

function get_user_setting(key as string, fallback = invalid) as dynamic
    if m.fixture.switchAfter <> invalid and m.requests.Count() >= m.fixture.switchAfter and m.fixture.switchKey = key then return "changed"
    if key = "access_token" then return m.fixture.token
    if key = "device_code" then return m.fixture.device
    return fallback
end function

function HttpRequest(params = invalid as dynamic) as object
    index = m.requests.Count()
    m.requests.Push(params)
    return { input: m.fixture.inputs[index], send: function() as dynamic
        return fixtureWireReply(m.input)
    end function }
end function

function fixtureWireReply(input as dynamic) as dynamic
    if m.fixture.cancelAfter <> invalid
        if m.requests.Count() >= m.fixture.cancelAfter then m.top.followStopRequested = true
    end if
    return input
end function

' roUrlEvent itself is the boundary. Production HTTP body/status validation
' executes unchanged, followed by the actual SDK response parsing.
function decodeJsonResponse(event as dynamic, allowHttpError = false as boolean) as dynamic
    if event = invalid then return invalid
    return decodeJsonBody(event.body, event.status, allowHttpError)
end function

sub trackEvent(event as string, props = {} as object)
end sub
