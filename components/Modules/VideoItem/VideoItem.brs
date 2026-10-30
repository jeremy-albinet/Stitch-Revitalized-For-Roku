sub init()
    m.disposed = false
    m.itemlabel = m.top.findNode("itemLabel")
    m.itemmask = m.top.findNode("itemMask")
    m.timestampRect = m.top.findNode("timestampRect")
    m.timestampLabel = m.top.findNode("timestampLabel")
    m.itemposter = m.top.findNode("itemPoster")
    m.posterBase = m.top.findNode("posterBase")
    m.circlePoster = m.top.findNode("circlePoster")
    m.circleRing = m.top.findNode("circleRing")
    m.liveicon = m.top.findNode("liveIcon")
    m.itemSubtitle = m.top.findNode("itemSubtitle")
    m.itemViewers = m.top.findNode("itemViewers")
    m.viewsRect = m.top.findNode("viewsRect")
    m.runtimeRect = m.top.findNode("runtimeRect")
    m.runtimeLabel = m.top.findNode("runtimeLabel")
    m.avatarGroup = m.top.findNode("avatarGroup")
    m.avatar = m.top.findNode("avatar")
    m.lift = m.top.findNode("lift")
    m.liftSlab = m.top.findNode("liftSlab")
    m.liftTop = m.top.findNode("liftTop")
    m.liftBottom = m.top.findNode("liftBottom")
    m.liftSize = 8
    m.avatarSize = 40
    layout = m.global?.constants?.ui?.layout
    if layout <> invalid
        if layout.cardLift <> invalid then m.liftSize = layout.cardLift
        if layout.cardAvatar <> invalid then m.avatarSize = layout.cardAvatar
    end if
    m.isCircle = false
    m.posterWidth = 0
    m.posterHeight = 0
    m.sawFocusPercent = false
    initLiveBadge()
    initTitleFonts()
end sub

' Category tiles are narrower, so their titles use a smaller size. Both fonts
' are created once per card instance and swapped as RowList recycles it.
sub initTitleFonts()
    m.titleFont = invalid
    m.gameTitleFont = invalid
    if m.itemlabel = invalid or m.itemlabel.font = invalid then return
    m.titleFont = m.itemlabel.font
    if m.global?.compactGrid = true
        m.titleFont.size = 18
        m.itemSubtitle.font.size = 16
    end if
    m.gameTitleFont = CreateObject("roSGNode", "Font")
    m.gameTitleFont.uri = m.titleFont.uri
    m.gameTitleFont.size = 18
end sub

sub setTitleFont(font as dynamic)
    if font = invalid or m.itemlabel = invalid then return
    current = m.itemlabel.font
    if current <> invalid and current.isSameNode(font) then return
    m.itemlabel.font = font
end sub

' Sizes the red badge to the localized LIVE text once per card instance.
sub initLiveBadge()
    badge = m.top.findNode("liveBadge")
    label = m.top.findNode("liveLabel")
    if badge = invalid or label = invalid then return
    ' Width 0 lets the label size to its text for measuring.
    label.width = 0
    label.text = tr("LIVE")
    width = 48
    try
        textWidth = label.localBoundingRect().width
        if textWidth + 16 > width then width = textWidth + 16
    catch e
    end try
    badge.width = width
    label.width = width
end sub

' Sizes a stat pill to its text: 8 px padding each side on a 24 px plate.
sub fitPill(label as dynamic, plate as dynamic, text as dynamic)
    if label = invalid or plate = invalid then return
    if text = invalid then text = ""
    label.width = 0
    label.text = text
    width = 0
    try
        ' Round up: a label narrower than its text by a fraction ellipsizes.
        width = Int(label.localBoundingRect().width + 0.999) + 1
    catch e
    end try
    if width <= 1 then width = len(text) * 9
    plate.width = width + 16
    plate.height = 24
    label.translation = [plate.translation[0] + 8, plate.translation[1]]
    label.width = width
    label.height = 24
    ' An empty stat (no viewer count yet) shows no plate at all.
    plate.visible = text <> ""
    label.visible = plate.visible
end sub

