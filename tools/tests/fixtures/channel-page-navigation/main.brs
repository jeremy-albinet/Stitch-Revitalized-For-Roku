sub main()
    m.port = createObject("roMessagePort")
    m.assertions = 0
    m.failures = 0
    screen = createObject("roSGScreen")
    screen.setMessagePort(m.port)
    scene = screen.createScene("FixtureScene")
    screen.show()
    glob = screen.getGlobalNode()
    first = scene.callFunc("fixtureStart")
    pause(100)
    request = scene.callFunc("fixtureRead").request
    task = first.callFunc("fixtureRead").task
    task.response = fixtureResponse()
    pause(250)
    state = scene.callFunc("fixtureRead")
    print "CHANNEL_NAV_AFTER_RESPONSE:pages="; state.pages.count(); ":depth="; state.depth
    if state.pages.count() = 5
        ' Reproduce the observed response order: the top two pages lose LIVE
        ' when a retained page's later response reparents the shared request.
        for each ix in [1, 3, 4, 2]
            state.pages[ix].callFunc("fixtureRead").task.response = fixtureResponse()
            pause(80)
        end for
    end if
    pause(350)
    state = scene.callFunc("fixtureRead")
    page = state.active
    rowlist = page.callFunc("fixtureRead").rowlist
    liveRow = rowlist.content.getChild(0)
    print "CHANNEL_NAV_FINAL:pages="; state.pages.count(); ":depth="; state.depth; ":liveChildren="; liveRow.getChildCount()
    check(state.pages.count() = 1 and state.depth = 1, "one Recents selection opens exactly one ChannelPage")
    check(task.isSameNode(first.callFunc("fixtureRead").task) and task.control = "run", "response does not restart updatePage or replace its task")
    check(liveRow.getChildCount() = 1, "visible Live now row keeps its child after overlapping responses")
    check(liveRow.getChild(0).contentTitle = "Current title" and request.contentTitle = "", "a recent-channel LIVE request receives the fetched title without changing the shared request")
    check(request.getParent() = invalid and request.streamerId = "" and request.previewImageURL = "" and request.viewersCount = 0, "navigation request stays unparented and unchanged")
    allIds = true
    for each contentRow in rowlist.content.getChildren(rowlist.content.getChildCount(), 0)
        for each item in contentRow.getChildren(contentRow.getChildCount(), 0)
            if item.streamerId <> "123" then allIds = false
        end for
    end for
    check(allIds and rowlist.content.getChildCount() = 3, "response ID reaches LIVE, CLIP and VOD items")
    rendered = false
    if liveRow.getChildCount() = 1
        live = liveRow.getChild(0)
        for each card in glob.fixtureCards
            if card.itemContent <> invalid and card.itemContent.isSameNode(live)
                rendered = card.findNode("itemPoster").uri <> "" and card.findNode("posterBase").visible and card.findNode("liveIcon").visible and card.findNode("avatarGroup").visible and card.findNode("itemViewers").text = "482 Viewers"
            end if
        end for
    end if
    check(rendered, "actual RowList populates actual VideoItem before any keys")
    check(rowlist.rowItemSize.count() = 3 and rowlist.rowHeights[0] = 295 and rowlist.rowHeights[1] = 295 and rowlist.rowHeights[2] = 295, "all three populated rows retain valid geometry")
    print "FIXTURE_KEY:ok"
    pause(350)
    selected = false
    if page.contentSelected <> invalid then selected = page.playContent and page.contentSelected.contentType = "LIVE" and page.contentSelected.streamerLogin = "fixture-channel" and page.contentSelected.streamerId = "123"
    check(selected, "first real OK selects playable LIVE content")
    ' An unchanged response builds another owned row without emptying the old
    ' collection or writing back through the shared navigation request.
    page.callFunc("fixtureRead").task.response = fixtureResponse()
    pause(150)
    updatedRow = page.callFunc("fixtureRead").rowlist.content.getChild(0)
    stable = liveRow.getChildCount() = 1 and updatedRow.getChildCount() = 1
    if stable then stable = not liveRow.getChild(0).isSameNode(updatedRow.getChild(0))
    check(stable, "unchanged response leaves both old and new LIVE rows populated with separate items")
    state = scene.callFunc("fixtureRead")
    check(state.pages.count() = 1 and state.depth = 1 and request.streamerId = "" and request.previewImageURL = "", "unchanged response cannot reopen navigation or mutate its request")
    missingTitle = fixtureResponse()
    missingTitle.liveTitle = ""
    page.callFunc("fixtureRead").task.response = missingTitle
    pause(150)
    fallback = page.callFunc("fixtureRead").rowlist.content.getChild(0).getChild(0)
    check(fallback.contentTitle <> "" and request.contentTitle = "", "missing fetched titles fall back to the channel name without mutating navigation metadata")
    print "FIXTURE_KEY:back"
    pause(350)
    state = scene.callFunc("fixtureRead")
    check(state.active.id = "PriorPage" and state.depth = 0, "one real Back restores the preceding page")
    screen.close()
    if m.failures = 0 then print "__PASS_MARKER__:"; m.assertions; " assertions"
end sub

function fixtureResponse() as object
    return {
        streamerId: "123", description: "", followerCount: 10, profileImageUrl: "pkg:/images/default_banner.png",
        isLive: true, liveTitle: "Current title", liveViewersCount: 482, liveGameDisplayName: "Current game",
        videoShelves: [
            { node: { title: "Featured clips", items: [{ id: "clip1", slug: "clip1", title: "Clip one", viewCount: 23, createdAt: "2026-10-01T00:00:00Z", thumbnailURL: "pkg:/images/default_banner.png" }] } },
            { node: { title: "Recent broadcasts", items: [{ id: "vod1", vodTitle: "VOD one", vodViewCount: 56, vodCreatedAt: "2026-10-01T00:00:00Z", thumbnailURL: "pkg:/images/default_banner.png" }] } }
        ]
    }
end function

sub check(ok as boolean, label as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_CHANNEL_NAV_FAIL:"; label
    end if
end sub

sub pause(duration as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < duration
        wait(25, m.port)
    end while
end sub
