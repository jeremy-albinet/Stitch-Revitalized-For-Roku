function fixtureRead() as object
    return { menu: m.settingsMenu, options: m.optionList, task: m.healthCheckTask, pending: m.pendingProxySave, keyboard: m.keyboardDialog, dialog: m.signOutDialog, disposed: m.disposed, levels: m.userLocation.count() }
end function
sub fixtureFocus(index as integer)
    m.settingsMenu.jumpToItem = index
    settingFocused()
end sub
sub fixtureSelect()
    settingSelected()
end sub
sub fixtureOptionChanged()
    optionChanged()
end sub
function fixtureHealthPassed(value as dynamic) as boolean
    return healthCheckPassed(value)
end function
function fixtureFailureText(value as dynamic) as string
    return healthCheckFailureText(value)
end function
sub fixtureHierarchy(section as object)
    LoadMenu(section)
end sub
