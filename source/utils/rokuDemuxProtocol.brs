function loopbackKeys(value as dynamic, keys as object) as boolean
    if type(value) <> "roAssociativeArray" then return false
    if value.Count() <> keys.Count() then return false
    for each key in keys
        if not value.DoesExist(key) then return false
    end for
    return true
end function

function loopbackDurationUs(text as dynamic) as integer
    if not loopbackString(text) then return -1
    if text.Len() < 1 or text.Len() > 9 then return -1
    parts = text.Split(".")
    if parts.Count() < 1 or parts.Count() > 2 then return -1
    whole = loopbackUnsigned(parts[0], 10)
    if whole < 0 then return -1
    fraction = 0
    if parts.Count() = 2
        digits = parts[1]
        if digits.Len() < 1 or digits.Len() > 6 then return -1
        fraction = loopbackUnsigned(digits, 999999)
        if fraction < 0 then return -1
        for i = digits.Len() to 5
            fraction *= 10
        end for
    end if
    micros = whole * 1000000 + fraction
    if micros < 1 or micros > 10000000 then return -1
    return micros
end function

function loopbackPublicationValid(pub as dynamic) as boolean
    if type(pub) = "roAssociativeArray"
        if pub.DoesExist("version") then return loopbackEpochPublicationValid(pub)
    end if
    if not loopbackKeys(pub, ["generation", "mediaSequence", "targetDuration", "initVideoId", "initAudioId", "durationUs", "sourceOffsetUs", "ended", "segments"]) then return false
    sessionId = loopbackAssetSession(pub.initVideoId)
    generationCap = 256&
    if sessionId <> "" then generationCap = 4294967295&
    if not loopbackInteger(pub.generation) or pub.generation < 1 or pub.generation > generationCap then return false
    if not loopbackInteger(pub.mediaSequence) or pub.mediaSequence < 0 or pub.mediaSequence > 4294967295 then return false
    if not loopbackInteger(pub.targetDuration) or pub.targetDuration < 1 or pub.targetDuration > 10 then return false
    if not loopbackInteger(pub.durationUs) or pub.durationUs < 1 or pub.durationUs > 80000000 then return false
    if not loopbackInteger(pub.sourceOffsetUs) or pub.sourceOffsetUs < m.config.sourceDelaySeconds * 1000000 then return false
    if not loopbackBoolean(pub.ended) then return false
    if not pub.ended and pub.durationUs < 6000000 then return false
    if not loopbackAssetId(pub.initVideoId) or not loopbackAssetId(pub.initAudioId) or pub.initVideoId = pub.initAudioId then return false
    if loopbackAssetSession(pub.initAudioId) <> sessionId then return false
    if type(pub.segments) <> "roArray" then return false
    if pub.segments.Count() < 1 or pub.segments.Count() > 8 then return false
    seen = {}
    seen[pub.initVideoId] = true
    seen[pub.initAudioId] = true
    sum = 0
    nextSequence = pub.mediaSequence
    for each segment in pub.segments
        if not loopbackKeys(segment, ["sequence", "duration", "durationUs", "videoId", "audioId"]) then return false
        if not loopbackInteger(segment.sequence) or segment.sequence <> nextSequence then return false
        if not loopbackInteger(segment.durationUs) or loopbackDurationUs(segment.duration) <> segment.durationUs then return false
        ' EXTINF rounds to the nearest integer; local TARGETDURATION stays 2.
        if segment.durationUs > pub.targetDuration * 1000000 + 499999 then return false
        if segment.durationUs >= 2500000 then return false
        if not loopbackAssetId(segment.videoId) or not loopbackAssetId(segment.audioId) then return false
        if loopbackAssetSession(segment.videoId) <> sessionId or loopbackAssetSession(segment.audioId) <> sessionId then return false
        if seen.DoesExist(segment.videoId) or seen.DoesExist(segment.audioId) or segment.videoId = segment.audioId then return false
        seen[segment.videoId] = true
        seen[segment.audioId] = true
        sum += segment.durationUs
        nextSequence += 1
    end for
    return sum = pub.durationUs
end function

