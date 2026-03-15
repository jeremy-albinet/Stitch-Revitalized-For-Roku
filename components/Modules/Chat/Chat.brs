sub init()
    m.chatPanel = m.top.findNode("chatPanel")
    m.maskgroup = m.top.findNode("maskGroup")
    m.chatLoadingLabel = m.top.findNode("chatLoadingLabel")
    setChatPanelSize()
    setSizingParameters()
    ' determines how far down the screen the first message will appear
    ' set to 700 to have first message at bottom of screen.
    m.translation = m.lower_bound - m.line_height
    ' Track messages by id for CLEARMSG support: {msg-id -> group node}
    m.messageNodeById = {}
    ' Track messages by username for CLEARCHAT support: {username -> [group nodes]}
    m.messageNodesByUser = {}
end sub

sub updatePanelTranslation()
    ' m.chatPanel.translation = [(m.top.width * 3), 0]
    setChatPanelSize()
    setSizingParameters()
    m.maskGroup.maskSize = [(m.chatpanel.width * m.global.constants.maskScaleFactor), (m.chatPanel.height * m.global.constants.maskScaleFactor)]
    m.maskGroup.maskOffset = [0, 0]
    for each chatmessage in m.chatPanel.getChildren(-1, 0)
        m.chatPanel.removeChild(chatmessage)
    end for
end sub

sub setSizingParameters()
    '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    ' Size and Spacing Settings
    '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    m.left_bound = m.font_size / 2
    m.right_bound = m.chatPanel.width - m.font_size
    m.badge_size = (m.font_size * 1.6)
    m.line_gap = m.font_size * 0.25
    m.line_height = (m.font_size * 1.4)

    m.message_height = (m.badge_size * 1.8)

    m.lower_bound = m.chatPanel.height - m.message_height
    '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
end sub

sub setChatPanelSize()
    m.font_size = m.top.fontSize
    ' m.chatPanel.width = m.global.constants.screenWidth
    ' m.chatPanel.height = m.global.constants.screenHeight
    m.translation = m.chatPanel.height - m.font_size
    m.lower_bound = m.chatPanel.height - m.font_size
    m.right_bound = m.chatPanel.width - m.font_size
    m.upper_bound = 0 - (m.chatPanel.height - m.font_size)
end sub

sub onInvisible()
    if m.top.visible = false
        m.chat.control = "stop"
    else
        m.chat.control = "run"
    end if
end sub

sub stopJobs()
    if m.chat <> invalid
        m.chat.control = "stop"
    end if
    if m.EmoteJob <> invalid
        m.EmoteJob.control = "stop"
    end if
end sub

sub onVideoChange()
    if not m.top.control
        m.chat.control = "stop"
        m.top.control = true
    end if
end sub

sub onEnterChannel()
    ' ? "Chat >> onEnterChannel > " m.top.channel
    if get_user_setting("ChatWebOption", "true") = "true"
        m.chat = m.top.findnode("ChatJob")
        m.chat.forceLive = m.top.forceLive
        ' m.chat.observeField("nextComment", "onNewComment")
        m.chat.observeField("nextCommentObj", "onNewCommentObj")
        m.chat.observeField("lastSentMessage", "onMessageSent")
        m.chat.observeField("clearMsgEvent", "onClearMsg")
        m.chat.observeField("clearChatEvent", "onClearChat")
        ' m.chat.observeField("clientComment", "onNewComment")
        m.chat.channel = m.top.channel
        m.chat.control = "stop"
        m.chat.control = "run"
    end if
    m.EmoteJob = m.top.findnode("EmoteJob")
    m.EmoteJob.observeField("loading", "onEmoteJobLoading")
    m.EmoteJob.channel_id = m.top.channel_id
    m.EmoteJob.channel = m.top.channel
    m.EmoteJob.control = "run"
end sub

sub onEmoteJobLoading()
    if m.chatLoadingLabel <> invalid
        m.chatLoadingLabel.visible = m.EmoteJob.loading
    end if
