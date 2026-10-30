' @include source/utils/ircParser.brs
sub main()
    malformedInfo = [invalid, "PING :server", 5, false, [], {}, { text: invalid }, { text: 5 }, { text: false }, { text: [] }, { text: {} }, { text: createObject("roByteArray") }]
    for each info in malformedInfo
        if not chatAssert(ircWebSocketText(info) = invalid, "malformed WebSocket event info rejected") then return
    end for
    if not chatAssert(ircWebSocketText({ Text: "" }) = "", "empty TextReceived event remains valid") then return
    chunk = ircWebSocketText({ Text: "PING :server" + chr(13) + chr(10) + "partial" })
    consumed = ircConsumeChunk({ buffer: "", discarding: false }, chunk)
    if not chatAssert(consumed.lines.count() = 1 and consumed.buffer = "partial", "valid TextReceived frame preserves IRC framing") then return
    ping = ircParseMessage(consumed.lines[0])
    if not chatAssert(ping.command.command = "PING" and ping.parameters = "server", "valid TextReceived keepalive remains parseable") then return

    raw = "@badges=moderator/1;color=#00FF00;display-name=Tester;tmi-sent-ts=1760000000123 :tester!tester@tester.tmi.twitch.tv PRIVMSG #channel :Hello : world"
    message = ircParseMessage(raw)
    if not chatAssert(message <> invalid, "tagged PRIVMSG") then return
    if not chatAssert(message.source.host = "tester@tester.tmi.twitch.tv", "prefix length") then return
    if not chatAssert(message.source.nick = "tester", "source nick") then return
    if not chatAssert(message.tags.tmi_sent_ts = "1760000000123", "timestamp whitespace") then return
    if not chatAssert(message.command.command = "PRIVMSG" and message.command.channel = "#channel", "command and channel") then return
    if not chatAssert(message.parameters = "Hello : world", "embedded colon") then return
    if not chatAssert(message.tags.badges[0] = "moderator/1", "badges") then return
    escaped = "A" + chr(92) + "sB" + chr(92) + ":C" + chr(92) + chr(92) + "D" + chr(92) + "nE" + chr(92) + "rF" + chr(92) + "q"
    expected = "A B;C" + chr(92) + "D" + chr(10) + "E" + chr(13) + "Fq"
    if not chatAssert(ircUnescapeTag(escaped) = expected, "IRCv3 escapes") then return
    message = ircParseMessage("@display-name=Name" + chr(92) + "sHere;emotes=25:2-6,99-103/bad$id:0-2/26:4-1/27:a-b/28/29:0-1 :user!user@host PRIVMSG #channel :  Kappa  ")
    if not chatAssert(message.parameters = "  Kappa  ", "message spaces preserve offsets") then return
    if not chatAssert(message.tags.display_name = "Name Here", "escaped display name") then return
    if not chatAssert(message.tags.emotes.count() = 2, "bad emote groups discarded") then return
    if not chatAssert(message.tags.emotes["25"].count() = 1, "out-of-message range discarded") then return
    if not chatAssert(message.tags.emotes["25"][0].startPosition = 2 and message.tags.emotes["25"][0].endPosition = 6, "valid range retained") then return
    emotes = ircParseEmotes("emotesv2_a123:0-4")
    if not chatAssert(emotes.doesExist("emotesv2_a123"), "string emote identifiers retained") then return
    message = ircParseMessage(":fallback!login@host PRIVMSG #channel :No tags")
    if not chatAssert(message.tags.display_name = "fallback", "tagless display fallback") then return
    ping = ircParseMessage("PING :server.example")
    if not chatAssert(ping.command.command = "PING" and ping.parameters = "server.example", "PING payload") then return
    reconnect = ircParseMessage(":tmi.twitch.tv RECONNECT")
    if not chatAssert(reconnect.command.command = "RECONNECT", "RECONNECT") then return
    if not chatAssert(ircParseMessage("@broken") = invalid, "malformed tags") then return
    if not chatAssert(ircParseMessage(":broken") = invalid, "malformed prefix") then return
    if not chatAssert(ircParseMessage("PRIVMSG #channel") = invalid, "missing message") then return
    if not chatAssert(ircParseMessage(invalid) = invalid, "invalid input") then return
    if not chatAssert(ircParseMessage("PING :a" + chr(10) + "PRIVMSG #x :b") = invalid, "embedded line rejection") then return

    state = ircConsumeChunk({ buffer: "", discarding: false }, "PING :ser")
    if not chatAssert(state.lines.count() = 0 and state.buffer = "PING :ser", "partial line") then return
    state = ircConsumeChunk(state, "ver" + chr(13))
    if not chatAssert(state.lines.count() = 0, "split CRLF") then return
    state = ircConsumeChunk(state, chr(10) + ":tmi RECONNECT" + chr(13) + chr(10) + "tail")
    if not chatAssert(state.lines.count() = 2 and state.lines[0] = "PING :server" and state.lines[1] = ":tmi RECONNECT", "combined lines") then return
    if not chatAssert(state.buffer = "tail", "unfinished tail retained") then return
    state = ircConsumeChunk({ buffer: "", discarding: false }, "123456789", 8)
    if not chatAssert(state.discarding and state.buffer = "", "oversized line bounded") then return
    state = ircConsumeChunk(state, "ignored" + chr(10) + "good" + chr(10), 8)
    if not chatAssert(state.lines.count() = 1 and state.lines[0] = "good" and not state.discarding, "resume after oversized line") then return

    lines = ircLoginLines("channel", false, "signedin", "SecretAccountToken", "justinfan12345")
    if not chatAssert(lines.count() = 4 and lines[1] = "PASS SCHMOOPIIE" and lines[2] = "NICK justinfan12345", "anonymous TCP login") then return
    for each line in lines
        if not chatAssert(line.instr("SecretAccountToken") < 0 and line.instr("signedin") < 0, "plaintext credential exclusion") then return
    end for
    lines = ircLoginLines("channel", true, "signedin", "SecretAccountToken", "justinfan12345")
    if not chatAssert(lines[1] = "PASS oauth:SecretAccountToken", "WSS auth retained") then return
    if not chatAssert(ircLoginLines("bad" + chr(13) + chr(10) + "JOIN #other", false, "", "", "justinfan12345").count() = 0, "channel injection rejected") then return
    lines = ircLoginLines("channel", true, "signedin", "token" + chr(10), "justinfan12345")
    if not chatAssert(lines[1] = "PASS SCHMOOPIIE", "invalid token uses anonymous login") then return
    if not chatAssert(ircBoundedDelay(23.5, false) = 23.5 and ircBoundedDelay(90, false) = 60 and ircBoundedDelay(-1, false) = 0, "bounded measured delay") then return
    if not chatAssert(ircBoundedDelay(23, true) = 0 and ircBoundedDelay(invalid, false) = 0, "immediate and invalid delay") then return
    print "STITCH_TEST_PASS: chat"
end sub

function chatAssert(condition as boolean, description as string) as boolean
    if not condition then print "STITCH_TEST_FAIL: chat " + description
    return condition
end function
