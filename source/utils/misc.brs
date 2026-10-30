function isNodeEvent(msg, field as string) as boolean
    return type(msg) = "roSGNodeEvent" and msg.getField() = field
end function


function getMsgPicker(msg, subnode = "" as string) as object
    node = msg.getRoSGNode()
    ' Subnode allows for handling alias messages
    if subnode <> ""
        node = node.findNode(subnode)
    end if
    coords = node.rowItemSelected
    target = node.content.getChild(coords[0]).getChild(coords[1])
    return target
end function

function getButton(msg, subnode = "buttons" as string) as object
    buttons = msg.getRoSGNode().findNode(subnode)
    if buttons = invalid then return invalid
    active_button = buttons.focusedChild
    return active_button
end function

function leftPad(base as string, fill as string, length as integer) as string
    while len(base) < length
        base = fill + base
    end while
    return base
end function

function ticksToHuman(ticks as longinteger) as string
    totalSeconds = int(ticks / 10000000)
    hours = stri(int(totalSeconds / 3600)).trim()
    minutes = stri(int((totalSeconds - (val(hours) * 3600)) / 60)).trim()
    seconds = stri(totalSeconds - (val(hours) * 3600) - (val(minutes) * 60)).trim()
    if val(hours) > 0 and val(minutes) < 10 then minutes = "0" + minutes
    if val(seconds) < 10 then seconds = "0" + seconds
    r = ""
    if val(hours) > 0 then r = hours + ":"
    r = r + minutes + ":" + seconds
    return r
end function

' Format time as 12 or 24 hour format based on system clock setting
function formatTime(time) as string
    hours = time.getHours()
    minHourDigits = 1
    di = CreateObject("roDeviceInfo")
    if di.GetClockFormat() = "12h"
        meridian = "AM"
        if hours = 0
            hours = 12
            meridian = "AM"
        else if hours = 12
            hours = 12
            meridian = "PM"
        else if hours > 12
            hours = hours - 12
            meridian = "PM"
        end if
    else
        ' For 24hr Clock, no meridian and pad hours to 2 digits
        minHourDigits = 2
        meridian = ""
    end if

    return Substitute("{0}:{1} {2}", leftPad(stri(hours).trim(), "0", minHourDigits), leftPad(stri(time.getMinutes()).trim(), "0", 2), meridian)

end function

function div_ceiling(a as integer, b as integer) as integer
    if a = 0 then return 0
    if a < b then return 1
    if int(a / b) = a / b
        return a / b
    end if
    return a / b + 1
end function

'Returns the item selected or -1 on backpress or other unhandled closure of dialog.
function get_dialog_result(dialog, port)
    while dialog <> invalid
        msg = wait(0, port)
        if isNodeEvent(msg, "backPressed")
            return -1
        else if isNodeEvent(msg, "itemSelected")
            return dialog.findNode("optionList").itemSelected
        end if
    end while
    'Dialog has closed outside of this loop, return -1 for failure
    return -1
end function

function lastFocusedChild(obj as object) as object
    if isValid(obj)
        if isValid(obj.focusedChild) and isValid(obj.focusedChild.focusedChild) and LCase(obj.focusedChild.focusedChild.subType()) = "tvepisodes"
            if isValid(obj.focusedChild.focusedChild.lastFocus)
                return obj.focusedChild.focusedChild.lastFocus
            end if
        end if

        child = obj
        for i = 0 to obj.getChildCount()
            if isValid(obj.focusedChild)
                child = child.focusedChild
            end if
        end for
        return child
    else
        return invalid
    end if
end function

sub setFieldTextValue(field, value)
    node = m.top.findNode(field)
    if node = invalid or value = invalid then return

    ' Handle non strings... Which _shouldn't_ happen, but hey
    if type(value) = "roInt" or type(value) = "Integer"
        value = str(value).trim()
    else if type(value) = "roFloat" or type(value) = "Float"
        value = str(value).trim()
    else if type(value) <> "roString" and type(value) <> "String"
        value = ""
    end if

    node.text = value
end sub