function loopbackEpochPublicationValid(pub as dynamic) as boolean
    if not loopbackKeys(pub, ["version", "discontinuitySequence", "generation", "mediaSequence", "targetDuration", "initVideoId", "initAudioId", "durationUs", "sourceOffsetUs", "ended", "segments"]) then return false
    if not loopbackInteger(pub.version) or pub.version <> 2 then return false
    for each field in ["generation", "mediaSequence", "discontinuitySequence", "sourceOffsetUs"]
        if not loopbackInteger(pub[field]) or pub[field] < 0 or pub[field] > 4294967295& then return false
    end for
    if pub.generation = 0 then return false
    if not loopbackInteger(pub.targetDuration) or pub.targetDuration <> 2 then return false
    if not loopbackInteger(pub.durationUs) or pub.durationUs < 1 or pub.durationUs > 80000000 then return false
    if type(m.config) <> "roAssociativeArray" then return false
    if not loopbackInteger(m.config.sourceDelaySeconds) or m.config.sourceDelaySeconds < 0 or m.config.sourceDelaySeconds > 60 then return false
    if pub.sourceOffsetUs < m.config.sourceDelaySeconds * 1000000& then return false
    if not loopbackBoolean(pub.ended) then return false
    if not pub.ended and pub.durationUs < 6000000 then return false
    sessionId = loopbackAssetSession(pub.initVideoId)
    if sessionId = "" or loopbackAssetSession(pub.initAudioId) <> sessionId then return false
    if pub.initVideoId = pub.initAudioId then return false
    if type(pub.segments) <> "roArray" then return false
    if pub.segments.Count() < 1 or pub.segments.Count() > 8 then return false
    if pub.mediaSequence > 4294967295& - pub.segments.Count() + 1& then return false
    seen = {}
    videoPairs = {}
    audioPairs = {}
    previous = invalid
    nextSequence = pub.mediaSequence + 0&
    sum = 0&
    for each segment in pub.segments
        if not loopbackKeys(segment, ["sequence", "duration", "durationUs", "videoId", "audioId", "epoch", "initVideoId", "initAudioId"]) then return false
        if not loopbackInteger(segment.sequence) or segment.sequence <> nextSequence then return false
        if not loopbackInteger(segment.epoch) or segment.epoch < 0 or segment.epoch > 4294967295& then return false
        if not loopbackInteger(segment.durationUs) or loopbackDurationUs(segment.duration) <> segment.durationUs then return false
        if (segment.durationUs >= 2500000) then return false
        if previous = invalid
            if segment.epoch <> pub.discontinuitySequence or segment.initVideoId <> pub.initVideoId or segment.initAudioId <> pub.initAudioId then return false
        else
            if segment.epoch <> previous.epoch and segment.epoch <> previous.epoch + 1& then return false
            if segment.epoch = previous.epoch and (segment.initVideoId <> previous.initVideoId or segment.initAudioId <> previous.initAudioId) then return false
        end if
        for each field in ["initVideoId", "initAudioId", "videoId", "audioId"]
            id = segment[field]
            if not loopbackAssetId(id) or loopbackAssetSession(id) <> sessionId then return false
        end for
        if segment.initVideoId = segment.initAudioId then return false
        if videoPairs.DoesExist(segment.initVideoId)
            if videoPairs[segment.initVideoId] <> segment.initAudioId then return false
        end if
        if audioPairs.DoesExist(segment.initAudioId)
            if audioPairs[segment.initAudioId] <> segment.initVideoId then return false
        end if
        videoPairs[segment.initVideoId] = segment.initAudioId
        audioPairs[segment.initAudioId] = segment.initVideoId
        for each field in ["initVideoId", "initAudioId", "videoId", "audioId"]
            id = segment[field]
            if seen.DoesExist(id)
                if (field <> "initVideoId" and field <> "initAudioId") or seen[id] <> field then return false
            end if
            seen[id] = field
        end for
        if seen.Count() > 64 then return false
        sum += segment.durationUs
        nextSequence += 1&
        previous = segment
    end for
    return sum = pub.durationUs
end function

' Metadata only: byte and decoder approval remain the producer's responsibility.
function loopbackPublicationAssets(publication as dynamic) as dynamic
    if not loopbackPublicationValid(publication) then return invalid
    ids = [publication.initVideoId, publication.initAudioId]
    tracks = ["video", "audio"]
    for each segment in publication.segments
        if publication.DoesExist("version")
            ids.Push(segment.initVideoId)
            tracks.Push("video")
            ids.Push(segment.initAudioId)
            tracks.Push("audio")
        end if
        ids.Push(segment.videoId)
        tracks.Push("video")
        ids.Push(segment.audioId)
        tracks.Push("audio")
    end for
    result = []
    seen = {}
    for i = 0 to ids.Count() - 1
        id = ids[i]
        if not seen.DoesExist(id)
            seen[id] = tracks[i]
            result.Push({ "id": id, "track": tracks[i] })
        else if seen[id] <> tracks[i]
            return invalid
        end if
        if result.Count() > 64 then return invalid
    end for
    return result
end function

