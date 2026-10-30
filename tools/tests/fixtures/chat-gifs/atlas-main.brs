sub main()
    m.checks = 0
    m.failures = 0
    fs = createObject("roFileSystem")
    state = getGlobalAA()
    state.mode = "valid"
    state.checkpoints = 0
    state.decodeIndex = 0
    state.golden = parseJson(readAsciiFile("pkg:/pillow-goldens.json"))
    state.official = true
    m.top = { stopRequested: false }
    disposalProbe = "__DISPOSAL_PROBE__"
    if disposalProbe <> ""
        runDisposalUnwindProbe(fs, disposalProbe)
        if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
        return
    end if
    budgetProbe = "__BUDGET_PROBE__"
    if budgetProbe <> ""
        runBudgetProbe(fs, budgetProbe)
        if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
        return
    end if
    bytes = createObject("roByteArray")
    bytes.readFile("pkg:/official.gif")
    info = chatAdmitGif(bytes)
    check(info.images.count() = 15 and info.durationMs = 990 and info.loopCount = 0, "checked metadata retains every frame/delay and infinite loop")
    runMovie(fs, bytes, "official", invalid)
    check(state.decodeIndex = 15, "all fifteen independently pinned wrappers and native stills decoded")
    state.official = false
    for each sample in parseJson(readAsciiFile("pkg:/atlas-cases.json"))
        bytes.readFile("pkg:/" + sample.name + ".gif")
        expectedLoop = -1
        if sample.name = "disposals" then expectedLoop = 0
        if sample.name = "opaque-background" then expectedLoop = 2
        check(chatAdmitGif(bytes).loopCount = expectedLoop, "actual finite/infinite/absent loop metadata: " + sample.name)
        expected = sample.expected
        if sample.engineExpected <> invalid then expected = sample.engineExpected
        runMovie(fs, bytes, sample.name, expected)
    end for
    for each mode in ["32-frames", "33-frames", "conversion-deadline", "request-deadline", "finish-deadline", "finish-request-deadline", "cancel-before", "cancel-during", "cancel-at-finish", "cancel-after-png", "wrapper-write", "wrapper-append", "wrapper-stat", "decode-invalid", "decode-size", "base-copy-failed", "draw-failed", "draw-throw", "scale-failed", "scale-throw", "png-write", "png-stat", "png-read", "png-corrupt", "png-admission", "delete-source", "delete-wrapper"]
        state.mode = mode
        state.official = false
        state.checkpoints = 0
        state.decodeIndex = 0
        m.top.stopRequested = mode = "cancel-before"
        source = "disposals"
        if mode = "32-frames" or mode = "33-frames" then source = mode
        bytes.readFile("pkg:/" + source + ".gif")
        path = "tmp:/stitch-emote-failure-" + mode + "/emote.gif"
        fs.createDirectory(chatAnimationDirectory(path))
        bytes.writeFile(path)
        result = invalid
        try
            result = chatConvertGif(fs, bytes, path, { totalMilliseconds: fixtureRequestTime })
        catch e
        end try
        check((result <> invalid) = (mode = "32-frames"), "bounded conversion failure/acceptance: " + mode)
        check(state.drawQueue.count() = 0, "native draws finished before failure/cancel unwinds source refs: " + mode)
        if mode = "finish-deadline" or mode = "finish-request-deadline" or mode = "cancel-at-finish" then check(state.pngExports = 0, "post-fence deadline/cancel cannot export a partial movie: " + mode)
        if result <> invalid then check(result.atlasWidth * result.atlasHeight = 131072 and result.frames = 32, "exact atlas/frame ceiling admitted without truncation")
        check(directoryBytes(fs, chatAnimationDirectory(path)) <= 3145728, "all partial files remain under reserved 3 MiB peak: " + mode)
        if mode = "delete-source" or mode = "delete-wrapper"
            check(fs.exists(path) or fs.exists(chatAnimationDirectory(path) + "/frame.gif"), "failed deletion retains its owned file")
        end if
        state.mode = "valid"
        check(deleteChatAnimationFile(fs, path) and not fs.exists(chatAnimationDirectory(path)), "fixed owned files cleaned after conversion failure: " + mode)
    end for
    m.top.stopRequested = false
    ' Unknown files are never deleted, even in an otherwise-owned directory.
    directory = "tmp:/stitch-emote-unknown"
    fs.createDirectory(directory)
    bytes.fromAsciiString("sentinel")
    bytes.writeFile(directory + "/keep.txt")
    check(not deleteChatAnimationFile(fs, directory + "/emote.gif") and fs.exists(directory + "/keep.txt"), "unknown file blocks cleanup acknowledgment without broad deletion")
    png = createObject("roByteArray")
    png.readFile("pkg:/rgba.png")
    check(chatGifPng(png, 2, 2), "actual RGBA PNG with signed CRC admitted")
    check(not chatGifPng(png, 1, 2), "wrong PNG dimensions rejected")
    png[40] = (png[40] + 1) mod 256
    check(not chatGifPng(png, 2, 2), "PNG CRC mutation rejected")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
