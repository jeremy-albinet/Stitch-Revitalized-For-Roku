sub main()
    m.assertions = 0
    m.failures = 0
    m.fixturePort = createObject("roMessagePort")
    screen = createObject("roSGScreen")
    screen.setMessagePort(m.fixturePort)
    scene = screen.createScene("FixtureScene")
    screen.show()
    fixtureGlobal = screen.getGlobalNode()
    testFollowing(scene, fixtureGlobal)
    testRetainedSelection(scene, fixtureGlobal)
    testChannelBroadcasterId(scene)
    testChannelLiveThumbnail(scene)
    testChannelLiveViewers(scene)
    testChannelLiveOwnership(scene)
    testLateAccountResponse(scene, fixtureGlobal)
    testBrowse(scene)
    testDetailPages(scene)
    testRoute(scene)
    testSearch(scene)
    testMenu(scene, fixtureGlobal)
    testRail(scene, fixtureGlobal)
    screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_UI_FAIL:"; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub testChannelLiveThumbnail(scene as object)
    generated = "https://static-cdn.jtvnw.net/previews-ttv/live_user_recent_channel-1280x720.jpg"
    for each sample in [
            { kind: "LIVE", preview: "", expected: generated },
            { kind: "LIVE", preview: "pkg:/images/default_banner.png", expected: "pkg:/images/default_banner.png" },
            { kind: "USER", preview: "", expected: generated }
        ]
        page = addPage(scene, "ChannelPage")
        content = createObject("roSGNode", "TwitchContentNode")
        fields = cardFields(sample.kind, "recent_channel")
        fields.previewImageURL = sample.preview
        setTwitchContentFields(content, fields)
        page.contentRequested = content
        state = inspect(page)
        state.task.response = channelIdResponse()
        live = inspect(page).rowlist.content.getChild(0).getChild(0)
        check(live.previewImageURL = sample.expected, sample.kind + " live card has a preview when opened from Recents and preserves an existing preview")
        check(content.previewImageURL = sample.preview, sample.kind + " thumbnail fallback leaves the request unchanged")
        page.callFunc("fixtureSelect", 0)
        check(page.playContent and page.contentSelected.previewImageURL = sample.expected, sample.kind + " live selection retains the thumbnail and playback contract")
        disposePage(scene, page)
    end for
end sub

sub testChannelLiveViewers(scene as object)
    for each sample in [
            { count: 2468, expected: 2468 },
            { count: 0, expected: 0 },
            { count: invalid, expected: 99 },
            { count: "invalid", expected: 99 },
            { count: -1, expected: 99 }
        ]
        page = addPage(scene, "ChannelPage")
        content = createObject("roSGNode", "TwitchContentNode")
        fields = cardFields("LIVE", "recent_channel")
        fields.viewersCount = 99
        setTwitchContentFields(content, fields)
        page.contentRequested = content
        response = channelIdResponse()
        response.liveViewersCount = sample.count
        state = inspect(page)
        state.task.response = response
        live = inspect(page).rowlist.content.getChild(0).getChild(0)
        check(not live.isSameNode(content) and live.viewersCount = sample.expected, "current channel viewers refresh the owned LIVE card, including zero, without erasing valid counts on bad data")
        check(content.viewersCount = 99 and content.getParent() = invalid, "viewer refresh preserves the original unparented LIVE request")
        page.callFunc("fixtureSelect", 0)
        check(page.contentSelected.viewersCount = sample.expected, "live playback selection carries the refreshed viewer count")
        disposePage(scene, page)
    end for
end sub

sub testChannelLiveOwnership(scene as object)
    fields = cardFields("LIVE", "owned-live")
    fields.append({ contentId: "live-id", contentTitle: "Original title", createdAt: "2026-10-01T00:00:00Z", gameDisplayName: "Original game", gameId: "game-id", gameName: "original-game", gameBoxArtUrl: "pkg:/images/default_banner.png", streamerId: "original-id", streamerProfileImageUrl: "pkg:/images/default_banner.png", datePublished: "2026-10-01T00:00:00Z", url: "https://example.invalid/stream.m3u8" })
    content = createObject("roSGNode", "TwitchContentNode")
    setTwitchContentFields(content, fields)
    owner = createObject("roSGNode", "ContentNode")
    owner.appendChild(content)
    page = addPage(scene, "ChannelPage")
    page.contentRequested = content
    response = channelIdResponse()
    response.streamerId = "resolved-id"
    response.liveViewersCount = 482
    inspect(page).task.response = response
    live = inspect(page).rowlist.content.getChild(0).getChild(0)
    check(owner.getChildCount() = 1 and content.getParent().isSameNode(owner), "LIVE construction keeps the request attached to its original owner")
    for each key in fields
        check(content[key] = fields[key], "LIVE construction preserves request field " + key)
        if key <> "streamerId" and key <> "viewersCount"
            check(live[key] = fields[key], "separate LIVE card retains metadata field " + key)
        end if
    end for
    check(live.streamerId = "resolved-id" and live.viewersCount = 482, "only the owned LIVE item receives current ID and viewers")
    disposePage(scene, page)
