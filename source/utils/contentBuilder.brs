' Returns row item size and height config for a given content type.
' contentType: string — the contentType field from a TwitchContentNode child
' hasRowLabel: boolean — whether the row has a visible label (affects height)
' tallRows: boolean — use taller row heights (Following scene uses larger cards)
' Returns: { itemSize: [width, height], rowHeight: integer }
' Returns invalid if contentType is unrecognized.
function getRowConfig(contentType, hasRowLabel as boolean, tallRows = false as boolean) as object
    if contentType = invalid then return invalid

    if contentType = "LIVE" or contentType = "VOD"
        itemSize = [320, 180]
        if tallRows
            if hasRowLabel
                rowHeight = 295
            else
                rowHeight = 255
            end if
        else
            if hasRowLabel
                rowHeight = 275
            else
                rowHeight = 235
            end if
        end if
        return { itemSize: itemSize, rowHeight: rowHeight }
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
