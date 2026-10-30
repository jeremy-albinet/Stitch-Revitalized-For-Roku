sub main()
    m.assertions = 0
    m.failures = 0
    m.marker = "__MARKER__"
    mode = "__MODE__"
    origin = "https://vod-cdn.example.test"
    source = origin + "/archive/index.m3u8?master=fixture%2Bquery"
    corpus = ParseJSON(ReadAsciiFile("pkg:/corpus.json"))
    if mode = "normal" or mode = "small"
        small = indexBytes(corpus.small)
        index = rokuVodIndexParse(small, source, origin)
        indexCheck(index <> invalid, "small completed VOD accepts")
        if index <> invalid
            indexCheck(index.count = 3 and index.sequence = 123& and index.totalUs = 31250001&, "exact microsecond durations and nonzero sequence")
            first = rokuVodIndexEntry(index, 0)
            indexCheck(first <> invalid, "first entry exists")
            if first <> invalid then indexCheck(first.uri = origin + "/archive/first.m4s?sig=fixture%2Fab%25" and first.durationUs = 1000001& and first.startUs = 0&, "first entry and query remain exact")
            indexCheck(index.mapUri = origin + "/archive/init.mp4?sig=fixture%2Bbytes", "init query remains exact")
            indexCheck(rokuVodIndexFind(index, 0&) = 0, "seek starts at recording start")
            indexCheck(rokuVodIndexFind(index, 1000000&) = 0, "last microsecond before boundary stays prior entry")
            indexCheck(rokuVodIndexFind(index, 1000001&) = 1, "boundary belongs to next entry")
            indexCheck(rokuVodIndexFind(index, 1250000&) = 1, "fractional middle position resolves")
            indexCheck(rokuVodIndexFind(index, 1250001&) = 2, "last entry starts at exact cumulative duration")
            indexCheck(rokuVodIndexFind(index, 31250000&) = 2, "recording's last microsecond resolves")
            indexCheck(rokuVodIndexFind(index, 31250001&) = invalid and rokuVodIndexFind(index, -1&) = invalid, "seek outside finite timeline refuses")
            indexCheck(rokuVodIndexEntry(index, -1) = invalid and rokuVodIndexEntry(index, 3) = invalid, "entry boundaries refuse")
            indexCheck(rokuVodIndexEntry(index, 1.0) = invalid and rokuVodIndexFind(index, 1.0) = invalid, "fractional scalar types refuse")
            small[0] = 33
            indexCheck(index.raw[0] = 35 and rokuVodIndexEntry(index, 0) <> invalid, "index owns raw copy independently of input mutation")
            first = rokuVodIndexEntry(index, 0)
            if first <> invalid then first.durationUs = 5&
            repeat = rokuVodIndexEntry(index, 0)
            if repeat <> invalid then indexCheck(repeat.durationUs = 1000001&, "returned entry mutation cannot change packed timeline")
            index.extra = true
            indexCheck(rokuVodIndexEntry(index, 0) = invalid and rokuVodIndexFind(index, 0&) = invalid, "wrong index shape refuses")
        end if
        crlf = rokuVodIndexParse(indexBytes(corpus.crlf), source, origin)
        indexCheck(crlf <> invalid, "CRLF input accepts")
        if crlf <> invalid
            middle = rokuVodIndexEntry(crlf, 1)
            indexCheck(middle <> invalid, "CRLF reference offset excludes carriage return")
            if middle <> invalid then indexCheck(middle.uri = origin + "/archive/second.m4s" and middle.startUs = 1000001&, "CRLF packed offset and exact timeline")
        end if
        defaultSequence = rokuVodIndexParse(indexBytes(corpus.defaultSequence), source, origin)
        indexCheck(defaultSequence <> invalid, "absent media sequence accepts default")
        if defaultSequence <> invalid then indexCheck(defaultSequence.sequence = 0&, "absent media sequence defaults zero")
        absolute = rokuVodIndexParse(indexBytes(corpus.absolute), source, origin)
        indexCheck(absolute <> invalid, "exact pinned absolute reference accepts")
        if absolute <> invalid
            entry = rokuVodIndexEntry(absolute, 0)
            if entry <> invalid then indexCheck(entry.uri = origin + "/absolute.m4s?x=fixture%2B%25", "absolute signed query bytes are unchanged")
        end if
        indexCheck(rokuVodIndexParse(invalid, source, origin) = invalid, "invalid body shape refuses")
        indexCheck(rokuVodIndexParse({}, source, origin) = invalid, "AA body shape refuses")
        indexCheck(rokuVodIndexParse(indexBytes(corpus.single), source, origin + "/") = invalid, "origin pin must be exact canonical origin")
        indexCheck(rokuVodIndexParse(indexBytes(corpus.single), "https://foreign.example.test/index.m3u8", origin) = invalid, "base source origin mismatch refuses")
        indexCheck(rokuVodIndexParse(indexBytes(corpus.single), "https://user@vod-cdn.example.test/index.m3u8", origin) = invalid, "base userinfo refuses")
        indexCheck(rokuVodIndexParse(indexBytes(corpus.single), "https://vod-cdn.example.test:443/index.m3u8", origin) = invalid, "base port refuses")
        indexCheck(rokuVodIndexParse(indexBytes(corpus.single), "https://VOD-CDN.example.test/index.m3u8", origin) = invalid, "noncanonical uppercase host refuses")
        indexCheck(rokuVodIndexEntry(invalid, 0) = invalid and rokuVodIndexFind({}, 0&) = invalid, "invalid getter shape safely refuses")
        for each malformed in ["truncated records", "reference offset overflow", "duration overflow", "sequence overflow", "zero entries", "foreign source", "foreign init"]
            damaged = rokuVodIndexParse(indexBytes(corpus.small), source, origin)
            if damaged <> invalid
                if malformed = "truncated records"
                    damaged.records = damaged.records.Slice(0, 71)
                else if malformed = "reference offset overflow"
                    damaged.records[0] = 255
                else if malformed = "duration overflow"
                    damaged.records[8] = 255
                else if malformed = "sequence overflow"
                    damaged.sequence = 4294967296&
                else if malformed = "zero entries"
                    damaged.count = 0
                else if malformed = "foreign source"
                    damaged.sourceUrl = "https://foreign.example.test/archive/index.m3u8"
                else if malformed = "foreign init"
                    damaged.mapUri = "https://foreign.example.test/init.mp4"
                end if
                indexCheck(rokuVodIndexEntry(damaged, 0) = invalid and rokuVodIndexFind(damaged, 0&) = invalid, "damaged getter refuses " + malformed)
            else
                indexCheck(false, "damaged getter fixture parses")
            end if
        end for
        for each bad in corpus.bad
            indexCheck(rokuVodIndexParse(indexBytes(bad.text), source, origin) = invalid, "refuse " + bad.name)
        end for
    end if
    if mode = "normal" or mode = "small" or mode = "comments"
        baseline = rokuVodIndexParse(indexBytes(corpus.small), source, origin)
        indexCheck(baseline <> invalid, "comment comparison baseline accepts")
        for each sample in corpus.comments
            commented = rokuVodIndexParse(indexBytes(sample.text), source, origin)
            indexCheck(commented <> invalid, "comments accept " + sample.name)
            if commented <> invalid and baseline <> invalid
                indexCheck(commented.raw.ToAsciiString() = sample.text, "comments retain exact bounded raw bytes")
                indexCheck(commented.count = baseline.count and commented.sequence = baseline.sequence and commented.totalUs = baseline.totalUs and commented.targetDuration = baseline.targetDuration, "comments preserve complete timeline metadata")
                indexCheck(commented.mapUri = baseline.mapUri and commented.sourceUrl = baseline.sourceUrl and commented.approvedOrigin = baseline.approvedOrigin, "comments preserve exact signed init and source authority")
                for entryNo = 0 to baseline.count - 1
                    expected = rokuVodIndexEntry(baseline, entryNo)
                    actual = rokuVodIndexEntry(commented, entryNo)
                    indexCheck(expected <> invalid and actual <> invalid, "commented packed entry exists")
                    if expected <> invalid and actual <> invalid
                        indexCheck(actual.uri = expected.uri and actual.durationUs = expected.durationUs and actual.startUs = expected.startUs, "comments preserve every signed reference and microsecond boundary")
                        indexCheck(rokuVodIndexFind(commented, expected.startUs) = entryNo, "commented sparse seek boundary remains exact")
                    end if
                end for
            end if
        end for
        if mode = "comments"
            for each bad in corpus.bad
                indexCheck(rokuVodIndexParse(indexBytes(bad.text), source, origin) = invalid, "refuse " + bad.name)
            end for
        end if
    end if
    if mode = "normal"
        large = CreateObject("roByteArray")
        indexCheck(large.ReadFile("pkg:/large.bin"), "self-contained large synthetic body loads")
        index = rokuVodIndexParse(large, source, origin)
        indexCheck(index <> invalid, "7376-entry completed EVENT accepts under body cap")
        if index <> invalid
            indexCheck(index.count = 7376 and index.totalUs = 73760000000& and index.records.Count() = 177024, "full long timeline and exact packed storage")
            digest = CreateObject("roEVPDigest")
            indexCheck(digest.Setup("sha256") = 0, "packed storage digest setup")
            hash = LCase(digest.Process(index.records))
            indexCheck(hash = "__LARGE_DIGEST__", "all packed offsets and long durations match independent golden")
            for each entryNo in [0, 3688, 7375]
                item = rokuVodIndexEntry(index, entryNo)
                indexCheck(item <> invalid, "long recording lookup exists")
                if item <> invalid then indexCheck(item.uri = origin + "/archive/" + entryNo.ToStr() + ".m4s" and item.startUs = entryNo * 10000000& and item.durationUs = 10000000&, "long recording start middle end fields")
            end for
            indexCheck(rokuVodIndexFind(index, 36880000000&) = 3688 and rokuVodIndexFind(index, 73759999999&) = 7375, "long-integer sparse seek finds exact middle and final entry")
            indexCheck(rokuVodIndexFind(index, 73760000000&) = invalid, "long recording end is half-open")
        end if
    else if mode = "comment-lines-max"
        indexCheck(loadIndex("comment-lines-max.bin", source, origin) <> invalid, "16448 lines with ignored comments accept")
    else if mode = "comment-lines-over"
        indexCheck(loadIndex("comment-lines-over.bin", source, origin) = invalid, "16449 lines with ignored comments refuse")
    end if
    print "STITCH_VOD_INDEX_RESULT: "; m.marker; " "; FormatJSON({ assertions: m.assertions, failures: m.failures })
end sub

function loadIndex(name as string, source as string, origin as string) as dynamic
    bytes = CreateObject("roByteArray")
    if not bytes.ReadFile("pkg:/" + name) then return invalid
    return rokuVodIndexParse(bytes, source, origin)
end function

function indexBytes(text as string) as object
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(text)
    return bytes
end function

sub indexCheck(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "STITCH_VOD_INDEX_FAIL: "; label
    end if
end sub
