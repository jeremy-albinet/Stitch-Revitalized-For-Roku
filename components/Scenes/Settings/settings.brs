sub init()
    m.disposed = false
    m.top.observeField("focusedChild", "onGetFocus")
    m.top.overhangTitle = tr("Settings")
    m.top.optionsAvailable = false

    m.userLocation = []

    m.settingsMenu = m.top.findNode("settingsMenu")
    m.sectionTitle = m.top.findNode("sectionTitle")
    m.settingDetail = m.top.findNode("settingDetail")
    m.settingTag = m.top.findNode("settingTag")
    m.settingTitle = m.top.findNode("settingTitle")
    m.settingDesc = m.top.findNode("settingDesc")
    m.settingValue = m.top.findNode("settingValue")
    m.supportQrPoster = m.top.findNode("supportQrPoster")
    m.optionList = m.top.findNode("optionList")
    m.scrollTrack = m.top.findNode("scrollTrack")
    m.scrollThumb = m.top.findNode("scrollThumb")
    m.scrollPosition = m.top.findNode("scrollPosition")

    m.keyboardDialog = invalid
    m.keyboardItem = invalid
    m.signOutDialog = invalid
    m.healthCheckTask = invalid
    m.pendingProxySave = invalid
    m.optionSetting = invalid
    applyDetailStyle()

    m.settingsMenu.observeField("itemFocused", "settingFocused")
    m.settingsMenu.observeField("itemSelected", "settingSelected")
    m.optionList.observeField("checkedItem", "optionChanged")

    m.configTree = GetConfigTree()
    LoadMenu({ children: m.configTree })
    m.settingsMenu.setFocus(true)
end sub

sub applyDetailStyle()
    ui = m.global?.constants?.ui
    if ui = invalid then return
    font = CreateObject("roSGNode", "Font")
    font.uri = ui.font.regular
    font.size = ui.type.body
    m.optionList.font = font
    m.optionList.focusedFont = font
    m.settingTag.text = tr("Experimental")
end sub

sub onGetFocus()
    if m.disposed then return
    ' Focus given to the page itself goes to the list of settings.
    if m.top.hasFocus() then m.settingsMenu.setFocus(true)
end sub

sub LoadMenu(configSection)
    if configSection.children = invalid
        m.userLocation.pop()
        configSection = m.userLocation.peek()
    else
        if m.userLocation.Count() > 0 then m.userLocation.peek().selectedIndex = m.settingsMenu.itemFocused
        m.userLocation.push(configSection)
    end if

    result = CreateObject("roSGNode", "ContentNode")
    for each item in configSection.children
        listItem = result.CreateChild("ContentNode")
        listItem.title = settingTitle(item)
        listItem.shortDescriptionLine1 = settingValueText(item)
        if item.settingName <> invalid
            listItem.id = item.settingName
        else if item.id <> invalid
            listItem.id = item.id
        end if
    end for

    m.settingsMenu.content = result

    selectedIndex = 0
    if configSection.selectedIndex <> invalid and configSection.selectedIndex >= 0 and configSection.selectedIndex < result.getChildCount() then selectedIndex = configSection.selectedIndex
    if result.getChildCount() > 0 then m.settingsMenu.jumpToItem = selectedIndex
    title = tr("Settings")
    for i = 1 to m.userLocation.count() - 1
        title += " / " + tr(m.userLocation[i].title)
    end for
    m.sectionTitle.text = title
    settingFocused()
end sub

function focusedSetting() as dynamic
    section = m.userLocation.peek()
    if section = invalid or section.children = invalid then return invalid
    index = m.settingsMenu.itemFocused
    if index < 0 then index = 0
    return section.children[index]
end function

function isSignedIn() as boolean
    return get_setting("active_user", "$default$") <> "$default$"
end function

function accountName() as string
    name = get_user_setting("display_name", "")
    if name = invalid or name = "" then name = get_user_setting("login", "")
    if name = invalid then name = ""
    return name
end function

' The stored value, or the schema default when nothing is stored. Reading for
' display does not write the default to the registry.
function currentSettingValue(item as object) as dynamic
    value = invalid
    user = get_setting("active_user")
    if user <> invalid and item.settingName <> invalid then value = registry_read(item.settingName, user)
    if value = invalid then value = item.default
    return value
end function

' The logout entry doubles as the account row: Sign out when signed in,
' account status when signed out.
function settingTitle(item as object) as string
    if item.action = "logout" and not isSignedIn() then return tr("Account")
    return tr(item.title)
