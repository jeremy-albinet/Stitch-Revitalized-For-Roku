sub init()
    m.disposed = false
    '*******************'
    '* Get Node List
    '*******************'
    m.headerRect = m.top.findNode("headerRect")
    m.menuOptions = m.top.findNode("MenuOptions")
    m.iconOptions = m.top.findNode("IconOptions")
    m.iconCaption = m.top.findNode("iconCaption")
    m.iconCaptionPlate = m.top.findNode("iconCaptionPlate")
    m.iconCaptionLabel = m.top.findNode("iconCaptionLabel")

    '*******************'
    '* Layout Constants
    '*******************'
    m.screenWidth = 1280
    m.iconRightPadding = 48
    m.iconSize = 32
    ' Tabs and icons are 44 px pills centred in the 64 px header. Roku Buttons
    ' inset their label 24 px on each side.
    m.buttonHeight = 44
    m.buttonInset = 24
    m.tabsX = 152

    '*******************'
    '* Per-group focus bitmap URIs. Tabs and icons both get the purple
    '* focus pill. We toggle focusBitmapUri on each Button to either
    '* the real image (when its group is focused) or a transparent 9-patch
    '* (when its group is not). Setting the URI to "" leaves the previously
    '* loaded bitmap cached on screen, so a real (transparent) image is used
    '* to forcibly clear the rendered focus indicator.
    '*******************'
    m.menuOptionsFocusUri = "pkg:/images/twitch-redesign/focus-round6.9.png"
    m.iconOptionsFocusUri = "pkg:/images/twitch-redesign/focus-round6.9.png"
    m.transparentFocusUri = "pkg:/images/transparent.9.png"

    m.top.observeField("focusedChild", "onGetfocus")
    m.top.observeField("updateUserIcon", "handleUserLogin")
    m.top.observeField("buttonSelected", "onMenuSelected")
    m.top.observeField("buttonFocused", "onMenuFocused")

    '*******************'
    '* Bridge events from the two ButtonGroupHoriz children into a single
    '* flat 0..N-1 index on m.top.buttonFocused / m.top.buttonSelected so
    '* heroScene continues to see one contiguous button list.
    '*******************'
    m.menuOptions.observeField("buttonFocused", "onMenuOptionsFocused")
    m.menuOptions.observeField("buttonSelected", "onMenuOptionsSelected")
    m.iconOptions.observeField("buttonFocused", "onIconOptionsFocused")
    m.iconOptions.observeField("buttonSelected", "onIconOptionsSelected")

    m.top.observeField("activeItem", "updateTabColors")
    m.top.observeField("focusItem", "onFocusItem")

    ' Active tab reads as primary text, other tabs as secondary; the focused
    ' tab is white on the purple focus pill.
    m.top.menuTextColor = m.global.constants.ui.color.textSecondary
    m.top.menuFocusColor = m.global.constants.ui.color.onAccent
end sub

' Remove all children from a ButtonGroup so updateMenuOptions can be re-run.
sub clearGroup(group as object)
    if group = invalid then return
    children = group.getChildren(-1, 0)
    for each child in children
        group.removeChild(child)
    end for
end sub

sub onMenuSelected()
    ? "button selected: "; m.top.buttonSelected
end sub

sub onMenuFocused()
    ? "button focused: "; m.top.buttonFocused
end sub

sub onMenuOptionsFocused()
    idx = m.menuOptions.buttonFocused
    if idx < 0 then return
    m.top.buttonFocused = idx
end sub

sub onMenuOptionsSelected()
    idx = m.menuOptions.buttonSelected
    if idx < 0 then return
    m.top.buttonSelected = idx
end sub

sub onIconOptionsFocused()
    idx = m.iconOptions.buttonFocused
    if idx < 0 then return
    m.top.buttonFocused = textButtonCount() + idx
    updateIconCaption()
end sub

sub onIconOptionsSelected()
    idx = m.iconOptions.buttonSelected
    if idx < 0 then return
    m.top.buttonSelected = textButtonCount() + idx
end sub

function textButtonCount() as integer
    return m.menuOptions.getChildCount()
end function

sub onGetfocus()
    if m.top.focusedChild <> invalid and m.top.focusedChild.id = "MenuBar"
        m.menuOptions.setFocus(true)
    end if
    updateGroupFocusVisuals()
end sub

