' Executes the actual renderer and tokenizer. Only PCRE syntax is adapted by
' the Node harness: brs-engine cannot compile Roku's scalar Unicode escapes.
' These checks establish layout/URI/lifecycle behavior, not native decoding.
sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: {}, emoteCache: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()
    chat = createObject("roSGNode", "Chat")
    m.scene.appendChild(chat)
    state = chat.callFunc("fixtureState")
    check(not state.compiled, "chat does not compile an emoji pattern in init")
    face = chr(&h1F600)
    heart = chr(&h2764) + chr(&hFE0F)
    family = chr(&h1F468) + chr(&h200D) + chr(&h1F469) + chr(&h200D) + chr(&h1F467) + chr(&h200D) + chr(&h1F466)
    joiner = chr(&h034F)
    samples = [
        { text: joiner, images: "", plain: " " },
        { text: joiner + joiner, images: "", plain: " " },
        { text: "before" + joiner + face + joiner + "after", images: "1f600", plain: "beforeafter " },
        { text: "a" + chr(&h0301) + joiner, images: "", plain: "a" + chr(&h0301) + " " },
        { text: "hello" + face + "world", images: "1f600", plain: "helloworld " },
        { text: heart, images: "2764", plain: " " },
        { text: chr(&h1F44D) + chr(&h1F3FD), images: "1f44d-1f3fd", plain: " " },
        { text: family, images: "1f468-200d-1f469-200d-1f467-200d-1f466", plain: " " },
        { text: chr(&h1F1FA) + chr(&h1F1F8), images: "1f1fa-1f1f8", plain: " " },
        { text: "1" + chr(&hFE0F) + chr(&h20E3), images: "31-20e3", plain: " " },
        { text: face + face, images: "1f600,1f600", plain: " " },
        { text: chr(&h1FAE8) + chr(&h1FA77), images: "1fae8,1fa77", plain: " " },
        { text: "ASCII 123 #*", images: "", plain: "ASCII 123 #* " },
        { text: "caf" + chr(&hE9) + " " + chr(&h4F60) + chr(&h597D), images: "", plain: "caf" + chr(&hE9) + " " + chr(&h4F60) + chr(&h597D) + " " }
    ]
    for each sample in samples
        group = chat.callFunc("fixtureBuild", sample.text)
        check(points(group) = sample.images, "image runs and pinned URIs for " + sample.text)
        check(textOf(group) = sample.plain, "ordinary text preserved around emoji for " + sample.text)
        check(group.chatMessageText = sample.text, "presentation preserves the original message, including invisible joiners")
        check(inBounds(group, state), "image/text runs fit chat bounds")
        chat.callFunc("fixturePrune", group)
    end for
    check(chat.callFunc("fixtureState").builds = 1, "all words and messages reuse one compiled full pattern")

    cache = { PETPET: "https://cdn.7tv.app/emote/01FSNK0GP000038GDBZ91HT6SQ/1x_static.webp", catJAM: "https://cdn.betterttv.net/emote/5f1b0186cf6d2144653d2970/static/1x.webp" }
    m.global.emoteCache = cache
    group = chat.callFunc("fixtureBuild", "PETPET catJAM PETPETx " + face + "catJAM")
    nodes = posters(group)
    check(nodes.count() = 3, "whole provider words become images; substrings and emoji-adjacent names stay text")
    if nodes.count() = 3
        check(nodes[0].uri = cache.PETPET and nodes[1].uri = cache.catJAM, "provider cache URLs are used verbatim")
    end if
    check(textOf(group).instr("PETPETx") >= 0 and textOf(group).instr("catJAM") >= 0, "provider lookup never replaces substrings")
    check(m.global.emoteCache.count() = 2, "emoji rendering does not modify the shared provider cache")
    chat.callFunc("fixturePrune", group)

    for each sample in [
            { text: "@viewer", highlighted: "@viewer" },
            { text: "(@Viewer_1),", highlighted: "@Viewer_1" },
            { text: "@one,@two", highlighted: "@one@two" },
            { text: "@" + string(25, "a"), highlighted: "@" + string(25, "a") },
            { text: "mail@example.com @@viewer bare@viewer @" + string(26, "a"), highlighted: "" }
        ]
        group = chat.callFunc("fixtureBuild", sample.text)
        check(highlightedText(group) = sample.highlighted, "mention colors honor username boundaries and leave email addresses untouched")
        check(textOf(group) = sample.text + " ", "mention highlighting preserves punctuation and source text")
        chat.callFunc("fixturePrune", group)
    end for
    chat.width = 150
    chat.fontSize = 20
    longMention = "@" + string(25, "W")
    group = chat.callFunc("fixtureBuild", longMention)
    check(highlightedText(group) = longMention and group.localBoundingRect().height > 40, "mentions retain their own highlight when wrapping at code-point boundaries")
    chat.callFunc("fixturePrune", group)
    chat.width = 275
    chat.fontSize = 14

    now = createObject("roDateTime").asSeconds()
    pin = { id: "pin-images", messageId: "pin-images", userId: "1", login: "viewer", senderName: "Viewer", text: "PETPET catJAM @viewer " + heart, sentAt: now, updatedAt: now, observedAt: now, expiresAt: now + 300& }
    chat.pinnedMessage = pin
    status = chat.callFunc("fixtureChatStatus", "syncing", false)
    check(status.pinVisible and status.statusVisible and status.clipTop >= 176 + status.statusHeight + 24, "reconnect/sync status reserves space below the pin instead of painting over retained chat")
    status = chat.callFunc("fixtureChatStatus", "connected", true)
    check(not status.statusVisible and status.clipTop = 176, "first rendered message releases status space while retaining the pin header")
    preview = chat.callFunc("fixturePinPreview")
    pinImages = posters(preview)
    check(pinImages.count() = 3, "pinned preview renders BTTV, 7TV and Unicode images")
    check(highlightedText(preview) = "@viewer", "pinned preview shares mention highlighting")
    check(chat.callFunc("showPinnedMessage"), "rich pinned message opens")
    dialog = m.scene.dialog
    check(dialog <> invalid and chatAssetPosters(dialog) = 3, "full pinned message renders the same provider and Unicode images")
    if dialog <> invalid
        check(highlightedText(dialog) = "@viewer", "full pinned message shares mention highlighting")
    end if
    m.global.addFields({
        twitchBadges: {
            "moderator/1": "https://static-cdn.jtvnw.net/badges/moderator.png",
            "subscriber/2042": "https://static-cdn.jtvnw.net/badges/subscriber.png",
            "gamerduo/1": "https://static-cdn.jtvnw.net/badges/gamerduo.png"
        }
    })
    pin.badges = ["moderator/1", "subscriber/2042", "gamerduo/1"]
    pin.updatedAt = now + 1&
    chat.pinnedMessage = pin
    header = chat.callFunc("fixturePinAuthor")
    headerImages = posters(header)
    check(headerImages.count() = 3 and textOf(header) = "Viewer", "pinned author includes the message's assigned moderator, subscriber and event badges")
    if headerImages.count() = 3
        check(headerImages[0].uri = m.global.twitchBadges["moderator/1"] and headerImages[1].uri = m.global.twitchBadges["subscriber/2042"] and headerImages[2].uri = m.global.twitchBadges["gamerduo/1"], "pinned badges retain assignment order and use the existing channel badge catalog")
        authorRow = header.getChild(0)
        check(authorRow.getChild(1).translation[0] = 63 and headerImages[0].width = 18 and headerImages[2].translation[0] = 42, "pinned badges fit the fixed author row before the name")
    end if
    check(chat.callFunc("showPinnedMessage"), "pin with badges opens its full dialog")
    authorDialog = m.scene.dialog.findNode("pinDialogAuthor")
    check(authorDialog <> invalid and posters(authorDialog).count() = 3 and textOf(authorDialog) = "Viewer", "full pinned message includes the same author badges before the name")
    chat.width = 100
    check(posters(header).count() = 0 and header.getChild(0).getChild(1).width = 76, "narrow pin headers preserve room for the author instead of clipping badges into the name")
    chat.width = 275
    chat.pinnedMessage = invalid
    check(preview.getChildCount() = 0 and header.getChildCount() = 0 and m.scene.dialog = invalid, "unpin releases both rich views and author badges and closes the dialog")
    status = chat.callFunc("fixtureChatStatus", "connecting", false)
    check(status.statusVisible and status.clipTop = status.statusHeight + 24, "reconnecting without a pin also reserves a separate status area")
    chat.callFunc("fixtureChatStatus", "connected", true)
    if pinImages.count() > 0
        failedBefore = chat.callFunc("fixtureState").failed
        chat.callFunc("fixtureImageStatus", pinImages[0], "failed")
        check(chat.callFunc("fixtureState").failed = failedBefore, "removed pin image callbacks cannot alter the current failure cache")
    end if

    gifUri = "https://media4.giphy.com/media/joSNxeswxuc74Juo8X/giphy.gif?cid=fixture&ep=v1_gifs_trending&rid=giphy.gif&ct=g"
    gifTitle = "[Y A Y Yes GIF by Djemilah Birnie]"
    gifText = "hello " + gifTitle + " @viewer"
    gifTags = { gifs: "6-39|joSNxeswxuc74Juo8X|" + gifUri }
    originalCacheCount = m.global.emoteCache.count()
    group = chat.callFunc("fixtureGifs", gifText, gifTags, false)
    check(textOf(group) = gifText + " ", "disabled GIF motion retains the complete original title and surrounding text")
    check(chat.callFunc("fixtureGifState").keys = 0, "disabled GIF motion does not register download descriptors")
    chat.callFunc("fixturePrune", group)
    chat.width = 150
    group = chat.callFunc("fixtureGifs", gifText, gifTags, true)
    gifNode = invalid
    mentionNode = invalid
    for each node in group.getChildren(-1, 0)
        if node.hasField("chatGifTitle") then gifNode = node
        if node.subtype() = "SimpleLabel" and node.text = "@viewer" then mentionNode = node
    end for
    check(gifNode <> invalid and gifNode.chatImageUri = gifUri, "GIF occurrence retains the exact supplied URL, including its query")
    check(group.chatMessageText = gifText and group.chatAttachments.count() = 1, "GIF occurrence preserves original text and attachment offsets")
    check(textOf(group) = gifText + " ", "pending GIF fallback retains its title without changing surrounding spaces")
    check(mentionNode <> invalid and gifNode <> invalid and mentionNode.translation[1] >= gifNode.translation[1] + 96, "tall GIF layout reserves its height before wrapping following text")
    check(m.global.emoteCache.count() = originalCacheCount, "GIF attachment titles never enter the provider word cache")
    descriptor = chat.callFunc("fixtureGifState").descriptors[gifUri]
    check(descriptor <> invalid and descriptor.format = "gif", "GIF occurrence supplies a separate format descriptor")
    chat.callFunc("fixturePrune", group)
    chat.callFunc("fixtureProviderUpdate", {})
    check(chat.callFunc("fixtureGifState").descriptors[gifUri] <> invalid, "incremental provider publication preserves current GIF descriptors")
    check(chat.callFunc("fixtureMissingDescriptor"), "a missing descriptor cannot crash the native failure callback")
    group = chat.callFunc("fixtureGifs", gifText, {}, false)
    check(chatAssetPosters(group) = 0, "unannotated GIF titles never trigger media fetching")
    chat.callFunc("fixturePrune", group)

    pin.id = "pin-late"
    pin.text = "LatePin"
    chat.pinnedMessage = pin
    check(chat.callFunc("showPinnedMessage"), "pin can open before provider loading completes")
    cache.LatePin = "https://cdn.7tv.app/emote/late-pin/1x_static.webp"
    chat.callFunc("fixtureChatStatus", "syncing", false)
    pending = chat.callFunc("fixturePublishProvider", cache)
    check(chatAssetPosters(chat.callFunc("fixturePinPreview")) = 1 and chatAssetPosters(m.scene.dialog) = 1, "incremental provider results refresh both pinned views before chat sync or provider completion")
    check(not pending.completed and not pending.rendered and pending.presentation = "syncing" and pending.statusVisible, "pin refresh leaves delayed chat and the unfinished provider worker unchanged")
    priorPreview = chat.callFunc("fixturePinPreview").getChild(0)
    chat.callFunc("fixturePublishProvider", cache)
    check(not priorPreview.isSameNode(chat.callFunc("fixturePinPreview").getChild(0)), "later provider publications refresh a pin without a new pinned-message snapshot")
    chat.callFunc("fixtureCompleteEmotes", cache)
    check(chatAssetPosters(chat.callFunc("fixturePinPreview")) = 1 and chatAssetPosters(m.scene.dialog) = 1, "provider completion refreshes both open rich pin views")
    check(chat.callFunc("fixtureGifState").descriptors[gifUri] <> invalid, "provider completion preserves learned GIF attachment descriptors")
    pinImage = posters(chat.callFunc("fixturePinPreview"))[0]
    chat.callFunc("fixtureImageStatus", pinImage, "failed")
    check(textOf(chat.callFunc("fixturePinPreview")) = "LatePin " and chatAssetPosters(chat.callFunc("fixturePinPreview")) = 0, "pinned provider failures retain a readable token")
    chat.pinnedMessage = invalid

    snapshot = {}
    for index = 1 to 256
        id = "fixture" + index.toStr()
        uri = "https://media.giphy.com/media/" + id + "/giphy.gif"
        group = chat.callFunc("fixtureGifs", "gif", { gifs: "0-2|" + id + "|" + uri }, true)
        chat.callFunc("fixturePrune", group)
        if index <= 128 then snapshot[uri] = { provider: "twitch-gif", uri: uri, format: "gif" }
    end for
    chat.callFunc("fixtureProviderUpdate", snapshot)
    state = chat.callFunc("fixtureGifState")
    gifCount = 0
    for each uri in state.descriptors
        if state.descriptors[uri].format = "gif" then gifCount++
    end for
    check(state.keys = 128 and gifCount = 128, "stale provider snapshots cannot resurrect evicted GIFs beyond the descriptor bound")

    chat.width = 140
    state = chat.callFunc("fixtureState")
    group = chat.callFunc("fixtureBuild", "ordinary words " + string(70, "x") + face + face + " tail")
    check(inBounds(group, state), "long words, adjacent emoji and following text remain within both bounds")
    check(group.localBoundingRect().height > 60, "long message wraps onto several rows")
    check(points(group) = "1f600,1f600", "wrapping does not split emoji into missing-glyph labels")
    check(textOf(group) = "ordinary words " + string(70, "x") + " tail ", "wrapping preserves ASCII text and spaces")
    chat.callFunc("fixturePrune", group)

    chat.width = 275
    state = chat.callFunc("fixtureState")
    longWord = string(256, "W")
    group = chat.callFunc("fixtureBuild", longWord)
    print "STITCH_CHAT_LONGWORD_NODES:"; group.getChildCount()
    check(textOf(group) = longWord + " " and inBounds(group, state), "long-word line runs preserve every character and stay within chat bounds")
    check(group.getChildCount() < 32, "long words use line runs instead of hundreds of individual character nodes")
    chat.callFunc("fixturePrune", group)

    ' A native emote after a non-BMP character must be cached under its entire
    ' token, not a UTF-16 slice beginning at the preceding space.
    chat.width = 275
    chat.channel = "fixture"
    state = chat.callFunc("fixtureState")
    job = state.job
    message = ircParseMessage("@id=unicode;display-name=Viewer;emotes=25:4-8 :viewer!viewer@host PRIVMSG #fixture :" + joiner + " " + face + " Kappa " + joiner)
    message.identity = { id: "unicode", userId: "1", login: "viewer" }
    message.moderationSeq = 0
    job.nextCommentObj = message
    settle(100)
    check(m.global.emoteCache.Kappa = "https://static-cdn.jtvnw.net/emoticons/v2/25/static/light/1.0", "actual renderComment consumes Twitch code-point offsets before emoji parsing")
    panel = chat.callFunc("fixtureState").panel
    nodes = posters(panel)
    check(nodes.count() = 2, "actual comment renders both Unicode and Twitch emote images")
    check(textOf(panel).instr(joiner) < 0, "actual IRC rendering keeps invisible joiners out of labels after consuming emote offsets")
    if nodes.count() = 2
        old = nodes[1]
        chat.callFunc("fixtureImageStatus", old, "failed")
        check(textOf(panel).instr("Kappa") >= 0 and posters(panel).count() = 1, "failed Twitch image is replaced with its readable token")
        check(inBounds(panel.getChild(0).getChild(0).getChild(3), chat.callFunc("fixtureState")), "failed-image fallback reflows within chat bounds")
    end if
    chat.callFunc("fixtureModerateRoom")
    check(panel.getChildCount() = 0, "moderation removes emoji-bearing rows")
    if nodes.count() = 2
        failedBefore = chat.callFunc("fixtureState").failed
        chat.callFunc("fixtureImageStatus", nodes[0], "failed")
        check(chat.callFunc("fixtureState").failed = failedBefore, "a removed row's late image event cannot change the cache")
    end if

    group = chat.callFunc("fixtureBuild", heart)
    nodes = posters(group)
    if nodes.count() = 1
        parent = group.getParent()
        chat.callFunc("fixtureImageStatus", nodes[0], "failed")
        replacement = parent.getChild(parent.getChildCount() - 1)
        check(textOf(replacement) = "<3 " and posters(replacement).count() = 0, "Unicode decode failure uses supported text, not Archivo missing glyphs")
        chat.callFunc("fixturePrune", replacement)
    else
        fail("heart image is unavailable before failure test")
    end if
    group = chat.callFunc("fixtureBuild", "catJAM")
    nodes = posters(group)
    if nodes.count() = 1
        chat.callFunc("fixtureImageStatus", nodes[0], "ready")
        check(posters(group).count() = 1, "ready image stays an image")
        chat.callFunc("fixturePrune", group)
    end if

    group = chat.callFunc("fixtureBuild", face)
    nodes = posters(group)
    if nodes.count() = 1
        parent = group.getParent()
        ' loadStatus is read-only. Supply the native event at the decoder boundary.
        chat.callFunc("fixtureImageStatus", nodes[0], "failed")
        replacement = parent.getChild(parent.getChildCount() - 1)
        check(textOf(replacement) = "[emoji] " and posters(replacement).count() = 0, "failed image notification uses a neutral Unicode fallback")
        chat.callFunc("fixturePrune", replacement)
    end if

    testEmojiLabel(heart, face)
    chat.callFunc("onDestroy")
    check(not chat.callFunc("fixtureState").compiled and chat.callFunc("fixtureState").failed = 0, "chat disposal releases its parser and bounded failure cache")
    m.scene.removeChild(chat)
    fixtureEnd()
