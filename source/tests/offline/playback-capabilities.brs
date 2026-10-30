' @include source/utils/deviceCapabilities.brs
sub main()
    m.capabilityChecks = 0
    avcDevice = {
        graphicsHeight: 720,
        CanDecodeVideo: function(format as object) as object
            return { result: format.codec = "mpeg4 avc" and Val(format.level) <= 4.2 }
        end function
    }
    hevcDevice = {
        graphicsHeight: 720,
        CanDecodeVideo: function(format as object) as object
            return { result: (format.codec = "mpeg4 avc" and Val(format.level) <= 4.2) or (format.codec = "hevc" and format.profile = "main" and Val(format.level) <= 5.1) }
        end function
    }
    avc = { RESOLUTION: "1920x1080", "FRAME-RATE": "60", CODECS: "avc1.64002a,mp4a.40.2", BANDWIDTH: "6000000" }
    hevc = { RESOLUTION: "2560x1440", "FRAME-RATE": "60", CODECS: "hvc1.1.6.L153.B0,mp4a.40.2", BANDWIDTH: "8500000" }
    if not playbackCapabilityExpect(isTwitchVariantSupported(avc, avcDevice), "1080p60 on a 720p UI device") then return
    if not playbackCapabilityExpect(not isTwitchVariantSupported(hevc, avcDevice), "1440p HEVC excluded on AVC decoder") then return
    if not playbackCapabilityExpect(isTwitchVariantSupported(hevc, hevcDevice), "1440p60 HEVC included on capable decoder") then return
    if not playbackCapabilityExpect(getTwitchSupportedCodecs(avcDevice) = "h264", "old-device AVC Usher fallback") then return
    if not playbackCapabilityExpect(getTwitchSupportedCodecs(hevcDevice) = "h264,h265", "verified HEVC negotiation names") then return
    hevcFormat = twitchVariantVideoFormat(hevc)
    if not playbackCapabilityExpect(hevcFormat.codec = "hevc" and hevcFormat.profile = "main" and Val(hevcFormat.level) = 5.1, "documented HEVC decoder query fields") then return
    hevc.CODECS = "hvc1.1.6.L150.B0,mp4a.40.2"
    if not playbackCapabilityExpect(Val(twitchVariantVideoFormat(hevc).level) = 5.0, "1440p60 fits HEVC level 5.0") then return
    avc32Device = {
        CanDecodeVideo: function(format as object) as object
            return { result: format.codec = "mpeg4 avc" and Val(format.level) <= 3.2 }
        end function
    }
    avc31Device = {
        CanDecodeVideo: function(format as object) as object
            return { result: format.codec = "mpeg4 avc" and Val(format.level) <= 3.1 }
        end function
    }
    avc720 = { RESOLUTION: "1280x720", "FRAME-RATE": "60", CODECS: "avc1.4d401f,mp4a.40.2" }
    if not playbackCapabilityExpect(twitchVariantVideoFormat(avc720).level = "3.2", "720p60 reaches AVC level 3.2 macroblock limit") then return
    if not playbackCapabilityExpect(isTwitchVariantSupported(avc720, avc32Device), "level 3.2 decoder accepts 720p60") then return
    if not playbackCapabilityExpect(not isTwitchVariantSupported(avc720, avc31Device), "level 3.1 decoder rejects 720p60 despite underspecified codec") then return
    avc720["FRAME-RATE"] = "30"
    if not playbackCapabilityExpect(isTwitchVariantSupported(avc720, avc31Device), "level 3.1 decoder accepts 720p30") then return
    hevc50Device = {
        CanDecodeVideo: function(format as object) as object
            return { result: format.codec = "hevc" and format.profile = "main" and Val(format.level) <= 5.0 }
        end function
    }
    hevc4k = { RESOLUTION: "3840x2160", "FRAME-RATE": "30", CODECS: "hvc1.1.6.L150.B0,mp4a.40.2", BANDWIDTH: "16000000" }
    if not playbackCapabilityExpect(twitchVariantVideoFormat(hevc4k).level = "5.0", "2160p30 fits HEVC level 5.0 picture and sample limits") then return
    if not playbackCapabilityExpect(isTwitchVariantSupported(hevc4k, hevc50Device), "level 5.0 decoder accepts 2160p30") then return
    hevc4k["FRAME-RATE"] = "60"
    if not playbackCapabilityExpect(twitchVariantVideoFormat(hevc4k).level = "5.1", "2160p60 exceeds HEVC level 5.0 sample limit") then return
    if not playbackCapabilityExpect(not isTwitchVariantSupported(hevc4k, hevc50Device), "level 5.0 decoder rejects 2160p60 despite underspecified codec") then return
    hevc.CODECS = "hvc1.2.4.L153.B0,mp4a.40.2"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(hevc, hevcDevice), "unsupported Main10 rejected") then return
    hevc.CODECS = "hvc1.1.6.L153.B0,mp4a.40.2"
    hevc["FRAME-RATE"] = "120"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(hevc, hevcDevice), "unsupported frame rate rejected") then return
    avc.RESOLUTION = "2560x1440"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(avc, avcDevice), "AVC conservative resolution cap") then return
    avc.RESOLUTION = "bad-resolution"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(avc, avcDevice), "malformed resolution rejected") then return
    avc.RESOLUTION = "1920x1080"
    avc.CODECS = "av01.0.08M.08,mp4a.40.2"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(avc, hevcDevice), "unnegotiated AV1 rejected") then return
    if not playbackLevelNegotiationChecks() then return
    ? "STITCH_TEST_PASS: playback-capabilities (" + m.capabilityChecks.ToStr() + " checks)"
