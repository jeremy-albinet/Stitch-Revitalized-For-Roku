sub init()
    m.disposed = false
    m.adState = invalid
    m.lastView = invalid
    m.plate = m.top.findNode("plate")
    m.title = m.top.findNode("adTitle")
    m.time = m.top.findNode("adTime")
    m.top.focusable = false
    adcHide()
    adcLayout()
end sub

function beginContent(owner as dynamic) as boolean
    if m.disposed then return false
    m.adState = twitchAdCountdownBegin(owner)
    adcHide()
    return m.adState <> invalid
end function

function adcOwned(owner as dynamic) as boolean
    try
        if m.disposed or m.adState = invalid then return false
        return tadState(m.adState, owner)
    catch error
        return false
    end try
end function

' Copy only validated primitive cue fields; never retain the caller's payload.
function setCues(owner as dynamic, cues as dynamic) as boolean
    if not adcOwned(owner)
        adcHide()
        return false
    end if
    try
        accepted = []
        valid = tadCuesValid(cues)
        if valid
            for each cue in cues
                accepted.Push({ startUs: cue.startUs, endUs: cue.endUs, durationUs: cue.durationUs, podCount: cue.podCount, podPosition: cue.podPosition })
            end for
        end if
        state = m.adState
        state.cues = accepted
        m.adState = state
        adcHide()
        return valid
    catch error
        state = m.adState
        state.cues = []
        m.adState = state
        adcHide()
        return false
    end try
end function

' UTC microseconds must refer to the presented media, including paused frames.
' No wall clock, timer, native epoch assumption or ad-pod duration is inferred.
function updatePresented(owner as dynamic, presentedUtcUs as dynamic, playbackState as dynamic) as boolean
    if not adcOwned(owner)
        adcHide()
        return false
    end if
    if not tadString(playbackState)
        adcHide()
        return false
    end if
    if playbackState <> "playing" and playbackState <> "paused" and playbackState <> "buffering"
        clear(owner)
        return false
    end if
    if not tadNumber(presentedUtcUs)
        adcHide()
        return false
    end if
    m.lastView = twitchAdCountdownView(m.adState, owner, presentedUtcUs, playbackState)
    adcRender()
    return true
end function

function clear(owner as dynamic) as boolean
    if not adcOwned(owner)
        adcHide()
        return false
    end if
    m.adState = invalid
    adcHide()
    return true
end function

sub adcHide()
    m.lastView = invalid
    m.top.visible = false
    if m.title <> invalid then m.title.text = ""
    if m.time <> invalid then m.time.text = ""
end sub

function adcLayout() as boolean
    if m.plate = invalid or m.title = invalid or m.time = invalid then return false
    width = m.top.videoAreaWidth
    if width < 320 or width > 1280
        m.top.visible = false
        return false
    end if
    badgeWidth = 280
    if width - 96 < badgeWidth then badgeWidth = width - 96
    m.top.translation = [width - 48 - badgeWidth, 48]
    m.plate.width = badgeWidth
    m.title.width = badgeWidth - 140
    m.time.translation = [badgeWidth - 114, 0]
    return true
end function

function adcCopy(value as dynamic) as boolean
    if not tadString(value) then return false
    if value.Len() < 1 or value.Len() > 256 then return false
    for i = 0 to value.Len() - 1
        character = Asc(value.Mid(i, 1))
        if character < 32 or character = 127 then return false
    end for
    return true
end function

function adcTitle(view as object) as string
    if view.number > 0 and view.count > 0
        template = m.top.numberedAdLabel
        if not adcCopy(template) then template = "Ad {0} of {1}"
        if template.Split("{0}").Count() <> 2 or template.Split("{1}").Count() <> 2 then template = "Ad {0} of {1}"
        return template.Replace("{0}", view.number.ToStr()).Replace("{1}", view.count.ToStr())
    end if
    text = m.top.adLabel
    if not adcCopy(text) then text = "Ad"
    return text
end function

sub adcRender()
    if m.disposed then return
    view = m.lastView
    if view = invalid then return
    if not view.visible or not adcLayout()
        m.top.visible = false
        m.title.text = ""
        m.time.text = ""
        return
    end if
    minutes = Int(view.remainingSeconds / 60)
    seconds = view.remainingSeconds - minutes * 60
    secondText = seconds.ToStr()
    if seconds < 10 then secondText = "0" + secondText
    m.title.text = adcTitle(view)
    m.time.text = Chr(183) + " " + minutes.ToStr() + ":" + secondText
    m.top.visible = true
end sub

sub onLayoutChange()
    if m.disposed then return
    if adcLayout() then adcRender()
end sub

sub onCopyChange()
    adcRender()
end sub

sub onDestroy()
    m.disposed = true
    m.adState = invalid
    adcHide()
end sub
