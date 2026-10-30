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
    entry = RW_NormalizeEntry(entry)
    if entry = invalid then return

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
    return RW_LoadEntries(RW_RegistryKey())
end function

' Pins use a separate key in the same account section, including anonymous.
' Both lists and the merged rail are bounded by the existing history limit.
function RW_LoadPins() as object
    return RW_LoadEntries("pins")
end function

function RW_LoadEntries(key as string) as object
    raw = registry_read(key, RW_Section())
    if GetInterface(raw, "ifString") = invalid then return []
    if raw = "" or Len(raw) > 32768 then return []
    parsed = ParseJson(raw)
    if type(parsed) <> "roArray" then return []
    entries = []
    seen = {}
    for each candidate in parsed
        entry = RW_NormalizeEntry(candidate)
        if entry <> invalid
            if not seen.DoesExist(entry.login)
                entries.push(entry)
                seen[entry.login] = true
                if entries.Count() = RW_MaxItems() then exit for
            end if
        end if
    end for
    return entries
end function

' Keep only bounded channel metadata; never persist a ContentNode or auth data.
' Older history has no broadcaster ID, so a valid login is sufficient.
function RW_NormalizeEntry(value as dynamic) as dynamic
    if type(value) <> "roAssociativeArray" then return invalid
    if GetInterface(value.login, "ifString") = invalid then return invalid
    login = LCase(value.login.Trim())
    if Len(login) = 0 or Len(login) > 25 then return invalid
    if not CreateObject("roRegex", "^[a-z0-9_]+$", "").IsMatch(login) then return invalid
    entry = { login: login, displayName: login, iconUrl: "", id: "" }
    if GetInterface(value.displayName, "ifString") <> invalid
        if value.displayName <> "" then entry.displayName = Left(value.displayName, 64)
    end if
    if GetInterface(value.iconUrl, "ifString") <> invalid
        if Len(value.iconUrl) <= 512
            if Left(value.iconUrl, 8) = "https://" or Left(value.iconUrl, 12) = "pkg:/images/" then entry.iconUrl = value.iconUrl
        end if
    end if
    if GetInterface(value.id, "ifString") <> invalid
        if Len(value.id) > 0 and Len(value.id) <= 32
            if CreateObject("roRegex", "^[0-9]+$", "").IsMatch(value.id) then entry.id = value.id
        end if
    end if
    return entry
end function

function RW_IsPinned(login as string) as boolean
    for each entry in RW_LoadPins()
        if entry.login = LCase(login.Trim()) then return true
    end for
    return false
end function

' Explicit desired state makes repeated actions idempotent. Never evict a pin.
function RW_SetPinned(value as dynamic, pinned as boolean, expectedSection = "" as string) as string
    if expectedSection <> "" and expectedSection <> RW_Section() then return "stale"
    entry = RW_NormalizeEntry(value)
    if entry = invalid then return "invalid"
    pins = RW_LoadPins()
    found = false
    updated = []
    for each pin in pins
        if pin.login = entry.login
            found = true
            if pinned then updated.push(pin)
        else
            updated.push(pin)
        end if
    end for
    if pinned and not found
        if pins.Count() >= RW_MaxItems() then return "limit"
        updated.Unshift(entry)
    end if
    if expectedSection <> "" and expectedSection <> RW_Section() then return "stale"
    registry_write("pins", FormatJson(updated), RW_Section())
    if pinned then return "pinned"
    return "unpinned"
end function

' Local removal also unpins; a later explicit watch uses RW_Add normally.
function RW_Remove(value as dynamic, expectedSection as string) as boolean
    if expectedSection <> RW_Section() then return false
    entry = RW_NormalizeEntry(value)
    if entry = invalid then return false
    for each key in [RW_RegistryKey(), "pins"]
        updated = []
        for each item in RW_LoadEntries(key)
            if item.login <> entry.login then updated.push(item)
        end for
        if expectedSection <> RW_Section() then return false
        registry_write(key, FormatJson(updated), expectedSection)
    end for
    return true
end function

' Pin order is stable (new pins first); watching does not reorder pins.
function RW_LoadRail() as object
    rail = []
    seen = {}
    for each entry in RW_LoadPins()
        entry.pinned = true
        rail.push(entry)
        seen[entry.login] = true
    end for
    for each entry in RW_Load()
        if rail.Count() >= RW_MaxItems() then exit for
        if not seen.DoesExist(entry.login)
            entry.pinned = false
            rail.push(entry)
            seen[entry.login] = true
        end if
    end for
    return rail
end function
