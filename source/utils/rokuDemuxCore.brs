' Private experimental Task state. No network/file/socket/player operations in this file.
sub nlCheck(ok as boolean, reason as string)
    if not ok then throw "native-live: " + reason
end sub

function nlString(value as dynamic) as boolean
    return Type(value) = "String" or Type(value) = "roString"
end function

sub nlInteger(value as dynamic, minimum as longinteger, maximum as longinteger)
    kind = Type(value, 3)
    nlCheck(kind = "Integer" or kind = "LongInteger" or kind = "roInt", "integral value required")
    nlCheck(value >= minimum and value <= maximum, "integer bound")
end sub

function nlNatural(text as string, maximum as longinteger) as longinteger
    nlCheck(text.Len() >= 1 and text.Len() <= 12, "invalid decimal length")
    value = 0&
    for i = 0 to text.Len() - 1
        digit = Asc(text.Mid(i, 1)) - 48
        nlCheck(digit >= 0 and digit <= 9, "invalid decimal digit")
        nlCheck(digit <= maximum and value <= (maximum - digit) \ 10&, "decimal exceeds bound")
        value = value * 10& + digit
    end for
    return value
end function

' Per-character Mid() scans cost ~57 us per character on a G204X (about
' 1.3 s per 16 KB playlist poll, far more during ads), so match natively.
' Chr(92) avoids source backslashes, which engines read differently.
sub nlUrlText(text as string)
    nlCheck(text.Len() >= 1 and text.Len() <= 8192, "URL length bound")
    nlCheck(not CreateObject("roRegex", "[^!-~]|[#" + Chr(92) + Chr(92) + "]", "").IsMatch(text), "URL character unsupported")
end sub

function nlHttps(url as string) as object
    nlUrlText(url)
    nlCheck(url.Left(8) = "https://", "HTTPS required")
    rest = url.Mid(8)
    boundary = rest.Len()
    for each separator in ["/", "?"]
        at = rest.InStr(separator)
        if at >= 0 and at < boundary then boundary = at
    end for
    host = rest.Left(boundary)
    nlCheck(host.Len() >= 3 and host.Len() <= 253 and host.InStr(".") > 0, "hostname required")
    nlCheck(CreateObject("roRegex", "^[A-Za-z0-9.-]+$", "").IsMatch(host), "hostname character unsupported")
    nlCheck(not CreateObject("roRegex", "^[0-9.]+$", "").IsMatch(host), "IP literal unsupported")
    for each label in host.Split(".")
        nlCheck(label.Len() >= 1 and label.Len() <= 63, "hostname label bound")
        nlCheck(label.Left(1) <> "-" and label.Right(1) <> "-", "hostname label malformed")
    end for
    pathQuery = rest.Mid(boundary)
    if pathQuery = "" or pathQuery.Left(1) = "?" then pathQuery = "/" + pathQuery
    query = ""
    at = pathQuery.InStr("?")
    if at >= 0
        query = pathQuery.Mid(at)
        pathQuery = pathQuery.Left(at)
    end if
    return { origin: "https://" + LCase(host), path: pathQuery, query: query }
end function

function nlPath(path as string) as string
    nlCheck(path.Left(1) = "/", "absolute path required")
    parts = path.Split("/")
    nlCheck(parts.Count() <= 128, "URL path work bound")
    normalized = []
    for each part in parts
        if part = "."
            ' Literal dot only; signed/escaped query and percent bytes are not decoded.
        else if part = ".."
            nlCheck(normalized.Count() > 1, "URL path escapes root")
            discard = normalized.Pop()
        else
            normalized.Push(part)
        end if
    end for
    tail = parts[parts.Count() - 1]
    if tail = "." or tail = ".." then normalized.Push("")
    result = normalized.Join("/")
    if result = "" then result = "/"
    return result
end function

function nlOrigins(baseOrigin as string, allowed as dynamic) as object
    origins = [baseOrigin]
    if allowed = invalid then return origins
    nlCheck(Type(allowed) = "roArray" and allowed.Count() <= 16, "approved origin count bound")
    for each entry in allowed
        nlCheck(nlString(entry), "approved origin must be string")
        parsed = nlHttps(entry)
        nlCheck(parsed.path = "/" and parsed.query = "" and entry = parsed.origin, "approved origin must be exact origin")
        found = false
        for each known in origins
            if known = entry then found = true
        end for
        if not found then origins.Push(entry)
    end for
    nlCheck(origins.Count() <= 16, "approved origin count bound")
    return origins
end function

function nativeLiveResolve(baseUrl as string, reference as string, approvedOrigins = invalid as dynamic) as string
    base = nlHttps(baseUrl)
    origins = nlOrigins(base.origin, approvedOrigins)
    nlUrlText(reference)
    if reference.Left(8) = "https://"
        absolute = nlHttps(reference)
        permitted = false
        for each origin in origins
            if origin = absolute.origin then permitted = true
        end for
        nlCheck(permitted, "URL origin not approved")
        return reference ' Preserve the already absolute signed URI exactly.
    end if
    if reference.Left(2) = "//" then return nativeLiveResolve(baseUrl, "https:" + reference, origins)
    first = reference.Split("/")[0]
    nlCheck(first.InStr(":") < 0, "URL scheme unsupported")
    if reference.Left(1) = "?" then return base.origin + base.path + reference
    query = ""
    path = reference
    at = path.InStr("?")
    if at >= 0
        query = path.Mid(at)
        path = path.Left(at)
    end if
    if path.Left(1) <> "/"
        slash = -1
        for i = 0 to base.path.Len() - 1
            if base.path.Mid(i, 1) = "/" then slash = i
        end for
        path = base.path.Left(slash + 1) + path
    end if
    result = base.origin + nlPath(path) + query
    nlUrlText(result)
    return result
end function

function nlAttributes(text as string) as object
    nlCheck(text.Len() >= 1 and text.Len() <= 8192, "attribute length bound")
    result = {}
    cursor = 0
    count = 0
    while cursor < text.Len()
        equals = text.Mid(cursor).InStr("=")
        nlCheck(equals > 0 and equals <= 64, "attribute name malformed")
        name = text.Mid(cursor, equals)
        nlCheck(CreateObject("roRegex", "^[A-Z0-9-]+$", "").IsMatch(name), "attribute name malformed")
        nlCheck(not result.DoesExist(name), "duplicate attribute")
        cursor += equals + 1
        nlCheck(cursor < text.Len(), "attribute value missing")
        if text.Mid(cursor, 1) = Chr(34)
            cursor += 1
            finish = text.Mid(cursor).InStr(Chr(34))
            nlCheck(finish >= 0, "attribute quote missing")
            value = text.Mid(cursor, finish)
            cursor += finish + 1
        else
            finish = text.Mid(cursor).InStr(",")
            if finish < 0 then finish = text.Len() - cursor
            value = text.Mid(cursor, finish)
            cursor += finish
        end if
        result[name] = value
        count += 1
        nlCheck(count <= 16, "attribute work bound")
        if cursor < text.Len()
            nlCheck(text.Mid(cursor, 1) = ",", "attribute separator malformed")
            cursor += 1
            nlCheck(cursor < text.Len(), "attribute trailing comma")
        end if
    end while
    return result
