' Eligible completed recordings use the verified bounded native backend.
' Consent, registry preferences and SceneGraph input flags cannot open this gate.
function rokuVodRuntimeAvailable() as boolean
    return true
end function

function rokuVodReadyMetadataValid(metadata as dynamic, descriptor as dynamic) as boolean
    if not rokuVodDescriptorValid(descriptor) or not rvdMetadata(metadata) then return false
    hinted = descriptor.metadata
    if metadata.width > hinted.width or metadata.height > hinted.height then return false
    if metadata["frameRate"] <> hinted["frameRate"] or metadata.bandwidth <> hinted.bandwidth then return false
    return true
end function

function rokuVodSessionReadyValid(ready as dynamic, sessionId as string, descriptor as dynamic) as boolean
    try
        if not rvdKeys(ready, ["sessionId", "boundAddressText", "boundPort", "metadata", "decoderApproved", "actualInitValidated", "requestedDecoderFormat", "mode", "totalDurationUs", "masterPath"]) then return false
        if not rokuDemuxString(ready["sessionId"]) or ready["sessionId"] <> sessionId then return false
        if not CreateObject("roRegex", "^[0-9a-f]{32}$", "").IsMatch(sessionId) then return false
        if not rokuDemuxString(ready.mode) or ready.mode <> "vod" then return false
        if not rokuDemuxInteger(ready["totalDurationUs"]) or ready["totalDurationUs"] < 1& or ready["totalDurationUs"] > 172800000000& then return false
        if not rokuDemuxString(ready["masterPath"]) or ready["masterPath"] <> "/vod/" + sessionId + "/master.m3u8" then return false
        if not rokuDemuxInteger(ready["boundPort"]) or ready["boundPort"] < 49152 or ready["boundPort"] > 65535 then return false
        if not rokuDemuxString(ready["boundAddressText"]) then return false
        if ready["boundAddressText"] <> "127.0.0.1" and ready["boundAddressText"] <> "127.0.0.1:" + ready["boundPort"].ToStr() and ready["boundAddressText"] <> "127.0.0.1:" + (ready["boundPort"] - 65536).ToStr() then return false
        for each key in ["decoderApproved", "actualInitValidated"]
            kind = type(ready[key], 3)
            if kind <> "Boolean" and kind <> "roBoolean" then return false
            if not ready[key] then return false
        end for
        if not rokuVodReadyMetadataValid(ready.metadata, descriptor) then return false
        if not rvdKeys(ready["requestedDecoderFormat"], ["codec", "profile", "level"]) then return false
        metadata = ready.metadata
        format = twitchVariantVideoFormat({ "CODECS": metadata["videoCodec"] + "," + metadata["audioCodec"], "RESOLUTION": metadata.width.ToStr() + "x" + metadata.height.ToStr(), "FRAME-RATE": metadata["frameRate"], "BANDWIDTH": metadata.bandwidth.ToStr() })
        if format = invalid then return false
        for each key in ["codec", "profile", "level"]
            if not rokuDemuxString(ready["requestedDecoderFormat"][key]) or ready["requestedDecoderFormat"][key] <> format[key] then return false
        end for
        return true
    catch error
        return false
    end try
end function

function rokuVodPlaybackReadyValid(event as dynamic, sessionId as string, descriptor as dynamic) as boolean
    try
        if not rvdKeys(event, ["id", "status", "reason", "url", "metadata", "mode", "totalDurationUs", "masterPath"]) then return false
        if not rokuDemuxString(event.id) or event.id <> sessionId then return false
        if not CreateObject("roRegex", "^[0-9a-f]{32}$", "").IsMatch(sessionId) then return false
        if not rokuDemuxString(event.status) or event.status <> "ready" then return false
        if not rokuDemuxString(event.reason) or event.reason <> "" then return false
        if not rokuDemuxString(event.mode) or event.mode <> "vod" then return false
        if not rokuDemuxInteger(event["totalDurationUs"]) or event["totalDurationUs"] < 1& or event["totalDurationUs"] > 172800000000& then return false
        if not rokuDemuxString(event["masterPath"]) or event["masterPath"] <> "/vod/" + sessionId + "/master.m3u8" then return false
        if not rokuDemuxString(event.url) or event.url.Left(17) <> "http://127.0.0.1:" then return false
        suffix = event.url.Mid(17)
        at = suffix.InStr("/")
        if at < 1 then return false
        portText = suffix.Left(at)
        port = rokuDemuxNatural(portText, 65535)
        if port = invalid or port < 49152 then return false
        if port.ToStr() <> portText or suffix.Mid(at) <> event["masterPath"] then return false
        return rokuVodReadyMetadataValid(event.metadata, descriptor)
    catch error
        return false
    end try
end function

' This checks a completed bounded playlist, not recorded-CDN egress authority.
function rokuVodPlaylistCompleted(playlist as dynamic, sourceUrl as string) as boolean
    try
        if not rokuDemuxString(playlist) or playlist.Len() > 262144 or not rvdOrigin(sourceUrl) then return false
        bytes = CreateObject("roByteArray")
        bytes.FromAsciiString(playlist)
        if bytes.Count() <> playlist.Len() or bytes.Count() > 262144 then return false
        return rokuVodIndexValidate(bytes, sourceUrl, nviUrl(sourceUrl).origin)
    catch error
        return false
    end try
end function
