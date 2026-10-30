' Helpers for pages that own a StatusPanel child (id "status") beside a
' RowList (m.rowlist). Action ids map to localized labels; each host
' implements onStatusAction(actionId) and calls releasePageStatus() from its
' onDestroy. The panel's own cleanup runs through disposeNodeTree.

sub initPageStatus()
    m.statusActionIds = []
    m.status = m.top.findNode("status")
    if m.status <> invalid then m.status.observeField("actionSelected", "onStatusActionSelected")
end sub

sub setPageStatus(state as string, title = "" as string, message = "" as string, actionIds = [] as object)
    if m.status = invalid then return
    statusHadFocus = m.status.isInFocusChain()
    m.statusActionIds = actionIds
    labels = []
    for each actionId in actionIds
        labels.push(statusActionLabel(actionId))
    end for
    m.status.title = title
    m.status.message = message
    m.status.actions = labels
    m.status.state = state
    if labels.count() = 0
        ' Hidden or loading panels cannot hold focus; return it to the content.
        if statusHadFocus and m.rowlist <> invalid then m.rowlist.setFocus(true)
    else if m.top.isInFocusChain()
        m.status.setFocus(true)
    end if
end sub

sub hidePageStatus()
    setPageStatus("hidden")
end sub

function statusActionLabel(actionId as string) as string
    if actionId = "retry" then return tr("Try again")
    if actionId = "back" then return tr("Back")
    if actionId = "browse" then return tr("Go to Browse")
    return actionId
end function

function selectedStatusAction() as string
    if m.status = invalid or m.statusActionIds = invalid then return ""
    index = m.status.actionSelected
    if index < 0 or index >= m.statusActionIds.count() then return ""
    return m.statusActionIds[index]
end function

sub onStatusActionSelected()
    if m.disposed then return
    actionId = selectedStatusAction()
    if actionId <> "" then onStatusAction(actionId)
end sub

' While the panel offers actions, focus given to the page goes to it instead
' of the empty RowList. Returns true when the panel owns page focus.
function focusStatusIfActive() as boolean
    if m.status = invalid or not m.status.visible or not m.status.hasActions then return false
    if m.top.hasFocus() then m.status.setFocus(true)
    return true
end function

sub releasePageStatus()
    if m.status <> invalid then m.status.unobserveField("actionSelected")
end sub
