' Offline inputs for the actual getClipUrlViaGraphQL function. Only the
' TwitchGraphQLRequest network boundary is canned; no selection logic is copied.
' No registry, HTTP transport, playback device or media decoder is exercised.

sub main()
    m.assertions = 0
    m.failures = 0
    m.cases = 0
    m.requests = 0

    expectClip(clipResponse([
        { quality: "2160", sourceURL: "https://example.test/mixed-2160.mp4" }
        { quality: "720", sourceURL: "https://example.test/mixed-720.mp4" }
        { quality: "1440", sourceURL: "https://example.test/mixed-1440.mp4" }
        { quality: "1080", sourceURL: "https://example.test/mixed-1080.mp4" }
        { quality: "360", sourceURL: "https://example.test/mixed-360.mp4" }
    ]), "https://example.test/mixed-1080.mp4", "shuffled mixed ladder prefers 1080")

    expectClip(clipResponse([
        { quality: "360", sourceURL: "https://example.test/reordered-360.mp4" }
        { quality: "1080", sourceURL: "https://example.test/reordered-1080.mp4" }
        { quality: "1440", sourceURL: "https://example.test/reordered-1440.mp4" }
        { quality: "720", sourceURL: "https://example.test/reordered-720.mp4" }
        { quality: "2160", sourceURL: "https://example.test/reordered-2160.mp4" }
    ]), "https://example.test/reordered-1080.mp4", "mixed ladder does not depend on ordering")

    expectClip(clipResponse([
        { quality: "720", sourceURL: "https://example.test/capped-720.mp4" }
        { quality: "1440", sourceURL: "https://example.test/capped-1440.mp4" }
        { quality: "1080" }
        { quality: "2160", sourceURL: "https://example.test/capped-2160.mp4" }
        { quality: "360", sourceURL: "https://example.test/capped-360.mp4" }
    ]), "https://example.test/capped-720.mp4", "best URL-bearing quality below cap wins")

    expectClip(clipResponse([
        { quality: "2160", sourceURL: "https://example.test/high-first-2160.mp4" }
        { quality: "1440", sourceURL: "https://example.test/high-first-1440.mp4" }
    ]), "https://example.test/high-first-1440.mp4", "all above 1080 keeps lowest offered high-first")

    expectClip(clipResponse([
        { quality: "1440", sourceURL: "https://example.test/low-first-1440.mp4" }
        { quality: "2160", sourceURL: "https://example.test/low-first-2160.mp4" }
    ]), "https://example.test/low-first-1440.mp4", "all above 1080 keeps lowest offered low-first")

    expectClip(clipResponse([
        { quality: "2160", sourceURL: "https://example.test/available-2160.mp4" }
        { quality: "1440" }
        { quality: "1200", sourceURL: "" }
        { quality: "1800", sourceURL: "https://example.test/available-1800.mp4" }
    ]), "https://example.test/available-1800.mp4", "lowest fallback must have a nonempty source URL")

    expectClip(clipResponse([
        { quality: "1440", sourceURL: "https://example.test/single-1440.mp4" }
    ]), "https://example.test/single-1440.mp4", "single 1440 source is retained")

    expectClip(clipResponse([]), invalid, "empty ladder has no URL")
    expectClip({ data: { clip: {} } }, invalid, "missing ladder has no URL")
    expectClip(clipResponse([
        { quality: "1080" }
        { quality: "720", sourceURL: "" }
        { quality: "1440", sourceURL: invalid }
    ]), invalid, "missing and empty sources have no URL")

    token = { value: "a b/+?=&", signature: "s/+?=&" }
    expectClip(clipResponse([
        { quality: "1080", sourceURL: "https://example.test/token.mp4" }
    ], token), "https://example.test/token.mp4?token=a%20b%2F%2B%3F%3D%26&sig=s%2F%2B%3F%3D%26", "token uses question mark and URI encoding")

    expectClip(clipResponse([
        { quality: "1440", sourceURL: "https://example.test/token.mp4?existing=keep%2Fthis" }
        { quality: "2160", sourceURL: "https://example.test/unselected.mp4" }
    ], token), "https://example.test/token.mp4?existing=keep%2Fthis&token=a%20b%2F%2B%3F%3D%26&sig=s%2F%2B%3F%3D%26", "fallback preserves existing query and uses ampersand")

    expectClip(clipResponse([
        { quality: "720", sourceURL: "https://example.test/plain.mp4?existing=keep%2Fthis" }
    ]), "https://example.test/plain.mp4?existing=keep%2Fthis", "absent token leaves offered URL unchanged")

    expectClip(clipResponse([]), invalid, "selection state does not leak into a later empty ladder")
    expectClip(clipResponse([
        { quality: "2160", sourceURL: "https://example.test/repeated-2160.mp4" }
        { quality: "1440", sourceURL: "https://example.test/repeated-1440.mp4" }
    ]), "https://example.test/repeated-1440.mp4", "selection state does not leak into a later fallback")
    expectClip(clipResponse([
        { quality: "360", sourceURL: "https://example.test/repeated-360.mp4" }
        { quality: "720", sourceURL: "https://example.test/repeated-720.mp4" }
        { quality: "2160", sourceURL: "https://example.test/repeated-high.mp4" }
    ]), "https://example.test/repeated-720.mp4", "selection state does not leak into a later capped ladder")

    check(m.requests = m.cases, "every clip call reached the canned query boundary exactly once")
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions, "; m.cases; " cases"
    else
        print "STITCH_CLIP_FAIL:"; m.failures; " failures, "; m.cases; " cases"
    end if
end sub

function clipResponse(qualities as object, token = invalid as dynamic) as object
    return { data: { clip: { videoQualities: qualities, playbackAccessToken: token } } }
end function

sub expectClip(response as dynamic, expected as dynamic, label as string)
    m.cases += 1
    m.fixtureResponse = response
    m.expectedSlug = "offline-clip-" + m.cases.toStr()
    actual = getClipUrlViaGraphQL(m.expectedSlug)
    if expected = invalid
        check(actual = invalid, label)
    else if actual = invalid
        check(false, label + ": returned invalid")
    else
        check(actual = expected, label + ": " + actual)
    end if
end sub

' Explicit canned network boundary: validate the actual query function's
' request contract and return the next GraphQL response without any I/O.
function TwitchGraphQLRequest(params as object) as dynamic
    m.requests += 1
    check(params.variables.slug = m.expectedSlug, "query passes the current slug in variables")
    check(params.query.inStr("clip(slug: $slug)") >= 0, "query requests the clip by slug")
    check(params.query.inStr("playbackAccessToken") >= 0, "query requests the playback token")
    check(params.query.inStr("videoQualities { frameRate quality sourceURL }") >= 0, "query requests the offered quality source URLs")
    return m.fixtureResponse
end function

sub check(condition as boolean, label as string)
    m.assertions += 1
    if not condition
        m.failures += 1
        print "STITCH_CLIP_FAIL:" + label
    end if
end sub
