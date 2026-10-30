sub main()
    m.assertions = 0
    m.failures = 0
    screen = createObject("roSGScreen")
    screen.setMessagePort(createObject("roMessagePort"))
    m.global = screen.getGlobalNode()
    setConstants()
    history = []
    for i = 0 to 9
        history.push({ login: "ring-" + i.toStr(), displayName: "Ring " + i.toStr(), iconUrl: "pkg:/images/profile-mask-540-white.png" })
    end for
    m.global.addFields({ recentRingHistory: history })
    scene = screen.createScene("RecentRingHost")
    screen.show()
    rail = scene.findNode("recentlyWatchedBar")
    testItems(rail)
    rail.callFunc("onDestroy")
    screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_RECENT_RING_FAIL: "; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_RECENT_RING_FAIL: "; message
    end if
end sub

' Transform the actual Poster rectangle through the current SceneGraph parents.
' These components use translations only; do not reproduce their layout rules.
function boundsIn(node as object, ancestor as object) as object
    rect = { x: 0.0, y: 0.0, width: node.width, height: node.height }
    cursor = node
    while not cursor.isSameNode(ancestor)
        rect.x += cursor.translation[0]
        rect.y += cursor.translation[1]
        cursor = cursor.getParent()
    end while
    return rect
end function

function contains(outer as object, inner as object) as boolean
    return inner.x >= outer.x and inner.y >= outer.y and inner.x + inner.width <= outer.x + outer.width and inner.y + inner.height <= outer.y + outer.height
end function

function sameCenter(a as object, b as object) as boolean
    return a.x + a.width / 2 = b.x + b.width / 2 and a.y + a.height / 2 = b.y + b.height / 2
end function

sub checkGeometry(item as object, rail as object, context as string)
    ring = item.findNode("selectionIndicator")
    face = item.findNode("avatar").findNode("examplePoster")
    dot = item.findNode("liveDot")
    faceRect = boundsIn(face, item)
    ringRect = boundsIn(ring, item)
    check(face.width > 0 and face.height > 0, context + ": the actual aliased face has size")
    check(sameCenter(ringRect, faceRect), context + ": ring and masked face are concentric")
    check(contains(ringRect, faceRect), context + ": the full face fits inside the focus footprint")
    check(ringRect.x >= 0 and ringRect.y >= 0, context + ": the full ring stays inside the item origin")
    dotRect = boundsIn(dot, item)
    check(contains(ringRect, dotRect), context + ": the live badge fits the item footprint")
    check(dotRect.x + dotRect.width = faceRect.x + faceRect.width and dotRect.y + dotRect.height = faceRect.y + faceRect.height, context + ": the live badge retains its alignment with the face corner")
    check(dot.getParent().isSameNode(ring.getParent()), context + ": the live badge stays outside the circular mask")
    check(ring.width = ring.height and ring.width = 64, context + ": the original full circle is drawn at native size")
    check(ring.uri = "pkg:/images/twitch-redesign/ring-64.png", context + ": the complete ring asset remains in use")
    check(not dot.visible or item.isLive, context + ": focus does not create a live badge")

    railRect = boundsIn(ring, rail)
    background = rail.findNode("backgroundBar")
    check(railRect.x >= 0 and railRect.x + railRect.width <= background.width, context + ": the whole ring fits the rail width")
    check(railRect.x + railRect.width / 2 = background.width / 2, context + ": the ring is centered in the rail")
    check(railRect.y >= 0 and railRect.y + railRect.height <= background.height, context + ": the full ring fits the rail height, including the first row")
    if item.focused
        caption = rail.callFunc("fixtureRead").caption
        plate = caption.findNode("captionPlate")
        check(caption.translation[1] + plate.height / 2 = railRect.y + railRect.height / 2, context + ": the caption stays centered beside the avatar")
    end if

    ' Check every real active clip in the ancestor chain, rather than inventing
    ' a list-cell clip. RecentlyWatchedBar creates Groups, not grid cells.
    cursor = ring
    while cursor <> invalid
        if cursor.hasField("clippingRect")
            clip = cursor.clippingRect
            if clip.width > 0 and clip.height > 0
                check(contains(clip, boundsIn(ring, cursor)), context + ": the full ring fits an active ancestor clippingRect")
            end if
        end if
        cursor = cursor.getParent()
    end while
end sub

sub testItems(rail as object)
    state = rail.callFunc("fixtureRead")
    first = state.items[0]
    ring = first.findNode("selectionIndicator")
    dot = first.findNode("liveDot")
    check(not ring.visible and not dot.visible, "an unfocused offline item has no ring or live badge")
    rail.itemHasFocus = true
    check(ring.visible and not dot.visible, "focus shows only the ring on an offline item")
    checkGeometry(first, rail, "first row")
    firstRing = boundsIn(ring, rail)
    icon = rail.findNode("icon")
    check(firstRing.y > icon.translation[1] + icon.height, "the first row focus footprint clears the recent-history icon")

    state.task.response = { "ring-0": true }
    check(dot.visible and ring.visible, "a live response adds the badge without hiding focus")
    checkGeometry(first, rail, "live first row")
    faceBefore = boundsIn(first.findNode("avatar").findNode("examplePoster"), first)
    dotBefore = boundsIn(dot, first)
    first.itemData = { login: "updated", displayName: "Updated", iconUrl: "pkg:/images/profile-mask-540.png", pinned: true }
    checkGeometry(first, rail, "avatar URI updated")
    check(sameCenter(faceBefore, boundsIn(first.findNode("avatar").findNode("examplePoster"), first)), "changing avatar URI does not move the face")
    check(sameCenter(dotBefore, boundsIn(dot, first)), "changing avatar URI does not move the live badge")

    rail.callFunc("fixtureKey", "down")
    check(not ring.visible and dot.visible, "leaving a live item hides its ring and retains its badge")
    second = rail.callFunc("fixtureRead").items[1]
    checkGeometry(second, rail, "second row")
    check(boundsIn(second.findNode("selectionIndicator"), rail).y - firstRing.y = 68, "the rail leaves space between complete rings")
    for i = 0 to 7
        rail.callFunc("fixtureKey", "down")
    end for
    state = rail.callFunc("fixtureRead")
    check(state.index = 9 and state.items[9].visible and not first.visible, "scrolling keeps the final item visible and hides the first")
    checkGeometry(state.items[9], rail, "scrolled focused last row")
    for i = 0 to 8
        rail.callFunc("fixtureKey", "up")
    end for
    checkGeometry(first, rail, "recycled first row focus")
    check(sameCenter(firstRing, boundsIn(ring, rail)), "scrolling back restores the first ring position")
    rail.itemHasFocus = false
    first.isLive = false
    check(not ring.visible and not dot.visible, "focus and live state clear independently after reuse")
    rail.callFunc("fixtureRefresh")
    rail.itemHasFocus = true
    rebuilt = rail.callFunc("fixtureRead").items[0]
    check(not rebuilt.isSameNode(first), "an unfocused history refresh rebuilds actual item components")
    checkGeometry(rebuilt, rail, "rebuilt first row")
end sub
