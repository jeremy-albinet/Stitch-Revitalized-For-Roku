' Remote kill switch helpers. See "Remote kill switch" in AGENTS.md.

' Validates the raw config.json text. Returns an AA holding only the known
' fields that have the right type, or invalid when the text is not a JSON
' object. Unknown fields and wrong-typed fields are dropped, so remoteFlag()
' falls back to the caller's default for them.
function parseRemoteConfig(text as dynamic) as dynamic
    if type(text) <> "String" and type(text) <> "roString" then return invalid
    json = invalid
    try
        json = ParseJson(text)
    catch e
        json = invalid
    end try
    if type(json) <> "roAssociativeArray" then return invalid

    cfg = {}
    for each name in ["adFix", "builtinSplitter"]
        if type(json[name]) = "Boolean" or type(json[name]) = "roBoolean" then cfg[name] = json[name]
    end for
    if type(json.message) = "String" or type(json.message) = "roString" then cfg.message = json.message
    valueType = type(json.version)
    if valueType = "Integer" or valueType = "roInt" or valueType = "LongInteger" or valueType = "Float" or valueType = "roFloat" or valueType = "Double" or valueType = "roDouble"
        cfg.version = json.version
    end if
    return cfg
end function

' Returns the remote value for `name`, or `default` when the config has not
' loaded (yet), failed to load, or does not carry that field.
function remoteFlag(name as string, default as dynamic) as dynamic
    if m.global = invalid then return default
    cfg = m.global.remoteConfig
    if type(cfg) <> "roAssociativeArray" or not cfg.doesExist(name) then return default
    return cfg[name]
end function
