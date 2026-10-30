' Explicit opt-in Task policy; no config file or user setting is read.
function rokuDemuxCacheBudgetValid(value as dynamic) as boolean
    if not loopbackInteger(value) then return false
    return value = 16777216 or value = 25165824 or value = 33554432
end function

function liveQuotaCreate(nowMs as dynamic) as dynamic
    if not loopbackInteger(nowMs) then return invalid
    if nowMs < 0 or nowMs > 4294967235000& then return invalid
    return [nowMs + 0&, 0&, 0&, 0&]
end function

function liveQuotaRefresh(quota as dynamic, nowMs as dynamic) as boolean
    if type(quota) <> "roArray" then return false
    if quota.Count() <> 4 or not loopbackInteger(nowMs) then return false
    for each value in quota
        if not loopbackInteger(value) then return false
        if value < 0 then return false
    end for
    if nowMs < quota[0] or nowMs > 4294967235000& then return false
    if quota[1] > 256 or quota[2] > 134217728 or quota[3] > 12000 then return false
    if nowMs - quota[0] >= 60000&
        quota[0] = nowMs + 0&
        quota[1] = 0&
        quota[2] = 0&
        quota[3] = 0&
    end if
    return true
end function

function liveQuotaFits(quota as dynamic, nowMs as dynamic, requests as dynamic, bytes as dynamic, socketCalls as dynamic) as boolean
    if not liveQuotaRefresh(quota, nowMs) then return false
    if not loopbackInteger(requests) or not loopbackInteger(bytes) or not loopbackInteger(socketCalls) then return false
    if requests < 0 or bytes < 0 or socketCalls < 0 then return false
    return requests <= 256& - quota[1] and bytes <= 134217728& - quota[2] and socketCalls <= 12000& - quota[3]
end function

function liveQuotaCharge(quota as dynamic, nowMs as dynamic, requests as dynamic, bytes as dynamic, socketCalls as dynamic) as boolean
    if not liveQuotaFits(quota, nowMs, requests, bytes, socketCalls) then return false
    quota[1] += requests
    quota[2] += bytes
    quota[3] += socketCalls
    return true
end function

function liveCounterNext(value as dynamic, amount as dynamic) as dynamic
    if not loopbackInteger(value) or not loopbackInteger(amount) then return invalid
    if value < 0 or amount < 0 or value > 9007199254740991& then return invalid
    if amount > 9007199254740991& - value then return invalid
    return value + amount + 0&
end function