end sub

sub testChannelBroadcasterId(scene as object)
    for each kind in ["LIVE", "USER", "VOD", "CLIP"]
        page = addPage(scene, "ChannelPage")
        content = createObject("roSGNode", "TwitchContentNode")
        setTwitchContentFields(content, cardFields(kind, "recent-channel"))
        if kind = "VOD" or kind = "CLIP"
            content.contentId = "recording-id"
            content.clipSlug = "recording-slug"
        end if
        page.contentRequested = content
        check(content.streamerId = "", kind + " navigation starts without a broadcaster ID")
        s = inspect(page)
        response = channelIdResponse()
        response.streamerId = "71092938"
        s.task.response = response
        check(content.streamerId = "" and content.contentType = kind and content.getParent() = invalid, kind + " channel metadata leaves navigation identity and ownership unchanged")
        check(inspect(page).rowlist.content.getChildCount() = 3, kind + " channel metadata builds live, VOD and clip rows")
        checkChannelRowIds(page, "71092938", kind + " navigation")
        live = inspect(page).rowlist.content.getChild(0).getChild(0)
        check(not live.isSameNode(content), kind + " launch builds a separate LIVE card")
        if kind = "VOD" or kind = "CLIP"
            check(live.contentId = "" and live.clipSlug = "", kind + " request cannot copy recording or clip identity into the LIVE item")
            check(content.contentId = "recording-id" and content.clipSlug = "recording-slug", kind + " request keeps its original recording and clip identity")
        end if
        disposePage(scene, page)
    end for

    for each kind in ["LIVE", "USER", "VOD", "CLIP"]
        page = addPage(scene, "ChannelPage")
        content = createObject("roSGNode", "TwitchContentNode")
        setTwitchContentFields(content, cardFields(kind, "known-channel"))
        content.streamerId = "existing-id"
        page.contentRequested = content
        s = inspect(page)
        for each sample in [
                { fields: {}, expectedId: "existing-id" },
                { fields: { streamerId: "" }, expectedId: "existing-id" },
                { fields: { streamerId: invalid }, expectedId: "existing-id" },
                { fields: { streamerId: 71092938 }, expectedId: "existing-id" },
                { fields: { streamerId: true }, expectedId: "existing-id" },
                { fields: { streamerId: {} }, expectedId: "existing-id" },
                { fields: { streamerId: [] }, expectedId: "existing-id" },
                { fields: { streamerId: "existing-id" }, expectedId: "existing-id" },
                { fields: { streamerId: "updated-id" }, expectedId: "updated-id" }
            ]
            response = channelIdResponse()
            response.append(sample.fields)
            s.task.response = response
            check(content.streamerId = "existing-id" and content.getParent() = invalid, kind + " response ID guard matrix preserves the original request")
            checkChannelRowIds(page, sample.expectedId, kind + " response ID guard matrix")
        end for
        s.task.response = invalid
        check(content.streamerId = "existing-id" and inspect(page).status.state = "error", kind + " failed channel response preserves the existing ID and failure status contract")
        disposePage(scene, page)
    end for
end sub

function channelIdResponse() as object
    return {
        isLive: true,
        description: "",
        followerCount: 2,
        liveTitle: "Current live stream",
        videoShelves: [
            { node: { title: "Recent videos", items: [{ id: "vod-1", vodTitle: "Recording", vodViewCount: 4, vodCreatedAt: "2026-10-01T00:00:00Z" }] } },
            { node: { title: "Clips", items: [{ id: "clip-1", slug: "fixture-clip", title: "Clip", viewCount: 3, createdAt: "2026-10-01T00:00:00Z" }] } }
        ]
    }
end function

sub checkChannelRowIds(page as object, expectedId as string, context as string)
    rowIndex = 0
    for each kind in ["LIVE", "VOD", "CLIP"]
        page.callFunc("fixtureSelect", rowIndex)
        selected = page.contentSelected
        check(page.playContent and selected.contentType = kind and selected.streamerId = expectedId, context + " emits " + kind + " with the broadcaster ID")
        rowIndex += 1
    end for
end sub

