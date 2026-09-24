local native = {}

local prefix = '[XICamera] '
local memory = require('_WindowerMemory')

function native.chat(color, text)
    windower.add_to_chat(color, prefix .. tostring(text))
end

function native.warn(text)
    native.chat(167, 'WARN: ' .. tostring(text))
end

function native.find(name, pattern)
    local address = memory.find('FFXiMain.dll', 0, pattern, 0, 0)
    if address == 0 then
        native.warn(name .. ' signature not found')
        return nil
    end
    return address
end

function native.unprotect(address, size)
    if address ~= nil and address ~= 0 then
        return memory.unprotect(address, size)
    end
    return false
end

function native.alloc(size)
    local ptr = memory.alloc(size)
    return ptr ~= nil and ptr ~= 0 and ptr or nil
end

function native.alloc_float(value)
    local ptr = native.alloc(4)
    if ptr then
        memory.write_float(ptr, value)
    end
    return ptr
end

native.memory = memory

return native
