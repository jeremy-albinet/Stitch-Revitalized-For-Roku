' Copyright Kasper Gammeltoft and other contributors. Licensed under MIT
' https://github.com/KasperGam/EmojiOnRoku/blob/main/LICENSE
sub init()
    m.disposed = false
    ' The emoji pattern is compiled once per label, on first non-empty text.
    m.emojiRegex = invalid
    m.emojiRegexFailed = false
    m.components = m.top.findNode("layout")
    m.top.observeField("text", "setText")
    m.animation = m.top.findNode("testAnimation")
    ' m.animation.duration = 0
    m.vector = m.top.findNode("testVector2D")
    ' kvArray = [
    '     [0, 0],
    '     [(0 - (m.components.boundingRect().width * 0.25)), m.components.translation[1]],
    '     [(0 - (m.components.boundingRect().width * 0.5)), m.components.translation[1]],
    '     [(0 - (m.components.boundingRect().width * 0.75)), m.components.translation[1]],
    '     [(0 - (m.components.boundingRect().width)), m.components.translation[1]]
    ' ]
    ' m.vector.keyValue = kvArray
    m.top.observeField("color", "updateComponents")
    m.top.observeField("font", "updateComponents")
    m.top.observeField("horizAlign", "updateComponents")
    m.top.observeField("vertAlign", "updateComponents")
    m.top.observeField("width", "updateComponents")
    m.top.observeField("repeatCount", "doScroll")
    m.top.observeField("emojiSize", "updateComponents")
    m.top.observeField("maxWidth", "updateComponents")
    m.timer = m.top.findNode("timer")
    if m.timer <> invalid
        m.timer.observeField("fire", "onTimerFireChange")
    end if
    m.scrollStartTimer = m.top.findNode("scrollStartTimer")
    if m.scrollStartTimer <> invalid then m.scrollStartTimer.observeField("fire", "onScrollStart")
    setText()
end sub

sub onTimerFireChange() as void
    if m.disposed then return
    if m.animation = invalid or m.timer = invalid then return
    m.animation.repeat = false
    m.animation.control = "stop"
    m.components.translation = [0, 0]
    m.timer.control = "stop"
    if m.top.repeatCount < 0 then doScroll()
end sub

sub doScroll()
    if m.disposed then return
    cancelScroll()
    if m.top.repeatCount <> invalid and m.top.repeatCount <> 0 and m.top.text <> "" and m.top.width > m.top.maxWidth
        if m.scrollStartTimer <> invalid
            m.scrollStartPending = true
            m.scrollStartTimer.control = "start"
        end if
    end if
end sub

sub onScrollStart()
    if m.scrollStartPending <> true then return
    m.scrollStartPending = false
    if m.disposed or m.top.repeatCount = 0 or m.top.text = "" then return
    if m.animation = invalid or m.timer = invalid or m.vector = invalid or m.top.maxWidth <= 0 then return
    distance = m.top.width - m.top.maxWidth
    if distance <= 0 then return
    m.animation.repeat = false
    m.timer.repeat = false
    m.vector.keyValue = [[0, 0], [0 - distance, 0]]
    m.animation.duration = distance / 40
    if m.animation.duration < 1 then m.animation.duration = 1
    m.timer.duration = m.animation.duration + 1
    m.animation.control = "start"
    m.timer.control = "start"
end sub

sub cancelScroll()
    m.scrollStartPending = false
    if m.scrollStartTimer <> invalid then m.scrollStartTimer.control = "stop"
    if m.timer <> invalid then m.timer.control = "stop"
    if m.animation <> invalid
        m.animation.repeat = false
        m.animation.control = "stop"
    end if
    if m.components <> invalid then m.components.translation = [0, 0]
end sub