sub testRetainedSelection(scene as object, fixtureGlobal as object)
    fixtureGlobal.fixtureSigned = true
    page = addPage(scene, "Following")
    s = inspect(page)
    s.task.response = { liveFollows: [cardFields("LIVE", "live-one")], offlineFollows: [cardFields("USER", "offline-one")] }
    page.callFunc("fixtureSelect", 0)
    check(page.playContent and page.contentSelected.contentType = "LIVE", "Following live selection requests direct playback")
    page.setFocus(true)
    page.callFunc("fixtureSelect", 1)
    check(not page.playContent and page.contentSelected.contentType = "USER", "retained Following offline selection clears direct playback")
    page.callFunc("fixtureSelect", 0)
    check(page.playContent and page.contentSelected.contentType = "LIVE", "retained Following can play live again")
    disposePage(scene, page)
    fixtureGlobal.fixtureSigned = false

    page = addPage(scene, "ChannelPage")
    content = createObject("roSGNode", "TwitchContentNode")
    setTwitchContentFields(content, cardFields("USER", "went-live"))
    page.contentRequested = content
    s = inspect(page)
    s.task.response = { isLive: true, videoShelves: [], description: "", followerCount: 2, liveTitle: "A live stream title", liveViewersCount: 2468, liveGameDisplayName: "Fixture Game" }
    page.callFunc("fixtureSelect", 0)
    selected = page.contentSelected
    check(page.playContent and selected.contentType = "LIVE", "fresh live status turns an offline channel request into playable LIVE content")
    check(selected.streamerLogin = content.streamerLogin and selected.streamerDisplayName = content.streamerDisplayName, "fresh live card preserves channel identity")
    check(content.contentType = "USER" and not content.isSameNode(selected), "building the live card preserves the original navigation request")
    check(selected.contentTitle = "A live stream title" and selected.gameDisplayName = "Fixture Game" and selected.viewersDisplay = "2.4K Viewers", "new LIVE card carries current title category and formatted viewers")
    card = createObject("roSGNode", "VideoItem")
    scene.appendChild(card)
    ' Keep the actual card text handlers; only thumbnail fetching is local.
    rendered = createObject("roSGNode", "TwitchContentNode")
    setTwitchContentFields(rendered, selected.getFields())
    rendered.previewImageURL = "pkg:/images/default_banner.png"
    card.itemContent = rendered
    check(card.findNode("itemLabel").text = "A live stream title", "the real LIVE card renders its stream title")
    check(card.findNode("itemViewers").text = "2.4K Viewers", "the real LIVE card renders its viewer count")
    check(card.findNode("itemSubtitle").text.InStr("Fixture Game") >= 0, "the real LIVE card renders its category")
    card.callFunc("onDestroy")
    scene.removeChild(card)
    disposePage(scene, page)
    page = addPage(scene, "ChannelPage")
    content = createObject("roSGNode", "TwitchContentNode")
    setTwitchContentFields(content, cardFields("VOD", "went-live"))
    content.contentId = "old-recording"
    content.contentTitle = "Old recording title"
    content.gameDisplayName = "Old recording game"
    content.viewersCount = 9000
    page.contentRequested = content
    s = inspect(page)
    s.task.response = { isLive: true, videoShelves: [], description: "", followerCount: 2, liveTitle: "A current live title", liveViewersCount: 2468, liveGameDisplayName: "Fixture Game" }
    page.callFunc("fixtureSelect", 0)
    check(page.contentSelected.contentType = "LIVE" and page.contentSelected.contentId <> "old-recording", "Live now opened through a Search VOD cannot replay that recording")
    check(content.contentType = "VOD" and content.contentId = "old-recording", "live playback leaves the original VOD navigation identity intact")
    check(page.contentSelected.contentTitle = "A current live title" and page.contentSelected.gameDisplayName = "Fixture Game" and page.contentSelected.viewersCount = 2468, "VOD navigation gets live metadata instead of recording metadata")
    check(content.contentTitle = "Old recording title" and content.gameDisplayName = "Old recording game" and content.viewersCount = 9000, "live metadata leaves the original recording unchanged")
    s.task.response = { isLive: true, videoShelves: [], description: "", followerCount: 2 }
    page.callFunc("fixtureSelect", 0)
    check(page.contentSelected.contentTitle = content.streamerDisplayName and page.contentSelected.gameDisplayName = "" and page.contentSelected.viewersCount = 0, "missing live metadata falls back without carrying recording metadata")
    disposePage(scene, page)
end sub