' Returns whether or not passed value is valid
function isValid(input) as boolean
    return input <> invalid
end function

' Returns whether or not passed value is valid and not empty
' Accepts a string, or any countable type (arrays and lists)
function isValidAndNotEmpty(input) as boolean
    if not isValid(input) then return false
    ' Use roAssociativeArray instead of list so we get access to the doesExist() method
    countableTypes = { "array": 1, "list": 1, "roarray": 1, "roassociativearray": 1, "rolist": 1 }
    inputType = LCase(type(input))
    if inputType = "string" or inputType = "rostring"
        trimmedInput = input.trim()
        return trimmedInput <> ""
    else if countableTypes.doesExist(inputType)
        return input.count() > 0
    else
        print "Called isValidAndNotEmpty() with invalid type: ", inputType
        return false
    end if
end function

' Rounds number to nearest integer
function roundNumber(f as float) as integer
    ' BrightScript only has a "floor" round
    ' This compares floor to floor + 1 to find which is closer
    m = int(f)
    n = m + 1
    x = abs(f - m)
    y = abs(f - n)
    if y > x
        return m
    else
        return n
    end if
end function

' Converts ticks to minutes
function getMinutes(ticks) as integer
    ' A tick is .1ms, so 1/10,000,000 for ticks to seconds,
    ' then 1/60 for seconds to minutes... 1/600,000,000
    return roundNumber(ticks / 600000000.0)
end function

'
' Returns whether or not a version number (e.g. 10.7.7) is greater or equal
' to some minimum version allowed (e.g. 10.8.0)
function versionChecker(versionToCheck as string, minVersionAccepted as string)
    leftHand = CreateObject("roLongInteger")
    rightHand = CreateObject("roLongInteger")

    regEx = CreateObject("roRegex", "\.", "")
    version = regEx.Split(versionToCheck)
    if version.Count() < 3
        for i = version.Count() to 3 step 1
            version.AddTail("0")
        end for
    end if

    minVersion = regEx.Split(minVersionAccepted)
    if minVersion.Count() < 3
        for i = minVersion.Count() to 3 step 1
            minVersion.AddTail("0")
        end for
    end if

    leftHand = (version[0].ToInt() * 10000) + (version[1].ToInt() * 100) + (version[2].ToInt() * 10)
    rightHand = (minVersion[0].ToInt() * 10000) + (minVersion[1].ToInt() * 100) + (minVersion[2].ToInt() * 10)

    return leftHand >= rightHand
end function

function findNodeBySubtype(node, subtype)
    foundNodes = []

    for each child in node.getChildren(-1, 0)
        if lcase(child.subtype()) = "group"
            return findNodeBySubtype(child, subtype)
        end if

        if lcase(child.subtype()) = lcase(subtype)
            foundNodes.push({
                node: child,
                parent: node
            })
        end if
    end for

    return foundNodes
end function

function AssocArrayEqual(Array1 as object, Array2 as object) as boolean
    if not isValid(Array1) or not isValid(Array2)
        return false
    end if

    if not Array1.Count() = Array2.Count()
        return false
    end if

    for each key in Array1
        if not Array2.DoesExist(key)
            return false
        end if

        if Array1[key] <> Array2[key]
            return false
        end if
    end for

    return true
end function

' Search string array for search value. Return if it's found
function inArray(haystack, needle) as boolean
    valueToFind = needle

    if LCase(type(valueToFind)) <> "rostring" and LCase(type(valueToFind)) <> "string"
        valueToFind = str(needle)
    end if

    valueToFind = lcase(valueToFind)

    for each item in haystack
        if lcase(item) = valueToFind then return true
    end for

    return false
end function

function toString(input) as string
    if LCase(type(input)) = "rostring" or LCase(type(input)) = "string"
        return input
    end if

    if input = invalid
        return ""
    end if

    return str(input)
end function

