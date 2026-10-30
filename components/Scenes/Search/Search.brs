sub init()
    m.disposed = false
    m.top.observeField("focusedChild", "onGetfocus")
    m.recents = m.top.findnode("recents")
    ' m.recents.buttons = ["Ammo", "paymoneywubby", "three"]
    if m.recents <> invalid
        m.recents.TextColor = m.global.constants.ui.color.text
        m.recents.FocusedTextColor = m.global.constants.ui.color.onAccent
        m.recents.observeField("buttonSelected", "onRecentItemSelected")
    end if
    m.recentsHeading = m.top.findNode("recentsHeading")
    if m.recentsHeading <> invalid then m.recentsHeading.text = tr("Recent searches")
    m.searchStatus = m.top.findNode("searchStatus")
    m.kb = m.top.findNode("keyboard")
    applyKeyboardPalette(m.kb)
    m.kb.textEditBox.hintText = tr("Enter Search Query")
    m.kb.textEditBox.voiceEnabled = true
    m.kb.observefield("text", "handleTextInput")
    m.rowlist = m.top.findNode("homeRowList")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    ' One request starts after typing pauses; each edit supersedes the last.
    m.activeQuery = ""
    m.searchTimer = m.top.findNode("searchDebounce")
    if m.searchTimer <> invalid then m.searchTimer.observeField("fire", "onSearchDebounce")
    updateRecents()
end sub

' Twitch colours on the on-screen keyboard: dark keys, purple focus.
sub applyKeyboardPalette(keyboard as dynamic)
    if keyboard = invalid or not keyboard.hasField("palette") then return
    color = m.global?.constants?.ui?.color
    if color = invalid then return
    palette = CreateObject("roSGNode", "RSGPalette")
    if palette = invalid then return
    palette.colors = {
        PrimaryTextColor: color.text,
        SecondaryTextColor: color.textSecondary,
        InputFieldColor: color.raised,
        KeyboardColor: color.surface,
        FocusColor: color.focusFill,
        FocusItemColor: color.onAccent
    }
    keyboard.palette = palette
end sub

sub updateRecents(appendItem = invalid)
    oldRecents = ParseJson(get_user_setting("recents", "[]"))
    if oldRecents = invalid
        oldRecents = []
    end if
    newRecents = []
    if appendItem <> invalid
        newRecents.Push(appendItem)
    end if
    for each item in oldRecents
        i = newRecents.count()
        if i < 3
            if item <> appendItem
                newRecents.Push(item)
            end if
        end if
    end for
    set_user_setting("recents", FormatJson(newRecents, 256))
    m.recents.buttons = ParseJson(get_user_setting("recents", "[]"))
    adjustPositionForRecents()
end sub

sub onRecentItemSelected()
    selectedText = m.recents.buttons[m.recents.buttonSelected].tostr()
    ? "SelectedText: "; selectedText
    m.kb.setfocus(true)
    m.kb.text = selectedText
end sub

sub adjustPositionForRecents()
    ' Heading and recent searches sit above the keyboard when history exists.
    recentCount = m.recents.buttons.count()
    if m.recentsHeading <> invalid then m.recentsHeading.visible = recentCount > 0
    yTranslation = 120
    if recentCount > 0
        m.recents.buttonHeight = 40
        yTranslation = m.recents.translation[1] + (recentCount * 40) + 16
    end if
    m.kb.translation = [m.kb.translation[0], yTranslation]
end sub

function currentSearchQuery() as string
    if m.kb = invalid or m.kb.text = invalid then return ""
    return m.kb.text.toStr().trim()
end function

sub showSearchStatus(text as string)
    if m.searchStatus = invalid then return
    m.searchStatus.text = text
    m.searchStatus.visible = text <> ""
end sub

sub handleTextInput()
    if m.disposed then return
    ' Any edit makes an in-flight response stale immediately.
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.activeQuery = ""
    if m.searchTimer <> invalid then m.searchTimer.control = "stop"
    query = currentSearchQuery()
    m.rowlist.visible = false
    m.rowlist.content = invalid
    if query = ""
        showSearchStatus("")
        return
    end if
    showSearchStatus(Substitute(tr("Searching for ""{0}""…"), query))
    if m.searchTimer <> invalid
        m.searchTimer.control = "start"
    else
        onSearchDebounce()
    end if
end sub

