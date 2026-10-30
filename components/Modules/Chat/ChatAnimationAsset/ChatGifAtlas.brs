' Task-only native still decode/composition. Compressed blocks are never decoded
' in BrightScript. All source bitmaps are immutable after use in another draw.
function chatConvertGif(fs as object, bytes as object, path as string, requestClock as object) as dynamic
    m.gifClock = createObject("roTimespan")
    m.gifPollClock = createObject("roTimespan")
    m.gifRequestClock = requestClock
    m.gifCancelled = m.top.stopRequested
    chatGifCheck()
    info = chatAdmitGif(bytes)
    chatGifCheck()
    if info = invalid then return invalid
    if info.frames > 32 then return invalid
    columns = 4
    if info.frames > 16 then columns = 8
    rows = int((info.frames + columns - 1) / columns)
    atlasWidth = columns * info.loadWidth
    atlasHeight = rows * info.loadHeight
    if atlasWidth * atlasHeight > 131072 then return invalid
    directory = chatAnimationDirectory(path)
    framePath = directory + "/frame.gif"
    renderPath = directory + "/atlas.png"
    atlas = chatGifBitmap(atlasWidth, atlasHeight)
    canvas = invalid
    ends = []
    for each frame in info.images
        chatGifCheck()
        if not chatGifWriteStill(fs, bytes, frame, framePath) then return invalid
        chatGifCheck()
        decoded = createObject("roBitmap", framePath)
        chatGifCheck()
        if not chatGifBitmapSize(decoded, frame.width, frame.height) then return invalid
        shown = chatGifBitmap(info.width, info.height)
        index = ends.count()
        drawn = true
        try
            if canvas = invalid
                shown.clear(chatGifBackground(bytes, info, info.images[0].transparent))
            else
                drawn = shown.drawObject(0, 0, canvas)
            end if
            if drawn
                shown.setAlphaEnable(true)
                drawn = shown.drawObject(frame.x, frame.y, decoded)
            end if
            ' Queue the dependent scale before one fence; keep every source alive.
            if drawn then drawn = atlas.drawScaledObject((index mod columns) * info.loadWidth, int(index / columns) * info.loadHeight, info.loadWidth / info.width, info.loadHeight / info.height, shown)
        catch e
            atlas.finish()
            throw e
        end try
        ' Finish completes all queued draws, including the source composition.
        atlas.finish()
        decoded = invalid
        chatGifCheck()
        if not drawn then return invalid
        if frame.disposal = 2
            ' Never clear a source: disposal is applied on a fresh destination.
            canvas = invalid
            disposed = chatGifBitmap(info.width, info.height)
            try
                drawn = disposed.drawObject(0, 0, shown)
                if drawn
                    cleared = chatGifBitmap(frame.width, frame.height)
                    cleared.clear(chatGifBackground(bytes, info, frame.transparent))
                    cleared.finish()
                    drawn = disposed.drawObject(frame.x, frame.y, cleared)
                end if
                disposed.finish()
            catch e
                atlas.finish()
                throw e
            end try
            if not drawn then return invalid
            cleared = invalid
            canvas = disposed
            disposed = invalid
        else if frame.disposal <> 3
            canvas = shown
        end if
        ' Disposal 3 retains the immutable pre-frame canvas (invalid = initial).
        shown = invalid
        ends.push(frame.endMs)
        chatGifCheck()
    end for
    canvas = invalid
    png = atlas.getPng(0, 0, atlasWidth, atlasHeight)
    atlas = invalid
    chatGifCheck()
    if not chatGifPng(png, atlasWidth, atlasHeight) then return invalid
    sha = chatGifSha(png)
    if not png.writeFile(renderPath) then return invalid
    chatGifCheck()
    if not chatGifFileSize(fs, renderPath, png.count()) then return invalid
    stored = createObject("roByteArray")
    if not stored.readFile(renderPath, 0, 525313) then return invalid
    if stored.count() <> png.count() then return invalid
    if chatGifSha(stored) <> sha then return invalid
    sourceSha = chatGifSha(bytes)
    chatGifCheck()
    ' A cache entry retains only its atlas. Failure retains the whole reservation.
    fs.delete(path)
    fs.delete(framePath)
    if fs.exists(path) or fs.exists(framePath) then return invalid
    chatGifCheck()
    return { format: "gif", renderer: "gif-atlas", width: info.width, height: info.height, loadWidth: info.loadWidth, loadHeight: info.loadHeight, frames: info.frames, durationMs: info.durationMs, loopCount: info.loopCount, frameEnds: ends, columns: columns, atlasWidth: atlasWidth, atlasHeight: atlasHeight, renderPath: renderPath, sourceBytes: bytes.count(), bytes: png.count(), sourceSha256: sourceSha, atlasSha256: sha, conversionMs: m.gifClock.totalMilliseconds() }
end function

' Native calls are synchronous: checks bound acceptance, not interruption time.
sub chatGifCheck()
    if m.gifPollClock.totalMilliseconds() >= 25
        m.gifCancelled = m.top.stopRequested
        m.gifPollClock.mark()
    end if
    if m.gifCancelled then throw "GIF conversion cancelled"
    if m.gifClock.totalMilliseconds() >= 3000 or m.gifRequestClock.totalMilliseconds() >= 8000 then throw "GIF conversion deadline"
end sub

