' Permanent disposal only; retained back-stack nodes must remain reusable.
' Component callbacks release m-only resources. Walk concrete children, never
' arbitrary node fields, which may reference a different retained screen.
' The explicit marker also works on runtimes without the newer hasFunc method.
sub disposeNodeTree(node as dynamic)
    if node = invalid then return
    if node.hasField("supportsDisposal")
        if node.supportsDisposal then node.callFunc("onDestroy")
    end if
    if node.isSubtype("Timer") or node.isSubtype("Animation")
        node.control = "stop"
    end if
    children = node.getChildren(node.getChildCount(), 0)
    for each child in children
        disposeNodeTree(child)
    end for
end sub
