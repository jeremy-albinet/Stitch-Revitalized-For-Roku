' Actual Chat visibility/start/completion and EmoteJob Task handlers execute.
' No socket or external HTTP request is created.
sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: {}, emoteCache: {}, fixtureProviderRequests: 0, fixtureProviderStatus: 200, fixtureProviderMalformed: false, fixtureProviderTimeout: false, fixtureProviderNoSet: false })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()
    cases = [
        { name: "optional404", status: 404, complete: true }
        { name: "malformed200", status: 200, complete: false }
        { name: "unavailable503", status: 503, complete: false }
        { name: "timeout", status: 200, complete: false }
        { name: "empty200", status: 200, complete: true }
        { name: "7tvNoSet", status: 200, complete: true }
    ]
    for each sample in cases
        m.global.fixtureProviderRequests = 0
        m.global.fixtureProviderStatus = sample.status
        m.global.fixtureProviderMalformed = sample.name = "malformed200"
        m.global.fixtureProviderTimeout = sample.name = "timeout"
        m.global.fixtureProviderNoSet = sample.name = "7tvNoSet"
        chat = createObject("roSGNode", "Chat")
        chat.visible = false
        m.scene.appendChild(chat)
        chat.channel_id = "42"
        chat.channel = sample.name
        check(chat.callFunc("fixtureRead").emote = invalid, "hidden Chat starts no emote task")
        chat.visible = true
        waitEmotes(chat, 6)
        state = chat.callFunc("fixtureRead")
        check(m.global.fixtureProviderRequests = 6, sample.name + " runs all production providers once")
        if sample.complete
            check(state.cached = sample.name, sample.name + " completes and remembers its cache")
        else
            check(state.cached = "", sample.name + " stays retryable after completion")
        end if
        chat.visible = false
        settle(40)
        check(chat.callFunc("fixtureRead").emote = invalid, "hide releases the emote worker")
        m.global.fixtureProviderStatus = 200
        m.global.fixtureProviderMalformed = false
        m.global.fixtureProviderTimeout = false
        chat.visible = true
        expected = 6
        if not sample.complete then expected = 12
        waitEmotes(chat, expected)
        settle(80)
        check(m.global.fixtureProviderRequests = expected, sample.name + " hide/show only refetches incomplete caches")
        check(chat.callFunc("fixtureRead").cached = sample.name, sample.name + " retains or recovers its cache")
        chat.visible = false
        settle(40)
        chat.visible = true
        settle(80)
        check(chat.callFunc("fixtureRead").emote = invalid and m.global.fixtureProviderRequests = expected, sample.name + " completed cache creates no second task on later reopen")
        chat.callFunc("onDestroy")
        m.scene.removeChild(chat)
    end for
    fixtureEnd()
end sub

sub waitEmotes(chat as object, expected as integer)
    clock = createObject("roTimespan")
    while clock.totalMilliseconds() < 4000
        if m.global.fixtureProviderRequests >= expected and chat.callFunc("fixtureRead").emote = invalid then return
        pump(20)
    end while
    fail("emote task did not complete")
end sub