end function

function nlDuration(text as string) as longinteger
    parts = text.Split(".")
    nlCheck(parts.Count() = 1 or parts.Count() = 2, "duration malformed")
    whole = nlNatural(parts[0], 30&)
    fraction = 0&
    if parts.Count() = 2
        nlCheck(parts[1].Len() >= 1 and parts[1].Len() <= 6, "duration precision unsupported")
        padded = parts[1] + string(6 - parts[1].Len(), "0")
        fraction = nlNatural(padded, 999999&)
    end if
    result = whole * 1000000& + fraction
    nlCheck(result > 0& and result <= 30000000&, "duration bound")
    return result
end function

function nativeLiveParsePlaylist(text as string, baseUrl as string, approvedOrigins = invalid as dynamic) as object
    base = nlHttps(baseUrl)
    origins = nlOrigins(base.origin, approvedOrigins)
    nlCheck(text.Len() > 0 and text.Len() <= 262144, "playlist string bound")
    nlCheck(not CreateObject("roRegex", "[^ -~" + Chr(10) + Chr(13) + "]", "").IsMatch(text), "playlist character unsupported")
    lines = text.Split(Chr(10))
    nlCheck(lines.Count() <= 1024, "playlist line work bound")
    nlCheck(lines[0].Trim() = "#EXTM3U", "media playlist header required")
    target = -1
    sequence = -1&
    mapUrl = ""
    maps = []
    epoch = 0&
    epochDeclared = false
    discontinuities = 0
    duration = ""
    durationUs = 0&
    segments = []
    ended = false
    for lineIndex = 1 to lines.Count() - 1
        line = lines[lineIndex]
        if line.Right(1) = Chr(13) then line = line.Left(line.Len() - 1)
        lineLimit = 8192
        if line.Left(17) = "#EXT-X-DATERANGE:" then lineLimit = 32768
        nlCheck(line.Len() <= lineLimit and line = line.Trim(), "playlist line malformed")
        if line <> ""
            nlCheck(not ended, "content after ENDLIST")
            if line.Left(22) = "#EXT-X-TARGETDURATION:"
                nlCheck(target < 0 and segments.Count() = 0, "duplicate or late target duration")
                target = CInt(nlNatural(line.Mid(22), 30&))
                nlCheck(target >= 1, "target duration bound")
            else if line.Left(22) = "#EXT-X-MEDIA-SEQUENCE:"
                nlCheck(sequence < 0& and segments.Count() = 0, "duplicate or late media sequence")
                sequence = nlNatural(line.Mid(22), 4294967295&)
            else if line.Left(11) = "#EXT-X-MAP:"
                attrs = nlAttributes(line.Mid(11))
                nlCheck(attrs.Count() = 1 and attrs.DoesExist("URI"), "map byte range or attributes unsupported")
                resolved = nativeLiveResolve(baseUrl, attrs.URI, origins)
                knownMap = false
                for each known in maps
                    if known = resolved then knownMap = true
                end for
                if not knownMap then maps.Push(resolved)
                nlCheck(maps.Count() <= 16, "map count bound")
                mapUrl = resolved
            else if line.Left(8) = "#EXTINF:"
                nlCheck(duration = "", "EXTINF without segment")
                comma = line.Mid(8).InStr(",")
                nlCheck(comma >= 0, "EXTINF comma required")
                duration = line.Mid(8, comma)
                durationUs = nlDuration(duration)
            else if line = "#EXT-X-ENDLIST"
                nlCheck(duration = "", "ENDLIST after unfinished segment")
                ended = true
            else if line.Left(11) = "#EXT-X-KEY:"
                attrs = nlAttributes(line.Mid(11))
                nlCheck(attrs.Count() = 1 and attrs.METHOD = "NONE", "encrypted input unsupported")
            else if line.Left(30) = "#EXT-X-DISCONTINUITY-SEQUENCE:"
                nlCheck(not epochDeclared and segments.Count() = 0 and discontinuities = 0, "duplicate or late discontinuity sequence")
                epoch = nlNatural(line.Mid(30), 4294967295&)
                epochDeclared = true
            else if line = "#EXT-X-DISCONTINUITY"
                nlCheck(duration = "" and epoch < 4294967295&, "discontinuity boundary invalid")
                epoch += 1&
                discontinuities += 1
                nlCheck(discontinuities <= 128, "discontinuity work bound")
            else if line = "#EXT-X-INDEPENDENT-SEGMENTS" or line.Left(25) = "#EXT-X-PROGRAM-DATE-TIME:"
                ' Informational for this full-segment subset; original durations remain exact.
            else if line.Left(17) = "#EXT-X-DATERANGE:"
                ' Bounded metadata only; never filter or bypass any selected timeline.
            else if line.Left(15) = "#EXT-X-VERSION:"
                version = nlNatural(line.Mid(15), 10&)
                nlCheck(version >= 1&, "version unsupported")
            else if line.Left(19) = "#EXT-X-ALLOW-CACHE:"
                nlCheck(line.Mid(19) = "YES" or line.Mid(19) = "NO", "allow-cache value unsupported")
            else if line.Left(23) = "#EXT-X-TWITCH-PREFETCH:" or line.Left(25) = "#EXT-X-TWITCH-TOTAL-SECS:" or line.Left(27) = "#EXT-X-TWITCH-ELAPSED-SECS:" or line.Left(28) = "#EXT-X-TWITCH-LIVE-SEQUENCE:"
                ' Prefetch hints are not full completed segments and are never fetched.
            else if line.Left(1) = "#"
                nlCheck(line.Left(4) <> "#EXT", "HLS tag unsupported")
            else
                nlCheck(duration <> "" and target >= 1 and sequence >= 0& and mapUrl <> "", "segment prerequisites missing")
                nlCheck(durationUs <= target * 1000000& + 999999&, "segment exceeds target duration")
                nlCheck(segments.Count() < 128, "segment count bound")
                nlCheck(sequence <= 4294967295& - segments.Count(), "media sequence overflow")
                segments.Push({ sequence: sequence + segments.Count(), duration: duration, durationUs: durationUs, mapUrl: mapUrl, epoch: epoch, url: nativeLiveResolve(baseUrl, line, origins) })
                duration = ""
            end if
        end if
    end for
    nlCheck(duration = "" and target >= 1 and sequence >= 0& and mapUrl <> "" and segments.Count() > 0, "incomplete media playlist")
    return { mapUrl: mapUrl, mediaSequence: sequence, targetDuration: target, segments: segments, ended: ended }
