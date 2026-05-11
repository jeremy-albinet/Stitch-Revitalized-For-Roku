sub Init()
    'input=CreateObject("roInput")
    'm.port=createobject("roMessagePort")
    'input.setMessagePort(m.port)
    m.top.functionName = "listenInput"
end sub

sub ListenInput()
    port = createobject("romessageport")
    InputObject = createobject("roInput")
    InputObject.setmessageport(port)

    while true
        msg = port.waitmessage(500)
        if type(msg) = "roInputEvent"
            print "INPUT EVENT!"
            if msg.isInput()
                inputData = msg.getInfo()
                'print inputData'
                for each item in inputData
                    print item + ": " inputData[item]
                end for

                ' pass the deeplink to UI (keys vary by launcher; content id is required)
                contentIdVal = invalid
                if inputData.DoesExist("contentID")
                    contentIdVal = inputData.contentID
                else if inputData.DoesExist("contentId")
                    contentIdVal = inputData.contentId
                end if
                mediaTypeVal = ""
                if inputData.DoesExist("mediaType")
                    mediaTypeVal = inputData.mediaType
                else if inputData.DoesExist("MediaType")
                    mediaTypeVal = inputData.MediaType
                end if
                if contentIdVal <> invalid and box(contentIdVal).toStr().trim() <> ""
                    deeplink = {
                        id: contentIdVal,
                        type: mediaTypeVal
                    }
                    print "got input deeplink= "; deeplink
                    m.top.inputData = deeplink
                end if
            end if
        end if
    end while
end sub
