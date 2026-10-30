sub init()
    m.disposed = false
    m.padding = 32
    m.spinnerSize = 40
    m.plate = m.top.findNode("plate")
    m.accent = m.top.findNode("accent")
    m.spinner = m.top.findNode("spinner")
    m.titleLabel = m.top.findNode("title")
    m.messageLabel = m.top.findNode("message")
    m.buttons = m.top.findNode("buttons")
    m.spinnerTimer = m.top.findNode("spinnerDelay")
    if m.spinner <> invalid and m.spinner.poster <> invalid
        m.spinner.poster.width = m.spinnerSize
        m.spinner.poster.height = m.spinnerSize
    end if
    if m.spinnerTimer <> invalid then m.spinnerTimer.observeField("fire", "onSpinnerDelay")
    if m.buttons <> invalid then m.buttons.observeField("buttonSelected", "onButtonSelected")
    m.top.observeField("focusedChild", "onFocusChange")
    onStateChange()
end sub

sub onStateChange()
    if m.disposed or m.titleLabel = invalid then return
    state = m.top.state
    m.top.visible = state = "loading" or state = "empty" or state = "error"
    if state = "loading"
        ' Restart the delay so each new load waits before showing the spinner.
        if m.spinnerTimer <> invalid
            m.spinnerTimer.control = "stop"
            m.spinnerTimer.control = "start"
        end if
    else
        hideSpinner()
    end if
    titleColor = "0xEFEFF1FF"
    if state = "error" then titleColor = "0xFF8280FF"
    uiColor = m.global?.constants?.ui?.color
    if uiColor <> invalid
        titleColor = uiColor.text
        if state = "error" then titleColor = uiColor.error
    end if
    m.titleLabel.color = titleColor
    onContentChange()
    ' Each new state starts on its first action, such as Try again.
    if m.top.hasActions then m.buttons.focusButton = 0
end sub

sub onContentChange()
    if m.disposed or m.titleLabel = invalid then return
    actions = m.top.actions
    if actions = invalid then actions = []
    showActions = m.top.visible and m.top.state <> "loading" and actions.count() > 0
    m.titleLabel.text = m.top.title
    m.messageLabel.text = m.top.message
    m.messageLabel.visible = m.top.state <> "loading" and m.top.message <> ""
    m.buttons.buttons = actions
    m.buttons.visible = showActions
    if showActions and m.top.hasFocus()
        m.buttons.setFocus(true)
    else if not showActions and m.buttons.isInFocusChain()
        m.top.setFocus(true)
    end if
    m.top.hasActions = showActions
    layout()
end sub

' Stack title, message and buttons; the plate grows to fit them.
sub layout()
    width = m.top.panelWidth
    pad = m.padding
    titleX = pad
    if m.top.state = "loading" then titleX = pad + m.spinnerSize + 16
    m.titleLabel.translation = [titleX, pad]
    m.titleLabel.width = width - titleX - pad
    y = pad + labelHeight(m.titleLabel, 36)
    if m.messageLabel.visible
        y += 8
        m.messageLabel.translation = [pad, y]
        m.messageLabel.width = width - (pad * 2)
        y += labelHeight(m.messageLabel, 28)
    end if
    if m.buttons.visible
        y += 24
        m.buttons.translation = [pad, y]
        count = m.buttons.buttons.count()
        y += (count * 48) + ((count - 1) * 12)
    end if
    m.plate.width = width
    m.plate.height = y + pad
    if m.accent <> invalid
        ' Inset so the rule clears the plate's rounded corners.
        m.accent.translation = [0, 8]
        m.accent.height = m.plate.height - 16
        m.accent.visible = m.top.state = "error"
    end if
end sub

function labelHeight(label as object, lineHeight as integer) as integer
    height = 0
    try
        height = label.boundingRect().height
    catch e
        height = 0
    end try
    if height <= 0 and label.text <> "" then height = lineHeight
    return height
end function

sub onSpinnerDelay()
    if m.disposed or m.top.state <> "loading" or m.spinner = invalid then return
    m.spinner.visible = true
    m.spinner.control = "start"
end sub

sub hideSpinner()
    if m.spinnerTimer <> invalid then m.spinnerTimer.control = "stop"
    if m.spinner <> invalid
        m.spinner.control = "stop"
        m.spinner.visible = false
    end if
end sub

' Hosts focus the panel itself; forward focus to the first useful button.
sub onFocusChange()
    if m.disposed then return
    if m.top.hasFocus() and m.buttons.visible then m.buttons.setFocus(true)
end sub

sub onButtonSelected()
    if m.disposed or not m.buttons.visible then return
    m.top.actionSelected = m.buttons.buttonSelected
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    if m.spinnerTimer <> invalid
        m.spinnerTimer.control = "stop"
        m.spinnerTimer.unobserveField("fire")
    end if
    if m.spinner <> invalid then m.spinner.control = "stop"
    if m.buttons <> invalid then m.buttons.unobserveField("buttonSelected")
    m.top.unobserveField("focusedChild")
end sub