sub testLateAccountResponse(scene as object, fixtureGlobal as object)
    fixtureGlobal.fixtureSigned = true
    menu = addMenu(scene)
    menu.updateUserIcon = true
    oldTask = inspect(menu).loginTask
    check(oldTask <> invalid, "signed-in icon starts a metadata request")
    menu.updateUserIcon = true
    replacement = inspect(menu).loginTask
    check(oldTask.control = "stop" and not oldTask.isSameNode(replacement), "a replacement icon lookup destroys the old task")
    oldTask.response = { data: [{ id: "old", display_name: "Old", profile_image_url: "pkg:/images/default_banner.png" }] }
    fixtureGlobal.fixtureSigned = false
    menu.updateUserIcon = true
    check(replacement.control = "stop" and inspect(menu).loginTask = invalid, "sign-out destroys pending account metadata")
    icon = inspect(menu).icons.findNode("LoginPage")
    anonymousIcon = icon.iconUri
    replacement.response = { data: [{ id: "old", display_name: "Old", profile_image_url: "pkg:/images/default_banner.png" }] }
    check(icon.iconUri = anonymousIcon, "late signed-in response cannot overwrite the signed-out icon")
    disposePage(scene, menu)
    fixtureGlobal.fixtureSigned = true
    menu = addMenu(scene)
    menu.updateUserIcon = true
    stale = inspect(menu).loginTask
    fixtureGlobal.fixtureSigned = false
    stale.response = { data: [{ id: "wrong-profile", display_name: "Old", profile_image_url: "pkg:/images/default_banner.png" }] }
    check(inspect(menu).profileId = "", "a response for a different active profile cannot write account metadata even before its icon update")
    disposePage(scene, menu)
    fixtureGlobal.fixtureSigned = true
    menu = addMenu(scene)
    menu.updateUserIcon = true
    stale = inspect(menu).loginTask
    fixtureGlobal.addFields({ fixtureUser: "another-user" })
    stale.response = { data: [{ id: "wrong-profile", display_name: "Old", profile_image_url: "pkg:/images/default_banner.png" }] }
    check(inspect(menu).profileId = "", "a lookup cannot write metadata into a different signed-in profile")
    menu.updateUserIcon = true
    inspect(menu).loginTask.response = { data: [{ id: "current-profile", display_name: "Current", profile_image_url: "pkg:/images/default_banner.png" }] }
    check(inspect(menu).profileId = "current-profile", "the current profile still receives its own metadata")
    disposePage(scene, menu)
    fixtureGlobal.removeField("fixtureUser")
    fixtureGlobal.fixtureSigned = false
    fixtureGlobal.addFields({ fixtureAvatar: "pkg:/images/default_banner.png" })
    menu = addMenu(scene)
    check(inspect(menu).icons.findNode("LoginPage").iconUri = fixtureGlobal.constants.defaultIcons.login, "an anonymous launch ignores stale account metadata already in its profile")
    disposePage(scene, menu)
    fixtureGlobal.removeField("fixtureAvatar")
end sub

sub testFollowing(scene as object, fixtureGlobal as object)
    page = addPage(scene, "Following")
    s = inspect(page)
    check(s.status.state = "loading" and s.task.request.type = "getFollowingPageQuery", "anonymous Following starts loading")
    check(page.findNode("anonymousHint").visible, "anonymous Following keeps its recommendation hint")
    s.task.response = invalid
    s = inspect(page)
    check(s.status.state = "error" and s.status.actions.count() = 1, "Following invalid response offers Retry")
    old = s.task
    selectAction(s, 0)
    s = inspect(page)
    check(not old.isSameNode(s.task) and old.control = "stop" and s.status.state = "loading", "Following Retry replaces and stops the old task")
    current = s.task
    old.response = { shelves: [] }
    s = inspect(page)
    check(s.status.state = "loading" and current.isSameNode(s.task), "removed Following observer suppresses a stale response")
    s.task.response = { shelves: [] }
    s = inspect(page)
    check(s.status.state = "empty" and s.status.actions.count() = 2, "anonymous Following valid-empty differs from failure")
    s.status.setFocus(true)
    check(s.status.findNode("buttons").isInFocusChain(), "real StatusPanel actions receive child focus")
    menu = addMenu(scene)
    menu.findNode("MenuOptions").setFocus(true)
    check(menu.isInFocusChain() and not s.status.isInFocusChain(), "page actions release focus to the actual MenuBar")
    check(not s.rowlist.drawFocusFeedback, "actionable page keeps row feedback hidden when menu is focused")
    s.status.setFocus(true)
    fixtureGlobal.fixtureHistory = [{ login: "focus-rail", displayName: "Focus Rail", iconUrl: "pkg:/images/default_banner.png" }]
    rail = addPage(scene, "RecentlyWatchedBar")
    rail.itemHasFocus = true
    rail.setFocus(true)
    check(rail.isInFocusChain() and not s.status.isInFocusChain(), "page actions release focus to the actual recent rail")
    disposePage(scene, rail)
    fixtureGlobal.fixtureHistory = []
    s.status.setFocus(true)
    selectAction(s, 0)
    s = inspect(page)
    check(s.status.state = "loading" and not s.status.hasActions and s.rowlist.isInFocusChain(), "Retry hides actions and moves focus to sibling content")
    pending = s.task
    selectAction(s, 0)
    check(pending.isSameNode(inspect(page).task), "hidden loading action cannot create a duplicate task")
    s.task.response = { shelves: [] }
    s = inspect(page)
    selectAction(s, 9)
    check(page.menuRequest = "", "out-of-range action cannot navigate")
    selectAction(s, 1)
    check(page.menuRequest = "Browse", "child Go to Browse maps to the actual navigation field")
    old = s.task
    page.callFunc("fixtureCleanup")
    page.callFunc("fixtureCleanup")
    selectAction(s, 0)
    old.response = invalid
    check(inspect(page).task = invalid and old.control = "stop" and inspect(page).disposed, "Following disposal stops tasks and suppresses child/stale callbacks")
    disposePage(scene, menu)
    disposePage(scene, page)

    fixtureGlobal.fixtureSigned = true
    page = addPage(scene, "Following")
    s = inspect(page)
    check(s.signedIn and not page.findNode("anonymousHint").visible, "signed-in Following omits anonymous guidance")
    s.task.response = { liveFollows: [], offlineFollows: [] }
    s = inspect(page)
    check(s.status.state = "empty" and s.status.actions.count() = 1 and s.status.actions[0] = "Go to Browse", "zero followed channels offers Browse")
    s.task.response = { liveFollows: [], offlineFollows: [cardFields("USER", "offline-one")] }
    s = inspect(page)
    check(s.status.state = "hidden" and s.rowlist.content.getChildCount() = 1, "offline-only follows remain usable content")
    check(instr(0, s.rowlist.content.getChild(0).title, "No one you follow is live") > 0, "offline-only follows have meaningful row copy")
    s.rowlist.setFocus(true)
    check(s.rowlist.isInFocusChain() and s.rowlist.drawFocusFeedback, "loaded Following shows feedback for actual row focus")
    menu = addMenu(scene)
    menu.findNode("MenuOptions").setFocus(true)
    check(menu.isInFocusChain() and not s.rowlist.isInFocusChain() and not s.rowlist.drawFocusFeedback, "loaded Following releases focus and feedback to MenuBar")
    disposePage(scene, menu)
    disposePage(scene, page)
    fixtureGlobal.fixtureSigned = false
