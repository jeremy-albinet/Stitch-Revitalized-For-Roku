function fixtureRead() as object
    return { items: m.items, index: m.currentIndex, caption: m.caption, task: m.liveStatusTask }
end function

function fixtureKey(key as string) as boolean
    return onKeyEvent(key, true)
end function

sub fixtureRefresh()
    onRefreshTimer()
end sub