sub onSearchDebounce()
    if m.disposed then return
    query = currentSearchQuery()
    if query = "" then return
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.activeQuery = query
    m.GetContentTask = createApiTask("getSearchQuery", "handleRecommendedSections", { query: query })
end sub

sub handleRecommendedSections()
    if m.disposed or m.GetContentTask = invalid then return
    rsp = m.GetContentTask.response
    query = m.activeQuery
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.activeQuery = ""
    ' Ignore a response for text the user has since changed.
    if query = "" or query <> currentSearchQuery() then return
    if rsp = invalid
        showSearchStatus(tr("Search isn't working right now. Check your connection, then edit your search to try again."))
        return
    end if
    if buildContentNodeFromShelves(rsp) = 0
        showSearchStatus(Substitute(tr("No results for ""{0}"". Check the spelling or try a channel or category name."), query))
    else
        showSearchStatus("")
    end if
end sub

function buildContentNodeFromShelves(shelves) as integer
    LiveChannels = []
    Users = []
    Games = []
    Vods = []
    for each item in shelves.channels
        rowItem = {}
        if item.stream <> invalid
            rowItem.contentType = "LIVE"
        else
            rowItem.contentType = "USER"
        end if
        if rowItem.contentType = "LIVE"
            if item.stream.broadcaster = invalid then continue for
            rowItem.contentId = item.stream.Id
            rowItem.createdAt = item.stream.createdAt
            rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", item.stream.broadcaster.login, "1280", "720")
            rowItem.contentTitle = item.stream.broadcaster.broadcastSettings?.title
            rowItem.viewersCount = item.stream.viewersCount
            rowItem.streamerDisplayName = item.stream.broadcaster.displayName
            rowItem.streamerLogin = item.stream.broadcaster.login
            rowItem.streamerId = item.stream.broadcaster.id
            rowItem.streamerProfileImageUrl = item.stream.broadcaster.profileImageURL
            if item.stream.game <> invalid
                rowItem.gameDisplayName = item.stream.game.displayName
                rowItem.gameBoxArtUrl = Left(item.stream.game.boxArtUrl, Len(item.stream.game.boxArtUrl) - 20) + "188x250.jpg"
                rowItem.gameId = item.stream.game.Id
                rowItem.gameName = item.stream.game.name
            end if
            LiveChannels.push(rowItem)
        end if
        if rowItem.contentType = "USER"
            rowItem.contentId = item.Id
            rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", item.login, "1280", "720")
            rowItem.contentTitle = item.displayName
            rowItem.followerCount = item.followers.totalCount
            rowItem.streamerDisplayName = item.displayName
            rowItem.streamerLogin = item.login
            rowItem.streamerId = item.id
            rowItem.streamerProfileImageUrl = item.profileImageURL
            Users.push(rowItem)
        end if
    end for
    for each game in shelves.games
        rowItem = {}
        rowItem.contentId = game.Id
        rowItem.contentType = "GAME"
        rowItem.viewersCount = game.viewersCount
        rowItem.contentTitle = game.displayName
        rowItem.gameDisplayName = game.displayName
        rowItem.gameBoxArtUrl = Left(game.boxArtUrl, Len(game.boxArtUrl) - 20) + "188x250.jpg"
        rowItem.gameId = game.Id
        rowItem.gameName = game.name
        Games.push(rowItem)
    end for
    for each VOD in shelves.videos
        rowItem = {}
        rowItem.contentType = "VOD"
        rowItem.contentId = VOD.Id
        if VOD.previewThumbnailURL <> invalid
            rowItem.previewImageURL = Left(VOD.previewThumbnailURL, len(VOD.previewThumbnailURL) - 20) + "320x180." + Right(VOD.previewThumbnailURL, 3)
        else if VOD.thumbnailURL <> invalid
            rowItem.previewImageURL = VOD.thumbnailURL
        end if
        rowItem.contentTitle = VOD.title
        rowItem.viewersCount = VOD.viewCount
        rowItem.streamerDisplayName = VOD.owner.displayName
        rowItem.streamerLogin = VOD.owner.login
        rowItem.streamerId = VOD.owner.id
        if VOD.game <> invalid
            rowItem.gameDisplayName = VOD.game.displayName
            rowItem.gameBoxArtUrl = Left(VOD.game.boxArtUrl, Len(VOD.game.boxArtUrl) - 20) + "188x250.jpg"
            rowItem.gameId = VOD.game.Id
            rowItem.gameName = VOD.game.name
        end if
        Vods.push(rowItem)
    end for
    AllContent = createObject("roSGNode", "ContentNode")
    firstRow = createObject("roSGNode", "ContentNode")
    firstRow.title = tr("Live Channels")
    for each stream in LiveChannels
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, stream)
        firstRow.appendChild(rowItem)
    end for
    secondRow = createObject("roSGNode", "ContentNode")
    secondRow.title = tr("Channels")
    for each User in Users
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, User)
        secondRow.appendChild(rowItem)
    end for
    thirdRow = createObject("roSGNode", "ContentNode")
    thirdRow.title = tr("Categories")
    for each Game in Games
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, Game)
        thirdRow.appendChild(rowItem)
    end for
    fourthRow = createObject("roSGNode", "ContentNode")
    fourthRow.title = tr("VODs")
    for each Vod in Vods
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, Vod)
        fourthRow.appendChild(rowItem)
    end for
    ' set content and heights
    rowItemSize = []
    rowHeights = []
    if firstRow.getChildCount() > 0
        config = getRowConfig("LIVE", true, true)
        rowItemSize.push(config.itemSize)
        rowHeights.push(config.rowHeight)
        AllContent.appendChild(firstRow)
    end if
    if secondRow.getchildCount() > 0
        config = getRowConfig("USER", true)
        rowItemSize.push(config.itemSize)
        rowHeights.push(config.rowHeight)
        AllContent.appendChild(secondRow)
    end if
    if thirdRow.getchildCount() > 0
        config = getRowConfig("GAME", true)
        rowItemSize.push(config.itemSize)
        rowHeights.push(config.rowHeight)
        AllContent.appendChild(thirdRow)
    end if
    if fourthRow.getchildCount() > 0
        config = getRowConfig("VOD", true, true)
        rowItemSize.push(config.itemSize)
        rowHeights.push(config.rowHeight)
        AllContent.appendchild(fourthRow)
    end if
    m.rowlist.visible = false
    m.rowlist.content = AllContent
    m.rowlist.rowHeights = rowHeights
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.visible = AllContent.getChildCount() > 0
    return AllContent.getChildCount()