' Restores the LIVE/VOD/CLIP card geometry. RowList recycles item components
' across rows, so GAME or USER geometry would otherwise carry over.
sub resetLayout()
    tile = getStreamTile()
    setThumbnailSize(tile.width, tile.height)
    m.itemlabel.maxwidth = tile.width
    ' The title's 28 px line (EmojiLabel y is its centre) starts 6 px below the
    ' focus slab, which reaches 8 px under the thumbnail.
    m.itemlabel.translation = [0, tile.height + 28]
    m.itemSubtitle.width = tile.width
    m.itemSubtitle.translation = [0, tile.height + 46]
    m.avatarGroup.translation = [0, tile.height + 22]
    m.viewsRect.translation = [8, tile.height - 32]
    setPosterBase(tile.width, tile.height)
end sub

sub setThumbnailSize(width as integer, height as integer)
    m.itemposter.width = width
    m.itemposter.height = height
    ' Roku autoscaling maps these logical sizes to the display resolution.
    m.itemposter.loadWidth = width
    m.itemposter.loadHeight = height
end sub

sub setPosterBase(width as integer, height as integer)
    m.posterWidth = width
    m.posterHeight = height
    if m.posterBase = invalid then return
    m.posterBase.width = width
    m.posterBase.height = height
    m.posterBase.visible = true
end sub

' Joins card subtitle parts with a middle dot, skipping empty parts.
function joinSubtitle(first as dynamic, second as dynamic) as string
    parts = []
    for each part in [first, second]
        if part <> invalid and part.toStr() <> "" then parts.push(part.toStr())
    end for
    return parts.join(" · ")
end function

' Reset all toggleable nodes to their default visible state before each
' content type configures its own layout. RowList recycles item components,
' so state from a previous content type would otherwise bleed through.
sub resetVisibility()
    if m.itemposter = invalid then return
    m.itemposter.visible = true
    m.isCircle = false
    if m.circlePoster <> invalid then m.circlePoster.visible = false
    if m.circleRing <> invalid then m.circleRing.visible = false
    if m.avatarGroup <> invalid then m.avatarGroup.visible = false
    if m.liveicon <> invalid then m.liveicon.visible = true
    if m.itemViewers <> invalid then m.itemViewers.visible = true
    if m.viewsRect <> invalid then m.viewsRect.visible = true
    ' No content type populates the runtime badge; an empty plate would
    ' otherwise draw as a stray square under the LIVE badge.
    if m.runtimeRect <> invalid then m.runtimeRect.visible = false
    if m.runtimeLabel <> invalid then m.runtimeLabel.visible = false
    if m.timestampLabel <> invalid then m.timestampLabel.visible = true
    if m.timestampRect <> invalid then m.timestampRect.visible = true
end sub

sub showcontent()
    if m.disposed then return
    m.itemLabel.repeatCount = 0
    resetVisibility()
    if m.itemposter <> invalid and m.itemlabel <> invalid and m.itemSubtitle <> invalid then resetLayout()
    GlobalSettings()
    titleFont = m.titleFont
    if m.top.itemContent.contentType = "GAME" then titleFont = m.gameTitleFont
    setTitleFont(titleFont)
    if m.top.itemContent.contentType = "GAME"
        GameSettings()
    else if m.top.itemContent.contentType = "LIVE"
        LiveSettings()
    else if m.top.itemContent.contentType = "VOD"
        VodSettings()
    else if m.top.itemContent.contentType = "CLIP"
        ClipSettings()
    else if m.top.itemContent.contentType = "USER"
        UserSettings()
    end if
    onFocusChange()
end sub

sub GlobalSettings()
    if m.global = invalid or m.global.constants = invalid then return
    if m.itemSubtitle = invalid then return
    m.itemSubtitle.color = m.global.constants.ui.color.textSecondary
end sub

sub GameSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.itemSubtitle = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    setThumbnailSize(188, 250)
    setPosterBase(188, 250)
    ' Text starts below the focus slab, which reaches 8 px under the box art.
    m.itemlabel.maxwidth = 188
    m.itemlabel.translation = [0, 276]
    m.itemSubtitle.width = 188
    m.itemSubtitle.translation = [0, 290]
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.viewersDisplay
    m.itemposter.uri = m.top.itemContent.gameBoxArtUrl
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

' Live cards follow Twitch's card: avatar, then title over channel · category.
sub setAvatar(uri as dynamic)
    if m.avatarGroup = invalid or m.avatar = invalid then return
    hasAvatar = GetInterface(uri, "ifString") <> invalid and uri <> ""
    m.avatarGroup.visible = hasAvatar
    if not hasAvatar then return
    m.avatar.uri = uri
    textX = m.avatarSize + 12
    tile = getStreamTile()
    m.itemlabel.maxwidth = tile.width - textX
    m.itemlabel.translation = [textX, tile.height + 28]
    m.itemSubtitle.width = tile.width - textX
    m.itemSubtitle.translation = [textX, tile.height + 46]
