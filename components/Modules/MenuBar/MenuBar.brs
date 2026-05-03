sub init()
    '*******************'
    '* Get Node List
    '*******************'
    m.logo = m.top.findNode("logo")
    m.headerRect = m.top.findNode("headerRect")
    m.menuOptions = m.top.findNode("MenuOptions")
    m.iconOptions = m.top.findNode("IconOptions")

    '*******************'
    '* Layout Constants
    '*******************'
    m.screenWidth = 1280
    m.iconRightPadding = 24

    '*******************'
    '* Per-group focus bitmap URIs. Each ButtonGroup uses a different
    '* focus image (text buttons get an underline indicator, icon buttons
    '* get a footprint). We toggle focusBitmapUri on each Button to either
    '* the real image (when its group is focused) or a transparent 9-patch
    '* (when its group is not). Setting the URI to "" leaves the previously
    '* loaded bitmap cached on screen, so a real (transparent) image is used
    '* to forcibly clear the rendered focus indicator.
    '*******************'
    m.menuOptionsFocusUri = "pkg:/images/focusindicator.9.png"
    m.iconOptionsFocusUri = "pkg:/images/focusfootprint.9.png"
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

    m.top.menuTextColor = m.global.constants.colors.muted.ice
    m.top.menuFocusColor = m.global.constants.colors.twitch.purple10

    ' Tracks whether MenuOptions has been shifted right by the logo width.
    ' updateMenuOptions() can be re-invoked when icon visibility changes,
    ' but the translation must only be applied once.
    m.menuOptionsTranslated = false
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
'*
'* We additionally toggle the group's own opacity briefly to force the
'* render tree to re-evaluate the new focusBitmapUri values, since
'* Roku caches the previously rendered bitmap on a non-focused group.
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
end sub

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
    map = {
        "search": m.global.constants.defaultIcons.search,
        "settings": m.global.constants.defaultIcons.settings,
        "loginpage": get_user_setting("profile_image_url", m.global.constants.defaultIcons.login)
    }
    newItem = createObject("roSGNode", "Button")
    newItem.id = icon
    newItem.textColor = m.top.menuTextColor
    newItem.focusedTextColor = m.top.menuTextColor
    newItem.iconUri = map[icon]
    newItem.focusedIconUri = map[icon]
    newItem.minWidth = 0
    newItem.height = m.top.menuOptionsHeight
    newItem.focusFootprintBitmapUri = "pkg:/images/focusfootprint.9.png"
    newItem.focusBitmapUri = "pkg:/images/focusfootprint.9.png"
    newItem.showFocusFootprint = false
    newItem.getchild(3).blendColor = m.top.menuTextColor
    newItem.getchild(3).width = m.top.menuFontSize * 2
    newItem.getchild(3).height = m.top.menuFontSize * 2
    newItem.getchild(4).blendColor = m.top.menuFocusColor
    newItem.getchild(4).width = m.top.menuFontSize * 2
    newItem.getchild(4).height = m.top.menuFontSize * 2
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

    '*******************'
    '* Include Width of Logo in Menu Option Offset (apply once)
    '*******************'
    if not m.menuOptionsTranslated
        xoffset = m.menuOptions.translation[0] + m.logo.width + m.logo.translation[0]
        yoffset = m.menuOptions.translation[1]
        m.menuOptions.translation = "[" + xoffset.ToStr() + "," + yoffset.ToStr() + "]"
        m.menuOptionsTranslated = true
    end if

    '*******************'
    '* Build text buttons -> MenuOptions (left-anchored)
    '*******************'
    menuButtons = []
    for i = 0 to (m.top.menuOptionsText.count() - 1)
        if m.top.menuOptionsText[i] <> ""
            newItem = createObject("roSGNode", "Button")
            font = CreateObject("roSGNode", "Font")
            font.size = m.top.menuFontSize
            font.uri = m.top.menuFontUri
            newItem.minWidth = 245
            newItem.textFont = font
            newItem.focusedTextFont = font
            newItem.textColor = m.top.menuTextColor
            newItem.focusedTextColor = m.top.menuFocusColor
            newItem.iconUri = ""
            newItem.focusedIconUri = ""
            newItem.height = m.top.menuOptionsHeight
            newItem.focusFootprintBitmapUri = "pkg:/images/focusfootprint.9.png"
            newItem.focusBitmapUri = "pkg:/images/focusindicator.9.png"
            newItem.showFocusFootprint = false
            newItem.id = m.top.menuOptionsText[i]
            newItem.text = tr(m.top.menuOptionsText[i])
            menuButtons.push(newItem)
        end if
    end for
    for each menuButton in menuButtons
        m.menuOptions.appendChild(menuButton)
    end for

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
        ' Fallback: estimate based on icon size when boundingRect is unavailable.
        ' Each icon button is ~ menuFontSize * 2 wide plus button chrome (~16px).
        perIcon = (m.top.menuFontSize * 2) + 16
        width = m.iconOptions.getChildCount() * perIcon
    end if
    x = m.screenWidth - m.iconRightPadding - width
    if x < 0 then x = 0
    m.iconOptions.translation = [x, 0]
end sub

sub handleUserLoginResponse()
    ? "[MenuBar] - handleUserLoginResponse()"
    search = m.loginIconTask.response
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
    if m.top.updateUserIcon
        if get_setting("active_user", "$default$") <> "$default$"
            ? "[MenuBar] - handleUserLogin()"
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
    m.top.unobserveField("focusedChild")
    m.top.unobserveField("updateUserIcon")
    m.top.unobserveField("buttonSelected")
    m.top.unobserveField("buttonFocused")
    if m.menuOptions <> invalid
        m.menuOptions.unobserveField("buttonFocused")
        m.menuOptions.unobserveField("buttonSelected")
    end if
    if m.iconOptions <> invalid
        m.iconOptions.unobserveField("buttonFocused")
        m.iconOptions.unobserveField("buttonSelected")
    end if
    m.loginIconTask = destroyTask(m.loginIconTask, "response")
end sub
