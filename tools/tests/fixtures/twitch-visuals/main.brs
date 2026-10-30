' Twitch redesign visual contracts on the actual card and settings-row
' components: focus is drawn by the item itself (RowList/MarkupList focus
' bitmaps sit under opaque thumbnails and plates on Roku), it follows list
' focus, card text clears the focus slab and fits the row heights from
' contentBuilder, and stat pills are never ellipsized.

sub main()
    m.assertions = 0
    m.failures = 0
    m.screen = createObject("roSGScreen")
    m.port = createObject("roMessagePort")
    m.screen.setMessagePort(m.port)
    m.global = m.screen.getGlobalNode()
    setConstants()
    m.scene = m.screen.createScene("VisualsHost")
    m.screen.show()
    m.lift = m.global.constants.ui.layout.cardLift
    testLiveCard()
    testRecycledCards()
    testCompactCard()
    testSettingsRow()
    m.screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_VISUALS_FAIL:"; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_VISUALS_FAIL: "; message
    end if
end sub

function content(fields as object) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields(fields)
    return node
end function

function liveFields() as object
    return {
        contentType: "LIVE",
        contentTitle: "Ranked grind until diamond, chill vibes",
        viewersCount: 12450,
        streamerDisplayName: "Ammo",
        gameDisplayName: "Valorant",
        previewImageURL: "pkg:/images/default_banner.png",
        streamerProfileImageUrl: "pkg:/images/twitch-redesign/live-dot.png"
    }
end function

sub focusCard(card as object, listFocused as boolean, percent as float)
    card.rowListHasFocus = listFocused
    card.itemHasFocus = percent >= 0.5
    card.focusPercent = percent
end sub

' EmojiLabel y is the centre of its 28 px line.
function titleTop(card as object) as float
    return card.findNode("itemLabel").translation[1] - 14
end function

function subtitleBottom(card as object) as float
    subtitle = card.findNode("itemSubtitle")
    return subtitle.translation[1] + subtitle.height
end function

function pillFits(card as object, labelId as string, plateId as string) as boolean
    label = card.findNode(labelId)
    plate = card.findNode(plateId)
    if label.text = "" or not plate.visible then return false
    return label.isTextEllipsized = false and plate.width = label.width + 16 and label.translation[0] = plate.translation[0] + 8
end function

sub testLiveCard()
    card = m.scene.createChild("VideoItem")
    card.itemContent = content(liveFields())
    lift = card.findNode("lift")
    check(not lift.visible, "a card shows no focus before its list has focus")
    check(card.findNode("avatarGroup").visible and card.findNode("itemLabel").translation[0] = 52 and card.findNode("itemSubtitle").translation[0] = 52, "a live card with an avatar starts its text beside the 40 px avatar")
    check(card.findNode("itemSubtitle").text = "Ammo · Valorant", "the subtitle names the channel and category")
    check(pillFits(card, "itemViewers", "viewsRect"), "the viewer pill fits its whole text with 8 px padding")
    check(card.findNode("liveIcon").visible, "a live card shows the LIVE pill")

    focusCard(card, true, 1.0)
    check(card.findNode("itemLabel").width > card.findNode("itemLabel").maxWidth and card.findNode("itemLabel").repeatCount = -1, "an overflowing focused title scrolls using its unclipped text width")
    slab = card.findNode("liftSlab")
    top = card.findNode("liftTop")
    bottom = card.findNode("liftBottom")
    check(lift.visible and slab.translation[0] = -m.lift and slab.translation[1] = m.lift, "full focus offsets the purple slab down-left by cardLift")
    check(slab.width = 320 and slab.height = 180, "the slab matches the thumbnail")
    check(top.translation[0] = -m.lift and top.translation[1] = 0 and top.width = m.lift, "the top bevel closes the slab's top-left corner")
    check(bottom.translation[0] = 320 - m.lift and bottom.translation[1] = 180 and bottom.height = m.lift, "the bottom bevel closes the slab's bottom-right corner")
    poster = card.findNode("itemPoster")
    check(poster.translation[0] = 0 and poster.translation[1] = 0, "the thumbnail itself never moves")

    focusCard(card, true, 0.5)
    check(lift.visible and slab.translation[1] = m.lift / 2, "the slab follows the RowList focus animation")
    focusCard(card, false, 1.0)
    check(card.findNode("itemLabel").repeatCount = 0, "a title stops scrolling when its list loses focus")
    check(not lift.visible, "focus disappears when the menu or rail takes focus")
    focusCard(card, true, 0.0)
    check(not lift.visible, "an unfocused card in a focused list shows no slab")

    check(titleTop(card) >= 180 + m.lift, "the title line starts below the focus slab")
    check(card.findNode("itemSubtitle").translation[1] >= titleTop(card) + 28, "the subtitle starts below the title line")
    check(subtitleBottom(card) <= getRowConfig("LIVE", false, true).rowHeight, "live card text fits an unlabeled tall row")
    m.scene.removeChild(card)
end sub

