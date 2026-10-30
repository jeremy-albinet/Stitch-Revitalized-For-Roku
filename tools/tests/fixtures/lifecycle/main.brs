sub main()
    port = createObject("roMessagePort")
    screen = createObject("roSGScreen")
    screen.setMessagePort(port)
    scene = screen.createScene("Owner")
    screen.show()
    if not scene.callFunc("rootBack", true) or not scene.exitApp
        fail("root Back could not exit before an initial screen loaded")
        return
    end if
    scene.exitApp = false
    scene.observeField("exitApp", port)
    if scene.callFunc("rootBack", false) or scene.exitApp
        fail("Back release requested exit")
        return
    end if
    scene.callFunc("begin")
    wait(150, port)
    retained = scene.active
    if retained.ticks < 1
        fail("initial timer did not run")
        return
    end if
    before = retained.ticks
    scene.callFunc("retain")
    outgoing = scene.active
    wait(100, port)
    if retained.cleanupCalls <> 0 or retained.ticks <= before
        fail("retained back-stack screen was disposed")
        return
    end if
    scene.callFunc("goBack")
    wait(60, port)
    if not scene.active.isSameNode(retained) or outgoing.cleanupCalls <> 1
        fail("Back did not dispose outgoing screen and restore retained screen")
        return
    end if
    before = outgoing.ticks
    retainedBefore = retained.ticks
    wait(100, port)
    if outgoing.ticks <> before or retained.ticks <= retainedBefore
        fail("detached permanent timer survived or retained timer stopped")
        return
    end if
    if outgoing.findNode("label").findNode("timer").control <> "stop"
        fail("owned EmojiLabel timer survived permanent disposal")
        return
    end if
    retained.callFunc("touch")
    if retained.touches <> 1
        fail("restored retained screen was not reusable")
        return
    end if
    scene.callFunc("disposeAgain", outgoing)
    if outgoing.cleanupCalls <> 1
        fail("cleanup was not idempotent")
        return
    end if
    scene.callFunc("retain")
    tabOutgoing = scene.active
    scene.callFunc("switchTab")
    if retained.cleanupCalls <> 1 or tabOutgoing.cleanupCalls <> 1 or scene.active.id <> "Following"
        fail("tab switch did not discard active and retained screens")
        return
    end if
    following = scene.active
    scene.callFunc("logout")
    if following.cleanupCalls <> 1 or scene.active.id <> "Settings"
        fail("logout did not dispose old account screen")
        return
    end if
    settings = scene.active
    scene.callFunc("login")
    if settings.cleanupCalls <> 1 or scene.active.id <> "Following"
        fail("login did not dispose old account screen")
        return
    end if
    finalScreen = scene.active
    sidebar = scene.sidebarResource
    inherited = createObject("roSGNode", "InheritedFollowing")
    scene.callFunc("disposeAgain", inherited)
    if inherited.cleanupCalls <> 1
        fail("inherited cleanup export did not dispatch derived implementation")
        return
    end if
    if not scene.callFunc("rootBack", true)
        fail("root Back did not consume the key while requesting exit")
        return
    end if
    exitMessage = wait(1000, port)
    if type(exitMessage) <> "roSGNodeEvent"
        fail("root Back did not notify the main thread")
        return
    end if
    if exitMessage.getField() <> "exitApp" or exitMessage.getData() <> true
        fail("root Back did not deliver a true exit request")
        return
    end if
    scene.unobserveField("exitApp")
    scene.callFunc("onDestroy")
    scene.callFunc("onDestroy")
    before = finalScreen.ticks
    sidebarBefore = sidebar.ticks
    wait(100, port)
    if finalScreen.cleanupCalls <> 1 or sidebar.cleanupCalls <> 1 or finalScreen.ticks <> before or sidebar.ticks <> sidebarBefore
        fail("root shutdown leaked a screen/sidebar timer or ran cleanup twice")
        return
    end if
    screen.close()
    print "STITCH_TEST_PASS: SceneGraph lifecycle"
end sub

sub fail(message as string)
    print "STITCH_TEST_FAIL: "; message
end sub
