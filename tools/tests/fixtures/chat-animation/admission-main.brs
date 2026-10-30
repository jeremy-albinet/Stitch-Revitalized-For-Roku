sub main()
    m.assertions = 0
    m.failures = 0
    cases = parseJson(readAsciiFile("pkg:/cases.json"))
    for each sample in cases
        bytes = createObject("roByteArray")
        check(bytes.readFile("pkg:/" + sample.name + ".webp"), "read generated binary fixture " + sample.name)
        result = chatAdmitWebp(bytes)
        check((result <> invalid) = sample.valid, "admission for " + sample.name)
        if result <> invalid
            check(result.bytes = bytes.count(), "actual byte count " + sample.name)
            check(result.loadWidth > 0 and result.loadHeight > 0 and result.loadWidth <= 64 and result.loadWidth <= result.width and result.loadHeight <= 64 and result.loadHeight <= result.height, "decode dimensions without upscaling " + sample.name)
            if sample.width <> invalid then check(result.width = sample.width and result.height = sample.height, "actual canvas " + sample.name)
            if sample.frames <> invalid then check(result.frames = sample.frames, "actual frame count " + sample.name)
            if sample.duration <> invalid then check(result.durationMs = sample.duration, "actual cycle " + sample.name)
            if sample.loadWidth <> invalid then check(result.loadWidth = sample.loadWidth and result.loadHeight = sample.loadHeight, "bounded decode dimensions " + sample.name)
        end if
    end for
    check(chatAdmitWebp(invalid) = invalid and chatAdmitWebp({}) = invalid, "non-byte inputs are rejected")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

sub check(ok as boolean, message as string)
    m.assertions++
    if not ok
        m.failures++
        print "CHAT_ANIMATION_FAIL: " + message
    end if
end sub