function select(arr, start = invalid, finish = invalid, step_ = 1):
    if step_ = 0
        ? "ValueError: slice step cannot be zero"
        return []
    end if
    if start = invalid then if step_ > 0 then start = 0 else start = arr.count() - 1
    if finish = invalid then if step_ > 0 then finish = arr.count() - 1 else finish = 0
    if start < 0 then start = arr.count() + start 'negative counts backwards from the end
    if finish < 0 then finish = arr.count() + finish
    res = []
    for i = start to finish step step_:
        res.push(arr[i])
    end for
    return res
end function

function TimeStamp()
    date = CreateObject("roDateTime")
    return date.AsSeconds()
end function

' Returns local-time wall clock as "MM-DD HH:MM:SS.mmm" - matches the format
' used by Roku's own beacon/sdkl debug lines. Use to prefix tagged debug
' prints when timing matters. roDateTime is UTC by default; ToLocalTime() is
' not idempotent so it's only called once per fresh object.
function getLogTimestamp() as string
    date = CreateObject("roDateTime")
    date.ToLocalTime()
    mm = leftPad(date.GetMonth().toStr(), "0", 2)
    dd = leftPad(date.GetDayOfMonth().toStr(), "0", 2)
    hh = leftPad(date.GetHours().toStr(), "0", 2)
    nn = leftPad(date.GetMinutes().toStr(), "0", 2)
    ss = leftPad(date.GetSeconds().toStr(), "0", 2)
    ms = leftPad(date.GetMilliseconds().toStr(), "0", 3)
    return mm + "-" + dd + " " + hh + ":" + nn + ":" + ss + "." + ms
end function


sub setTwitchContentFields(twitchContentNode, fields)
    if fields.contentId <> invalid
        twitchContentNode.contentId = fields.contentId
    end if
    if fields.createdAt <> invalid
        twitchContentNode.createdAt = fields.createdAt
    end if
    if fields.contentType <> invalid
        twitchContentNode.contentType = fields.contentType
    end if
    if fields.previewImageURL <> invalid
        twitchContentNode.previewImageUrl = fields.previewImageURL
    end if
    if fields.contentTitle <> invalid
        twitchContentNode.contentTitle = fields.contentTitle
    end if
    if fields.viewersCount <> invalid
        twitchContentNode.viewersCount = fields.viewersCount
    end if
    if fields.followerCount <> invalid
        twitchContentNode.followerCount = fields.followerCount
    end if
    if fields.streamerDisplayName <> invalid
        twitchContentNode.streamerDisplayName = fields.streamerDisplayName
    end if
    if fields.streamerLogin <> invalid
        twitchContentNode.streamerLogin = fields.streamerLogin
    end if
    if fields.streamerid <> invalid
        twitchContentNode.streamerId = fields.streamerId
    end if
    if fields.streamerProfileImageUrl <> invalid
        twitchContentNode.streamerProfileImageUrl = fields.streamerProfileImageUrl
    end if
    if fields.gameDisplayName <> invalid
        twitchContentNode.gameDisplayName = fields.gameDisplayName
    end if
    if fields.gameBoxArtUrl <> invalid
        twitchContentNode.gameBoxArtUrl = fields.gameBoxArtUrl
    end if
    if fields.gameId <> invalid
        twitchContentNode.gameId = fields.gameId
    end if
    if fields.gameName <> invalid
        twitchContentNode.gameName = fields.gameName
    end if
    if fields.url <> invalid
        twitchContentNode.url = fields.url
    end if
    if fields.clipslug <> invalid
        twitchContentNode.clipslug = fields.clipslug
    end if
    if fields.datePublished <> invalid
        twitchContentNode.datePublished = fields.datePublished
    end if
end sub

' Helper function to add and set fields of a content node
sub AddAndSetFields(node as object, aa as object)
    'This gets called for every content node -- no logging since it's pretty verbose
    addFields = {}
    setFields = {}
    for each field in aa
        if node.hasField(field)
            setFields[field] = aa[field]
        else
            addFields[field] = aa[field]
        end if
    end for
    node.setFields(setFields)
    node.addFields(addFields)
end sub


