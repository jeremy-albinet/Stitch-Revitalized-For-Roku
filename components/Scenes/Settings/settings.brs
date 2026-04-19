sub init()
    m.top.observeField("focusedChild", "onGetFocus")
    m.top.overhangTitle = tr("Settings")
    m.top.optionsAvailable = false

    m.userLocation = []

    m.categoryList = m.top.findNode("categoryList")
    m.settingsMenu = m.top.findNode("settingsMenu")
    m.settingsMenu.focusBitmapBlendColor = m.global.constants.colors.twitch.purple9
    m.settingsMenu.focusedColor = m.global.constants.colors.white

    m.settingDetail = m.top.findNode("settingDetail")
    m.settingDesc = m.top.findNode("settingDesc")
    m.settingTitle = m.top.findNode("settingTitle")

    m.boolSetting = m.top.findNode("boolSetting")
    m.radioSetting = m.top.findNode("radioSetting")

    m.keyboardDialog = invalid
    m.healthCheckTask = invalid
    m.pendingProxySave = invalid

    ' Derive numRows from screen resolution so scrolling works on any Roku
    ' itemSize height=50, itemSpacing=5 → 55px per row
    ' Available: screenHeight - 80 (overhang) - 10 (list y offset)
    screenHeight = m.top.getScene().currentDesignResolution.height
    m.settingsMenu.numRows = Int((screenHeight - 80 - 10) / 55)

    m.categoryList.setFocus(true)

    m.settingsMenu.observeField("itemFocused", "settingFocused")
    m.settingsMenu.observeField("itemSelected", "settingSelected")
    m.settingsMenu.observeField("focusedChild", "onGetFocus")

    m.boolSetting.observeField("checkedItem", "boolSettingChanged")
    m.radioSetting.observeField("checkedItem", "radioSettingChanged")

    m.configTree = GetConfigTree()
    if get_setting("active_user", "$default$") = "$default$"
        filteredTree = []
        for each item in m.configTree
            if item.action <> "logout"
                filteredTree.push(item)
            end if
        end for
        m.configTree = filteredTree
    end if
    LoadMenu({ children: m.configTree })
end sub

sub onGetFocus()
    if m.settingDetail.focusedChild = invalid
        if not m.radioSetting.hasFocus()
            m.settingDesc.visible = true
            m.settingsMenu.setFocus(true)
        end if
    end if
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
        listItem.title = tr(item.title)
        listItem.Description = tr(item.description)
        listItem.id = item.id
    end for

    m.settingsMenu.content = result

    if configSection.selectedIndex <> invalid and configSection.selectedIndex > -1
        m.settingsMenu.jumpToItem = configSection.selectedIndex
    end if
end sub

sub settingFocused()
    selectedSetting = m.userLocation.peek().children[m.settingsMenu.itemFocused]
    m.settingDesc.text = tr(selectedSetting.Description)
    m.settingTitle.text = tr(selectedSetting.Title)

    m.boolSetting.visible = false
    m.radioSetting.visible = false

    if selectedSetting.type = invalid
        return
    else if selectedSetting.type = "text"
        ' Just show current value in description — keyboard opens on select
        currentVal = get_user_setting(selectedSetting.settingName, "")
        if currentVal = ""
            m.settingDesc.text = tr(selectedSetting.Description)
        else
            m.settingDesc.text = tr(selectedSetting.Description) + chr(10) + chr(10) + "Current: " + currentVal
        end if
    else if selectedSetting.type = "bool"
        m.boolSetting.visible = true
        if get_user_setting(selectedSetting.settingName) = "true"
            m.boolSetting.checkedItem = 1
        else
            m.boolSetting.checkedItem = 0
        end if
    else if LCase(selectedSetting.type) = "radio"
        selectedValue = get_user_setting(selectedSetting.settingName)
        radioContent = CreateObject("roSGNode", "ContentNode")
        itemIndex = 0
        for each item in m.userLocation.peek().children[m.settingsMenu.itemFocused].options
            listItem = radioContent.CreateChild("ContentNode")
            listItem.title = tr(item.title)
            listItem.id = item.id
            if selectedValue = item.id
                m.radioSetting.checkedItem = itemIndex
            end if
            itemIndex++
        end for
        m.radioSetting.content = radioContent
    else if selectedSetting.type = "action"
        m.boolSetting.visible = false
        m.radioSetting.visible = false
    else
        print "Unknown setting type " + selectedSetting.type
    end if
end sub

sub settingSelected()
    selectedItem = m.userLocation.peek().children[m.settingsMenu.itemFocused]

    if selectedItem.type <> invalid
        if selectedItem.type = "bool"
            m.boolSetting.setFocus(true)
        else if selectedItem.type = "radio"
            m.settingDesc.visible = false
            m.radioSetting.visible = true
            m.radioSetting.setFocus(true)
        else if selectedItem.type = "text"
            showTextKeyboard(selectedItem)
        else if selectedItem.type = "action"
            if selectedItem.action = "logout"
                performLogout()
            end if
        end if
    else if selectedItem.children <> invalid and selectedItem.children.Count() > 0
        LoadMenu(selectedItem)
        m.settingsMenu.setFocus(true)
    end if

    m.settingDesc.text = m.settingsMenu.content.GetChild(m.settingsMenu.itemFocused).Description
end sub

