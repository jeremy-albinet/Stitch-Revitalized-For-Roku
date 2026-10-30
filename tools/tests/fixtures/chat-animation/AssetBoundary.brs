' HTTP and deliberate failure/epilogue boundaries only. Allocation, stat, read,
' write and successful deletion use the actual filesystem in the actual Task.
function fixtureTransfer() as object
    return {
        top: m.top, setMessagePort: fixtureSetObject, setCertificatesFile: fixtureSetString,
        initClientCertificates: fixtureNothing, setUrl: fixtureSetString,
        asyncHead: fixtureHead, asyncGetToFile: fixtureStart, asyncCancel: fixtureCancel, getIdentity: fixtureIdentity
    }
end function

function fixtureHead() as boolean
    m.top.fixtureHeadPending = true
    return true
end function

function fixtureStart(path as string) as boolean
    bytes = createObject("roByteArray")
    bytes.readFile("pkg:/" + m.top.fixtureSource)
    result = bytes.writeFile(path)
    m.top.fixtureStarted = true
    return result
end function

function fixtureWait(duration as integer, port as object) as dynamic
    if m.top.fixtureHeadPending
        m.top.fixtureHeadPending = false
        return { top: m.top, getSourceIdentity: fixtureIdentity, getResponseCode: fixtureHeadCode, getResponseHeadersArray: fixtureHeaders }
    end if
    if not m.top.fixtureRelease
        return wait(duration, port)
    end if
    return { top: m.top, mode: m.top.fixtureMode, getSourceIdentity: fixtureIdentity, getResponseCode: fixtureResponseCode, getResponseHeadersArray: fixtureHeaders }
end function

function fixtureHeaders() as object
    return [{ "Content-Length": createObject("roFileSystem").stat("pkg:/" + m.top.fixtureSource).size.toStr() }]
end function

function fixtureHeadCode() as integer
    return 200
end function

function fixtureResponseCode() as integer
    if m.mode = "reject" then return 404
    return 200
end function

sub fixtureCancel()
    if m.top.fixtureWriteOnCancel
        bytes = createObject("roByteArray")
        bytes.fromAsciiString("last producer write before cancellation completes")
        m.top.fixtureLateWrite = bytes.writeFile(m.top.request.path)
    end if
    m.top.fixtureCancelled = true
end sub

function fixtureDelete(fs as object, path as string) as boolean
    locked = m.top.fixtureLockedPath
    m.top.fixtureDeleteCount++
    if locked <> "" and locked.left(path.len()) = path then return false
    return fs.delete(path)
end function

sub fixtureAfterResponse()
    ' Expose the response-before-return race without changing filesystem code.
    port = createObject("roMessagePort")
    clock = createObject("roTimespan")
    while m.top.fixtureHoldAfterResponse and clock.totalMilliseconds() < 2000
        ignored = wait(20, port)
    end while
end sub

function fixtureIdentity() as integer
    return 42
end function

sub fixtureSetObject(value as object)
end sub
sub fixtureSetString(value as string)
end sub
sub fixtureNothing()
end sub
