sub init()
    m.itemlabel = m.top.findNode("itemLabel")
    m.itemmask = m.top.findNode("itemMask")
    m.timestampRect = m.top.findNode("timestampRect")
    m.timestampLabel = m.top.findNode("timestampLabel")
    m.itemposter = m.top.findNode("itemPoster")
    m.circlePoster = m.top.findNode("circlePoster")
    m.liveicon = m.top.findNode("liveIcon")
    m.itemSubtitle = m.top.findNode("itemSubtitle")
    m.itemThirdTitle = m.top.findNode("itemThirdTitle")
    m.itemViewers = m.top.findNode("itemViewers")
    m.viewsRect = m.top.findNode("viewsRect")
    m.runtimeRect = m.top.findNode("runtimeRect")
    m.runtimeLabel = m.top.findNode("runtimeLabel")
end sub

' Reset all toggleable nodes to their default visible state before each
' content type configures its own layout. RowList recycles item components,
' so state from a previous content type would otherwise bleed through.
sub resetVisibility()
    if m.itemposter = invalid then return
    m.itemposter.visible = true
    if m.circlePoster <> invalid then m.circlePoster.visible = false
    if m.liveicon <> invalid then m.liveicon.visible = true
    if m.itemViewers <> invalid then m.itemViewers.visible = true
    if m.viewsRect <> invalid then m.viewsRect.visible = true
    if m.runtimeRect <> invalid then m.runtimeRect.visible = true
    if m.runtimeLabel <> invalid then m.runtimeLabel.visible = true
    if m.timestampLabel <> invalid then m.timestampLabel.visible = true
    if m.timestampRect <> invalid then m.timestampRect.visible = true
end sub

sub showcontent()
    resetVisibility()
    GlobalSettings()
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
end sub

sub GlobalSettings()
    if m.global = invalid or m.global.constants = invalid then return
    if m.itemSubtitle = invalid or m.itemThirdTitle = invalid then return
    m.itemSubtitle.color = m.global.constants.colors.hinted.grey9
    m.itemThirdTitle.color = m.global.constants.colors.hinted.grey9

end sub

sub GameSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.itemSubtitle = invalid or m.itemThirdTitle = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    m.itemposter.width = 188
    m.itemposter.height = 250
    m.itemposter.loadwidth = 188
    m.itemposter.loadheight = 250
    m.itemlabel.maxwidth = 188
    m.itemlabel.translation = "[0,270]"
    m.itemSubtitle.translation = "[0, 280]"
    m.itemThirdTitle.translation = "[0, 290]"
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.viewersDisplay
    m.itemposter.uri = m.top.itemContent.gameBoxArtUrl
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub LiveSettings()
    if m.itemposter = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid or m.itemThirdTitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.itemViewers.text = m.top.itemContent.viewersDisplay
    try
        m.viewsRect.height = m.itemViewers.boundingRect().height
        m.viewsRect.width = m.itemViewers.boundingRect().width + 6
    catch e
    end try
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = m.top.itemContent.streamerDisplayName
    m.itemThirdTitle.text = m.top.itemContent.gameDisplayName
    m.itemlabel.text = m.top.itemContent.contentTitle
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
end sub

sub VodSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid or m.itemThirdTitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.liveicon.visible = false
    m.itemViewers.text = m.top.itemContent.viewersDisplay
    try
        m.viewsRect.height = m.itemViewers.boundingRect().height
        m.viewsRect.width = m.itemViewers.boundingRect().width + 6
        m.timestampLabel.text = m.top.itemContent.relativePublishDate
        m.timestampRect.height = m.timestampLabel.boundingRect().height
        m.timestampRect.width = m.timestampLabel.boundingRect().width + 6
    catch e
    end try
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = m.top.itemContent.streamerDisplayName
    m.itemThirdTitle.text = m.top.itemContent.gameDisplayName
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub ClipSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid or m.itemThirdTitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.liveicon.visible = false
    m.itemViewers.text = m.top.itemContent.viewersDisplay
    try
        m.viewsRect.height = m.itemViewers.boundingRect().height
        m.viewsRect.width = m.itemViewers.boundingRect().width + 6
        m.timestampLabel.text = m.top.itemContent.relativePublishDate
        m.timestampRect.height = m.timestampLabel.boundingRect().height
        m.timestampRect.width = m.timestampLabel.boundingRect().width + 6
    catch e
    end try
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = m.top.itemContent.streamerDisplayName
    m.itemThirdTitle.text = m.top.itemContent.gameDisplayName
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub UserSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.circlePoster = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid or m.itemThirdTitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    m.itemposter.visible = false
    m.circlePoster.uri = m.top.itemContent.streamerProfileImageUrl
    m.circlePoster.visible = true
    m.itemlabel.maxwidth = 150
    m.itemlabel.translation = "[0,160]"
    m.itemSubtitle.translation = "[0, 170]"
    m.itemThirdTitle.translation = "[0, 180]"
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.followerDisplay
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub onGetFocus()
    if m.top.itemHasFocus
        if m.itemLabel.localBoundingRect().width > m.itemLabel.maxWidth
            m.itemLabel.repeatCount = -1
        end if
    else
        m.itemLabel.repeatCount = 0
    end if
end sub

sub showrowfocus()
    m.itemmask.opacity = 0.75 - (m.top.rowFocusPercent * 0.75)
end sub
