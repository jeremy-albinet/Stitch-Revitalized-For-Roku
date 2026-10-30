' In-memory account/registry boundary: never reads or writes a Roku registry.
function get_setting(key as string, fallback = invalid) as dynamic
    if key = "active_user"
        if m.global.fixtureSigned and m.global.hasField("fixtureUser") then return m.global.fixtureUser
        if m.global.fixtureSigned then return "fixture-user"
        return "$default$"
    end if
    return fallback
end function

function get_user_setting(key as string, fallback = invalid) as dynamic
    if key = "device_code" then return "fixture-device"
    if key = "login" then return "fixture-user"
    if key = "profile_image_url" and m.global.hasField("fixtureAvatar") then return m.global.fixtureAvatar
    if key = "display_name" and m.global.fixtureSigned then return "Fixture Viewer"
    if m.fixtureRegistry = invalid then m.fixtureRegistry = {}
    if m.fixtureRegistry.doesExist(key) then return m.fixtureRegistry[key]
    return fallback
end function

sub set_user_setting(key as string, value as dynamic)
    if m.fixtureRegistry = invalid then m.fixtureRegistry = {}
    m.fixtureRegistry[key] = value
end sub

sub set_setting(key as string, value as dynamic)
end sub
