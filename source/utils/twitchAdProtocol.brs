' The server owns demux bindings; shared player/metadata clock scopes do not.
function twitchAdClockServerPublication(state as object, publication as dynamic) as dynamic
    if type(publication) <> "roAssociativeArray" then return invalid
    if not publication.DoesExist("version") then return twitchAdClockPublication(state, publication)
    if state.closed or state.phase = "failed" then return invalid
    if not tadString(state.adClockSource) or state.adClockSource <> state.sourceUrl then return invalid
    try
        return twitchAdClockEpochProject(state, publication)
    catch e
        return invalid
    end try
end function

' Metadata is informational. A malformed projection falls back to canonical
' bytes; it must never reject otherwise valid playback or alter a media URI.
function twitchAdClockManifest(track as string, publication as dynamic, projection as dynamic) as dynamic
    canonical = loopbackManifest(track, publication)
    if canonical = invalid or track = "master" or projection = invalid then return canonical
    if not twitchAdClockTimelineValid(projection) then return canonical
    if publication.DoesExist("version")
        if not twitchAdClockEpochProjectionValid(publication, projection) then return canonical
    else
        checked = twitchAdClockProject(projection, publication, projection.segments[0].epoch)
        if checked = invalid then return canonical
    end if
    text = canonical.ToAsciiString()
    lines = text.Split(Chr(10))
    output = ""
    at = 0
    for each line in lines
        if line.Left(8) = "#EXTINF:"
            if at >= projection.segments.Count() then return canonical
            output += "#EXT-X-PROGRAM-DATE-TIME:" + projection.segments[at].date + Chr(10)
            if at = 0 then output += twitchAdClockCueTags(projection.cues)
            at += 1
        end if
        if line <> "" then output += line + Chr(10)
    end for
    if at <> projection.segments.Count() then return canonical
    return loopbackAsciiBuffer(output)
end function

' Source epochs are proved against the selected window and converted cache.
' Only the projection adopts the destination playlist's local epoch labels;
' source dates, durations, cues and the immutable publication stay unchanged.
function twitchAdClockEpochProject(state as object, publication as dynamic) as dynamic
    if not loopbackEpochPublicationValid(publication) or not twitchAdClockTimelineValid(state.adClockTimeline) then return invalid
    if not loopbackBoolean(state.sourceTransitions) or state.sourceTransitions <> true then return invalid
    if type(state.window) <> "roAssociativeArray" or type(state.window.segments) <> "roArray" then return invalid
    if type(state.segments) <> "roArray" or state.segments.Count() > 64 then return invalid
    if state.window.segments.Count() <> publication.segments.Count() then return invalid
    anchors = []
    previousSource = invalid
    previousLocal = invalid
    for i = 0 to publication.segments.Count() - 1
        target = publication.segments[i]
        selected = state.window.segments[i]
        if type(selected) <> "roAssociativeArray" then return invalid
        for each field in ["sequence", "epoch", "durationUs"]
            if not loopbackInteger(selected[field]) then return invalid
        end for
        if selected.sequence <> target.sequence or selected.durationUs <> target.durationUs or selected.duration <> target.duration then return invalid
        match = invalid
        for each source in state.adClockTimeline.segments
            if source.sequence = target.sequence then match = source
        end for
        saved = invalid
        for each cached in state.segments
            if type(cached) <> "roAssociativeArray" then return invalid
            if not loopbackInteger(cached.sequence) then return invalid
            if cached.sequence = target.sequence
                if saved <> invalid then return invalid
                saved = cached
            end if
        end for
        if match = invalid or saved = invalid then return invalid
        for each field in ["sourceEpoch", "localEpoch", "durationUs"]
            if not loopbackInteger(saved[field]) then return invalid
        end for
        if match.epoch <> saved.sourceEpoch or selected.epoch <> saved.sourceEpoch then return invalid
        if target.epoch <> saved.localEpoch or match.durationUs <> saved.durationUs then return invalid
        if not tadString(saved.mapUrl) or not tadString(saved.url) then return invalid
        if selected.mapUrl <> saved.mapUrl or selected.url <> saved.url or saved.duration <> target.duration then return invalid
        for each field in ["videoId", "audioId", "initVideoId", "initAudioId"]
            if target[field] <> saved[field] then return invalid
        end for
        if previousSource <> invalid
            if match.epoch - previousSource <> target.epoch - previousLocal then return invalid
        end if
        anchors.Push({ sequence: match.sequence, epoch: target.epoch, startUs: match.startUs, durationUs: match.durationUs, date: match.date })
        previousSource = match.epoch
        previousLocal = target.epoch
    end for
    projected = { cues: state.adClockTimeline.cues, segments: anchors }
    if not twitchAdClockEpochProjectionValid(publication, projected) then return invalid
    return projected
end function

' A frozen version-two sidecar uses local publication epochs, not source or
' native Video clock-kind epochs. Require the exact same boundary per segment.
function twitchAdClockEpochProjectionValid(publication as dynamic, projection as dynamic) as boolean
    if not loopbackEpochPublicationValid(publication) or not twitchAdClockTimelineValid(projection) then return false
    if projection.segments.Count() <> publication.segments.Count() then return false
    for i = 0 to publication.segments.Count() - 1
        target = publication.segments[i]
        anchor = projection.segments[i]
        if anchor.sequence <> target.sequence or anchor.durationUs <> target.durationUs then return false
        if anchor.epoch <> target.epoch then return false
    end for
    return true
end function