end sub

sub testBrowse(scene as object)
    page = addPage(scene, "Browse")
    s = inspect(page)
    check(s.status.state = "loading" and s.featured <> invalid and s.categories <> invalid and s.live <> invalid, "Browse launches a finite section set")
    check(s.featured.request.requireShelves = true, "Browse requires its shelves even when the account part of the shared query succeeds")
    s.featured.response = invalid
    s = inspect(page)
    check(s.status.state = "loading" and s.failed = 1, "Browse waits for pending siblings after one failure")
    s.live.response = { streams: [cardFields("LIVE", "live-one")], hasNextPage: true, cursor: "live-cursor" }
    s = inspect(page)
    row = s.rowlist.content.getChild(0)
    check(s.status.state = "hidden" and s.rowlist.visible and row.getChild(0).streamerLogin = "live-one", "Browse partial success is usable before all siblings settle")
    s.categories.response = invalid
    s = inspect(page)
    check(s.status.state = "hidden" and s.rowlist.content.getChild(0).isSameNode(row), "Browse sibling failures preserve loaded row identity")
    page.callFunc("fixtureMore")
    s = inspect(page)
    pending = s.live
    check(s.liveBuffering and pending.request.cursor = "live-cursor", "Browse pagination sends the current cursor")
    page.callFunc("fixtureMore")
    check(pending.isSameNode(inspect(page).live), "Browse suppresses duplicate pending pagination")
    pending.response = invalid
    s = inspect(page)
    check(not s.liveBuffering and s.status.state = "hidden" and s.rowlist.content.getChild(0).isSameNode(row), "failed pagination preserves existing content and clears pending")
    page.callFunc("fixtureMore")
    s = inspect(page)
    check(not pending.isSameNode(s.live) and pending.control = "stop", "Browse permits a finite explicit pagination retry")
    s.live.response = { streams: [cardFields("LIVE", "live-two")], hasNextPage: false, cursor: "" }
    s = inspect(page)
    check(s.rowlist.content.getChildCount() = 2 and s.rowlist.content.getChild(1).getChild(0).streamerLogin = "live-two", "later Browse success appends real native content")
    check(s.rowlist.rowItemSize.count() = s.rowlist.content.getChildCount() and s.rowlist.rowHeights.count() = s.rowlist.content.getChildCount(), "Browse row metadata stays aligned after append")
    disposePage(scene, page)

    page = addPage(scene, "Browse")
    s = inspect(page)
    s.featured.response = { shelves: [] }
    s.categories.response = { games: [], hasNextPage: false, cursor: "" }
    s.live.response = { streams: [], hasNextPage: false, cursor: "" }
    s = inspect(page)
    check(s.status.state = "empty" and s.failed = 0, "Browse all-success empty differs from error")
    oldFeatured = s.featured
    oldCategories = s.categories
    oldLive = s.live
    selectAction(s, 0)
    s = inspect(page)
    check(s.status.state = "loading" and not oldFeatured.isSameNode(s.featured) and not oldCategories.isSameNode(s.categories) and not oldLive.isSameNode(s.live), "Browse Retry replaces each section once")
    check(oldFeatured.control = "stop" and oldCategories.control = "stop" and oldLive.control = "stop", "Browse Retry stops every previous section")
    oldLive.response = { streams: [cardFields("LIVE", "stale")], hasNextPage: false, cursor: "" }
    check(inspect(page).status.state = "loading" and inspect(page).rowlist.content = invalid, "old Browse response cannot overwrite retry state")
    s.featured.response = invalid
    s.categories.response = invalid
    s.live.response = invalid
    s = inspect(page)
    check(s.status.state = "error" and s.failed = 3 and s.status.actions.count() = 1, "Browse all-invalid offers explicit Retry")
    selectAction(s, 0)
    s = inspect(page)
    pause(150)
    check(s.featured.isSameNode(inspect(page).featured), "Browse does not automatically retry pending loading")
    old = s.live
    page.callFunc("fixtureCleanup")
    old.response = invalid
    check(inspect(page).disposed and inspect(page).live = invalid and old.control = "stop", "Browse disposal removes pending observers and stops tasks")
    disposePage(scene, page)
