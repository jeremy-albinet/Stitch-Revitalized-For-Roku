' Read-only local pins; actual rail/items process them, including offline dots.
function RW_Load() as object
    return m.global.fixtureHistory
end function

function RW_LoadRail() as object
    entries = RW_Load()
    for each entry in entries
        entry.pinned = true
    end for
    return entries
end function

function RW_Section() as string
    return "fixture-recently-watched"
end function

function RW_IsPinned(login as string) as boolean
    return false
end function

function RW_MaxItems() as integer
    return 12
end function
