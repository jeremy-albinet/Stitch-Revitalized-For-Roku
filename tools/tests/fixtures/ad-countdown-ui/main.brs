' Real SceneGraph nodes and unchanged production component handlers. There is
' no network, decoder, provider payload or synthetic replacement for the UI.
sub main()
    m.assertions = 0
    m.failures = 0
    m.startUs = 1791550000000000&
    m.port = CreateObject("roMessagePort")
    m.screen = CreateObject("roSGScreen")
    m.screen.SetMessagePort(m.port)
    m.scene = m.screen.CreateScene("AdCountdownFixture")
    m.screen.Show()
    print "STITCH_AD_UI_BEGIN: __MARKER__"
    testPresentation()
    testOwnership()
    testBadData()
    testLayoutAndCopy()
    testDisposal()
    m.screen.Close()
    print "STITCH_AD_UI_END: __MARKER__ "; FormatJson({assertions: m.assertions, failures: m.failures})
end sub

sub check(condition as boolean, message as string)
    m.assertions += 1
    if not condition
        m.failures += 1
        print "STITCH_AD_UI_FAIL: __MARKER__ " + message
    end if
end sub

function addBadge() as object
    badge = CreateObject("roSGNode", "AdCountdown")
    m.scene.AppendChild(badge)
    check(badge.Subtype() = "AdCountdown" and badge.FindNode("adTitle").Subtype() = "Label" and badge.FindNode("adTime").Subtype() = "Label", "actual component has real Label nodes")
    check(not badge.visible and not badge.focusable, "new badge is hidden and nonfocusable")
    return badge
end function

function cue(startUs as longinteger, durationUs as longinteger, count as integer, position as integer) as object
    return {startUs: startUs, endUs: startUs + durationUs, durationUs: durationUs, podCount: count, podPosition: position}
end function

sub load(badge as object, owner as string, cues as object)
    check(badge.CallFunc("beginContent", owner), "content owner begins")
    check(badge.CallFunc("setCues", owner, cues), "sanitized cues accepted")
    hidden(badge, "cue delivery alone has no presentation clock")
end sub

sub hidden(badge as object, why as string)
    check(not badge.visible and badge.FindNode("adTitle").text = "" and badge.FindNode("adTime").text = "", why)
end sub

sub shown(badge as object, title as string, time as string, why as string)
    check(badge.visible and badge.FindNode("adTitle").text = title and badge.FindNode("adTime").text = Chr(183) + " " + time, why)
end sub

sub dispose(badge as object)
    badge.CallFunc("onDestroy")
    m.scene.RemoveChild(badge)
end sub

