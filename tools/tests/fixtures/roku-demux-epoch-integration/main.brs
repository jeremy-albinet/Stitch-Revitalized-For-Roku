function eiDescriptor() as object
    return {version: 1, sourceUrl: "https://canned.ttvnw.net/live/source.m3u8?token=fixtureSignature", qualityId: "1080p60", approvedOrigins: ["https://canned.ttvnw.net"],
        metadata: {videoCodec: "avc1.4D402A", audioCodec: "mp4a.40.2", width: 1920, height: 1080, frameRate: "60.000", bandwidth: 8042999, isHD: true}}
end function

function eiRequest(path as string, method = "GET" as string, range = "" as string) as string
    crlf = Chr(13) + Chr(10)
    result = method + " " + path + " HTTP/1.1" + crlf + "Host: 127.0.0.1:49371" + crlf
    if range <> "" then result += "Range: " + range + crlf
    return result + crlf
end function

sub eiReset(raw = "" as string, transitions = true as boolean)
    m.events = []
    m.observers = []
    m.top = {sessionId: "0123456789abcdef0123456789abcdef", inputDescriptor: eiDescriptor(), enableSourceTransitions: transitions, experimentalMode: true, cacheBudgetBytes: 16777216, listenPort: 49371, stopRequested: false,
        ObserveField: eiObserve, UnobserveField: eiUnobserve, observers: m.observers}
    m.sessionId = m.top.sessionId
    m.clockValues = [2000, 0]
    m.clock = {values: m.clockValues, index: 0, TotalMilliseconds: eiClock}
    m.requestClock = {values: m.clockValues, index: 1, TotalMilliseconds: eiClock}
    m.monotonicClock = nativeLiveClockCreate(0)
    m.lastNowMs = 0&
    m.steadyMode = true
    m.sourceTransitions = transitions
    m.cacheBudgetBytes = 16777216
    m.listenPort = 49371
    m.httpQuota = liveQuotaCreate(0&)
    m.counterExhausted = false
    m.closing = false
    m.port = CreateObject("roMessagePort")
    incoming = CreateObject("roByteArray")
    incoming.FromAsciiString(raw)
    outgoing = CreateObject("roByteArray")
    m.io = [incoming, 0, outgoing, m.events, [], [false], ""]
    if raw.InStr("/asset/") >= 0 then m.io[6] = raw.Split(" ")[1].Mid(7)
    m.connection = {io: m.io, GetCountRcvBuf: eiReceiveCount, IsReadable: eiReadable, Receive: eiReceive, IsWritable: eiWritable, Send: eiSend, eOK: eiSocketOk, NotifyReadable: eiNotify, NotifyWritable: eiNotify, Close: eiSocketClose}
    m.listener = invalid
    m.liveState = invalid
    m.config = invalid
    m.currentPublication = invalid
    m.currentGeneration = 0&
    m.publications = {}
    m.activeLease = ""
    m.validationLease = ""
    m.activeGeneration = 0&
    m.activeBody = invalid
    m.initMasterMetadata = invalid
    m.initMasterTiming = invalid
    m.lastDiagnostics = invalid
    m.decodeCount = 0
    m.decoderAllowed = true
    m.stopDuringDecode = false
    m.result = {ok: false, status: "failed", reason: "not_started", actualInitValidated: false, decoderApproved: false, cleanupOk: true,
        requests: 1&, completedRequests: 0&, transmittedBytes: 0&, sendCalls: 0&, shortWrites: 0&, receiveCalls: 0&, retryableReceives: 0&, bufferLogicalCount: 0&, headerBytesPeak: 0&,
        headRequests: 0&, rangeRequests: 0&, masterRequests: 0&, videoPlaylistRequests: 0&, audioPlaylistRequests: 0&, videoBodies: 0&, audioBodies: 0&, urlEventsHandled: 0&, pumpCalls: 0&,
        retiredPublications: 0&, publicationsObserved: 0&, deliveredPublications: 0&, maxPinnedGenerations: 0&, cacheBytesPeak: 0&, convertedSegmentPairs: 0&, upstreamFetchCount: 0&, upstreamPlaylistCount: 0&,
        clientErrors: 0&, errorResponses: 0&, lastClientReason: "", countersComplete: true, connectionClosed: false}
end sub

