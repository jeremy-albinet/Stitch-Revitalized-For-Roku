' Offline only: no registry, authentication or media/network IO.
function TwitchGraphQLRequest(params as object) as object
    m.top.fixtureQuery = params
    token = { value: "canned-playback-token/+?=&", signature: "canned-playback-signature" }
    if params.query.InStr("VodPlayerWrapper") >= 0 then return { data: { video: { playbackAccessToken: token } } }
    if params.query.InStr("ClipAccessToken") >= 0
        return { data: { clip: { playbackAccessToken: token, videoQualities: [{ frameRate: 30, quality: "480", sourceURL: "https://clips-media-assets2.twitch.tv/canned.mp4" }] } } }
    end if
    return { data: { user: { stream: { playbackAccessToken: token, createdAt: "2026-10-27T18:00:00Z", game: { name: "fresh-category", displayName: "Fresh category", boxArtURL: "https://static-cdn.jtvnw.net/ttv-boxart/fixture-{width}x{height}.jpg" } } } } }
end function

function getTwitchSupportedCodecs(device as object) as string
    return "h264,h265"
end function

function isTwitchVariantSupported(variant as object, device as object) as boolean
    m.top.fixtureApprovals++
    return variant["VIDEO"] <> "reject-decoder"
end function

function get_user_setting(key as string, defaultValue = "" as dynamic) as dynamic
    if key = "proxy.url" then return m.top.fixtureProxy
    if key = "playback.video.quality" then return m.top.fixturePreference
    if key = "access_token" then return "OAUTH_NEVER_EXPORT"
    return defaultValue
end function

function HttpRequest(options as object) as object
    return {
        fixtureHost: m.top, requestOptions: options,
        Send: function() as object
            status = 200
            if m.requestOptions.url.Right(7) = "/health"
                body = FormatJSON({ status: "ok", version: "0.3.0", selected_master_version: 1 })
            else if m.requestOptions.url.InStr("https://usher.ttvnw.net/") = 0
                m.fixtureHost.fixtureUsher = m.requestOptions
                body = m.fixtureHost.fixtureMaster
            else
                m.fixtureHost.fixtureProbes++
                m.fixtureHost.fixtureProbeOptions = m.requestOptions
                sample = m.fixtureHost.fixtureBodies[m.requestOptions.url]
                body = "<html>missing canned transport</html>"
                if sample <> invalid then body = sample
            end if
            return {
                body: body, status: status,
                GetResponseCode: function() as integer
                    return m.status
                end function,
                GetString: function() as string
                    return m.body
                end function
            }
        end function
    }
end function

sub captureException(error as dynamic, context as string)
    m.top.fixtureFailures++
    print "STITCH_ROKU_DESCRIPTOR_FAIL: unexpected task exception"
end sub
