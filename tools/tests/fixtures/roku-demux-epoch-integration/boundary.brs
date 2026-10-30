function eiClock() as dynamic
    return m.values[m.index]
end function

function eiReadable() as boolean
    return true
end function

function eiReceiveCount() as integer
    return m.io[0].Count() - m.io[1]
end function

function eiReceive(data as object, start as integer, amount as integer) as integer
    size = amount
    if size > m.io[0].Count() - m.io[1] then size = m.io[0].Count() - m.io[1]
    for i = 0 to size - 1
        data[start + i] = m.io[0][m.io[1] + i]
    end for
    m.io[1] += size
    return size
end function

function eiWritable() as boolean
    return true
end function

function eiSocketOk() as boolean
    return not m.io[5][0]
end function

sub eiNotify(value as boolean)
end sub

sub eiSocketClose()
    if m.io[6] <> ""
        acquired = false
        for each asset in m.io[4]
            if asset.id = m.io[6] and asset.leases > 0 then acquired = true
        end for
        if not acquired then throw "integration-socket: socket closes before actual Core release"
    end if
    m.io[3].Push("socket-close")
end sub

sub eiObserve(field as string, port as object)
    m.observers.Push("observe:" + field)
end sub

sub eiUnobserve(field as string)
    m.observers.Push("unobserve:" + field)
end sub

function isTwitchVariantSupported(variant as object, device = invalid as dynamic) as boolean
    m.decodeCount += 1
    m.events.Push("decoder")
    if m.stopDuringDecode then m.top.stopRequested = true
    return m.decoderAllowed
end function

' Only socket I/O and native device decision are substituted. No Core/Fetch/
' Protocol/initialization gate/Server production function is replaced.
function eiSend(data as object, start as integer, amount as integer) as integer
    if m.io[5][0] then return -1
    if m.io[6] <> ""
        acquired = false
        for each asset in m.io[4]
            if asset.id = m.io[6] and asset.leases > 0 then acquired = true
        end for
        if not acquired then throw "integration-socket: actual Core body remains leased through send"
    end if
    m.io[3].Push("send")
    for i = 0 to amount - 1
        m.io[2].Push(data[start + i])
    end for
    return amount
end function

function eiCancel() as boolean
    m.events.Push("transfer-cancel")
    return true
end function