function rowEI(sequence as integer, mode = "" as string) as object
    name = "content"
    epoch = 0&
    if sequence >= 13 and sequence <= 15
        name = "ad"
        epoch = 1&
    else if sequence >= 16
        epoch = 2&
        if sequence >= 20
            name = ["content", "ad", "other"][(sequence - 20) mod 3]
            epoch += sequence - 20
        end if
    end if
    if mode = "alias" and sequence >= 13
        name = "content-alias"
        epoch = 0&
    end if
    if mode = "pts" then name = "content"
    return { name: name, epoch: epoch }
end function

function playlistEI(first as integer, count as integer, mode = "" as string, ended = false as boolean) as string
    row = rowEI(first, mode)
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:6" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:" + first.ToStr() + Chr(10)
    text += "#EXT-X-DISCONTINUITY-SEQUENCE:" + row.epoch.ToStr() + Chr(10)
    previous = invalid
    for i = 0 to count - 1
        sequence = first + i
        row = rowEI(sequence, mode)
        if previous = invalid or row.name <> previous.name or row.epoch <> previous.epoch
            if previous <> invalid and row.epoch <> previous.epoch then text += "#EXT-X-DISCONTINUITY" + Chr(10)
            text += "#EXT-X-MAP:URI=" + Chr(34) + row.name + ".mp4" + Chr(34) + Chr(10)
        end if
        text += "#EXTINF:2.002000," + Chr(10) + "segment-" + sequence.ToStr() + ".m4s" + Chr(10)
        previous = row
    end for
    if ended then text += "#EXT-X-ENDLIST" + Chr(10)
    return text
end function

function bytesEI(record as object) as object
    body = CreateObject("roByteArray")
    body.FromHexString(record.hex)
    return body
end function

sub checkEI(ok as boolean, message as string)
    m.assertions += 1
    if not ok then throw "epoch-integration-fixture: " + message
end sub

sub caseEI(name as string)
    m.cases.Push(name)
    print "STITCH_EPOCH_INTEGRATION_CASE: " + name
end sub

sub createEI(transitions = true as boolean)
    eiReset("", transitions)
    m.clockValues[0] = 0&
    checkEI(prepareRokuDemuxInput(), "typed Task policy validates actual descriptor")
    options = liveSteadyOptions()
    keys = ["mode", "sessionId"]
    if transitions then keys.Push("sourceTransitions")
    checkEI(loopbackKeys(options, keys), "actual policy emits only exact authorized options")
    m.liveState = nativeLiveCreate(m.config.trustedMediaUrl, 0&, 0, m.config.approvedOrigins, true, m.cacheBudgetBytes, options)
    checkEI(m.liveState.sourceTransitions = transitions, "actual Core receives typed policy")
end sub

sub feedEI(state as object, kind as string, payload as dynamic, nowMs as dynamic)
    m.liveState = state
    checkEI(rokuDemuxFeedInput(state, kind, payload, nowMs), "actual Fetch feed accepts approved bytes")
    m.liveState = state
end sub