end sub

sub onSendMessage()
    if m.chat <> invalid and m.top.sendMessage <> "" and m.top.sendMessage <> invalid
        m.chat.sendMessage = m.top.sendMessage
        m.top.sendMessage = ""
    end if
end sub

sub onMessageSent()
    if m.chat.lastSentMessage <> "" and m.chat.lastSentMessage <> invalid
        showSystemMessage("Sent ✓ " + m.chat.lastSentMessage)
    end if
end sub

sub onClearMsg()
    ev = m.chat.clearMsgEvent
    if ev = invalid then return
    targetId = ""
    if ev?.tags?.target_msg_id <> invalid
        targetId = ev.tags.target_msg_id
    end if
    if targetId <> "" and m.messageNodeById.DoesExist(targetId)
        node = m.messageNodeById[targetId]
        strikeGroup = node.findNode("strikeLine_" + targetId)
        if strikeGroup = invalid
            nodeRect = node.localBoundingRect()
            strike = createObject("roSGNode", "Rectangle")
            strike.id = "strikeLine_" + targetId
            strike.width = nodeRect.width + 20
            strike.height = 2
            strike.color = "0xFF4444FF"
            strike.translation = [0, nodeRect.height / 2]
            node.appendChild(strike)
        end if
    end if
end sub

sub onClearChat()
    ev = m.chat.clearChatEvent
    if ev = invalid then return
    targetUser = ev.parameters.trim()
    if targetUser = "" or targetUser = invalid
        ' Full chat clear — remove all messages
        for each chatmessage in m.chatPanel.getChildren(-1, 0)
            m.chatPanel.removeChild(chatmessage)
        end for
        m.messageNodeById = {}
        m.messageNodesByUser = {}
        m.translation = m.lower_bound - m.line_height
    else
        ' Per-user timeout/ban — strike out that user's messages
        if m.messageNodesByUser.DoesExist(targetUser)
            for each node in m.messageNodesByUser[targetUser]
                nodeRect = node.localBoundingRect()
                strike = createObject("roSGNode", "Rectangle")
                strike.width = nodeRect.width + 20
                strike.height = 2
                strike.color = "0xFF4444FF"
                strike.translation = [0, nodeRect.height / 2]
                node.appendChild(strike)
            end for
        end if
    end if
end sub

sub showSystemMessage(text as string)
    group = createObject("roSGNode", "Group")
    label = createObject("roSGNode", "SimpleLabel")
    label.fontSize = m.font_size
    label.fontUri = "pkg:/fonts/Archivo-Regular.otf"
    label.color = "0xFFFFFFCC"
    label.visible = true
    label.text = text
    group.appendChild(label)
    appendChatGroup(group)
    ' Auto-remove after 4 seconds
    removeTimer = createObject("roSGNode", "Timer")
    removeTimer.duration = 4
    removeTimer.repeat = false
    removeTimer.observeField("fire", "onSystemMessageTimeout")
    m.pendingSystemGroup = group
    removeTimer.control = "start"
end sub

sub onSystemMessageTimeout()
    if m.pendingSystemGroup <> invalid
        m.chatPanel.removeChild(m.pendingSystemGroup)
        m.pendingSystemGroup = invalid
    end if
end sub

sub appendChatGroup(group as object)
    group.translation = [m.left_bound, m.translation]
    m.chatPanel.appendChild(group)
    y_translation = group.localBoundingRect().height + m.line_gap
    if m.translation + y_translation > m.chatPanel.height
        for each chatmessage in m.chatPanel.getChildren(-1, 0)
            if (chatmessage.translation[1] + chatmessage.localBoundingRect().height) < 0
                m.chatPanel.removeChild(chatmessage)
            else
                chatmessage.translation = [chatmessage.translation[0], (chatmessage.translation[1] - y_translation)]
            end if
        end for
    else
        m.translation += y_translation
    end if
end sub