end function


sub handleItemSelected()
    if m.kb.text <> ""
        updateRecents(m.kb.text)
    end if
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    if selectedRow = invalid then return
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.contentSelected = selectedItem
end sub


sub onGetFocus()
    if m.rowlist.focusedchild <> invalid
        if m.rowlist.focusedChild.id = "homeRowList"
            m.rowlist.focusedChild.setFocus(true)
        end if
    else if m.top.focusedChild <> invalid
        if m.top.focusedChild.id = "Search"
            m.kb.setFocus(true)
        else if m.top.focusedChild.id = "homeRowList"
            m.rowlist.setfocus(true)
        end if
    else
        m.top.setfocus(true)
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
sub updateRowListFocusFeedback()
    if m.rowlist = invalid then return
    hasFocus = false
    if m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
        hasFocus = true
    end if
    m.rowlist.drawFocusFeedback = hasFocus
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ? "Search Key Press: "; key
        if key = "right"
            if m.top.focusedChild.id = "keyboard" or m.top.focusedChild.id = "recents"
                m.kb.setfocus(false)
                m.rowlist.setfocus(true)
                return true
            end if
        end if
        if key = "left"
            if m.top.focusedChild.id = "homeRowList"
                m.rowlist.setfocus(false)
                m.kb.setfocus(true)
                return true
            end if
        end if
        if key = "up"
            if m.top?.focusedChild?.id <> invalid and m.top.focusedChild.id = "keyboard"
                if m.recents.buttons.count() > 0
                    m.recents.setfocus(true)
                    return true
                end if
            end if
        end if
        ' Back from any Search area returns to the menu.
        if key = "up" or key = "back"
            m.rowlist.setfocus(false)
            m.kb.setfocus(false)
            m.top.backPressed = true
            return true
        end if
        if key = "down"
            if m.top?.focusedChild?.id <> invalid and m.top.focusedChild.id = "recents"
                m.kb.setfocus(true)
                return true
            end if
        end if
    end if
    return false
end function

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.top.lastFocus = invalid
    m.top.unobserveField("focusedChild")
    if m.recents <> invalid then m.recents.unobserveField("buttonSelected")
    if m.searchTimer <> invalid
        m.searchTimer.control = "stop"
        m.searchTimer.unobserveField("fire")
    end if
    m.kb.unobserveField("text")
    m.rowlist.unobserveField("itemSelected")
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
