' Fixed HD layout; invalid dimensions fall back before calculating safe bounds.
function chatLayoutGeometry(mode as dynamic, position as dynamic, chatVisible as boolean, width = 1280 as dynamic, height = 720 as dynamic) as object
    if not isChatLayoutDimension(width, 640) then width = 1280
    if not isChatLayoutDimension(height) then height = 720
    overlay = false
    if GetInterface(mode, "ifString") <> invalid then overlay = mode = "overlay"
    corner = "bottom-right"
    if GetInterface(position, "ifString") <> invalid
        if position = "top-left" or position = "top-right" or position = "bottom-left" then corner = position
    end if

    chatWidth = 320
    chatHeight = height
    x = width - chatWidth
    y = 0
    videoWidth = width
    if overlay
        insetX = 48
        insetY = 36
        chatWidth = 360
        chatHeight = 480
        if chatWidth > width - insetX * 2 then chatWidth = width - insetX * 2
        if chatHeight > height - insetY * 2 then chatHeight = height - insetY * 2
        x = width - insetX - chatWidth
        y = height - insetY - chatHeight
        if corner = "top-left" or corner = "bottom-left" then x = insetX
        if corner = "top-left" or corner = "top-right" then y = insetY
    else if chatVisible
        videoWidth = width - chatWidth
    end if
    return { overlayMode: overlay, chatWidth: chatWidth, chatHeight: chatHeight, chatTranslation: [x, y], videoWidth: videoWidth, videoHeight: height }
end function

function isChatLayoutDimension(value as dynamic, minimum = 320 as integer) as boolean
    if GetInterface(value, "ifInt") = invalid and GetInterface(value, "ifFloat") = invalid and GetInterface(value, "ifDouble") = invalid then return false
    return value >= minimum and value <= 7680
end function

function chatOverlayOpacity(value as dynamic) as float
    if GetInterface(value, "ifString") <> invalid
        if value = "0.25" then return 0.25
        if value = "0.75" then return 0.75
        if value = "1" then return 1.0
    end if
    return 0.5
end function

sub applyChatLayout()
    if m.chatWindow = invalid or m.video = invalid then return
    layout = chatLayoutGeometry(get_user_setting("chat.layout", "side"), get_user_setting("chat.overlayPosition", "bottom-right"), m.chatWindow.visible)
    m.chatWindow.overlayMode = layout.overlayMode
    opacity = 1.0
    if layout.overlayMode then opacity = chatOverlayOpacity(get_user_setting("chat.overlayOpacity", "0.5"))
    m.chatWindow.backgroundOpacity = opacity
    m.chatWindow.width = layout.chatWidth
    m.chatWindow.height = layout.chatHeight
    m.chatWindow.translation = layout.chatTranslation
    m.video.width = layout.videoWidth
    m.video.height = layout.videoHeight
    m.video.translation = [0, 0]
    if m.video.hasField("chatOverlayMode") then m.video.chatOverlayMode = layout.overlayMode
    m.video.chatIsVisible = m.chatWindow.visible
end sub