' Will update the components if an interface field has changed.
sub updateComponents()
    ' Only update components if we are actually rendering text
    if m.top.text <> ""
        width = m.top.width
        height = m.top.height
        hAlign = m.top.horizAlign
        vAlign = m.top.vertAlign
        ' Set the layout group properties to reflect the horiz and vert
        ' aligments
        m.components.horizAlignment = hAlign
        m.components.vertAlignment = vAlign

        ' Set component properties
        comps = getAllComponents()
        totalWidth = 0
        for each comp in comps
            comp.visible = true
            if comp.subtype() = "Label"
                comp.width = 0
                comp.height = height
                comp.vertAlign = vAlign
                comp.color = m.top.color
                if m.top.font <> invalid
                    comp.font = m.top.font
                end if
            else
                ' For posters, use emojiSize first if set
                if m.top.emojiSize > 0
                    comp.width = m.top.emojiSize
                    comp.height = m.top.emojiSize
                    ' Then use height if set
                else if height > 0
                    comp.width = height
                    comp.height = height
                else
                    comp.width = 0
                    comp.height = 0
                end if
            end if
            totalWidth = totalWidth + comp.width
        end for
        width = totalWidth

        ' Check if we need to use ellipsis for this label
        ' checkBoundingWidth()
        boundingWidth = totalWidth
        try
            boundingWidth = m.components.boundingRect().width
        catch e
        end try
        if width = 0 or boundingWidth > width
            width = boundingWidth
        end if
        m.top.width = width * 1.1
        if m.top.maxWidth = 0
            m.top.maxWidth = m.top.width
        end if
        if m.top.emojiSize > height
            height = m.top.emojiSize
        end if
        ' Set proper translation for horizontal alignment
        xTranslation = 0
        yTranslation = 0
        ' For center, that is in the middle of the node
        if hAlign = "center"
            xTranslation = width / 2
            ' For right, that is the right edge of the node
        else if hAlign = "right"
            xTranslation = width
        end if

        ' Set proper translation for vertical alignment
        ' For center, use the middle of the node
        if vAlign = "center"
            yTranslation = height / 2
            ' For bottom, use bottom edge of node
        else if vAlign = "bottom"
            yTranslation = height
        end if
        m.top.clippingRect = {
            width: m.top.maxWidth,
            height: (m.top.height * 2),
            x: 0,
            y: (0 - (m.top.height / 2))
        }
        ' m.top.translation = [m.top.translation[0], m.top.translation[1] + (height / 2)]
        ' m.components.translation = [xTranslation, height]
        if m.scrollStartPending = true or (m.animation <> invalid and m.animation.control = "start")
            doScroll()
        end if
    end if
end sub

' Convenience function to check if we need to truncate the label
sub checkBoundingWidth()
    curWidth = 0
    width = m.top.width
    ' Reset previous ellipsis if present
    existingEllipsis = m.components.findNode("ellipsis")
    if existingEllipsis <> invalid
        m.components.removeChild(existingEllipsis)
    end if

    comps = getAllComponents()

    for index = 0 to comps.count() - 1
        comp = comps[index]
        ' If we are already over the width, then don't display any other components
        if curWidth >= width and width > 0
            comp.visible = false
        else
            ' See if this component extends beyond the available width
            compWidth = comp.boundingRect().width
            curWidth += compWidth

            if curWidth > width and width > 0
                diff = curWidth - width

                ' For labels, we might be able to have the label use proper ellipsis by itself
                if comp.subType() = "Label"
                    newCompWidth = compWidth - diff
                    ellipsis = createLabel("…")
                    minWidth = ellipsis.boundingRect().width
                    ' If the label is too short to have an ellipsis itself, insert one here
                    if newCompWidth <= minWidth
                        comp.visible = false
                        ellipsis.id = "ellipsis"
                        m.components.insertChild(ellipsis, index)
                    else
                        ' Label will use ellipsis with explicit width set
                        comp.width = newCompWidth
                    end if
                else
                    ' Replace with ellipsis
                    comp.visible = false
                    ellipsis = createLabel("…")
                    ellipsis.id = "ellipsis"
                    m.components.insertChild(ellipsis, index)
                end if
            end if
        end if
    end for
