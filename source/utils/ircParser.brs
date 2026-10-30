' IRC helpers are independent of SceneGraph so wire-format regressions can run offline.
function ircWebSocketText(info as dynamic) as dynamic
    if getInterface(info, "ifAssociativeArray") = invalid then return invalid
    text = info.text
    if getInterface(text, "ifString") = invalid then return invalid
    return text
end function

function ircParseMessage(message as dynamic, acceptChat = true as boolean) as dynamic
    if type(message) <> "String" and type(message) <> "roString" then return invalid
    if message.len() = 0 or message.len() > 8192 then return invalid
    while message.right(1) = chr(13) or message.right(1) = chr(10)
        message = message.left(message.len() - 1)
    end while
    if message.instr(chr(13)) >= 0 or message.instr(chr(10)) >= 0 then return invalid
    parsed = { tags: {}, source: invalid, command: {}, parameters: "" }
    rawTags = ""
    index = 0
    if message.left(1) = "@"
        ending = message.instr(" ")
        if ending < 2 then return invalid
        rawTags = message.mid(1, ending - 1)
        index = ending + 1
    end if
    while index < message.len() and message.mid(index, 1) = " "
        index++
    end while
    if message.mid(index, 1) = ":"
        index++
        ending = message.instr(index, " ")
        if ending < index then return invalid
        parsed.source = ircParseSource(message.mid(index, ending - index))
        index = ending + 1
    end if
    remainder = message.mid(index)
    if remainder.trim() = "" then return invalid
    trailing = remainder.instr(" :")
    if trailing >= 0
        parsed.parameters = remainder.mid(trailing + 2)
        remainder = remainder.left(trailing)
    end if
    parts = remainder.tokenize(" ")
    if parts.count() = 0 then return invalid
    parsed.command = { command: ucase(parts[0]) }
    if parts.count() > 1 then parsed.command.channel = parts[1]
    if parsed.command.command = "PING" and trailing < 0 and parts.count() > 1
        parsed.parameters = parts[1]
    end if
    command = parsed.command.command
    if not acceptChat and (command = "PRIVMSG" or command = "USERNOTICE") then return invalid
    if rawTags <> "" then parsed.tags = ircParseTags(rawTags)
    if command = "PRIVMSG" or command = "USERNOTICE"
        if parts.count() < 2 or parts[1].left(1) <> "#" then return invalid
        if command = "PRIVMSG" and trailing < 0 then return invalid
        if parsed.parameters.len() > 1500 then return invalid
        if command = "USERNOTICE"
            systemMessage = parsed.tags.system_msg
            if systemMessage = invalid then systemMessage = ""
            if systemMessage.len() > 1500 then return invalid
            if systemMessage.trim() = "" and parsed.parameters.trim() = "" then return invalid
        end if
        if not parsed.tags.doesExist("display_name") or parsed.tags.display_name = ""
            if command = "USERNOTICE"
                parsed.tags.display_name = ""
                if parsed.tags.login <> invalid then parsed.tags.display_name = parsed.tags.login
            else if parsed.source <> invalid and parsed.source.nick <> invalid
                parsed.tags.display_name = parsed.source.nick
            else
                return invalid
            end if
        end if
        if parsed.tags.doesExist("emotes")
            parsed.tags.emotes = ircValidEmoteRanges(parsed.tags.emotes, parsed.parameters.len())
        end if
    end if
    return parsed
end function

function ircParseSource(source as string) as object
    separator = source.instr("!")
    if separator >= 0
        return { nick: source.left(separator), host: source.mid(separator + 1) }
    end if
    return { nick: invalid, host: source }
end function

function ircUnescapeTag(value as string) as string
    if value.instr(chr(92)) < 0 then return value
    result = ""
    index = 0
    while index < value.len()
        char = value.mid(index, 1)
        if char = chr(92)
            index++
            if index >= value.len() then exit while
            char = value.mid(index, 1)
            if char = ":"
                char = ";"
            else if char = "s"
                char = " "
            else if char = "r"
                char = chr(13)
            else if char = "n"
                char = chr(10)
            end if
        end if
        result += char
        index++
    end while
    return result
end function

function ircParseTags(tags as string) as object
    result = {}
    for each tag in tags.split(";")
        separator = tag.instr("=")
        if separator < 1 then continue for
        key = tag.left(separator).replace("-", "_")
        value = ircUnescapeTag(tag.mid(separator + 1))
        if key = "badges" or key = "badge_info"
            result[key] = []
            if value <> "" then result[key] = value.split(",")
        else if key = "emotes"
            result[key] = ircParseEmotes(value)
        else if key = "emote_sets"
            result[key] = value.split(",")
        else if key <> "client_nonce" and key <> "flags"
            result[key] = value
        end if
    end for
    return result
end function

function ircIsDigits(value as string) as boolean
    if value = "" or value.len() > 16 then return false
    for index = 0 to value.len() - 1
        char = asc(value.mid(index, 1))
        if char < 48 or char > 57 then return false
    end for
    return true
end function

