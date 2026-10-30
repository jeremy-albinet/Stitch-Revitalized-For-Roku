' Local pinned input only. The production bar, item and CirclePoster execute.
function RW_Load() as object
    return m.global.recentRingHistory
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
