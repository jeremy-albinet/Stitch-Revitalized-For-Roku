' Twitch PRIVMSG gifs: inclusive code-point range|ID|URL, comma-separated.
' Keep the exact unescaped URL: dev.twitch.tv/docs/chat/irc/#privmsg-tags.
function ircGifUri(uri as dynamic) as dynamic
    if GetInterface(uri, "ifString") = invalid then return invalid
    if uri.len() > 2048 or uri.len() = 0 then return invalid
    if createObject("roRegex", "[^!-~]", "").isMatch(uri) then return invalid
    if uri.instr(chr(92)) >= 0 or uri.instr("#") >= 0 or uri.instr("|") >= 0 then return invalid
    resource = uri
    query = resource.instr("?")
    if query >= 0 then resource = resource.left(query)
    ' Explicit media origins and a literal media path exclude userinfo, ports,
    ' IPs, encoded path traversal and arbitrary GIPHY endpoints/redirectors.
    if not createObject("roRegex", "^https://media[0-4]?[.]giphy[.]com/media/[A-Za-z0-9_-]{1,128}/[A-Za-z0-9_-]{1,128}[.]gif$", "").isMatch(resource) then return invalid
    return uri
end function

' Bound input/work independently of the wire parser. Malformed entries retain
' their original text; the first non-overlapping entry wins, then sort by start.
function ircGifAttachments(tags as dynamic, message as string) as object
    attachments = []
    if GetInterface(tags, "ifAssociativeArray") = invalid or message.len() > 1500 then return attachments
    value = tags.gifs
    if GetInterface(value, "ifString") = invalid then return attachments
    if value.len() = 0 or value.len() > 8192 then return attachments
    entries = value.split(",")
    if entries.count() > 32 then return attachments
    rangePattern = createObject("roRegex", "^[0-9]{1,4}-[0-9]{1,4}$", "")
    idPattern = createObject("roRegex", "^[A-Za-z0-9_-]{1,128}$", "")
    for each entry in entries
        fields = entry.split("|")
        if fields.count() <> 3 then continue for
        if not rangePattern.isMatch(fields[0]) or not idPattern.isMatch(fields[1]) then continue for
        uri = ircGifUri(fields[2])
        if uri = invalid then continue for
        positions = fields[0].split("-")
        start = positions[0].toInt()
        finish = positions[1].toInt()
        if start > finish or finish >= 1500 then continue for
        length = finish - start + 1
        text = ircEmoteText(message, start, length)
        if text = "" then continue for
        overlaps = false
        for each attachment in attachments
            if start < attachment.start + attachment.length and finish >= attachment.start then overlaps = true
        end for
        if overlaps then continue for
        attachments.push({ start: start, length: length, id: fields[1], uri: uri, text: text })
        if attachments.count() = 8 then exit for
    end for
    ' Insertion sort over at most eight entries; never mutate the caller's tags.
    for index = 1 to attachments.count() - 1
        item = attachments[index]
        previous = index - 1
        while previous >= 0
            if attachments[previous].start <= item.start then exit while
            attachments[previous + 1] = attachments[previous]
            previous--
        end while
        attachments[previous + 1] = item
    end for
    return attachments
end function
