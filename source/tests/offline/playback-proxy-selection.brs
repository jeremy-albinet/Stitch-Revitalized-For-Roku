' @include source/utils/playbackHls.brs
sub main()
    m.selectionAssertions = 0
    m.selectionFailures = 0
    for each health in [invalid, {}, { status: 3 }, { status: false }, { status: "ok" }, { status: "ok", version: "0.1.0" }, { status: "ok", selected_master_version: "1" }, { status: "error", selected_master_version: 1 }]
        selectionCheck(not proxySupportsSelectedMaster(health), "legacy or malformed service does not advertise selected-master support")
    end for
    selectionCheck(proxySupportsSelectedMaster({ status: "ok", version: "0.3.0" }), "released service remains compatible before capability field")
    selectionCheck(proxySupportsSelectedMaster({ status: "ok", version: "0.4.0", selected_master_version: 1 }), "future service negotiates explicit supported protocol")
    attrs = {
        "BANDWIDTH": "8042999", "AVERAGE-BANDWIDTH": "7999999", "RESOLUTION": "1920x1080", "FRAME-RATE": "60.000",
        "CODECS": "avc1.4D401F,mp4a.40.2", "AUDIO": "shared", "VIDEO": "shared", "SUBTITLES": "shared", "CLOSED-CAPTIONS": "captions",
        "VIDEO-RANGE": "SDR", "STABLE-VARIANT-ID": "same-id", "IVS-NAME": "source", "URL": "https://old.invalid/path/master.m3u8?token=fixture", "SEPARATE-AUDIO": true
    }
    media = [
        { "TYPE": "AUDIO", "GROUP-ID": "shared", "NAME": "English, stereo", "LANGUAGE": "en", "CHANNELS": "2", "DEFAULT": "YES", "AUTOSELECT": "YES", "URI": "" },
        { "TYPE": "AUDIO", "GROUP-ID": "shared", "NAME": "French", "LANGUAGE": "fr", "DEFAULT": "NO" },
        { "TYPE": "VIDEO", "GROUP-ID": "shared", "NAME": "main", "URI": "https://old.invalid/video.m3u8?sig=fixture" },
        { "TYPE": "SUBTITLES", "GROUP-ID": "shared", "NAME": "English", "LANGUAGE": "en", "FORCED": "NO", "URI": "https://old.invalid/subs.m3u8" },
        { "TYPE": "CLOSED-CAPTIONS", "GROUP-ID": "captions", "NAME": "CC1", "INSTREAM-ID": "CC1" },
        { "TYPE": "AUDIO", "GROUP-ID": "unreferenced", "NAME": "unused", "URI": "https://old.invalid/unused.m3u8" }
    ]
    descriptor = playbackSelectionDescriptor(attrs, media)
    selectionCheck(descriptor <> invalid, "build complete descriptor")
    if descriptor = invalid then return
    selectionCheck(descriptor.attributes.Count() = attrs.Count() - 2, "exclude only two internal variant fields")
    for each key in attrs
        if key <> "URL" and key <> "SEPARATE-AUDIO"
            selectionCheck(descriptor.attributes[key] = attrs[key], "preserve exact attribute " + key)
        end if
    end for
    selectionCheck(descriptor.groups.Count() = 5, "retain every referenced type and member, excluding unreferenced groups")
    for index = 0 to 4
        member = descriptor.groups[index]
        expected = media[index]
        selectionCheck(member["hasUri"] = expected.DoesExist("URI"), "retain URI presence including an empty string")
        selectionCheck(GetInterface(member["hasUri"], "ifBoolean") <> invalid, "URI presence is Boolean")
        for each key in expected
            if key <> "URI" then selectionCheck(member.attributes[key] = expected[key], "retain every group attribute " + key)
        end for
        selectionCheck(not member.attributes.DoesExist("URI"), "exclude group URI")
    end for
    json = playbackSelectionJson([descriptor])
    selectionCheck(json <> invalid, "serialize valid descriptor")
    if json = invalid then return
    selectionCheck(json.InStr(Chr(34) + "hasUri" + Chr(34)) >= 0 and json.InStr(Chr(34) + "hasuri" + Chr(34)) < 0, "mixed-case native JSON key is quoted")
    selectionCheck(json.InStr("old.invalid") < 0 and json.InStr("fixture") < 0, "descriptor contains no original rendition/group URL")
    wire = ParseJSON(json)[0]
    selectionCheck(wire.groups[0]["hasUri"] = true and wire.groups[1]["hasUri"] = false, "JSON preserves present-empty versus missing URI")
    masterUrl = "https://usher.invalid/master.m3u8?token=a%2Fb%2B%3D&sig=fixture&x=a=b"
    url = buildProxySelectedM3u8Url("http://service.invalid:8080", masterUrl, [descriptor])
    parts = url.Split("?")[1].Split("&")
    selectionCheck(parts.Count() = 2, "selected route contains only u and selections")
    selectionCheck(parts[0].Mid(2).DecodeUriComponent() = masterUrl, "nested master URL retains its full original query")
    selectionCheck(parts[1].Mid(11).DecodeUriComponent() = json, "wire selections decode to actual builder JSON")
    attrs["CLOSED-CAPTIONS"] = "NONE"
    selectionCheck(playbackSelectionDescriptor(attrs, media).groups.Count() = 4, "NONE omits the captions group")
    changed = {}
    changed.Append(attrs)
    changed["CODECS"] = "hvc1.2.4.L153.B0,mp4a.40.2"
    selectionCheck(playbackSelectionDescriptor(changed, media).attributes["CODECS"] = changed["CODECS"], "retain whole HEVC Main10 level/audio declaration without normalization")
    changed.Delete("AVERAGE-BANDWIDTH")
    selectionCheck(not playbackSelectionDescriptor(changed, media).attributes.DoesExist("AVERAGE-BANDWIDTH"), "optional absence is preserved")
    changed["FRAME-RATE"] = "60.0"
    selectionCheck(playbackSelectionDescriptor(changed, media).attributes["FRAME-RATE"] = "60.0", "do not normalize textual FPS identity")
    attrs["URI"] = "https://injected.invalid/target"
    selectionCheck(playbackSelectionDescriptor(attrs, media) = invalid, "reject URL-bearing stream attributes")
    attrs.Delete("URI")
    attrs["CODECS"] = 123
    selectionCheck(playbackSelectionDescriptor(attrs, media) = invalid, "reject non-string attribute")
    attrs["CODECS"] = "avc1.4D401F,mp4a.40.2"
    attrs["BAD_NAME"] = "value"
    selectionCheck(playbackSelectionDescriptor(attrs, media) = invalid, "reject non-HLS attribute name")
    attrs.Delete("BAD_NAME")
    attrs[string(129, "A")] = "value"
    selectionCheck(playbackSelectionDescriptor(attrs, media) = invalid, "reject attribute name over128 characters")
    attrs.Delete(string(129, "A"))
    attrs["EXTRA"] = string(4097, "x")
    selectionCheck(playbackSelectionDescriptor(attrs, media) = invalid, "reject attribute value over4096 characters")
    attrs.Delete("EXTRA")
    manyAttrs = {}
    for index = 1 to 65
        manyAttrs["ATTR-" + index.ToStr()] = "value"
    end for
    selectionCheck(playbackSelectionDescriptor(manyAttrs, []) = invalid, "reject more than64 attributes")
    manyAttrs.Delete("ATTR-65")
    selectionCheck(playbackSelectionDescriptor(manyAttrs, []) <> invalid, "allow64 attributes")
    members = []
    for index = 1 to 65
        members.Push({ "TYPE": "AUDIO", "GROUP-ID": "shared", "NAME": index.ToStr() })
    end for
    selectionCheck(playbackSelectionDescriptor(attrs, members) = invalid, "reject more than64 referenced group members")
    members.Pop()
    selectionCheck(playbackSelectionDescriptor(attrs, members) <> invalid, "allow64 referenced group members")
    selectionCheck(buildProxySelectedM3u8Url("http://service.invalid", masterUrl, []) = invalid, "reject empty selection without legacy fallback")
    selectionCheck(buildProxySelectedM3u8Url("http://service.invalid", masterUrl, "invalid") = invalid, "reject non-array selection")
    selections = []
    for index = 1 to 33
        selections.Push(playbackSelectionDescriptor({ "BANDWIDTH": index.ToStr() }, []))
    end for
    selectionCheck(playbackSelectionJson(selections) = invalid, "reject more than32 selections")
    selections.Pop()
    selectionCheck(playbackSelectionJson(selections) <> invalid, "allow32 distinct selections")
    selectionCheck(playbackSelectionJson([{ "attributes": {}, "groups": [], "URL": "https://injected.invalid" }]) = invalid, "reject unexpected descriptor keys")
    selectionCheck(playbackSelectionJson([{ "attributes": { "URI": "https://injected.invalid" }, "groups": [] }]) = invalid, "reject URL-bearing serialized descriptor")
    selectionCheck(playbackSelectionJson([{ "attributes": {}, "groups": [{ "attributes": {}, "hasUri": "true" }] }]) = invalid, "reject non-Boolean URI flag")
    selectionCheck(playbackSelectionJson([{ "attributes": {}, "groups": [{ "attributes": {}, "hasuri": true }] }]) = invalid, "reject wrong-cased URI flag before serialization")
    large = []
    for index = 1 to 9
        large.Push(playbackSelectionDescriptor({ "NAME": string(4096, "x"), "BANDWIDTH": index.ToStr() }, []))
    end for
    selectionCheck(playbackSelectionJson(large) = invalid, "reject decoded selection payload over32KiB")
    unicodeValue = ""
    for index = 1 to 1000
        unicodeValue += "é"
    end for
    unicodeSelections = []
    for index = 1 to 17
        unicodeSelections.Push(playbackSelectionDescriptor({ "NAME": unicodeValue, "BANDWIDTH": index.ToStr() }, []))
    end for
    unicodeJson = FormatJSON(unicodeSelections)
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(unicodeJson)
    selectionCheck(bytes.Count() > 32768, "Unicode control exceeds UTF-8 payload size")
    selectionCheck(playbackSelectionJson(unicodeSelections) = invalid, "enforce payload bound in UTF-8 bytes")
    selectionCheck(playbackSelectionAttributeBytes({ "A": "é" }, 100) = 11, "early byte accounting includes actual JSON Unicode escaping")
    selectionCheck(playbackSelectionAttributeBytes({ "A": "é" }, 10) > 10, "early byte accounting stops over its remaining budget")
    if m.selectionFailures = 0 then ? "STITCH_TEST_PASS: proxy selection "; m.selectionAssertions; " assertions"
end sub

sub selectionCheck(condition as boolean, detail as string)
    m.selectionAssertions++
    if not condition
        m.selectionFailures++
        ? "STITCH_TEST_FAIL: " + detail
    end if
end sub
