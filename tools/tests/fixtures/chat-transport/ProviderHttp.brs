' Native HTTP-event methods are canned; the production caller and decoders run.
function HttpRequest(params as object) as object
    m.global.fixtureProviderRequests++
    return { url: params.url, global: m.global, send: fixtureProviderSend }
end function

function fixtureProviderSend() as dynamic
    status = 200
    body = "[]"
    if m.url = "https://gql.twitch.tv/gql"
        body = "{""data"":{""badges"":[],""user"":null}}"
    else if m.url = "https://7tv.io/v3/emote-sets/global"
        body = "{""emotes"":[]}"
    else if m.url.instr("/users/twitch/") >= 0
        if m.global.fixtureProviderTimeout then return invalid
        status = m.global.fixtureProviderStatus
        if m.url.instr("https://7tv.io/") = 0
            body = "{""emote_set"":{""emotes"":[]}}"
            if m.global.fixtureProviderNoSet then body = "{""emote_set"":null}"
        else if m.url.instr("/frankerfacez/") < 0
            body = "{""channelEmotes"":[],""sharedEmotes"":[]}"
        end if
        if m.global.fixtureProviderMalformed then body = "{}"
    end if
    return { status: status, body: body, getString: fixtureBody, getResponseCode: fixtureStatus }
end function

function fixtureBody() as string
    return m.body
end function

function fixtureStatus() as integer
    return m.status
end function