function ircParseEmotes(value as string) as object
    result = {}
    if value = "" then return result
    idPattern = createObject("roRegex", "^[A-Za-z0-9_-]{1,128}$", "")
    for each emote in value.split("/")
        parts = emote.split(":")
        if parts.count() <> 2 then continue for
        if not idPattern.isMatch(parts[0]) then continue for
        ranges = []
        for each position in parts[1].split(",")
            range = position.split("-")
            if range.count() <> 2 then continue for
            if not ircIsDigits(range[0]) or not ircIsDigits(range[1]) then continue for
            startPosition = val(range[0])
            endPosition = val(range[1])
            if startPosition < 0 or endPosition < startPosition or endPosition >= 8192 then continue for
            ranges.push({ startPosition: startPosition, endPosition: endPosition })
        end for
        if ranges.count() > 0 then result[parts[0]] = ranges
    end for
    return result
end function

function ircValidEmoteRanges(emotes as object, messageLength as integer) as object
    result = {}
    for each emote in emotes.items()
        ranges = []
        for each range in emote.value
            if range.startPosition >= 0 and range.endPosition < messageLength
                ranges.push(range)
            end if
        end for
        if ranges.count() > 0 then result[emote.key] = ranges
    end for
    return result
end function

' Keep an incomplete line across reads; discard oversized lines through their next LF.
function ircConsumeChunk(state as object, chunk as string, maxLineLength = 8192 as integer) as object
    lines = []
    text = state.buffer + chunk
    discarding = state.discarding
    index = 0
    while true
        ending = text.instr(index, chr(10))
        if ending < 0 then exit while
        line = text.mid(index, ending - index)
        if not discarding and line.len() <= maxLineLength
            if line.right(1) = chr(13) then line = line.left(line.len() - 1)
            if line <> "" then lines.push(line)
        end if
        discarding = false
        index = ending + 1
    end while
    buffer = text.mid(index)
    if discarding or buffer.len() > maxLineLength
        buffer = ""
        discarding = true
    end if
    return { buffer: buffer, discarding: discarding, lines: lines }
end function

function ircLoginLines(channel as string, secure as boolean, username as string, token as string, anonymousNick as string) as object
    if not createObject("roRegex", "^[a-z0-9_]{1,25}$", "").isMatch(channel) then return []
    lines = ["CAP REQ :twitch.tv/tags twitch.tv/commands"]
    if secure and createObject("roRegex", "^[a-z0-9_]{1,25}$", "").isMatch(username) and createObject("roRegex", "^[A-Za-z0-9]+$", "").isMatch(token)
        lines.push("PASS oauth:" + token)
        lines.push("NICK " + username)
    else
        lines.push("PASS SCHMOOPIIE")
        lines.push("NICK " + anonymousNick)
    end if
    lines.push("JOIN #" + channel)
    return lines
end function

' Moderation identities are short ASCII tokens: message UUIDs, numeric user IDs
' and logins. Anything else is treated as absent.
function ircIdentity(value as dynamic) as string
    if getInterface(value, "ifString") = invalid then return ""
    if value = "" or value.len() > 64 then return ""
    value = lcase(value)
    for index = 0 to value.len() - 1
        char = asc(value.mid(index, 1))
        if (char < 48 or char > 57) and (char < 97 or char > 122) and char <> 45 and char <> 95 then return ""
    end for
    return value
end function

' Retained with each chat message so later moderation can remove it.
function ircMessageIdentity(message as object) as object
    login = invalid
    if message.source <> invalid then login = message.source.nick
    if message.command.command = "USERNOTICE" then login = message.tags.login
    return { id: ircIdentity(message.tags.id), userId: ircIdentity(message.tags.user_id), login: ircIdentity(login) }
end function

' CLEARMSG removes one message. CLEARCHAT removes one user's messages, or every
' message when it names nobody. Malformed notices are ignored, never widened.
function ircModerationEvent(message as object) as dynamic
    command = message.command.command
    if command = "CLEARMSG"
        id = ircIdentity(message.tags.target_msg_id)
        if id = "" then return invalid
        return { kind: "message", id: id, userId: "", login: "" }
    end if
    if command <> "CLEARCHAT" then return invalid
    if message.parameters = "" and not message.tags.doesExist("target_user_id")
        return { kind: "room", id: "", userId: "", login: "" }
    end if
    userId = ircIdentity(message.tags.target_user_id)
    login = ircIdentity(message.parameters)
    if userId = "" and login = "" then return invalid
    return { kind: "user", id: "", userId: userId, login: login }
end function

function ircModerationMatches(identity as dynamic, event as object) as boolean
    if event.kind = "room" then return true
    if identity = invalid then return false
    if event.kind = "message" then return event.id <> "" and identity.id = event.id
    if event.userId <> "" and identity.userId = event.userId then return true
    return event.login <> "" and identity.login = event.login
end function

function ircBoundedDelay(delaySeconds as dynamic, forceLive as boolean) as float
    if forceLive then return 0
    if type(delaySeconds) <> "Float" and type(delaySeconds) <> "Double" and type(delaySeconds) <> "Integer" and type(delaySeconds) <> "roFloat" and type(delaySeconds) <> "roInt" then return 0
    if delaySeconds < 0 then return 0
    if delaySeconds > 60 then return 60
    return delaySeconds
end function
