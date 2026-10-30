sub main()
    m.assertions = 0
    m.failures = 0
    m.top = { stopRequested: false, animatedEmotes: {}, channel: "fixture" }
    m.global = { emoteCache: {}, setField: fixtureSetCache }
    seven = { name: "same", data: { animated: true, host: { url: "//cdn.7tv.app/emote/seven", files: [
        { name: "4x.webp", static_name: "4x_static.webp", width: 128, frame_count: 5 },
        { name: "1x.avif", width: 32, frame_count: 5 },
        { name: "1x.webp", static_name: "1x_static.webp", width: 32, frame_count: 5 }
    ] } } }
    bttv = { id: "bttv", code: "same", imageType: "gif" }
    check(irc7tvAnimation(seven).uri = "https://cdn.7tv.app/emote/seven/1x.webp", "7TV selects advertised animated 1x WebP")
    check(irc7tvImage(seven) = "https://cdn.7tv.app/emote/seven/1x_static.webp", "7TV retains advertised static URI")
    check(ircBttvAnimation(bttv).uri = "https://cdn.betterttv.net/emote/bttv/1x.webp", "BTTV GIF metadata selects animated WebP")
    check(ircBttvImage(bttv) = "https://cdn.betterttv.net/emote/bttv/static/1x.webp", "BTTV GIF retains static WebP")
    check(ircBttvAnimation({ id: "flag", animated: true }) <> invalid, "BTTV explicit animated flag works without imageType")
    check(ircBttvImage({ id: "flag", animated: true }) = "https://cdn.betterttv.net/emote/flag/static/1x.webp", "explicit animated flag also selects static fallback")
    check(ircBttvAnimation({ id: "still", imageType: "png" }) = invalid, "static BTTV image does not animate")
    check(ircBttvAnimation({}) = invalid and ircBttvAnimation(invalid) = invalid, "missing BTTV identifier rejected")
    check(irc7tvAnimation({}) = invalid and irc7tvAnimation(invalid) = invalid, "missing 7TV host rejected")
    getGlobalAA().httpBody = [bttv]
    getGlobalTTVEmotes()
    getGlobalAA().httpBody = { emotes: [seven] }
    getGlobal7tvEmotes()
    descriptors = m.top.animatedEmotes
    check(descriptors.count() = 2, "different providers using the same word retain distinct URI descriptors")
    check(descriptors[ircBttvImage(bttv)].uri = ircBttvAnimation(bttv).uri, "actual BTTV producer publishes descriptor")
    check(descriptors[irc7tvImage(seven)].uri = irc7tvAnimation(seven).uri, "actual 7TV producer publishes descriptor")
    check(getGlobalAA().published.same = irc7tvImage(seven), "actual producer's word cache still stores static strings")
    seven.data.host.files = [{ name: "2x.webp", width: 64, frame_count: 5 }, { name: "3x.webp", width: 96, frame_count: 5 }]
    check(irc7tvAnimation(seven).uri = "https://cdn.7tv.app/emote/seven/2x.webp", "smallest advertised width is selected when 1x is absent")
    seven.data.host.files = [{ name: "1x.webp", frame_count: 1 }]
    check(irc7tvAnimation(seven) = invalid, "single-frame file metadata stays static")
    seven.data.host.files = [{ name: "1x_static.webp", frame_count: 5 }, { name: "1x.gif", frame_count: 5 }]
    check(irc7tvAnimation(seven) = invalid, "no synthetic GIF or static animation URLs")
    seven.data.host.files = [{ name: "../1x.webp", frame_count: 5 }]
    check(irc7tvAnimation(seven) = invalid, "advertised file names cannot traverse paths")
    m.top.stopRequested = true
    publishAnimatedEmote("https://cdn.example/late-static.webp", { uri: "https://cdn.example/late.webp" })
    publishEmoteCache({ late: "https://cdn.example/late-static.webp" })
    check(m.top.animatedEmotes.count() = 2 and not getGlobalAA().published.doesExist("late"), "canceled provider cannot publish late static or animated metadata")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

sub fixtureSetCache(field as string, value as object)
    getGlobalAA().published = value
end sub

function HttpRequest(options as object) as object
    return { send: fixtureSend }
end function

function fixtureSend() as object
    return { body: getGlobalAA().httpBody }
end function

function decodeJsonResponse(event as object) as dynamic
    return event.body
end function

function get_user_setting(key as string, fallback = invalid as dynamic) as dynamic
    return fallback
end function

sub check(ok as boolean, message as string)
    m.assertions++
    if not ok
        m.failures++
        print "CHAT_ANIMATION_FAIL: " + message
    end if
end sub
