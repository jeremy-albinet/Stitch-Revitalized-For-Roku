' Runs the actual compiled TwitchApiTask query functions against canned GraphQL
' bodies. Only the HTTP, registry and telemetry boundaries are replaced; the
' Node test owns the cases and the expected response contracts.
sub main()
    cases = ParseJson(ReadAsciiFile("pkg:/source/cases.json"))
    queries = {
        getHomePageQuery: getHomePageQuery,
        getFollowingPageQuery: getFollowingPageQuery,
        getBrowsePagePopularQuery: getBrowsePagePopularQuery,
        getBrowsePageQuery: getBrowsePageQuery,
        getChannelHomeQuery: getChannelHomeQuery,
        getContentAdvisoryQuery: getContentAdvisoryQuery,
        getGameDirectoryQuery: getGameDirectoryQuery,
        getCategoryQuery: getCategoryQuery,
        getRecommendedSections: getRecommendedSections
        getTwitchBookmarks: getTwitchBookmarks
    }
    completed = 0
    for each fixtureCase in cases
        m.body = fixtureCase.body
        m.accessToken = fixtureCase.accessToken
        m.requests = []
        m.top = { request: fixtureCase.request, response: "unset", control: "" }
        ' Call through a local so the query runs with the global m, as in a Task.
        query = queries[fixtureCase.query]
        query()
        authorized = false
        deviceId = invalid
        if m.requests.count() = 1
            authorized = m.requests[0].headers.doesExist("Authorization")
            deviceId = m.requests[0].headers["Device-ID"]
        end if
        print "STITCH_GQL_CASE: " + FormatJson({
            name: fixtureCase.name,
            response: m.top.response,
            control: m.top.control,
            requests: m.requests.count(),
            authorized: authorized,
            deviceId: deviceId
        })
        completed = completed + 1
    end for
    print "STITCH_GQL_PASS: __PASS_MARKER__ " + completed.toStr()
end sub

function get_user_setting(key, default = invalid)
    if key = "device_code" then return "fixture-device"
    if key = "access_token" then return m.accessToken
    return default
end function

function get_setting(key, default = invalid)
    if key = "active_user" and m.accessToken <> invalid
        if m.top.request.switchProfile = true and m.requests.count() > 0 then return "another-user"
        return "fixture-user"
    end if
    return default
end function

sub set_user_setting(key as string, value as dynamic)
    m.persisted = { key: key, value: value }
end sub

function HttpRequest(params = invalid as dynamic) as object
    m.requests.push(params)
    return {
        body: m.body,
        send: function() as dynamic
            return m.body
        end function
    }
end function

' Mirrors the production decoder after a successful HTTP status.
function decodeJsonResponse(event as dynamic, allowHttpError = false as boolean) as dynamic
    if GetInterface(event, "ifString") = invalid then return invalid
    return ParseJson(event)
end function

sub trackEvent(event as string, props = {} as object)
end sub

sub captureException(e as object, location as string)
end sub
