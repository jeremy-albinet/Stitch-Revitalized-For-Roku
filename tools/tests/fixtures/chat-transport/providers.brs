' All production provider handlers, lifecycle and JSON decoding execute.
' HTTP events and registry access are offline boundaries; no credentials are used.
sub main()
    m.assertions = 0
    m.failures = 0
    bttvChannel = "https://api.betterttv.net/3/cached/users/twitch/42"
    ffzChannel = "https://api.betterttv.net/3/cached/frankerfacez/users/twitch/42"
    sevenChannel = "https://7tv.io/v3/users/twitch/42"
    channelUrls = [bttvChannel, ffzChannel, sevenChannel]
    cases = [
        { url: bttvChannel, body: "{}", name: "BTTV missing both arrays" }
        { url: bttvChannel, body: "{""channelEmotes"":[]}", name: "BTTV missing shared array" }
        { url: bttvChannel, body: "{""sharedEmotes"":[]}", name: "BTTV missing channel array" }
        { url: bttvChannel, body: "{""channelEmotes"":[],""sharedEmotes"":null}", name: "BTTV null shared array" }
        { url: bttvChannel, body: "{""channelEmotes"":[],""sharedEmotes"":{}}", name: "BTTV object shared array" }
        { url: bttvChannel, body: "{""channelEmotes"":null,""sharedEmotes"":[]}", name: "BTTV null channel array" }
        { url: bttvChannel, body: "{""channelEmotes"":{},""sharedEmotes"":[]}", name: "BTTV object channel array" }
        { url: sevenChannel, body: "{}", name: "7TV missing no-set envelope" }
        { url: sevenChannel, body: "{""emote_set"":{}}", name: "7TV missing emotes array" }
        { url: sevenChannel, body: "{""emote_set"":{""emotes"":null}}", name: "7TV null emotes array" }
        { url: sevenChannel, body: "{""emote_set"":{""emotes"":{}}}", name: "7TV object emotes array" }
        { url: "https://api.betterttv.net/3/cached/emotes/global", body: "{}", name: "BTTV global object instead of array" }
        { url: "https://api.betterttv.net/3/cached/frankerfacez/users/twitch/42", body: "{}", name: "FFZ object instead of array" }
        { url: "https://7tv.io/v3/emote-sets/global", body: "{""emotes"":{}}", name: "7TV global object instead of array" }
    ]
    for each url in channelUrls
        for each body in ["", "not JSON", "null"]
            cases.push({ url: url, body: body, name: url + " undecodable HTTP 200 body '" + body + "'" })
        end for
    end for
    for each fixtureCase in cases
        resetProviders()
        state = getGlobalAA()
        responses = state.providerResponses
        validBody = responses[fixtureCase.url]
        responses[fixtureCase.url] = fixtureCase.body
        state.providerResponses = responses
        runEmoteJob()
        check(m.fetchFailed and m.top.completed and not m.top.cacheComplete, fixtureCase.name + " must finish with retryable failure")
        check(state.providerRequests.count() = 6, fixtureCase.name + " does not prevent remaining providers")

        responses = state.providerResponses
        responses[fixtureCase.url] = validBody
        state.providerResponses = responses
        ' Reopening retries a cache only when the previous job left it incomplete.
        if not m.top.cacheComplete
            m.top.completed = false
            runEmoteJob()
        end if
        check(not m.fetchFailed and m.top.completed and m.top.cacheComplete, fixtureCase.name + " succeeds on retry")
        check(state.providerRequests.count() = 12, fixtureCase.name + " is fetched again on retry")
    end for

    resetProviders()
    runEmoteJob()
    check(not m.fetchFailed and m.top.completed and m.top.cacheComplete, "legitimate empty provider arrays complete the cache")
    check(getGlobalAA().publishedCache.IRC = "https://cdn.example/irc.png", "empty provider results preserve learned IRC emotes")

    resetProviders()
    responses = getGlobalAA().providerResponses
    responses[sevenChannel] = "{""emote_set"":null}"
    getGlobalAA().providerResponses = responses
    runEmoteJob()
    check(not m.fetchFailed and m.top.completed and m.top.cacheComplete, "explicit 7TV no-set completes the cache")

    for each url in channelUrls
        for each body in ["", "not JSON", "{}", "{""message"":""not registered""}"]
            resetProviders()
            getGlobalAA().providerStatuses[url] = 404
            getGlobalAA().providerResponses[url] = body
            runEmoteJob()
            check(not m.fetchFailed and m.top.completed and m.top.cacheComplete, url + " HTTP 404 is completed optional absence regardless of error body")
            check(getGlobalAA().providerRequests.count() = 6, "optional absence still fetches the remaining providers")
        end for
    end for

    resetProviders()
    for each url in channelUrls
        getGlobalAA().providerStatuses[url] = 404
    end for
    getGlobalAA().learnAtUrl = "https://7tv.io/v3/emote-sets/global"
    runEmoteJob()
    check(not m.fetchFailed and m.top.cacheComplete, "all optional channel registrations may be absent")
    cache = getGlobalAA().publishedCache
    check(cache.IRC = "https://cdn.example/irc.png" and cache.LateIRC = "https://cdn.example/late-irc.png", "provider publication merges the new IRC cache learned during HTTP wait")

    getGlobalAA().providerResponses["https://7tv.io/v3/emote-sets/global"] = "{}"
    runEmoteJob()
    check(m.fetchFailed and not m.top.cacheComplete, "later optional absence cannot mask another provider's malformed success")

    resetProviders()
    urls = getGlobalAA().providerResponses.keys()
    for each url in urls
        for each status in [403, 429, 500, 503, -1]
            resetProviders()
            getGlobalAA().providerStatuses[url] = status
            runEmoteJob()
            check(m.fetchFailed and m.top.completed and not m.top.cacheComplete, url + " non-success status remains retryable even with a valid provider body")
        end for
        resetProviders()
        getGlobalAA().timeoutUrl = url
        runEmoteJob()
        check(m.fetchFailed and m.top.completed and not m.top.cacheComplete, url + " timeout remains retryable")
        getGlobalAA().timeoutUrl = ""
        runEmoteJob()
        check(not m.fetchFailed and m.top.cacheComplete and getGlobalAA().providerRequests.count() = 12, url + " timeout recovery refetches providers")
    end for

    for each url in ["https://api.betterttv.net/3/cached/emotes/global", "https://7tv.io/v3/emote-sets/global", "https://gql.twitch.tv/gql"]
        resetProviders()
        getGlobalAA().providerStatuses[url] = 404
        runEmoteJob()
        check(m.fetchFailed and not m.top.cacheComplete, "HTTP 404 outside optional channel lookup remains retryable")
    end for

    resetProviders()
    getGlobalAA().cancelUrl = bttvChannel
    runEmoteJob()
    check(not m.top.completed and not m.top.cacheComplete and getGlobalAA().providerRequests.count() = 3, "stop during actual HTTP provider handling starts no later provider")
    check(getGlobalAA().cachePublications = getGlobalAA().publicationsAtCancel, "stop during actual HTTP provider handling adds no cache publication after cancellation")

    for each url in channelUrls
        resetProviders()
        getGlobalAA().providerStatuses[url] = 404
        getGlobalAA().cancelUrl = url
        runEmoteJob()
        check(not m.top.completed and not m.top.cacheComplete, "canceled optional absence never completes the cache")
        check(getGlobalAA().cachePublications = getGlobalAA().publicationsAtCancel, "canceled optional absence publishes no stale cache")
    end for

    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