end function

function settingDescription(item as object) as string
    if item.action = "logout"
        if not isSignedIn() then return tr("Not signed in. Use the account button at the top right to sign in. Signing in is optional.")
        return Substitute(tr("Signed in as {0}."), accountName()) + " " + tr(item.description)
    end if
    if item.description = invalid then return ""
    return tr(item.description)
end function

' Text shown beside each setting name in the list.
function settingValueText(item as object) as string
    if item.children <> invalid then return tr("Open")
    if item.type = invalid then return ""
    if item.type = "action"
        if item.action <> "logout" then return ""
        if isSignedIn() then return accountName()
        return tr("Not signed in")
    end if
    value = currentSettingValue(item)
    if item.type = "bool"
        if value = "true" then return tr("On")
        return tr("Off")
    else if LCase(item.type) = "radio"
        option = findOption(item, value)
        if option <> invalid then return tr(option.title)
        if GetInterface(value, "ifString") <> invalid then return value
        return ""
    else if item.type = "text"
        if GetInterface(value, "ifString") = invalid or value = "" then return tr("Not set")
        return value
    end if
    return ""
end function

function findOption(item as object, value as dynamic) as dynamic
    if item.options = invalid or GetInterface(value, "ifString") = invalid then return invalid
    for each option in item.options
        if option.id = value then return option
    end for
    return invalid
end function

' Off/On for bool settings (stored "false"/"true"), otherwise the schema options.
function optionChoices(item as object) as object
    if item.type = "bool"
        return [{ title: tr("Off"), id: "false" }, { title: tr("On"), id: "true" }]
    end if
    choices = []
    if item.options = invalid then return choices
    for each option in item.options
        choices.push({ title: tr(option.title), id: option.id })
    end for
    return choices
end function

sub settingFocused()
    if m.disposed then return
    updateScrollIndicator()
    item = focusedSetting()
    if item = invalid then return
    m.settingTag.visible = item.experimental = true
    m.settingTitle.text = settingTitle(item)
    m.settingDesc.text = settingDescription(item)
    m.settingValue.visible = false
    m.supportQrPoster.visible = false
    m.optionList.visible = false
    m.optionSetting = invalid

    if item.type = invalid
        return
    else if item.type = "bool" or LCase(item.type) = "radio"
        showOptions(item)
    else if item.type = "text"
        m.settingValue.text = Substitute(tr("Current: {0}"), settingValueText(item))
        m.settingValue.visible = true
    else if item.type = "action" and item.action = "support_stitch"
        m.supportQrPoster.visible = true
    else if item.type <> "action"
        print "Unknown setting type " + item.type
    end if
end sub

' Track focus through the list without changing its native scroll or focus.
sub updateScrollIndicator()
    count = 0
    if m.settingsMenu.content <> invalid then count = m.settingsMenu.content.getChildCount()
    rows = m.settingsMenu.numRows
    scrollable = rows > 0 and count > rows
    m.scrollTrack.visible = scrollable
    m.scrollPosition.visible = scrollable
    if not scrollable then return
    focused = m.settingsMenu.itemFocused
    if focused < 0 then focused = 0
    if focused >= count then focused = count - 1
    height = m.scrollTrack.height * rows / count
    if height < 24 then height = 24
    m.scrollThumb.height = height
    m.scrollThumb.translation = [0, (m.scrollTrack.height - height) * focused / (count - 1)]
    m.scrollPosition.text = Substitute(tr("{0} of {1}"), (focused + 1).toStr(), count.toStr())
end sub

' The options are visible with the current choice checked; OK moves focus in.
sub showOptions(item as object)
    choices = optionChoices(item)
    value = currentSettingValue(item)
    content = CreateObject("roSGNode", "ContentNode")
    checked = -1
    for i = 0 to choices.count() - 1
        node = content.CreateChild("ContentNode")
        node.title = choices[i].title
        node.id = choices[i].id
        if choices[i].id = value then checked = i
    end for
    m.optionList.content = content
    if checked >= 0 then m.optionList.checkedItem = checked
    m.optionSetting = item
    m.optionList.visible = true
end sub

