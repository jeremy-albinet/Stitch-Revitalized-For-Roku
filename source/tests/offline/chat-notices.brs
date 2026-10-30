' @include source/utils/ircParser.brs
sub main()
    gift = ircParseMessage("@id=gift1;login=alice;user-id=101;msg-id=subgift;system-msg=Alice\sgifted\sa\ssub\sto\sBob! :tmi.twitch.tv USERNOTICE #channel")
    if not noticeAssert(gift <> invalid, "gift without trailing chat text is accepted") then return
    if not noticeAssert(gift.parameters = "" and gift.tags.system_msg = "Alice gifted a sub to Bob!", "gift text is decoded without inventing a user message") then return
    if not noticeAssert(gift.tags.display_name = "alice", "sender display falls back to the login tag") then return
    identity = ircMessageIdentity(gift)
    if not noticeAssert(identity.id = "gift1" and identity.userId = "101" and identity.login = "alice", "notice identity uses the actor rather than the IRC server") then return
    if not noticeAssert(ircModerationMatches(identity, { kind: "user", userId: "", login: "alice" }), "notices participate in login-based moderation") then return

    resub = ircParseMessage("@id=resub1;display-name=Alice;login=alice;msg-id=resub;system-msg=Alice\ssubscribed\sfor\s6\smonths!;emotes=25:2-6,100-104 :tmi.twitch.tv USERNOTICE #channel :  Kappa thanks!")
    if not noticeAssert(resub <> invalid and resub.parameters = "  Kappa thanks!", "resub preserves the user's exact message") then return
    if not noticeAssert(resub.tags.emotes["25"].count() = 1 and resub.tags.emotes["25"][0].startPosition = 2, "emote positions refer to user text without a system prefix") then return
    if not noticeAssert(resub.tags.system_msg = "Alice subscribed for 6 months!", "system and user messages remain separate") then return

    for each kind in ["sub", "resub", "subgift", "submysterygift", "anonsubgift", "anonsubmysterygift", "giftpaidupgrade", "raid", "bitsbadgetier", "viewermilestone", "sharedchatnotice", "future-event"]
        notice = ircParseMessage("@msg-id=" + kind + ";system-msg=An\sevent :tmi.twitch.tv USERNOTICE #channel")
        if not noticeAssert(notice <> invalid and notice.tags.system_msg = "An event", "server-supplied text accepted for " + kind) then return
        if not noticeAssert(notice.tags.display_name = "", "system-only events do not invent a sender") then return
    end for
    announcement = ircParseMessage("@display-name=Alice;msg-id=announcement;emotes=25:0-4 :tmi.twitch.tv USERNOTICE #channel :Kappa hello")
    if not noticeAssert(announcement <> invalid and announcement.tags.emotes["25"].count() = 1, "user-only announcement remains renderable") then return
    multiline = ircParseMessage("@system-msg=Hello\nworld\r! :tmi.twitch.tv USERNOTICE #channel")
    if not noticeAssert(multiline <> invalid and multiline.tags.system_msg = "Hello" + chr(10) + "world" + chr(13) + "!", "escaped control characters stay within a tag") then return
    for each raw in ["USERNOTICE", "USERNOTICE :missing channel", "USERNOTICE channel :bad target", "@msg-id=subgift :tmi.twitch.tv USERNOTICE #channel", "@system-msg=\s :tmi.twitch.tv USERNOTICE #channel :  ", "@system-msg=" + string(1501, "x") + " :tmi.twitch.tv USERNOTICE #channel", "@system-msg=gift :tmi.twitch.tv USERNOTICE #channel :" + string(1501, "x")]
        if not noticeAssert(ircParseMessage(raw) = invalid, "empty, malformed and oversized notices are rejected") then return
    end for
    print "STITCH_TEST_PASS: chat notices"
end sub

function noticeAssert(condition as boolean, description as string) as boolean
    if not condition then print "STITCH_TEST_FAIL: chat notices " + description
    return condition
end function
