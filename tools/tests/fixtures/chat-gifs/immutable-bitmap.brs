' Model queued Draw2D work and OS 16 source immutability, forwarding the actual
' pixels to engine bitmaps at Finish. This is a contract test, not native timing.
sub fixtureBeginConversion()
    state = getGlobalAA()
    if state.drawQueue <> invalid
        if state.drawQueue.count() <> 0 then throw "unfinished draws survived conversion"
    end if
    state.drawQueue = []
    state.finishCalls = 0
    state.maxQueued = 0
    state.pngExports = 0
    state.expiredAtFinish = false
    state.disposalCheckpoint = false
    state.disposalQueueAtCheckpoint = 0
    state.disposalFenceAtCheckpoint = 0
    state.disposalRectCheckpoint = false
end sub
function fixtureBitmap(properties as dynamic) as object
    if getGlobalAA().disposalCheckpoint and getGlobalAA().mode = "disposal-allocation" then throw "scripted cleared bitmap allocation exception"
    return fixtureWrap(createObject("roBitmap", properties), "canvas")
end function
function fixtureWrap(bitmap as object, kind = "decoded" as string) as object
    state = getGlobalAA()
    if state.bitmapSerial = invalid then state.bitmapSerial = 0
    if state.frozenIds = invalid then state.frozenIds = ""
    state.bitmapSerial++
    return { bitmap: bitmap, id: state.bitmapSerial.toStr(), kind: kind, getWidth: fixtureWidth, getHeight: fixtureHeight, clear: fixtureClear, drawObject: fixtureCopy, drawScaledObject: fixtureScale, setAlphaEnable: fixtureAlpha, finish: fixtureFinish, getPng: fixtureGetPng }
end function
sub fixtureWritable(id as string)
    if getGlobalAA().frozenIds.instr("|" + id + "|") >= 0 then throw "source bitmap mutated after draw"
end sub
sub fixtureFrozen(id as string)
    state = getGlobalAA()
    state.frozenIds += "|" + id + "|"
end sub
function fixtureWidth() as integer
    return m.bitmap.getWidth()
end function
function fixtureHeight() as integer
    return m.bitmap.getHeight()
end function
sub fixtureClear(color as integer)
    fixtureWritable(m.id)
    fixtureQueue({ kind: "clear", destination: m.bitmap, destinationId: m.id, color: color })
end sub
function fixtureCopy(x as integer, y as integer, source as object) as boolean
    fixtureWritable(m.id)
    if getGlobalAA().mode = "base-copy-failed" and source.kind = "canvas" and getGlobalAA().decodeIndex = 2 then return false
    fixtureQueue({ kind: "copy", destination: m.bitmap, destinationId: m.id, alpha: m.bitmap.getAlphaEnable(), source: source.bitmap, sourceId: source.id, x: x, y: y })
    fixtureFrozen(source.id)
    state = getGlobalAA()
    if state.decodeIndex = 3 and state.finishCalls = 3
        state.disposalCheckpoint = true
        state.disposalQueueAtCheckpoint = state.drawQueue.count()
        state.disposalFenceAtCheckpoint = state.finishCalls
        if state.mode = "disposal-base-false" then return false
    else if state.disposalCheckpoint and state.finishCalls = 4 and state.mode = "disposal-rect-false"
        state.disposalRectCheckpoint = true
        return false
    end if
    return true
end function
function fixtureScale(x as integer, y as integer, scaleX as float, scaleY as float, source as object) as boolean
    fixtureWritable(m.id)
    if getGlobalAA().mode = "scale-failed" then return false
    if getGlobalAA().mode = "scale-throw" then throw "scripted native scale exception"
    fixtureQueue({ kind: "scale", destination: m.bitmap, destinationId: m.id, alpha: m.bitmap.getAlphaEnable(), source: source.bitmap, sourceId: source.id, x: x, y: y, scaleX: scaleX, scaleY: scaleY })
    fixtureFrozen(source.id)
    return true
end function
sub fixtureAlpha(enabled as boolean)
    m.bitmap.setAlphaEnable(enabled)
end sub
sub fixtureFinish()
    state = getGlobalAA()
    queue = state.drawQueue
    for each operation in queue
        if operation.kind = "clear"
            operation.destination.clear(operation.color)
        else
            operation.destination.setAlphaEnable(operation.alpha)
            if operation.kind = "copy"
                drawn = operation.destination.drawObject(operation.x, operation.y, operation.source)
            else
                drawn = operation.destination.drawScaledObject(operation.x, operation.y, operation.scaleX, operation.scaleY, operation.source)
            end if
            if not drawn then throw "engine draw failed while realizing queue"
        end if
    end for
    m.bitmap.finish()
    state.drawQueue = []
    state.finishCalls++
    state.expiredAtFinish = true
end sub
function fixtureGetPng(x as integer, y as integer, width as integer, height as integer) as object
    state = getGlobalAA()
    if state.drawQueue.count() <> 0 then throw "PNG read before Finish"
    state.pngExports++
    return m.bitmap.getPng(x, y, width, height)
end function

sub fixtureQueue(operation as object)
    state = getGlobalAA()
    queue = state.drawQueue
    queue.push(operation)
    state.drawQueue = queue
    if queue.count() > state.maxQueued then state.maxQueued = queue.count()
end sub

' Explicit releases in the actual converter are instrumented at this boundary.
' Holding bitmap refs in the test's pending queue must not hide early releases.
function fixtureReleaseBitmap(bitmap as dynamic) as dynamic
    if bitmap = invalid then return invalid
    for each operation in getGlobalAA().drawQueue
        if operation.sourceId = bitmap.id or operation.destinationId = bitmap.id then throw "bitmap released before Finish"
    end for
    return invalid
end function
function fixtureReplaceCanvas(previous as dynamic, nextCanvas as object) as object
    fixtureReleaseBitmap(previous)
    return nextCanvas
end function
