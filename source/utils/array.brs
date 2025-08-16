' MIT License

' Copyright (c) 2020 Julio Alves
' https://github.com/juliomalves/roku-libs/tree/master
' Permission is hereby granted, free of charge, to any person obtaining a copy
' of this software and associated documentation files (the "Software"), to deal
' in the Software without restriction, including without limitation the rights
' to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
' copies of the Software, and to permit persons to whom the Software is
' furnished to do so, subject to the following conditions:

' The above copyright notice and this permission notice shall be included in all
' copies or substantial portions of the Software.

' THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
' IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
' FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
' AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
' LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
' OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
' SOFTWARE.

'
'   array.brs
'
'
function ArrayUtil() as object

    util = {

        isArray: function(arr) as boolean
            return type(arr) = "roArray"
        end function,

        contains: function(arr as object, element as dynamic) as boolean
            return m.indexOf(arr, element) >= 0
        end function,

        indexOf: function(arr as object, element as dynamic) as integer
            if not m.isArray(arr) then return -1

            size = arr.count()

            if size = 0 then return -1

            for i = 0 to size - 1
                if arr[i] = element then return i
            end for

            return -1
        end function,

        lastIndexOf: function(arr as object, element as dynamic) as integer
            if not m.isArray(arr) then return -1

            size = arr.count()

            if size = 0 then return -1

            for i = size - 1 to 0 step -1
                if arr[i] = element then return i
            end for

            return -1
        end function,

        slice: function(arr as object, fromIndex = 0 as integer, toIndex = invalid as dynamic)
            if not m.isArray(arr) then return invalid

            size = arr.count()
            lastIndex = size - 1
            slicedArr = []

            if fromIndex < 0 then fromIndex = size + fromIndex
            if toIndex = invalid then toIndex = lastIndex
            if toIndex < 0 then toIndex = size + toIndex
            if toIndex >= size then toIndex = lastIndex

            if fromIndex >= size or fromIndex > toIndex then return slicedArr

            for i = fromIndex to toIndex
                slicedArr.push(arr[i])
            end for

            return slicedArr
        end function,

        fill: function(arr as object, value as dynamic, startIndex = 0 as integer, endIndex = invalid as dynamic)
            if not m.isArray(arr) then return invalid

            size = arr.count()
            lastIndex = size - 1
            filledArr = []

            if size = 0 then return arr

            if startIndex < 0 then startIndex = 0
            if startIndex > lastIndex then startIndex = lastIndex
            if endIndex = invalid then endIndex = lastIndex
            if endIndex < startIndex then endIndex = startIndex

            for i = 0 to lastIndex
                if i >= startIndex and i <= endIndex
                    filledArr.push(value)
                else
                    filledArr.push(arr[i])
                end if
            end for

            return filledArr
        end function,

        flat: function(arr as object, depth = 1 as integer)
            if not m.isArray(arr) then return invalid

            size = arr.count()

            if size = 0 then return arr

            flattenArr = []

            for each item in arr
                if m.isArray(item)
                    if depth > 1
                        flattenArr.append(m.flat(item, depth - 1))
                    else
                        flattenArr.append(item)
                    end if
                else
                    flattenArr.push(item)
                end if
            end for

            return flattenArr
        end function,

        map: function(arr as object, func as function)
            if not m.isArray(arr) then return invalid

            size = arr.count()
            mappedArr = []

            if size = 0 then return mappedArr

            for i = 0 to size - 1
                mappedArr.push(func(arr[i], i, arr))
            end for

            return mappedArr
        end function,

        reduce: function(arr as object, func as function, initialValue = invalid as dynamic)
            if not m.isArray(arr) then return invalid

            size = arr.count()
            startAt = 0
            accumulator = initialValue

            if size = 0 then return accumulator

            if accumulator = invalid
                accumulator = arr[0]
                startAt = 1
            end if

            for i = startAt to size - 1
                accumulator = func(accumulator, arr[i], i, arr)
            end for

            return accumulator
        end function,

        filter: function(arr as object, func as function)
            if not m.isArray(arr) then return invalid

            size = arr.count()
            mappedArr = []

            if size = 0 then return mappedArr

            for i = 0 to size - 1
                if func(arr[i], i, arr)
                    mappedArr.push(arr[i])
                end if
            end for

            return mappedArr
        end function,

        find: function(arr as object, func as function)
            if not m.isArray(arr) then return invalid

            size = arr.count()

            if size = 0 then return invalid

            for i = 0 to size - 1
                if func(arr[i], i, arr)
                    return arr[i]
                end if
            end for

            return invalid
        end function,

        findIndex: function(arr as object, func as function) as integer
            if not m.isArray(arr) then return -1

            size = arr.count()

            if size = 0 then return -1

            for i = 0 to size - 1
                if func(arr[i], i, arr)
                    return i
                end if
            end for

            return -1
        end function,

        every: function(arr as object, func as function) as boolean
            if not m.isArray(arr) then return true

            size = arr.count()

            if size = 0 then return true

            for i = 0 to size - 1
                if func(arr[i], i, arr) = false
                    return false
                end if
            end for

            return true
        end function,

        some: function(arr as object, func as function) as boolean
            if not m.isArray(arr) then return false

            size = arr.count()

            if size = 0 then return false

            for i = 0 to size - 1
                if func(arr[i], i, arr)
                    return true
                end if
            end for

            return false
        end function,

        groupBy: function(arr as object, key as string)
            if not m.isArray(arr) then return invalid

            size = arr.count()
            accumulator = {}

            if size = 0 then return accumulator

            for i = 0 to size - 1
                element = arr[i]

                if element = invalid then continue for

                keyValue = element[key]

                if keyValue = invalid then continue for

                groupName = keyValue.toStr()
                groupArray = accumulator[groupName]

                if m.isArray(groupArray)
                    groupArray.push(element)
                else
                    accumulator[groupName] = []
                    accumulator[groupName].push(element)
                end if
            end for

            return accumulator
        end function
    }

    return util

end function
