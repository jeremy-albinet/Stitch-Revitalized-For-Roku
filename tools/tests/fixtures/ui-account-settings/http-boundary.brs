' Test-only HttpRequest interface. No roUrlTransfer or external request occurs.
function HttpRequest(params = invalid as dynamic) as object
    m.global.fixtureHttpRequest = params
    input = m.global.fixtureHttpInput
    return {
        input: input,
        send: function() as dynamic
            if m.input.noEvent then return invalid
            return {
                status: m.input.status,
                body: m.input.body,
                reason: m.input.reason,
                getResponseCode: function() as integer
                    return m.status
                end function,
                getString: function() as dynamic
                    return m.body
                end function,
                getFailureReason: function() as dynamic
                    return m.reason
                end function
            }
        end function
    }
end function