'Create a row of content
function createRow(list as object, num as integer)
    Parent = createObject("RoSGNode", "ContentNode")
    row = createObject("RoSGNode", "ContentNode")
    row.Title = list[num].Title
    for each itemAA in list[num].ContentList
        item = createObject("RoSGNode", "ContentNode")
        AddAndSetFields(item, itemAA)
        row.appendChild(item)
    end for
    Parent.appendChild(row)
    return Parent
end function

'Create a grid of content - simple splitting of a feed to different rows
'with the title of the row hidden.
'Set the for loop parameters to adjust how many columns there
'should be in the grid.
function createGrid(list as object)
    Parent = createObject("RoSGNode", "ContentNode")
    for i = 0 to list.count() step 5
        row = createObject("RoSGNode", "ContentNode")
        if i = 0
            row.Title = "Followed Channels"
        end if
        for j = i to i + 4
            if list[j] <> invalid
                item = createObject("RoSGNode", "ContentNode")
                AddAndSetFields(item, list[j])
                row.appendChild(item)
            end if
        end for
        Parent.appendChild(row)
    end for
    return Parent
end function


' Applies the interface palette to a standard dialog or keyboard dialog. Keys
' follow Roku's RSGPalette documentation (Standard Dialog Framework). Without a
' palette field or constants, the dialog keeps the inherited system palette.
function applyDialogPalette(dialog as dynamic) as boolean
    if dialog = invalid then return false
    if not dialog.hasField("palette") then return false
    color = m.global?.constants?.ui?.color
    if color = invalid then return false
    palette = CreateObject("roSGNode", "RSGPalette")
    if palette = invalid then return false
    palette.colors = {
        DialogBackgroundColor: color.surface,
        DialogItemColor: color.focus,
        DialogTextColor: color.text,
        DialogFocusColor: color.focusFill,
        DialogFocusItemColor: color.onAccent,
        DialogSecondaryTextColor: color.textSecondary,
        DialogSecondaryItemColor: color.divider,
        DialogInputFieldColor: color.raised,
        DialogKeyboardColor: color.raised,
        DialogFootprintColor: color.divider
    }
    dialog.palette = palette
    return true
end function

' Sign-out confirmation shared by the Account panel and Settings. Button 0
' confirms; the caller observes buttonSelected/wasClosed and signs out.
function createSignOutDialog() as object
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = tr("Sign out of Twitch?")
    dialog.message = [tr("Your settings and recent channels stay on this Roku. You can still watch public streams.")]
    dialog.buttons = [tr("Sign out"), tr("Cancel")]
    applyDialogPalette(dialog)
    return dialog
end function

' Sets a label's text and widens it and its plate to fit, never below
' minWidth. Width 0 lets the label size to its text for measuring.
function fitLabelPlate(label as dynamic, plate as dynamic, text as string, padding as integer, minWidth as integer) as integer
    width = minWidth
    if label = invalid then return width
    label.width = 0
    label.text = text
    try
        textWidth = Int(label.localBoundingRect().width) + padding
        if textWidth > width then width = textWidth
    catch e
    end try
    label.width = width
    if plate <> invalid then plate.width = width
    return width
end function

' Centered status message for the live and recorded player wrappers: a
' surface plate with an optional Bold 24 title and a Regular 20 body.
function createPlayerMessageOverlay() as object
    ui = m.global?.constants?.ui
    surface = "0x1F1F23FF"
    text = "0xEFEFF1FF"
    secondary = "0xADADB8FF"
    if ui <> invalid
        surface = ui.color.surface
        text = ui.color.text
        secondary = ui.color.textSecondary
    end if
    overlay = CreateObject("roSGNode", "Group")
    overlay.visible = false
    plate = overlay.createChild("Rectangle")
    plate.id = "messagePlate"
    plate.width = 640
    plate.color = surface
    title = overlay.createChild("Label")
    title.id = "messageTitle"
    title.font = createArchivoFont(true, 24)
    title.color = text
    title.horizAlign = "center"
    title.width = 576
    title.height = 32
    body = overlay.createChild("Label")
    body.id = "messageText"
    body.font = createArchivoFont(false, 20)
    body.color = secondary
    body.horizAlign = "center"
    body.wrap = true
    body.maxLines = 3
    body.width = 576
    return overlay
