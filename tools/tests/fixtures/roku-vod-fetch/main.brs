sub vfAssert(ok as boolean, message as string)
    m.assertions++
    if not ok then throw "fetch-fixture:" + message
end sub

function vfYes(value = invalid as dynamic, extra = invalid as dynamic) as boolean
    return true
end function

sub vfPort(port as object)
    m.port = port
end sub

function vfGetPort() as object
    return m.port
end function

sub vfUrl(url as string)
    m.url = url
end sub

function vfIdentity() as integer
    return m.identity
end function

function vfHead() as boolean
    m.state[7].Push({ url: m.url, phase: "head" })
    return m.state[3]
end function

function vfGet(path as string) as boolean
    m.state[7].Push({ url: m.url, phase: "get" })
    m.state[1] = true
    return m.state[3]
end function

function vfCancel() as boolean
    m.state[8]++
    return m.state[4]
end function

function vfExists(path as string) as boolean
    return m.state[1]
end function

function vfStat(path as string) as object
    size = m.state[0].Count()
    if m.state[10] <> invalid then size = m.state[10]
    return { type: "file", size: size }
end function

function vfDelete(path as string) as boolean
    m.state[11]++
    if not m.state[5] then return false
    m.state[1] = false
    return true
end function

function rvfFileSystem() as object
    return { state: m.io, Exists: vfExists, Stat: vfStat, Delete: vfDelete }
end function

function rvfTransfer() as object
    m.io[9]++
    return { state: m.io, identity: m.io[9], port: invalid, url: "", SetMessagePort: vfPort, GetMessagePort: vfGetPort, SetCertificatesFile: vfYes, EnablePeerVerification: vfYes, EnableHostVerification: vfYes, EnableEncodings: vfYes, EnableResume: vfYes, SetMinimumTransferRate: vfYes, SetHeaders: vfYes, SetUrl: vfUrl, GetIdentity: vfIdentity, AsyncHead: vfHead, AsyncGetToFile: vfGet, AsyncCancel: vfCancel }
end function

function rvfConfigureTransport(transfer as object, url as string) as boolean
    return m.io[2]
end function

function rvfReadFile(path as string, count as integer) as dynamic
    return m.io[0]
end function

function rvfUrlEvent(event as dynamic) as boolean
    return Type(event) = "roAssociativeArray"
end function

function vfEventIdentity() as integer
    return m.state[0]
end function

function vfEventInt() as integer
    return m.state[1]
end function

function vfEventCode() as integer
    return m.state[2]
end function

function vfEventHeaders() as object
    return m.state[3]
end function

function vfEvent(identity as integer, size as integer, status = 200 as integer, headers = invalid as dynamic) as object
    if headers = invalid then headers = [{ "Content-Length": size.ToStr() }]
    return { state: [identity, 1, status, headers], GetSourceIdentity: vfEventIdentity, GetInt: vfEventInt, GetResponseCode: vfEventCode, GetResponseHeadersArray: vfEventHeaders }
end function

function vfBytes(text as string) as object
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(text)
    return bytes
end function

function vfNew() as object
    m.io = [vfBytes(m.master), false, true, true, true, true, 0, [], 0, 0, invalid, 0]
    state = rokuVodFetchCreate(m.descriptor, m.session)
    vfAssert(state <> invalid and state.phase = "idle" and not state.trusted and state.index = invalid, "independent finite constructor")
    vfAssert(state.path = "tmp:/stitch-vod-" + m.session + ".bin" and state.op = invalid and not state.ownFile, "exclusive session input ownership")
    return state
end function

