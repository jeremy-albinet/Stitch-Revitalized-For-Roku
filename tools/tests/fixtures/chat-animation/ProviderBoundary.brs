' Actual provider parsing/publication runs in a Task; only HTTP is canned.
sub fixtureProviders()
    getGlobalTTVEmotes()
    getGlobal7tvEmotes()
    m.top.cacheComplete = true
    m.top.completed = true
end sub

function HttpRequest(options as object) as object
    return { url: options.url, send: fixtureProviderSend }
end function

function fixtureProviderSend() as object
    if m.url.instr("betterttv") >= 0
        return { body: [{ id: "fixture-bttv", code: "BTTV", animated: true }] }
    end if
    return { body: { emotes: [{ name: "Seven", data: { animated: true, host: { url: "//cdn.7tv.app/emote/fixture-seven", files: [
        { name: "1x.webp", static_name: "1x_static.webp", width: 32, frame_count: 5 }
    ] } } }] } }
end function

function decodeJsonResponse(event as object) as dynamic
    return event.body
end function