sub drainEI(state as object, nowMs as dynamic)
    steps = 0
    while state.phase <> "ready" and state.phase <> "ended"
        checkEI(steps < 60, "finite exact production stage drain")
        if state.phase = "init" or state.phase = "init-rotation"
            intent = nlIntent(state, nowMs)
            name = "content"
            if intent.url.InStr("/ad.mp4") >= 0 then name = "ad"
            oldPair = state.initIds
            oldTracks = FormatJson(state.tracks)
            oldMaster = FormatJson(m.config.metadata)
            oldCalls = m.decodeCount
            record = m.corpus.inits[name]
            feedEI(state, "init", bytesEI(record.input), nowMs)
            checkEI(m.decodeCount = oldCalls + 1 and m.result.actualInitValidated and m.result.decoderApproved, "actual byte/device gate precedes real Core init staging")
            checkEI(state.phase = "init-video" and state.input <> invalid, "approved actual Core init stages conversion")
            if oldPair.Count() = 2
                checkEI(FormatJson(state.initIds) = FormatJson(oldPair) and FormatJson(state.tracks) = oldTracks and FormatJson(m.config.metadata) = oldMaster, "old init and immutable master retained before atomic split")
            end if
            nativeLiveAdvance(state, nowMs)
            if oldPair.Count() = 2 then checkEI(FormatJson(state.initIds) = FormatJson(oldPair), "one output cannot install changed pair")
            nativeLiveAdvance(state, nowMs)
            m.liveState = state
            for each pair in [[state.initIds[0],record.video],[state.initIds[1],record.audio]]
                body = nativeLiveAcquire(state,pair[0])
                checkEI(body <> invalid and nlBodyDigest(body.data) = pair[1].sha256 and LCase(body.data.ToHexString()) = pair[1].hex, "complete independent initialization split golden")
                nativeLiveRelease(state,pair[0])
                m.goldens += 1
            end for
            checkEI(state.input = invalid and state.pendingWindow = invalid and state.temporaryVideo = invalid, "atomic pair releases staging scratch")
        else if state.phase = "segment"
            missing = nlMissing(state)
            if missing = invalid
                nativeLiveAdvance(state,nowMs)
            else
                record = m.corpus.media[CInt(missing.sequence-10&)]
                feedEI(state,"segment",bytesEI(record.input),nowMs)
                nativeLiveAdvance(state,nowMs)
                nativeLiveAdvance(state,nowMs)
                saved = state.segments[nlSegmentIndex(state,missing.sequence)]
                for each pair in [[saved.videoId,record.video],[saved.audioId,record.audio]]
                    body = nativeLiveAcquire(state,pair[0])
                    checkEI(body <> invalid and nlBodyDigest(body.data) = pair[1].sha256 and LCase(body.data.ToHexString()) = pair[1].hex, "complete independent media/TFDT split golden")
                    nativeLiveRelease(state,pair[0])
                    m.goldens += 1
                end for
                m.pairs += 1
            end if
        else
            nativeLiveAdvance(state,nowMs)
        end if
        steps += 1
    end while
    m.liveState = state
end sub

sub admitEI(state as object, nowMs as dynamic)
    m.clockValues[0] = nowMs
    m.liveState = state
    checkEI(pumpLiveServer(1), "actual Server accepts actual Core generation and cached bodies")
    checkEI(m.currentGeneration = state.latest and loopbackPublicationValid(m.currentPublication), "same validated actual current generation")
    for each asset in state.assets
        checkEI(asset.leases = 0 or asset.id = m.activeLease, "temporary validation leases released with active request preserved")
    end for
    checkEI(state.op = invalid and state.transfers = 0, "offline fixture does not initiate a network transfer")
    m.admissions += 1
end sub

function preparedEI(transitions = true as boolean) as object
    createEI(transitions)
    state = m.liveState
    feedEI(state,"playlist",playlistEI(10,3),0&)
    drainEI(state,0&)
    admitEI(state,0&)
    return state
end function

sub closeEI(state as object)
    m.liveState = state
    closeLiveConnection()
    ids=[]
    for each generation in state.generations
        if generation.advertised then ids.Push(generation.id)
    end for
    for each id in ids
        nativeLiveRetire(state,id)
    end for
    checkEI(m.result.cleanupOk and nativeLiveClose(state), "actual Fetch/Core close after generation and socket cleanup")
    checkEI(state.closed and state.assets.Count() = 0 and state.segments.Count() = 0 and state.cacheBytes = 0 and state.input = invalid and state.pendingWindow = invalid and state.op = invalid and m.activeLease = "" and m.validationLease = "" and m.activeBody = invalid and m.connection = invalid, "actual typed cleanup clears all source/cache/request state")
end sub

sub socketEI(state as object, id as string, method="GET" as string)
    incoming=CreateObject("roByteArray")
    incoming.FromAsciiString(eiRequest("/asset/"+id,method,"bytes=0-3"))
    outgoing=CreateObject("roByteArray")
    m.io=[incoming,0,outgoing,m.events,state.assets,[false],id]
    m.connection={io:m.io,GetCountRcvBuf:eiReceiveCount,IsReadable:eiReadable,Receive:eiReceive,IsWritable:eiWritable,Send:eiSend,eOK:eiSocketOk,NotifyReadable:eiNotify,NotifyWritable:eiNotify,Close:eiSocketClose}
    m.result.reason="not_started"
    m.result.connectionClosed=false
end sub

