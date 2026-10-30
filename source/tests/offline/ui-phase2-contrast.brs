' @include source/utils/uiContrast.brs
' Checks the chat name contrast helper against published WCAG 2.x reference
' values (luminance of pure primaries, 21:1 white on black, 4.48:1 for
' #777777 on white) and the lightening rules the chat relies on.
sub main()
    canvas = "0E0E10"
    if not contrastExpect(uiNormalizeHex("#0000ff") = "0000FF", "normalizes #rrggbb") then return
    if not contrastExpect(uiNormalizeHex("0xEB0400FF") = "EB0400", "normalizes 0xRRGGBBAA") then return
    if not contrastExpect(uiNormalizeHex("12345") = "" and uiNormalizeHex("GG0000") = "" and uiNormalizeHex(invalid) = "" and uiNormalizeHex(42) = "", "rejects malformed colors") then return

    if not contrastExpect(near(uiRelativeLuminance("FFFFFF"), 1.0, 0.0001) and near(uiRelativeLuminance("000000"), 0.0, 0.0001), "white and black luminance") then return
    if not contrastExpect(near(uiRelativeLuminance("FF0000"), 0.2126, 0.0001) and near(uiRelativeLuminance("00FF00"), 0.7152, 0.0001) and near(uiRelativeLuminance("0000FF"), 0.0722, 0.0001), "primary luminance matches the sRGB coefficients") then return
    if not contrastExpect(near(uiContrastRatio("FFFFFF", "000000"), 21.0, 0.001), "white on black is 21:1") then return
    ratio = uiContrastRatio("777777", "FFFFFF")
    if not contrastExpect(ratio > 4.47 and ratio < 4.49, "#777777 on white is about 4.48:1") then return
    if not contrastExpect(near(uiContrastRatio("0000FF", canvas), uiContrastRatio(canvas, "0000FF"), 0.000001), "contrast is symmetric") then return

    ' Already readable Twitch colors are returned unchanged.
    for each color in ["FF0000", "00FF7F", "DAA520", "FF69B4", "1E90FF"]
        if not contrastExpect(uiContrastRatio(color, canvas) >= 4.5 and uiReadableColor(color, canvas, 4.5) = color, color + " stays unchanged") then return
    end for

    ' Low-contrast colors become readable with their hue kept and only as
    ' much lightening as needed.
    cases = [
        { color: "0000FF", order: [2, 0, 1] },
        { color: "B22222", order: [0, 1, 2] },
        { color: "8A2BE2", order: [2, 0, 1] },
        { color: "000000", order: [0, 1, 2] }
    ]
    for each item in cases
        before = uiContrastRatio(item.color, canvas)
        result = uiReadableColor(item.color, canvas, 4.5)
        after = uiContrastRatio(result, canvas)
        if not contrastExpect(before < 4.5 and result <> item.color, item.color + " starts below 4.5:1 and changes") then return
        if not contrastExpect(after >= 4.5 and after < 4.8, item.color + " reaches 4.5:1 without overshooting (" + Str(after).trim() + ")") then return
        if not contrastExpect(result <> "FFFFFF", item.color + " is not flattened to white") then return
        for i = 0 to 2
            if not contrastExpect(uiHexChannel(result, i) >= uiHexChannel(item.color, i), item.color + " only moves toward white") then return
        end for
        if not contrastExpect(keepsOrder(item.color, result, item.order), item.color + " keeps its channel order (hue)") then return
    end for
    if not contrastExpect(uiReadableColor("zz", canvas, 4.5) = "", "malformed color returns empty") then return

    ? "STITCH_TEST_PASS: ui phase2 contrast helper"
end sub

' True when the channels of result keep the same ordering as source, with
' equal channels staying equal.
function keepsOrder(source as string, result as string, order as object) as boolean
    for i = 0 to 1
        a = order[i]
        b = order[i + 1]
        if uiHexChannel(source, a) = uiHexChannel(source, b)
            if Abs(uiHexChannel(result, a) - uiHexChannel(result, b)) > 1 then return false
        else if uiHexChannel(result, a) < uiHexChannel(result, b)
            return false
        end if
    end for
    return true
end function

function near(value as float, expected as float, tolerance as float) as boolean
    return Abs(value - expected) <= tolerance
end function

function contrastExpect(condition as boolean, detail as string) as boolean
    if not condition then ? "STITCH_TEST_FAIL: " + detail
    return condition
end function
