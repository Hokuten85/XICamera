--[[
    XICamera - Windower 4 addon

    Camera patch logic lives in the shared xicamera_core.lua (lib/), driven through the generic
    memory helpers exported by the Windower DLL. Native code only provides memory
    read/write/search/allocation primitives and an atomic compare-exchange.
]]

_addon.name = 'XICamera'
_addon.author = 'Hokuten'
_addon.version = '0.8.0'
_addon.commands = {'camera','cam','xicamera','xicam'}

config = require('config')
require('lists')
require('tables')

local defaults = T{
    cameraDistance = 6,
    battleDistance = 8.2,
    horizontalPanSpeed = 3.0,
    verticalPanSpeed = 10.7,
    saveOnIncrement = false,
    autoCalcVertSpeed = true,
    battleRange = 4.0,
    battleRangeLocked = true,
}

local settings = config.load(defaults)
config.save(settings)

local addon_path = windower.addon_path:gsub('\\', '/')
package.cpath = package.cpath .. ';' .. addon_path .. '/libs/?.dll'
package.path = package.path .. ';' .. addon_path .. '/lib/?.lua'

local native = require('windower_native')
local Core = require('xicamera_core')
local raw = native.memory

local mem = {
    find        = function(sig) return raw.find('FFXiMain.dll', 0, sig, 0, 0) end,
    read_u16    = function(a) return raw.read_uint16(a) end,
    read_u32    = function(a) return raw.read_uint32(a) end,
    read_float  = function(a) return raw.read_float(a) end,
    write_u16   = function(a, v) raw.write_uint16(a, v) end,
    write_u32   = function(a, v) raw.write_uint32(a, v) end,
    write_float = function(a, v) raw.write_float(a, v) end,
    alloc       = function(size) return native.alloc(size) end,
    log         = function(text) native.chat(167, text) end,
}
-- the DLL's atomic swap, when this build of it has one
if raw.compare_exchange_uint32 then
    mem.cas_u32 = function(a, expected, v) return raw.compare_exchange_uint32(a, expected, v) end
end
do
    local base, size = raw.get_base('FFXiMain.dll'), raw.get_size('FFXiMain.dll')
    if base and base ~= 0 and size and size ~= 0 then
        mem.image_base, mem.image_size = base, size
    end
end

local core = Core.new(mem)

local function setHorizontalPanSpeed(newSpeed)
    settings.horizontalPanSpeed = newSpeed
    core:setHorizontalPanSpeed(newSpeed)
end

local function setVerticalPanSpeed(newSpeed)
    settings.verticalPanSpeed = newSpeed
    core:setVerticalPanSpeed(newSpeed)
end

local function setCameraDistance(newDistance)
    settings.cameraDistance = newDistance
    core:setCameraDistance(newDistance)
    if settings.autoCalcVertSpeed then
        setVerticalPanSpeed(defaults.verticalPanSpeed * newDistance / 6.0)
    end
end

local function setBattleCameraDistance(newDistance)
    settings.battleDistance = newDistance
    core:setBattleDistance(newDistance)
end

local function setBattleCameraRange(newRange)
    settings.battleRange = math.min(math.max(0, tonumber(newRange) or 0), 100)
    core:setBattleRange(settings.battleRange)
end

local function setBattleRangeLock(isLocked)
    settings.battleRangeLocked = isLocked
    core:setBattleRangeLock(isLocked)
end

local function applySettings()
    setCameraDistance(settings.cameraDistance)
    setBattleCameraDistance(settings.battleDistance)
    setHorizontalPanSpeed(settings.horizontalPanSpeed)
    if settings.autoCalcVertSpeed then
        setVerticalPanSpeed(defaults.verticalPanSpeed * settings.cameraDistance / 6.0)
    else
        setVerticalPanSpeed(settings.verticalPanSpeed)
    end
    setBattleCameraRange(settings.battleRange)
    setBattleRangeLock(settings.battleRangeLocked)
end