end function

' windowUs above the six-second minimum gives the player a startup cushion;
' the steady server opts into a longer window (see serveBoundedLive).
function nlWindow(playlist as object, delayUs as longinteger, waitForStartup = false as boolean, sourceTransitions = false as boolean, windowUs = 6000000& as longinteger) as object
    nlCheck(not playlist.ended or delayUs = 0&, "historical ENDLIST unsupported")
    nlCheck(windowUs >= 6000000& and windowUs <= 16000000&, "window length bound")
    segments = playlist.segments
    finish = segments.Count() - 1
    behind = 0&
    while finish >= 0 and behind < delayUs
        behind += segments[finish].durationUs
        finish -= 1
    end while
    nlCheck(finish >= 0 and behind >= delayUs, "requested source delay unavailable")
    start = finish
    total = 0&
    count = 0
    while start >= 0 and (total < 6000000& or count < 3 or (total < windowUs and count < 8))
        total += segments[start].durationUs
        count += 1
        start -= 1
        nlCheck(count <= 8, "window segment bound")
    end while
    nlCheck(total >= 6000000& and count >= 3, "six-second source window unavailable")
    result = []
    for i = start + 1 to finish
        result.Push(segments[i])
    end for
    selectedMap = result[0].mapUrl
    selectedEpoch = result[0].epoch
    for each segment in result
        if sourceTransitions then exit for
        if waitForStartup and not playlist.ended
            if segment.mapUrl <> selectedMap or segment.epoch <> selectedEpoch then return invalid
        end if
        nlCheck(segment.mapUrl = selectedMap and segment.epoch = selectedEpoch, "selected window crosses map or discontinuity")
    end for
    return { segments: result, durationUs: total, sourceOffsetUs: behind, targetDuration: playlist.targetDuration, mapUrl: selectedMap, epoch: selectedEpoch, ended: playlist.ended }
end function

' Preserve every unpublished sequence still present in bounded upstream history.
function nlContinuityWindow(playlist as object, window as object, publishedLast as longinteger, sourceTransitions = false as boolean) as object
    nlInteger(publishedLast, 0&, 4294967295&)
    nextSequence = publishedLast + 1&
    if window.segments[0].sequence <= nextSequence then return window
    segments = playlist.segments
    finishSequence = window.segments[window.segments.Count() - 1].sequence
    start = -1
    finish = -1
    for i = 0 to segments.Count() - 1
        if segments[i].sequence = nextSequence then start = i
        if segments[i].sequence = finishSequence then finish = i
    end for
    nlCheck(start >= 0 and finish >= start, "continuity history unavailable")
    nlCheck(finish - start + 1 <= 8, "continuity window segment bound")
    result = []
    total = 0&
    for i = start to finish
        segment = segments[i]
        nlCheck(segment.sequence = nextSequence + i - start, "continuity sequence gap")
        if not sourceTransitions then nlCheck(segment.mapUrl = window.mapUrl and segment.epoch = window.epoch, "continuity window crosses map or discontinuity")
        total += segment.durationUs
        result.Push(segment)
    end for
    nlCheck(total >= 6000000& and result.Count() >= 3, "six-second continuity window unavailable")
    return { segments: result, durationUs: total, sourceOffsetUs: window.sourceOffsetUs, targetDuration: window.targetDuration, mapUrl: window.mapUrl, epoch: window.epoch, ended: window.ended }
end function

function nativeLiveCreate(mediaUrl as string, nowMs as dynamic, sourceDelaySeconds as integer, approvedOrigins = invalid as dynamic, trustedExperimentalTransport = false as dynamic, cacheBudgetBytes = 16777216& as dynamic, steadyOptions = invalid as dynamic) as object
    origin = nlHttps(mediaUrl)
    origins = nlOrigins(origin.origin, approvedOrigins)
    flagType = Type(trustedExperimentalTransport, 3)
    nlCheck(flagType = "Boolean" or flagType = "roBoolean", "experimental flag must be Boolean")
    nlInteger(cacheBudgetBytes, 16777216&, 33554432&)
    nlCheck(cacheBudgetBytes = 16777216& or cacheBudgetBytes = 25165824& or cacheBudgetBytes = 33554432&, "unsupported cache budget")
    nlCheck(cacheBudgetBytes = 16777216& or trustedExperimentalTransport, "larger cache budget requires experimental transport")
    steadyMode = false
    sourceTransitions = false
    sessionId = ""
    if steadyOptions <> invalid
        nlCheck(Type(steadyOptions) = "roAssociativeArray" and (steadyOptions.Count() = 2 or steadyOptions.Count() = 3), "steady options shape")
        nlCheck(steadyOptions.DoesExist("mode") and steadyOptions.DoesExist("sessionId"), "steady options keys")
        nlCheck(nlString(steadyOptions.mode) and steadyOptions.mode = "steady", "steady mode must be explicit")
        nlCheck(nlString(steadyOptions.sessionId), "steady session identity type")
        sessionId = steadyOptions.sessionId
        nlCheck(CreateObject("roRegex", "^[0-9a-f]{32}$", "").IsMatch(sessionId), "steady session identity shape")
        nlCheck(trustedExperimentalTransport, "steady mode requires experimental transport")
        if steadyOptions.Count() = 3
            nlCheck(steadyOptions.DoesExist("sourceTransitions"), "source transition option key")
            flagType = Type(steadyOptions.sourceTransitions, 3)
            nlCheck((flagType = "Boolean" or flagType = "roBoolean") and steadyOptions.sourceTransitions, "source transitions must be explicit true")
            sourceTransitions = true
        end if
        steadyMode = true
    end if
    clockCap = 2147400000&
    if steadyMode then clockCap = 4294967235000&
    nlInteger(nowMs, 0&, clockCap)
    nlInteger(sourceDelaySeconds, 0&, 60&)
    return { sourceUrl: mediaUrl, origin: origin.origin, approvedOrigins: origins, trustedExperimentalTransport: trustedExperimentalTransport, cacheBudgetBytes: cacheBudgetBytes, steadyMode: steadyMode, sourceTransitions: sourceTransitions, pollFromRequest: false, localEpoch: 0&, sessionId: sessionId, started: false, lastUpstreamProgress: nowMs, lastPublicationProgress: nowMs, quotaStart: nowMs, quotaSteps: 0, quotaTransfers: 0, phase: "playlist", deadline: nowMs + 45000&, lastNow: nowMs, delayUs: sourceDelaySeconds * 1000000&, window: invalid, mapUrl: "", epoch: -1&, tracks: invalid, initIds: [], initDigest: "", initByteCount: 0, initAliasCount: 0&, pendingWindow: invalid, pendingPlaylistSequence: -1&, assets: [], segments: [], generations: [], latest: 0, serial: 0, cacheBytes: 0, peakCacheBytes: 0, op: invalid, input: invalid, temporaryVideo: invalid, pendingSegment: invalid, nextPoll: nowMs, publishedFirst: -1&, publishedLast: -1&, lastPlaylistSequence: -1&, nextGeneration: 1, steps: 0, transfers: 0, playlistCount: 0, initPairCount: 0, segmentPairCount: 0, ownInputFile: false, error: "", failureCategory: 0, closed: false }
