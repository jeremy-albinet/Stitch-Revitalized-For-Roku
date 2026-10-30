sub main()
    m.assertions = 0
    m.failures = 0
    mode = "__MODE__"
    data = ParseJSON(ReadAsciiFile("pkg:/data.json"))
    selection = { sourceUrl: data.source, qualityId: "1080p60 (Source)" }
    if mode = "normal"
        descriptor = rokuVodDescriptorFromTrustedMaster(data.master, data.usher, selection, "123456")
        p2Check(descriptor <> invalid, "trusted exact rendition derives descriptor")
        if descriptor <> invalid
            p2Check(rokuVodDescriptorValid(descriptor) and rokuVodDescriptorMatchesMaster(descriptor, data.master), "descriptor syntax and actual master corroboration")
            p2Check(descriptor.version = 2 and descriptor.mode = "vod" and descriptor.vodId = "123456" and descriptor.approvedOrigin = data.origin, "primitive version two source binding")
            p2Check(descriptor.sourceUrl = data.source and descriptor.usherUrl = data.usher and descriptor.qualityId = selection.qualityId, "exact source and signed queries remain unchanged")
            meta = descriptor.metadata
            p2Check(meta.videoCodec = "avc1.4D402A" and meta.audioCodec = "mp4a.40.2" and meta.width = 1920 and meta.height = 1080 and meta.frameRate = "60.000" and meta.bandwidth = 6000000 and meta.isHD, "seven hints derive from master")
            p2Check(not rokuDemuxDescriptorValid(descriptor), "recorded descriptor is never LIVE version one")
            descriptor.metadata.bandwidth = 7000000
            p2Check(rokuVodDescriptorValid(descriptor) and not rokuVodDescriptorMatchesMaster(descriptor, data.master), "valid syntax alone cannot establish master provenance")
        end if
        original = rokuVodDescriptorFromTrustedMaster(data.master, data.usher, selection, "123456")
        for each commented in data.comments
            accepted = rokuVodDescriptorFromTrustedMaster(commented, data.usher, selection, "123456")
            p2Check(accepted <> invalid, "non-EXT master comments accept")
            if accepted <> invalid and original <> invalid
                p2Check(rokuVodDescriptorValid(accepted) and rokuVodDescriptorMatchesMaster(accepted, data.master) and rokuVodDescriptorMatchesMaster(original, commented), "comments preserve actual master corroboration")
                for each field in ["version", "mode", "vodId", "usherUrl", "sourceUrl", "qualityId", "approvedOrigin"]
                    p2Check(accepted[field] = original[field], "comments preserve primitive source binding " + field)
                end for
                for each field in ["videoCodec", "audioCodec", "width", "height", "frameRate", "bandwidth", "isHD"]
                    p2Check(accepted.metadata[field] = original.metadata[field], "comments preserve seven actual rendition hints " + field)
                end for
            end if
        end for
        for each item in data.bad
            p2Check(rokuVodDescriptorFromTrustedMaster(item.master, item.usher, { sourceUrl: item.source, qualityId: item.quality }, item.id) = invalid, "refuse " + item.name)
        end for
        for each field in ["extra", "version", "mode", "vodId", "usherUrl", "sourceUrl", "qualityId", "approvedOrigin", "metadata"]
            changed = rokuVodDescriptorFromTrustedMaster(data.master, data.usher, selection, "123456")
            if changed <> invalid
                if field = "extra"
                    changed.extra = true
                else if field = "version"
                    changed.version = 1
                else if field = "mode"
                    changed.mode = "live"
                else if field = "metadata"
                    changed.metadata = {}
                else
                    changed[field] = invalid
                end if
                p2Check(not rokuVodDescriptorValid(changed), "wrong primitive shape refuses " + field)
            else
                p2Check(false, "fresh mutation descriptor exists")
            end if
        end for
        p2Check(rokuVodDescriptorFromTrustedMaster(data.master, data.usher, { sourceUrl: data.source, qualityId: selection.qualityId, extra: true }, "123456") = invalid, "unknown selection keys refuse")
        p2Check(not rokuVodDescriptorValid(invalid) and not rokuVodDescriptorMatchesMaster({}, data.master), "wrong public shapes safely refuse")
        p2Check(rokuVodDescriptorFromTrustedMaster(data.master.Replace(Chr(10), Chr(13) + Chr(10)), data.usher, selection, "123456") <> invalid, "CRLF trusted master accepts")
        p2Check(rokuVodDescriptorFromTrustedMaster(data.master.Replace(data.source, "https://recorded.ttvnw.net/archive/index.m3u8?sig=fixture%2B%25"), data.usher, { sourceUrl: "https://recorded.ttvnw.net/archive/index.m3u8?sig=fixture%2B%25", qualityId: selection.qualityId }, "123456") <> invalid, "exact trusted recorded ttvnw source accepts")
    end if
    if mode = "normal" or mode = "metadata" then testSessionMetadata(data, selection)
    if mode = "normal" or mode = "variant" then testVariantSource(data, selection)
    print "VOD_P2_RESULT: __MARKER__ "; FormatJSON({ assertions: m.assertions, failures: m.failures })
