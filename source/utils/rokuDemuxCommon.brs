function loopbackMarkerValid(marker as string) as boolean
    if marker.Len() < 8 or marker.Len() > 64 then return false
    if marker.InStr("ROOT_REPLACE") >= 0 then return false
    for i = 1 to marker.Len()
        value = Asc(Mid(marker, i, 1))
        allowed = (value >= 48 and value <= 57) or (value >= 65 and value <= 90) or (value >= 97 and value <= 122) or value = 45 or value = 95
        if not allowed then return false
    end for
    return true
end function

function loopbackPortValid(port as integer) as boolean
    return port >= 49152 and port <= 65535
end function

function loopbackExactAddress(text as string, actualPort as integer, expectedPort as integer) as boolean
    if not loopbackPortValid(expectedPort) or actualPort <> expectedPort then return false
    if text = "127.0.0.1" then return true
    if text = "127.0.0.1:" + expectedPort.ToStr() then return true
    if expectedPort > 32767
        signedPort = expectedPort - 65536
        if text = "127.0.0.1:" + signedPort.ToStr() then return true
    end if
    return false
end function

function loopbackReceiveBuffer() as object
    buffer = CreateObject("roByteArray")
    for i = 0 to 255
        buffer.Push(0)
    end for
    return buffer
end function

sub loopbackLog(marker as string, stage as string, fields as object)
    ' Fixed asset IDs, counts, states and numeric errors only; never raw headers.
    print "LOOPBACK_LIVE|"; marker; "|"; stage; "|"; FormatJson(fields)
end sub

function loopbackInteger(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "Integer" or kind = "LongInteger" or kind = "roInt"
end function

function loopbackString(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "String" or kind = "roString"
end function

function loopbackBoolean(value as dynamic) as boolean
    kind = type(value, 3)
    return kind = "Boolean" or kind = "roBoolean"
end function

function loopbackNumber(value as dynamic) as boolean
    kind = type(value, 3)
    return loopbackInteger(value) or kind = "Float" or kind = "Double" or kind = "roFloat" or kind = "roDouble"
end function

function loopbackAssetId(value as dynamic) as boolean
    if not loopbackString(value) then return false
    if value.Len() >= 6 and value.Len() <= 8 and value.Left(5) = "live-"
        digits = value.Right(value.Len() - 5)
        if digits.Left(1) = "0" then return false
        number = loopbackUnsigned(digits, 256)
        if number >= 1 and number <= 256 then return true
    end if
    if value.Len() < 39 or value.Len() > 48 then return false
    if m.loopbackAssetIdRegex = invalid then m.loopbackAssetIdRegex = CreateObject("roRegex", "^live-[0-9a-f]{32}-[1-9][0-9]{0,9}$", "")
    if not m.loopbackAssetIdRegex.IsMatch(value) then return false
    digits = value.Mid(38)
    return loopbackIdentityNumber(digits) >= 1&
end function

function loopbackIdentityNumber(text as string) as longinteger
    if text.Len() < 1 or text.Len() > 10 then return -1&
    number = 0&
    for i = 0 to text.Len() - 1
        digit = Asc(text.Mid(i, 1)) - 48
        if digit < 0 or digit > 9 then return -1&
        if number > (4294967295& - digit) \ 10& then return -1&
        number = number * 10& + digit
    end for
    return number
end function

function loopbackSteadySessionIdValid(value as dynamic) as boolean
    if not loopbackString(value) then return false
    if m.loopbackSessionIdRegex = invalid then m.loopbackSessionIdRegex = CreateObject("roRegex", "^[0-9a-f]{32}$", "")
    return m.loopbackSessionIdRegex.IsMatch(value)
end function

function loopbackAssetSession(value as dynamic) as string
    if not loopbackAssetId(value) then return ""
    if value.Len() < 39 then return ""
    return value.Mid(5, 32)
end function

function loopbackAvcCodec(value as dynamic) as boolean
    if not loopbackString(value) then return false
    if value.Len() <> 11 or value.Left(5) <> "avc1." then return false
    suffix = UCase(value.Right(6))
    for i = 1 to suffix.Len()
        code = Asc(Mid(suffix, i, 1))
        if (code < 48 or code > 57) and (code < 65 or code > 70) then return false
    end for
    return true
end function

function loopbackUnsigned(text as string, maximum as integer) as integer
    if text = "" or text.Len() > 10 then return -1
    number = 0
    for i = 1 to text.Len()
        value = Asc(Mid(text, i, 1))
        if value < 48 or value > 57 then return -1
        number = number * 10 + value - 48
        if number > maximum then return -1
    end for
    return number
end function

function loopbackRange(value as string, size as integer) as object
    bad = { "ok": false, "status": 416, "start": 0, "length": 0, "range": false }
    if size < 1 or size > 4194304 then return bad
    if value = "" then return { "ok": true, "status": 200, "start": 0, "length": size, "range": false }
    if value.Len() > 48 or value.Left(6) <> "bytes=" then return bad
    span = value.Right(value.Len() - 6)
    dash = span.InStr("-")
    if dash < 0 then return bad
    first = span.Left(dash)
    last = span.Right(span.Len() - dash - 1)
    if first = ""
        suffix = loopbackUnsigned(last, 4194304)
        if suffix <= 0 then return bad
        if suffix > size then suffix = size
        return { "ok": true, "status": 206, "start": size - suffix, "length": suffix, "range": true }
    end if
    start = loopbackUnsigned(first, 4194304)
    if start < 0 or start >= size then return bad
    finish = size - 1
    if last <> ""
        finish = loopbackUnsigned(last, 4194304)
        if finish < start then return bad
        if finish >= size then finish = size - 1
    end if
    return { "ok": true, "status": 206, "start": start, "length": finish - start + 1, "range": true }
end function
