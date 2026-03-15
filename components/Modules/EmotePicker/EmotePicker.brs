sub init()
    m.emoteGrid = m.top.findNode("emoteGrid")
    m.providerTabs = m.top.findNode("providerTabs")
    m.currentProvider = "all"
    m.top.observeField("visible", "onVisibleChanged")
    m.emoteGrid.observeField("itemSelected", "onEmoteItemSelected")
    setupProviderTabs()
end sub

sub setupProviderTabs()
    if m.providerTabs = invalid then return
    tabLabels = ["All", "Twitch", "BTTV", "FFZ", "7TV"]
    for each label in tabLabels
        btn = CreateObject("roSGNode", "Button")
        btn.text = label
        btn.minWidth = 120
        btn.height = 36
        btn.textColor = "0xEFEFF1FF"
        btn.focusedTextColor = "0xEFEFF1FF"
        btn.focusBitmapUri = "pkg:/images/FocusFootprint.9.png"
        btn.focusFootprintBitmapUri = "pkg:/images/FocusFootprint.9.png"
        btn.showFocusFootprint = false
        m.providerTabs.appendChild(btn)
    end for
    m.providerTabs.observeField("buttonSelected", "onProviderSelected")
end sub

sub onVisibleChanged()
    if not m.top.visible then return
    populateEmoteGrid(m.currentProvider)
    if m.providerTabs <> invalid
        m.providerTabs.setFocus(true)
    end if
end sub

' Determine which provider an emote belongs to by inspecting its CDN URL.
' 7TV emotes are stored under cdn.7tv.app (set by EmoteJob) and mapped to "stv".
function getProviderFromUri(uri as string) as string
    if uri.Instr("jtvnw.net") > -1
        return "twitch"
    else if uri.Instr("7tv.app") > -1
        ' SevenTV CDN — matches URLs written by EmoteJob (cdn.7tv.app/emote/…)
        return "stv"
    else if uri.Instr("frankerfacez.com") > -1
        return "ffz"
    else if uri.Instr("betterttv.net") > -1
        return "bttv"
    end if
    return "other"
end function

' Build the MarkupGrid ContentNode from the global emote cache, optionally
' filtered to a single provider.
sub populateEmoteGrid(provider as string)
    emoteCache = m.global.emoteCache
    if emoteCache = invalid then return
    contentNode = CreateObject("roSGNode", "ContentNode")
    for each emoteName in emoteCache
        emoteUri = emoteCache[emoteName]
        emoteProvider = getProviderFromUri(emoteUri)
        if provider = "all" or emoteProvider = provider
            item = CreateObject("roSGNode", "ContentNode")
            item.addFields({ emoteCode: emoteName, emoteUri: emoteUri })
            contentNode.appendChild(item)
        end if
    end for
    m.emoteGrid.content = contentNode
end sub

' Called when the user presses down on a provider tab (via ButtonGroupHoriz
' buttonSelected event), which switches the active filter and moves focus
' to the emote grid.
' Tab order matches providerMap: All(0) Twitch(1) BTTV(2) FFZ(3) 7TV→stv(4)
sub onProviderSelected()
    if m.providerTabs = invalid then return
    selectedIndex = m.providerTabs.buttonFocused
    providerMap = ["all", "twitch", "bttv", "ffz", "stv"]
    if selectedIndex >= 0 and selectedIndex < providerMap.count()
        m.currentProvider = providerMap[selectedIndex]
    end if
    populateEmoteGrid(m.currentProvider)
    if m.emoteGrid <> invalid
        if m.emoteGrid.content <> invalid and m.emoteGrid.content.getChildCount() > 0
            m.emoteGrid.setFocus(true)
        end if
    end if
end sub

' Called when the user presses OK on an emote in the grid.
sub onEmoteItemSelected()
    selectedIndex = m.emoteGrid.itemSelected
    content = m.emoteGrid.content
    if content = invalid then return
    item = content.getChild(selectedIndex)
    if item <> invalid and item.emoteCode <> invalid
        m.top.emoteSelected = item.emoteCode
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    ' Let VideoPlayer handle the back key to dismiss this overlay.
    if key = "back" then return false
    ' When the grid has focus and user presses up from the first row, return
    ' focus to the provider tabs so they can switch filters.
    if key = "up"
        if m.providerTabs <> invalid
            m.providerTabs.setFocus(true)
            return true
        end if
    end if
    return false
end function
