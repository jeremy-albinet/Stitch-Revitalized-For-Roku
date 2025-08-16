sub Main(input as dynamic)
    ' Add deep linking support here. Input is an associative array containing
    ' parameters that the client defines. Examples include "options, contentID, etc."
    ' See guide here: https://sdkdocs.roku.com/display/sdkdoc/External+Control+Guide
    ' For example, if a user clicks on an ad for a movie that your app provides,
    ' you will have mapped that movie to a contentID and you can parse that ID
    ' out from the input parameter here.
    ' Call the service provider API to look up
    ' the content details, or right data from feed for id
    if input <> invalid
        print "Received Input -- write code here to check it!"
        if input.instant_on_run_mode <> invalid
            print "Instant On Run Mode: "; input.instant_on_run_mode
        end if
        if input.lastExitOrTerminationReason <> invalid
            print "Last Exit or Termination Reason: "; input.lastExitOrTerminationReason
        end if
        if input.source <> invalid
            print "Source: "; input.source
        end if
        if input.splashTime <> invalid
            print "Splash Time: "; input.splashTime
        end if
        if input.reason <> invalid
            if input.reason = "ad"
                print "Channel launched from ad click"
                'do ad stuff here
            end if
        end if
        if input.contentID <> invalid
            m.contentID = input.contentID
            print "contentID is: " + input.contentID
            'launch/prep the content mapped to the contentID here
        end if
    end if

    ' Initialize roSGScreen and roMessagePort
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    ' Set global constants
    m.global = screen.getGlobalNode()
    setConstants() ' Assuming this sets necessary global constants

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

    while true
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent"
            if msg.isScreenClosed()
                return
            end if
        else if msgType = "roSGNodeEvent"
            field = msg.getField()
            if field = "exitApp"
                return
            end if
        end if
    end while
end sub
