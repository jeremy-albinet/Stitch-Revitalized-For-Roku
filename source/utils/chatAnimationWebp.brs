' Admission only, not a decoder. See developers.google.com/speed/webp/docs/riff_container.
' Integer fields use doubles until bounded, so hostile uint32 lengths cannot wrap.
function chatWebpLE(bytes as object, offset as integer, length as integer) as double
    value = 0#
    factor = 1#
    for index = 0 to length - 1
        value += bytes[offset + index] * factor
        factor *= 256
    end for
    return value
end function

function chatWebpTag(bytes as object, offset as integer) as string
    return chr(bytes[offset]) + chr(bytes[offset + 1]) + chr(bytes[offset + 2]) + chr(bytes[offset + 3])
end function

function chatWebpChunkEnd(bytes as object, offset as integer, limit as integer) as integer
    if offset < 0 or offset + 8 > limit then return -1
    size = chatWebpLE(bytes, offset + 4, 4)
    if size > limit - offset - 8 then return -1
    finish = offset + 8 + int(size)
    if (size mod 2) <> 0
        if finish >= limit then return -1
        if bytes[finish] <> 0 then return -1
        finish++
    end if
    return finish
end function

function chatWebpImageHeader(bytes as object, offset as integer, length as integer, tag as string, width as integer, height as integer) as boolean
    if tag = "VP8 "
        if length < 10 then return false
        if (bytes[offset] and 1) <> 0 then return false
        if bytes[offset + 3] <> &h9d or bytes[offset + 4] <> 1 or bytes[offset + 5] <> &h2a then return false
        return (chatWebpLE(bytes, offset + 6, 2) mod 16384) = width and (chatWebpLE(bytes, offset + 8, 2) mod 16384) = height
    end if
    if tag = "VP8L"
        if length < 5 then return false
        if bytes[offset] <> &h2f then return false
        bits = chatWebpLE(bytes, offset + 1, 4)
        if int(bits / 536870912#) <> 0 then return false
        return (bits mod 16384) + 1 = width and (int(bits / 16384) mod 16384) + 1 = height
    end if
    return false
end function

function chatAdmitWebp(bytes as dynamic) as dynamic
    if type(bytes) <> "roByteArray" then return invalid
    limit = bytes.count()
    if limit < 44 or limit > 1048576 then return invalid
    if chatWebpTag(bytes, 0) <> "RIFF" or chatWebpTag(bytes, 8) <> "WEBP" then return invalid
    if chatWebpLE(bytes, 4, 4) <> limit - 8 then return invalid
    offset = 12
    chunks = 0
    width = 0
    height = 0
    frames = 0
    duration = 0
    hasAnimation = false
    while offset < limit
        chunks++
        if chunks > 1024 then return invalid
        finish = chatWebpChunkEnd(bytes, offset, limit)
        if finish < 0 then return invalid
        tag = chatWebpTag(bytes, offset)
        size = int(chatWebpLE(bytes, offset + 4, 4))
        body = offset + 8
        if offset = 12 and tag <> "VP8X" then return invalid
        if tag = "VP8X"
            if offset <> 12 or size <> 10 then return invalid
            if (bytes[body] and &hc1) <> 0 or (bytes[body] and 2) = 0 then return invalid
            if chatWebpLE(bytes, body + 1, 3) <> 0 then return invalid
            width = int(chatWebpLE(bytes, body + 4, 3)) + 1
            height = int(chatWebpLE(bytes, body + 7, 3)) + 1
            if width > 128 or height > 128 then return invalid
        else if tag = "ANIM"
            if hasAnimation or frames <> 0 or size <> 6 then return invalid
            hasAnimation = true
        else if tag = "ANMF"
            if not hasAnimation or size < 16 then return invalid
            x = chatWebpLE(bytes, body, 3) * 2
            y = chatWebpLE(bytes, body + 3, 3) * 2
            frameWidth = int(chatWebpLE(bytes, body + 6, 3)) + 1
            frameHeight = int(chatWebpLE(bytes, body + 9, 3)) + 1
            delay = chatWebpLE(bytes, body + 12, 3)
            if x + frameWidth > width or y + frameHeight > height or bytes[body + 15] > 3 then return invalid
            ' Very short delays have implementation-dependent playback behavior.
            if delay < 10 then return invalid
            duration += delay
            frames++
            if frames > 512 or duration > 20000 or width * height * frames > 1048576 then return invalid
            nested = body + 16
            imageSeen = false
            alphaSeen = false
            frameChunks = 0
            while nested < body + size
                frameChunks++
                if frameChunks > 4 then return invalid
                nestedEnd = chatWebpChunkEnd(bytes, nested, body + size)
                if nestedEnd < 0 then return invalid
                nestedTag = chatWebpTag(bytes, nested)
                nestedSize = int(chatWebpLE(bytes, nested + 4, 4))
                if nestedTag = "VP8 " or nestedTag = "VP8L"
                    if imageSeen or (alphaSeen and nestedTag = "VP8L") then return invalid
                    if not chatWebpImageHeader(bytes, nested + 8, nestedSize, nestedTag, frameWidth, frameHeight) then return invalid
                    imageSeen = true
                else if nestedTag = "ALPH"
                    if alphaSeen or imageSeen or nestedSize < 1 then return invalid
                    alphaSeen = true
                else
                    return invalid
                end if
                nested = nestedEnd
            end while
            if not imageSeen then return invalid
        else if tag = "VP8 " or tag = "VP8L" or tag = "ALPH"
            return invalid
        end if
        offset = finish
    end while
    if frames < 2 then return invalid
    scale = 1.0
    if width > 64 then scale = 64.0 / width
    if height * scale > 64 then scale = 64.0 / height
    loadWidth = int(width * scale)
    loadHeight = int(height * scale)
    if loadWidth < 1 then loadWidth = 1
    if loadHeight < 1 then loadHeight = 1
    return { width: width, height: height, loadWidth: loadWidth, loadHeight: loadHeight, frames: frames, durationMs: duration, bytes: limit }
end function
