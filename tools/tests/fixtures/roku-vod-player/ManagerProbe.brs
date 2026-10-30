' Inspection/direct dispatch only; the production owner handlers are unchanged.
function fixtureRead() as object
    return { worker: m.worker, video: m.video, id: m.currentId, descriptor: m.currentDescriptor, pending: m.pending, stopping: m.stopping, disposed: m.disposed }
end function

sub fixtureCleanupTimeout()
    m.cleanupClock = { TotalMilliseconds: function() as integer
        return 15000
    end function }
    onCleanupTick()
end sub
