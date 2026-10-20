sub init()
    m.avatarSize = 200
    m.pitch = 280
    m.tilesY = 400
    m.tiles = m.top.findNode("tiles")
    m.ring = m.top.findNode("ring")
    m.top.findNode("title").font = makeFont("pkg:/fonts/Archivo-Bold.otf", 56)
    m.top.findNode("title").text = tr("Who's watching?")
    m.index = 0
    buildTiles()
    m.top.setFocus(true)
end sub

function makeFont(uri as string, size as integer) as object
    font = CreateObject("roSGNode", "Font")
    font.uri = uri
    font.size = size
    return font
end function

sub buildTiles()
    m.tiles.removeChildren(m.tiles.getChildren(-1, 0))
    m.profiles = getProfiles()
    m.hasAdd = m.profiles.Count() < 5
    count = m.profiles.Count()
    if m.hasAdd then count = count + 1
    startX = (1920 - count * m.pitch) / 2
    for i = 0 to count - 1
        tile = CreateObject("roSGNode", "Group")
        tile.translation = [startX + i * m.pitch, m.tilesY]
        name = tr("Add account")
        if i < m.profiles.Count()
            section = m.profiles[i]
            name = registry_read("display_name", section)
            if name = invalid then name = section
            avatar = CreateObject("roSGNode", "CirclePoster")
            avatar.width = m.avatarSize
            avatar.height = m.avatarSize
            imageUrl = registry_read("profile_image_url", section)
            if imageUrl = invalid or imageUrl = "" then imageUrl = m.global.constants.defaultIcons.login
            avatar.uri = imageUrl
            avatar.translation = [(m.pitch - m.avatarSize) / 2, 0]
            tile.appendChild(avatar)
        else
            circle = CreateObject("roSGNode", "Poster")
            circle.uri = "pkg:/images/profile-mask-540.png"
            circle.blendColor = m.global.constants.colors.hinted.grey5
            circle.width = m.avatarSize
            circle.height = m.avatarSize
            circle.translation = [(m.pitch - m.avatarSize) / 2, 0]
            tile.appendChild(circle)
            plus = CreateObject("roSGNode", "Label")
            plus.text = "+"
            plus.font = makeFont("pkg:/fonts/Archivo-Bold.otf", 96)
            plus.width = m.avatarSize
            plus.height = m.avatarSize
            plus.horizAlign = "center"
            plus.vertAlign = "center"
            plus.translation = [(m.pitch - m.avatarSize) / 2, 0]
            tile.appendChild(plus)
        end if
        label = CreateObject("roSGNode", "Label")
        label.text = name
        label.font = makeFont("pkg:/fonts/Archivo-Regular.otf", 30)
        label.width = m.pitch
        label.horizAlign = "center"
        label.translation = [0, m.avatarSize + 30]
        tile.appendChild(label)
        m.tiles.appendChild(tile)
    end for
    if m.index >= count then m.index = count - 1
    moveRing()
end sub

sub moveRing()
    tile = m.tiles.getChild(m.index)
    if tile = invalid then return
    m.ring.translation = [tile.translation[0] + (m.pitch - m.ring.width) / 2, m.tilesY - 12]
end sub

sub confirmRemove()
    if m.index >= m.profiles.Count() then return
    section = m.profiles[m.index]
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = tr("Remove profile?")
    dialog.message = [section]
    dialog.buttons = [tr("Cancel"), tr("Remove")]
    dialog.observeField("buttonSelected", "onRemoveDialogButton")
    dialog.observeField("wasClosed", "onRemoveDialogClosed")
    m.removeSection = section
    m.removeDialog = dialog
    m.top.getScene().dialog = dialog
end sub

sub onRemoveDialogButton()
    if m.removeDialog = invalid then return
    if m.removeDialog.buttonSelected = 1 then removeAccount(m.removeSection)
    m.removeDialog.close = true
end sub

sub onRemoveDialogClosed()
    if m.removeDialog = invalid then return
    m.removeDialog.unobserveField("buttonSelected")
    m.removeDialog.unobserveField("wasClosed")
    m.removeDialog = invalid
    m.top.setFocus(true)
end sub

sub removeAccount(section as string)
    removeProfile(section)
    NukeRegistry(section)
    if get_setting("active_user", "$default$") = section
        set_setting("active_user", "$default$")
    end if
    if getProfiles().Count() = 0
        m.top.profileSelected = "$default$"
    else
        buildTiles()
    end if
end sub

sub onDestroy()
    if m.removeDialog <> invalid
        m.removeDialog.unobserveField("buttonSelected")
        m.removeDialog.unobserveField("wasClosed")
        m.removeDialog = invalid
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return true
    count = m.tiles.getChildCount()
    if key = "left" and m.index > 0
        m.index = m.index - 1
        moveRing()
    else if key = "right" and m.index < count - 1
        m.index = m.index + 1
        moveRing()
    else if key = "OK"
        if m.index < m.profiles.Count()
            m.top.profileSelected = m.profiles[m.index]
        else
            m.top.addAccount = true
        end if
    else if key = "options"
        confirmRemove()
    else if key = "back"
        m.top.backPressed = true
    end if
    return true
end function
