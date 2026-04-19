sub init()
    m.top.functionName = "runCheck"
end sub

sub runCheck()
    proxyUrl = m.top.proxyUrl
    if proxyUrl = invalid or proxyUrl = ""
        m.top.result = { ok: false, reason: "empty", message: "Proxy URL is empty" }
        return
    end if

    scheme = LCase(Left(proxyUrl, 7))
    schemeShort = LCase(Left(proxyUrl, 8))
    if scheme <> "http://" and schemeShort <> "https://"
        m.top.result = { ok: false, reason: "scheme", message: "URL must start with http:// or https://" }
        return
    end if

    healthUrl = proxyUrl
    if healthUrl.right(1) = "/" then healthUrl = healthUrl.left(healthUrl.len() - 1)
    healthUrl = healthUrl + "/health"

    req = HttpRequest({
        url: healthUrl,
        method: "GET",
        headers: { "Accept": "application/json" },
        timeout: 3000,
        retries: 1
    })

    event = req.send()
    if event = invalid
        m.top.result = { ok: false, reason: "unreachable", message: "Could not reach proxy (timeout, DNS, or network error)" }
        return
    end if

    statusCode = event.getResponseCode()
    if statusCode <= 0
        failureReason = event.getFailureReason()
        if failureReason = invalid or failureReason = "" then failureReason = "Network error"
        m.top.result = { ok: false, reason: "network", message: failureReason }
        return
    end if

    if statusCode <> 200
        m.top.result = { ok: false, reason: "http", message: "Proxy returned HTTP " + statusCode.toStr() }
        return
    end if

    body = event.getString()
    if body = invalid or body = ""
        m.top.result = { ok: false, reason: "empty_body", message: "Proxy /health returned an empty body" }
        return
    end if

    parsed = invalid
    try
        parsed = ParseJson(body)
    catch e
        parsed = invalid
    end try

    if parsed = invalid or Type(parsed) <> "roAssociativeArray"
        m.top.result = { ok: false, reason: "bad_body", message: "Proxy /health did not return JSON" }
        return
    end if

    if parsed.status <> "ok"
        m.top.result = { ok: false, reason: "bad_status", message: "Proxy /health status is not 'ok'" }
        return
    end if

    version = parsed.version
    if version = invalid then version = ""
    m.top.result = { ok: true, reason: "ok", message: "Connection successful", version: version }
end sub