end function

' Called only after the sole playlist GET successfully starts, including retries.
sub nativeLivePlaylistStarted(state as object, nowMs as dynamic)
    if not state.pollFromRequest then return
    nlTime(state, nowMs)
    nlCheck(state.steadyMode and state.trustedExperimentalTransport and not state.closed and state.phase = "playlist", "playlist polling owner invalid")
    nlCheck(state.op <> invalid and state.input = invalid, "playlist polling operation missing")
    nlCheck(state.op.kind = "playlist" and state.op.phase = "get" and state.op.deadline = nowMs + 6000&, "playlist polling operation invalid")
    state.playlistRequestStartedAt = nowMs + 0&
    state.playlistRequestPending = true
end sub

' Reload timing starts at the request, not publication or conversion.
sub nlAcceptPlaylistPoll(state as object, text as string, target as integer, nowMs as dynamic, lastSequence = -1& as dynamic, lastDurationUs = 0& as dynamic)
    if not state.pollFromRequest then return
    nlCheck(state.DoesExist("playlistRequestStartedAt") and state.DoesExist("playlistRequestPending"), "playlist polling start missing")
    nlInteger(state.playlistRequestStartedAt, 0&, nowMs)
    nlCheck(state.playlistRequestPending = true and text.Len() > 0 and text.Len() <= 262144, "playlist polling snapshot invalid")
    nlInteger(target, 1&, 30&)
    ' Leave room for the existing6s operation inside the15s health deadline.
    if target >= 9
        state.pollFromRequest = false
        nlClearPlaylistPoll(state)
        return
    end if
    nlInteger(lastSequence, -1&, 4294967295&)
    nlInteger(lastDurationUs, 0&, 30000000&)
    advancing = false
    if lastSequence >= 0&
        advancing = true
        if state.DoesExist("playlistLastTail") then advancing = lastSequence > state.playlistLastTail
        if advancing then state.playlistLastTail = lastSequence
    end if
    interval = target * 1000&
    if state.DoesExist("playlistSnapshot")
        if state.playlistSnapshot = text then interval = target * 500&
    end if
    nearEdge = false
    if state.DoesExist("windowUs") then nearEdge = state.windowUs >= 6000000& and state.windowUs <= 8000000&
    if nearEdge and state.sourceTransitions and state.started and state.delayUs = 0& and lastSequence >= 0& and lastDurationUs > 0& and lastDurationUs < 2500000&
        ' Like hls.js computeReloadInterval, use the short tail only on media advance.
        ' This opt-in intentionally polls sooner than RFC8216's full target floor.
        interval = target * 500&
        if advancing
            interval = (lastDurationUs + 999&) \ 1000&
            if interval < 1000& then interval = 1000&
            if interval > target * 1000& then interval = target * 1000&
        end if
    end if
    state.nextPoll = state.playlistRequestStartedAt + interval
    state.playlistSnapshot = text
    state.playlistRequestPending = false
end sub

sub nlClearPlaylistPoll(state as object)
    for each key in ["playlistSnapshot", "playlistRequestStartedAt", "playlistRequestPending", "playlistLastTail"]
        state.Delete(key)
    end for
end sub

sub nlTime(state as object, nowMs as dynamic)
    clockCap = 2147400000&
    if state.steadyMode then clockCap = 4294967235000&
    nlInteger(nowMs, 0&, clockCap)
    nlCheck(nowMs >= state.lastNow, "clock moved backwards")
    state.lastNow = nowMs
    if not state.steadyMode or not state.started
        nlCheck(nowMs < state.deadline, "finite runtime complete")
    else
        nlCheck(nowMs - state.lastUpstreamProgress < 15000&, "upstream progress deadline")
        nlCheck(nowMs - state.lastPublicationProgress < 30000&, "publication progress deadline")
    end if
end sub

' Task-local bounded clock conversion; rejects rollback or >60s caller gaps.
function nativeLiveClockCreate(rawMs as dynamic) as object
    nlInteger(rawMs, -2147483648&, 4294967295&)
    raw = rawMs + 0&
    if raw < 0& then raw += 4294967296&
    return { raw: raw, elapsed: 0& }
end function

function nativeLiveClockAdvance(clock as object, rawMs as dynamic) as longinteger
    nlInteger(rawMs, -2147483648&, 4294967295&)
    nlInteger(clock.raw, 0&, 4294967295&)
    nlInteger(clock.elapsed, 0&, 4294967235000&)
    raw = rawMs + 0&
    if raw < 0& then raw += 4294967296&
    delta = raw - clock.raw
    if delta < 0& then delta += 4294967296&
    nlCheck(delta <= 60000&, "raw clock rollback or caller gap")
    nlCheck(delta <= 4294967235000& - clock.elapsed, "clock exhausted")
    clock.raw = raw
    clock.elapsed += delta
    return clock.elapsed
end function

sub nlIncrement(state as object, field as string)
    nlInteger(state[field], 0&, 4294967294&)
    state[field] += 1&
end sub

' Same finite ceilings per explicit60s interval in opted-in steady mode.
sub nlUseWork(state as object, kind as string, nowMs as dynamic, commit = true as boolean)
    nlCheck(kind = "tick" or kind = "transfer", "unknown work quota")
    field = "steps"
    limit = 12000
    quotaField = "quotaSteps"
    if kind = "transfer"
        field = "transfers"
        limit = 256
        quotaField = "quotaTransfers"
    end if
    if not state.steadyMode
        if kind = "tick" and commit
            state.steps += 1
            nlCheck(state.steps <= 12000, "scheduler work bound")
        else
            nlCheck(state[field] < limit, "upstream request count bound")
            if commit then state[field] += 1
        end if
        return
    end if
    nlInteger(nowMs, 0&, 4294967235000&)
    nlCheck(nowMs >= state.quotaStart, "work quota clock moved backwards")
    if nowMs - state.quotaStart >= 60000&
        state.quotaStart = nowMs
        state.quotaSteps = 0
        state.quotaTransfers = 0
    end if
    nlCheck(state[quotaField] < limit, "steady work interval bound")
    nlInteger(state[field], 0&, 4294967294&)
    if commit
        state[quotaField] += 1
        nlIncrement(state, field)
    end if