end sub

' function normalizeText(text as string)
'     unicodeRegex = createObject("roRegex", unidecodeRegex(), "m")
'     matches = unicodeRegex.matchAll(text)
'     for each match in matches
'         matchText = match[0]
'         text = text.replace(matchText, textPointName(matchText))
'     end for
'     return text
' end function

' Updates the entire label components with new text.
sub setText()
    cancelScroll()
    labelText = m.top.text

    resetComponents()
    if labelText <> ""
        for each segment in emojiTextRuns(labelText)
            if segment.uri = ""
                m.components.appendChild(createLabel(segment.text))
            else
                m.components.appendChild(createPoster(segment.uri, emojiFallback(segment.text)))
            end if
        end for
    end if

    ' Update the components.
    updateComponents()
end sub

' Create a new label to display non-emoji text in the label.
function createLabel(withText as string)
    label = createObject("roSGNode", "Label")
    label.text = withText
    label.color = m.top.color
    label.vertAlign = m.top.vertAlign
    label.height = m.top.height
    if m.top.font <> invalid
        label.font = m.top.font
    end if

    return label
end function

' Create a new poster to show an emoji with.
function createPoster(uri as string, fallback as string)
    poster = CreateObject("roSGNode", "Poster")
    poster.addFields({ emojiFallbackText: fallback })
    poster.observeField("loadStatus", "onEmojiImageStatus")
    poster.uri = uri

    ' Use emoji size first if set
    if m.top.emojiSize > 0
        poster.width = m.top.emojiSize
        poster.height = m.top.emojiSize
        ' Then use height if set
    else if m.top.height > 0
        poster.width = m.top.height
        poster.height = m.top.height
    end if

    return poster
end function

sub onEmojiImageStatus(event as object)
    poster = event.getRoSGNode()
    status = event.getData()
    if status <> "ready" and status <> "failed" then return
    poster.unobserveField("loadStatus")
    if m.disposed or status = "ready" then return
    parent = poster.getParent()
    if parent = invalid then return
    label = createLabel(poster.emojiFallbackText)
    for index = 0 to parent.getChildCount() - 1
        if parent.getChild(index).isSameNode(poster)
            parent.replaceChild(label, index)
            exit for
        end if
    end for
    updateComponents()
end sub

' Returns all components for the current emoji label.
function getAllComponents()
    components = []
    for i = 0 to m.components.getChildCount() - 1
        components.push(m.components.getChild(i))
    end for

    return components
end function

' Removes all child components to reset the layout group.
sub resetComponents()
    while m.components.getChildCount() > 0
        child = m.components.getChild(0)
        if child.subtype() = "Poster" then child.unobserveField("loadStatus")
        m.components.removeChildIndex(0)
    end while
end sub


sub onDestroy()
    if m.disposed then return
    m.disposed = true
    cancelScroll()
    if m.scrollStartTimer <> invalid then m.scrollStartTimer.unobserveField("fire")
    if m.timer <> invalid
        m.timer.control = "stop"
        m.timer.unobserveField("fire")
    end if
    if m.animation <> invalid
        m.animation.control = "stop"
    end if
    m.top.unobserveField("text")
    m.top.unobserveField("color")
    m.top.unobserveField("font")
    m.top.unobserveField("horizAlign")
    m.top.unobserveField("vertAlign")
    m.top.unobserveField("width")
    m.top.unobserveField("repeatCount")
    m.top.unobserveField("emojiSize")
    m.top.unobserveField("maxWidth")
    resetComponents()
    m.emojiRegex = invalid
end sub

' function onSizeChange()
'     m.top.clippingRect = {
'         width: m.top.maxWidth
'         height: m.top.height
'         x: 0
'         y: -10
'     }
' end function