sub vfComplete(state as object, kind as string, entryNo as integer, bytes as object, nowMs as longinteger)
    m.io[0] = bytes
    vfAssert(rokuVodFetchBegin(state, kind, entryNo, m.port, nowMs), "actual authorized transfer begins")
    vfAssert(not rokuVodFetchBegin(state, kind, entryNo, m.port, nowMs), "no overlapping transfer")
    op = state.op
    if kind = "master"
        vfAssert(op.phase = "get" and op.headCount = -1 and state.ownFile and m.io[7].Count() = 1 and m.io[7][0].phase = "get", "Usher master starts one direct GET without HEAD")
    else
        vfAssert(op.phase = "head" and not state.ownFile, "non-master starts HEAD without staging")
        vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(op.identity, bytes.Count()), nowMs + 1&), "actual HEAD completion")
        vfAssert(state.phase <> "failed", "HEAD conversion failed:" + state.reason)
        vfAssert(state.op.phase = "get" and state.ownFile and state.op.identity <> op.identity and state.op.headCount = bytes.Count(), "one retained GET and distinct source identity")
        vfAssert(not rokuVodFetchHandleUrlEvent(state, vfEvent(op.identity, bytes.Count()), nowMs + 2&), "late HEAD event ignored")
    end if
    op = state.op
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(op.identity, bytes.Count()), nowMs + 3&), "actual GET completion")
    vfAssert(state.phase = "ready" and state.op = invalid and not state.ownFile and not m.io[1], "deleted staging before completed output")
    vfAssert(not rokuVodFetchHandleUrlEvent(state, vfEvent(op.identity, bytes.Count()), nowMs + 4&), "completed event cannot publish twice")
end sub

sub vfSequence()
    state = vfNew()
    vfAssert(rvfIntent(state, "playlist", -1) = invalid and rvfIntent(state, "media", 0) = invalid, "master corroboration precedes all CDN requests")
    vfComplete(state, "master", -1, vfBytes(m.master), 0&)
    vfAssert(state.trusted and state.index = invalid and m.io[7][0].url = m.descriptor.usherUrl, "exact hardcoded Usher master independently downloaded")
    output = rokuVodFetchTake(state)
    vfAssert(output.kind = "master" and output.data = true and rokuVodFetchTake(state) = invalid, "trusted master payload not retained or replayed")
    vfComplete(state, "playlist", -1, vfBytes(m.playlist), 10&)
    output = rokuVodFetchTake(state)
    vfAssert(output.kind = "playlist" and output.data.count = 24 and state.index.count = 24, "full actual immutable index admitted")
    vfAssert(m.io[7][1].url = m.descriptor.sourceUrl, "only exact corroborated variant requested")
    vfComplete(state, "init", -1, vfBytes("synthetic init body"), 20&)
    output = rokuVodFetchTake(state)
    vfAssert(output.kind = "init" and output.entryNo = -1 and output.data.ToAsciiString() = "synthetic init body", "binary init delivered without byte changes")
    vfAssert(m.io[7][3].url = state.index.mapUri, "init URI resolved only from validated index")
    vfComplete(state, "media", 23, vfBytes("paired source bytes"), 30&)
    output = rokuVodFetchTake(state)
    vfAssert(output.entryNo = 23 and output.data.ToAsciiString() = "paired source bytes", "sparse exact authorized entry bytes")
    vfAssert(m.io[7][5].url = rokuVodIndexEntry(state.index, 23).uri, "no sequential eager download")
    vfAssert(m.io[7].Count() = 7 and m.io[7][0].phase = "get" and m.io[7][1].phase = "head" and m.io[7][2].phase = "get" and m.io[7][3].phase = "head" and m.io[7][4].phase = "get" and m.io[7][5].phase = "head" and m.io[7][6].phase = "get", "only master skips HEAD in actual request sequence")
    vfAssert(rvfIntent(state, "media", 24) = invalid and rvfIntent(state, "media", -1) = invalid and rvfIntent(state, "https://foreign.invalid", 0) = invalid, "unindexed and arbitrary URL refusals")
    vfAssert(rokuVodFetchPump(state, 31001&, false) and rokuVodFetchPump(state, 65001&, false), "long pause has no idle or lifetime expiry")
    vfAssert(rokuVodFetchClose(state) and state.closed and state.index = invalid and state.descriptor = invalid and state.op = invalid and state.output = invalid, "close releases all private references")
    vfAssert(rokuVodFetchClose(state) and not rokuVodFetchBegin(state, "master", -1, m.port, 65001&), "closed owner never restarts")
end sub

