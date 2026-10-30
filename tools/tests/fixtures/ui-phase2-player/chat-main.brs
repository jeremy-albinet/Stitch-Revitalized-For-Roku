' Actual Chat name rendering (contrast against the chat background, bounded
' per-instance cache, link color, status copy), EmojiLabel's per-instance
' pattern cache with its plain-text fallback, and the documented contrast of
' the interface color tokens. Chat transport tasks are never started.
sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: {}, emoteCache: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()

    testChatNames()
    testEmojiLabel()
    testTokenContrast()

    fixtureEnd()
end sub

function hexByte(value as integer) as string
    digits = "0123456789ABCDEF"
    return digits.mid(Int(value / 16), 1) + digits.mid(value mod 16, 1)
end function

function nameColor(chat as object, color as dynamic) as string
    return colorHex(chat.callFunc("fixtureNameColor", color))
end function

sub testChatNames()
    chat = createObject("roSGNode", "Chat")
    m.scene.appendChild(chat)
    canvas = uiNormalizeHex(m.ui.canvas)
    check(uiNormalizeHex(chat.backgroundColor) = canvas, "chat sits on the canvas color")

    blue = nameColor(chat, "0000FF")
    check(blue <> "0000FF" and uiContrastRatio(blue, canvas) >= 4.5, "a blue name is lightened to at least 4.5:1")
    check(uiHexChannel(blue, 2) > uiHexChannel(blue, 0) and uiHexChannel(blue, 0) = uiHexChannel(blue, 1), "the lightened name stays blue")
    fireBrick = nameColor(chat, "B22222")
    check(uiContrastRatio(fireBrick, canvas) >= 4.5 and uiHexChannel(fireBrick, 0) > uiHexChannel(fireBrick, 1), "FireBrick is lightened and stays red")
    check(nameColor(chat, "FF0000") = "FF0000", "an already readable name color is unchanged")
    for each bad in ["#12", "", "nothex"]
        check(nameColor(chat, bad) = "FFFFFF", "malformed color '" + bad + "' shows white")
    end for
    check(nameColor(chat, invalid) = "FFFFFF", "an unset color shows white")
    check(chat.callFunc("fixtureCached") = 3, "only valid colors are cached")
    nameColor(chat, "0000ff")
    check(chat.callFunc("fixtureCached") = 3, "a repeated color in any case is served from the cache")

    ' 128 distinct colors fill the cache; the next one starts it over.
    for i = 0 to 124
        nameColor(chat, "20" + hexByte(i) + "40")
    end for
    check(chat.callFunc("fixtureCached") = 128, "the cache holds 128 colors")
    nameColor(chat, "123456")
    check(chat.callFunc("fixtureCached") = 1, "the 129th color starts a new cache instead of growing")

    other = createObject("roSGNode", "Chat")
    m.scene.appendChild(other)
    check(other.callFunc("fixtureCached") = 0 and chat.callFunc("fixtureCached") = 1, "each chat keeps its own cache")
    chat.backgroundColor = "0x000000FF"
    waitCached(chat, 0)
    check(chat.callFunc("fixtureCached") = 0, "a background change clears the cache")

    check(colorHex(chat.callFunc("fixtureLinkColor")) = uiNormalizeHex(m.ui.link), "links use the link color")
    check(chat.callFunc("fixtureStatus", "reconnecting") = "Chat disconnected. Reconnecting…", "the reconnect status is readable copy")
    nameColor(chat, "0000FF")
    chat.callFunc("onDestroy")
    check(chat.callFunc("fixtureCached") = 0, "disposal clears the cache")
    other.callFunc("onDestroy")
    m.scene.removeChild(chat)
    m.scene.removeChild(other)
end sub

