' Explicit offline boundaries. No transport, credential or registry access.
function TwitchGraphQLRequest(params as object) as object
    return { data: { user: { stream: { playbackAccessToken: { value: "fixture/+?=&", signature: "fixture-sig" } } } } }
end function

function getTwitchSupportedCodecs(device as object) as string
    return "h264"
end function

function isTwitchVariantSupported(variant as object, device as object) as boolean
    return variant["VIDEO"] <> "reject-decoder"
end function

function get_user_setting(key as string, defaultValue = "" as dynamic) as dynamic
    if key = "proxy.url" then return m.top.fixtureProxy
    if key = "playback.video.quality" then return m.top.fixturePreference
    return defaultValue
end function

function HttpRequest(options as object) as object
    return {
        fixtureHost: m.top,
        requestOptions: options,
        Send: function() as dynamic
            text = ""
            status = 200
            if m.requestOptions.url.Right(7) = "/health"
                if m.fixtureHost.fixtureHealthFailure = "timeout" then return invalid
                health = { status: "ok", version: "0.3.0", selected_master_version: 1 }
                if m.fixtureHost.fixtureLegacyProxy then health = { status: "ok", version: "0.1.0" }
                text = FormatJSON(health)
                if m.fixtureHost.fixtureHealthFailure = "http" then status = 503
                if m.fixtureHost.fixtureHealthFailure = "json" then text = "not JSON"
            else if m.requestOptions.url.InStr("https://usher.ttvnw.net/") = 0
                m.fixtureHost.fixtureUsherUrl = m.requestOptions.url
                text = m.fixtureHost.fixtureMaster
            else
                m.fixtureHost.fixtureProbes++
                if m.requestOptions.url.InStr("unknown-transport") >= 0
                    text = "<html>offline</html>"
                else if m.requestOptions.url.InStr("muxed") >= 0
                    text = "#EXTM3U" + Chr(10) + "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34)
                else
                    text = "#EXTM3U" + Chr(10) + "#EXTINF:2," + Chr(10) + "segment.ts"
                end if
            end if
            return {
                body: text,
                status: status,
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
    print "STITCH_SELECTION_FAIL: unexpected task exception in " + context; " "; FormatJSON(error)
    if m.top <> invalid then m.top.fixtureFailures++
end sub
