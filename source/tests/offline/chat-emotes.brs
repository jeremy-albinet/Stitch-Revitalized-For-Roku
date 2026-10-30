' @include source/utils/ircEmotes.brs
' @include components/Modules/EmojiLabel/EmojiLabelUtil.brs
' @include components/Modules/EmojiLabel/EmojiLabelRegex.brs
sub main()
    emote = {
        data: {
            host: {
                url: "//cdn.7tv.app/emote/id", files: [
                    { name: "1x.webp", static_name: "1x.webp" },
                    { name: "2x.gif", static_name: "2x.png" },
                    { name: "1x.gif", static_name: "1x.png" }
                ]
            }
        }
    }
    if not chatEmoteAssert(irc7tvImage(emote) = "https://cdn.7tv.app/emote/id/1x.png", "7TV advertised static 1x PNG") then return
    if not chatEmoteAssert(irc7tvImage({ data: { animated: false, host: { url: "//cdn.7tv.app/emote/id", files: [{ name: "1x.webp" }] } } }) = "https://cdn.7tv.app/emote/id/1x.webp", "static WebP") then return
    animated = { data: { animated: true, host: { url: "https://cdn.7tv.app/emote/id", files: [{ name: "2x.webp", static_name: "2x_static.webp" }, { name: "1x.webp", static_name: "1x_static.webp" }] } } }
    if not chatEmoteAssert(irc7tvImage(animated) = "https://cdn.7tv.app/emote/id/1x_static.webp", "animated emote advertised static WebP, 1x preferred") then return
    if not chatEmoteAssert(irc7tvImage({ data: { host: { url: "//cdn.7tv.app/emote/id", files: [{ name: "1x.avif", static_name: "1x_static.avif" }] } } }) = invalid, "AVIF refused") then return
    if not chatEmoteAssert(irc7tvImage({ data: { animated: true, host: { url: "//cdn.7tv.app/emote/id", files: [{ name: "1x.webp", frame_count: 12 }] } } }) = invalid, "no guessed static rendition") then return
    if not chatEmoteAssert(irc7tvImage({ data: { host: { url: "http://bad", files: [] } } }) = invalid, "insecure host refused") then return
    if not chatEmoteAssert(irc7tvImage({ data: { host: { url: "https://cdn.example", files: "bad" } } }) = invalid, "malformed files refused") then return
    if not chatEmoteAssert(irc7tvImage({ data: { host: { files: [{}] } } }) = invalid, "missing host URL refused") then return
    if not chatEmoteAssert(irc7tvImage({ data: { host: { url: "https://cdn.example", files: [{ static_name: 1 }] } } }) = invalid, "malformed filename refused") then return
    if not chatEmoteAssert(irc7tvImage(invalid) = invalid, "missing emote") then return
    if not chatEmoteAssert(ircImageUrl("//cdn.frankerfacez.com/emote/1/1") = "https://cdn.frankerfacez.com/emote/1/1", "FFZ relative protocol") then return
    if not chatEmoteAssert(ircImageUrl("javascript:invalid") = invalid, "invalid image URL") then return
    if not chatEmoteAssert(ircBttvImage({ id: "id", imageType: "gif" }) = "https://cdn.betterttv.net/emote/id/static/1x.webp", "BTTV static rendition of animated source") then return
    if not chatEmoteAssert(ircBttvImage({ id: "id", imageType: "png" }) = "https://cdn.betterttv.net/emote/id/1x.png", "BTTV static source") then return
    merged = ircMergeEmoteCache({ Kappa: "https://twitch.example/kappa" }, { NewEmote: "https://cdn.example/new", Bad: invalid }, 2)
    if not chatEmoteAssert(merged.count() = 2 and merged.Kappa = "https://twitch.example/kappa" and merged.NewEmote = "https://cdn.example/new", "preserve IRC emotes during fetch") then return
    merged = ircMergeEmoteCache(merged, { Another: "https://cdn.example/another" }, 2)
    if not chatEmoteAssert(merged.count() = 2, "bounded emote cache") then return
    face = chr(&h1F600)
    if not chatEmoteAssert(ircEmoteText(face + " Kappa", 2, 5) = "Kappa", "Twitch code-point offsets after non-BMP emoji") then return
    if not chatEmoteAssert(ircEmoteText("abc", 2, 5) = "" and ircEmoteText("abc", -1, 2) = "", "invalid ranges do not poison cache") then return
    if not chatEmoteAssert(emojiCharacters(face + face).count() = 2, "long text never splits a surrogate pair") then return
    base = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.3/assets/72x72/"
    if not chatEmoteAssert(emojiPointName(chr(&h2764) + chr(&hFE0F)) = base + "2764.png", "heart VS16 normalization") then return
    if not chatEmoteAssert(emojiPointName("1" + chr(&hFE0F) + chr(&h20E3)) = base + "31-20e3.png", "keycap VS16 normalization") then return
    if not chatEmoteAssert(emojiPointName(chr(&h1F3F3) + chr(&hFE0F) + chr(&h200D) + chr(&h1F308)) = base + "1f3f3-fe0f-200d-1f308.png", "ZWJ preserves VS16") then return
    print "STITCH_TEST_PASS: chat emotes"
end sub

function chatEmoteAssert(condition as boolean, description as string) as boolean
    if not condition then print "STITCH_TEST_FAIL: chat emotes " + description
    return condition
end function
