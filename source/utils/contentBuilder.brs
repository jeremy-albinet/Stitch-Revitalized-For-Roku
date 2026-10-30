' Shared stream geometry in the redesigned interface's HD coordinate space.
function getStreamTile() as object
    if m.global?.compactGrid = true then return { width: 256, height: 144, perRow: 4 }
    return { width: 320, height: 180, perRow: 3 }
end function

' Returns row item size and height config for a given content type.
' contentType: string — the contentType field from a TwitchContentNode child
' hasRowLabel: boolean — whether the row has a visible label (affects height)
' tallRows: boolean — reserve space for the expanded stream card text
' Returns: { itemSize: [width, height], rowHeight: integer }
' Returns invalid if contentType is unrecognized.
function getRowConfig(contentType, hasRowLabel as boolean, tallRows = false as boolean) as object
    if contentType = invalid then return invalid

    if contentType = "LIVE" or contentType = "VOD" or contentType = "CLIP"
        tile = getStreamTile()
        itemSize = [tile.width, tile.height]
        if tallRows
            if hasRowLabel
                rowHeight = tile.height + 115
            else
                rowHeight = tile.height + 75
            end if
        else
            if hasRowLabel
                rowHeight = tile.height + 95
            else
                rowHeight = tile.height + 55
            end if
        end if
        return { itemSize: itemSize, rowHeight: rowHeight }
    end if

    if contentType = "GAME"
        ' The category subtitle ends at y=308; leave padding and label space.
        if hasRowLabel
            rowHeight = 355
        else
            rowHeight = 315
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