'*******************'
'* Toggle focus visuals on the two ButtonGroups so only the currently
'* focused group draws its focus indicator. We swap each Button's
'* focusBitmapUri between the real image (active) and a transparent
'* 9-patch (inactive). Setting the URI to "" leaves the previously
'* loaded bitmap rendered on screen, so a real (transparent) image
'* must be supplied to forcibly clear the indicator.
'*******************'
sub updateGroupFocusVisuals()
    if m.menuOptions = invalid or m.iconOptions = invalid then return
    focused = m.top.focusedChild
    focusedId = ""
    if focused <> invalid then focusedId = focused.id
    menuActive = (focusedId = "MenuOptions")
    iconActive = (focusedId = "IconOptions")
    applyFocusUri(m.menuOptions, m.menuOptionsFocusUri, menuActive)
    applyFocusUri(m.iconOptions, m.iconOptionsFocusUri, iconActive)
    updateIconCaption()
end sub

sub updateTabColors()
    if m.menuOptions = invalid then return
    color = m.global.constants.ui.color
    for i = 0 to m.menuOptions.getChildCount() - 1
        tabButton = m.menuOptions.getChild(i)
        if tabButton <> invalid
            if tabButton.id = m.top.activeItem
                tabButton.textColor = color.text
            else
                tabButton.textColor = color.textSecondary
            end if
        end if
    end for
end sub

' Moves the tab focus marker without selecting it, so returning to the menu
' starts from the page that was opened another way.
sub onFocusItem()
    if m.menuOptions = invalid then return
    for i = 0 to m.menuOptions.getChildCount() - 1
        tabButton = m.menuOptions.getChild(i)
        if tabButton <> invalid and tabButton.id = m.top.focusItem
            m.menuOptions.focusButton = i
            return
        end if
    end for
end sub

' Icon-only buttons say their name while focused.
sub updateIconCaption()
    if m.iconCaption = invalid or m.iconCaptionLabel = invalid then return
    focused = m.top.focusedChild
    button = invalid
    if focused <> invalid and focused.id = "IconOptions"
        button = m.iconOptions.getChild(m.iconOptions.buttonFocused)
    end if
    if button = invalid
        m.iconCaption.visible = false
        return
    end if
    m.iconCaptionLabel.text = iconCaptionText(button.id)
    padding = 12
    labelWidth = 0
    rightEdge = m.screenWidth - m.iconRightPadding
    try
        labelWidth = m.iconCaptionLabel.boundingRect().width
        bounds = button.boundingRect()
        rightEdge = m.iconOptions.translation[0] + bounds.x + bounds.width
    catch e
    end try
    if labelWidth <= 0 then labelWidth = len(m.iconCaptionLabel.text) * 10
    width = labelWidth + (padding * 2)
    ' Keep the caption inside the TV-safe frame.
    x = rightEdge - width
    if x + width > 1232 then x = 1232 - width
    if x < 48 then x = 48
    m.iconCaptionPlate.width = width
    m.iconCaption.translation = [x, 72]
    m.iconCaption.visible = true
end sub

function iconCaptionText(iconId as string) as string
    if iconId = "Settings" then return tr("Settings")
    if iconId = "Search" then return tr("Search")
    if iconId = "LoginPage"
        if get_setting("active_user", "$default$") = "$default$" then return tr("Sign in")
        ' Signed in, the avatar opens the Account panel.
        name = get_user_setting("display_name")
        if name = invalid or name = "" then name = get_user_setting("login", "")
        if name <> "" then return tr("Account") + " · " + name
        return tr("Account")
    end if
    return iconId
end function

sub applyFocusUri(group as object, uri as string, active as boolean)
    if group = invalid then return
    value = m.transparentFocusUri
    if active then value = uri
    count = group.getChildCount()
    for i = 0 to count - 1
        btn = group.getChild(i)
        if btn <> invalid
            ' Toggle both the focus and footprint bitmaps. Roku caches the
            ' previously rendered bitmap on a non-focused group, so updating
            ' both URIs in tandem forces the engine to re-render with the
            ' new (transparent) image when the group loses focus.
            btn.focusBitmapUri = value
            btn.focusFootprintBitmapUri = value
        end if
    end for
end sub

'*******************'
'* Bridge focus between MenuOptions <-> IconOptions when either group
'* hits its left/right boundary and bubbles the unhandled key event up.
'*******************'
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    focused = m.top.focusedChild
    if focused = invalid then return false
    if key = "right" and focused.id = "MenuOptions"
        if m.iconOptions.getChildCount() > 0
            m.iconOptions.focusButton = 0
            return true
        end if
    else if key = "left" and focused.id = "IconOptions"
        last = m.menuOptions.getChildCount() - 1
        if last >= 0
            m.menuOptions.focusButton = last
            return true
        end if
    end if
    return false
