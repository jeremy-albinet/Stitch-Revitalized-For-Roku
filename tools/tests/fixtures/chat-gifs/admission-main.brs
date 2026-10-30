sub main()
    m.checks = 0
    m.failures = 0
    for each sample in parseJson(readAsciiFile("pkg:/cases.json"))
        bytes = createObject("roByteArray")
        check(bytes.readFile("pkg:/" + sample.name + ".gif"), "fixture file " + sample.name)
        result = chatAdmitGif(bytes)
        check((result <> invalid) = sample.valid, "admission " + sample.name)
        if result <> invalid
            check(result.format = "gif" and result.bytes = bytes.count(), "format/actual admitted bytes " + sample.name)
            check(result.loadWidth >= 1 and result.loadHeight >= 1 and result.loadWidth <= 64 and result.loadHeight <= 64, "bounded native decode dimensions " + sample.name)
            check(result.width <= 512 and result.height <= 512 and result.width * result.height * result.frames <= 4194304 and result.frames <= 128 and result.durationMs <= 20000, "source work remains bounded " + sample.name)
            if sample.width <> invalid then check(result.width = sample.width and result.height = sample.height, "source canvas " + sample.name)
            if sample.frames <> invalid then check(result.frames = sample.frames, "actual frames " + sample.name)
            if sample.duration <> invalid then check(result.durationMs = sample.duration, "actual frame delays " + sample.name)
            if sample.loadWidth <> invalid then check(result.loadWidth = sample.loadWidth and result.loadHeight = sample.loadHeight, "aspect-preserving bounded decode " + sample.name)
        end if
    end for
    check(chatAdmitGif(invalid) = invalid and chatAdmitGif({}) = invalid and chatAdmitGif([]) = invalid, "invalid byte input")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
end sub

sub check(ok as boolean, label as string)
    m.checks++
    if not ok
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