end function

' Fills a createPlayerMessageOverlay group and centers its plate on screen.
sub setPlayerMessage(overlay as object, title as string, message as string)
    titleNode = overlay.findNode("messageTitle")
    body = overlay.findNode("messageText")
    plate = overlay.findNode("messagePlate")
    if titleNode = invalid or body = invalid or plate = invalid then return
    titleNode.text = title
    titleNode.visible = (title <> "")
    body.text = message
    bodyHeight = 28
    try
        measured = Int(body.localBoundingRect().height)
        if measured > bodyHeight then bodyHeight = measured
    catch e
    end try
    bodyTop = 24
    if title <> "" then bodyTop = 68
    plateHeight = bodyTop + bodyHeight + 24
    top = 360 - Int(plateHeight / 2)
    plate.height = plateHeight
    plate.translation = [0, top]
    titleNode.translation = [32, top + 24]
    body.translation = [32, top + bodyTop]
end sub

function createArchivoFont(bold as boolean, size as integer) as object
    font = CreateObject("roSGNode", "Font")
    if bold
        font.uri = "pkg:/fonts/Archivo-Bold.otf"
    else
        font.uri = "pkg:/fonts/Archivo-Regular.otf"
    end if
    font.size = size
    return font
end function

' Splits items into consecutive groups of at most size items. The final group
' keeps any remainder, so no trailing item is dropped.
function chunkItems(items as dynamic, size as integer) as object
    groups = []
    if type(items) <> "roArray" or size < 1 then return groups
    group = []
    for each item in items
        group.push(item)
        if group.count() = size
            groups.push(group)
            group = []
        end if
    end for
    if group.count() > 0 then groups.push(group)
    return groups
end function


function numberToText(number as object) as object
    result = ""
    if number < 1000
        result = number.toStr()
    else if number < 1000 * 1000
        n = (number / 1000).toStr()
        ' Regex: any numbers with a dot and a decimal different from 0 OR any amount of numbers (stops at the dot). In that order.
        r = CreateObject("roRegex", "([0-9]+\.[1-9])|([0-9]+)", "")
        result = r.Match(n)[0] + "K"
    else
        n = (number / 1000000).toStr()
        r = CreateObject("roRegex", "([0-9]+\.[1-9])|([0-9]+)", "")
        result = r.Match(n)[0] + "M"
    end if
    return result
end function


function getRelativeTimePublished(timePublished as string) as string
    secondsSincePublished = createObject("roDateTime")
    secondsSincePublished.FromISO8601String(timePublished)
    currentTime = createObject("roDateTime").AsSeconds()
    elapsedTime = currentTime - secondsSincePublished.AsSeconds()

    elapsedTime = Int(elapsedTime / 60)
    if elapsedTime < 60
        if elapsedTime = 1
            return "1 minute ago"
        else
            return elapsedTime.ToStr() + " minutes ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 60)
    if elapsedTime < 24
        if elapsedTime = 1
            return "1 hour ago"
        else
            return elapsedTime.ToStr() + " hours ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 24)
    if elapsedTime < 30
        if elapsedTime = 1
            return "1 day ago"
        else
            return elapsedTime.ToStr() + " days ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 30)
    if elapsedTime < 12
        if elapsedTime = 1
            return "Last month"
        else
            return elapsedTime.ToStr() + " months ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 12)
    if elapsedTime = 1
        return "1 year ago"
    else
        return elapsedTime.ToStr() + " years ago"
    end if

end function

' Validates a deep property chain exists and is valid
' Returns true if root is valid and all keys in path exist and resolve to valid values
' Uses case-insensitive key lookup (LookupCI)
function isChainValid(root as dynamic, path as string) as boolean
    if not isValid(root) then return false
    if path = "" then return true
    parts = path.Split(".")
    node = root
    for each p in parts
        if not isValid(node) then return false
        if type(node) <> "roAssociativeArray" then return false
        node = node.LookupCI(p)
    end for
    return isValid(node)
end function