end sub

sub runDisposalUnwindProbe(fs as object, mode as string)
    state = getGlobalAA()
    state.mode = mode
    state.official = false
    bytes = createObject("roByteArray")
    bytes.readFile("pkg:/disposals.gif")
    path = "tmp:/stitch-emote-probe-" + mode + "/emote.gif"
    fs.createDirectory(chatAnimationDirectory(path))
    bytes.writeFile(path)
    result = invalid
    errorMessage = ""
    try
        result = chatConvertGif(fs, bytes, path, { totalMilliseconds: fixtureRequestTime })
    catch e
        errorMessage = e.message
    end try
    check(result = invalid, "disposal-2 fault rejects movie: " + mode)
    check(state.disposalCheckpoint and state.decodeIndex = 3, "exact disposal base-copy checkpoint reached: " + mode)
    check(state.disposalQueueAtCheckpoint = 1 and state.disposalFenceAtCheckpoint = 3, "one base copy queued before cleared bitmap allocation/finish: " + mode)
    check(state.drawQueue.count() = 0, "disposal-2 pending draws completed before source unwind: " + mode + " queued=" + state.drawQueue.count().toStr())
    fences = 4
    if mode = "disposal-rect-false" then fences = 5
    check(state.finishCalls = fences, "disposal-2 failure uses completion fence: " + mode)
    if mode = "disposal-cancel" then check(errorMessage = "GIF conversion cancelled", "cancel thrown by actual helper check")
    if mode = "disposal-deadline" or mode = "disposal-request-deadline" then check(errorMessage = "GIF conversion deadline", "exact 3000/8000ms helper deadline thrown")
    if mode = "disposal-allocation" then check(errorMessage = "scripted cleared bitmap allocation exception", "cleared native allocation exception propagated")
    if mode = "disposal-rect-false" then check(state.disposalRectCheckpoint, "false result injected after rectangle copy queued")
    check(state.pngExports = 0, "disposal-2 rejected work never exported")
    check(directoryBytes(fs, chatAnimationDirectory(path)) <= 3145728, "failed disposal stays inside file reservation")
    check(deleteChatAnimationFile(fs, path) and not fs.exists(chatAnimationDirectory(path)), "owned-file cleanup follows disposal completion")
end sub

sub runBudgetProbe(fs as object, mode as string)
    state = getGlobalAA()
    state.mode = mode
    state.decodeIndex = 0
    state.checkpoints = 0
    bytes = createObject("roByteArray")
    bytes.readFile("pkg:/official.gif")
    if mode = "budget-valid-2001" or mode = "budget-valid-2999"
        state.official = true
        expectedMs = 2001
        if mode = "budget-valid-2999" then expectedMs = 2999
        runMovie(fs, bytes, mode, invalid, mode, expectedMs)
        check(state.decodeIndex = 15, "extended budget completes all fifteen frames")
        check(fixtureRequestTime() = 7999, "extended budget stays inside original eight-second request")
        return
    end if
    state.official = false
    path = "tmp:/stitch-emote-" + mode + "/emote.gif"
    fs.createDirectory(chatAnimationDirectory(path))
    bytes.writeFile(path)
    result = invalid
    errorMessage = ""
    try
        result = chatConvertGif(fs, bytes, path, { totalMilliseconds: fixtureRequestTime })
    catch e
        errorMessage = e.message
    end try
    if mode = "budget-exact-3000" then check(result = invalid and errorMessage = "GIF conversion deadline", "3000 ms conversion boundary rejects")
    if mode = "budget-request-8000" then check(result = invalid and errorMessage = "GIF conversion deadline", "8000 ms request boundary rejects even below conversion cap")
    if mode = "budget-cancel" then check(result = invalid and errorMessage = "GIF conversion cancelled", "cancellation remains active below 3000 ms")
    check(state.decodeIndex = 2, "policy guard stops at injected second-decode checkpoint")
    check(state.drawQueue.count() = 0 and state.pngExports = 0, "policy rejection leaves no pending draws or PNG export")
    check(directoryBytes(fs, chatAnimationDirectory(path)) <= 3145728, "policy probe preserves pending file reservation")
    check(deleteChatAnimationFile(fs, path) and not fs.exists(chatAnimationDirectory(path)), "policy rejection cleans only owned files")
