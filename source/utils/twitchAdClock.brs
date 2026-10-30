function twitchAdClockBoolean(value as dynamic) as boolean
    kind = type(value)
    return kind = "Boolean" or kind = "roBoolean"
end function

' Presentation time comes from Video, never from a wall clock or a seek request.
function twitchAdClockUtc(info as dynamic) as dynamic
    if type(info) <> "roAssociativeArray" then return invalid
    epochKind = type(info.epoch, 3)
    if epochKind <> "Integer" and epochKind <> "roInt" and epochKind <> "LongInteger" and epochKind <> "roLongInteger" then return invalid
    if info.epoch <> 1 then return invalid
    value = info.video
    kind = type(value, 3)
    if kind <> "Double" and kind <> "roDouble" and kind <> "Integer" and kind <> "roInt" and kind <> "LongInteger" and kind <> "roLongInteger" then return invalid
    if not tadNumber(value) or value < 0# or value > 2147483647# then return invalid
    ' Native Int accepts Float. Direct typed assignment preserves UTC seconds.
    seconds% = value
    if seconds% > value then seconds% -= 1
    fraction# = value - seconds%
    if fraction# < 0# or fraction# >= 1# then return invalid
    micros% = Int(fraction# * 1000000# + 0.5#)
    if micros% = 1000000
        if seconds% = 2147483647 then return invalid
        seconds% += 1
        micros% = 0
    end if
    if micros% < 0 or micros% > 999999 then return invalid
    return seconds% * 1000000& + micros%
end function

' Runs after, and never in place of, the existing validated feed. Retained data
' contains no URI or provider identifier; source equality is checked privately.
sub twitchAdClockCapture(state as object, kind as string, payload as dynamic, source as string)
    if kind <> "playlist" then return
    state.adClockTimeline = invalid
    state.adClockSource = ""
    if source <> state.sourceUrl or state.closed or state.phase = "failed" then return
    try
        timeline = twitchAdClockTimeline(payload)
        if not twitchAdClockTimelineValid(timeline) then return
        state.adClockTimeline = timeline
        state.adClockSource = state.sourceUrl
    catch e
        state.adClockTimeline = invalid
    end try
end sub

function twitchAdClockPublication(state as object, publication as dynamic) as dynamic
    if state.closed or state.phase = "failed" then return invalid
    if not tadString(state.adClockSource) or state.adClockSource <> state.sourceUrl then return invalid
    return twitchAdClockProject(state.adClockTimeline, publication, state.epoch)
end function

' Read only explicitly observed segment PDT; do not extrapolate across a gap,
' MAP/discontinuity, source change, or an unknown native epoch.
function twitchAdClockTimeline(text as dynamic) as dynamic
    cues = twitchAdCountdownRanges(text)
    if cues = invalid then return invalid
    lines = text.Split(Chr(10))
    if lines.Count() > 1024 then return invalid
    if lines[0].Trim() <> "#EXTM3U" then return invalid
    sequence = invalid
    epoch = 0&
    epochDeclared = false
    discontinuities = 0
    segments = []
    date = ""
    startUs = invalid
    durationUs = invalid
    ended = false
    for each raw in lines
        line = raw
        if line.Right(1) = Chr(13) then line = line.Left(line.Len() - 1)
        if line <> line.Trim() then return invalid
        if ended and line <> "" then return invalid
        if line.Left(22) = "#EXT-X-MEDIA-SEQUENCE:"
            if sequence <> invalid or segments.Count() > 0 then return invalid
            sequence = tadNatural(line.Mid(22), 4294967295&)
            if sequence = invalid then return invalid
        else if line.Left(30) = "#EXT-X-DISCONTINUITY-SEQUENCE:"
            if epochDeclared or segments.Count() > 0 or discontinuities > 0 then return invalid
            epoch = tadNatural(line.Mid(30), 4294967295&)
            if epoch = invalid then return invalid
            epochDeclared = true
        else if line = "#EXT-X-DISCONTINUITY"
            if durationUs <> invalid or epoch >= 4294967295& then return invalid
            epoch += 1&
            discontinuities += 1
            date = ""
            startUs = invalid
        else if line.Left(25) = "#EXT-X-PROGRAM-DATE-TIME:"
            if date <> "" then return invalid
            date = line.Mid(25)
            startUs = tadUtcUs(date)
            if startUs = invalid then return invalid
            if startUs > 2147483647000000& then return invalid
        else if line.Left(8) = "#EXTINF:"
            if durationUs <> invalid then return invalid
            comma = line.Mid(8).InStr(",")
            if comma < 0 then return invalid
            durationUs = tadDurationUs(line.Mid(8, comma))
            if durationUs = invalid then return invalid
            if durationUs > 10000000& then return invalid
        else if line = "#EXT-X-ENDLIST"
            if durationUs <> invalid then return invalid
            ended = true
        else if line.Left(18) = "#EXT-X-STREAM-INF:" or line.Left(26) = "#EXT-X-I-FRAME-STREAM-INF:"
            return invalid ' No guessed native Automatic rendition.
        else if line <> "" and line.Left(1) <> "#"
            if sequence = invalid or durationUs = invalid or startUs = invalid then return invalid
            if segments.Count() >= 128 or sequence > 4294967295& - segments.Count() then return invalid
            segments.Push({ sequence: sequence + segments.Count(), epoch: epoch, startUs: startUs, durationUs: durationUs, date: date })
            date = ""
            startUs = invalid
            durationUs = invalid
        end if
    end for
    if sequence = invalid or segments.Count() = 0 or durationUs <> invalid or date <> "" then return invalid
    return { cues: cues, segments: segments }
end function

function twitchAdClockTimelineValid(timeline as dynamic) as boolean
    if type(timeline) <> "roAssociativeArray" or timeline.Count() <> 2 then return false
    if not timeline.DoesExist("cues") or not timeline.DoesExist("segments") then return false
    if not tadCuesValid(timeline.cues) or type(timeline.segments) <> "roArray" then return false
    if timeline.segments.Count() < 1 or timeline.segments.Count() > 128 then return false
    previous = invalid
    for each segment in timeline.segments
        if type(segment) <> "roAssociativeArray" or segment.Count() <> 5 then return false
        for each key in ["sequence", "epoch", "startUs", "durationUs", "date"]
            if not segment.DoesExist(key) then return false
        end for
        for each key in ["sequence", "epoch", "startUs", "durationUs"]
            kind = type(segment[key], 3)
            if kind <> "Integer" and kind <> "roInt" and kind <> "LongInteger" and kind <> "roLongInteger" then return false
        end for
        if segment.sequence < 0& or segment.sequence > 4294967295& or segment.epoch < 0& or segment.epoch > 4294967295& then return false
        if segment.durationUs < 1& or segment.durationUs > 10000000& then return false
        if not tadString(segment.date) then return false
        utc = tadUtcUs(segment.date)
        if utc = invalid then return false
        if utc <> segment.startUs or utc > 2147483647000000& then return false
        if previous <> invalid
            if segment.sequence <> previous.sequence + 1& or segment.epoch < previous.epoch then return false
            difference = segment.startUs - previous.startUs - previous.durationUs
            if segment.epoch <> previous.epoch and difference < 0& then return false
            if segment.epoch = previous.epoch
                if difference < 0& or difference > 1000& then return false
            end if
        end if
        previous = segment
    end for
    return true
end function

' Publication projection is separate from the immutable canonical publication.
' Every anchor must match an actual selected source sequence and its epoch.
function twitchAdClockProject(timeline as dynamic, publication as dynamic, epoch as dynamic) as dynamic
    if not twitchAdClockTimelineValid(timeline) then return invalid
    if type(publication) <> "roAssociativeArray" or type(publication.segments) <> "roArray" then return invalid
    kind = type(epoch, 3)
    if kind <> "Integer" and kind <> "roInt" and kind <> "LongInteger" and kind <> "roLongInteger" then return invalid
    anchors = []
    for each target in publication.segments
        match = invalid
        for each source in timeline.segments
            if source.sequence = target.sequence then match = source
        end for
        if match = invalid then return invalid
        if match.epoch <> epoch or match.durationUs <> target.durationUs then return invalid
        anchors.Push({ sequence: match.sequence, epoch: match.epoch, startUs: match.startUs, durationUs: match.durationUs, date: match.date })
    end for
    projected = { cues: timeline.cues, segments: anchors }
    if not twitchAdClockTimelineValid(projected) then return invalid
    return projected
end function

function twitchAdClockIso(utcUs as longinteger) as string
    seconds% = utcUs / 1000000#
    if seconds% * 1000000& > utcUs then seconds% -= 1
    micros& = utcUs - seconds% * 1000000&
    date = CreateObject("roDateTime")
    date.FromSeconds(seconds%)
    text = date.ToISOString()
    if text.Right(1) <> "Z" then return ""
    text = text.Left(19)
    digits = micros&.ToStr()
    while digits.Len() < 6
        digits = "0" + digits
    end while
    return text + "." + digits + "Z"
end function

function twitchAdClockCueTags(cues as object) as string
    text = ""
    quote = Chr(34)
    for each cue in cues
        date = twitchAdClockIso(cue.startUs)
        if date = "" then return ""
        seconds% = cue.durationUs / 1000000#
        if seconds% * 1000000& > cue.durationUs then seconds% -= 1
        fraction& = cue.durationUs - seconds% * 1000000&
        digits = fraction&.ToStr()
        while digits.Len() < 6
            digits = "0" + digits
        end while
        text += "#EXT-X-DATERANGE:ID=" + quote + "stitch-ad-" + cue.startUs.ToStr() + quote + ",CLASS=" + quote + "twitch-stitched-ad" + quote + ",START-DATE=" + quote + date + quote + ",DURATION=" + seconds%.ToStr() + "." + digits
        if cue.podCount > 0 then text += ",X-TV-TWITCH-AD-POD-LENGTH=" + cue.podCount.ToStr() + ",X-TV-TWITCH-AD-POD-POSITION=" + cue.podPosition.ToStr()
        text += Chr(10)
    end for
    return text
end function

function twitchAdClockBoundsValid(bounds as dynamic) as boolean
    if type(bounds) <> "roArray" or bounds.Count() > 128 then return false
    previousEnd = -1&
    for each bound in bounds
        if type(bound) <> "roAssociativeArray" or bound.Count() <> 2 then return false
        if not bound.DoesExist("startUs") or not bound.DoesExist("endUs") then return false
        for each key in ["startUs", "endUs"]
            kind = type(bound[key], 3)
            if kind <> "Integer" and kind <> "roInt" and kind <> "LongInteger" and kind <> "roLongInteger" then return false
        end for
        if bound.startUs < 0& or bound.endUs > 2147483648000000& or bound.endUs <= bound.startUs then return false
        if bound.endUs - bound.startUs > 10000000& or bound.startUs < previousEnd then return false
        previousEnd = bound.endUs
    end for
    return true
end function

function twitchAdClockInBounds(utcUs as dynamic, bounds as dynamic) as boolean
    if utcUs = invalid or not twitchAdClockBoundsValid(bounds) then return false
    for each bound in bounds
        if utcUs >= bound.startUs and utcUs < bound.endUs then return true
    end for
    return false
end function

' Merge only exact observed records. Overlap that was already accepted within
' one payload retains that payload's existing pod-rounding policy; new overlap
' across publications is refused. No clock/date interval is extended.
function twitchAdClockRetain(previous as object, current as object, isCue as boolean) as dynamic
    if isCue
        if not tadCuesValid(previous) or not tadCuesValid(current) then return invalid
        cap = 32
    else
        if not twitchAdClockBoundsValid(previous) or not twitchAdClockBoundsValid(current) then return invalid
        cap = 128
    end if
    result = []
    oldIndex = 0
    newIndex = 0
    last = invalid
    lastOld = false
    lastNew = false
    while oldIndex < previous.Count() or newIndex < current.Count()
        fromOld = false
        fromNew = false
        if oldIndex >= previous.Count()
            candidate = current[newIndex]
            fromNew = true
        else if newIndex >= current.Count()
            candidate = previous[oldIndex]
            fromOld = true
        else if previous[oldIndex].startUs < current[newIndex].startUs
            candidate = previous[oldIndex]
            fromOld = true
        else if previous[oldIndex].startUs > current[newIndex].startUs
            candidate = current[newIndex]
            fromNew = true
        else
            candidate = previous[oldIndex]
            duplicate = current[newIndex]
            if candidate.endUs <> duplicate.endUs then return invalid
            if isCue
                if candidate.durationUs <> duplicate.durationUs or candidate.podCount <> duplicate.podCount or candidate.podPosition <> duplicate.podPosition then return invalid
            end if
            fromOld = true
            fromNew = true
        end if
        if last <> invalid and candidate.startUs < last.endUs
            if not isCue then return invalid
            if not ((lastOld and fromOld) or (lastNew and fromNew)) then return invalid
        end if
        item = { startUs: candidate.startUs, endUs: candidate.endUs }
        if isCue
            item.durationUs = candidate.durationUs
            item.podCount = candidate.podCount
            item.podPosition = candidate.podPosition
        end if
        if result.Count() = cap then result.Shift()
        result.Push(item)
        last = item
        lastOld = fromOld
        lastNew = fromNew
        if fromOld then oldIndex += 1
        if fromNew then newIndex += 1
    end while
    if isCue
        if not tadCuesValid(result) then return invalid
    else
        if not twitchAdClockBoundsValid(result) then return invalid
    end if
    return result
end function

sub twitchAdClockResetMetadata()
    m.adBounds = []
    m.adCues = []
    m.adLastUtc = invalid
    if m.adBadge <> invalid then m.adBadge.callFunc("setCues", m.adOwner, [])
end sub

' Shared wrapper handlers use only sanitized cue/bounds and the actual native
' frame observation. Metadata polling has no authority over playback time.
sub initAdCountdown()
    m.adBadge = m.top.findNode("adCountdown")
    m.adOwner = ""
    m.adBounds = []
    m.adCues = []
    m.adLastUtc = invalid
    m.top.observeField("positionInfo", "onAdPresented")
end sub

function beginAdCountdown(owner as string) as boolean
    if m.disposed or not tadOwner(owner) or m.adBadge = invalid then return false
    if m.adOwner <> "" then m.adBadge.callFunc("clear", m.adOwner)
    m.adOwner = owner
    m.adBounds = []
    m.adCues = []
    m.adLastUtc = invalid
    return m.adBadge.callFunc("beginContent", owner)
end function

function setAdMetadata(owner as string, cues as dynamic, bounds as dynamic) as boolean
    if m.disposed or m.adBadge = invalid or owner <> m.adOwner or owner = "" then return false
    if not tadCuesValid(cues) or not twitchAdClockBoundsValid(bounds)
        twitchAdClockResetMetadata()
        return false
    end if
    if cues.Count() = 0 and bounds.Count() = 0
        twitchAdClockResetMetadata()
        return true
    end if
    retainedBounds = twitchAdClockRetain(m.adBounds, bounds, false)
    retainedCues = twitchAdClockRetain(m.adCues, cues, true)
    if retainedBounds = invalid or retainedCues = invalid
        twitchAdClockResetMetadata()
        return false
    end if
    if not m.adBadge.callFunc("setCues", owner, retainedCues)
        twitchAdClockResetMetadata()
        return false
    end if
    m.adBounds = retainedBounds
    m.adCues = retainedCues
    ' Cue refresh does not read a future seek value or invent a rendered frame.
    updateAdPresented()
    return true
end function

sub onAdPresented()
    if m.disposed or m.adOwner = "" or m.adBadge = invalid then return
    m.adLastUtc = twitchAdClockUtc(m.top.positionInfo)
    updateAdPresented()
end sub

sub updateAdPresented()
    if m.disposed or m.adOwner = "" or m.adBadge = invalid then return
    value = m.adLastUtc
    if not twitchAdClockInBounds(value, m.adBounds) then value = invalid
    state = m.top.state
    if state = "playing" or state = "paused" or state = "buffering"
        m.adBadge.callFunc("updatePresented", m.adOwner, value, state)
    else if state = "error" or state = "finished" or state = "stopped"
        ignored = clearAdCountdown(m.adOwner)
    else
        m.adBadge.callFunc("updatePresented", m.adOwner, invalid, "buffering")
    end if
end sub

function clearAdCountdown(owner as string) as boolean
    if owner <> m.adOwner or owner = "" then return false
    if m.adBadge <> invalid then m.adBadge.callFunc("clear", owner)
    m.adOwner = ""
    m.adBounds = []
    m.adCues = []
    m.adLastUtc = invalid
    return true
end function

sub destroyAdCountdown()
    ignored = clearAdCountdown(m.adOwner)
    m.top.unobserveField("positionInfo")
    if m.adBadge <> invalid then m.adBadge.callFunc("onDestroy")
end sub
