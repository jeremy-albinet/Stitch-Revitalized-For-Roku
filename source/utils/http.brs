function HttpRequest(params = invalid as dynamic) as object
    url = invalid
    method = invalid
    headers = {}
    data = invalid
    timeout = 15000
    retries = 1
    interval = 500
    if params <> invalid
        if params.url <> invalid then url = params.url
        if params.method <> invalid then method = params.method
        if params.headers <> invalid then headers = params.headers
        if params.data <> invalid then data = params.data
        if params.timeout <> invalid then timeout = params.timeout
        if params.retries <> invalid then retries = params.retries
        if params.interval <> invalid then interval = params.interval
    end if

    timeout = boundedHttpOption(timeout, 15000, 50, 30000)
    retries = boundedHttpOption(retries, 1, 1, 3)
    interval = boundedHttpOption(interval, 500, 0, 5000)

    obj = {
        _timeout: timeout,
        _retries: retries,
        _interval: interval,
        _deviceInfo: createObject("roDeviceInfo"),
        _url: url,
        _method: method,
        _requestHeaders: headers,
        _data: data,
        _http: invalid,
        _isAborted: false,

        _isProtocolSecure: function(url as string) as boolean
            return left(url, 6) = "https:"
        end function,

        _createHttpRequest: function() as object
            request = createObject("roUrlTransfer")
            if request = invalid
                return invalid
            end if
            request.setPort(createObject("roMessagePort"))
            request.setUrl(m._url)
            request.retainBodyOnError(true)
            request.enableCookies()
            request.setHeaders(m._requestHeaders)
            if m._method <> invalid then request.setRequest(m._method)

            'Checks if URL protocol is secured, and adds appropriate parameters if needed
            if m._isProtocolSecure(m._url)
                request.setCertificatesFile("common:/certs/ca-bundle.crt")
                request.initClientCertificates()
            end if

            return request
        end function,

        getPort: function()
            if m._http <> invalid
                return m._http.getPort()
            else
                return invalid
            end if
        end function,

        getCookies: function(domain as string, path as string) as object
            if m._http <> invalid
                return m._http.getCookies(domain, path)
            else
                return invalid
            end if
        end function,

        send: function(data = invalid as dynamic) as dynamic
            timeout = m._timeout
            retries = m._retries
            response = invalid

            if data <> invalid then m._data = data

            if getInterface(m._url, "ifString") = invalid then return invalid
            if m._url = "" then return invalid

            if m._data <> invalid and getInterface(m._data, "ifString") = invalid
                m._data = formatJson(m._data)
            end if

            while retries > 0 and m._deviceInfo.getLinkStatus()
                if m._isAborted then exit while
                deadline = CreateObject("roTimeSpan")
                deadline.Mark()
                if m._sendHttpRequest(m._data)
                    remaining = timeout - deadline.TotalMilliseconds()
                    event = invalid
                    if remaining > 0 then event = m._http.getPort().waitMessage(remaining)

                    if m._isAborted
                        m._isAborted = false
                        m._http.asyncCancel()
                        exit while
                    else if type(event) = "roUrlEvent" and deadline.TotalMilliseconds() <= timeout
                        response = event
                        exit while
                    end if

                    m._http.asyncCancel()
                    timeout = boundedHttpOption(timeout * 2, 15000, 50, 30000)
                    if retries > 1 then sleep(m._interval)
                end if

                retries--
            end while

            return response
        end function,

        _sendHttpRequest: function(data = invalid as dynamic) as dynamic
            m._http = m._createHttpRequest()
            if m._http = invalid then return false

            if data <> invalid
                return m._http.asyncPostFromString(data)
            else
                return m._http.asyncGetToString()
            end if
        end function,

        abort: sub()
            m._isAborted = true
        end sub

    }

    return obj
end function

' Requests cannot opt into an indefinite wait or unbounded retry count.
function boundedHttpOption(value as dynamic, fallback as integer, minimum as integer, maximum as integer) as integer
    valueType = type(value)
    if valueType <> "Integer" and valueType <> "roInt" and valueType <> "roInteger" and valueType <> "Float" and valueType <> "roFloat" and valueType <> "Double" and valueType <> "roDouble" and valueType <> "LongInteger" and valueType <> "roLongInteger" then return fallback
    if value < minimum then return fallback
    if value > maximum then return maximum
    return Int(value)
end function

function decodeJsonResponse(event as dynamic, allowHttpError = false as boolean) as dynamic
    if type(event) <> "roUrlEvent" then return invalid
    return decodeJsonBody(event.getString(), event.getResponseCode(), allowHttpError)
end function

function decodeJsonBody(body as dynamic, status as integer, allowHttpError = false as boolean) as dynamic
    if getInterface(body, "ifString") = invalid then return invalid
    if status <= 0 then return invalid
    if not allowHttpError and (status < 200 or status >= 300) then return invalid
    if body = "" or Len(body) > 4194304 then return invalid
    return ParseJSON(body)
end function