sub testPresentation()
    badge = addBadge()
    ' Independent expected times are written as wall-clock strings; this
    ' fixture does not call the production view helper to compute a golden.
    cues = [cue(m.startUs, 30239000&, 4, 0), cue(m.startUs + 30239000&, 15224000&, 4, 1)]
    load(badge, "contentA", cues)
    check(badge.CallFunc("updatePresented", "contentA", m.startUs - 1&, "playing"), "before-ad presentation accepted")
    hidden(badge, "no badge before exact ad start")
    check(badge.CallFunc("updatePresented", "contentA", m.startUs, "playing"), "exact ad start accepted")
    shown(badge, "Ad 1 of 4", "0:31", "fractional first duration rounds upward")
    badge.CallFunc("updatePresented", "contentA", m.startUs + 239000&, "playing")
    shown(badge, "Ad 1 of 4", "0:30", "whole remaining second is not rounded twice")
    badge.CallFunc("updatePresented", "contentA", m.startUs + 238999&, "playing")
    shown(badge, "Ad 1 of 4", "0:31", "one microsecond past boundary rounds upward")
    badge.CallFunc("updatePresented", "contentA", m.startUs + 2000000&, "paused")
    shown(badge, "Ad 1 of 4", "0:29", "paused frame uses its presentation time")
    wait(80, m.port)
    shown(badge, "Ad 1 of 4", "0:29", "pause has no autonomous timer")
    badge.CallFunc("updatePresented", "contentA", m.startUs + 2000000&, "buffering")
    wait(80, m.port)
    shown(badge, "Ad 1 of 4", "0:29", "buffering retains frozen presented time")
    badge.CallFunc("updatePresented", "contentA", m.startUs + 30239000& - 1&, "playing")
    shown(badge, "Ad 1 of 4", "0:01", "last microsecond stays visible")
    badge.CallFunc("updatePresented", "contentA", m.startUs + 30239000&, "playing")
    shown(badge, "Ad 2 of 4", "0:16", "next individual ad begins at prior half-open end")
    badge.CallFunc("updatePresented", "contentA", m.startUs + 45463000&, "playing")
    hidden(badge, "final half-open ad end hides badge")
    load(badge, "partialPod", [cue(m.startUs, 15224000&, 5, 3)])
    badge.CallFunc("updatePresented", "partialPod", m.startUs, "playing")
    shown(badge, "Ad 4 of 5", "0:16", "partial pod shows only actual current-ad duration and known ordinal")
    load(badge, "unknownPod", [cue(m.startUs, 60239000&, 0, -1)])
    badge.CallFunc("updatePresented", "unknownPod", m.startUs, "playing")
    shown(badge, "Ad", "1:01", "missing pod count never fabricates numbering")
    load(badge, "longAd", [cue(m.startUs, 3600000000&, 0, -1)])
    badge.CallFunc("updatePresented", "longAd", m.startUs, "playing")
    shown(badge, "Ad", "60:00", "maximum admitted duration keeps all countdown digits")
    load(badge, "overlap", [cue(m.startUs, 30239000&, 4, 0), cue(m.startUs + 30238000&, 15224000&, 4, 1)])
    badge.CallFunc("updatePresented", "overlap", m.startUs + 30238000&, "playing")
    shown(badge, "Ad 2 of 4", "0:16", "proven adjacent one-millisecond rounding tie selects the current ad")
    dispose(badge)
end sub

sub testOwnership()
    badge = addBadge()
    cues = [cue(m.startUs, 30000000&, 4, 0)]
    load(badge, "ownerOne", cues)
    cues.Clear()
    badge.CallFunc("updatePresented", "ownerOne", m.startUs, "playing")
    shown(badge, "Ad 1 of 4", "0:30", "caller array mutation cannot change retained sanitized cues")
    inputCue = cue(m.startUs, 30000000&, 4, 0)
    check(badge.CallFunc("setCues", "ownerOne", [inputCue]), "caller primitive record accepted")
    inputCue.endUs = m.startUs + 1000000&
    inputCue.durationUs = 1000000&
    inputCue.podCount = 0
    inputCue.podPosition = -1
    badge.CallFunc("updatePresented", "ownerOne", m.startUs, "playing")
    shown(badge, "Ad 1 of 4", "0:30", "caller primitive record mutation cannot change copied fields")
    check(badge.CallFunc("beginContent", "ownerTwo"), "new content replaces owner")
    hidden(badge, "replacement clears prior cue and display")
    check(not badge.CallFunc("updatePresented", "ownerOne", m.startUs, "playing"), "late old-owner presentation rejected")
    hidden(badge, "old content cannot resurrect badge")
    check(badge.CallFunc("setCues", "ownerTwo", [cue(m.startUs, 10000000&, 0, -1)]), "replacement cues accepted")
    badge.CallFunc("updatePresented", "ownerTwo", m.startUs, "playing")
    shown(badge, "Ad", "0:10", "new owner renders its own cues")
    check(not badge.CallFunc("setCues", "ownerOne", [cue(m.startUs, 9000000&, 4, 2)]), "late old-owner cues rejected")
    hidden(badge, "stale call hides stale presentation")
    badge.CallFunc("updatePresented", "ownerTwo", m.startUs, "playing")
    shown(badge, "Ad", "0:10", "stale cues never replace current owner cues")
    check(not badge.CallFunc("clear", "ownerOne"), "old owner cannot close new content")
    badge.CallFunc("updatePresented", "ownerTwo", m.startUs, "playing")
    shown(badge, "Ad", "0:10", "current owner remains valid after stale clear")
    check(badge.CallFunc("clear", "ownerTwo"), "current owner clear accepted")
    hidden(badge, "clear empties actual labels and hides group")
    check(not badge.CallFunc("updatePresented", "ownerTwo", m.startUs, "playing"), "cleared content cannot resume without new begin")
    for each state in ["error", "finished", "stopped", "stopping", "none", "invalid-state"]
        load(badge, "stateOwner", [cue(m.startUs, 30000000&, 0, -1)])
        badge.CallFunc("updatePresented", "stateOwner", m.startUs, "playing")
        check(not badge.CallFunc("updatePresented", "stateOwner", m.startUs, state), "terminal or unsupported state clears " + state)
        hidden(badge, "no badge after " + state)
        check(not badge.CallFunc("updatePresented", "stateOwner", m.startUs, "playing"), "cleared state cannot resurrect " + state)
    end for
    dispose(badge)
