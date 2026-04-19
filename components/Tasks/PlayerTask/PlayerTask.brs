'*********************************************************************
'** (c) 2016-2017 Roku, Inc.  All content herein is protected by U.S.
'** copyright and other applicable intellectual property laws and may
'** not be copied without the express permission of Roku, Inc., which
'** reserves all rights.  Reuse of any of this content for any purpose
'** without the permission of Roku, Inc. is strictly prohibited.
'*********************************************************************

sub init()
    m.top.functionName = "playContentWithAds"
    m.top.id = "PlayerTask"
end sub

sub playContentWithAds()
    video = m.top.video

    port = CreateObject("roMessagePort")
    video.observeField("position", port)
    video.observeField("state", port)

    video.visible = true
    video.control = "play"
    video.setFocus(true)

    curPos = 0
    adPods = invalid
    isPlayingPostroll = false
    while true
        msg = wait(0, port)
        if type(msg) = "roSGNodeEvent"
            field = msg.GetField()

            if field = "position"
                curPos = msg.GetData()
                if adPods <> invalid and adPods.count() > 0
                    video.control = "stop"
                end if

            else if field = "state"
                curState = msg.GetData()

                if curState = "error"
                    ? "[PlayerTask] error code="; video.errorCode; " msg="; video.errorStr

                else if curState = "stopped"
                    if adPods = invalid or adPods.count() = 0
                        exit while
                    end if
                    adPods = invalid
                    if isPlayingPostroll
                        exit while
                    end if
                    video.visible = true
                    video.seek = curPos
                    video.control = "play"
                    video.setFocus(true)

                else if curState = "finished"
                    if adPods = invalid or adPods.count() = 0
                        exit while
                    end if
                    isPlayingPostroll = true
                    video.control = "stop"
                end if
            end if
        end if
    end while

    video.unobserveField("position")
    video.unobserveField("state")
end sub