end function

function buildIcon(icon)
    accountIcon = m.global.constants.defaultIcons.login
    if get_setting("active_user", "$default$") <> "$default$"
        accountIcon = get_user_setting("profile_image_url", accountIcon)
    end if
    map = {
        "search": m.global.constants.defaultIcons.search,
        "settings": m.global.constants.defaultIcons.settings,
        "loginpage": accountIcon
    }
    newItem = createObject("roSGNode", "Button")
    newItem.id = icon
    newItem.textColor = m.top.menuTextColor
    newItem.focusedTextColor = m.top.menuTextColor
    newItem.iconUri = map[icon]
    newItem.focusedIconUri = map[icon]
    newItem.height = m.buttonHeight
    newItem.minWidth = m.iconSize + (m.buttonInset * 2)
    newItem.maxWidth = newItem.minWidth
    newItem.focusFootprintBitmapUri = m.transparentFocusUri
    newItem.focusBitmapUri = m.iconOptionsFocusUri
    newItem.showFocusFootprint = false
    ' Some runtimes omit these internal Posters; the public icon fields remain valid.
    iconPoster = newItem.getChild(3)
    if iconPoster <> invalid
        iconPoster.blendColor = m.global.constants.ui.color.text
        iconPoster.width = m.iconSize
        iconPoster.height = m.iconSize
    end if
    focusedIconPoster = newItem.getChild(4)
    if focusedIconPoster <> invalid
        focusedIconPoster.blendColor = m.top.menuFocusColor
        focusedIconPoster.width = m.iconSize
        focusedIconPoster.height = m.iconSize
    end if
    return newItem
end function

sub updateMenuOptions()
    '*******************'
    '* Bail out until heroScene has supplied menuOptionsText. The icon-flag
    '* onChange handlers fire during heroScene.init() before menuOptionsText
    '* is assigned, and rebuilding icons that early causes Button child
    '* Posters to not be fully materialized yet (brs-engine quirk).
    '*******************'
    if m.top.menuOptionsText.count() = 0 then return

    '*******************'
    '* Clear existing children so this can be re-run when any of the
    '* observed inputs (menuOptionsText, showSearchIcon, showSettingsIcon,
    '* showLoginIcon) changes. Without this, repeated calls would
    '* append duplicate buttons.
    '*******************'
    clearGroup(m.menuOptions)
    clearGroup(m.iconOptions)

    m.menuOptions.translation = [m.tabsX, (64 - m.buttonHeight) / 2]
    m.iconOptions.translation = [m.iconOptions.translation[0], (64 - m.buttonHeight) / 2]

    '*******************'
    '* Build text buttons -> MenuOptions (left-anchored). Each tab is as wide
    '* as its localized label plus the Button inset, like Twitch's nav links.
    '*******************'
    font = CreateObject("roSGNode", "Font")
    font.size = m.top.menuFontSize
    font.uri = m.top.menuFontUri
    menuButtons = []
    for i = 0 to (m.top.menuOptionsText.count() - 1)
        if m.top.menuOptionsText[i] <> ""
            newItem = createObject("roSGNode", "Button")
            newItem.textFont = font
            newItem.focusedTextFont = font
            newItem.textColor = m.top.menuTextColor
            newItem.focusedTextColor = m.top.menuFocusColor
            newItem.iconUri = ""
            newItem.focusedIconUri = ""
            newItem.focusFootprintBitmapUri = m.transparentFocusUri
            newItem.focusBitmapUri = m.menuOptionsFocusUri
            newItem.showFocusFootprint = false
            newItem.height = m.buttonHeight
            newItem.id = m.top.menuOptionsText[i]
            newItem.text = tr(m.top.menuOptionsText[i])
            newItem.minWidth = tabWidth(newItem.text, font)
            newItem.maxWidth = newItem.minWidth
            menuButtons.push(newItem)
        end if
    end for
    for each menuButton in menuButtons
        m.menuOptions.appendChild(menuButton)
    end for
    updateTabColors()

    '*******************'
    '* Build icons -> IconOptions (right-anchored)
    '*******************'
    icons = []
    if m.top.showSearchIcon
        icons.push(buildIcon("Search"))
    end if
    if m.top.showSettingsIcon
        icons.push(buildIcon("Settings"))
    end if
    if m.top.showLoginIcon
        icons.push(buildIcon("LoginPage"))
    end if
    for each icon in icons
        m.iconOptions.appendChild(icon)
    end for

    '*******************'
    '* Right-anchor the IconOptions group. ButtonGroup ignores
    '* horizAlignment for its container position, so compute the X
    '* translation from the rendered width.
    '*******************'
    positionIconOptions()
