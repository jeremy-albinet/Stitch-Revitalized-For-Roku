' Private Task-local metadata gate; include reviewed nativeDemuxBulk.brs and
' unchanged source/utils/deviceCapabilities.brs. No conversion or buffer export.

sub nmiCheck(ok as boolean, reason as string)
    if not ok then throw "native-init-metadata: " + reason
end sub

function nmiInteger(value as dynamic) as boolean
    kind = Type(value, 3)
    return kind = "Integer" or kind = "LongInteger" or kind = "roInt"
end function

function nmiString(value as dynamic) as boolean
    kind = Type(value, 3)
    return kind = "String" or kind = "roString"
end function

function nmiU16(data as object, offset as integer, limit as integer) as integer
    nmiCheck(offset >= 0 and offset <= limit - 2, "truncated uint16")
    return data[offset] * 256 + data[offset + 1]
end function

function nmiHexByte(value as integer) as string
    digits = "0123456789ABCDEF"
    return digits.Mid(value \ 16, 1) + digits.Mid(value mod 16, 1)
end function

function nmiProfile(value as integer) as string
    if value = 66 then return "baseline"
    if value = 77 then return "main"
    if value = 100 then return "high"
    return ""
end function

function nmiLevel(value as integer) as string
    levels = ",10,11,12,13,20,21,22,30,31,32,40,41,42,50,51,52,60,61,62,"
    if levels.InStr("," + value.ToStr() + ",") < 0 then return ""
    return (value \ 10).ToStr() + "." + (value mod 10).ToStr()
end function

function nmiChild(data as object, parent as object, kind as string, ctx as object) as object
    found = invalid
    for each child in nbBoxes(data, parent.body, parent.finish, ctx)
        if child.kind = kind
            nmiCheck(found = invalid, "duplicate " + kind)
            found = child
        end if
    end for
    nmiCheck(found <> invalid, "missing " + kind)
    return found
end function

function nmiSampleEntry(data as object, trak as object, ctx as object) as object
    mdia = nmiChild(data, trak, "mdia", ctx)
    minf = nmiChild(data, mdia, "minf", ctx)
    stbl = nmiChild(data, minf, "stbl", ctx)
    stsd = nmiChild(data, stbl, "stsd", ctx)
    nmiCheck(stsd.finish - stsd.body >= 8, "truncated stsd")
    nmiCheck(nbU32(data, stsd.body, stsd.finish) = 0&, "unsupported stsd version or flags")
    nmiCheck(nbU32(data, stsd.body + 4, stsd.finish) = 1&, "exactly one sample entry required")
    entries = nbBoxes(data, stsd.body + 8, stsd.finish, ctx)
    nmiCheck(entries.Count() = 1, "sample entry count mismatch")
    entry = entries[0]
    nmiCheck(entry.finish - entry.body >= 8, "truncated sample entry")
    nmiCheck(nmiU16(data, entry.body + 6, entry.finish) = 1, "unsupported data reference")
    return entry
end function