sub transitionEI()
    caseEI("actual-content-ad-content-approval-publication-request")
    state=preparedEI()
    master=FormatJson(m.config.metadata)
    oldId=m.currentPublication.initVideoId
    oldBody=nativeLiveAcquire(state,oldId)
    oldHash=nlBodyDigest(oldBody.data)
    nativeLiveRelease(state,oldId)
    oldGeneration=m.currentGeneration
    ' A real old asset request lease crosses every real new publication.
    socketEI(state,oldId)
    response=prepareLiveResponse({track:"",assetId:oldId,head:false,range:""})
    checkEI(response<>invalid,"actual advertised asset response exists")
    m.activeBody=response.data
    checkEI(m.activeLease=oldId and state.assets[nlAssetIndex(state,oldId)].leases=1,"real old init request is held")
    for sequence=13 to 18
        nowMs=(sequence-12)*3000&
        feedEI(state,"playlist",playlistEI(10,sequence-9),nowMs)
        if sequence=13 or sequence=16
            checkEI(state.phase="init-rotation" and m.currentGeneration=oldGeneration,"old Server generation remains during changed init staging")
        end if
        drainEI(state,nowMs)
        admitEI(state,nowMs)
        checkEI(FormatJson(m.config.metadata)=master,"initial actual master metadata remains immutable")
        checkEI(nlBodyDigest(m.activeBody)=oldHash and state.assets[nlAssetIndex(state,oldId)].leases=1,"old actual leased init survives changed publication")
        retainedPublications=m.publications
        currentEntry=m.publications[m.currentGeneration.ToStr()]
        m.publications={}
        m.publications[m.currentGeneration.ToStr()]=currentEntry
        ' Indexed traversal survives nested production iteration of this array.
        for eiIndex = 0 to m.currentPublication.segments.Count()-1
            selectedEI=m.currentPublication.segments[eiIndex]
            checkEI(liveAssetRole(m.currentPublication,selectedEI.initVideoId)="init" and liveAssetRole(m.currentPublication,selectedEI.initAudioId)="init","actual mixed publication later pair retains init role")
            checkEI(advertisedAssetTrack(selectedEI.initVideoId)="video" and advertisedAssetTrack(selectedEI.initAudioId)="audio","all actual later epoch initialization pairs are advertised")
        end for
        m.publications=retainedPublications
        if sequence=13 or sequence=16 or sequence=18
            name="first-ad"
            if sequence=16 then name="return"
            if sequence=18 then name="rolled"
            for each track in ["video","audio"]
                manifest=loopbackManifest(track,m.currentPublication)
                checkEI(manifest.ToAsciiString()=m.corpus.manifests[name][track],"exact independent mixed-epoch manifest golden")
                m.manifests+=1
            end for
        end if
        oldGeneration=m.currentGeneration
    end for
    checkEI(state.initPairCount=3 and state.segmentPairCount=9 and m.decodeCount=3,"all real initialization and media pairs approved once")
    checkEI(m.initMasterTiming.videoTimescale=m.corpus.inits.content.videoTimescale,"first actual master timing remains immutable")
    checkEI(state.tracks[0][0]=m.corpus.inits.content.videoTrackId,"return content retains its actual track identity")
    ' Current does not reference old first init. Lease, not generation, pins body.
    checkEI(nlAssetIndex(state,oldId)>=0,"old leased init still cached before socket close")
    closeLiveConnection()
    checkEI(m.events[m.events.Count()-1]="socket-close" and m.activeLease="" and m.activeBody=invalid,"actual socket closure precedes actual request release")
    checkEI(nlAssetIndex(state,oldId)<0,"last old request release permits retired init pruning")
    for each method in ["GET","HEAD"]
        id=m.currentPublication.initVideoId
        socketEI(state,id,method)
        checkEI(serveLiveRequest(m.requestClock),"actual current init range GET/HEAD succeeds")
        checkEI(m.activeLease=id and state.assets[nlAssetIndex(state,id)].leases=1,"actual lease remains after serving until socket close")
        checkEI(m.io[2].ToAsciiString().Left(28).InStr("206 Partial Content")>=0,"actual bounded range response")
        closeLiveConnection()
        checkEI(state.assets[nlAssetIndex(state,id)].leases=0 and m.activeBody=invalid,"actual request close releases Core body")
    end for
    closeEI(state)
end sub

