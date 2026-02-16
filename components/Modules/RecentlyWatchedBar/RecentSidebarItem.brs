sub init()
  ' Ensure highlight sits behind the icon
  m.sel = m.top.findNode("selectionIndicator")
  m.sel.translation = [-1, -1]
end sub
