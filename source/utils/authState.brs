' Twitch uses message for device-flow errors; RFC 8628 also defines error.
function getOAuthPollState(status as integer, response as dynamic) as string
    if status <= 0 or status >= 500 then return "network"
    if status = 429 then return "slow_down"
    if getInterface(response, "ifAssociativeArray") = invalid then return "error"
    if status >= 200 and status < 300
        if getInterface(response.access_token, "ifString") <> invalid
            if response.access_token <> "" then return "success"
        end if
        return "error"
    end if
    errorName = response.error
    if getInterface(errorName, "ifString") = invalid then errorName = response.message
    if getInterface(errorName, "ifString") = invalid then return "error"
    errorName = LCase(errorName)
    if errorName = "authorization_pending" then return "pending"
    if errorName = "slow_down" then return "slow_down"
    if errorName = "access_denied" then return "denied"
    if errorName = "expired_token" or errorName = "invalid device code" then return "expired"
    return "error"
end function

function getOAuthValidationState(status as integer, response as dynamic) as string
    if status = 401 then return "invalid"
    if status = 200 and getInterface(response, "ifAssociativeArray") <> invalid
        expiresType = type(response.expires_in)
        if expiresType = "Integer" or expiresType = "roInt" or expiresType = "roInteger" or expiresType = "LongInteger" or expiresType = "roLongInteger"
            ' Twitch reports 0 for tokens that never expire, which this client's
            ' device sign-in issues; an expired token is answered with 401.
            if response.expires_in >= 0 then return "valid"
        end if
    end if
    return "indeterminate"
end function
