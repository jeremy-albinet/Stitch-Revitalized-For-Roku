' Observed Twitch stitched-ad DATERANGEs only. No media/control/network changes.
' Metadata ownership and a proven presented UTC clock belong to the caller.

function tadString(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "String" or kind = "roString"
end function

function tadNumber(value as dynamic) as boolean
    kind = type(value, 3)
    ' Single precision absolute UTC cannot represent a truthful seconds tick.
    if kind <> "Integer" and kind <> "LongInteger" and kind <> "roInt" and kind <> "Double" and kind <> "roDouble" then return false
    return value = value and value >= 0 and value <= 4102444800000000#
end function

function tadNatural(text as string, maximum as longinteger) as dynamic
    if text.Len() < 1 or text.Len() > 16 then return invalid
    value = 0&
    for i = 0 to text.Len() - 1
        digit = Asc(text.Mid(i, 1)) - 48
        if digit < 0 or digit > 9 then return invalid
        if value > (maximum - digit) \ 10& then return invalid
        value = value * 10& + digit
    end for
    if value > maximum then return invalid
    return value
end function

function tadDurationUs(text as string) as dynamic
    parts = text.Split(".")
    if parts.Count() < 1 or parts.Count() > 2 then return invalid
    whole = tadNatural(parts[0], 3600&)
    if whole = invalid then return invalid
    fraction = 0&
    if parts.Count() = 2
        digits = parts[1]
        if digits.Len() < 1 or digits.Len() > 6 then return invalid
        fraction = tadNatural(digits, 999999&)
        if fraction = invalid then return invalid
        for i = digits.Len() to 5
            fraction *= 10&
        end for
    end if
    value = whole * 1000000& + fraction
    if value < 1& or value > 3600000000& then return invalid
    return value
end function

function tadLeap(year as integer) as boolean
    return year mod 4 = 0 and (year mod 100 <> 0 or year mod 400 = 0)
end function

function tadUtcUs(text as string) as dynamic
    size = text.Len()
    if size < 20 or size > 27 then return invalid
    if text.Mid(4, 1) <> "-" or text.Mid(7, 1) <> "-" or text.Mid(10, 1) <> "T" or text.Mid(13, 1) <> ":" or text.Mid(16, 1) <> ":" or text.Right(1) <> "Z" then return invalid
    year = tadNatural(text.Left(4), 2099&)
    month = tadNatural(text.Mid(5, 2), 12&)
    day = tadNatural(text.Mid(8, 2), 31&)
    hour = tadNatural(text.Mid(11, 2), 23&)
    minute = tadNatural(text.Mid(14, 2), 59&)
    second = tadNatural(text.Mid(17, 2), 59&)
    if year = invalid or month = invalid or day = invalid or hour = invalid or minute = invalid or second = invalid then return invalid
    if year < 1970& or month < 1& or day < 1& then return invalid
    monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if tadLeap(year) then monthDays[1] = 29
    if day > monthDays[CInt(month - 1&)] then return invalid
    fraction = 0&
    if size > 20
        if text.Mid(19, 1) <> "." then return invalid
        fraction = tadNatural(text.Mid(20, size - 21), 999999&)
        if fraction = invalid then return invalid
        for i = size - 21 to 5
            fraction *= 10&
        end for
    end if
    days = 0&
    for prior = 1970 to year - 1
        days += 365&
        if tadLeap(prior) then days += 1&
    end for
    for prior = 0 to month - 2
        days += monthDays[prior]
    end for
    days += day - 1&
    return (days * 86400& + hour * 3600& + minute * 60& + second) * 1000000& + fraction
end function

' Unknown attribute values are scanned, never copied into retained state.
' Native matching replaces per-character Mid() scans that took 1.6-3.2 s per
' ad playlist poll on a G204X, stalling the worker while ads started. The
' grammar is unchanged: keys [A-Z0-9-]{1,64}; non-empty quoted values of
' printable ASCII without quotes; non-empty unquoted values without quotes
' or commas; comma separators; at most 128 unique keys.
function tadAttributes(line as string) as dynamic
    if line.Len() < 18 or line.Len() > 32768 or line.Left(17) <> "#EXT-X-DATERANGE:" then return invalid
    q = Chr(34)
    value = "(?:" + q + "[ !#-~]+" + q + "|[ !#-+.-~-]+)"
    if not CreateObject("roRegex", "^#EXT-X-DATERANGE:[A-Z0-9-]{1,64}=" + value + "(?:,[A-Z0-9-]{1,64}=" + value + ")*$", "").IsMatch(line) then return invalid
    matches = CreateObject("roRegex", "([A-Z0-9-]+)=(?:" + q + "[^" + q + "]*" + q + "|[^," + q + "]*)", "").MatchAll(line.Mid(17))
    if matches.Count() < 1 or matches.Count() > 128 then return invalid
    known = ["CLASS", "START-DATE", "DURATION", "X-TV-TWITCH-AD-POD-LENGTH", "X-TV-TWITCH-AD-POD-POSITION"]
    seen = {}
    attributes = {}
    for each match in matches
        key = match[1]
        if seen.DoesExist(key) then return invalid
        seen[key] = true
        ' Read the value from the whole match: engines number unmatched
        ' alternation groups differently.
        text = match[0].Mid(key.Len() + 1)
        if text.Left(1) = q then text = text.Mid(1, text.Len() - 2)
        for each allowed in known
            if key = allowed then attributes[key] = text
        end for
    end for
    return attributes
end function

function tadCue(attributes as object) as dynamic
    if attributes["CLASS"] <> "twitch-stitched-ad" then return invalid
    if not tadString(attributes["START-DATE"]) or not tadString(attributes["DURATION"]) then return invalid
    startUs = tadUtcUs(attributes["START-DATE"])
    durationUs = tadDurationUs(attributes["DURATION"])
    if startUs = invalid or durationUs = invalid then return invalid
    podCount = 0&
    podPosition = -1&
    countKey = "X-TV-TWITCH-AD-POD-LENGTH"
    positionKey = "X-TV-TWITCH-AD-POD-POSITION"
    if attributes.DoesExist(countKey) and attributes.DoesExist(positionKey)
        podCount = tadNatural(attributes[countKey], 32&)
        podPosition = tadNatural(attributes[positionKey], 31&)
        if podCount = invalid or podPosition = invalid then return invalid
        if podCount < 1& or podPosition >= podCount then return invalid
    end if
    return { startUs: startUs, endUs: startUs + durationUs, durationUs: durationUs, podCount: podCount, podPosition: podPosition }
end function

function twitchAdCountdownRange(line as dynamic) as dynamic
    try
        if not tadString(line) then return invalid
        attributes = tadAttributes(line)
        if attributes = invalid then return invalid
        return tadCue(attributes)
    catch error
        return invalid
    end try
end function

function tadCuesValid(cues as dynamic) as boolean
    if type(cues) <> "roArray" or cues.Count() > 32 then return false
    prior = invalid
    for each cue in cues
        if type(cue) <> "roAssociativeArray" or cue.Count() <> 5 then return false
        for each key in ["startUs", "endUs", "durationUs", "podCount", "podPosition"]
            if not cue.DoesExist(key) then return false
            kind = type(cue[key], 3)
            if kind <> "Integer" and kind <> "LongInteger" and kind <> "roInt" then return false
        end for
        if cue.startUs < 0& or cue.startUs > 4102444800000000& or cue.durationUs < 1& or cue.durationUs > 3600000000& or cue.endUs <> cue.startUs + cue.durationUs then return false
        if cue.podCount = 0&
            if cue.podPosition <> -1& then return false
        else if cue.podCount < 1& or cue.podCount > 32& or cue.podPosition < 0& or cue.podPosition >= cue.podCount
            return false
        end if
        if prior <> invalid
            if cue.startUs <= prior.startUs then return false
            overlap = prior.endUs - cue.startUs
            if overlap > 0&
                if overlap > 1000& or cue.podCount = 0& or cue.podCount <> prior.podCount or cue.podPosition <> prior.podPosition + 1& then return false
            end if
        end if
        prior = cue
    end for
    return true
end function

function twitchAdCountdownRanges(text as dynamic) as dynamic
    try
        if not tadString(text) then return invalid
        if text.Len() > 262144 then return invalid
        lines = text.Split(Chr(10))
        if lines.Count() > 8192 then return invalid
        cues = []
        rangeCount = 0
        for each line in lines
            if line.Right(1) = Chr(13) then line = line.Left(line.Len() - 1)
            if line.Left(17) = "#EXT-X-DATERANGE:"
                rangeCount += 1
                if rangeCount > 128 then return invalid
                attributes = tadAttributes(line)
                if attributes = invalid then return invalid
                if attributes["CLASS"] = "twitch-stitched-ad"
                    cue = tadCue(attributes)
                    if cue = invalid then return invalid
                    duplicate = false
                    updated = []
                    inserted = false
                    for each existing in cues
                        if existing.startUs = cue.startUs
                            if existing.endUs <> cue.endUs or existing.podCount <> cue.podCount or existing.podPosition <> cue.podPosition then return invalid
                            duplicate = true
                        end if
                        if not inserted and cue.startUs < existing.startUs
                            updated.Push(cue)
                            inserted = true
                        end if
                        updated.Push(existing)
                    end for
                    if not duplicate
                        if not inserted then updated.Push(cue)
                        cues = updated
                        if cues.Count() > 32 then return invalid
                    end if
                end if
            end if
        end for
        if not tadCuesValid(cues) then return invalid
        return cues
    catch error
        return invalid
    end try
end function

function tadOwner(value as dynamic) as boolean
    if not tadString(value) then return false
    if value.Len() < 1 or value.Len() > 64 then return false
    for i = 0 to value.Len() - 1
        character = Asc(value.Mid(i, 1))
        if (character < 65 or character > 90) and (character < 97 or character > 122) and (character < 48 or character > 57) and character <> 45 and character <> 95 then return false
    end for
    return true
end function

function twitchAdCountdownBegin(owner as dynamic) as dynamic
    if not tadOwner(owner) then return invalid
    return { version: 1, owner: owner, cues: [], closed: false }
end function

function tadState(state as dynamic, owner as dynamic) as boolean
    if type(state) <> "roAssociativeArray" or state.Count() <> 4 then return false
    return state.version = 1 and state.closed = false and tadOwner(owner) and state.owner = owner and tadCuesValid(state.cues)
end function

function twitchAdCountdownSet(state as dynamic, owner as dynamic, text as dynamic) as boolean
    try
        if not tadState(state, owner) then return false
        cues = twitchAdCountdownRanges(text)
        if cues = invalid
            state.cues = []
            return false
        end if
        state.cues = cues
        return true
    catch error
        return false
    end try
end function

' Relative epoch needs independently proven source/presentation mapping.
function twitchAdCountdownClock(positionInfo as dynamic) as dynamic
    try
        if type(positionInfo) <> "roAssociativeArray" or positionInfo.Count() > 16 then return invalid
        kind = type(positionInfo.epoch, 3)
        if kind <> "Integer" and kind <> "LongInteger" and kind <> "roInt" then return invalid
        if positionInfo.epoch <> 1 or not tadNumber(positionInfo.video) then return invalid
        if positionInfo.video > 4102444800# then return invalid
        return positionInfo.video * 1000000#
    catch error
        return invalid
    end try
end function

function twitchAdCountdownView(state as dynamic, owner as dynamic, presentedUtcUs as dynamic, playbackState as dynamic) as object
    hidden = { visible: false, remainingSeconds: 0, number: 0, count: 0 }
    try
        if not tadState(state, owner) or not tadNumber(presentedUtcUs) then return hidden
        if playbackState <> "playing" and playbackState <> "paused" and playbackState <> "buffering" then return hidden
        selected = invalid
        for each cue in state.cues
            if presentedUtcUs >= cue.startUs and presentedUtcUs < cue.endUs then selected = cue
        end for
        if selected = invalid then return hidden
        remaining = selected.endUs - presentedUtcUs
        seconds = Int(remaining / 1000000#)
        if seconds * 1000000# < remaining then seconds += 1
        number = 0
        if selected.podCount > 0 then number = selected.podPosition + 1
        return { visible: true, remainingSeconds: seconds, number: number, count: selected.podCount }
    catch error
        return hidden
    end try
end function

function twitchAdCountdownEnd(state as dynamic, owner as dynamic) as boolean
    try
        if not tadState(state, owner) then return false
        state.cues = []
        state.closed = true
        state.owner = ""
        return true
    catch error
        return false
    end try
end function