end sub

sub positionIconOptions()
    if m.iconOptions = invalid then return
    if m.iconOptions.getChildCount() = 0 then return
    width = 0
    try
        bounds = m.iconOptions.boundingRect()
        if bounds <> invalid and bounds.width <> invalid
            width = bounds.width
        end if
    catch e
        width = 0
    end try
    if width <= 0
        ' Fallback when boundingRect is unavailable: fixed-width icon pills.
        perIcon = m.iconSize + (m.buttonInset * 2) + 4
        width = m.iconOptions.getChildCount() * perIcon
    end if
    x = m.screenWidth - m.iconRightPadding - width
    if x < 0 then x = 0
    m.iconOptions.translation = [x, (64 - m.buttonHeight) / 2]
end sub

' Label width plus the Button's inset on both sides, so the focus pill hugs
' the localized text and the label sits centred in it.
function tabWidth(text as string, font as object) as integer
    width = 0
    try
        probe = CreateObject("roSGNode", "Label")
        probe.font = font
        probe.text = text
        ' Round up so the label never ellipsizes by a fraction of a pixel.
        width = Int(probe.boundingRect().width + 0.999) + 1
    catch e
        width = 0
    end try
    if width <= 0 then width = len(text) * 14
    return width + (m.buttonInset * 2)
end function

sub handleUserLoginResponse(event = invalid as dynamic)
    if m.disposed or m.loginIconTask = invalid then return
    if event <> invalid
        if not event.getRoSGNode().isSameNode(m.loginIconTask) then return
    end if
    ? "[MenuBar] - handleUserLoginResponse()"
    search = m.loginIconTask.response
    requestedUser = m.loginIconUser
    m.loginIconTask = destroyTask(m.loginIconTask, "response")
    m.loginIconUser = invalid
    if requestedUser = invalid or requestedUser <> get_setting("active_user", "$default$") then return
    if search <> invalid and search.data <> invalid
        for each stream in search.data
            set_user_setting("id", stream.id)
            set_user_setting("display_name", stream.display_name)
            set_user_setting("profile_image_url", stream.profile_image_url)
        end for
        avatar = m.iconOptions.findNode("LoginPage")
        if avatar <> invalid
            avatar.iconUri = get_user_setting("profile_image_url")
            avatar.focusedIconUri = get_user_setting("profile_image_url")
            m.top.updateUserIcon = false
        end if
    end if
end sub

sub handleUserLogin()
    if m.disposed then return
    if m.top.updateUserIcon
        m.loginIconTask = destroyTask(m.loginIconTask, "response")
        m.loginIconUser = invalid
        activeUser = get_setting("active_user", "$default$")
        if activeUser <> "$default$"
            ? "[MenuBar] - handleUserLogin()"
            m.loginIconUser = activeUser
            m.loginIconTask = createApiTask("TwitchHelixApiRequest", "handleUserLoginResponse", {
                params: {
                    endpoint: "users",
                    args: "login=" + get_user_setting("login"),
                    method: "GET"
                }
            })
        else
            avatar = m.iconOptions.findNode("LoginPage")
            if avatar <> invalid
                avatar.iconUri = m.global.constants.defaultIcons.login
                avatar.focusedIconUri = m.global.constants.defaultIcons.login
                m.top.updateUserIcon = false
            end if
        end if
    end if
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.unobserveField("focusedChild")
    m.top.unobserveField("updateUserIcon")
    m.top.unobserveField("buttonSelected")
    m.top.unobserveField("buttonFocused")
    m.top.unobserveField("activeItem")
    m.top.unobserveField("focusItem")
    if m.menuOptions <> invalid
        m.menuOptions.unobserveField("buttonFocused")
        m.menuOptions.unobserveField("buttonSelected")
    end if
    if m.iconOptions <> invalid
        m.iconOptions.unobserveField("buttonFocused")
        m.iconOptions.unobserveField("buttonSelected")
    end if
    m.loginIconTask = destroyTask(m.loginIconTask, "response")
    m.loginIconUser = invalid
end sub
