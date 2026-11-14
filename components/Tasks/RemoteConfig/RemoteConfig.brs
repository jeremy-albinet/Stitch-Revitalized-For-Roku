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
            ' HttpRequest sends while retries > 0: 1 means a single attempt
            retries: 1
        }).send()
        if event <> invalid and event.getResponseCode() = 200
            cfg = parseRemoteConfig(event.getString())
        end if
    catch e
        cfg = invalid
    end try

    if cfg = invalid
        ? "[RemoteConfig] not loaded, using defaults"
        m.top.result = { ok: false, config: {} }
    else
        ? "[RemoteConfig] loaded: "; FormatJson(cfg)
        m.top.result = { ok: true, config: cfg }
    end if
end sub
