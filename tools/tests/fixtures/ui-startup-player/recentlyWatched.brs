' Read-only local pins; the actual rail and items process them.
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
