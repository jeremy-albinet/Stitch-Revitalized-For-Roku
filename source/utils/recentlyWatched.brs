' Recently Watched utility — registry-backed watch history.
'
' Entry shape: { login: string, displayName: string, iconUrl: string }
' Stored in a dedicated per-user registry section as a JSON array.
' Section name: "{activeUser}_recently_watched"

' Maximum number of history entries to keep.
function RW_MaxItems() as integer
    return 12
end function

' Registry key used to store the history array within the section.
function RW_RegistryKey() as string
    return "history"
end function

' Returns the registry section name for the current user.
' Uses "$default$" as the section prefix when no user is logged in.
function RW_Section() as string
    activeUser = get_setting("active_user", "$default$")
    return activeUser + "_recently_watched"
end function

' Add an entry to recently watched history.
' Deduplicates by login (moves existing to front). Trims to RW_MaxItems().
' No-ops if login is missing.
sub RW_Add(entry as object)
    if entry = invalid then return
    if entry.login = invalid or entry.login = "" then return

    existing = RW_Load()

    filtered = []
    for each item in existing
        if item.login <> entry.login
            filtered.push(item)
        end if
    end for

    updated = [entry]
    for each item in filtered
        updated.push(item)
    end for

    maxItems = RW_MaxItems()
    if updated.Count() > maxItems
        trimmed = []
        for i = 0 to maxItems - 1
            trimmed.push(updated[i])
        end for
        updated = trimmed
    end if

    registry_write(RW_RegistryKey(), FormatJson(updated), RW_Section())
end sub

' Load recently watched history from the dedicated registry section.
' Returns an array of entry AAs, or an empty array if none stored.
function RW_Load() as object
    raw = registry_read(RW_RegistryKey(), RW_Section())
    if raw = invalid or raw = "" then return []

    parsed = ParseJson(raw)
    if parsed = invalid then return []
    if not (type(parsed) = "roArray") then return []

    maxItems = RW_MaxItems()
    if parsed.Count() <= maxItems then return parsed

    trimmed = []
    for i = 0 to maxItems - 1
        trimmed.push(parsed[i])
    end for
    return trimmed
end function