sub testRecycledCards()
    card = m.scene.createChild("VideoItem")
    card.itemContent = content(liveFields())
    card.itemContent = content({ contentType: "GAME", contentTitle: "Just Chatting", viewersCount: 310000, gameBoxArtUrl: "pkg:/images/default_banner.png" })
    focusCard(card, true, 1.0)
    slab = card.findNode("liftSlab")
    check(card.findNode("lift").visible and slab.width = 188 and slab.height = 250, "a recycled category tile lifts its box art, not the old thumbnail size")
    check(not card.findNode("avatarGroup").visible and card.findNode("itemLabel").translation[0] = 0, "a category tile drops the previous card's avatar and indent")
    check(not card.findNode("viewsRect").visible and not card.findNode("liveIcon").visible, "a category tile has no stat or LIVE pill")
    check(titleTop(card) >= 250 + m.lift and subtitleBottom(card) <= getRowConfig("GAME", false).rowHeight, "category text clears the slab and fits its row")

    card.itemContent = content({ contentType: "USER", contentTitle: "Northwind", followerCount: 120400, streamerProfileImageUrl: "pkg:/images/twitch-redesign/live-dot.png" })
    focusCard(card, true, 1.0)
    ring = card.findNode("circleRing")
    check(ring.visible and not card.findNode("lift").visible, "a channel circle shows a ring instead of the slab")
    check(titleTop(card) >= ring.translation[1] + ring.height and subtitleBottom(card) <= getRowConfig("USER", false).rowHeight, "channel text clears the ring and fits its row")
    focusCard(card, false, 1.0)
    check(not ring.visible, "the ring follows list focus")

    card.itemContent = content({ contentType: "VOD", contentTitle: "Day 40", viewersCount: 18000, datePublished: "2026-10-01T12:00:00Z", streamerDisplayName: "Cubesmith", previewImageURL: "pkg:/images/default_banner.png" })
    check(not card.findNode("circleRing").visible and not card.findNode("liveIcon").visible and not card.findNode("avatarGroup").visible, "a video card resets the circle, LIVE pill and avatar")
    check(pillFits(card, "itemViewers", "viewsRect") and pillFits(card, "timestampLabel", "timestampRect"), "video view and date pills fit their text")
    focusCard(card, true, 1.0)
    check(card.findNode("lift").visible and card.findNode("liftSlab").width = 320, "a recycled video card lifts at thumbnail size")

    noViewers = liveFields()
    noViewers.delete("viewersCount")
    card.itemContent = content(noViewers)
    check(not card.findNode("viewsRect").visible and not card.findNode("itemViewers").visible, "a live card without a viewer count shows no empty pill")
    m.scene.removeChild(card)
end sub

sub testCompactCard()
    m.global.compactGrid = true
    card = m.scene.createChild("VideoItem")
    card.itemContent = content(liveFields())
    focusCard(card, true, 1.0)
    poster = card.findNode("itemPoster")
    slab = card.findNode("liftSlab")
    check(poster.width = 256 and poster.height = 144 and slab.width = poster.width and slab.height = poster.height, "compact thumbnails and their focus slabs use the shared card dimensions")
    check(poster.loadWidth = 256 and poster.loadHeight = 144, "compact previews use matching logical decode sizes for Roku autoscaling")
    check(card.findNode("itemLabel").font.size = 18 and card.findNode("itemSubtitle").font.size = 16, "compact card typography stays readable without changing the comfortable default")
    check(titleTop(card) >= poster.height + m.lift and subtitleBottom(card) <= getRowConfig("LIVE", false, true).rowHeight, "compact card text clears the focus slab and fits the actual row height")
    check(card.findNode("avatarGroup").translation[1] = 166 and card.findNode("viewsRect").translation[1] = 112, "compact avatars and stat pills follow the smaller thumbnail")
    card.itemContent = content({ contentType: "GAME", contentTitle: "A category", gameBoxArtUrl: "pkg:/images/default_banner.png" })
    check(poster.loadWidth = 188 and poster.loadHeight = 250, "category art uses its matching logical decode size")
    card.itemContent = content({ contentType: "VOD", contentTitle: "A recording", streamerDisplayName: "Fixture", gameDisplayName: "Category", previewImageURL: "pkg:/images/default_banner.png" })
    check(poster.width = 256 and poster.height = 144 and card.findNode("itemLabel").maxWidth = 256, "recycling a category card restores compact video geometry")
    check(poster.loadWidth = 256 and poster.loadHeight = 144, "recycled video previews restore the compact decode size")
    m.global.compactGrid = false
    comfortable = m.scene.createChild("VideoItem")
    comfortable.itemContent = content(liveFields())
    check(comfortable.findNode("itemPoster").width = 320 and comfortable.findNode("itemLabel").font.size = 20, "returning to comfortable mode restores its original card size and font")
    check(comfortable.findNode("itemPoster").loadWidth = 320 and comfortable.findNode("itemPoster").loadHeight = 180, "comfortable previews retain their logical decode size")
end sub

sub testSettingsRow()
    row = m.scene.createChild("SettingsListItem")
    item = createObject("roSGNode", "ContentNode")
    item.title = "Lower live latency"
    item.shortDescriptionLine1 = "Off"
    row.itemContent = item
    row.width = 520
    row.height = 60
    ring = row.findNode("focusRing")
    check(not ring.visible, "an idle settings row has no ring")
    row.listHasFocus = true
    row.focusPercent = 1.0
    check(ring.visible and ring.width = 520 and ring.height = 60, "the focused row draws its own ring at the row size")
    row.listHasFocus = false
    check(not ring.visible, "the row ring follows list focus")
    m.scene.removeChild(row)
end sub