function nmiAvc(data as object, entry as object, ctx as object) as object
    nmiCheck(entry.kind = "avc1" or entry.kind = "avc3", "video codec unsupported; HEVC gate pending")
    nmiCheck(entry.finish - entry.body >= 78, "truncated video sample entry")
    width = nmiU16(data, entry.body + 24, entry.finish)
    height = nmiU16(data, entry.body + 26, entry.finish)
    nmiCheck(width > 0 and height > 0, "zero video dimensions")
    config = invalid
    for each child in nbBoxes(data, entry.body + 78, entry.finish, ctx)
        if child.kind = "avcC"
            nmiCheck(config = invalid, "duplicate avcC")
            config = child
        else if child.kind = "hvcC" or child.kind = "av1C" or child.kind = "esds"
            nmiCheck(false, "conflicting video configuration")
        end if
    end for
    nmiCheck(config <> invalid, "missing avcC")
    p = config.body
    finish = config.finish
    nmiCheck(finish - p >= 7 and finish - p <= 65536, "avcC size bound")
    nmiCheck(data[p] = 1, "unsupported avcC version")
    profileIdc = data[p + 1]
    compatibility = data[p + 2]
    levelIdc = data[p + 3]
    profile = nmiProfile(profileIdc)
    level = nmiLevel(levelIdc)
    nmiCheck(profile <> "" and level <> "", "unsupported AVC profile or level")
    nmiCheck(compatibility mod 4 = 0, "reserved AVC compatibility bits")
    nmiCheck(not (levelIdc = 11 and (profileIdc = 66 or profileIdc = 77) and (compatibility and 16) <> 0), "AVC level1b unsupported")
    nmiCheck(data[p + 4] >= 252 and data[p + 4] mod 4 <> 2, "invalid AVC NAL length size")
    nalLengthSize = data[p + 4] mod 4 + 1
    nmiCheck(data[p + 5] = 225, "exactly one AVC SPS required")
    p += 6
    spsSize = nmiU16(data, p, finish)
    p += 2
    nmiCheck(spsSize >= 5 and spsSize <= finish - p, "truncated AVC SPS")
    nmiCheck(data[p] >= 32 and data[p] < 128 and data[p] mod 32 = 7, "invalid AVC SPS NAL type")
    nmiCheck(data[p + 1] = profileIdc and data[p + 2] = compatibility and data[p + 3] = levelIdc, "SPS differs from avcC profile or level")
    p += spsSize
    nmiCheck(p < finish, "missing AVC PPS count")
    nmiCheck(data[p] = 1, "exactly one AVC PPS required")
    p += 1
    ppsSize = nmiU16(data, p, finish)
    p += 2
    nmiCheck(ppsSize >= 2 and ppsSize <= finish - p, "truncated AVC PPS")
    nmiCheck(data[p] >= 32 and data[p] < 128 and data[p] mod 32 = 8, "invalid AVC PPS NAL type")
    p += ppsSize
    if p < finish
        nmiCheck(profileIdc = 100 and finish - p = 4, "unsupported trailing avcC configuration")
        nmiCheck(data[p] = 253 and data[p + 1] = 248 and data[p + 2] = 248 and data[p + 3] = 0, "unsupported AVC chroma, bit depth or SPS extensions")
        p += 4
    end if
    nmiCheck(p = finish, "avcC boundary")
    codec = entry.kind + "." + nmiHexByte(profileIdc) + nmiHexByte(compatibility) + nmiHexByte(levelIdc)
    return { videoEntry: entry.kind, videoCodec: codec, videoProfile: profile, videoProfileIdc: profileIdc, videoCompatibility: compatibility, videoLevel: level, videoLevelIdc: levelIdc, nalLengthSize: nalLengthSize, width: width, height: height }
end function

function nmiDescriptor(data as object, offset as integer, limit as integer) as object
    nmiCheck(offset >= 0 and offset <= limit - 2, "truncated MPEG4 descriptor")
    tag = data[offset]
    p = offset + 1
    size = 0
    done = false
    for i = 1 to 4
        nmiCheck(p < limit, "truncated MPEG4 descriptor length")
        value = data[p]
        p += 1
        size = size * 128 + value mod 128
        nmiCheck(size <= 4096, "MPEG4 descriptor size bound")
        if value < 128
            done = true
            exit for
        end if
    end for
    nmiCheck(done and size <= limit - p, "invalid MPEG4 descriptor length")
    return { tag: tag, body: p, finish: p + size }
end function

function nmiBits(data as object, state as object, count as integer) as integer
    nmiCheck(count >= 1 and count <= 16 and state[0] <= state[1] - count, "truncated AudioSpecificConfig")
    value = 0
    weights = [128, 64, 32, 16, 8, 4, 2, 1]
    for i = 1 to count
        bit = state[0]
        value = value * 2 + (data[bit \ 8] \ weights[bit mod 8]) mod 2
        state[0] += 1
    end for
    return value
end function

function nmiAacConfig(data as object, config as object) as object
    nmiCheck(config.finish - config.body >= 2 and config.finish - config.body <= 64, "AAC config size bound")
    bits = [config.body * 8, config.finish * 8]
    nmiCheck(nmiBits(data, bits, 5) = 2, "only AAC-LC object type2 supported")
    index = nmiBits(data, bits, 4)
    rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
    nmiCheck(index >= 0 and index < rates.Count(), "unsupported AAC sample rate index")
    channels = nmiBits(data, bits, 4)
    nmiCheck(channels = 1 or channels = 2, "only explicit mono or stereo AAC supported")
    nmiCheck(nmiBits(data, bits, 3) = 0, "unsupported AAC GASpecificConfig")
    remaining = bits[1] - bits[0]
    if remaining >= 17
        nmiCheck(nmiBits(data, bits, 11) = &h2b7 and nmiBits(data, bits, 5) = 5 and nmiBits(data, bits, 1) = 0, "AAC SBR or unknown sync extension unsupported")
    end if
    nmiCheck(bits[1] - bits[0] <= 7, "unsupported trailing AAC configuration")
    while bits[0] < bits[1]
        nmiCheck(nmiBits(data, bits, 1) = 0, "nonzero AAC padding")
    end while
    return { audioEntry: "mp4a", audioCodec: "mp4a.40.2", audioObjectType: 2, audioSampleRate: rates[index], audioChannels: channels }