end sub

sub runMovie(fs as object, bytes as object, name as string, expected as dynamic, mode = "valid" as string, expectedConversionMs = -1 as integer)
    state = getGlobalAA()
    state.mode = mode
    state.checkpoints = 0
    state.decodeIndex = 0
    path = "tmp:/stitch-emote-pixels-" + name + "/emote.gif"
    fs.createDirectory(chatAnimationDirectory(path))
    bytes.writeFile(path)
    info = chatConvertGif(fs, bytes, path, { totalMilliseconds: fixtureRequestTime })
    check(info <> invalid, "complete movie admitted: " + name)
    if info = invalid then return
    if expectedConversionMs >= 0 then check(info.conversionMs = expectedConversionMs and info.conversionMs > 2000 and info.conversionMs < 3000, "valid whole movie completes between two and three seconds")
    check(state.drawQueue.count() = 0 and state.maxQueued <= 3, "bounded draw queue fully realized before export: " + name)
    if name = "official" then check(state.finishCalls = 15, "whole official movie uses fifteen fences for fifteen exact frames")
    normalFences = info.frames
    for each frame in chatAdmitGif(bytes).images
        if frame.disposal = 2 then normalFences += 2
    end for
    check(state.finishCalls = normalFences, "normal disposal fence counts unchanged: " + name)
    check(info.renderer = "gif-atlas" and info.sourceBytes = bytes.count() and info.bytes > 0 and info.bytes <= 525312, "separate source and retained byte admission: " + name)
    check(not fs.exists(path) and not fs.exists(chatAnimationDirectory(path) + "/frame.gif"), "input and wrapper removed before cache publication: " + name)
    ' Fresh drawn GetByteArray is deliberately never used. Export, file reload,
    ' then read decoded PNG pixels, matching the target's required validation path.
    atlas = createObject("roBitmap", info.renderPath)
    for index = 0 to info.frames - 1
        rgba = atlas.getByteArray((index mod info.columns) * info.loadWidth, int(index / info.columns) * info.loadHeight, info.loadWidth, info.loadHeight)
        normalize(rgba)
        if expected = invalid
            check(chatGifSha(rgba) = state.golden.frames[index].rgba64Sha256, "Pillow exact pixel-center tile " + index.toStr())
            previous = 0
            if index > 0 then previous = info.frameEnds[index - 1]
            check(info.frameEnds[index] - previous = state.golden.frames[index].delayMs, "exact official delay " + index.toStr())
        else
            check(lcase(rgba.toHexString()) = expected[index], "hand-authored composition/scale pixels " + name + ":" + index.toStr())
            if lcase(rgba.toHexString()) <> expected[index] then print "PIXELS "; name; index; " actual="; rgba.toHexString().left(128); " expected="; expected[index].left(128)
        end if
    end for
    if info.frames < info.columns * int(info.atlasHeight / info.loadHeight)
        rgba = atlas.getByteArray((info.frames mod info.columns) * info.loadWidth, int(info.frames / info.columns) * info.loadHeight, info.loadWidth, info.loadHeight)
        check(rgba.toHexString() = string(rgba.count() * 2, "0"), "unused atlas tile is transparent black: " + name)
    end if
    atlas = invalid
    check(deleteChatAnimationFile(fs, path) and not fs.exists(chatAnimationDirectory(path)), "atlas deleted through sentinel ownership: " + name)
end sub

function directoryBytes(fs as object, directory as string) as integer
    total = 0
    for each name in ["emote.gif", "frame.gif", "atlas.png"]
        stat = fs.stat(directory + "/" + name)
        if stat <> invalid
            if GetInterface(stat.size, "ifInt") <> invalid then total += stat.size
        end if
    end for
    return total
end function

sub normalize(bytes as object)
    for offset = 0 to bytes.count() - 1 step 4
        if bytes[offset + 3] = 0
            bytes[offset] = 0
            bytes[offset + 1] = 0
            bytes[offset + 2] = 0
        end if
    end for
end sub