end sub

sub testEmojiLabel(heart as string, face as string)
    label = createObject("roSGNode", "EmojiLabel")
    label.height = 28
    m.scene.appendChild(label)
    label.text = "love " + heart
    parts = label.callFunc("fixtureParts")
    check(parts.count() = 2 and parts[1].subtype() = "Poster", "EmojiLabel uses the shared production tokenizer")
    if parts.count() = 2
        poster = parts[1]
        check(poster.uri = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.3/assets/72x72/2764.png", "EmojiLabel shares corrected VS16 URI normalization")
        label.maxWidth = 20
        label.repeatCount = -1
        label.color = "0xFFFFFFFF"
        check(label.callFunc("fixtureScrollState").pending, "a style update preserves a pending title marquee")
        label.callFunc("fixtureScrollStart")
        check(label.callFunc("fixtureScrollState").scrolling, "the title is scrolling before the late emoji failure")
        label.callFunc("fixtureImageStatus", poster, "failed")
        check(textOf(label) = "love <3", "EmojiLabel image decode failure gets a supported text fallback")
        state = label.callFunc("fixtureScrollState")
        check(state.pending and not state.scrolling, "a late emoji fallback restarts the title with a reading pause")
        label.callFunc("fixtureScrollStart")
        state = label.callFunc("fixtureScrollState")
        distance = label.width - label.maxWidth
        check(state.target = 0 - distance and distance / state.duration <= 40 and state.cycleDuration = state.duration + 1, "the restarted marquee uses only overflow at readable speed after image fallback")
        label.repeatCount = 0
    end if
    label.text = face + face
    parts = label.callFunc("fixtureParts")
    check(parts.count() = 2 and parts[0].subtype() = "Poster" and parts[1].subtype() = "Poster", "repeated text updates create separate emoji images")
    check(label.callFunc("fixtureBuilds") = 1, "EmojiLabel reuses its compiled parser")
    label.callFunc("onDestroy")
    check(label.callFunc("fixtureParts").count() = 0, "EmojiLabel disposal removes image observers and nodes")
    m.scene.removeChild(label)
end sub

function posters(node as object) as object
    result = []
    if node.subtype() = "Poster" then result.push(node)
    for each child in node.getChildren(-1, 0)
        result.append(posters(child))
    end for
    return result
end function

function points(node as object) as string
    result = []
    base = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.3/assets/72x72/"
    for each poster in posters(node)
        if poster.uri.left(base.len()) <> base then return "unexpected image URI"
        result.push(poster.uri.mid(base.len()).replace(".png", ""))
    end for
    return result.join(",")
end function

function textOf(node as object) as string
    if node.subtype() = "Label" or node.subtype() = "SimpleLabel" then return node.text
    result = ""
    for each child in node.getChildren(-1, 0)
        result += textOf(child)
    end for
    return result
end function

function highlightedText(node as object) as string
    if node.subtype() = "SimpleLabel"
        if colorHex(node.color) = "BF94FF" then return node.text
        return ""
    end if
    result = ""
    for each child in node.getChildren(-1, 0)
        result += highlightedText(child)
    end for
    return result
end function

function chatAssetPosters(node as object) as integer
    count = 0
    for each poster in posters(node)
        if poster.uri.instr("cdn.7tv.app/") >= 0 or poster.uri.instr("cdn.betterttv.net/") >= 0 or poster.uri.instr("jdecked/twemoji@") >= 0 then count++
    end for
    return count
end function

function inBounds(group as object, state as object) as boolean
    for each node in group.getChildren(-1, 0)
        if node.translation[0] < state.left - 0.1 or node.translation[0] + node.localBoundingRect().width > state.right + 0.1 then return false
    end for
    return true
end function