sub showTextKeyboard(selectedItem as object)
    currentVal = get_user_setting(selectedItem.settingName, "")

    m.keyboardDialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    m.keyboardDialog.title = tr(selectedItem.title)
    m.keyboardDialog.text = currentVal
    m.keyboardDialog.buttons = ["Save", "Cancel"]
    m.keyboardDialog.observeField("buttonSelected", "onKeyboardButtonSelected")

    m.top.getScene().dialog = m.keyboardDialog
end sub

sub onKeyboardButtonSelected()
    if m.keyboardDialog = invalid then return

    if m.keyboardDialog.buttonSelected = 0 ' Save
        selectedSetting = m.userLocation.peek().children[m.settingsMenu.itemFocused]
        newVal = m.keyboardDialog.text.trim()

        ' For proxy.url, validate the endpoint with a /health probe before saving.
        ' Empty string means "disable proxy" and bypasses the check.
        if selectedSetting.settingName = "proxy.url" and newVal <> ""
            startProxyHealthCheck(selectedSetting, newVal)
            return
        end if

        set_user_setting(selectedSetting.settingName, newVal)
        ' Refresh description to show new value
        settingFocused()
    end if

    closeKeyboardDialog()
end sub

sub closeKeyboardDialog()
    if m.keyboardDialog = invalid then return
    m.keyboardDialog.close = true
    m.keyboardDialog.unobserveField("buttonSelected")
    m.keyboardDialog = invalid
    ' Cancel any in-flight health check so its result does not save the URL
    ' after the user has already dismissed or cancelled the dialog.
    if m.healthCheckTask <> invalid
        m.healthCheckTask.unobserveField("result")
        m.healthCheckTask.control = "stop"
        m.healthCheckTask = invalid
    end if
    m.pendingProxySave = invalid
    m.settingsMenu.setFocus(true)
end sub

sub startProxyHealthCheck(selectedSetting as object, newVal as string)
    ' Guard against concurrent health checks if the user somehow re-triggers.
    if m.healthCheckTask <> invalid then return

    m.pendingProxySave = {
        settingName: selectedSetting.settingName,
        value: newVal
    }

    if m.keyboardDialog <> invalid
        m.keyboardDialog.title = tr("Testing connection...")
    end if

    m.healthCheckTask = CreateObject("roSGNode", "ProxyHealthCheck")
    m.healthCheckTask.proxyUrl = newVal
    m.healthCheckTask.observeField("result", "onProxyHealthResult")
    m.healthCheckTask.control = "run"
end sub

sub onProxyHealthResult()
    if m.healthCheckTask = invalid then return

    result = m.healthCheckTask.result
    m.healthCheckTask.unobserveField("result")
    m.healthCheckTask = invalid

    pending = m.pendingProxySave
    m.pendingProxySave = invalid

    if result = invalid
        if m.keyboardDialog <> invalid
            m.keyboardDialog.title = tr("Error: unknown failure. Try again.")
        end if
        return
    end if

    if result.ok <> true
        if m.keyboardDialog <> invalid
            reason = result.message
            if reason = invalid or reason = "" then reason = tr("Proxy not reachable")
            m.keyboardDialog.title = tr("Error: ") + reason
        end if
        return
    end if

    if pending <> invalid
        set_user_setting(pending.settingName, pending.value)
        settingFocused()
    end if

    closeKeyboardDialog()
end sub

sub boolSettingChanged()
    if m.boolSetting.focusedChild = invalid then return
    selectedSetting = m.userLocation.peek().children[m.settingsMenu.itemFocused]
    if m.boolSetting.checkedItem
        set_user_setting(selectedSetting.settingName, "true")
    else
        set_user_setting(selectedSetting.settingName, "false")
    end if
end sub

sub radioSettingChanged()
    if m.radioSetting.focusedChild = invalid then return
    selectedSetting = m.userLocation.peek().children[m.settingsMenu.itemFocused]
    set_user_setting(selectedSetting.settingName, m.radioSetting.content.getChild(m.radioSetting.checkedItem).id)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if (key = "back" or key = "left") and m.settingsMenu.focusedChild <> invalid and m.userLocation.Count() > 1
        LoadMenu({})
        return true
    else if (key = "back" or key = "left") and m.settingDetail.focusedChild <> invalid
        m.settingsMenu.setFocus(true)
        return true
    else if (key = "back" or key = "left") and m.radioSetting.hasFocus()
        m.settingsMenu.setFocus(true)
        return true
    else if key = "back"
        m.top.backPressed = true
        return true
    end if
    if key = "right" or key = "OK"
        settingSelected()
    end if
    if key = "up"
        m.top.backPressed = true
        return true
    end if
    return false
end function

sub performLogout()
    active_user = get_setting("active_user", "$default$")
    if active_user <> "$default$"
        NukeRegistry(active_user)
        set_setting("active_user", "$default$")
    else
        for each key in getRegistryKeys("$default$")
            if key <> "temp_device_code" and key <> "device_code"
                unset_user_setting(key)
            end if
        end for
    end if
    m.top.finished = true
end sub

sub onDestroy()
    m.top.unobserveField("focusedChild")
    m.settingsMenu.unobserveField("itemFocused")
    m.settingsMenu.unobserveField("itemSelected")
    m.settingsMenu.unobserveField("focusedChild")
    m.boolSetting.unobserveField("checkedItem")
    m.radioSetting.unobserveField("checkedItem")
    if m.keyboardDialog <> invalid
        m.keyboardDialog.unobserveField("buttonSelected")
        m.keyboardDialog = invalid
    end if
    if m.healthCheckTask <> invalid
        m.healthCheckTask.unobserveField("result")
        m.healthCheckTask.control = "stop"
        m.healthCheckTask = invalid
    end if
end sub
