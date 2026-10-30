function fixtureSeekRead() as object
    return { preview: m.isSeekMode, position: m.currentPositionSeconds, wasPlaying: m.preSeekWasPlaying }
end function

sub fixturePreview(seconds as integer)
    seekRelative(seconds)
end sub

sub fixtureApplyPreview()
    applySeekPreview()
end sub

sub fixtureCancelPreview()
    cancelSeekPreview()
end sub
