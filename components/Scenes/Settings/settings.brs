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
    LoadMenu({ children: m.configTree })
end sub

sub updateScrollbar()
    if m.scrollTrack = invalid or m.scrollThumb = invalid then return
    totalItems = m.userLocation.peek().children.Count()
    if totalItems <= 0 then return

    trackHeight = m.scrollbarTrackHeight
    thumbHeight = Int(trackHeight * m.settingsMenu.numRows / totalItems)
    if thumbHeight < 20 then thumbHeight = 20

    maxScroll = totalItems - m.settingsMenu.numRows
    if maxScroll <= 0
        ' All items fit — hide scrollbar
        m.scrollTrack.visible = false
        m.scrollThumb.visible = false
        return
    end if

    m.scrollTrack.visible = true
    m.scrollThumb.visible = true
    m.scrollThumb.height = thumbHeight

    ' With fixedFocus, firstVisible = itemFocused exactly — list scrolls on every keypress
    maxFirstVisible = totalItems - m.settingsMenu.numRows
    if maxFirstVisible < 0 then maxFirstVisible = 0

    travelRange = trackHeight - thumbHeight
    if maxFirstVisible > 0
        thumbY = Int(travelRange * m.settingsMenu.itemFocused / maxFirstVisible)
        if thumbY > travelRange then thumbY = travelRange
    else
        thumbY = 0
    end if
    m.scrollThumb.translation = [496, 10 + thumbY]
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
    m.keyboardDialog.message = tr(selectedItem.description)
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
        set_user_setting(selectedSetting.settingName, newVal)
        ' Refresh description to show new value
        settingFocused()
    end if

    m.keyboardDialog.close = true
    m.keyboardDialog.unobserveField("buttonSelected")
    m.keyboardDialog = invalid
    m.settingsMenu.setFocus(true)
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
end sub
