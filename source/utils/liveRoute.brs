' Live lists routed through the built-in server look like http://127.0.0.1:PORT/live?u=<encoded Twitch url>.

function isLiveRouted(url as dynamic) as boolean
    if url = invalid then return false
    s = url.toStr()
    return s.InStr("127.0.0.1") >= 0 and s.InStr("/live?u=") >= 0
end function

' Gives back the direct Twitch link a routed live URL was made from. Twitch links are plain ASCII.
function directLiveUrl(url as string) as string
    marker = "/live?u="
    at = url.InStr(marker)
    if at < 0 then return url
    parts = url.Mid(at + marker.Len()).Split("%")
    direct = parts[0]
    for i = 1 to parts.Count() - 1
        direct = direct + Chr(Val(parts[i].Left(2), 16)) + parts[i].Mid(2)
    end for
    return direct
end function
