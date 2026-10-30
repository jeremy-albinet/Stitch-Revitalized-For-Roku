sub checkAd(ok as boolean, message as string)
    if not ok then throw "ad-countdown-fixture: " + message
    m.assertions += 1
end sub

sub parserAd(corpus as object)
    cue = twitchAdCountdownRange(corpus.single)
    checkAd(cue <> invalid and cue.startUs = corpus.startUs and cue.durationUs = 30239000&, "exact observed fractional ad duration")
    checkAd(cue.Count() = 5 and cue.podCount = 4& and cue.podPosition = 0&, "pod count is count not seconds")
    checkAd(FormatJson(cue).InStr("synthetic-discard") < 0 and not cue.DoesExist("ID") and not cue.DoesExist("CLASS"), "private IDs tracking and unknown values never retained")
    checkAd(twitchAdCountdownRange(corpus.unknown) = invalid and twitchAdCountdownRanges(corpus.unknown).Count() = 0, "unknown metadata class never creates ad")
    checkAd(twitchAdCountdownRange(123) = invalid and twitchAdCountdownRanges(invalid) = invalid, "bounded input types")
    for each item in corpus.bad
        checkAd(twitchAdCountdownRange(item.text) = invalid, "malformed cue refusal " + item.name)
        checkAd(twitchAdCountdownRanges(item.text) = invalid, "malformed batch refusal " + item.name)
    end for
    cues = twitchAdCountdownRanges(corpus.pod)
    checkAd(cues <> invalid and cues.Count() = 4, "observed 1ms rounding overlap accepted")
    sorted = twitchAdCountdownRanges(corpus.reversedPod)
    checkAd(sorted <> invalid and sorted.Count() = 4 and sorted[0].startUs = corpus.startUs, "bounded sorted cues and CRLF accepted")
    print "STITCH_AD_CUES: " + FormatJson(sorted)
    checkAd(twitchAdCountdownRanges(corpus.pod + Chr(10) + corpus.single).Count() = 4, "exact duplicate discarded")
    for each item in corpus.overlapBad
        checkAd(twitchAdCountdownRanges(item.text) = invalid, "ambiguous overlap refusal " + item.name)
    end for
    for each text in [corpus.plain, corpus.missingCount, corpus.missingPosition]
        plain = twitchAdCountdownRange(text)
        checkAd(plain <> invalid and plain.durationUs = 30239000& and plain.podCount = 0& and plain.podPosition = -1&, "missing optional ordinal permits exact individual duration")
    end for
    checkAd(twitchAdCountdownRanges(corpus.incompletePod).Count() = 3, "incomplete five-ad pod keeps exact individual cues")
    checkAd(twitchAdCountdownRange(corpus.attributeLimit) <> invalid and twitchAdCountdownRange(corpus.attributeOver) = invalid, "128 attribute ceiling")
    checkAd(twitchAdCountdownRanges(corpus.cuesLimit).Count() = 32 and twitchAdCountdownRanges(corpus.cuesOver) = invalid, "32 retained cue ceiling")
    checkAd(twitchAdCountdownRanges(corpus.rangesLimit).Count() = 0 and twitchAdCountdownRanges(corpus.rangesOver) = invalid, "128 source range work ceiling")
    body = corpus.single + Chr(10) + "#"
    body += String(262144 - body.Len(), "x")
    checkAd(twitchAdCountdownRanges(body).Count() = 1 and twitchAdCountdownRanges(body + "x") = invalid, "262144 text ceiling")
    checkAd(twitchAdCountdownRanges(String(8191, Chr(10))).Count() = 0 and twitchAdCountdownRanges(String(8192, Chr(10))) = invalid, "8192 bounded source line work")
    checkAd(tadUtcUs("2000-02-29T00:00:00Z") = 951782400000000& and tadUtcUs("2100-01-01T00:00:00Z") = invalid, "actual leap calendar and finite supported epoch")
end sub

