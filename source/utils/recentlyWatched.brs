' Recently Watched utility — registry-backed watch history.
'
' Entry shape: { login: string, displayName: string, iconUrl: string }
' Stored in a dedicated per-user registry section as a JSON array.
' Section name: "{activeUser}_recently_watched"
' Keys: "history" = recent entries (newest first, capped at RW_MaxItems()),
'       "pinned"  = pinned entries in the order they were pinned (never capped).

' Maximum number of history entries to keep.
function RW_MaxItems() as integer
    return 12
end function

' Registry key for the pinned array within the section.
function RW_PinnedKey() as string
    return "pinned"
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

    ' Pinned channels already show in the sidebar; keep them out of the recent list.
    if RW_ListHas(RW_LoadPinned(), entry.login) then return

    updated = [entry]
    for each item in RW_ListWithout(RW_LoadRecent(), entry.login)
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

' Remove one channel (by login) from the sidebar, pinned or recent.
sub RW_Remove(login as string)
    if login = "" then return
    RW_WriteLists(RW_ListWithout(RW_LoadRecent(), login), RW_ListWithout(RW_LoadPinned(), login))
end sub

' Clear the recent (unpinned) history for the current user. Pinned channels stay.
sub RW_Clear()
    registry_delete(RW_RegistryKey(), RW_Section())
end sub

' Pin a channel: it moves to the end of the pinned list and leaves the recent list.
sub RW_Pin(entry as object)
    if entry = invalid or entry.login = invalid or entry.login = "" then return
    pinned = RW_LoadPinned()
    if RW_ListHas(pinned, entry.login) then return
    pinned.push({ login: entry.login, displayName: entry.displayName, iconUrl: entry.iconUrl })
    RW_WriteLists(RW_ListWithout(RW_LoadRecent(), entry.login), pinned)
end sub

' Unpin a channel: it goes to the front of the recent list.
sub RW_Unpin(login as string)
    pinned = RW_LoadPinned()
    entry = invalid
    for each item in pinned
        if item.login <> invalid and LCase(item.login) = LCase(login) then entry = item
    end for
    if entry = invalid then return
    registry_write(RW_PinnedKey(), FormatJson(RW_ListWithout(pinned, login)), RW_Section())
    RW_Add(entry)
end sub

' Items of a list whose login is not `login` (case-insensitive).
function RW_ListWithout(list as object, login as string) as object
    kept = []
    for each item in list
        if item.login = invalid or LCase(item.login) <> LCase(login) then kept.push(item)
    end for
    return kept
end function

function RW_ListHas(list as object, login as string) as boolean
    for each item in list
        if item.login <> invalid and LCase(item.login) = LCase(login) then return true
    end for
    return false
end function

' Sidebar order: pinned first (flagged pinned = true), then recent entries that are
' not pinned, capped at maxItems. The cap never touches pinned entries.
function RW_Combine(pinned as object, recent as object, maxItems as integer) as object
    result = []
    for each item in pinned
        flagged = {}
        flagged.append(item)
        flagged.pinned = true
        result.push(flagged)
    end for
    kept = 0
    for each item in recent
        if kept >= maxItems then exit for
        if item.login = invalid or not RW_ListHas(pinned, item.login)
            result.push(item)
            kept += 1
        end if
    end for
    return result
end function

' Pinned entries then recent entries, as shown in the sidebar.
function RW_Load() as object
    return RW_Combine(RW_LoadPinned(), RW_LoadRecent(), RW_MaxItems())
end function

function RW_LoadPinned() as object
    return RW_LoadList(RW_PinnedKey())
end function

' Recent entries only, trimmed to RW_MaxItems(). Old installs only have this key.
function RW_LoadRecent() as object
    parsed = RW_LoadList(RW_RegistryKey())
    maxItems = RW_MaxItems()
    if parsed.Count() <= maxItems then return parsed

    trimmed = []
    for i = 0 to maxItems - 1
        trimmed.push(parsed[i])
    end for
    return trimmed
end function

' Parse one registry array; empty array when missing or malformed.
function RW_LoadList(key as string) as object
    raw = registry_read(key, RW_Section())
    if raw = invalid or raw = "" then return []

    parsed = ParseJson(raw)
    if parsed = invalid then return []
    if not (type(parsed) = "roArray") then return []
    return parsed
end function

' Writes both lists with a single registry Flush (Flush is the slow part).
sub RW_WriteLists(recent as object, pinned as object)
    reg = CreateObject("roRegistrySection", RW_Section())
    reg.Write(RW_RegistryKey(), FormatJson(recent))
    reg.Write(RW_PinnedKey(), FormatJson(pinned))
    reg.Flush()
end sub