sub laterHttpEI()
    caseEI("actual-mixed-later-init-http")
    state=preparedEI()
    feedEI(state,"playlist",playlistEI(10,4),3000&)
    drainEI(state,3000&)
    admitEI(state,3000&)
    for each track in ["video","audio"]
        id=m.currentPublication.segments[2].initVideoId
        if track="audio" then id=m.currentPublication.segments[2].initAudioId
        checkEI(id<>m.currentPublication.initVideoId and id<>m.currentPublication.initAudioId,"HTTP target is a later mixed-epoch init")
        for each method in ["GET","HEAD"]
            socketEI(state,id,method)
            checkEI(serveLiveRequest(m.requestClock),"actual later mixed init GET/HEAD range request succeeds")
            checkEI(m.activeLease=id and state.assets[nlAssetIndex(state,id)].leases=1,"actual later pair remains leased through response")
            if method="GET"
                expected=bytesEI(m.corpus.inits.ad[track])
                actual=m.io[2].Slice(m.io[2].Count()-4,m.io[2].Count())
                checkEI(actual.ToHexString()=expected.Slice(0,4).ToHexString(),"exact requested range bytes from actual later init golden")
            else
                checkEI(m.io[2].ToAsciiString().Right(4)=Chr(13)+Chr(10)+Chr(13)+Chr(10),"HEAD sends only headers for later init")
            end if
            closeLiveConnection()
            checkEI(m.result.cleanupOk and state.assets[nlAssetIndex(state,id)].leases=0,"actual later init closes before request release")
        end for
    end for
    closeEI(state)
end sub

sub resetEpochEI()
    caseEI("same-map-actual-tfdt-reset")
    state=preparedEI()
    calls=m.decodeCount
    oldIds=FormatJson(state.initIds)
    feedEI(state,"playlist",playlistEI(10,4,"pts"),3000&)
    checkEI(state.phase="segment" and state.localEpoch=1& and state.pendingWindow=invalid,"same-map actual source discontinuity preserves approved pair")
    feedEI(state,"segment",bytesEI(m.corpus.ptsMedia.input),3000&)
    nativeLiveAdvance(state,3000&)
    nativeLiveAdvance(state,3000&)
    admitEI(state,3000&)
    checkEI(m.decodeCount=calls and FormatJson(state.initIds)=oldIds and m.currentPublication.segments[2].epoch=1&,"same-MAP reset requires no invented approval or initialization")
    for each pair in [[m.currentPublication.segments[2].videoId,m.corpus.ptsMedia.video],[m.currentPublication.segments[2].audioId,m.corpus.ptsMedia.audio]]
        body=nativeLiveAcquire(state,pair[0])
        checkEI(nlBodyDigest(body.data)=pair[1].sha256 and LCase(body.data.ToHexString())=pair[1].hex,"unchanged actual reset fragment TFDT bytes")
        nativeLiveRelease(state,pair[0])
        m.goldens+=1
    end for
    closeEI(state)
end sub

sub refusalEI()
    caseEI("incompatible-init-and-native-decision-before-feed")
    for each mode in ["entry","decoder","stop"]
        state=preparedEI()
        oldMaster=FormatJson(m.config.metadata)
        oldPublication=FormatJson(m.currentPublication)
        oldPhase=state.phase
        feedEI(state,"playlist",playlistEI(10,4),3000&)
        oldIds=FormatJson(state.initIds)
        oldPairs=state.initPairCount
        m.liveState=state
        input=bytesEI(m.corpus.inits.ad.input)
        ' Profile/level changes are allowed; a sample-entry family change is not.
        if mode="entry" then input.FromHexString(m.corpus.inits.ad.input.hex.Replace("61766331","61766333"))
        if mode="decoder" then m.decoderAllowed=false
        if mode="stop" then m.stopDuringDecode=true
        refused=false
        reason=""
        try
            accepted=rokuDemuxFeedInput(state,"init",input,3000&)
            if mode="stop" then refused=not accepted
        catch error
            reason=error.message
            if mode="entry" then refused=reason="native-live: actual init master incompatible"
            if mode="decoder" then refused=reason="native-live: actual init decoder rejected"
        end try
        checkEI(refused,"incompatible or stopped init is refused before real Core staging "+mode)
        checkEI(state.phase="init-rotation" and state.input=invalid and state.initPairCount=oldPairs and FormatJson(state.initIds)=oldIds,"refused gate cannot replace real Core identity "+mode)
        checkEI(FormatJson(m.config.metadata)=oldMaster and FormatJson(m.currentPublication)=oldPublication,"refused gate preserves immutable master and Server publication "+mode)
        closeEI(state)
    end for
    ' Ads and encoder restarts change profile/level; the decoder-approved
    ' init is staged instead of stopping playback.
    state=preparedEI()
    oldMaster=FormatJson(m.config.metadata)
    feedEI(state,"playlist",playlistEI(10,4),3000&)
    input=CreateObject("roByteArray")
    input.FromHexString(m.corpus.incompatibleProfile)
    m.liveState=state
    checkEI(rokuDemuxFeedInput(state,"init",input,3000&),"decoder-approved changed-profile init is accepted")
    checkEI(state.phase="init-video" and state.pendingWindow<>invalid,"changed-profile init is staged for the new epoch")
    checkEI(FormatJson(m.config.metadata)=oldMaster,"accepted later init leaves the advertised master unchanged")
    closeEI(state)
