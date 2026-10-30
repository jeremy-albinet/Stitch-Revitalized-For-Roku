sub main()
    m.assertions = 0
    m.failures = 0
    m.marker = "__MARKER__"
    mode = "__MODE__"
    m.corpus = ParseJson(ReadAsciiFile("pkg:/corpus.json"))
    source = m.corpus.source
    origin = m.corpus.origin
    if mode = "grammar"
        for each sample in m.corpus.good
            bytes = preflightBytes(sample.text)
            index = rokuVodIndexParse(bytes, source, origin)
            check(index <> invalid, "full accepts " + sample.name)
            check(rokuVodIndexValidate(bytes, source, origin), "validate accepts " + sample.name)
            check(rokuVodPlaylistCompleted(sample.text, source), "runtime accepts " + sample.name)
            if index <> invalid
                check(index.Keys().Count() = 10 and index.raw.Count() = bytes.Count(), "full shape and raw length")
                check(digest(index.raw) = digest(bytes), "full raw bytes unchanged")
                check(digest(index.records) = sample.recordsDigest, "all independent packed records exact")
                last = rokuVodIndexEntry(index, index.count - 1)
                check(last <> invalid, "last entry exists")
                if last <> invalid
                    check(last.startUs = sample.lastStartUs and last.durationUs = sample.lastDurationUs, "last cumulative microseconds exact")
                    check(rokuVodIndexFind(index, index.totalUs - 1&) = index.count - 1, "last microsecond resolves")
                    check(rokuVodIndexFind(index, index.totalUs) = invalid, "finite end remains half open")
                end if
            end if
        end for
        for each sample in m.corpus.bad
            bytes = preflightBytes(sample.text)
            parsed = rokuVodIndexParse(bytes, source, origin) <> invalid
            validated = rokuVodIndexValidate(bytes, source, origin)
            check(not parsed, "full refuses " + sample.name)
            check(not validated, "validate refuses " + sample.name)
            check(parsed = validated, "differential refusal " + sample.name)
        end for
        bytes = preflightBytes(m.corpus.single)
        for each wrong in [invalid, 1, 0, "true", {}, []]
            check(nviScan(bytes, source, origin, wrong) = invalid, "internal mode rejects nonboolean")
        end for
        check(nviScan(bytes, source, origin, false) = true, "internal validation mode returns boolean")
        check(type(nviScan(bytes, source, origin, true)) = "roAssociativeArray", "internal full mode returns index")
        check(not rokuVodIndexValidate(invalid, source, origin), "invalid validation input refuses")
        check(not rokuVodIndexValidate(bytes, source, origin + "/"), "noncanonical origin refuses")
        check(not rokuVodIndexValidate(bytes, "https://foreign.example.test/index.m3u8", origin), "foreign origin refuses")
        check(rokuVodRuntimeAvailable(), "compiled runtime capability enables eligible recorded playback")
        callbackChecks()
    else if mode = "writes"
        check(rokuVodPlaylistCompleted(m.corpus.single, source), "preflight never invokes packed writes")
        check(rokuVodIndexValidate(preflightBytes(m.corpus.single), source, origin), "validation skips packed writes")
        check(rokuVodIndexParse(preflightBytes(m.corpus.single), source, origin) = invalid, "full builder actually invokes packed writes")
    else if mode = "traversal"
        for each sample in ["lines-max.bin", "unterminated-max.bin"]
            bytes = CreateObject("roByteArray")
            check(bytes.ReadFile("pkg:/" + sample), "maximum line fixture loads")
            m.splitCalls = 0
            m.blockSplit = false
            check(rokuVodIndexValidate(bytes, source, origin), "maximum processed lines validate")
            check(m.splitCalls = 1, "bounded accepted input allocates one Split")
        end for
        for each sample in ["lines-over.bin", "unterminated-over.bin", "newline-flood.bin"]
            bytes = CreateObject("roByteArray")
            check(bytes.ReadFile("pkg:/" + sample), "excess line fixture loads")
            for each buildRecords in [false, true]
                m.splitCalls = 0
                m.blockSplit = true
                check(nviScan(bytes, source, origin, buildRecords) = invalid, "oversized line fragmentation refuses")
                check(m.splitCalls = 0, "excess lines refused before Split allocation")
            end for
        end for
    else if mode = "entries" or mode = "duration" or mode = "lines" or mode = "bytes"
        for each label in ["max", "over"]
            bytes = CreateObject("roByteArray")
            check(bytes.ReadFile("pkg:/" + mode + "-" + label + ".bin"), "bounded boundary fixture loads")
            index = rokuVodIndexParse(bytes, source, origin)
            parsed = index <> invalid
            validated = rokuVodIndexValidate(bytes, source, origin)
            check(parsed = (label = "max"), "full boundary " + mode + " " + label)
            check(validated = (label = "max"), "validate boundary " + mode + " " + label)
            check(parsed = validated, "boundary differential " + mode + " " + label)
            if index <> invalid and label = "max"
                if mode = "entries" then check(index.count = 8192, "entry ceiling exact")
                if mode = "duration" then check(index.totalUs = 172800000000&, "48-hour total uses long integer")
            end if
        end for
    else if mode = "long"
        bytes = CreateObject("roByteArray")
        check(bytes.ReadFile("pkg:/long.bin"), "long synthetic input loads")
        index = rokuVodIndexParse(bytes, source, origin)
        check(index <> invalid, "full7376 entries accepts")
        check(rokuVodIndexValidate(bytes, source, origin), "validation7376 entries accepts")
        if index <> invalid
            check(index.count = 7376 and index.records.Count() = 177024 and index.totalUs = 73760000000&, "unchanged full7376 index contract")
            check(digest(index.records) = "__LONG_RECORDS_DIGEST__", "full7376 record bytes match independent golden")
            check(digest(index.raw) = digest(bytes), "long raw clone remains exact")
            last = rokuVodIndexEntry(index, 7375)
            check(last <> invalid, "last7376 entry exists")
            if last <> invalid then check(last.startUs = 73750000000& and last.durationUs = 10000000&, "last7376 timestamp and duration exact")
            check(rokuVodIndexFind(index, 73759999999&) = 7375 and rokuVodIndexFind(index, 73760000000&) = invalid, "long half-open final boundary exact")
        end if
    else if mode = "count-refusal"
        bytes = CreateObject("roByteArray")
        check(bytes.ReadFile("pkg:/entries-over.bin"), "entry refusal fixture loads")
        check(not rokuVodIndexValidate(bytes, source, origin), "validation rejects8193 entries")
    else if mode = "callback"
        callbackChecks()
    end if
    print "STITCH_VOD_PREFLIGHT_RESULT: "; m.marker; " "; FormatJson({ assertions: m.assertions, failures: m.failures })