end function

function nmiAac(data as object, entry as object, ctx as object) as object
    nmiCheck(entry.kind = "mp4a", "unsupported audio sample entry")
    nmiCheck(entry.finish - entry.body >= 28, "truncated audio sample entry")
    nmiCheck(nmiU16(data, entry.body + 8, entry.finish) = 0, "only version-zero mp4a supported")
    esds = invalid
    for each child in nbBoxes(data, entry.body + 28, entry.finish, ctx)
        if child.kind = "esds"
            nmiCheck(esds = invalid, "duplicate esds")
            esds = child
        else if child.kind = "avcC" or child.kind = "hvcC" or child.kind = "av1C"
            nmiCheck(false, "conflicting audio configuration")
        end if
    end for
    nmiCheck(esds <> invalid, "missing esds")
    nmiCheck(esds.finish - esds.body >= 4, "truncated esds")
    nmiCheck(nbU32(data, esds.body, esds.finish) = 0&, "unsupported esds version or flags")
    es = nmiDescriptor(data, esds.body + 4, esds.finish)
    nmiCheck(es.tag = 3 and es.finish = esds.finish and es.finish - es.body >= 3, "invalid ES descriptor")
    nmiCheck(data[es.body + 2] < 32, "ES dependency, URL or OCR unsupported")
    decoder = nmiDescriptor(data, es.body + 3, es.finish)
    nmiCheck(decoder.tag = 4 and decoder.finish - decoder.body >= 13, "invalid decoder config descriptor")
    nmiCheck(data[decoder.body] = 64 and data[decoder.body + 1] = 21, "only MPEG4 audio object0x40 stream type5 supported")
    config = nmiDescriptor(data, decoder.body + 13, decoder.finish)
    nmiCheck(config.tag = 5 and config.finish = decoder.finish, "missing or ambiguous AAC decoder-specific info")
    sl = nmiDescriptor(data, decoder.finish, es.finish)
    nmiCheck(sl.tag = 6 and sl.finish - sl.body = 1 and sl.finish = es.finish, "invalid SL descriptor")
    nmiCheck(data[sl.body] = 2, "unsupported SL config")
    result = nmiAacConfig(data, config)
    sampleRate = nbU32(data, entry.body + 24, entry.finish)
    nmiCheck(sampleRate mod 65536& = 0& and sampleRate \ 65536& = result.audioSampleRate, "AAC sample entry rate differs from ASC")
    nmiCheck(nmiU16(data, entry.body + 16, entry.finish) = result.audioChannels, "AAC sample entry channels differ from ASC")
    return result
end function

function nativeLiveInspectInitMetadata(data as object) as object
    nmiCheck(Type(data) = "roByteArray", "init must be bytearray")
    nmiCheck(data.Count() >= 8 and data.Count() <= 2097152, "init input bound")
    ctx = nbContext()
    moov = invalid
    for each atom in nbBoxes(data, 0, data.Count(), ctx)
        nmiCheck(atom.kind <> "moof" and atom.kind <> "mdat", "media boxes are not init metadata")
        if atom.kind = "moov"
            nmiCheck(moov = invalid, "duplicate moov")
            moov = atom
        end if
    end for
    nmiCheck(moov <> invalid, "missing moov")
    video = invalid
    audio = invalid
    ids = []
    for each trak in nbBoxes(data, moov.body, moov.finish, ctx)
        if trak.kind = "trak"
            nmiCheck(ids.Count() < 2, "exactly two tracks required")
            ' Existing parser recursively applies mandatory encryption/layout guards.
            info = nbTrakInfo(data, trak, ctx)
            for each previous in ids
                nmiCheck(previous <> info[0], "duplicate track ID")
            end for
            ids.Push(info[0])
            entry = nmiSampleEntry(data, trak, ctx)
            if info[1] = "video"
                nmiCheck(video = invalid, "multiple video tracks")
                video = nmiAvc(data, entry, ctx)
                video.videoTrackId = info[0]
            else if info[1] = "audio"
                nmiCheck(audio = invalid, "multiple audio tracks")
                audio = nmiAac(data, entry, ctx)
                audio.audioTrackId = info[0]
            else
                nmiCheck(false, "unknown track handler")
            end if
        end if
    end for
    nmiCheck(ids.Count() = 2 and video <> invalid and audio <> invalid, "one video and one AAC track required")
    result = { version: 1 }
    for each key in video
        result[key] = video[key]
    end for
    for each key in audio
        result[key] = audio[key]
    end for
    return result
