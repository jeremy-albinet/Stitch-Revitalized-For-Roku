' Duplicate action after the real key action has hidden/disposed the wrapper.
' The production handler body and its focused-button state remain unchanged.
sub fixtureExitAgain()
    executeButtonAction()
end sub

function fixtureOverlay() as object
    return { disposed: m.disposed, visible: m.isOverlayVisible, focusedButton: m.currentFocusedButton, fadeControl: m.fadeAwayTimer.control, qualityVisible: m.qualityDialog.visible }
end function

' Supply only the focus index, then execute the actual unchanged action body.
sub fixtureDisposedAction(button as integer)
    m.currentFocusedButton = button
    executeButtonAction()
end sub
