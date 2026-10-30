' Color contrast helpers using WCAG 2.x sRGB relative luminance. Colors are
' "RRGGBB", "#RRGGBB" or "0xRRGGBB[AA]" strings; results are "RRGGBB".

' Returns the color as uppercase "RRGGBB", or "" when it is not a hex color.
function uiNormalizeHex(color as dynamic) as string
    if color = invalid or GetInterface(color, "ifString") = invalid then return ""
    text = UCase(color.trim())
    if text.left(1) = "#"
        text = text.mid(1)
    else if text.left(2) = "0X"
        text = text.mid(2)
    end if
    if text.len() <> 6 and text.len() <> 8 then return ""
    text = text.left(6)
    digits = "0123456789ABCDEF"
    for i = 0 to 5
        if digits.instr(text.mid(i, 1)) < 0 then return ""
    end for
    return text
end function

' Channel byte (0-255) at index 0, 1 or 2 of a normalized "RRGGBB".
function uiHexChannel(hex as string, index as integer) as integer
    digits = "0123456789ABCDEF"
    return digits.instr(hex.mid(index * 2, 1)) * 16 + digits.instr(hex.mid(index * 2 + 1, 1))
end function

function uiLinearChannel(value as integer) as float
    c = value / 255.0
    if c <= 0.04045 then return c / 12.92
    return ((c + 0.055) / 1.055) ^ 2.4
end function

' Relative luminance in [0, 1]; invalid colors count as black.
function uiRelativeLuminance(color as dynamic) as float
    hex = uiNormalizeHex(color)
    if hex = "" then return 0.0
    return 0.2126 * uiLinearChannel(uiHexChannel(hex, 0)) + 0.7152 * uiLinearChannel(uiHexChannel(hex, 1)) + 0.0722 * uiLinearChannel(uiHexChannel(hex, 2))
end function

function uiContrastRatio(colorA as dynamic, colorB as dynamic) as float
    a = uiRelativeLuminance(colorA)
    b = uiRelativeLuminance(colorB)
    if a < b
        swap = a
        a = b
        b = swap
    end if
    return (a + 0.05) / (b + 0.05)
end function

' Moves each channel the fraction amount (0-1) of the way toward white.
function uiTowardWhite(hex as string, amount as float) as string
    digits = "0123456789ABCDEF"
    result = ""
    for i = 0 to 2
        value = uiHexChannel(hex, i)
        value = Int(value + (255 - value) * amount + 0.5)
        if value > 255 then value = 255
        result = result + digits.mid(Int(value / 16), 1) + digits.mid(value mod 16, 1)
    end for
    return result
end function

' Returns color unchanged when it already reaches minRatio against a darker
' background. Otherwise blends it toward white by the smallest amount found
' in eight bisection steps that reaches minRatio, so the hue stays and the
' work is bounded. Invalid colors return "".
function uiReadableColor(color as dynamic, background as dynamic, minRatio as float) as string
    hex = uiNormalizeHex(color)
    if hex = "" then return ""
    if uiContrastRatio(hex, background) >= minRatio then return hex
    low = 0.0
    high = 1.0
    best = "FFFFFF"
    for i = 1 to 8
        middle = (low + high) / 2
        candidate = uiTowardWhite(hex, middle)
        if uiContrastRatio(candidate, background) >= minRatio
            high = middle
            best = candidate
        else
            low = middle
        end if
    end for
    return best
end function
