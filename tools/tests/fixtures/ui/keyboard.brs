' Native field/focus boundary, without the engine's unsupported keyboard widget.
sub init()
    edit = createObject("roSGNode", "Group")
    edit.addFields({ hintText: "", voiceEnabled: false })
    m.top.textEditBox = edit
end sub
