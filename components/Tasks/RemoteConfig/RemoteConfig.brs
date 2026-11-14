sub init()
    m.top.functionName = "fetchConfig"
end sub

sub fetchConfig()
    cfg = invalid
    try
        event = HttpRequest({
            url: "https://raw.githubusercontent.com/jeremy-albinet/Stitch-Revitalized-For-Roku/remote-config/config.json",
            method: "GET",
            headers: { "Accept": "application/json" },
            timeout: 3000,
            retries: 0
        }).send()
        if event <> invalid and event.getResponseCode() = 200
            cfg = parseRemoteConfig(event.getString())
        end if
    catch e
        cfg = invalid
    end try

    if cfg = invalid
        m.top.result = { ok: false, config: {} }
    else
        m.top.result = { ok: true, config: cfg }
    end if
end sub