windower.register_event('load', function()
    if core:install() then
        native.chat(207, 'loaded. Try //camera status')
    else
        local off = {}
        for _, g in ipairs(core:groupStatus()) do
            if g.required and not g.enabled then off[#off + 1] = g.name end
        end
        native.chat(167, 'not every patch group is in (' .. table.concat(off, ', ') .. '); see //camera status')
    end
    applySettings()
end)

windower.register_event('unload', function()
    config.save(settings)
    core:uninstall()
end)

local function require_number(args, syntax)
    if not args[1] or not tonumber(args[1]) then
        error('Invalid syntax: ' .. syntax)
        return nil
    end
    return tonumber(args[1])
end

windower.register_event('addon command', function(command, ...)
    command = command and command:lower() or 'help'
    local args = L{...}

    if table.contains(T{'help', 'h'}, command) then
        native.chat(8, _addon.name .. ' v.' .. _addon.version)
        native.chat(8, 'd|distance # - sets the camera distance - default: ' .. defaults.cameraDistance)
        native.chat(8, 'b|battle # - sets the battle camera distance - default: ' .. defaults.battleDistance)
        native.chat(8, 'hs|hspeed # - sets the horizontal pan speed - default: ' .. defaults.horizontalPanSpeed)
        native.chat(8, 'vs|vspeed # - sets the vertical pan - default: ' .. defaults.verticalPanSpeed .. ', forces auto calc off')
        native.chat(8, 'vh|vheight # - snaps camera height to character/reference height plus #')
        native.chat(8, 'brange|br # - Set Battle Camera Range - default: 4, min: 0, max: 100, forces battle range lock on')
        native.chat(8, 'battlelock|bl <on|true|1|off|false|0> - lock or unlock Battle Camera Range')
        native.chat(8, 'in|incr, de|decr, bin|bincr, bde|bdecr - step camera distances')
        native.chat(8, 'saveOnIncrement|soi - toggle saving on step commands')
        native.chat(8, 'autoCalcVertSpeed|acv - toggle vertical pan speed auto calc')
        native.chat(8, 's|status - print status')
    elseif table.contains(T{'distance', 'd'}, command) then
        local value = require_number(args, '//camera distance <number>')
        if not value then return end
        setCameraDistance(value)
        config.save(settings)
        native.chat(8, 'set camera distance to ' .. value)
    elseif table.contains(T{'battle', 'b'}, command) then
        local value = require_number(args, '//camera battle <number>')
        if not value then return end
        setBattleCameraDistance(value)
        config.save(settings)
        native.chat(8, 'set battle distance to ' .. value)
    elseif table.contains(T{'hspeed', 'hs'}, command) then
        local value = require_number(args, '//camera hspeed <number>')
        if not value then return end
        setHorizontalPanSpeed(value)
        config.save(settings)
        native.chat(8, 'set horizontal pan speed to ' .. value)
    elseif table.contains(T{'vspeed', 'vs'}, command) then
        local value = require_number(args, '//camera vspeed <number>')
        if not value then return end
        settings.autoCalcVertSpeed = false
        setVerticalPanSpeed(value)
        config.save(settings)
        native.chat(8, 'set vertical pan speed to ' .. value)
    elseif table.contains(T{'vheight', 'vh', 'snapheight', 'sh'}, command) then
        local value = require_number(args, '//camera vheight <offset>')
        if not value then return end
        local cameraY, referenceY = core:snapHeight(value)
        if cameraY then
            native.chat(8, string.format('snapped camera height to %.2f (reference %.2f + %.2f)', cameraY, referenceY, value))
        else
            native.chat(167, 'failed to snap camera height; camera task was not available')
        end
    elseif table.contains(T{'incr', 'in', 'bincr', 'bin', 'decr', 'de', 'bdecr', 'bde'}, command) then
        local isIncr = string.find(command, 'in') ~= nil
        local isBattle = string.find(command, 'b') ~= nil
        local newDistance = (isBattle and settings.battleDistance or settings.cameraDistance) + (isIncr and 1 or -1)
        if isBattle then setBattleCameraDistance(newDistance) else setCameraDistance(newDistance) end
        if settings.saveOnIncrement then config.save(settings) end
        native.chat(8, 'set ' .. (isBattle and 'battle ' or '') .. 'camera distance to ' .. newDistance)
    elseif table.contains(T{'saveonincrement', 'soi'}, command) then
        settings.saveOnIncrement = not settings.saveOnIncrement
        config.save(settings)
        native.chat(8, 'saveOnIncrement changed to ' .. tostring(settings.saveOnIncrement))
    elseif table.contains(T{'autocalcvertspeed', 'acv'}, command) then
        settings.autoCalcVertSpeed = not settings.autoCalcVertSpeed
        if settings.autoCalcVertSpeed then setVerticalPanSpeed(defaults.verticalPanSpeed * settings.cameraDistance / 6.0) end
        config.save(settings)
        native.chat(8, 'autoCalcVertSpeed changed to ' .. tostring(settings.autoCalcVertSpeed))
    elseif table.contains(T{'brange', 'br'}, command) then
        local value = require_number(args, '//camera brange <number>')
        if not value then return end
        setBattleRangeLock(true)
        setBattleCameraRange(value)
        config.save(settings)
        native.chat(8, 'battle camera range changed to ' .. settings.battleRange)
    elseif table.contains(T{'battlelock', 'bl'}, command) then
        if table.contains(T{'on', 'true', '1'}, tostring(args[1])) then
            setBattleRangeLock(true)
            config.save(settings)
            native.chat(8, 'battle camera range locked')
        elseif table.contains(T{'off', 'false', '0'}, tostring(args[1])) then
            setBattleRangeLock(false)
            config.save(settings)
            native.chat(8, 'battle camera range unlocked')
        end
    elseif table.contains(T{'status', 's'}, command) then
        native.chat(127, '- status')
        native.chat(127, '-  active: ' .. tostring(core:active()))
        native.chat(127, '-  cameraDistance: ' .. tostring(settings.cameraDistance))
        native.chat(127, '-  battleDistance: ' .. tostring(settings.battleDistance))
        native.chat(127, '-  horizontalPanSpeed: ' .. tostring(settings.horizontalPanSpeed))
        native.chat(127, '-  verticalPanSpeed: ' .. tostring(settings.verticalPanSpeed))
        local cameraY, referenceY = core:cameraHeights()
        if cameraY then
            native.chat(127, string.format('-  cameraY: %.2f', cameraY))
            native.chat(127, string.format('-  referenceY: %.2f', referenceY))
        end
        native.chat(127, '-  battleRange: ' .. tostring(settings.battleRange))
        native.chat(127, '-  battleRangeLocked: ' .. tostring(settings.battleRangeLocked))
        native.chat(127, '-  saveOnIncrement: ' .. tostring(settings.saveOnIncrement))
        native.chat(127, '-  autoCalcVertSpeed: ' .. tostring(settings.autoCalcVertSpeed))
        for _, site in ipairs(core:status(true)) do
            if site.state ~= 'patched' then
                native.chat(127, string.format('-  %s: %s%s', site.name, site.state, site.note and (' (' .. site.note .. ')') or ''))
            end
        end
    end
end)
