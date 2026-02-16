' Recently Watched utilities (Roku BrightScript-safe)

function RW_Load(maxItems = 12 as Integer) as Object
    sec = CreateObject("roRegistrySection", "stitch")
    json = sec.Read("recently_watched")
    if json = invalid or json = "" then return []

    parsed = ParseJson(json)
    if parsed = invalid then return []

    ' Ensure it's an array
    if GetInterface(parsed, "ifArray") = invalid then return []

    ' Trim if needed
    while parsed.Count() > maxItems
        parsed.Pop()
    end while

    return parsed
end function

sub RW_Save(list as Object)
    sec = CreateObject("roRegistrySection", "stitch")
    sec.Write("recently_watched", FormatJson(list))
    sec.Flush()
end sub

sub RW_Add(item as Object, maxItems = 12 as Integer)
    if item = invalid then return

    ' Require at least a login or id
    idKey = ""
    if item.id <> invalid and item.id <> "" then
        idKey = item.id
    else if item.login <> invalid and item.login <> "" then
        idKey = item.login
    else
        return
    end if

    list = RW_Load(maxItems)
    newList = []

    for each it in list
        itId = ""
        if it.id <> invalid then itId = it.id
        if itId = "" and it.login <> invalid then itId = it.login

        if itId <> idKey
            newList.Push(it)
        end if
    end for

    dt = CreateObject("roDateTime")
    item.lastWatched = dt.AsSeconds().ToStr()

    ' Put newest first
    newList.Unshift(item)

    while newList.Count() > maxItems
        newList.Pop()
    end while

    RW_Save(newList)
end sub