sub settingSelected()
    if m.disposed then return
    selectedItem = focusedSetting()
    if selectedItem = invalid then return

    if selectedItem.type <> invalid
        if selectedItem.type = "bool" or LCase(selectedItem.type) = "radio"
            if m.optionSetting = invalid then showOptions(selectedItem)
            if m.optionList.checkedItem >= 0 then m.optionList.jumpToItem = m.optionList.checkedItem
            m.optionList.setFocus(true)
        else if selectedItem.type = "text"
            showTextKeyboard(selectedItem)
        else if selectedItem.type = "action"
            if selectedItem.action = "logout"
                ' The signed-out account row is information only.
                if isSignedIn() then confirmSignOut()
            else if selectedItem.action = "support_stitch"
                m.supportQrPoster.visible = true
            else
                print "Unknown action: " + selectedItem.action
            end if
        end if
    else if selectedItem.children <> invalid and selectedItem.children.Count() > 0
        LoadMenu(selectedItem)
        m.settingsMenu.setFocus(true)
    end if
end sub

' Saves a choice the user made in the focused option list.
sub optionChanged()
    if m.disposed or not m.optionList.hasFocus() then return
    item = m.optionSetting
    if item = invalid or m.optionList.content = invalid then return
    option = m.optionList.content.getChild(m.optionList.checkedItem)
    if option = invalid then return
    if item.settingName = "analytics.enabled"
        set_user_setting("analytics.consentVersion", "1")
    end if
    set_user_setting(item.settingName, option.id)
    refreshFocusedValue()
end sub

sub refreshFocusedValue()
    item = focusedSetting()
    if item = invalid or m.settingsMenu.content = invalid then return
    row = m.settingsMenu.content.getChild(m.settingsMenu.itemFocused)
    if row <> invalid then row.shortDescriptionLine1 = settingValueText(item)
    if item.type = "text"
        m.settingValue.text = Substitute(tr("Current: {0}"), settingValueText(item))
    end if
end sub

sub showTextKeyboard(selectedItem as object)
    if m.keyboardDialog <> invalid then return
    currentVal = currentSettingValue(selectedItem)
    if GetInterface(currentVal, "ifString") = invalid then currentVal = ""

    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = tr(selectedItem.title)
    dialog.text = currentVal
    dialog.buttons = [tr("Save"), tr("Cancel")]
    applyDialogPalette(dialog)
    dialog.observeField("buttonSelected", "onKeyboardButtonSelected")
    dialog.observeField("wasClosed", "onKeyboardClosed")
    m.keyboardDialog = dialog
    m.keyboardItem = selectedItem

    scene = m.top.getScene()
    if scene <> invalid then scene.dialog = dialog
end sub

sub onKeyboardButtonSelected()
    if m.disposed or m.keyboardDialog = invalid then return

    if m.keyboardDialog.buttonSelected = 0 ' Save
        selectedSetting = m.keyboardItem
        newVal = m.keyboardDialog.text.trim()

        ' The demux service address is saved only after its /health check
        ' passes. Empty turns the service off and needs no check.
        if selectedSetting.settingName = "proxy.url" and newVal <> ""
            startProxyHealthCheck(selectedSetting, newVal)
            return
        end if

        set_user_setting(selectedSetting.settingName, newVal)
        refreshFocusedValue()
    end if

    closeKeyboardDialog()
end sub

' Back in the keyboard cancels like the Cancel button, including any check.
sub onKeyboardClosed()
    if m.disposed or m.keyboardDialog = invalid then return
    closeKeyboardDialog()
end sub

sub closeKeyboardDialog()
    dialog = m.keyboardDialog
    m.keyboardDialog = invalid
    m.keyboardItem = invalid
    ' Cancel any in-flight health check so its result does not save the URL
    ' after the user has already dismissed or cancelled the dialog.
    m.healthCheckTask = destroyTask(m.healthCheckTask, "result")
    m.pendingProxySave = invalid
    if dialog <> invalid
        dialog.unobserveField("buttonSelected")
        dialog.unobserveField("wasClosed")
        dialog.close = true
        clearSceneDialog(dialog)
    end if
    if not m.disposed then m.settingsMenu.setFocus(true)
end sub

sub clearSceneDialog(dialog as object)
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        if scene.dialog.isSameNode(dialog) then scene.dialog = invalid
    end if
end sub

sub setKeyboardStatus(text as string)
    if m.keyboardDialog <> invalid then m.keyboardDialog.message = [text]
end sub