sub vfRefusals()
    vfAssert(rokuVodFetchCreate(m.descriptor, m.session.Left(31)) = invalid, "invalid owner refused")
    state = vfNew()
    m.io[2] = false
    vfAssert(not rokuVodFetchBegin(state, "master", -1, m.port, 0&), "failed native transport configuration refuses before Async")
    vfAssert(state.reason = "transport_configuration" and m.io[7].Count() = 0 and state.op = invalid and not state.trusted, "configuration failure starts no request")
    vfAssert(rokuVodFetchClose(state), "refused transfer owner closes")
    state = vfNew()
    state.descriptor.sourceUrl = "https://foreign.invalid/index.m3u8"
    vfAssert(not rokuVodFetchBegin(state, "master", -1, m.port, 0&) and m.io[7].Count() = 0, "mutated descriptor refused without egress")
    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "refusal master GET fixture begins")
    identity = state.op.identity
    vfAssert(not rokuVodFetchHandleUrlEvent(state, vfEvent(identity + 1, m.io[0].Count()), 1&) and state.op.identity = identity, "foreign transfer identity cannot advance state")
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(identity, m.io[0].Count(), 302, [{"Content-Length": "1"}, {"Location": "https://foreign.invalid/x"}]), 2&), "redirect completion observed")
    vfAssert(state.phase = "failed" and not state.trusted and m.io[7].Count() = 1, "redirect never starts CDN or followup GET")
    vfAssert(rokuVodFetchClose(state), "redirect refusal cleans retained owner")
    state = vfNew()
    m.io[0] = vfBytes(m.master.Replace("1920x1080", "1280x720"))
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "mismatching master begins")
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(state.op.identity, m.io[0].Count()), 1&), "mismatch direct GET processed")
    vfAssert(state.phase = "failed" and state.reason = "master_mismatch" and not state.trusted and not m.io[1] and state.output = invalid, "master mismatch deleted before refusing variant")
    vfAssert(rokuVodFetchClose(state), "mismatch cleanup acknowledged")
    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "deadline begins")
    vfAssert(not rokuVodFetchPump(state, 5000&, false) and state.reason = "operation_deadline" and state.op = invalid and m.io[8] = 1 and not state.ownFile and not m.io[1], "deadline cancels exact active transfer")
    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "stop direct GET begins")
    vfAssert(state.op.phase = "get" and state.ownFile, "stop fixture owns direct GET staging")
    vfAssert(not rokuVodFetchPump(state, 2&, true) and state.op = invalid and not state.ownFile and not m.io[1] and m.io[8] = 1, "stop cancels and verifies staging removal")
    vfAssert(rokuVodFetchClose(state), "stopped helper closes")
    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "cancel-block fixture begins")
    m.io[4] = false
    vfAssert(not rokuVodFetchClose(state) and state.cleanupBlocked and state.op <> invalid and not state.closed, "failed cancellation retains unresolved transfer ownership")
    m.io[4] = true
    vfAssert(rokuVodFetchClose(state), "actual later cancellation releases once")
    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "delete-block fixture begins")
    vfAssert(state.op.phase = "get" and state.ownFile, "delete-block owns direct GET staging")
    m.io[5] = false
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(state.op.identity, m.io[0].Count()), 2&), "blocked completion handled")
    vfAssert(state.phase = "failed" and state.cleanupBlocked and state.ownFile and state.output = invalid and not rokuVodFetchClose(state), "failed deletion cannot deliver or acknowledge cleanup")
    m.io[5] = true
    vfAssert(rokuVodFetchClose(state) and not m.io[1], "verified eventual deletion closes")
    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "oversized in-flight direct GET begins")
    vfAssert(state.op.phase = "get" and state.ownFile, "oversized in-flight owns direct GET staging")
    m.io[10] = 262145
    vfAssert(not rokuVodFetchPump(state, 2&, false) and state.reason = "inflight_size" and state.op = invalid and not m.io[1], "actual in-flight oversize cancels and deletes before acceptance")
    vfAssert(rokuVodFetchClose(state), "oversized transfer owner closes")
    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "corrupt-path direct GET begins")
    vfAssert(state.op.phase = "get" and state.ownFile, "corrupt-path owns direct GET staging")
    state.path = "tmp:/foreign-owned.bin"
    vfAssert(not rokuVodFetchPump(state, 2&, false) and state.cleanupBlocked and state.ownFile and m.io[11] = 0, "foreign path is never read/deleted or falsely acknowledged")
    state.path = "tmp:/stitch-vod-" + m.session + ".bin"
    vfAssert(rokuVodFetchClose(state) and not m.io[1], "only restored exact session path can be verified and removed")
end sub