end sub

sub policyEI()
    caseEI("typed-policy-default-off-and-malformed-refusals")
    state=preparedEI(false)
    checkEI(not m.currentPublication.DoesExist("version") and not state.sourceTransitions,"actual default path remains v1")
    refused=false
    try
        feedEI(state,"playlist",playlistEI(13,3),3000&)
    catch error
        refused=error.message="native-live: selected discontinuity change unsupported"
    end try
    checkEI(refused,"default-off actual Core refuses mixed source epoch")
    closeEI(state)
    for each flag in [invalid,0,1,"true",[],{}]
        eiReset()
        m.top.enableSourceTransitions=flag
        checkEI(not prepareRokuDemuxInput() and m.liveState=invalid and m.result.reason="invalid_source_transition_policy","malformed Task policy refuses before actual provider creation")
    end for
    eiReset()
    m.top.Delete("enableSourceTransitions")
    m.clockValues[0] = 0&
    checkEI(prepareRokuDemuxInput() and liveSteadyOptions().Count()=2,"truly absent harness Task flag defaults false")
    options=liveSteadyOptions()
    state=nativeLiveCreate(m.config.trustedMediaUrl,0&,0,m.config.approvedOrigins,true,m.cacheBudgetBytes,options)
    checkEI(not state.sourceTransitions,"actual absent default creates unchanged Core path")
    closeEI(state)
end sub

sub cleanupEI()
    caseEI("actual-send-failure-stop-and-transfer-cancel-cleanup")
    for each mode in ["failure","stop"]
        state=preparedEI()
        id=m.currentPublication.initVideoId
        socketEI(state,id)
        response=prepareLiveResponse({track:"",assetId:id,head:false,range:""})
        checkEI(response<>invalid,"actual advertised asset response exists")
    m.activeBody=response.data
        if mode="failure" then m.io[5][0]=true
        if mode="stop" then m.top.stopRequested=true
        checkEI(not sendLiveSpan(m.activeBody,0,4,m.requestClock),"actual stopped or failed socket cannot send body")
        closeLiveConnection()
        checkEI(state.assets[nlAssetIndex(state,id)].leases=0 and m.activeBody=invalid and m.activeLease="" and m.connection=invalid,"actual failure cleanup releases real Core request lease")
        closeEI(state)
    end for
    createEI()
    state=m.liveState
    state.op={transfer:{events:m.events,AsyncCancel:eiCancel}}
    state.ownInputFile=false
    m.top.stopRequested=true
    closeEI(state)
    checkEI(m.events[m.events.Count()-1]="transfer-cancel","actual Fetch close cancels retained transfer")
end sub

sub main()
    m.assertions=0
    m.cases=[]
    m.goldens=0
    m.pairs=0
    m.manifests=0
    m.admissions=0
    m.corpus=ParseJson(ReadAsciiFile("pkg:/corpus.json"))
    try
        transitionEI()
        laterHttpEI()
        resetEpochEI()
        refusalEI()
        policyEI()
        cleanupEI()
    catch error
        print "STITCH_EPOCH_INTEGRATION_FAIL: __MARKER__ ";error.message
        return
    end try
    print "STITCH_EPOCH_INTEGRATION_PASS: __MARKER__ ";FormatJson({assertions:m.assertions,cases:m.cases.Count(),goldens:m.goldens,pairs:m.pairs,manifests:m.manifests,admissions:m.admissions})
end sub