' One check at a time: the same address is not checked twice, and a new
' address replaces a check that has not answered yet.
sub startProxyHealthCheck(selectedSetting as object, newVal as string)
    if m.healthCheckTask <> invalid
        if m.pendingProxySave <> invalid and m.pendingProxySave.value = newVal then return
        m.healthCheckTask = destroyTask(m.healthCheckTask, "result")
    end if

    m.pendingProxySave = {
        settingName: selectedSetting.settingName,
        value: newVal
    }
    setKeyboardStatus(tr("Checking the service…"))

    m.healthCheckTask = CreateObject("roSGNode", "ProxyHealthCheck")
    m.healthCheckTask.proxyUrl = newVal
    m.healthCheckTask.observeField("result", "onProxyHealthResult")
    m.healthCheckTask.control = "run"
end sub

sub onProxyHealthResult()
    if m.disposed or m.healthCheckTask = invalid then return

    result = m.healthCheckTask.result
    m.healthCheckTask = destroyTask(m.healthCheckTask, "result")

    pending = m.pendingProxySave
    m.pendingProxySave = invalid
    if pending = invalid or m.keyboardDialog = invalid then return

    ' The address shown must be the one that was checked.
    if m.keyboardDialog.text.trim() <> pending.value
        setKeyboardStatus(tr("The address changed. Press Save to check it."))
        return
    end if

    if not healthCheckPassed(result)
        setKeyboardStatus(healthCheckFailureText(result))
        return
    end if

    set_user_setting(pending.settingName, pending.value)
    refreshFocusedValue()
    closeKeyboardDialog()
end sub

function healthCheckPassed(result as dynamic) as boolean
    if type(result) <> "roAssociativeArray" then return false
    if GetInterface(result.ok, "ifBoolean") = invalid then return false
    return result.ok
end function

function healthCheckFailureText(result as dynamic) as string
    reason = invalid
    if type(result) = "roAssociativeArray" then reason = result.message
    if GetInterface(reason, "ifString") = invalid or reason = ""
        return tr("Couldn't check the service. Try again.")
    end if
    return Substitute(tr("Couldn't reach the service: {0}. Check the address and that the service is running."), reason)
end function

sub confirmSignOut()
    if m.signOutDialog <> invalid then return
    dialog = createSignOutDialog()
    dialog.observeField("buttonSelected", "onSignOutChoice")
    dialog.observeField("wasClosed", "onSignOutClosed")
    m.signOutDialog = dialog
    scene = m.top.getScene()
    if scene <> invalid then scene.dialog = dialog
end sub

sub onSignOutChoice()
    if m.disposed or m.signOutDialog = invalid then return
    confirmed = m.signOutDialog.buttonSelected = 0
    closeSignOutDialog()
    if confirmed
        performLogout()
    else
        m.settingsMenu.setFocus(true)
    end if
end sub

sub onSignOutClosed()
    if m.disposed or m.signOutDialog = invalid then return
    closeSignOutDialog()
    m.settingsMenu.setFocus(true)
end sub

sub closeSignOutDialog()
    dialog = m.signOutDialog
    if dialog = invalid then return
    m.signOutDialog = invalid
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    clearSceneDialog(dialog)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" or key = "left" or key = "up"
        if m.optionList.isInFocusChain()
            m.settingsMenu.setFocus(true)
            return true
        end if
        if m.settingsMenu.isInFocusChain() and m.userLocation.Count() > 1
            LoadMenu({})
            return true
        end if
    end if
    if key = "back" or key = "up"
        m.top.backPressed = true
        return true
    end if
    if key = "right" and m.settingsMenu.isInFocusChain()
        settingSelected()
        return true
    end if
    return false
end function

' Keeps preferences and the anonymous device identity (signOutAccount).
sub performLogout()
    signOutAccount()
    m.top.finished = true
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.lastFocus = invalid
    m.top.unobserveField("focusedChild")
    m.settingsMenu.unobserveField("itemFocused")
    m.settingsMenu.unobserveField("itemSelected")
    m.optionList.unobserveField("checkedItem")
    if m.keyboardDialog <> invalid
        m.keyboardDialog.unobserveField("buttonSelected")
        m.keyboardDialog.unobserveField("wasClosed")
        clearSceneDialog(m.keyboardDialog)
        m.keyboardDialog = invalid
    end if
    closeSignOutDialog()
    m.keyboardItem = invalid
    m.healthCheckTask = destroyTask(m.healthCheckTask, "result")
    m.pendingProxySave = invalid
end sub