sub vfCountPairing()
    state = vfNew()
    vfComplete(state, "master", -1, vfBytes(m.master), 0&)
    unused = rokuVodFetchTake(state)
    m.io[0] = vfBytes(m.playlist)
    vfAssert(rokuVodFetchBegin(state, "playlist", -1, m.port, 10&), "mismatched non-master HEAD begins")
    headIdentity = state.op.identity
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(headIdentity, m.io[0].Count() + 1), 11&), "mismatched non-master HEAD completes")
    vfAssert(state.op.phase = "get" and state.op.identity <> headIdentity and state.op.headCount = m.io[0].Count() + 1, "non-master GET retains exact HEAD count")
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(state.op.identity, m.io[0].Count()), 12&), "different non-master GET count observed")
    vfAssert(state.phase = "failed" and state.reason = "head_get_count" and state.output = invalid and state.index = invalid and not state.ownFile and not m.io[1], "non-master HEAD GET count mismatch refuses and deletes")
    vfAssert(rokuVodFetchClose(state), "count mismatch owner closes")

    state = vfNew()
    vfComplete(state, "master", -1, vfBytes(m.master), 0&)
    unused = rokuVodFetchTake(state)
    m.io[0] = vfBytes(m.playlist)
    vfAssert(rokuVodFetchBegin(state, "playlist", -1, m.port, 10&), "sentinel refusal non-master HEAD begins")
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(state.op.identity, m.io[0].Count()), 11&), "sentinel refusal non-master HEAD completes")
    state.op.headCount = -1
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(state.op.identity, m.io[0].Count()), 12&), "non-master missing HEAD count observed")
    vfAssert(state.phase = "failed" and state.reason = "head_get_count" and state.output = invalid and not state.ownFile and not m.io[1], "only master may use absent HEAD count sentinel")
    vfAssert(rokuVodFetchClose(state), "sentinel refusal owner closes")

    state = vfNew()
    vfAssert(rokuVodFetchBegin(state, "master", -1, m.port, 0&), "master altered HEAD count fixture begins")
    state.op.headCount = m.io[0].Count() - 1
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(state.op.identity, m.io[0].Count()), 1&), "master altered HEAD count observed")
    vfAssert(state.phase = "failed" and state.reason = "head_get_count" and not state.trusted and state.output = invalid and not state.ownFile and not m.io[1], "master exception requires exact minus one sentinel")
    vfAssert(rokuVodFetchClose(state), "master altered count owner closes")
end sub

sub vfMediaLimits()
    state = vfNew()
    vfAssert(rvfIntent(state, "master", -1).limit = 262144 and rvfIntent(state, "media", 0) = invalid, "master cap and independent authority remain unchanged")
    vfComplete(state, "master", -1, vfBytes(m.master), 0&)
    unused = rokuVodFetchTake(state)
    vfAssert(rvfIntent(state, "playlist", -1).limit = 262144, "playlist cap remains256KiB")
    vfComplete(state, "playlist", -1, vfBytes(m.playlist), 10&)
    unused = rokuVodFetchTake(state)
    vfAssert(rvfIntent(state, "init", -1).limit = 2097152 and rvfIntent(state, "media", 0).limit = 12582912, "only completed authorized media gets12MiB cap")
    for each size in [4194304, 9418736, 12582912]
        vfAssert(rvfHeaders([{ "Content-Length": size.ToStr() }], 200, 12582912, true) = size, "actual media HEAD framing accepts reviewed whole-input profile")
        vfAssert(rvfHeaders([{ "Content-Length": size.ToStr() }, { "Content-Range": "bytes 0-" + (size - 1).ToStr() + "/" + size.ToStr() }], 206, 12582912, false) = size, "actual complete media206 framing accepts reviewed profile")
    end for
    before = m.io[7].Count()
    vfAssert(rokuVodFetchBegin(state, "media", 0, m.port, 20&), "oversized reviewed media HEAD begins")
    vfAssert(rokuVodFetchHandleUrlEvent(state, vfEvent(state.op.identity, 12582913), 21&), "above12MiB HEAD completion observed")
    vfAssert(state.phase = "failed" and state.reason = "framing_integer" and m.io[7].Count() = before + 1 and state.op = invalid and not state.ownFile and state.output = invalid, "above12MiB media refuses before GET and output")
    vfAssert(rokuVodFetchClose(state), "oversized profile refusal cleans retained owner")
end sub