end sub

sub LiveSettings()
    if m.itemposter = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    fitPill(m.itemViewers, m.viewsRect, m.top.itemContent.viewersDisplay)
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = joinSubtitle(m.top.itemContent.streamerDisplayName, m.top.itemContent.gameDisplayName)
    m.itemlabel.text = m.top.itemContent.contentTitle
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    setAvatar(m.top.itemContent.streamerProfileImageUrl)
end sub

sub VodSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.liveicon.visible = false
    fitPill(m.itemViewers, m.viewsRect, m.top.itemContent.viewersDisplay)
    fitPill(m.timestampLabel, m.timestampRect, m.top.itemContent.relativePublishDate)
    m.timestampRect.visible = m.timestampLabel.text <> ""
    m.timestampLabel.visible = m.timestampRect.visible
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = joinSubtitle(m.top.itemContent.streamerDisplayName, m.top.itemContent.gameDisplayName)
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub ClipSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.liveicon.visible = false
    fitPill(m.itemViewers, m.viewsRect, m.top.itemContent.viewersDisplay)
    fitPill(m.timestampLabel, m.timestampRect, m.top.itemContent.relativePublishDate)
    m.timestampRect.visible = m.timestampLabel.text <> ""
    m.timestampLabel.visible = m.timestampRect.visible
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = joinSubtitle(m.top.itemContent.streamerDisplayName, m.top.itemContent.gameDisplayName)
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub UserSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.circlePoster = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    m.itemposter.visible = false
    if m.posterBase <> invalid then m.posterBase.visible = false
    m.isCircle = true
    m.circlePoster.uri = m.top.itemContent.streamerProfileImageUrl
    m.circlePoster.visible = true
    ' Text starts below the focus ring, which reaches 10 px under the circle.
    m.itemlabel.maxwidth = 150
    m.itemlabel.translation = [0, 180]
    m.itemSubtitle.width = 150
    m.itemSubtitle.translation = [0, 196]
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.followerDisplay
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub onGetFocus()
    if m.disposed then return
    onFocusChange()
end sub

' Focus follows the RowList's own focus animation, so the lift grows and
' shrinks only as the remote moves focus. Nothing shows while the menu or
' rail holds focus.
sub onFocusChange()
    if m.disposed or m.lift = invalid then return
    amount = 0.0
    if m.top.focusPercent > 0 then m.sawFocusPercent = true
    if m.top.rowListHasFocus = true
        amount = m.top.focusPercent
        ' A runtime that never animates focusPercent still reports the item.
        if not m.sawFocusPercent and m.top.itemHasFocus = true then amount = 1.0
    end if
    if amount > 1 then amount = 1.0
    repeatCount = 0
    if amount >= 1 and m.itemLabel.width > m.itemLabel.maxWidth then repeatCount = -1
    m.itemLabel.repeatCount = repeatCount
    if m.isCircle
        m.lift.visible = false
        if m.circleRing <> invalid then m.circleRing.visible = amount >= 0.5
        return
    end if
    if m.circleRing <> invalid then m.circleRing.visible = false
    applyLift(amount)
end sub

' The slab sits offset down-left by up to cardLift px; the bevels close the
' gaps at its top-left and bottom-right corners.
sub applyLift(amount as float)
    size = Int(m.liftSize * amount + 0.5)
    if size < 1 or m.posterWidth <= 0
        m.lift.visible = false
        return
    end if
    width = m.posterWidth
    height = m.posterHeight
    m.liftSlab.width = width
    m.liftSlab.height = height
    m.liftSlab.translation = [0 - size, size]
    m.liftTop.width = size
    m.liftTop.height = size
    m.liftTop.translation = [0 - size, 0]
    m.liftBottom.width = size
    m.liftBottom.height = size
    m.liftBottom.translation = [width - size, height]
    m.lift.visible = true
end sub

sub showrowfocus()
    if m.disposed then return
    if m.itemmask = invalid or m.top.rowFocusPercent = invalid then return
    m.itemmask.opacity = 0.75 - (m.top.rowFocusPercent * 0.75)
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    if m.itemlabel <> invalid then m.itemlabel.callFunc("onDestroy")
end sub
