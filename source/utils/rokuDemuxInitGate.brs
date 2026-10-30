' Task-owned gate: actual downloaded initialization bytes are checked BEFORE publication.
sub validateLiveInitOutput(payload as object)
    if m.top.stopRequested then return
    actual = nativeLiveInspectInitMetadata(payload)
    frameRate = m.config["metadata"]["frameRate"]
    bandwidth = m.config.metadata.bandwidth
    variant = nativeLiveInitMetadataVariant(actual, frameRate, bandwidth)
    nlCheck(variant <> invalid, "actual init metadata invalid")
    allowed = nativeLiveInitMetadataSupported(actual, frameRate, bandwidth)
    nlCheck(allowed, "actual init decoder rejected")
    if m.top.stopRequested then return
    if m.sourceTransitions = true
        nlCheck(liveInitTransitionContextValid(), "actual init owner or phase invalid")
        timing = liveInitTrackConfiguration(payload, actual)
        if m.initMasterMetadata <> invalid
            nlCheck(liveInitMasterCompatible(actual, timing), "actual init master incompatible")
        end if
        if m.top.stopRequested then return
        if m.initMasterMetadata = invalid
            m.initMasterMetadata = actual
            m.initMasterTiming = timing
            m.config["metadata"] = { "videoCodec": actual.videoCodec, "audioCodec": actual.audioCodec, "width": actual.width, "height": actual.height, "frameRate": frameRate, "bandwidth": bandwidth, "isHD": actual.height >= 720 }
        end if
    else
        m.config["metadata"] = { "videoCodec": actual.videoCodec, "audioCodec": actual.audioCodec, "width": actual.width, "height": actual.height, "frameRate": frameRate, "bandwidth": bandwidth, "isHD": actual.height >= 720 }
    end if
    m.result["decoderApproved"] = allowed
    m.result["actualInitValidated"] = true
    m.result["requestedDecoderFormat"] = twitchVariantVideoFormat(variant)
end sub

' The payload-only gate runs inside the one Task-owned Fetch->Core feed. A
' publication flag never substitutes for downloaded-byte or decoder approval.
function liveInitTransitionContextValid() as boolean
    try
        state = m.liveState
        if type(state) <> "roAssociativeArray" then return false
        if not loopbackSteadySessionIdValid(m.sessionId) or state.sessionId <> m.sessionId then return false
        for each key in ["steadyMode", "sourceTransitions", "trustedExperimentalTransport"]
            if not loopbackBoolean(state[key]) or state[key] <> true then return false
        end for
        if m.initMasterMetadata = invalid
            return state.phase = "init" and type(state.initIds) = "roArray" and state.initIds.Count() = 0
        end if
        if state.phase <> "init-rotation" or type(state.pendingWindow) <> "roAssociativeArray" then return false
        if not loopbackInteger(state.epoch) or state.epoch < 0 or state.epoch > 4294967295& then return false
        nextEpoch = state.pendingWindow.epoch
        if not loopbackInteger(nextEpoch) then return false
        return nextEpoch = state.epoch or (state.epoch < 4294967295& and nextEpoch = state.epoch + 1&)
    catch error
        return false
    end try
end function

' Each later init already passed the native decoder check above. Ads and
' encoder restarts legitimately change profile, level, resolution and AAC
' configuration across a discontinuity, so only the sample-entry family must
' stay the same as the first init.
function liveInitMasterCompatible(actual as object, timing as object) as boolean
    master = m.initMasterMetadata
    return actual.videoEntry = master.videoEntry and actual.audioEntry = master.audioEntry
end function

' Read bounded actual mdhd/ASC configuration; Bulk's track map is only ID/kind.
' Creation/duration timestamps are preserved and are not interpreted as UTC.
function liveInitTrackConfiguration(data as object, actual as object) as object
    ctx = nbContext()
    moov = invalid
    for each atom in nbBoxes(data, 0, data.Count(), ctx)
        if atom.kind = "moov" then moov = atom
    end for
    nlCheck(moov <> invalid, "actual init timescale moov missing")
    result = { videoTimescale: 0&, audioTimescale: 0&, audioConfigDigest: "" }
    for each trak in nbBoxes(data, moov.body, moov.finish, ctx)
        if trak.kind = "trak"
            info = nbTrakInfo(data, trak, ctx)
            mdia = nmiChild(data, trak, "mdia", ctx)
            mdhd = nmiChild(data, mdia, "mdhd", ctx)
            nlCheck(mdhd.finish - mdhd.body >= 4, "actual init mdhd truncated")
            flags = nbU32(data, mdhd.body, mdhd.finish)
            nlCheck(flags = 0& or flags = 16777216&, "actual init mdhd flags unsupported")
            skip = 12
            size = 24
            if flags = 16777216&
                skip = 20
                size = 36
            end if
            nlCheck(mdhd.finish - mdhd.body = size, "actual init mdhd layout unsupported")
            scale = nbU32(data, mdhd.body + skip, mdhd.finish)
            nlCheck(scale > 0&, "actual init timescale invalid")
            nlCheck(nmiU16(data, mdhd.finish - 2, mdhd.finish) = 0, "actual init mdhd reserved invalid")
            if info[1] = "video"
                nlCheck(info[0] = actual.videoTrackId and result.videoTimescale = 0&, "actual init video ownership invalid")
                result.videoTimescale = scale
            else
                nlCheck(info[1] = "audio" and info[0] = actual.audioTrackId and result.audioTimescale = 0&, "actual init audio ownership invalid")
                result.audioTimescale = scale
                entry = nmiSampleEntry(data, trak, ctx)
                esds = invalid
                for each child in nbBoxes(data, entry.body + 28, entry.finish, ctx)
                    if child.kind = "esds" then esds = child
                end for
                nlCheck(esds <> invalid, "actual init ASC missing")
                es = nmiDescriptor(data, esds.body + 4, esds.finish)
                decoder = nmiDescriptor(data, es.body + 3, es.finish)
                config = nmiDescriptor(data, decoder.body + 13, decoder.finish)
                count = config.finish - config.body
                nlCheck(count >= 2 and count <= 64, "actual init ASC bound")
                bytes = data.Slice(config.body, config.finish)
                nlCheck(type(bytes) = "roByteArray" and bytes.Count() = count, "actual init ASC slice invalid")
                result.audioConfigDigest = nbBulkDigest(bytes)
                bytes = invalid
            end if
        end if
    end for
    nlCheck(result.videoTimescale > 0& and result.audioTimescale > 0& and result.audioConfigDigest <> "", "actual init track configuration missing")
    return result
end function
