' @include source/utils/ircParser.brs
' @include source/utils/ircEmotes.brs
' @include source/utils/ircGifs.brs
sub main()
    m.checks = 0
    m.failures = 0
    ' Twitch's documented PRIVMSG example, not a live capture.
    ' https://dev.twitch.tv/docs/chat/irc/#privmsg-tags
    uri = "https://media4.giphy.com/media/joSNxeswxuc74Juo8X/giphy.gif?cid=095d7a5dzizsiwgabonagkmigggv8v1spfai91ac3x0dsiy0&ep=v1_gifs_trending&rid=giphy.gif&ct=g"
    title = "[Y A Y Yes GIF by Djemilah Birnie]"
    wire = "@badge-info=subscriber/30;badges=broadcaster/1,subscriber/0;color=#033700;display-name=TwitchDev;emotes=;first-msg=0;flags=;gifs=0-33|joSNxeswxuc74Juo8X|" + uri + ";id=401abf17-7e99-45d6-9bdf-43934e839327;mod=0;returning-chatter=0;room-id=12826;subscriber=1;tmi-sent-ts=1783632907018;turbo=0;user-id=141981764;user-type= :twitchdev!twitchdev@twitchdev.tmi.twitch.tv PRIVMSG #twitch :" + title
    parsed = ircParseMessage(wire)
    original = formatJson(parsed)
    attachments = ircGifAttachments(parsed.tags, parsed.parameters)
    check(attachments.count() = 1, "documented plural gifs tag")
    if attachments.count() = 1
        item = attachments[0]
        check(item.start = 0 and item.length = 34 and item.text = title, "inclusive source range and actual title")
        check(item.id = "joSNxeswxuc74Juo8X" and item.uri = uri, "exact ID and complete supplied query")
    end if
    check(formatJson(parsed) = original and parsed.parameters = title, "parser does not mutate tags, identity or body")
    ' All cases below are authored negative/Unicode fixtures, not Twitch captures.
    short = "https://media4.giphy.com/media/example/giphy.gif"
    tag = "|example|" + short
    for each bad in [invalid, {}, [], 1, true, { gifs: invalid }, { gifs: 1 }, { gif: "0-0" + tag }, { gifs: "" }]
        check(ircGifAttachments(bad, "abc").count() = 0, "missing/wrong-type/singular tag")
    end for
    for each bad in ["-1-0", "1-0", "0-3", "9999-9999", "00000-0", "0.0-1", "0e0-1", "+0-1", "a-1", "0", "0-1-2", " 0-1"]
        check(ircGifAttachments({ gifs: bad + tag }, "abc").count() = 0, "invalid or out-of-body range " + bad)
    end for
    for each bad in ["0-0||" + short, "0-0|a b|" + short, "0-0|id|" + short + "|extra", "0-0|" + string(129, "x") + "|" + short]
        check(ircGifAttachments({ gifs: bad }, "abc").count() = 0, "invalid entry fields/ID")
    end for
    entries = ircGifAttachments({ gifs: "4-5" + tag + ",0-1" + tag + ",1-4" + tag + ",4-5" + tag + ",2-3" + tag }, "abcdef")
    check(entries.count() = 3, "overlap/duplicate removed while adjacent entries survive")
    if entries.count() = 3 then check(entries[0].text = "ab" and entries[1].text = "cd" and entries[2].text = "ef", "output sorted by source position")
    entries = ircGifAttachments({ gifs: "0-0" + tag + ",bad," + "2-2" + tag }, "abc")
    check(entries.count() = 2, "malformed entries rejected independently")
    entries = ircGifAttachments({ gifs: "2-4" + tag }, "😀 [X]!")
    check(entries.count() = 1, "non-BMP prefix counts one code point")
    if entries.count() = 1 then check(entries[0].start = 2 and entries[0].length = 3 and entries[0].text = "[X]", "source code-point offsets retained")
    entries = ircGifAttachments({ gifs: "0-2" + tag }, "[😀]!")
    check(entries.count() = 1, "non-BMP title occurrence admitted")
    if entries.count() = 1 then check(entries[0].text = "[😀]" and entries[0].length = 3, "non-BMP title remains intact")
    check(ircGifAttachments({ gifs: "3-4" + tag }, "😀 abc").count() = 1, "Unicode range through final character")
    check(ircGifAttachments({ gifs: "4-5" + tag }, "😀 abc").count() = 0, "UTF-16 length cannot authorize an out-of-body code-point range")
    check(ircGifAttachments({ gifs: string(8193, "x") }, "abc").count() = 0, "oversized tag bounded")
    check(ircGifAttachments({ gifs: "0-0" + tag }, string(1501, "x")).count() = 0, "oversized message bounded")
    many = ""
    for index = 0 to 31
        if index > 0 then many += ","
        many += index.toStr() + "-" + index.toStr() + tag
    end for
    check(ircGifAttachments({ gifs: many }, string(40, "x")).count() = 8, "eight retained attachments bounded")
    check(ircGifAttachments({ gifs: many + ",32-32" + tag }, string(40, "x")).count() = 0, "maximum 32 input entries bounded")
    for each bad in ["http://media4.giphy.com/media/a/giphy.gif", "https://media4.giphy.com:443/media/a/giphy.gif", "https://user@media4.giphy.com/media/a/giphy.gif", "https://media4.giphy.com.evil.test/media/a/giphy.gif", "https://evil.test/media/a/giphy.gif", "https://127.0.0.1/media/a/giphy.gif", "https://[::1]/media/a/giphy.gif", "https://localhost/media/a/giphy.gif", "https://media4.giphy.com/redirect/giphy.gif", "https://media4.giphy.com/media/../giphy.gif", "https://media4.giphy.com/media/%2e%2e/giphy.gif", short + "#fragment", short + chr(10), short + chr(92), short + "?x= a", short + "?x=" + string(2048, "a")]
        check(ircGifUri(bad) = invalid and ircGifAttachments({ gifs: "0-0|id|" + bad }, "abc").count() = 0, "unsafe/unbounded URL rejected")
    end for
    exact = short + "?a=b=c&escaped=%2F%3B&order=2&order=1"
    check(ircGifUri(exact) = exact, "query bytes/order/duplicates never normalized")
    escaped = ircParseMessage("@gifs=0-0|id|" + short + "?x=a\:b&z=c=d :nick!nick@host PRIVMSG #twitch :X")
    check(ircGifAttachments(escaped.tags, escaped.parameters)[0].uri = short + "?x=a;b&z=c=d", "tag unescape once, preserve equals/semicolon query")
    if m.failures = 0 then print "STITCH_TEST_PASS: chat-gifs "; m.checks; " assertions"
end sub

sub check(ok as boolean, label as string)
    m.checks++
    if not ok
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
