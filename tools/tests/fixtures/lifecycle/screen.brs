sub init()
    m.disposed = false
    m.timer = m.top.findNode("timer")
    m.timer.observeField("fire", "tick")
    m.timer.control = "start"
    ' Force an actual owned EmojiLabel timer to run before permanent disposal.
    labelTimer = m.top.findNode("label").findNode("timer")
    labelTimer.duration = 0.05
    labelTimer.control = "start"
end sub

sub tick()
    m.top.ticks += 1
end sub

sub touch()
    m.top.touches += 1
end sub

' Derived cleanup is invoked in the target component's script context.
sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.cleanupCalls += 1
    m.timer.control = "stop"
    m.timer.unobserveField("fire")
end sub
