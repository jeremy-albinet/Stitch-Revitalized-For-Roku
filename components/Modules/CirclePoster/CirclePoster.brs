sub updateMask()
    m.poster = m.top.findNode("examplePoster")
    m.maskGroup = m.top.findNode("exampleMaskGroup")
    m.background = m.top.findNode("background")
    m.outline = m.top.findNode("outline")
    m.maskgroup2 = m.top.findNode("maskgroup2")
    ' Make outline slightly larger than poster
    m.outline.width = m.poster.width + 5
    m.outline.height = m.poster.height + 5

    ' add a default black circle background
    m.background.width = m.poster.width + 2
    m.background.height = m.poster.height + 2
    m.background.translation = [1, 1]
    m.maskGroup.translation = [2, 2]

    m.maskGroup.maskOffset = [0, 0]
    m.outline.visible = true

    ' maskScaleFactor requires constants — skip sizing if not yet available.
    if m.global = invalid or m.global.constants = invalid then return
    m.maskGroup2.maskSize = [(m.outline.width * m.global.constants.maskScaleFactor), (m.outline.height * m.global.constants.maskScaleFactor)]
    m.maskGroup.maskSize = [(m.poster.width * m.global.constants.maskScaleFactor), (m.poster.height * m.global.constants.maskScaleFactor)]
end sub

sub showContent()

end sub