function extractMessage(section) as object
    m.userstate_change = false
    words = section.Split(" ")
    if words[2] = "USERSTATE"
        m.userstate_change = true
    end if
    message = ""
    for i = 4 to words.Count() - 1
        message += words[i] + " "
    end for
    return message
end function

function buildBadges(badges)
    group = createObject("roSGNode", "Group")
    group.visible = true
    badge_translation = 0
    for each badge in badges
        if badge <> invalid and badge <> ""
            if m.global.twitchBadges <> invalid
                if m.global.twitchBadges[badge] <> invalid
                    poster = createObject("roSGNode", "Poster")
                    poster.uri = m.global.twitchBadges[badge]
                    poster.width = m.badge_size
                    poster.height = m.badge_size
                    poster.visible = true
                    poster.translation = [badge_translation, 0]
                    group.appendChild(poster)
                    badge_translation += (m.badge_size + (m.badge_size / 6))
                end if
            end if
        end if
    end for
    return group
end function

function buildEmote(posterUri)
    poster = createObject("roSGNode", "Poster")
    poster.uri = posterUri
    poster.visible = true
    bounding_rect = poster.localBoundingRect()
    poster_width = bounding_rect.width
    poster_height = bounding_rect.height
    ratio = 1
    if poster_height <> 0
        ratio = m.badge_size / poster_height
        poster.height = (poster_height * ratio)
    else
        poster.height = m.badge_size
    end if
    if poster_width <> 0
        poster.width = (poster_width * ratio)
    else
        poster.width = m.badge_size
    end if
    return poster
end function

function buildUsername(display_name, color)
    username = createObject("roSGNode", "SimpleLabel")
    username.text = display_name
    if color = ""
        color = "FFFFFF"
    end if
    username.color = "0x" + color + "FF"
    username.visible = true
    username.fontSize = m.font_size
    username.fontUri = "pkg:/fonts/Archivo-Bold.otf"
    return username
end function

function buildColon()
    colon = createObject("roSGNode", "SimpleLabel")
    colon.fontSize = m.font_size
    colon.fontUri = "pkg:/fonts/Archivo-Regular.otf"
    colon.color = "0xFFFFFFFF"
    colon.visible = true
    colon.text = ": "
    return colon
end function




function wordOrImage(word, isUrl = false, color = "")
    if m.global.emoteCache.DoesExist(word)
        return buildEmote(m.global.emoteCache[word])
    else
        message_text = createObject("roSGNode", "SimpleLabel")
        message_text.fontSize = m.font_size
        message_text.fontUri = "pkg:/fonts/Archivo-Regular.otf"
        message_text.visible = true
        message_text.text = word + " "
        if color <> ""
            message_text.color = "0x" + color + "FF"
        end if
        if isUrl
            message_text.color = m.global.constants.colors.twitch.purple9
        end if
        return message_text
    end if
end function

'

function buildMessage(message, x_translation)
    return buildMessage_colored(message, x_translation, "")
end function

