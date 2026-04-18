' Fire-and-forget task that writes one entry to the recently watched registry.
' Offloads registry I/O off the render thread.

sub init()
    m.top.functionName = "addEntry"
end sub

sub addEntry()
    RW_Add(m.top.entry)
    m.top.control = "STOP"
end sub
