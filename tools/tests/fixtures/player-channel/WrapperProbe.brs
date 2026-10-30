function fixtureOverlay() as object
    return { disposed: m.disposed, visible: m.isOverlayVisible, focused: m.currentFocusedButton, fade: m.fadeAwayTimer.control, preview: m.isSeekMode, position: m.currentPositionSeconds }
end function

sub fixtureRepeatAction()
    executeButtonAction()
end sub
