' Structural admission only, never LZW/pixel decoding. GIF89a block grammar:
' www.w3.org/Graphics/GIF/spec-gif89a.txt. Native decoding remains fallible.
function chatGifLE16(bytes as object, offset as integer) as integer
    return bytes[offset] + bytes[offset + 1] * 256
end function

' The shared budget bounds tiny-block attacks across image/comment blocks.
' Payloads are skipped, not copied or decoded; every length is checked first.
function chatGifSubBlocks(bytes as object, offset as integer, scan as object) as integer
    limit = bytes.count()
    while offset < limit
        scan.blocks++
        if scan.blocks > 8192 then return -1
        size = bytes[offset]
        offset++
        if size = 0 then return offset
        if size > limit - offset then return -1
        offset += size
    end while
    return -1
end function

function chatAdmitGif(bytes as dynamic) as dynamic
    if type(bytes) <> "roByteArray" then return invalid
    limit = bytes.count()
    if limit < 14 or limit > 1048576 then return invalid
    header = ""
    for index = 0 to 5
        header += chr(bytes[index])
    end for
    if header <> "GIF89a" and header <> "GIF87a" then return invalid
    width = chatGifLE16(bytes, 6)
    height = chatGifLE16(bytes, 8)
    if width < 1 or height < 1 or width > 512 or height > 512 then return invalid
    packed = bytes[10]
    globalColors = 0
    offset = 13
    if (packed and &h80) <> 0
        globalColors = 2 ^ ((packed and 7) + 1)
        if bytes[11] >= globalColors then return invalid
        offset += globalColors * 3
        if offset >= limit then return invalid
    end if
    frames = 0
    images = []
    loopCount = -1
    duration = 0
    pendingControl = false
    transparent = false
    transparentIndex = 0
    loopSeen = false
    blocks = 0
    scan = { blocks: 0 }
    while offset < limit
        blocks++
        if blocks > 1024 then return invalid
        marker = bytes[offset]
        offset++
        if marker = &h3b
            if offset <> limit or pendingControl or frames < 2 or duration < 100 then return invalid
            scale = 1#
            if width > 64 then scale = 64# / width
            if height * scale > 64 then scale = 64# / height
            loadWidth = int(width * scale)
            loadHeight = int(height * scale)
            if loadWidth < 1 then loadWidth = 1
            if loadHeight < 1 then loadHeight = 1
            return { format: "gif", width: width, height: height, loadWidth: loadWidth, loadHeight: loadHeight, frames: frames, durationMs: duration, bytes: limit, images: images, globalColors: globalColors, backgroundIndex: bytes[11], loopCount: loopCount }
        else if marker = &h21
            if header <> "GIF89a" or offset >= limit then return invalid
            label = bytes[offset]
            offset++
            if label = &hf9
                if pendingControl or limit - offset < 6 then return invalid
                if bytes[offset] <> 4 or bytes[offset + 5] <> 0 then return invalid
                flags = bytes[offset + 1]
                ' Reserved bits, undefined disposal and input-driven waits are unsupported.
                if (flags and &he2) <> 0 or int(flags / 4) > 3 then return invalid
                delay = chatGifLE16(bytes, offset + 2) * 10
                if delay < 20 then return invalid
                duration += delay
                if duration > 20000 then return invalid
                transparent = (flags and 1) <> 0
                transparentIndex = bytes[offset + 4]
                disposal = int(flags / 4)
                pendingControl = true
                offset += 6
            else if label = &hfe
                offset = chatGifSubBlocks(bytes, offset, scan)
                if offset < 0 then return invalid
            else if label = &hff
                if loopSeen or limit - offset < 17 then return invalid
                if bytes[offset] <> 11 then return invalid
                identifier = ""
                for index = 1 to 11
                    identifier += chr(bytes[offset + index])
                end for
                if identifier <> "NETSCAPE2.0" and identifier <> "ANIMEXTS1.0" then return invalid
                if bytes[offset + 12] <> 3 or bytes[offset + 13] <> 1 or bytes[offset + 16] <> 0 then return invalid
                loopSeen = true
                loopCount = chatGifLE16(bytes, offset + 14)
                offset += 17
            else
                ' Plain-text rendering and unknown extension grammars are unsupported.
                return invalid
            end if
        else if marker = &h2c
            if not pendingControl or limit - offset < 9 then return invalid
            x = chatGifLE16(bytes, offset)
            y = chatGifLE16(bytes, offset + 2)
            frameWidth = chatGifLE16(bytes, offset + 4)
            frameHeight = chatGifLE16(bytes, offset + 6)
            if frameWidth < 1 or frameHeight < 1 or x + frameWidth > width or y + frameHeight > height then return invalid
            packed = bytes[offset + 8]
            if (packed and &h18) <> 0 then return invalid
            offset += 9
            colors = globalColors
            paletteOffset = 13
            if (packed and &h80) <> 0
                colors = 2 ^ ((packed and 7) + 1)
                paletteOffset = offset
                offset += colors * 3
            end if
            if colors = 0 or offset >= limit then return invalid
            if transparent and transparentIndex >= colors then return invalid
            ' The code-size byte is bounded without decoding its LZW stream.
            if bytes[offset] < 2 or bytes[offset] > 8 then return invalid
            dataStart = offset
            offset++
            if offset >= limit then return invalid
            if bytes[offset] = 0 then return invalid
            offset = chatGifSubBlocks(bytes, offset, scan)
            if offset < 0 then return invalid
            frames++
            ' Count complete source canvases, even for small delta rectangles.
            if frames > 128 or width * height * frames > 4194304 then return invalid
            images.push({ x: x, y: y, width: frameWidth, height: frameHeight, interlaced: (packed and &h40) <> 0, colors: colors, paletteOffset: paletteOffset, dataStart: dataStart, dataLength: offset - dataStart, transparent: transparent, transparentIndex: transparentIndex, disposal: disposal, delayMs: delay, endMs: duration })
            pendingControl = false
        else
            return invalid
        end if
    end while
    return invalid
end function
