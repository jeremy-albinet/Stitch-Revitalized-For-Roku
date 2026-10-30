sub init()
    m.disposed = false
end sub

' Application-owned cleanup invoked explicitly before permanent removal.
sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.lastFocus = invalid
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    return false
end function