end sub

function nlAssetIndex(state as object, id as string) as integer
    for i = 0 to state.assets.Count() - 1
        if state.assets[i].id = id then return i
    end for
    return -1
end function

function nlSegmentIndex(state as object, sequence as longinteger) as integer
    for i = 0 to state.segments.Count() - 1
        if state.segments[i].sequence = sequence then return i
    end for
    return -1
end function

function nlMissing(state as object) as object
    for each segment in state.window.segments
        if nlSegmentIndex(state, segment.sequence) < 0 then return segment
    end for
    return invalid
end function

function nlIntent(state as object, nowMs as dynamic) as object
    nlTime(state, nowMs)
    if state.closed or state.phase = "failed" or state.phase = "ended" then return invalid
    if state.phase = "ready" and nowMs >= state.nextPoll then state.phase = "playlist"
    if state.phase = "playlist"
        if nowMs < state.nextPoll then return invalid
        return { kind: "playlist", url: state.sourceUrl, limit: 262144 }
    end if
    if state.phase = "init" then return { kind: "init", url: state.mapUrl, limit: 2097152 }
    if state.phase = "init-rotation" then return { kind: "init", url: state.pendingWindow.mapUrl, limit: 2097152 }
    if state.phase = "segment"
        segment = nlMissing(state)
        if segment <> invalid then return { kind: "segment", url: segment.url, limit: 4194304 }
    end if
    return invalid
end function

' Only opted-in, already-started playback selects a complete mixed window.
sub nlEpochAcceptWindow(state as object, parsed as object, window as object)
    for each segment in parsed.segments
        at = nlSegmentIndex(state, segment.sequence)
        if at >= 0
            old = state.segments[at]
            nlCheck(old.url = segment.url and old.duration = segment.duration and old.durationUs = segment.durationUs and old.mapUrl = segment.mapUrl and old.sourceEpoch = segment.epoch, "cached epoch segment identity changed")
        end if
    end for
    previous = invalid
    for each segment in window.segments
        if previous <> invalid then nlCheck(segment.epoch = previous.epoch or segment.epoch = previous.epoch + 1&, "source epoch progression invalid")
        previous = segment
    end for
    nlCheck(window.segments[0].sequence <= state.publishedLast + 1&, "source sequence gap")
    state.window = window
    state.lastPlaylistSequence = parsed.mediaSequence
    nlIncrement(state, "playlistCount")
    state.phase = "segment"
    nlEpochPrepare(state)
end sub

' Keep the old scalar init and advertised bodies until the next pair is complete.
sub nlEpochPrepare(state as object)
    segment = nlMissing(state)
    if segment = invalid then return
    nlCheck(segment.sequence > state.publishedLast, "published epoch history unavailable")
    nlCheck(segment.epoch = state.epoch or segment.epoch = state.epoch + 1&, "next source epoch invalid")
    localEpoch = state.localEpoch
    nlInteger(localEpoch, 0&, 4294967295&)
    if segment.epoch <> state.epoch
        nlInteger(localEpoch, 0&, 4294967294&)
        localEpoch += 1&
    end if
    if segment.mapUrl <> state.mapUrl
        nlCheck(state.initIds.Count() = 2 and state.initDigest <> "" and state.pendingWindow = invalid, "epoch initialization state invalid")
        state.pendingWindow = { mapUrl: segment.mapUrl, epoch: segment.epoch, localEpoch: localEpoch, sequence: segment.sequence }
        state.phase = "init-rotation"
    else
        state.epoch = segment.epoch
        state.localEpoch = localEpoch
    end if
end sub

sub nlEpochCommitInit(state as object, ids as object, tracks as object, digest as string, byteCount as integer)
    nlEpochPendingValid(state)
    pending = state.pendingWindow
    segment = nlMissing(state)
    nlCheck(pending <> invalid and segment <> invalid and pending.sequence = segment.sequence and pending.mapUrl = segment.mapUrl and pending.epoch = segment.epoch, "pending epoch initialization invalid")
    state.initIds = ids
    state.tracks = tracks
    state.initDigest = digest
    state.initByteCount = byteCount
    state.mapUrl = pending.mapUrl
    state.epoch = pending.epoch
    state.localEpoch = pending.localEpoch
    state.pendingWindow = invalid
    state.phase = "segment"
end sub

sub nlEpochPendingValid(state as object)
    pending = state.pendingWindow
    segment = nlMissing(state)
    nlCheck(Type(pending) = "roAssociativeArray" and segment <> invalid, "pending epoch initialization invalid")
    keys = ["mapUrl", "epoch", "localEpoch", "sequence"]
    if pending.Count() = 7 then keys = ["mapUrl", "epoch", "localEpoch", "sequence", "tracks", "digest", "byteCount"]
    nlCheck(loopbackKeys(pending, keys), "pending epoch initialization invalid")
    nlCheck(pending.sequence = segment.sequence and pending.mapUrl = segment.mapUrl and pending.epoch = segment.epoch, "pending epoch initialization invalid")
    nlInteger(pending.localEpoch, 0&, 4294967295&)
    expected = state.localEpoch + 0&
    if pending.epoch = state.epoch + 1& then expected += 1&
    nlCheck((pending.epoch = state.epoch or pending.epoch = state.epoch + 1&) and pending.localEpoch = expected, "pending local epoch invalid")
end sub