function chatGifBitmap(width as integer, height as integer) as object
    chatGifCheck()
    bitmap = createObject("roBitmap", { width: width, height: height, AlphaEnable: false })
    chatGifCheck()
    if not chatGifBitmapSize(bitmap, width, height) then throw "GIF bitmap unavailable"
    return bitmap
end function

function chatGifBitmapSize(bitmap as dynamic, width as integer, height as integer) as boolean
    if bitmap = invalid then return false
    return bitmap.getWidth() = width and bitmap.getHeight() = height
end function

' Transparent frames restore transparent background; otherwise use the logical
' GCT background (or transparent if there is no GCT).
function chatGifBackground(bytes as object, info as object, transparent as boolean) as integer
    if transparent or info.globalColors = 0 then return 0
    offset = 13 + info.backgroundIndex * 3
    red = bytes[offset]
    if red > 127 then red -= 256
    return red * 16777216 + bytes[offset + 1] * 65536 + bytes[offset + 2] * 256 + 255
end function

' Prefix is <= 799 bytes. Palette and compressed data are native ranged writes;
' no interpreted copy of the up-to-1-MiB compressed stream.
function chatGifWriteStill(fs as object, bytes as object, frame as object, path as string) as boolean
    prefix = createObject("roByteArray")
    prefix.fromAsciiString("GIF89a")
    packed = 128
    colors = 2
    while colors < frame.colors
        packed++
        colors *= 2
    end while
    for each value in [frame.width mod 256, int(frame.width / 256), frame.height mod 256, int(frame.height / 256), packed, 0, 0]
        prefix.push(value)
    end for
    flags = 0
    if frame.transparent then flags = 1
    control = createObject("roByteArray")
    for each value in [&h21, &hf9, 4, flags, 0, 0, frame.transparentIndex, 0, &h2c, 0, 0, 0, 0, frame.width mod 256, int(frame.width / 256), frame.height mod 256, int(frame.height / 256), 0]
        control.push(value)
    end for
    if frame.interlaced then control[17] = &h40
    trailer = createObject("roByteArray")
    trailer.push(&h3b)
    chatGifCheck()
    if not prefix.writeFile(path) then return false
    if not bytes.appendFile(path, frame.paletteOffset, frame.colors * 3) then return false
    if not control.appendFile(path) then return false
    if not bytes.appendFile(path, frame.dataStart, frame.dataLength) then return false
    if not trailer.appendFile(path) then return false
    chatGifCheck()
    return chatGifFileSize(fs, path, 32 + frame.colors * 3 + frame.dataLength)
end function

function chatGifFileSize(fs as object, path as string, size as integer) as boolean
    stat = fs.stat(path)
    if stat = invalid then return false
    if GetInterface(stat.size, "ifInt") = invalid and GetInterface(stat.size, "ifLongInt") = invalid then return false
    return stat.size = size
end function

function chatGifSha(bytes as object) as string
    chatGifCheck()
    digest = createObject("roEVPDigest")
    if digest.setup("sha256") <> 0 then throw "GIF digest unavailable"
    value = lcase(digest.process(bytes))
    chatGifCheck()
    if value.len() <> 64 then throw "GIF digest failed"
    return value
end function

' Native PNG output must fit the reserved file budget and the exact atlas.
function chatGifPng(bytes as dynamic, width as integer, height as integer) as boolean
    if type(bytes) <> "roByteArray" then return false
    if bytes.count() < 57 or bytes.count() > 525312 then return false
    if bytes[0] <> 137 or bytes[1] <> 80 or bytes[2] <> 78 or bytes[3] <> 71 or bytes[4] <> 13 or bytes[5] <> 10 or bytes[6] <> 26 or bytes[7] <> 10 then return false
    if bytes[8] <> 0 or bytes[9] <> 0 or bytes[10] <> 0 or bytes[11] <> 13 then return false
    if bytes[12] <> 73 or bytes[13] <> 72 or bytes[14] <> 68 or bytes[15] <> 82 then return false
    if bytes[16] <> 0 or bytes[17] <> 0 or bytes[18] * 256 + bytes[19] <> width then return false
    if bytes[20] <> 0 or bytes[21] <> 0 or bytes[22] * 256 + bytes[23] <> height then return false
    if bytes[24] <> 8 or bytes[25] <> 6 or bytes[26] <> 0 or bytes[27] <> 0 or bytes[28] <> 0 then return false
    offset = 8
    chunks = 0
    idatSeen = false
    while offset <= bytes.count() - 12
        chatGifCheck()
        chunks++
        if chunks > 1024 or bytes[offset] <> 0 or bytes[offset + 1] > 8 then return false
        length = bytes[offset + 1] * 65536 + bytes[offset + 2] * 256 + bytes[offset + 3]
        if length > bytes.count() - offset - 12 then return false
        crcOffset = offset + 8 + length
        crc = bytes.getCRC32(offset + 4, length + 4)
        red = bytes[crcOffset]
        if red > 127 then red -= 256
        expected = red * 16777216 + bytes[crcOffset + 1] * 65536 + bytes[crcOffset + 2] * 256 + bytes[crcOffset + 3]
        if crc <> expected then return false
        if bytes[offset + 4] = 73 and bytes[offset + 5] = 68 and bytes[offset + 6] = 65 and bytes[offset + 7] = 84 then idatSeen = true
        if bytes[offset + 4] = 73 and bytes[offset + 5] = 69 and bytes[offset + 6] = 78 and bytes[offset + 7] = 68 then return idatSeen and length = 0 and crcOffset + 4 = bytes.count()
        offset = crcOffset + 4
    end while
    return false
end function