function loopbackSafeDiagnostics(value as dynamic, cacheBudgetBytes = 16777216& as dynamic, steadyMode = false as dynamic) as dynamic
    if not loopbackInteger(cacheBudgetBytes) then return invalid
    if cacheBudgetBytes <> 16777216& and cacheBudgetBytes <> 25165824& and cacheBudgetBytes <> 33554432& then return invalid
    if not loopbackBoolean(steadyMode) then return invalid
    fields = ["phase", "failed", "failureCategory", "generation", "cacheBytes", "peakCacheBytes", "assetCount", "fetchCount", "playlistCount", "initPairCount", "segmentPairCount", "transferActive", "inputRetained", "inputFilePresent", "closed"]
    if not loopbackKeys(value, fields) then return invalid
    if not loopbackString(value.phase) or value.phase.Len() < 1 or value.phase.Len() > 32 then return invalid
    phases = ",playlist,init,init-rotation,segment,init-video,init-audio,segment-video,segment-audio,ready,ended,failed,stopped,"
    if value.phase.InStr(",") >= 0 or phases.InStr("," + value.phase + ",") < 0 then return invalid
    for each name in ["failed", "transferActive", "inputRetained", "inputFilePresent", "closed"]
        if not loopbackBoolean(value[name]) then return invalid
    end for
    for each name in ["failureCategory", "generation", "cacheBytes", "peakCacheBytes", "assetCount", "fetchCount", "playlistCount", "initPairCount", "segmentPairCount"]
        if not loopbackInteger(value[name]) or value[name] < 0 then return invalid
        cap = 1024&
        if steadyMode then cap = 4294967295&
        if name = "cacheBytes" or name = "peakCacheBytes" then cap = cacheBudgetBytes
        if name = "assetCount" then cap = 256&
        if name = "generation" and not steadyMode then cap = 256&
        if name = "failureCategory" then cap = 2
        if value[name] > cap then return invalid
    end for
    return value
end function

function loopbackAsciiBuffer(text as string) as dynamic
    if text.Len() < 1 or text.Len() > 16384 then return invalid
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(text)
    if bytes.Count() <> text.Len() then return invalid
    return bytes
end function

function loopbackManifest(track as string, publication as dynamic) as dynamic
    nl = Chr(10)
    quote = Chr(34)
    if track = "master"
        meta = m.config.metadata
        text = "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl + "#EXT-X-INDEPENDENT-SEGMENTS" + nl
        text += "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + quote + "audio" + quote + ",NAME=" + quote + "Audio" + quote + ",DEFAULT=YES,AUTOSELECT=YES,URI=" + quote + "/audio.m3u8" + quote + nl
        text += "#EXT-X-STREAM-INF:BANDWIDTH=" + meta.bandwidth.ToStr() + ",RESOLUTION=" + meta.width.ToStr() + "x" + meta.height.ToStr() + ",FRAME-RATE=" + meta.frameRate + ",CODECS=" + quote + meta.videoCodec + ",mp4a.40.2" + quote + ",AUDIO=" + quote + "audio" + quote + nl + "/video.m3u8" + nl
        return loopbackAsciiBuffer(text)
    end if
    if track <> "video" and track <> "audio" then return invalid
    if not loopbackPublicationValid(publication) then return invalid
    if publication.DoesExist("version") then return loopbackEpochManifest(track, publication)
    initId = publication.initVideoId
    if track = "audio" then initId = publication.initAudioId
    text = "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl + "#EXT-X-TARGETDURATION:2" + nl
    text += "#EXT-X-MEDIA-SEQUENCE:" + publication.mediaSequence.ToStr() + nl
    text += "#EXT-X-MAP:URI=" + quote + "/asset/" + initId + quote + nl
    for each segment in publication.segments
        id = segment.videoId
        if track = "audio" then id = segment.audioId
        text += "#EXTINF:" + segment.duration + "," + nl + "/asset/" + id + nl
    end for
    if publication.ended then text += "#EXT-X-ENDLIST" + nl
    return loopbackAsciiBuffer(text)
end function

function loopbackEpochManifest(track as string, publication as dynamic) as dynamic
    if track <> "video" and track <> "audio" then return invalid
    if not loopbackEpochPublicationValid(publication) then return invalid
    nl = Chr(10)
    quote = Chr(34)
    text = "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl + "#EXT-X-TARGETDURATION:2" + nl
    text += "#EXT-X-MEDIA-SEQUENCE:" + publication.mediaSequence.ToStr() + nl
    text += "#EXT-X-DISCONTINUITY-SEQUENCE:" + publication.discontinuitySequence.ToStr() + nl
    previousEpoch = -1&
    for each segment in publication.segments
        if segment.epoch <> previousEpoch
            if previousEpoch >= 0 then text += "#EXT-X-DISCONTINUITY" + nl
            initId = segment.initVideoId
            if track = "audio" then initId = segment.initAudioId
            text += "#EXT-X-MAP:URI=" + quote + "/asset/" + initId + quote + nl
        end if
        id = segment.videoId
        if track = "audio" then id = segment.audioId
        text += "#EXTINF:" + segment.duration + "," + nl + "/asset/" + id + nl
        previousEpoch = segment.epoch
    end for
    if publication.ended then text += "#EXT-X-ENDLIST" + nl
    return loopbackAsciiBuffer(text)
end function