end sub

sub testDetailPages(scene as object)
    for each name in ["GamePage", "ChannelPage"]
        page = addPage(scene, name)
        content = createObject("roSGNode", "TwitchContentNode")
        content.contentType = "LIVE"
        content.streamerLogin = "fixture-channel"
        content.streamerDisplayName = "Fixture Channel"
        content.gameName = "Fixture Game"
        page.contentRequested = content
        s = inspect(page)
        check(s.task <> invalid and s.status.state = "loading", name + " loads requested content")
        s.task.response = invalid
        s = inspect(page)
        check(s.status.state = "error" and s.status.actions.count() = 2, name + " failure offers Retry and Back")
        old = s.task
        selectAction(s, 0)
        s = inspect(page)
        check(not old.isSameNode(s.task) and old.control = "stop" and s.status.state = "loading", name + " Retry replaces a stopped task")
        if name = "GamePage"
            s.task.response = { edges: [] }
        else
            s.task.response = { isLive: false, videoShelves: [], description: "fixture", followerCount: 2 }
        end if
        s = inspect(page)
        check(s.status.state = "empty" and s.status.actions.count() = 1 and s.status.actions[0] = "Back", name + " valid-empty offers Back without claiming failure")
        selectAction(s, 0)
        check(page.backPressed, name + " child Back emits navigation")
        if name = "GamePage"
            edges = []
            for i = 0 to 6
                edges.push({ node: { id: i.toStr(), viewersCount: i, broadcaster: { login: "game-" + i.toStr(), displayName: "Game " + i.toStr(), id: i.toStr(), broadcastSettings: { title: "Stream" } } } })
            end for
            edges.unshift(invalid)
            edges.push({ node: { broadcaster: { login: "" } } })
            s.task.response = { edges: edges }
            s = inspect(page)
            check(s.status.state = "hidden" and s.rowlist.content.getChildCount() = 3, "Game handler retains valid streams and skips malformed entries")
            check(s.rowlist.content.getChild(0).getChildCount() = 3 and s.rowlist.content.getChild(1).getChildCount() = 3 and s.rowlist.content.getChild(2).getChildCount() = 1, "Game trailing partial row preserves all seven streams as 3/3/1")
        else
            s.task.response = { isLive: true, videoShelves: [], description: "fixture", followerCount: 2 }
            s = inspect(page)
            check(s.status.state = "hidden" and not s.rowlist.content.getChild(0).getChild(0).isSameNode(content), "Channel success exposes a separate live card and preserves the navigation request")
        end if
        old = s.task
        shell = s.shell
        page.callFunc("fixtureCleanup")
        page.callFunc("fixtureCleanup")
        s = inspect(page)
        check(s.task = invalid and old.control = "stop" and s.disposed, name + " cleanup is idempotent and stops task")
        if name = "ChannelPage" then check(s.shell = invalid and shell.control = "stop", "Channel cleanup stops its independent profile task")
        old.response = invalid
        check(s.status.state = "hidden", name + " disposed response cannot restore error status")
        disposePage(scene, page)
    end for
end sub

