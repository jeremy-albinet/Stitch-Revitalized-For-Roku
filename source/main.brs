sub Main(input as dynamic)
    ' Initialize roSGScreen and roMessagePort
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    ' Set global constants
    m.global = screen.getGlobalNode()
    setConstants() ' Assuming this sets necessary global constants

    ' Capture prior exit/crash reason before the scene starts so heroScene can
    ' include it in the app_opened analytics event.
    ' Only store abnormal/crash exits — normal user exits (back, screensaver,
    ' power-off) are not actionable and would pollute the prior_exit_reason prop.
    priorExitReason = ""
    if input <> invalid and input.lastExitOrTerminationReason <> invalid
        reason = input.lastExitOrTerminationReason.toStr()
        crashReasons = [
            "EXIT_BRIGHTSCRIPT_CRASH",
            "EXIT_OUT_OF_MEMORY",
            "EXIT_BRIGHTSCRIPT_TIMEOUT",
            "EXIT_BRIGHTSCRIPT_ERROR"
        ]
        for each crashReason in crashReasons
            if reason = crashReason
                priorExitReason = reason
                exit for
            end if
        end for
    end if
    m.global.addFields({ priorExitReason: priorExitReason })

    ' Set the message port for screen
    screen.setMessagePort(m.port)

    ' Ensure the scene is properly created
    m.scene = screen.CreateScene("HeroScene")

    ' The main function that runs when the application is launched
    screen.show()

    ' Signal beacons after the scene is fully initialized
    m.scene.signalBeacon("AppDialogInitiate")
    m.scene.signalBeacon("AppDialogComplete")
    m.scene.signalBeacon("AppLaunchComplete")

    m.scene.observeField("exitApp", m.port)
    m.scene.setFocus(true)

    screenClosed = false
    while true
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent"
            if msg.isScreenClosed()
                screenClosed = true
                exit while
            end if
        else if msgType = "roSGNodeEvent"
            field = msg.getField()
            if field = "exitApp"
                exit while
            end if
        end if
    end while
    finishMainScene(screen, m.scene, m.port, screenClosed)
    m.scene = invalid
end sub

sub finishMainScene(screen as object, scene as object, port as object, screenClosed as boolean)
    if screenClosed then return
    session = scene.GetField("localPlaybackSession")
    metadataOwner = scene.findNode("stitchAdMetadataOwner")
    scene.unobserveField("exitApp")
    ' callFunc synchronizes with render; keep it alive for cooperative cleanup.
    scene.callFunc("onDestroy")
    clock = CreateObject("roTimeSpan")
    clock.Mark()
    while session <> invalid or metadataOwner <> invalid
        sessionBusy = false
        metadataBusy = false
        if session <> invalid then sessionBusy = session.busy
        if metadataOwner <> invalid then metadataBusy = metadataOwner.busy
        if not sessionBusy and not metadataBusy then exit while
        remaining = 15000 - clock.TotalMilliseconds()
        if remaining <= 0 then exit while
        timeout = 100
        if remaining < timeout then timeout = remaining
        msg = wait(timeout, port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        end if
    end while
    screen.close()
end sub
