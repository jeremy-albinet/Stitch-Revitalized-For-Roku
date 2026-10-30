' Explicit GraphQL/HTTP/decoder boundaries. No registry or network operations.
function TwitchGraphQLRequest(request as object) as object
    m.top.graphqlCount++
    token = { value: "fixture-public-token", signature: "fixture-public-signature" }
    return { data: { video: { playbackAccessToken: token }, user: { stream: { playbackAccessToken: token } } } }
end function

function HttpRequest(options as object) as object
    requests = m.top.httpRequests
    if requests = invalid then requests = []
    requests.Push({ url: options.url, timeout: options.timeout, method: options.method })
    m.top.httpRequests = requests
    payload = m.top.fixturePlaylist
    status = 200
    if options.url.Right(7) = "/health"
        payload = FormatJSON({ status: "ok", version: "0.3.0", selected_master_version: 1 })
    else if options.url.Left(24) = "https://usher.ttvnw.net/"
        payload = m.top.fixtureMaster
        status = m.top.fixtureMasterStatus
    end if
    response = {
        payload: payload, status: status,
        GetString: function() as string
            return m.payload
        end function,
        GetResponseCode: function() as integer
            return m.status
        end function
    }
    return {
        response: response,
        Send: function() as object
            return m.response
        end function
    }
end function

function fixtureDecoder() as object
    return {
        CanDecodeVideo: function(format as object) as object
            return { result: true }
        end function
    }
end function