function buildMessage_colored(message, x_translation, color)
    message_group = createObject("roSGNode", "Group")
    words = message.Split(" ")
    line_available_space = m.right_bound - x_translation
    current_line = 0
    for each word in words
        if asc(word.right(1)) = 917504
            word = word.mid(0, (word.len() - 1))
            ? "Found invalid character"
        end if
        ' Make room for emotes just in case
        urlRegex = createObject("roRegex", "https?:\/\/[a-zA-Z0-9\.]+", "i")
        isUrl = urlRegex.IsMatch(word)

        block = wordOrImage(word, isUrl, color)
        block_width = block.localBoundingRect().width
        if block_width > m.right_bound
            ? "break it up!"
            block = createObject("roSGNode", "Group")
            charTranslation = 0
            charLine = 0
            charLineAvailableSpace = m.right_bound - x_translation
            for each char in word.split("")
                charNode = createObject("roSGNode", "SimpleLabel")
                charNode.fontSize = m.font_size
                charNode.fontUri = "pkg:/fonts/Archivo-Regular.otf"
                charNode.visible = true
                charNode.text = char
                if color <> ""
                    charNode.color = "0x" + color + "FF"
                end if
                if isUrl
                    charNode.color = m.global.constants.colors.twitch.purple9
                end if
                charWidth = charNode.localBoundingRect().width
                if (charLineAvailableSpace - charWidth) < 0
                    charLine++
                    charLineAvailableSpace = m.right_bound - m.left_bound
                    charTranslation = 0 - x_translation + m.left_bound
                end if
                charNode.translation = [(charTranslation), (charLine * (m.badge_size + m.line_gap))]
                charLineAvailableSpace -= charWidth
                charTranslation += charWidth
                block.appendChild(charNode)
            end for
            block_width = block.localBoundingRect().width
        else if line_available_space - block_width <= 0
            current_line++
            line_available_space = m.right_bound - m.left_bound
        end if
        block.translation = [(m.right_bound - line_available_space), (current_line * (m.badge_size + m.line_gap))]
        if block_width = 0
            block_width = m.badge_size
        end if
        line_available_space -= block_width
        message_group.appendChild(block)
    end for
    return message_group
end function