sub vfFraming()
    vfAssert(rvfHeaders([{ "Content-Length": "4" }], 200, 4, true) = 4, "strict HEAD count")
    vfAssert(rvfHeaders([{ "Content-Length": "4" }, { "Content-Range": "bytes 0-3/4" }], 206, 4, false) = 4, "complete bounded 206")
    cases = [ [{ "Content-Length": "5" }], [{ "Content-Length": "0" }], [{ "Content-Length": "04" }], [{ "Content-Length": "4" }, { "content-length": "4" }], [{ "Transfer-Encoding": "chunked" }], [{ "Content-Length": "4" }, { "Content-Encoding": "gzip" }], [{ "Content-Length": "4" }, { "Content-Range": "bytes 1-4/5" }], [{ "Content-Length": "4" }, { "Location": "https://foreign.invalid" }], [] ]
    for each headers in cases
        rejected = false
        try
            unused = rvfHeaders(headers, 200, 4, false)
        catch error
            rejected = true
        end try
        vfAssert(rejected, "malformed, duplicate, compressed, redirect, incomplete, oversized framing refuses")
    end for
    for each stat in [{ type: "directory", size: 4 }, { type: "file", size: 5 }, { type: "file", size: 3 }, { type: "file", size: 4.0 }, invalid]
        rejected = false
        try
            unused = rvfCompletedCount(stat, 4, 4)
        catch error
            rejected = true
        end try
        vfAssert(rejected, "actual file stat and framing bounds")
    end for
end sub

function vfCerts(value as string) as boolean
    m.state[0].Push(["certs", value])
    return m.state[1] <> "certs"
end function

function vfPeer(value as boolean) as boolean
    m.state[0].Push(["peer", value])
    return m.state[1] <> "peer"
end function

function vfHost(value as boolean) as boolean
    m.state[0].Push(["host", value])
    return m.state[1] <> "host"
end function

function vfEncoding(value as boolean) as boolean
    m.state[0].Push(["encoding", value])
    return m.state[1] <> "encoding"
end function

function vfResume(value as boolean) as boolean
    m.state[0].Push(["resume", value])
    return m.state[1] <> "resume"
end function

function vfRate(value as integer, seconds as integer) as boolean
    m.state[0].Push(["rate", value, seconds])
    return m.state[1] <> "rate"
end function

sub vfTransportConfiguration()
    state = [[], ""]
    transfer = { state: state, SetCertificatesFile: vfCerts, EnablePeerVerification: vfPeer, EnableHostVerification: vfHost, EnableEncodings: vfEncoding, EnableResume: vfResume, SetMinimumTransferRate: vfRate }
    vfAssert(vfActualConfigureTransport(transfer, m.descriptor.usherUrl), "actual documented native configuration function")
    vfAssert(FormatJson(state[0]) = FormatJson([["certs", "common:/certs/ca-bundle.crt"], ["peer", true], ["host", true], ["encoding", false], ["resume", false], ["rate", 1, 2]]), "actual CA/TLS/no-encoding/no-resume/min-rate call arguments, no auth/cookies")
    for each failed in ["certs", "peer", "host", "encoding", "resume", "rate"]
        state[0] = []
        state[1] = failed
        vfAssert(not vfActualConfigureTransport(transfer, m.descriptor.usherUrl), "every actual native option failure refuses configuration")
    end for
    state[0] = []
    state[1] = ""
    vfAssert(not vfActualConfigureTransport(transfer, "http://foreign.invalid") and state[0].Count() = 0, "non-HTTPS URL refuses before native setup")
end sub

sub main()
    m.assertions = 0
    m.session = "0123456789abcdef0123456789abcdef"
    m.master = ReadAsciiFile("pkg:/master.m3u8")
    m.playlist = ReadAsciiFile("pkg:/index.m3u8")
    m.port = CreateObject("roMessagePort")
    try
        m.descriptor = rokuVodDescriptorFromTrustedMaster(m.master, "https://usher.ttvnw.net/vod/v2/123.m3u8?fixture=synthetic", { sourceUrl: "https://dsynthetic.cloudfront.net/archive/index.m3u8?fixture=synthetic", qualityId: "1080p60" }, "123")
        vfAssert(m.descriptor <> invalid, "actual trusted syntax fixture")
        vfTransportConfiguration()
        vfSequence()
        vfRefusals()
        vfCountPairing()
        vfMediaLimits()
        vfFraming()
        print "STITCH_VOD_FETCH_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 0})
    catch error
        print "STITCH_VOD_FETCH_FAIL: __MARKER__ " + error.message
        print "STITCH_VOD_FETCH_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 1})
    end try
end sub