sub testRoute(scene as object)
    route = scene.callFunc("fixtureRoute")
    check(route.after.id = "Browse" and route.active = "Browse" and route.focus = "Browse", "Following child Browse action executes actual hero navigation and menu state")
    check(route.before.callFunc("fixtureRead").disposed and route.task.control = "stop", "hero routing disposes the departing page")
    check(route.afterStale.isSameNode(route.after), "disposed Following menuRequest cannot reroute the active page")
end sub

sub testSearch(scene as object)
    page = addPage(scene, "Search")
    s = inspect(page)
    s.kb.text = "alpha"
    pause(350)
    s.kb.text = "beta"
    pause(300)
    check(inspect(page).task = invalid, "Search restarts its actual half-second debounce after an edit")
    s = waitForSearch(page)
    check(s.task <> invalid and s.task.request.query = "beta", "Search requests only final text after the Timer fires")
    old = s.task
    s.kb.text = "gamma"
    old.response = { channels: [], games: [], videos: [] }
    s = inspect(page)
    check(s.task = invalid and old.control = "stop" and instr(0, s.status.text, "gamma") > 0, "superseded Search response cannot replace current text status")
    s = waitForSearch(page)
    s.task.response = { channels: [], games: [], videos: [] }
    s = inspect(page)
    check(instr(0, s.status.text, "No results") > 0 and not s.rowlist.visible, "Search valid-empty shows no-results guidance")
    s.kb.text = "delta"
    s = waitForSearch(page)
    s.task.response = invalid
    s = inspect(page)
    check(instr(0, s.status.text, "isn't working") > 0 and not s.rowlist.visible, "Search invalid response shows connection failure")
    s.kb.text = ""
    s = inspect(page)
    check(not s.status.visible and s.timer.control = "stop" and s.task = invalid, "cleared Search cancels Timer/task and hides status")
    s.kb.setFocus(true)
    check(page.callFunc("fixtureKey", "back", true) and page.backPressed, "Search keyboard Back emits navigation")
    s.kb.text = "cleanup"
    s = waitForSearch(page)
    old = s.task
    page.callFunc("fixtureCleanup")
    s = inspect(page)
    check(s.disposed and s.task = invalid and old.control = "stop" and s.timer.control = "stop", "Search cleanup stops request and debounce")
    s.kb.text = "should-not-request"
    old.response = { channels: [], games: [], videos: [] }
    pause(600)
    check(inspect(page).task = invalid, "disposed Search text/response observers cannot launch another request")
    disposePage(scene, page)
end sub

sub testMenu(scene as object, fixtureGlobal as object)
    menu = addMenu(scene)
    s = inspect(menu)
    menu.activeItem = "Browse"
    colorProbe = createObject("roSGNode", "Label")
    colorProbe.color = fixtureGlobal.constants.ui.color.text
    check(s.tabs.getChild(1).textColor = colorProbe.color, "active MenuBar tab uses actual primary color token")
    colorProbe.color = fixtureGlobal.constants.ui.color.textSecondary
    check(s.tabs.getChild(0).textColor = colorProbe.color, "inactive MenuBar tab uses actual secondary color token")
    menu.focusItem = "Browse"
    check(s.tabs.focusButton = 1 and menu.buttonSelected = -1, "MenuBar focusItem moves focus marker without selection")
    s.tabs.buttonSelected = 2
    check(menu.buttonSelected = 2, "actual tab selection bridges the flat index")
    s.icons.buttonSelected = 1
    check(menu.buttonSelected = 5, "actual icon selection bridges after text tabs")
    s.icons.setFocus(true)
    s.icons.buttonFocused = 0
    check(s.caption.visible and s.label.text = "Search", "focused Search icon shows its caption")
    s.icons.buttonFocused = 1
    check(s.label.text = "Settings", "focused Settings icon updates its caption")
    s.icons.buttonFocused = 2
    check(s.label.text = "Sign in", "anonymous account icon says Sign in")
    fixtureGlobal.fixtureSigned = true
    s.icons.buttonFocused = 1
    s.icons.buttonFocused = 2
    check(s.label.text = "Account · Fixture Viewer", "signed-in account caption names the Account panel and supplied display name")
    s.tabs.setFocus(true)
    check(not s.caption.visible, "leaving icon focus hides the menu caption")
    oldColor = s.tabs.getChild(0).textColor
    menu.callFunc("fixtureCleanup")
    menu.activeItem = "Following"
    s.icons.buttonSelected = 0
    check(inspect(menu).disposed and s.tabs.getChild(0).textColor = oldColor and menu.buttonSelected = 5, "MenuBar disposal removes color and child selection observers")
    disposePage(scene, menu)
    fixtureGlobal.fixtureSigned = false
end sub