sub viewAd(corpus as object)
    state = twitchAdCountdownBegin("synthetic-owner-1")
    checkAd(state <> invalid and twitchAdCountdownBegin("unsafe owner") = invalid, "bounded owner identity")
    checkAd(twitchAdCountdownSet(state, "synthetic-owner-1", corpus.pod), "actual cue ingestion")
    view = twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs, "playing")
    checkAd(view.visible and view.remainingSeconds = 31 and view.number = 1 and view.count = 4, "per-ad ceiling and one-based valid ordinal")
    for each playback in ["paused", "buffering", "playing"]
        held = twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs + 10239000&, playback)
        checkAd(held.visible and held.remainingSeconds = 20 and held.number = 1 and state.cues.Count() = 4, "presented clock remains truthful through " + playback)
    end for
    checkAd(not twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs - 1&, "playing").visible, "not before actual ad start")
    atNext = twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs + 30238000&, "playing")
    checkAd(atNext.visible and atNext.number = 2 and atNext.remainingSeconds = 16, "latest started cue owns actual rounding boundary")
    atEnd = twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs + 76110000&, "playing")
    checkAd(not atEnd.visible, "half-open end hides exactly at ad finish")
    for each playback in ["none", "error", "stopped", "stopping", "finished", "unknown"]
        checkAd(not twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs, playback).visible, "terminal unknown state hidden " + playback)
    end for
    checkAd(not twitchAdCountdownView(state, "stale-owner", corpus.startUs, "playing").visible and not twitchAdCountdownSet(state, "stale-owner", corpus.single), "stale owner cannot drive or replace badge")
    checkAd(not twitchAdCountdownView(state, "synthetic-owner-1", invalid, "playing").visible and not twitchAdCountdownView(state, "synthetic-owner-1", "fake", "playing").visible, "unknown clock never guessed")
    checkAd(twitchAdCountdownSet(state, "synthetic-owner-1", corpus.incompletePod), "partial pod accepted without synthesized break duration")
    third = twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs + 45462000&, "playing")
    checkAd(third.visible and third.count = 5 and third.number = 3 and third.remainingSeconds = 16, "partial pod displays only actual current ad countdown")
    checkAd(not twitchAdCountdownSet(state, "synthetic-owner-1", corpus.bad[0].text) and state.cues.Count() = 0, "invalid refresh clears stale timing")
    checkAd(not twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs, "playing").visible, "failed refresh cannot leave stale ad")
    checkAd(twitchAdCountdownSet(state, "synthetic-owner-1", corpus.plain), "unordinalled ad accepted")
    plain = twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs, "playing")
    checkAd(plain.visible and plain.count = 0 and plain.number = 0 and plain.remainingSeconds = 31, "unknown optional count never fabricated")
    checkAd(not twitchAdCountdownEnd(state, "stale-owner") and twitchAdCountdownEnd(state, "synthetic-owner-1") and state.cues.Count() = 0 and state.closed and state.owner = "", "dispose clears owned cues and owner")
    checkAd(not twitchAdCountdownSet(state, "synthetic-owner-1", corpus.pod) and not twitchAdCountdownView(state, "synthetic-owner-1", corpus.startUs, "playing").visible, "disposed source cannot resurrect badge")
end sub

sub clockAd(corpus as object)
    utc = twitchAdCountdownClock({epoch: 1, video: corpus.startUs / 1000000#, audio: 0, clip_id: 1})
    checkAd(utc <> invalid and utc = corpus.startUs, "documented rendered UTC clock converted exactly")
    checkAd(twitchAdCountdownClock({epoch: 0, video: 10#, audio: 10#}) = invalid, "relative clock cannot masquerade as UTC")
    for each clock in [{epoch: 2, video: 10#}, {epoch: 1.0, video: 10#}, {epoch: 1, video: -1#}, {epoch: 1, video: "10"}, {epoch: 1}, {epoch: 1, video: 4102444801#}, {epoch: 1, video: 10.5}, invalid]
        checkAd(twitchAdCountdownClock(clock) = invalid, "malformed unknown clock refused")
    end for
end sub

sub main()
    m.assertions = 0
    try
        corpus = ParseJson(ReadAsciiFile("pkg:/corpus.json"))
        mode = "__MODE__"
        if mode = "parser" then parserAd(corpus)
        if mode = "view" then viewAd(corpus)
        if mode = "clock" then clockAd(corpus)
        print "STITCH_AD_CASE: " + mode
        print "STITCH_AD_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 0})
    catch error
        print "STITCH_AD_FAIL: __MARKER__ " + error.message
        print "STITCH_AD_PASS: __MARKER__ " + FormatJson({assertions: m.assertions, failures: 1})
    end try
end sub
