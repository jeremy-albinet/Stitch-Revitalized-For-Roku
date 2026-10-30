function ircImageUrl(uri as dynamic) as dynamic
    if type(uri) <> "String" and type(uri) <> "roString" then return invalid
    if uri.left(2) = "//" then return "https:" + uri
    if uri.left(8) = "https://" then return uri
    return invalid
end function

' Select only advertised static images. Roku OS 15.1 supports WebP, but not AVIF.
function irc7tvImage(emote as dynamic) as dynamic
    host = emote?.data?.host
    if GetInterface(host?.files, "ifArray") = invalid then return invalid
    base = ircImageUrl(host.url)
    if base = invalid then return invalid
    fallback = invalid
    bestRank = 100
    for each file in host.files
        name = file?.static_name
        if GetInterface(name, "ifString") = invalid or name = ""
            ' An animated entry's name is not a static rendition.
            if GetInterface(file?.name, "ifString") <> invalid and file.name.right(4) = ".png"
                name = file.name
            else if emote?.data?.animated <> true and file?.frame_count <> invalid and file.frame_count <= 1
                name = file?.name
            else if emote?.data?.animated = false
                name = file?.name
            else
                name = invalid
            end if
        end if
        if GetInterface(name, "ifString") <> invalid
            rank = 100
            if name.right(4) = ".png" then rank = 2
            if name.right(5) = ".webp" then rank = 4
            if rank < 100 and (name.left(3) = "1x." or name.left(3) = "1x_") then rank -= 1
            if rank < bestRank
                bestRank = rank
                fallback = base + "/" + name
            end if
        end if
    end for
    return fallback
end function

' IRC ranges count Unicode code points. Some runtimes index strings as UTF-16.
function ircEmoteText(message as string, start as integer, length as integer) as string
    if start < 0 or length <= 0 then return ""
    position = 0
    codePoint = 0
    first = -1
    while position < message.len()
        if codePoint = start then first = position
        if codePoint = start + length then exit while
        value = asc(message.mid(position, 1))
        position++
        if value >= &hD800 and value <= &hDBFF and position < message.len()
            low = asc(message.mid(position, 1))
            if low >= &hDC00 and low <= &hDFFF then position++
        end if
        codePoint++
    end while
    if first < 0 or codePoint <> start + length then return ""
    return message.mid(first, position - first)
end function

function ircBttvImage(emote as object) as dynamic
    if emote?.id = invalid then return invalid
    imageType = emote?.imageType
    ' Use BTTV's own static rendition for a predictable, single Poster image.
    if imageType = "gif" or emote?.animated = true then return "https://cdn.betterttv.net/emote/" + emote.id + "/static/1x.webp"
    return "https://cdn.betterttv.net/emote/" + emote.id + "/1x.png"
end function

' Descriptors are keyed by the static URI, never by a provider's reusable word.
function ircBttvAnimation(emote as dynamic) as dynamic
    if GetInterface(emote?.id, "ifString") = invalid or emote.id = "" then return invalid
    if emote?.imageType <> "gif" and emote?.animated <> true then return invalid
    return { uri: "https://cdn.betterttv.net/emote/" + emote.id + "/1x.webp" }
end function

function irc7tvAnimation(emote as dynamic) as dynamic
    host = emote?.data?.host
    if GetInterface(host?.files, "ifArray") = invalid then return invalid
    base = ircImageUrl(host.url)
    if base = invalid then return invalid
    best = invalid
    bestWidth = 2147483647
    for each file in host.files
        name = file?.name
        if GetInterface(name, "ifString") <> invalid
            if name.right(5) = ".webp" and name.instr("/") < 0 and name.instr("static") < 0
                animated = emote?.data?.animated = true
                if GetInterface(file?.frame_count, "ifInt") <> invalid then animated = file.frame_count > 1
                if animated
                    width = bestWidth
                    if GetInterface(file?.width, "ifInt") <> invalid then width = file.width
                    if name = "1x.webp" then width = 0
                    if best = invalid or width < bestWidth
                        bestWidth = width
                        best = { uri: base + "/" + name }
                    end if
                end if
            end if
        end if
    end for
    return best
end function

function ircMergeEmoteCache(current as object, fetched as object, maxEntries = 10000 as integer) as object
    for each item in fetched.items()
        uri = ircImageUrl(item.value)
        if uri <> invalid and item.key <> ""
            if current.doesExist(item.key) or current.count() < maxEntries
                current[item.key] = uri
            end if
        end if
    end for
    return current
end function