sub onNewCommentObj()
    m.chat.readyForNextComment = false
    if m.chat.nextCommentObj <> invalid
        comment = m.chat.nextCommentObj
        command = comment?.command?.command

        ' Handle NOTICE messages (slow mode, subscriber-only, etc.)
        if command = "NOTICE"
            noticeText = comment.parameters.trim()
            if noticeText <> ""
                showSystemMessage("📢 " + noticeText)
            end if
            m.chat.readyForNextComment = true
            return
        end if

        ' Handle USERNOTICE (sub/resub/gift-sub alerts)
        if command = "USERNOTICE"
            msgId = ""
            if comment?.tags?.msg_id <> invalid
                msgId = comment.tags.msg_id
            end if
            systemMsg = ""
            senderName = ""
            if comment?.tags?.display_name <> invalid
                senderName = comment.tags.display_name
            end if
            if msgId = "sub"
                systemMsg = "🎉 " + senderName + " just subscribed!"
            else if msgId = "resub"
                months = ""
                if comment?.tags?.msg_param_cumulative_months <> invalid
                    months = " (" + comment.tags.msg_param_cumulative_months + " months)"
                end if
                systemMsg = "🎉 " + senderName + " resubscribed!" + months
            else if msgId = "subgift"
                recipient = ""
                if comment?.tags?.msg_param_recipient_display_name <> invalid
                    recipient = comment.tags.msg_param_recipient_display_name
                end if
                systemMsg = "🎁 " + senderName + " gifted a sub to " + recipient + "!"
            else if msgId = "submysterygift"
                count = "1"
                if comment?.tags?.msg_param_mass_gift_count <> invalid
                    count = comment.tags.msg_param_mass_gift_count
                end if
                systemMsg = "🎁 " + senderName + " gifted " + count + " sub(s)!"
            else if msgId = "raid"
                viewers = ""
                if comment?.tags?.msg_param_viewerCount <> invalid
                    viewers = " (" + comment.tags.msg_param_viewerCount + " viewers)"
                end if
                systemMsg = "⚔️ " + senderName + " is raiding!" + viewers
            else if msgId = "ritual"
                systemMsg = "✨ " + senderName + " is new here! Say hi!"
            else
                systemMsg = "📣 " + senderName
                if comment.parameters <> "" and comment.parameters <> invalid
                    systemMsg += ": " + comment.parameters.trim()
                end if
            end if
            if systemMsg <> ""
                showSystemMessage(systemMsg)
            end if
            m.chat.readyForNextComment = true
            return
        end if

        display_name = ""
        if comment?.tags?.display_name <> invalid
            display_name = comment.tags.display_name
        end if
        message = comment.parameters.trim()
        color = ""
        if comment?.tags?.color <> invalid
            color = comment.tags.color.replace("#", "")
        end if

        ' Detect /me action messages: body starts with chr(1)+"ACTION "
        isAction = false
        if message.left(7) = Chr(1) + "ACTION"
            isAction = true
            message = message.mid(7).trim()
            if message.right(1) = Chr(1)
                message = message.left(message.len() - 1)
            end if
        end if

        ' Detect channel point reward messages
        isReward = false
        if comment?.tags?.custom_reward_id <> invalid and comment.tags.custom_reward_id <> ""
            isReward = true
        end if

        badges = []
        if comment?.tags?.badges <> invalid
            for each key in comment.tags.badges
                badgeID = key
                badges.push(badgeID)
            end for
        end if
        emote_set = {}
        if comment?.tags?.emotes <> invalid
            for each emote in comment.tags.emotes.Items()
                value = { starts: [], length: 0 }
                for each emote_instance in emote.value
                    value.starts.push(Val(emote_instance.startposition))
                    value.length = (Val(emote_instance.endposition) - Val(emote_instance.startposition)) + 1
                end for
                emote_set[emote.key] = value
            end for
        end if

        quoteRegex = createObject("roRegex", "[\x{2018}\x{2019}]", "")
        message = quoteRegex.replace(message, "'")
        ' Grab missing Twitch emotes on the fly
        for each emoticon in emote_set.Items()
            e_start = emoticon.value.starts[0]
            emote_word = Mid(message, (e_start + 1), emoticon.value.length)
            if not m.global.emoteCache.DoesExist(emote_word)
                emoteCache = m.global.emoteCache
                if not emoteCache.DoesExist(emote_word)
                    emoteCache[emote_word] = "https://static-cdn.jtvnw.net/emoticons/v2/" + emoticon.key + "/static/light/1.0"
                end if
                m.global.setField("emoteCache", emoteCache)
            end if
        end for

        if display_name = "" or message = ""
            m.chat.readyForNextComment = true
            return
        end if

        x_translation = m.left_bound
        group = createObject("roSGNode", "Group")

        ' Channel point reward highlight background
        if isReward
            rewardBg = createObject("roSGNode", "Rectangle")
            rewardBg.color = "0x1A0A3FFF"
            rewardBg.width = m.chatPanel.width - m.left_bound
            rewardBg.height = m.message_height * 2
            rewardBg.translation = [0, 0]
            group.appendChild(rewardBg)
        end if

        badge_group = buildBadges(badges)
        badge_group.translation = [x_translation, 0]
        x_translation += badge_group.localBoundingRect().width + 1

        if isAction
            ' /me: render "* username message" all in the user's color
            username_label = buildUsername("* " + display_name + " ", color)
            username_label.translation = [x_translation, 0]
            x_translation += username_label.localBoundingRect().width + 1
            message_group = buildMessage_colored(message, x_translation, color)
            message_group.translation = [0, 0]
            group.appendChild(badge_group)
            group.appendChild(username_label)
            group.appendChild(message_group)
        else
            username = buildUsername(display_name, color)
            username.translation = [x_translation, 0]
            x_translation += username.localBoundingRect().width + 1

            colon = buildColon()
            colon.translation = [x_translation, 0]
            x_translation += colon.localBoundingRect().width + 1

            message_group = buildMessage(message, x_translation)
            message_group.translation = [0, 0]

            group.appendChild(badge_group)
            group.appendChild(username)
            group.appendChild(colon)
            group.appendChild(message_group)
        end if

        ' Track by msg-id for CLEARMSG
        msgId = ""
        if comment?.tags?.id <> invalid
            msgId = comment.tags.id
            if msgId <> ""
                m.messageNodeById[msgId] = group
            end if
        end if
        ' Track by username for CLEARCHAT
        trackUser = display_name.lower()
        if trackUser <> ""
            if not m.messageNodesByUser.DoesExist(trackUser)
                m.messageNodesByUser[trackUser] = []
            end if
            m.messageNodesByUser[trackUser].push(group)
        end if

        appendChatGroup(group)
    end if
    m.chat.readyForNextComment = true
end sub