end sub

function playbackCapabilityExpect(condition as boolean, detail as string) as boolean
    m.capabilityChecks++
    if not condition then ? "STITCH_TEST_FAIL: " + detail
    return condition
end function

function playbackLevelNegotiationChecks() as boolean
    main31 = { RESOLUTION: "852x480", "FRAME-RATE": "30", CODECS: "avc1.4d401f,mp4a.40.2", BANDWIDTH: "1427999" }
    main32 = { RESOLUTION: "1280x720", "FRAME-RATE": "60", CODECS: "avc1.4d401f,mp4a.40.2" }
    high31 = { RESOLUTION: "640x360", "FRAME-RATE": "30", CODECS: "avc1.64001f,mp4a.40.2" }
    high50 = { RESOLUTION: "1920x1080", "FRAME-RATE": "60", CODECS: "avc1.640032,mp4a.40.2" }
    mainHevc40 = { RESOLUTION: "1280x720", "FRAME-RATE": "30", CODECS: "hvc1.1.6.L120.B0,mp4a.40.2" }
    mainHevc50 = { RESOLUTION: "2560x1440", "FRAME-RATE": "60", CODECS: "hvc1.1.6.L150.B0,mp4a.40.2" }
    mainHevc51 = { RESOLUTION: "2560x1440", "FRAME-RATE": "60", CODECS: "hvc1.1.6.L153.B0,mp4a.40.2" }
    main10Hevc50 = { RESOLUTION: "2560x1440", "FRAME-RATE": "60", CODECS: "hvc1.2.4.L150.B0,mp4a.40.2" }

    originalVariant = FormatJson(main31)
    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", "4.2"] }, { result: true }])
    if not playbackCapabilityExpect(isTwitchVariantSupported(main31, device), "native Main3.1 level enumeration accepts confirmed Main4.1") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "main", ["3.1", "4.1"], "Main3.1 retry") then return false
    if not playbackCapabilityExpect(FormatJson(main31) = originalVariant, "level retry leaves caller variant and declared CODECS unchanged") then return false
    if not playbackCapabilityExpect(twitchVariantVideoFormat(main31).level = "3.1", "negotiation does not rewrite the stream requirement") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", "4.2"] }, { result: false }, { result: true }])
    if not playbackCapabilityExpect(isTwitchVariantSupported(main32, device), "native Main3.2 enumerates past false4.1 to confirmed4.2") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "main", ["3.2", "4.1", "4.2"], "Main3.2 retry") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1"], codec: ["hevc"], profile: ["main"] }, { result: true }])
    if not playbackCapabilityExpect(isTwitchVariantSupported(high31, device), "High3.1 can use explicit same-profile4.1 capacity") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "high", ["3.1", "4.1"], "suggested codec/profile are not copied") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", "4.2"] }, { result: true }])
    if not playbackCapabilityExpect(not isTwitchVariantSupported(high50, device), "signaled High5.0 source stays excluded by4.1/4.2 capacities") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "high", ["5.0"], "never query below source5.0") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1"] }, { result: true }])
    if not playbackCapabilityExpect(isTwitchVariantSupported(mainHevc40, device), "HEVC Main4.0 accepts explicit Main4.1 capacity") then return false
    if not playbackLevelQueriesMatch(device, "hevc", "main", ["4.0", "4.1"], "HEVC4.0 retry") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", "5.1"] }, { result: true }])
    if not playbackCapabilityExpect(isTwitchVariantSupported(mainHevc50, device), "1440p60 Main5.0 accepts confirmed5.1 after skipping lower4.1") then return false
    if not playbackLevelQueriesMatch(device, "hevc", "main", ["5.0", "5.1"], "HEVC stream requirement remains5.0") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["5.0"] }, { result: true }])
    if not playbackCapabilityExpect(not isTwitchVariantSupported(mainHevc51, device), "declared HEVC5.1 cannot use lower5.0 capacity") then return false
    if not playbackLevelQueriesMatch(device, "hevc", "main", ["5.1"], "no underspecified HEVC retry") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["5.1"], profile: ["main"] }, { result: false }])
    if not playbackCapabilityExpect(not isTwitchVariantSupported(main10Hevc50, device), "unsupported HEVC Main10 never falls back to Main") then return false
    if not playbackLevelQueriesMatch(device, "hevc", "main 10", ["5.0", "5.1"], "Main10 profile retained") then return false

    device = playbackLevelDecoder([{ result: true, updated: "codec,profile,level", level: [invalid] }])
    if not playbackCapabilityExpect(isTwitchVariantSupported(main31, device), "direct explicit true does not inspect unused suggestions") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "main", ["3.1"], "direct true has one query") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["3.0", "3.1"] }, { result: true }])
    if not playbackCapabilityExpect(isTwitchVariantSupported(main31, device), "same required level may be explicitly confirmed without lowering") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "main", ["3.1", "3.1"], "skip lower3.0 and preserve exact requirement") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", "4.2"] }, { result: false }, { result: false }])
    if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "all sufficient capacity responses false remains unsupported") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "main", ["3.1", "4.1", "4.2"], "finite original capacities") then return false

    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1"] }, { result: false, updated: "level", level: ["4.2"] }, { result: true }])
    if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "false candidate suggestions do not trigger recursive negotiation") then return false
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "main", ["3.1", "4.1"], "no third recursive candidate") then return false

    boundedLevels = ["3.1", "3.2", "4.0", "4.1", "4.2", "5.0", "5.1", "5.2"]
    boundedResponses = [{ result: false, updated: "level", level: boundedLevels }]
    for each level in boundedLevels
        boundedResponses.Push({ result: false })
    end for
    device = playbackLevelDecoder(boundedResponses)
    if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "eight advertised capacities exhaust without accepting false") then return false
    if not playbackCapabilityExpect(device.calls.Count() = 9, "decoder work is bounded to original plus eight calls") then return false
    expectedBounded = ["3.1"]
    for each level in boundedLevels
        expectedBounded.Push(level)
    end for
    if not playbackLevelQueriesMatch(device, "mpeg4 avc", "main", expectedBounded, "bounded capacities retain codec/profile") then return false

    invalidResponses = [invalid, true, false, 1, "true", [], {}, { result: invalid }, { result: 1 }, { result: 0 }, { result: "true" }, { result: "false" }, { result: [] }, { result: {} }]
    for index = 0 to invalidResponses.Count() - 1
        response = invalidResponses[index]
        if GetInterface(response, "ifAssociativeArray") <> invalid
            response.updated = "level"
            response.level = ["4.1"]
        end if
        device = playbackLevelDecoder([response, { result: true }])
        if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "invalid initial decoder result " + index.ToStr()) then return false
        if not playbackCapabilityExpect(device.calls.Count() = 1, "invalid initial response never retries " + index.ToStr()) then return false
    end for

    invalidUpdated = [invalid, "", "codec", "profile", "Level", "LEVEL", "level,profile", "level profile", "level,codec", "level,", " level", "level ", ["level"], { level: true }, 1, true]
    for index = 0 to invalidUpdated.Count() - 1
        device = playbackLevelDecoder([{ result: false, updated: invalidUpdated[index], level: ["4.1"] }, { result: true }])
        if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "nonexact level-only updated field " + index.ToStr()) then return false
        if not playbackCapabilityExpect(device.calls.Count() = 1, "combined/invalid update never retries " + index.ToStr()) then return false
    end for

    invalidLevels = [invalid, "4.1", 4.1, true, { level: "4.1" }, [], [invalid], [4.1], [true], [{ level: "4.1" }], [["4.1"]], ["4.1", invalid], ["4.1", "4.2", "5.0", "5.1", "5.2", "6.0", "6.1", "6.2", "3.1"]]
    for index = 0 to invalidLevels.Count() - 1
        device = playbackLevelDecoder([{ result: false, updated: "level", level: invalidLevels[index] }, { result: true }])
        if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "invalid level container/member or over-cap array " + index.ToStr()) then return false
        if not playbackCapabilityExpect(device.calls.Count() = 1, "validate entire level list before querying " + index.ToStr()) then return false
    end for

    invalidLevelStrings = ["4.3", "04.1", "4", "4.10", "4.1x", "4.1 ", " 4.1", "4.1e0", "4.1" + Chr(10), "NaN", "Infinity", "-4.1", "+4.1", "3.4", "7.0", "", "1000000000000000.0", "4.1,4.2", "5.0,5.1", "4.1,4.2,5.0"]
    for each level in invalidLevelStrings
        device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", level] }, { result: true }])
        if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "noncanonical level cannot coerce to capacity " + FormatJson(level)) then return false
        if not playbackCapabilityExpect(device.calls.Count() = 1, "malformed trailing level prevents partial success " + FormatJson(level)) then return false
    end for

    for each level in ["1.1", "1.2", "1.3", "2.2", "3.2", "4.2"]
        device = playbackLevelDecoder([{ result: false, updated: "level", level: ["5.1", level] }, { result: true }])
        if not playbackCapabilityExpect(not isTwitchVariantSupported(mainHevc50, device), "AVC-only level is not a canonical HEVC capacity " + level) then return false
        if not playbackCapabilityExpect(device.calls.Count() = 1, "HEVC validates all codec-specific levels " + level) then return false
    end for

    for index = 0 to invalidResponses.Count() - 1
        device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", "4.2"] }, invalidResponses[index], { result: true }])
        if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "malformed retry response fails closed " + index.ToStr()) then return false
        if not playbackCapabilityExpect(device.calls.Count() = 2, "malformed retry cannot fall through to later success " + index.ToStr()) then return false
    end for

    device = playbackLevelDecoder([{ fixtureThrow: true }, { result: true }])
    if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "initial decoder exception fails closed") then return false
    if not playbackCapabilityExpect(device.calls.Count() = 1, "initial exception cannot negotiate") then return false
    device = playbackLevelDecoder([{ result: false, updated: "level", level: ["4.1", "4.2"] }, { fixtureThrow: true }, { result: true }])
    if not playbackCapabilityExpect(not isTwitchVariantSupported(main31, device), "capacity decoder exception fails closed") then return false
    if not playbackCapabilityExpect(device.calls.Count() = 2, "capacity exception cannot fall through to later success") then return false
    return true
end function

function playbackLevelDecoder(responses as object) as object
    ' Arrays retain identity in brs-engine; captured JSON also avoids nested AA
    ' writes disappearing through its copy-on-read behavior.
    return {
        calls: [],
        responses: responses,
        CanDecodeVideo: function(format as object) as dynamic
            m.calls.Push(FormatJson(format))
            index = m.calls.Count() - 1
            if index >= m.responses.Count() then return invalid
            response = m.responses[index]
            if GetInterface(response, "ifAssociativeArray") <> invalid
                if response.fixtureThrow = true then throw "fixture decoder unavailable"
            end if
            return response
        end function
    }
end function

function playbackLevelQueriesMatch(device as object, codec as string, profile as string, levels as object, detail as string) as boolean
    if not playbackCapabilityExpect(device.calls.Count() = levels.Count(), detail + " query count") then return false
    for index = 0 to levels.Count() - 1
        query = ParseJson(device.calls[index])
        if not playbackCapabilityExpect(query.Count() = 3 and query.codec = codec and query.profile = profile and query.level = levels[index], detail + " query " + index.ToStr()) then return false
    end for
    return true
end function