sub nativeLiveFeed(state as object, kind as string, payload as dynamic, nowMs as dynamic)
    nlCheck(state.op = invalid, "feed while transfer active")
    intent = nlIntent(state, nowMs)
    nlCheck(intent <> invalid and intent.kind = kind, "feed kind mismatch")
    if kind = "playlist"
        nlCheck(nlString(payload), "playlist payload must be string")
        parsed = nativeLiveParsePlaylist(payload, state.sourceUrl, state.approvedOrigins)
        nlCheck(parsed.mediaSequence >= state.lastPlaylistSequence, "playlist sequence moved backwards")
        tail = parsed.segments[parsed.segments.Count() - 1]
        waitForStartup = state.steadyMode and not state.started and state.publishedLast < 0& and state.initIds.Count() = 0 and not parsed.ended
        windowUs = 6000000&
        if state.DoesExist("windowUs") then windowUs = state.windowUs
        if state.sourceTransitions and state.started
            window = nlWindow(parsed, state.delayUs, false, true, windowUs)
        else
            window = nlWindow(parsed, state.delayUs, waitForStartup, false, windowUs)
        end if
        if window = invalid
            ' Wait on this normal mixed window; never select an older timeline.
            state.lastPlaylistSequence = parsed.mediaSequence
            nlIncrement(state, "playlistCount")
            state.nextPoll = nowMs + parsed.targetDuration * 500&
            nlAcceptPlaylistPoll(state, payload, parsed.targetDuration, nowMs, tail.sequence, tail.durationUs)
            if state.steadyMode then state.lastUpstreamProgress = nowMs
            return
        end if
        if window.segments[window.segments.Count() - 1].sequence < state.publishedLast
            ' A stale tail must not replace the window or consult retired history.
            state.phase = "ready"
            nlAcceptPlaylistPoll(state, payload, parsed.targetDuration, nowMs, tail.sequence, tail.durationUs)
            if not state.pollFromRequest then state.nextPoll = nowMs + parsed.targetDuration * 500&
            return
        end if
        if state.sourceTransitions and state.started
            window = nlContinuityWindow(parsed, window, state.publishedLast, true)
        end if
        ' Check after continuity: prepended older segments are published too.
        if state.sourceTransitions
            for each segment in window.segments
                nlCheck(segment.durationUs < 2500000& and segment.durationUs <= window.targetDuration * 1000000& + 499999&, "epoch source duration unsupported")
            end for
        end if
        if state.sourceTransitions and state.started
            nlEpochAcceptWindow(state, parsed, window)
            nlAcceptPlaylistPoll(state, payload, parsed.targetDuration, nowMs, tail.sequence, tail.durationUs)
            state.lastUpstreamProgress = nowMs
            return
        end if
        if state.publishedLast >= 0& then window = nlContinuityWindow(parsed, window, state.publishedLast)
        nlCheck(state.epoch < 0& or state.epoch = window.epoch, "selected discontinuity change unsupported")
        if state.publishedLast >= 0& then nlCheck(window.segments[0].sequence <= state.publishedLast + 1&, "source sequence gap")
        for each segment in window.segments
            cached = nlSegmentIndex(state, segment.sequence)
            if cached >= 0
                old = state.segments[cached]
                nlCheck(old.url = segment.url and old.duration = segment.duration, "cached segment identity changed")
            end if
        end for
        if state.mapUrl <> "" and state.mapUrl <> window.mapUrl
            nlCheck(state.initIds.Count() = 2 and state.initDigest <> "", "map rotation before initialization")
            state.pendingWindow = window
            state.pendingPlaylistSequence = parsed.mediaSequence
            state.phase = "init-rotation"
        else
            state.lastPlaylistSequence = parsed.mediaSequence
            state.mapUrl = window.mapUrl
            state.epoch = window.epoch
            state.window = window
            nlIncrement(state, "playlistCount")
            state.phase = "init"
            if state.initIds.Count() = 2 then state.phase = "segment"
        end if
        nlAcceptPlaylistPoll(state, payload, parsed.targetDuration, nowMs, tail.sequence, tail.durationUs)
    else
        nlCheck(Type(payload) = "roByteArray", "binary payload must be bytearray")
        nlCheck(payload.Count() > 0 and payload.Count() <= intent.limit, "binary payload bound")
        if kind = "init"
            digest = nlInitDigest(state, payload)
            if state.sourceTransitions and state.phase = "init-rotation"
                tracks = nlInspectEpochInit(payload)
                if payload.Count() = state.initByteCount and digest = state.initDigest
                    nlInteger(state.initAliasCount, 0&, 4294967294&)
                    nlEpochCommitInit(state, state.initIds, tracks, digest, payload.Count())
                    nlIncrement(state, "initAliasCount")
                else
                    pending = state.pendingWindow
                    pending.tracks = tracks
                    pending.digest = digest
                    pending.byteCount = payload.Count()
                    state.pendingWindow = pending
                    state.input = payload
                    state.phase = "init-video"
                end if
            else if state.phase = "init-rotation"
                nlCheck(state.pendingWindow <> invalid and state.pendingWindow.epoch = state.epoch, "pending map initialization invalid")
                nlInteger(state.initAliasCount, 0&, 4294967294&)
                nlInteger(state.playlistCount, 0&, 4294967294&)
                state.mapUrl = state.pendingWindow.mapUrl
                state.window = state.pendingWindow
                state.lastPlaylistSequence = state.pendingPlaylistSequence
                state.pendingWindow = invalid
                state.pendingPlaylistSequence = -1&
                nlIncrement(state, "playlistCount")
                nlIncrement(state, "initAliasCount")
                state.phase = "segment"
            else
                tracks = nativeDemuxBulkInspectInit(payload)
                video = 0
                audio = 0
                for each track in tracks
                    if track[1] = "video" then video += 1
                    if track[1] = "audio" then audio += 1
                end for
                nlCheck(tracks.Count() = 2 and video = 1 and audio = 1, "one video and one audio track required")
                state.initDigest = digest
                state.initByteCount = payload.Count()
                state.input = payload
                state.tracks = tracks
                state.phase = "init-video"
            end if
        else
            state.input = payload
            state.pendingSegment = nlMissing(state)
            nlCheck(state.pendingSegment <> invalid, "segment identity missing")
            if state.sourceTransitions then nlCheck(state.pendingSegment.mapUrl = state.mapUrl and state.pendingSegment.epoch = state.epoch and state.pendingWindow = invalid, "segment initialization binding invalid")
            state.phase = "segment-video"
        end if
    end if
    if state.steadyMode then state.lastUpstreamProgress = nowMs
end sub

function nlInspectEpochInit(payload as object) as object
    tracks = nativeDemuxBulkInspectInit(payload)
    video = 0
    audio = 0
    for each track in tracks
        if track[1] = "video" then video += 1
        if track[1] = "audio" then audio += 1
    end for
    nlCheck(tracks.Count() = 2 and video = 1 and audio = 1, "one video and one audio track required")
    return tracks
end function

