' Engine boundary for EmojiLabelRegex.brs. brs-engine cannot compile the
' production Unicode emoji pattern, and its regex errors escape try/catch, so
' this substitute returns an ASCII pattern and counts compilations per label
' instance. A requested failure throws, standing in for firmware that cannot
' compile the pattern (Roku returns invalid). EmojiLabel.brs runs unchanged.
function emojiRegexSource() as string
    if m.fixtureBuilds = invalid then m.fixtureBuilds = 0
    m.fixtureBuilds += 1
    if m.fixtureFail <> invalid and m.fixtureFail then throw "fixture pattern unavailable"
    return ":\)"
end function
