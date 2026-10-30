' Isolate navigation from registry/account/network state.
function get_setting(key as string, fallback = invalid) as dynamic
    return fallback
end function

function get_user_setting(key as string, fallback = invalid) as dynamic
    if key = "device_code" then return "offline-device"
    return fallback
end function
