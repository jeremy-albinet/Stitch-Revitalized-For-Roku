' Recently Watched utility — registry-backed watch history.
'
' Entry shape: { id: string, login: string, displayName: string, iconUrl: string }
' Stored under the current user's registry section as JSON.

' Maximum number of history entries to keep.
function RW_MaxItems() as integer
    return 12
end function

' Add an entry to recently watched history.
' Deduplicates by id (moves existing to front). Trims to maxItems.
sub RW_Add(entry as object, maxItems as integer)
    if entry = invalid then return
    if entry.id = invalid or entry.id = "" then return

    existing = RW_Load(maxItems)

    ' Remove any existing entry with the same id so we can prepend fresh
    filtered = []
    for each item in existing
        if item.id <> entry.id
            filtered.push(item)
        end if
    end for

    ' Prepend the new entry
    updated = [entry]
    for each item in filtered
        updated.push(item)
    end for

    ' Trim to maxItems
    if updated.Count() > maxItems
        trimmed = []
        for i = 0 to maxItems - 1
            trimmed.push(updated[i])
        end for
        updated = trimmed
    end if

    set_user_setting("recentlyWatched", FormatJson(updated))
end sub

' Load recently watched history from registry.
' Returns an array of entry AAs, or an empty array if none stored.
function RW_Load(maxItems as integer) as object
    raw = get_user_setting("recentlyWatched")
    if raw = invalid or raw = "" then return []

    parsed = ParseJson(raw)
    if parsed = invalid then return []
    if not (type(parsed) = "roArray") then return []

    if parsed.Count() <= maxItems
        return parsed
    end if

    trimmed = []
    for i = 0 to maxItems - 1
        trimmed.push(parsed[i])
    end for
    return trimmed
end function