sub resetProviders()
    m.top = { stopRequested: false, channel_id: "42", channel: "fixture", completed: false, cacheComplete: false }
    m.global = { emoteCache: { IRC: "https://cdn.example/irc.png" }, twitchBadges: {}, setField: fixturePublishCache }
    state = getGlobalAA()
    state.providerRequests = []
    state.providerResponses = {
        "https://gql.twitch.tv/gql": "{""data"":{""badges"":[],""user"":null}}"
        "https://api.betterttv.net/3/cached/emotes/global": "[]"
        "https://api.betterttv.net/3/cached/users/twitch/42": "{""channelEmotes"":[],""sharedEmotes"":[]}"
        "https://api.betterttv.net/3/cached/frankerfacez/users/twitch/42": "[]"
        "https://7tv.io/v3/emote-sets/global": "{""emotes"":[]}"
        "https://7tv.io/v3/users/twitch/42": "{""emote_set"":{""emotes"":[]}}"
    }
    state.cachePublications = 0
    state.providerStatuses = {}
    state.timeoutUrl = ""
    state.learnAtUrl = ""
    state.publishedCache = invalid
    state.cancelUrl = ""
    state.publicationsAtCancel = -1
end sub

function HttpRequest(params as object) as object
    state = getGlobalAA()
    requests = state.providerRequests
    requests.push(params.url)
    state.providerRequests = requests
    if params.url = state.cancelUrl
        state.publicationsAtCancel = state.cachePublications
        m.top.stopRequested = true
    end if
    if params.url = state.learnAtUrl
        ' Replace the global snapshot so a stale pre-request cache cannot pass.
        cache = {}
        cache.append(m.global.emoteCache)
        cache.LateIRC = "https://cdn.example/late-irc.png"
        m.global.emoteCache = cache
    end if
    return { url: params.url, send: fixtureHttpSend }
end function

function fixtureHttpSend() as dynamic
    state = getGlobalAA()
    if m.url = state.timeoutUrl then return invalid
    status = 200
    if state.providerStatuses.doesExist(m.url) then status = state.providerStatuses[m.url]
    return { body: state.providerResponses[m.url], status: status, getString: fixtureBody, getResponseCode: fixtureStatus }
end function

' Adapt the fake HTTP event to the unmodified production status/JSON decoder.
function decodeJsonResponse(event as dynamic, allowHttpError = false as boolean) as dynamic
    if event = invalid then return invalid
    return decodeJsonBody(event.getString(), event.getResponseCode(), allowHttpError)
end function

function fixtureBody() as string
    return m.body
end function

function fixtureStatus() as integer
    return m.status
end function

function get_user_setting(key as string, fallback = invalid as dynamic) as dynamic
    return fallback
end function

sub fixturePublishCache(field as string, cache as object)
    if field <> "emoteCache" then return
    getGlobalAA().cachePublications++
    getGlobalAA().publishedCache = cache
end sub

sub check(condition as boolean, message as string)
    m.assertions++
    if not condition
        m.failures++
        print "STITCH_CHAT_TRANSPORT_FAIL: " + message
    end if
end sub