sub waitCached(chat as object, count as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 2000
        if chat.callFunc("fixtureCached") = count then return
        pump(20)
    end while
end sub

function newLabel() as object
    label = createObject("roSGNode", "EmojiLabel")
    label.height = 28
    m.scene.appendChild(label)
    return label
end function

sub setText(label as object, text as string)
    label.text = text
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 2000
        if label.callFunc("fixtureText") = text then return
        pump(20)
    end while
    fail("timed out rendering " + text)
end sub

sub testEmojiLabel()
    first = newLabel()
    second = newLabel()
    s = first.callFunc("fixtureRead")
    check(s.builds = 0 and not s.compiled, "a label compiles nothing before it has text")
    setText(first, "First title")
    setText(first, "Second title")
    setText(first, "Third title")
    s = first.callFunc("fixtureRead")
    check(s.builds = 1 and s.compiled and s.parts = 1, "text updates reuse the one pattern this label compiled")
    setText(second, "Other card")
    check(second.callFunc("fixtureRead").builds = 1 and first.callFunc("fixtureRead").builds = 1, "each label compiles its own pattern once; nothing is shared")

    failing = newLabel()
    failing.callFunc("fixtureFailCompile")
    check(not failing.callFunc("fixtureCompile"), "a pattern that cannot be compiled is reported as unavailable")
    setText(failing, "Plain fallback")
    setText(failing, "Still plain")
    s = failing.callFunc("fixtureRead")
    check(s.failed and s.builds = 1 and s.parts = 1, "after a failed compile text stays plain and compiling is not retried")

    first.maxWidth = 80
    first.repeatCount = -1
    check(not first.callFunc("fixtureRead").scrolling, "long-title activation returns before scrolling starts")
    settle(1100)
    check(first.callFunc("fixtureRead").scrolling, "the reading pause starts scrolling asynchronously")
    s = first.callFunc("fixtureRead")
    check((first.width - first.maxWidth) / s.duration <= 40 and s.cycleDuration = s.duration + 1, "the marquee moves at a readable speed and holds its ending before repeating")
    settle(Int((s.cycleDuration + 0.1) * 1000))
    check(first.callFunc("fixtureRead").pending and not first.callFunc("fixtureRead").scrolling, "a completed infinite marquee schedules another reading pause")
    settle(1100)
    check(first.callFunc("fixtureRead").scrolling, "the actual marquee starts a second pass while focus remains")
    first.repeatCount = 0
    check(not first.callFunc("fixtureRead").scrolling, "focus loss stops scrolling")
    first.repeatCount = -1
    first.repeatCount = 0
    settle(300)
    check(not first.callFunc("fixtureRead").scrolling, "focus loss cancels a pending start")
    first.repeatCount = -1
    setText(first, "Replacement title")
    ' Deliver a fire already queued before cancellation through the real handler.
    first.callFunc("fixtureScrollStart")
    settle(300)
    check(not first.callFunc("fixtureRead").scrolling, "text replacement cancels the old title's pending start")
    first.repeatCount = 0
    first.repeatCount = -1
    first.callFunc("onDestroy")
    settle(300)
    check(not first.callFunc("fixtureRead").scrolling, "disposal cancels a pending scroll start")
    check(not first.callFunc("fixtureRead").compiled, "disposal releases the compiled pattern")
    second.maxWidth = 500
    second.repeatCount = -1
    settle(1100)
    check(not second.callFunc("fixtureRead").scrolling and not second.callFunc("fixtureRead").pending, "titles that fit never start a marquee")
    for each label in [first, second, failing]
        m.scene.removeChild(label)
    end for
end sub

' The interface tokens promise readable text. These pairs are the documented
' uses in the design system; each must reach WCAG 4.5:1.
sub testTokenContrast()
    ui = m.ui
    for each role in ["text", "textSecondary", "textTertiary", "focus", "error", "warn", "success", "link"]
        check(uiContrastRatio(ui[role], ui.canvas) >= 4.5, role + " reaches 4.5:1 on the canvas")
    end for
    check(uiContrastRatio(ui.textSecondary, ui.surface) >= 4.5, "secondary text reaches 4.5:1 on surfaces")
    check(uiContrastRatio(ui.onAccent, ui.focusFill) >= 4.5, "text on the focus fill reaches 4.5:1")
    check(uiContrastRatio(ui.onAccent, ui.live) >= 4.5, "the LIVE label reaches 4.5:1 on red")
end sub