' Native SHA256 plus exact length retains identity without retaining the original input.
function nlInitDigest(state as object, payload as object) as string
    nlCheck(Type(payload) = "roByteArray" and payload.Count() > 0 and payload.Count() <= 2097152, "initialization byte bound")
    digest = nlBodyDigest(payload)
    if state.phase = "init-rotation"
        if state.sourceTransitions
            nlEpochPendingValid(state)
            pending = state.pendingWindow
            nlCheck(pending.epoch = state.epoch or pending.epoch = state.epoch + 1&, "next source epoch invalid")
            if pending.epoch = state.epoch then nlCheck(payload.Count() = state.initByteCount and digest = state.initDigest, "selected map initialization changed")
        else
            nlCheck(payload.Count() = state.initByteCount and digest = state.initDigest, "selected map initialization changed")
        end if
    end if
    return digest
end function

function nlProtected(state as object, id as string) as boolean
    for each initId in state.initIds
        if initId = id then return true
    end for
    for each generation in state.generations
        if generation.advertised or generation.id = state.latest
            for each held in generation.ids
                if held = id then return true
            end for
        end if
    end for
    if state.window <> invalid
        for each segment in state.window.segments
            at = nlSegmentIndex(state, segment.sequence)
            if at >= 0
                saved = state.segments[at]
                if saved.videoId = id or saved.audioId = id then return true
                if state.sourceTransitions and (saved.initVideoId = id or saved.initAudioId = id) then return true
            end if
        end for
    end if
    return false
end function

sub nlPrune(state as object)
    retained = []
    for each asset in state.assets
        if asset.leases > 0 or nlProtected(state, asset.id)
            retained.Push(asset)
        else
            state.cacheBytes -= asset.size
        end if
    end for
    state.assets = retained
    segments = []
    for each segment in state.segments
        if nlAssetIndex(state, segment.videoId) >= 0 and nlAssetIndex(state, segment.audioId) >= 0
            keep = true
            if state.sourceTransitions then keep = nlAssetIndex(state, segment.initVideoId) >= 0 and nlAssetIndex(state, segment.initAudioId) >= 0
            if keep then segments.Push(segment)
        end if
    end for
    state.segments = segments
    generations = []
    for each generation in state.generations
        if generation.advertised or generation.id = state.latest then generations.Push(generation)
    end for
    state.generations = generations
end sub

' Numeric admission used by the actual atomic pair store; no allocation here.
sub nlCheckPairCacheBudget(cacheBytes as dynamic, pairBytes as dynamic, cacheBudgetBytes as dynamic)
    nlInteger(cacheBudgetBytes, 16777216&, 33554432&)
    nlCheck(cacheBudgetBytes = 16777216& or cacheBudgetBytes = 25165824& or cacheBudgetBytes = 33554432&, "unsupported cache budget")
    nlInteger(cacheBytes, 0&, cacheBudgetBytes)
    nlInteger(pairBytes, 2&, 8388608&)
    nlCheck(pairBytes <= cacheBudgetBytes - cacheBytes, "cache byte budget exceeded")
end sub

function nlStorePair(state as object, video as object, audio as object) as object
    nlCheck(Type(video) = "roByteArray" and Type(audio) = "roByteArray", "converted bytearray required")
    nlCheck(video.Count() > 0 and audio.Count() > 0 and video.Count() <= 4194304 and audio.Count() <= 4194304, "converted byte count bound")
    nlPrune(state)
    total = video.Count() + audio.Count() + 0&
    nlCheckPairCacheBudget(state.cacheBytes, total, state.cacheBudgetBytes)
    serialCap = 254&
    if state.steadyMode then serialCap = 4294967293&
    nlInteger(state.serial, 0&, 4294967295&)
    nlCheck(state.assets.Count() <= 62 and state.serial <= serialCap, "cache asset count bound")
    ids = []
    for each kind in ["video", "audio"]
        body = video
        if kind = "audio" then body = audio
        state.serial += 1&
        id = "live-" + state.serial.ToStr()
        if state.steadyMode then id = "live-" + state.sessionId + "-" + state.serial.ToStr()
        state.assets.Push({ id: id, mime: kind + "/mp4", kind: kind, size: body.Count(), data: body, digest: nlBodyDigest(body), leases: 0 })
        ids.Push(id)
    end for
    state.cacheBytes += CInt(total)
    if state.cacheBytes > state.peakCacheBytes then state.peakCacheBytes = state.cacheBytes
    return ids
end function

sub nlPublish(state as object, nowMs as dynamic)
    if nlMissing(state) <> invalid then return
    window = state.window
    first = window.segments[0].sequence
    last = window.segments[window.segments.Count() - 1].sequence
    if first <> state.publishedFirst or last <> state.publishedLast or window.ended
        nlPrune(state)
        nlCheck(state.generations.Count() < 12, "publication generation bound")
        if state.steadyMode then nlInteger(state.nextGeneration, 1&, 4294967295&)
        publication = { generation: state.nextGeneration, mediaSequence: first, targetDuration: window.targetDuration, initVideoId: state.initIds[0], initAudioId: state.initIds[1], durationUs: window.durationUs, sourceOffsetUs: window.sourceOffsetUs, ended: window.ended, segments: [] }
        ids = [state.initIds[0], state.initIds[1]]
        if state.sourceTransitions
            firstSaved = state.segments[nlSegmentIndex(state, first)]
            publication.version = 2
            publication.discontinuitySequence = firstSaved.localEpoch
            publication.targetDuration = 2
            publication.initVideoId = firstSaved.initVideoId
            publication.initAudioId = firstSaved.initAudioId
        end if
        publishedSegments = []
        for each segment in window.segments
            saved = state.segments[nlSegmentIndex(state, segment.sequence)]
            item = { sequence: segment.sequence, duration: segment.duration, durationUs: segment.durationUs, videoId: saved.videoId, audioId: saved.audioId }
            if state.sourceTransitions
                nlCheck(saved.mapUrl = segment.mapUrl and saved.sourceEpoch = segment.epoch and saved.durationUs = segment.durationUs, "publication epoch binding invalid")
                item.epoch = saved.localEpoch
                item.initVideoId = saved.initVideoId
                item.initAudioId = saved.initAudioId
            end if
            publishedSegments.Push(item)
            ids.Push(saved.videoId)
            ids.Push(saved.audioId)
        end for
        publication.segments = publishedSegments
        if state.sourceTransitions
            assets = loopbackPublicationAssets(publication)
            nlCheck(assets <> invalid, "epoch publication invalid")
            ids = []
            for each asset in assets
                nlCheck(nlAssetIndex(state, asset.id) >= 0, "epoch publication asset missing")
                ids.Push(asset.id)
            end for
        end if
        state.generations.Push({ id: state.nextGeneration, advertised: false, ids: ids, publication: publication })
        state.latest = state.nextGeneration
        state.nextGeneration += 1&
        if state.steadyMode
            state.started = true
            state.lastPublicationProgress = nowMs
        end if
        state.publishedFirst = first
        state.publishedLast = last
    end if
    state.phase = "ready"
    if window.ended then state.phase = "ended"
    if not state.pollFromRequest then state.nextPoll = nowMs + window.targetDuration * 500&
    nlPrune(state)
