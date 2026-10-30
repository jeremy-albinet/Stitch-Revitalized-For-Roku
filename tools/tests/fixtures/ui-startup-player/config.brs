' In-memory registry boundary. Values live on the global node and are read and
' replaced as a whole AA (no chained writes); no Roku registry is touched.
function fixtureRegistry() as object
    registry = m.global.fixtureRegistry
    if registry = invalid then registry = {}
    return registry
end function

function get_setting(key as string, fallback = invalid) as dynamic
    registry = fixtureRegistry()
    if registry.doesExist("app/" + key) then return registry["app/" + key]
    return fallback
end function

sub set_setting(key as string, value as dynamic)
    registry = fixtureRegistry()
    registry["app/" + key] = value
    m.global.fixtureRegistry = registry
end sub

function get_user_setting(key as string, fallback = invalid) as dynamic
    registry = fixtureRegistry()
    if registry.doesExist(key) then return registry[key]
    return fallback
end function

sub set_user_setting(key as string, value as dynamic)
    registry = fixtureRegistry()
    registry[key] = value
    m.global.fixtureRegistry = registry
end sub

' Startup must never sign anyone out; a call is recorded so assertions see it.
sub signOutAccount()
    set_setting("fixtureSignedOut", "true")
end sub
