function fixtureParts() as object
    return m.components.getChildren(-1, 0)
end function

function fixtureBuilds() as integer
    if m.fixtureBuilds = invalid then return 0
    return m.fixtureBuilds
end function

sub fixtureScrollStart()
    onScrollStart()
end sub

function fixtureScrollState() as object
    return { pending: m.scrollStartPending = true, scrolling: m.animation.control = "start", duration: m.animation.duration, cycleDuration: m.timer.duration, target: m.vector.keyValue[1][0] }
end function

sub fixtureImageStatus(poster as object, status as string)
    onEmojiImageStatus({ node: poster, status: status, getRoSGNode: fixtureEventNode, getData: fixtureEventData })
end sub

function fixtureEventNode() as object
    return m.node
end function

function fixtureEventData() as string
    return m.status
end function
