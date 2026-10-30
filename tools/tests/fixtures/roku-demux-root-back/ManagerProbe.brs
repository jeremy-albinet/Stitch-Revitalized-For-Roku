function fixtureManager() as object
    return { worker: m.worker, currentId: m.currentId, pending: m.pending, video: m.video, stopping: m.stopping, disposed: m.disposed, cleanupClock: m.cleanupClock, blockedPendingId: m.blockedPendingId }
end function

sub fixtureTimeout()
    m.cleanupClock = { TotalMilliseconds: function() as integer
        return 15000
    end function }
    onCleanupTick()
end sub
