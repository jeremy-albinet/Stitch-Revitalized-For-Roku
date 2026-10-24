' Single source of truth for LIVE/VOD/CLIP tiles: poster size and how many
' tiles a stream grid puts in one row. 4 x 400 + 3 x 30 spacing fits every
' scene's left offset inside 1920.
function getStreamTile() as object
    return { width: 400, height: 225, perRow: 4 }
end function

' Returns row item size and height config for a given content type.
' contentType: string — the contentType field from a TwitchContentNode child
' hasRowLabel: boolean — whether the row has a visible label (affects height)
' tallRows: boolean — use taller row heights (Following scene uses larger cards)
' Returns: { itemSize: [width, height], rowHeight: integer }
' Returns invalid if contentType is unrecognized.
function getRowConfig(contentType, hasRowLabel as boolean, tallRows = false as boolean) as object
    if contentType = invalid then return invalid

    if contentType = "LIVE" or contentType = "VOD" or contentType = "CLIP"
        tile = getStreamTile()
        ' Room below the poster for title + subtitle, plus the row label.
        rowHeight = tile.height + 55
        if hasRowLabel then rowHeight += 40
        if tallRows then rowHeight += 20
        return { itemSize: [tile.width, tile.height], rowHeight: rowHeight }
    end if

    if contentType = "GAME"
        if hasRowLabel
            rowHeight = 325
        else
            rowHeight = 305
        end if
        return { itemSize: [188, 250], rowHeight: rowHeight }
    end if

    if contentType = "USER"
        if hasRowLabel
            rowHeight = 260
        else
            rowHeight = 240
        end if
        return { itemSize: [150, 150], rowHeight: rowHeight }
    end if

    return invalid
end function