end sub

sub nativeLiveAdvance(state as object, nowMs as dynamic)
    nlTime(state, nowMs)
    nlCheck(state.op = invalid, "conversion while transfer active")
    if state.phase = "init-video"
        state.temporaryVideo = nativeDemuxBulkInit(state.input, "video")
        state.phase = "init-audio"
    else if state.phase = "init-audio"
        audio = nativeDemuxBulkInit(state.input, "audio")
        if state.sourceTransitions and state.pendingWindow <> invalid
            nlEpochPendingValid(state)
            pending = state.pendingWindow
            nlCheck(pending.digest = nlBodyDigest(state.input) and pending.byteCount = state.input.Count() and FormatJson(pending.tracks) = FormatJson(nlInspectEpochInit(state.input)), "staged initialization identity changed")
            nlInteger(state.initPairCount, 0&, 4294967294&)
            ids = nlStorePair(state, state.temporaryVideo, audio)
            nlEpochCommitInit(state, ids, pending.tracks, pending.digest, pending.byteCount)
        else
            state.initIds = nlStorePair(state, state.temporaryVideo, audio)
        end if
        nlIncrement(state, "initPairCount")
        state.input = invalid
        state.temporaryVideo = invalid
        state.phase = "segment"
    else if state.phase = "segment-video"
        state.temporaryVideo = nativeDemuxBulkFragment(state.input, state.tracks, "video")
        state.phase = "segment-audio"
    else if state.phase = "segment-audio"
        audio = nativeDemuxBulkFragment(state.input, state.tracks, "audio")
        ids = nlStorePair(state, state.temporaryVideo, audio)
        nlIncrement(state, "segmentPairCount")
        segment = state.pendingSegment
        saved = { sequence: segment.sequence, duration: segment.duration, url: segment.url, videoId: ids[0], audioId: ids[1] }
        if state.sourceTransitions
            saved.durationUs = segment.durationUs
            saved.mapUrl = segment.mapUrl
            saved.sourceEpoch = segment.epoch
            saved.localEpoch = state.localEpoch
            saved.initVideoId = state.initIds[0]
            saved.initAudioId = state.initIds[1]
        end if
        state.segments.Push(saved)
        state.input = invalid
        state.temporaryVideo = invalid
        state.pendingSegment = invalid
        state.phase = "segment"
    end if
    if state.sourceTransitions and state.phase = "segment" then nlEpochPrepare(state)
    if state.phase = "segment" and nlMissing(state) = invalid then nlPublish(state, nowMs)
end sub

function nativeLivePublication(state as object) as object
    for i = 0 to state.generations.Count() - 1
        generation = state.generations[i]
        if generation.id = state.latest
            generation.advertised = true
            state.generations[i] = generation
            original = generation.publication
            copy = { generation: original.generation, mediaSequence: original.mediaSequence, targetDuration: original.targetDuration, initVideoId: original.initVideoId, initAudioId: original.initAudioId, durationUs: original.durationUs, sourceOffsetUs: original.sourceOffsetUs, ended: original.ended, segments: [] }
            copiedSegments = []
            for each segment in original.segments
                copiedSegments.Push({ sequence: segment.sequence, duration: segment.duration, durationUs: segment.durationUs, videoId: segment.videoId, audioId: segment.audioId })
            end for
            copy.segments = copiedSegments
            if state.sourceTransitions
                copy.version = original.version
                copy.discontinuitySequence = original.discontinuitySequence
                for j = 0 to copiedSegments.Count() - 1
                    item = copiedSegments[j]
                    segment = original.segments[j]
                    item.epoch = segment.epoch
                    item.initVideoId = segment.initVideoId
                    item.initAudioId = segment.initAudioId
                    copiedSegments[j] = item
                end for
                copy.segments = copiedSegments
            end if
            return copy
        end if
    end for
    return invalid
end function

function nativeLiveAcquire(state as object, id as string) as object
    at = nlAssetIndex(state, id)
    if at < 0 then return invalid
    asset = state.assets[at]
    nlCheck(asset.leases < 8, "asset lease bound")
    nlCheck(Type(asset.data) = "roByteArray" and asset.data.Count() = asset.size, "cached asset mutated")
    nlCheck(nlBodyDigest(asset.data) = asset.digest, "cached asset mutated")
    asset.leases += 1
    state.assets[at] = asset
    return { id: asset.id, mime: asset.mime, kind: asset.kind, size: asset.size, data: asset.data }
end function

function nlBodyDigest(data as object) as string
    nlCheck(Type(data) = "roByteArray" and data.Count() > 0 and data.Count() <= 4194304, "cached bytearray bound")
    digest = CreateObject("roEVPDigest")
    nlCheck(digest <> invalid and digest.Setup("sha256") = 0, "cache digest unavailable")
    result = digest.Process(data)
    nlCheck(nlString(result) and result.Len() = 64, "cache digest result invalid")
    return LCase(result)
end function

sub nativeLiveRelease(state as object, id as string)
    at = nlAssetIndex(state, id)
    nlCheck(at >= 0, "release asset missing")
    asset = state.assets[at]
    nlCheck(asset.leases > 0, "release without lease")
    asset.leases -= 1
    state.assets[at] = asset
    nlPrune(state)
end sub

sub nativeLiveRetire(state as object, generationId as dynamic)
    nlInteger(generationId, 1&, 4294967295&)
    found = false
    for i = 0 to state.generations.Count() - 1
        generation = state.generations[i]
        if generation.id = generationId
            generation.advertised = false
            state.generations[i] = generation
            found = true
        end if
    end for
    nlCheck(found, "retire generation missing")
    nlPrune(state)
end sub

sub nlAbort(state as object, reason as string)
    nlClearPlaylistPoll(state)
    state.error = reason
    state.failureCategory = 1 ' Fixed native live/transport/parser failure category.
    if reason.Left(14) = "native-demux: " then state.failureCategory = 2
    state.phase = "failed"
    state.input = invalid
    state.temporaryVideo = invalid
    state.pendingSegment = invalid
    state.pendingWindow = invalid
    state.pendingPlaylistSequence = -1&
    ' Advertised/leased cached bodies remain until root closes serving clients.
end sub

function nativeLiveStatus(state as object) as object
    return { phase: state.phase, error: state.error, generation: state.latest, cacheBytes: state.cacheBytes, assetCount: state.assets.Count(), transferActive: state.op <> invalid, inputRetained: state.input <> invalid, closed: state.closed }
end function