sub testRail(scene as object, fixtureGlobal as object)
    history = []
    for i = 0 to 9
        history.push({ login: "rail-" + i.toStr(), displayName: "Rail " + i.toStr(), iconUrl: "pkg:/images/default_banner.png" })
    end for
    fixtureGlobal.fixtureHistory = history
    rail = addPage(scene, "RecentlyWatchedBar")
    s = inspect(rail)
    check(rail.hasItems and s.items.count() = 10 and not s.caption.visible, "actual rail builds supplied history without invisible initial focus")
    rail.itemHasFocus = true
    check(s.caption.visible and s.label.text = "Rail 0" and s.items[0].focused, "entering actual rail reveals focused channel name")
    s.task.response = { "rail-0": true }
    check(s.items[0].isLive and s.label.text = "Rail 0 · LIVE", "rail status response adds LIVE to focused caption")
    oldItems = s.items
    rail.callFunc("fixtureRefresh")
    check(oldItems[0].isSameNode(inspect(rail).items[0]), "rail refresh preserves focused item identity")
    check(rail.callFunc("fixtureKey", "down", true), "rail Down consumes navigation")
    s = inspect(rail)
    check(s.index = 1 and s.label.text = "Rail 1" and s.items[1].focused and not s.items[0].focused, "rail Down updates focus and caption together")
    for i = 0 to 7
        rail.callFunc("fixtureKey", "down", true)
    end for
    s = inspect(rail)
    check(s.index = 9 and s.items[9].visible and not s.items[0].visible and s.label.text = "Rail 9", "scrolling rail keeps its focused final item visible")
    check(rail.callFunc("fixtureKey", "down", true) and inspect(rail).index = 9, "rail Down remains bounded at final item")
    for i = 0 to 8
        rail.callFunc("fixtureKey", "up", true)
    end for
    check(not rail.callFunc("fixtureKey", "up", true) and inspect(rail).index = 0, "top rail Up bubbles for host navigation")
    s = inspect(rail)
    s.task.response = invalid
    check(not s.items[0].isLive and s.label.text = "Rail 0", "failed live status clears stale LIVE caption")
    check(rail.callFunc("fixtureKey", "OK", true) and rail.contentSelected.streamerLogin = "rail-0", "rail OK emits the actual selected channel")
    check(not rail.itemHasFocus and not s.caption.visible and not s.items[0].focused, "rail selection releases caption and focus marker")
    old = s.task
    timer = s.timer
    rail.callFunc("fixtureCleanup")
    rail.callFunc("fixtureCleanup")
    s = inspect(rail)
    old.response = { "rail-0": true }
    check(s.disposed and s.task = invalid and old.control = "stop" and timer.control = "stop" and s.items.count() = 0, "rail disposal stops Timer/task and releases all items")
    disposePage(scene, rail)
    fixtureGlobal.fixtureHistory = []
    rail = addPage(scene, "RecentlyWatchedBar")
    rail.itemHasFocus = true
    s = inspect(rail)
    check(not rail.hasItems and not s.caption.visible and s.task = invalid, "empty rail has no invisible caption or request")
    check(not rail.callFunc("fixtureKey", "up", true), "empty rail Up bubbles without a hidden item")
    disposePage(scene, rail)
end sub

function addPage(scene as object, name as string) as object
    node = createObject("roSGNode", name)
    scene.appendChild(node)
    return node
end function

function addMenu(scene as object) as object
    menu = addPage(scene, "MenuBar")
    menu.menuOptionsText = ["Following", "Browse", "Live Channels", "Categories"]
    return menu
end function

function inspect(node as object) as object
    return node.callFunc("fixtureRead")
end function

sub selectAction(state as object, index as integer)
    state.status.findNode("buttons").buttonSelected = index
end sub

sub disposePage(scene as object, node as object)
    disposeNodeTree(node)
    scene.removeChild(node)
end sub

function cardFields(kind as string, login as string) as object
    return { contentType: kind, contentTitle: login, streamerLogin: login, streamerDisplayName: login, viewersCount: 4, followerCount: 2, previewImageURL: "pkg:/images/default_banner.png" }
end function

' Port events must not shorten a requested delay; the actual Timer drives Search.
sub pause(duration as integer)
    elapsed = createObject("roTimespan")
    elapsed.mark()
    while elapsed.totalMilliseconds() < duration
        wait(25, m.fixturePort)
    end while
end sub

function waitForSearch(page as object) as object
    elapsed = createObject("roTimespan")
    elapsed.mark()
    while inspect(page).task = invalid and elapsed.totalMilliseconds() < 1500
        wait(25, m.fixturePort)
    end while
    return inspect(page)
end function

sub check(condition as boolean, message as string)
    if condition
        m.assertions += 1
    else
        m.failures += 1
        print "STITCH_UI_FAIL:"; message
    end if
end sub
