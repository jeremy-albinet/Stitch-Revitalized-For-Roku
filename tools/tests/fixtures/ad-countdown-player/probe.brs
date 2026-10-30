' Read-only inspection and native-I/O boundary injection. Every operation under
' test goes through unchanged production handlers and real SceneGraph nodes.
function fixtureAdRead() as object
    badge = m.adBadge
    return {owner: m.adOwner, bounds: m.adBounds.Count(), utc: m.adLastUtc, badgeVisible: badge.visible, title: badge.findNode("adTitle").text, time: badge.findNode("adTime").text, x: badge.translation[0], width: badge.findNode("plate").width, disposed: m.disposed}
end function

function fixtureAdOwnerRead() as object
    response = invalid
    count = 0
    closedType = "invalid"
    cleanupType = "invalid"
    if m.worker <> invalid
        response = m.worker.response
        if type(response) = "roAssociativeArray"
            count = response.Count()
            closedType = type(response.closed)
            cleanupType = type(response.cleanupOk)
        end if
    end if
    return {owner: m.owner, worker: m.worker, video: m.video, pending: m.pending, stopping: m.stopping, acknowledged: m.acknowledged, timerControl: m.timer.control, disposed: m.disposed, response: response, responseCount: count, closedType: closedType, cleanupType: cleanupType}
end function

sub fixtureDeliverAd(response as dynamic)
    if m.worker = invalid then return
    m.worker.response = response
end sub

sub fixtureWorkerMode(mode as string)
    if m.worker <> invalid then m.worker.fixtureMode = mode
end sub

sub fixtureExpireAdCleanup()
    m.cleanupClock = {TotalMilliseconds: fixtureExpiredClock}
    onAdCleanupTick()
end sub

function fixtureExpiredClock() as integer
    return 5000
end function
