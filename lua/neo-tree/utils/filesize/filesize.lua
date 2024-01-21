-- lua-filesize, generate a human readable string describing the file size
-- Copyright (c) 2016 Boris Nagaev
-- See the LICENSE file for terms of use.

local si = {
    bits = {"b", "Kb", "Mb", "Gb", "Tb", "Pb", "Eb", "Zb", "Yb"},
    bytes = {"B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"},
}

local function isNan(num)
    -- http://lua-users.org/wiki/InfAndNanComparisons
    -- NaN is the only value that doesn't equal itself
    return num ~= num
end

local function roundNumber(num, digits)
    local fmt = "%." .. digits .. "f"
    return tonumber(fmt:format(num))
end

local function filesize(size, options)

    -- copy options to o
    local o = {}
    for key, value in pairs(options or {}) do
        o[key] = value
    end

    local function setDefault(name, default)
        if o[name] == nil then
            o[name] = default
        end
    end
    setDefault("bits", false)
    setDefault("unix", false)
    setDefault("base", 2)
    setDefault("round", o.unix and 1 or 2)
    setDefault("spacer", o.unix and "" or " ")
    setDefault("suffixes", {})
    setDefault("output", "string")
    setDefault("exponent", -1)

    assert(not isNan(size), "Invalid arguments")

    local ceil = (o.base > 2) and 1000 or 1024
    local negative = (size < 0)
    if negative then
        -- Flipping a negative number to determine the size
        size = -size
    end

    local result

    -- Zero is now a special case because bytes divide by 1
    if size == 0 then
        result = {
            0,
            o.unix and "" or (o.bits and "b" or "B"),
        }
    else
        -- Determining the exponent
        if o.exponent == -1 or isNan(o.exponent) then
            o.exponent = math.floor(math.log(size) / math.log(ceil))
        end

        -- Exceeding supported length, time to reduce & multiply
        if o.exponent > 8 then
            o.exponent = 8
        end

        local val
        if o.base == 2 then
            val = size / math.pow(2, o.exponent * 10)
        else
            val = size / math.pow(1000, o.exponent)
        end

        if o.bits then
            val = val * 8
            if val > ceil then
                val = val / ceil
                o.exponent = o.exponent + 1
            end
        end

        result = {
            roundNumber(val, o.exponent > 0 and o.round or 0),
            (o.base == 10 and o.exponent == 1) and
                (o.bits and "kb" or "kB") or
                (si[o.bits and "bits" or "bytes"][o.exponent + 1]),
        }

        if o.unix then
            result[2] = result[2]:sub(1, 1)

            if result[2] == "b" or result[2] == "B" then
                result ={
                    math.floor(result[1]),
                    "",
                }
            end
        end

    end

    assert(result)

    -- Decorating a 'diff'
    if negative then
        result[1] = -result[1]
    end

    -- Applying custom suffix
    result[2] = o.suffixes[result[2]] or result[2]

    -- Applying custom suffix
    result[2] = o.suffixes[result[2]] or result[2]

    -- Returning Array, Object, or String (default)
    if o.output == "array" then
        return result
    elseif o.output == "exponent" then
        return o.exponent
    elseif o.output == "object" then
        return {
            value = result[1],
            suffix = result[2],
        }
    elseif o.output == "string" then
        local value = tostring(result[1])
        value = value:gsub('%.0$', '')
        local suffix = result[2]
        return value .. o.spacer .. suffix
    end
end

return filesize