' Native still GIF and GPU scaling are offline boundaries. The engine's real
' still decoder is checked against independent Pillow full-frame hashes here.
function fixtureDecode(path as string) as dynamic
    state = getGlobalAA()
    if state.mode = "decode-invalid" then return invalid
    if state.mode = "decode-size" then return createObject("roBitmap", { width: 1, height: 1, AlphaEnable: false })
    if state.official
        wrapper = createObject("roByteArray")
        wrapper.readFile(path)
        golden = state.golden.frames[state.decodeIndex]
        check(wrapper.count() = golden.wrapperBytes and chatGifSha(wrapper) = golden.wrapperSha256, "exact independent still wrapper bytes " + state.decodeIndex.toStr())
    end if
    bitmap = createObject("roBitmap", path)
    if state.official and bitmap <> invalid
        rgba = bitmap.getByteArray(0, 0, bitmap.getWidth(), bitmap.getHeight())
        normalize(rgba)
        check(chatGifSha(rgba) = golden.decodedSha256, "Pillow full native-boundary decode " + state.decodeIndex.toStr())
    end if
    state.decodeIndex++
    return fixtureWrap(bitmap)
end function

function fixtureGifClock() as object
    return { totalMilliseconds: fixtureGifTime, mark: fixtureNothing }
end function
function fixtureGifTime() as integer
    state = getGlobalAA()
    if state.decodeIndex >= 2
        if state.mode = "budget-valid-2001" then return 2001
        if state.mode = "budget-valid-2999" or state.mode = "budget-request-8000" or state.mode = "budget-cancel" then return 2999
        if state.mode = "budget-exact-3000" then return 3000
    end if
    if state.mode = "disposal-deadline" and state.disposalCheckpoint then return 3000
    if state.mode = "conversion-deadline" and state.decodeIndex >= 2 then return 3000
    if state.mode = "finish-deadline" and state.expiredAtFinish then return 3000
    return 25
end function
function fixtureRequestTime() as integer
    state = getGlobalAA()
    if state.decodeIndex >= 2
        if state.mode = "budget-request-8000" then return 8000
        if state.mode.left(7) = "budget-" then return 7999
    end if
    if getGlobalAA().mode = "disposal-request-deadline" and getGlobalAA().disposalCheckpoint then return 8000
    if getGlobalAA().mode = "request-deadline" and getGlobalAA().decodeIndex >= 1 then return 8000
    if getGlobalAA().mode = "finish-request-deadline" and getGlobalAA().expiredAtFinish then return 8000
    return 0
end function
sub fixtureNothing()
end sub
sub fixtureCheckpoint()
    state = getGlobalAA()
    state.checkpoints++
    if state.mode = "cancel-during" and state.decodeIndex = 2 then m.top.stopRequested = true
    if state.mode = "cancel-at-finish" and state.expiredAtFinish then m.top.stopRequested = true
    if state.mode = "disposal-cancel" and state.disposalCheckpoint then m.top.stopRequested = true
    if state.mode = "budget-cancel" and state.decodeIndex >= 2 then m.top.stopRequested = true
end sub

function fixtureWrite(bytes as object, path as string) as boolean
    if getGlobalAA().mode = "wrapper-write" then return false
    return bytes.writeFile(path)
end function
function fixtureAppend(bytes as object, path as string, start as integer, size as integer) as boolean
    if getGlobalAA().mode = "wrapper-append" then return false
    return bytes.appendFile(path, start, size)
end function
function fixturePngWrite(bytes as object, path as string) as boolean
    state = getGlobalAA()
    if state.mode = "png-write" then return false
    result = bytes.writeFile(path)
    if state.mode = "cancel-after-png" then m.top.stopRequested = true
    if state.mode = "png-corrupt"
        broken = createObject("roByteArray")
        broken.fromAsciiString(string(bytes.count(), "x"))
        broken.writeFile(path)
    end if
    return result
end function
function fixturePngRead(bytes as object, path as string, start as integer, size as integer) as boolean
    if getGlobalAA().mode = "png-read" then return false
    return bytes.readFile(path, start, size)
end function
function fixtureAtlasStat(fs as object, path as string) as dynamic
    mode = getGlobalAA().mode
    if (mode = "wrapper-stat" and path.right(9) = "frame.gif") or (mode = "png-stat" and path.right(9) = "atlas.png") then return { size: "not numeric" }
    return fs.stat(path)
end function
function fixtureDelete(fs as object, path as string) as boolean
    mode = getGlobalAA().mode
    if mode = "delete-source" and path.right(9) = "emote.gif" then return false
    if mode = "delete-wrapper" and path.right(9) = "frame.gif" then return false
    return fs.delete(path)
end function
sub check(ok as boolean, label as string)
    m.checks++
    if not ok
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