end sub

sub testSessionMetadata(data as object, selection as object)
    original = rokuVodDescriptorFromTrustedMaster(data.master, data.usher, selection, "123456")
    p2Check(original <> invalid, "metadata baseline rendition accepts")
    for each master in data.acceptedMetadata
        accepted = rokuVodDescriptorFromTrustedMaster(master, data.usher, selection, "123456")
        p2Check(accepted <> invalid, "bounded session data and MEDIA IVS label accept")
        if accepted <> invalid and original <> invalid
            p2Check(rokuVodDescriptorValid(accepted) and rokuVodDescriptorMatchesMaster(accepted, data.master) and rokuVodDescriptorMatchesMaster(original, master), "metadata preserves reciprocal actual master corroboration")
            for each field in ["version", "mode", "vodId", "usherUrl", "sourceUrl", "qualityId", "approvedOrigin"]
                p2Check(accepted[field] = original[field], "metadata cannot change primitive authority " + field)
            end for
            for each field in ["videoCodec", "audioCodec", "width", "height", "frameRate", "bandwidth", "isHD"]
                p2Check(accepted.metadata[field] = original.metadata[field], "metadata cannot change actual rendition hint " + field)
            end for
            p2Check(accepted.Keys().Count() = 8 and accepted.metadata.Keys().Count() = 7, "session data and IVS labels never propagate descriptor keys")
        end if
    end for
    for each item in data.rejectedMetadata
        p2Check(rokuVodDescriptorFromTrustedMaster(item.master, item.usher, { "sourceUrl": item.source, "qualityId": item.quality }, item.id) = invalid, "metadata refuse " + item.name)
    end for
end sub

sub testVariantSource(data as object, selection as object)
    original = rokuVodDescriptorFromTrustedMaster(data.master, data.usher, selection, "123456")
    p2Check(original <> invalid, "variant baseline rendition accepts")
    for each master in data.acceptedVariantSources
        accepted = rokuVodDescriptorFromTrustedMaster(master, data.usher, selection, "123456")
        p2Check(accepted <> invalid, "quoted source or transcode enum accepts")
        if accepted <> invalid and original <> invalid
            p2Check(rokuVodDescriptorValid(accepted) and rokuVodDescriptorMatchesMaster(accepted, data.master) and rokuVodDescriptorMatchesMaster(original, master), "variant label preserves reciprocal master corroboration")
            for each field in ["version", "mode", "vodId", "usherUrl", "sourceUrl", "qualityId", "approvedOrigin"]
                p2Check(accepted[field] = original[field], "variant label cannot change primitive authority " + field)
            end for
            for each field in ["videoCodec", "audioCodec", "width", "height", "frameRate", "bandwidth", "isHD"]
                p2Check(accepted.metadata[field] = original.metadata[field], "variant label cannot change actual codec or quality " + field)
            end for
            p2Check(accepted.Keys().Count() = 8 and accepted.metadata.Keys().Count() = 7, "provider source label never propagates descriptor fields")
        end if
    end for
    for each item in data.rejectedVariantSources
        p2Check(rokuVodDescriptorFromTrustedMaster(item.master, item.usher, { "sourceUrl": item.source, "qualityId": item.quality }, item.id) = invalid, "variant refuse " + item.name)
    end for
end sub

sub p2Check(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "VOD_P2_FAIL: "; label
    end if
end sub
