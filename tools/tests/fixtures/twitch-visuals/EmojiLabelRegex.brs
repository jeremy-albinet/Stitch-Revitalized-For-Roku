' Engine boundary: brs-engine cannot compile the production Unicode emoji
' pattern, so card titles use an ASCII pattern here. EmojiLabel.brs and
' EmojiLabelUtil.brs run unchanged.
function emojiRegexSource() as string
    return ":\)"
end function