end sub

sub testBadData()
    badge = addBadge()
    for each owner in [invalid, 10, "", "bad/owner", String(65, "x")]
        check(not badge.CallFunc("beginContent", owner), "malformed owner rejected")
        hidden(badge, "malformed owner has no visible badge")
    end for
    load(badge, "validOwner", [cue(m.startUs, 30000000&, 0, -1)])
    for each clock in [invalid, "1791550000000000", -1&, 10.5, 4102444800000001&]
        check(not badge.CallFunc("updatePresented", "validOwner", clock, "playing"), "missing imprecise malformed or out-of-range clock rejected")
        hidden(badge, "bad clock never leaves stale countdown")
    end for
    badge.CallFunc("updatePresented", "validOwner", 1791550000000000#, "playing")
    shown(badge, "Ad", "0:30", "explicit precise Double UTC accepted")
    badge.CallFunc("updatePresented", "validOwner", 0#, "playing")
    hidden(badge, "relative zero is never mapped into today's UTC cue")
    for each state in [invalid, 1, [], {}]
        check(not badge.CallFunc("updatePresented", "validOwner", m.startUs, state), "non-string playback state rejected")
        hidden(badge, "bad playback state hides countdown")
    end for
    extra = cue(m.startUs, 30000000&, 0, -1)
    extra.tracking = "must-not-be-retained"
    wrongType = cue(m.startUs, 30000000&, 0, -1)
    wrongType.durationUs = "30000000"
    badInputs = [invalid, {}, [extra], [wrongType], [cue(m.startUs, 30000000&, 4, 4)], [cue(m.startUs, 0&, 0, -1)], [cue(m.startUs, 30000000&, 0, -1), cue(m.startUs, 30000000&, 0, -1)], [cue(m.startUs, 30000000&, 4, 0), cue(m.startUs + 29998000&, 15000000&, 4, 1)]]
    tooMany = []
    for i = 0 to 32
        tooMany.Push(cue(m.startUs + i * 40000000&, 30000000&, 0, -1))
    end for
    badInputs.Push(tooMany)
    for each input in badInputs
        load(badge, "validOwner", [cue(m.startUs, 30000000&, 0, -1)])
        badge.CallFunc("updatePresented", "validOwner", m.startUs, "playing")
        check(not badge.CallFunc("setCues", "validOwner", input), "malformed unbounded raw or ambiguous cues rejected")
        hidden(badge, "bad cues clear labels before any other update")
        badge.CallFunc("updatePresented", "validOwner", m.startUs, "playing")
        hidden(badge, "bad cues clear previously valid cue storage")
    end for
    check(badge.CallFunc("setCues", "validOwner", []), "empty sanitized cue array accepted")
    badge.CallFunc("updatePresented", "validOwner", m.startUs, "playing")
    hidden(badge, "empty cue array remains hidden")
    tooMany.Pop()
    check(badge.CallFunc("setCues", "validOwner", tooMany), "maximum 32 sanitized cues accepted")
    badge.CallFunc("updatePresented", "validOwner", m.startUs + 31& * 40000000&, "playing")
    shown(badge, "Ad", "0:30", "final cue in bounded array remains reachable")
    dispose(badge)
end sub

sub testLayoutAndCopy()
    badge = addBadge()
    load(badge, "layoutOwner", [cue(m.startUs, 30000000&, 4, 0)])
    badge.CallFunc("updatePresented", "layoutOwner", m.startUs, "playing")
    plate = badge.FindNode("plate")
    title = badge.FindNode("adTitle")
    timer = badge.FindNode("adTime")
    check(plate.Subtype() = "Poster" and plate.height = 40 and plate.width <= 280, "real rounded plate obeys height and width caps")
    check(title.font.size = 22 and timer.font.size = 22, "countdown uses readable Archivo size")
    check(badge.translation[0] + plate.width = 1232 and badge.translation[1] = 48, "full HD placement keeps exact right and top safe insets")
    check(not title.wrap and title.maxLines = 1 and title.width + title.translation[0] + 8 <= timer.translation[0], "title cannot wrap into or overlap countdown")
    check(timer.translation[0] + timer.width = plate.width - 18, "time keeps its own right padding")
    badge.videoAreaWidth = 960
    check(badge.translation[0] + plate.width = 912 and badge.visible, "chat-sized video has its own safe right corner")
    badge.videoAreaWidth = 320
    check(plate.width = 224 and badge.translation[0] = 48 and title.width > 0 and timer.width = 96, "narrow supported video shrinks title space without truncating countdown")
    badge.videoAreaWidth = 200
    check(not badge.visible, "unsupported narrow geometry stays hidden")
    badge.videoAreaWidth = 1280
    shown(badge, "Ad 1 of 4", "0:30", "valid geometry restores current exact countdown")
    badge.numberedAdLabel = "Anzeige {0} von {1}"
    shown(badge, "Anzeige 1 von 4", "0:30", "host localized numbering updates actual Label")
    badge.numberedAdLabel = String(100, "W") + " {0} / {1}"
    check(title.text = String(100, "W") + " 1 / 4" and title.width = 140 and title.height = 40 and title.ellipsisText = Chr(8230), "long localized title uses bounded native ellipsis area")
    check(timer.text = Chr(183) + " 0:30" and timer.width = 96 and not timer.wrap, "long localized copy leaves countdown independently readable")
    for each template in ["Ads", "Ad {0} {0} / {1}", "Ad {0} / {1}" + Chr(10), String(257, "x")]
        badge.numberedAdLabel = template
        shown(badge, "Ad 1 of 4", "0:30", "invalid localized numbering falls back to truthful bounded copy")
    end for
    load(badge, "single", [cue(m.startUs, 30000000&, 0, -1)])
    badge.CallFunc("updatePresented", "single", m.startUs, "playing")
    badge.adLabel = "Anuncio"
    shown(badge, "Anuncio", "0:30", "host localized single-ad label updates")
    badge.adLabel = Chr(10)
    shown(badge, "Ad", "0:30", "invalid single-ad label safely falls back")
    check(not badge.focusable and not title.focusable and not timer.focusable and not plate.focusable, "visible badge and children remain nonfocusable")
    for i = 0 to badge.GetChildCount() - 1
        child = badge.GetChild(i)
        check(child.Subtype() <> "Timer" and child.Subtype() <> "Task" and child.Subtype() <> "Button", "badge creates no timer task or interactive control")
    end for
    dispose(badge)
end sub

sub testDisposal()
    badge = addBadge()
    load(badge, "disposeOwner", [cue(m.startUs, 30000000&, 0, -1)])
    badge.CallFunc("updatePresented", "disposeOwner", m.startUs, "playing")
    check(badge.supportsDisposal, "explicit application disposal exported")
    badge.CallFunc("onDestroy")
    hidden(badge, "disposal clears actual labels and hides component")
    badge.CallFunc("onDestroy")
    check(not badge.CallFunc("beginContent", "newOwner"), "disposed component refuses new owner")
    check(not badge.CallFunc("setCues", "disposeOwner", [cue(m.startUs, 30000000&, 0, -1)]), "disposed component refuses late cues")
    check(not badge.CallFunc("updatePresented", "disposeOwner", m.startUs, "playing"), "disposed component refuses late presentation")
    badge.videoAreaWidth = 960
    badge.adLabel = "Late translation"
    hidden(badge, "post-disposal field changes cannot resurrect badge")
    m.scene.RemoveChild(badge)
end sub