end function

function nativeLiveInitMetadataVariant(meta as dynamic, frameRate as string, bandwidth as dynamic) as dynamic
    try
        keys = ["version", "videoTrackId", "audioTrackId", "videoEntry", "videoCodec", "videoProfile", "videoProfileIdc", "videoCompatibility", "videoLevel", "videoLevelIdc", "nalLengthSize", "width", "height", "audioEntry", "audioCodec", "audioObjectType", "audioSampleRate", "audioChannels"]
        if Type(meta) <> "roAssociativeArray" then return invalid
        if meta.Count() <> keys.Count() then return invalid
        for each key in keys
            if not meta.DoesExist(key) then return invalid
        end for
        for each key in ["version", "videoTrackId", "audioTrackId", "videoProfileIdc", "videoCompatibility", "videoLevelIdc", "nalLengthSize", "width", "height", "audioObjectType", "audioSampleRate", "audioChannels"]
            if not nmiInteger(meta[key]) then return invalid
        end for
        for each key in ["videoEntry", "videoCodec", "videoProfile", "videoLevel", "audioEntry", "audioCodec"]
            if not nmiString(meta[key]) then return invalid
        end for
        if meta.version <> 1 or meta.videoTrackId < 1 or meta.videoTrackId > 4294967295& or meta.audioTrackId < 1 or meta.audioTrackId > 4294967295& or meta.videoTrackId = meta.audioTrackId then return invalid
        if meta.videoEntry <> "avc1" and meta.videoEntry <> "avc3" then return invalid
        if meta.videoProfile <> nmiProfile(meta.videoProfileIdc) or meta.videoProfile = "" then return invalid
        if meta.videoLevel <> nmiLevel(meta.videoLevelIdc) or meta.videoLevel = "" then return invalid
        if meta.videoCompatibility < 0 or meta.videoCompatibility > 255 or meta.videoCompatibility mod 4 <> 0 then return invalid
        if meta.videoCodec <> meta.videoEntry + "." + nmiHexByte(meta.videoProfileIdc) + nmiHexByte(meta.videoCompatibility) + nmiHexByte(meta.videoLevelIdc) then return invalid
        if meta.width < 1 or meta.width > 65535 or meta.height < 1 or meta.height > 65535 then return invalid
        if meta.nalLengthSize <> 1 and meta.nalLengthSize <> 2 and meta.nalLengthSize <> 4 then return invalid
        if meta.audioEntry <> "mp4a" or meta.audioCodec <> "mp4a.40.2" or meta.audioObjectType <> 2 then return invalid
        if meta.audioChannels <> 1 and meta.audioChannels <> 2 then return invalid
        rates = ",96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350,"
        if rates.InStr("," + meta.audioSampleRate.ToStr() + ",") < 0 then return invalid
        if not nmiInteger(bandwidth) then return invalid
        if bandwidth < 1 or bandwidth > 20000000 then return invalid
        if frameRate.Len() < 1 or frameRate.Len() > 9 then return invalid
        parts = frameRate.Split(".")
        if parts.Count() < 1 or parts.Count() > 2 then return invalid
        for each part in parts
            if part.Len() < 1 or part.Len() > 6 then return invalid
            for i = 0 to part.Len() - 1
                code = Asc(part.Mid(i, 1))
                if code < 48 or code > 57 then return invalid
            end for
        end for
        if Val(frameRate) <= 0 or Val(frameRate) > 60.01 then return invalid
        return { "CODECS": meta.videoCodec + "," + meta.audioCodec, "RESOLUTION": meta.width.ToStr() + "x" + meta.height.ToStr(), "FRAME-RATE": frameRate, "BANDWIDTH": bandwidth.ToStr() }
    catch e
        return invalid
    end try
end function

function nativeLiveInitMetadataSupported(meta as dynamic, frameRate as string, bandwidth as dynamic, device = invalid as dynamic) as boolean
    variant = nativeLiveInitMetadataVariant(meta, frameRate, bandwidth)
    if variant = invalid then return false
    return isTwitchVariantSupported(variant, device)
end function