end sub

sub callbackChecks()
    source = m.corpus.source
    variant = { "URL": source, "CODECS": "avc1.4D402A,mp4a.40.2" }
    for each finish in [14999, 15000, 16000]
        resetProbe(0, finish)
        accepted = isMuxedCmafVariant(variant, {})
        if finish < 15000
            check(accepted = true and not m.playbackProbeFailed, "completion before deadline accepts")
            check(m.playbackProbeVodComplete[source] = true and m.playbackProbeCache[source] = true, "successful bounded completion is cached")
        else
            check(accepted = invalid and m.playbackProbeFailed, "completion at or after deadline refuses")
            check(m.playbackProbeVodComplete[source] = invalid and m.playbackProbeCache[source] = invalid, "late completion never records success")
        end if
        check(m.playbackProbeCount = 1 and m.httpCalls = 1 and m.lastTimeout = 3000, "one HTTP probe retains original request budget")
    end for
    resetProbe(15000, 15000)
    check(isMuxedCmafVariant(variant, {}) = invalid and m.httpCalls = 0, "initial exhausted budget refuses without HTTP")
    resetProbe(0, 0)
    m.playbackProbeCount = 8
    check(isMuxedCmafVariant(variant, {}) = invalid and m.httpCalls = 0, "probe count cap remains eight")
    resetProbe(0, 20000)
    cache = m.playbackProbeCache
    cache[source] = false
    m.playbackProbeCache = cache
    check(isMuxedCmafVariant(variant, {}) = false and m.httpCalls = 0 and m.playbackProbeCount = 0, "existing cached result bypass remains unchanged")
    resetProbe(14500, 14999)
    check(isMuxedCmafVariant(variant, {}) = true and m.lastTimeout = 500, "HTTP timeout uses original remaining budget")
    resetProbe(0, 0)
    m.fixturePlaylist = m.corpus.single.Replace("#EXT-X-ENDLIST", "#EXT-X-ENDLIS")
    check(isMuxedCmafVariant(variant, {}) = true and m.playbackProbeVodComplete[source] = false, "muxed classification does not fabricate completed VOD")
    resetProbe(0, 16000)
    m.rokuDemuxEnabled = false
    check(isMuxedCmafVariant(variant, {}) = true and not m.playbackProbeFailed, "non-VOD legacy probe behavior remains unchanged")
end sub

sub resetProbe(start as integer, finish as integer)
    m.rokuDemuxEnabled = true
    m.rokuVodEnabled = true
    m.playbackProbeCount = 0
    m.playbackProbeFailed = false
    m.playbackProbeCache = {}
    m.playbackProbeVodComplete = {}
    m.playbackProbeOrigins = {}
    m.fixturePlaylist = m.corpus.single
    m.httpCalls = 0
    m.lastTimeout = 0
    m.playbackProbeClock = {
        values: [start, finish], cursor: 0,
        TotalMilliseconds: function() as integer
            value = m.values[m.cursor]
            if m.cursor < 1 then m.cursor++
            return value
        end function
    }
end sub

' Deterministic HTTP and monotonic-clock boundaries; no network/native device IO.
function HttpRequest(options as object) as object
    m.httpCalls++
    m.lastTimeout = options.timeout
    response = {
        body: m.fixturePlaylist,
        GetResponseCode: function() as integer
            return 200
        end function,
        GetString: function() as string
            return m.body
        end function
    }
    return {
        response: response,
        Send: function() as object
            return m.response
        end function
    }
end function

function preflightBytes(text as string) as object
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(text)
    return bytes
end function

' Counts the actual Split boundary. Inadmissible fragments are never allocated
' even by the deliberately broken early-guard fixture.
function fixtureBoundedSplit(text as string, separator as string) as object
    m.splitCalls++
    if m.blockSplit then throw "fixture: inadmissible Split reached"
    return text.Split(separator)
end function

function digest(bytes as object) as string
    hash = CreateObject("roEVPDigest")
    if hash.Setup("sha256") <> 0 then return ""
    return LCase(hash.Process(bytes))
end function

sub check(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "STITCH_VOD_PREFLIGHT_FAIL: "; label
    end if
end sub
