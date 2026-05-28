--[[
    XICamera - Windower 4 addon

    Camera patch logic lives in Lua and uses the generic _XICamera.memory
    helpers exported by the Windower DLL. This mirrors the Ashita addon model:
    native code only provides memory read/write/search/allocation primitives.
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
local mem = native.memory
local initialized = false

local state = {
    minDistancePtr = nil,
    originalMinDistance = nil,
    maxDistancePtr = nil,
    originalMaxDistance = nil,
    minBattleDistancePtr = nil,
    originalMinBattleDistance = nil,
    maxBattleDistancePtr = nil,
    originalMaxBattleDistance = nil,
    horizontalPanSpeedPtr = nil,
    originalHorizontalPanSpeed = nil,
    verticalPanSpeedPtr = nil,
    originalVerticalPanSpeed = nil,

    zoomSetupSig = nil,
    walkAnimationSig = nil,
    npcWalkAnimationSig = nil,
    battleSoundSig = nil,
    originalMinDistancePtr = nil,
    newMinDistanceConstant = nil,

    jittersSig = nil,
    originalJitterPtr = nil,
    newJitterPtr = nil,
    jittersPush1Sig = nil,
    originalJitterPush1Ptr = nil,
    newJitterNegPtr = nil,

    battleCamRangeSig = nil,
    originalBattleCamRangePtr = nil,
    newBattleCamRangePtr = nil,
    battleCamRangeLockLocation = nil,
    originalBattleRangeLockValues = nil,

    cameraManagerGlobalPtr = nil,
}

local function setHorizontalPanSpeed(newSpeed)
    settings.horizontalPanSpeed = newSpeed
    if state.horizontalPanSpeedPtr then
        mem.write_float(state.horizontalPanSpeedPtr, newSpeed / 100.0)
    end
end

local function setVerticalPanSpeed(newSpeed)
    settings.verticalPanSpeed = newSpeed
    if state.verticalPanSpeedPtr then
        mem.write_float(state.verticalPanSpeedPtr, newSpeed / 100.0)
    end
end

local function setCameraDistance(newDistance)
    settings.cameraDistance = newDistance
    if state.minDistancePtr and state.maxDistancePtr then
        mem.write_float(state.minDistancePtr, newDistance - (state.originalMaxDistance - state.originalMinDistance))
        mem.write_float(state.maxDistancePtr, newDistance)
    end
    if state.newMinDistanceConstant then
        mem.write_float(state.newMinDistanceConstant, newDistance - (state.originalMaxDistance - state.originalMinDistance))
    end
    if settings.autoCalcVertSpeed then
        setVerticalPanSpeed(defaults.verticalPanSpeed * newDistance / 6.0)
    end
end

local function setBattleCameraDistance(newDistance)
    settings.battleDistance = newDistance
    if state.minBattleDistancePtr and state.maxBattleDistancePtr then
        mem.write_float(state.minBattleDistancePtr, newDistance - (state.originalMaxBattleDistance - state.originalMinBattleDistance))
        mem.write_float(state.maxBattleDistancePtr, newDistance)
    end
end

local function setBattleCameraRange(newRange)
    settings.battleRange = math.min(math.max(0, tonumber(newRange) or 0), 100)
    if state.newBattleCamRangePtr then
        mem.write_float(state.newBattleCamRangePtr, settings.battleRange)
    end
end

local function setBattleRangeLock(isLocked)
    settings.battleRangeLocked = isLocked
    if not state.battleCamRangeLockLocation then return end
    if isLocked then
        mem.write_uint16(state.battleCamRangeLockLocation, state.originalBattleRangeLockValues)
    else
        mem.write_uint16(state.battleCamRangeLockLocation, 0x9090)
    end
end

local function getCameraTask()
    if not state.cameraManagerGlobalPtr then return nil end
    local manager = mem.read_uint32(state.cameraManagerGlobalPtr)
    if not manager or manager == 0 then return nil end
    local cameraTask = mem.read_uint32(manager + 0x50)
    if not cameraTask or cameraTask == 0 then return nil end
    return cameraTask
end

local function snapVerticalCameraOffset(offset)
    local cameraTask = getCameraTask()
    if not cameraTask then return nil end
    local referenceY = mem.read_float(cameraTask + 0x54)
    local cameraY = referenceY + offset
    mem.write_float(cameraTask + 0x48, cameraY)
    return cameraY, referenceY
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

local function initMemory()
    if initialized then return true end

    local minDistanceSig = native.find('minDistanceSig', 'D8C9D9C0D8C1D9C2D80D????????D9C3DCC0D8EB')
    if not minDistanceSig then return false end
    state.minDistancePtr = mem.read_uint32(minDistanceSig + 0x0A)
    state.originalMinDistance = mem.read_float(state.minDistancePtr)
    native.unprotect(state.minDistancePtr, 4)

    local maxDistanceSig = native.find('maxDistanceSig', 'D9442410D825????????51D80D')
    if not maxDistanceSig then return false end
    state.maxDistancePtr = mem.read_uint32(maxDistanceSig + 0x06)
    state.originalMaxDistance = mem.read_float(state.maxDistancePtr)
    native.unprotect(state.maxDistancePtr, 4)

    local minBattleDistanceSig = native.find('minBattleDistanceSig', '5152D8442424D905????????D8C1')
    if not minBattleDistanceSig then return false end
    state.minBattleDistancePtr = mem.read_uint32(minBattleDistanceSig + 0x08)
    state.originalMinBattleDistance = mem.read_float(state.minBattleDistancePtr)
    native.unprotect(state.minBattleDistancePtr, 4)

    local maxBattleDistanceSig = native.find('maxBattleDistanceSig', 'D8C1D8CAD95C2450D805????????D8C9')
    if not maxBattleDistanceSig then return false end
    state.maxBattleDistancePtr = mem.read_uint32(maxBattleDistanceSig + 0x0A)
    state.originalMaxBattleDistance = mem.read_float(state.maxBattleDistancePtr)
    native.unprotect(state.maxBattleDistancePtr, 4)

    state.zoomSetupSig = native.find('zoomSetupSig', '85C0741AD9442404D80D????????D80D????????D87C')
    if state.zoomSetupSig then
        state.originalMinDistancePtr = mem.read_uint32(state.zoomSetupSig + 0x10)
        state.newMinDistanceConstant = native.alloc_float(state.originalMinDistance)
        if state.newMinDistanceConstant then
            mem.write_uint32(state.zoomSetupSig + 0x10, state.newMinDistanceConstant)
        end
    end

    state.walkAnimationSig = native.find('walkAnimationSig', '0F85????????D80D????????D913D81D')
    if state.walkAnimationSig and state.newMinDistanceConstant then
        mem.write_uint32(state.walkAnimationSig + 0x08, state.newMinDistanceConstant)
    end

    state.npcWalkAnimationSig = native.find('npcWalkAnimationSig', '7514D9442410D80D????????D91B8B8E')
    if state.npcWalkAnimationSig and state.newMinDistanceConstant then
        mem.write_uint32(state.npcWalkAnimationSig + 0x08, state.newMinDistanceConstant)
    end

    state.battleSoundSig = native.find('battleSoundSig', 'D95C2414741B487410D9442410D80D')
    if state.battleSoundSig and state.newMinDistanceConstant then
        mem.write_uint32(state.battleSoundSig + 0x0F, state.newMinDistanceConstant)
    end

    local hPanSpeedSig = native.find('hPanSpeedSig', 'D84C24208B068BCED80D')
    if hPanSpeedSig then
        state.horizontalPanSpeedPtr = mem.read_uint32(hPanSpeedSig + 0x0A)
        state.originalHorizontalPanSpeed = mem.read_float(state.horizontalPanSpeedPtr)
        native.unprotect(state.horizontalPanSpeedPtr, 4)
    end

    local vPanSpeedSig = native.find('vPanSpeedSig', 'D84C24248B168BCED80D')
    if vPanSpeedSig then
        state.verticalPanSpeedPtr = mem.read_uint32(vPanSpeedSig + 0x0A)
        state.originalVerticalPanSpeed = mem.read_float(state.verticalPanSpeedPtr)
        native.unprotect(state.verticalPanSpeedPtr, 4)
    end

    state.jittersSig = native.find('jittersSig', '8D54242C8D44242CD8C9525550')
    if state.jittersSig then
        state.newJitterPtr = native.alloc_float(1.0)
        state.originalJitterPtr = mem.read_uint32(state.jittersSig + 0x0F)
        mem.write_uint32(state.jittersSig + 0x0F, state.newJitterPtr)
        mem.write_uint32(state.jittersSig + 0x1F, state.newJitterPtr)
    end

    state.jittersPush1Sig = native.find('jittersPush1Sig', 'D8642410518D44242CD80D????????D91C24')
    if state.jittersPush1Sig then
        state.newJitterNegPtr = native.alloc_float(-1.0)
        state.originalJitterPush1Ptr = mem.read_uint32(state.jittersPush1Sig + 0x0B)
        mem.write_uint32(state.jittersPush1Sig + 0x0B, state.newJitterNegPtr)
    end

    state.battleCamRangeSig = native.find('battleCamRangeSig', 'D8C9D99C24DC000000DDD8D9442450D8442428D83D')
    if state.battleCamRangeSig then
        state.originalBattleCamRangePtr = mem.read_uint32(state.battleCamRangeSig + 0x15)
        state.newBattleCamRangePtr = native.alloc_float(mem.read_float(state.originalBattleCamRangePtr))
        mem.write_uint32(state.battleCamRangeSig + 0x15, state.newBattleCamRangePtr)
        state.battleCamRangeLockLocation = state.battleCamRangeSig + 0x19
        state.originalBattleRangeLockValues = mem.read_uint16(state.battleCamRangeLockLocation)
    end

    local cameraManagerSig = native.find('cameraManagerSig', 'A1????????0594020000C39090909090A1????????8B4050C3')
    if cameraManagerSig then
        state.cameraManagerGlobalPtr = mem.read_uint32(cameraManagerSig + 0x11)
    end

    initialized = true
    applySettings()
    return true
end

local function restorePointers()
    if not initialized then return end

    if state.minDistancePtr then mem.write_float(state.minDistancePtr, state.originalMinDistance) end
    if state.maxDistancePtr then mem.write_float(state.maxDistancePtr, state.originalMaxDistance) end
    if state.minBattleDistancePtr then mem.write_float(state.minBattleDistancePtr, state.originalMinBattleDistance) end
    if state.maxBattleDistancePtr then mem.write_float(state.maxBattleDistancePtr, state.originalMaxBattleDistance) end
    if state.horizontalPanSpeedPtr then mem.write_float(state.horizontalPanSpeedPtr, state.originalHorizontalPanSpeed) end
    if state.verticalPanSpeedPtr then mem.write_float(state.verticalPanSpeedPtr, state.originalVerticalPanSpeed) end

    if state.zoomSetupSig and state.originalMinDistancePtr then mem.write_uint32(state.zoomSetupSig + 0x10, state.originalMinDistancePtr) end
    if state.walkAnimationSig and state.originalMinDistancePtr then mem.write_uint32(state.walkAnimationSig + 0x08, state.originalMinDistancePtr) end
    if state.npcWalkAnimationSig and state.originalMinDistancePtr then mem.write_uint32(state.npcWalkAnimationSig + 0x08, state.originalMinDistancePtr) end
    if state.battleSoundSig and state.originalMinDistancePtr then mem.write_uint32(state.battleSoundSig + 0x0F, state.originalMinDistancePtr) end

    if state.jittersSig and state.originalJitterPtr then
        mem.write_uint32(state.jittersSig + 0x0F, state.originalJitterPtr)
        mem.write_uint32(state.jittersSig + 0x1F, state.originalJitterPtr)
    end
    if state.jittersPush1Sig and state.originalJitterPush1Ptr then
        mem.write_uint32(state.jittersPush1Sig + 0x0B, state.originalJitterPush1Ptr)
    end
    if state.battleCamRangeSig and state.originalBattleCamRangePtr then
        mem.write_uint32(state.battleCamRangeSig + 0x15, state.originalBattleCamRangePtr)
    end
    if state.battleCamRangeLockLocation and state.originalBattleRangeLockValues then
        mem.write_uint16(state.battleCamRangeLockLocation, state.originalBattleRangeLockValues)
    end

    if state.newMinDistanceConstant then mem.dealloc(state.newMinDistanceConstant) end
    if state.newJitterPtr then mem.dealloc(state.newJitterPtr) end
    if state.newJitterNegPtr then mem.dealloc(state.newJitterNegPtr) end
    if state.newBattleCamRangePtr then mem.dealloc(state.newBattleCamRangePtr) end

    initialized = false
end

windower.register_event('load', function()
    if initMemory() then
        native.chat(207, 'loaded. Try //camera status')
    else
        native.chat(167, 'failed to initialize; one or more required signatures were not found')
    end
end)

windower.register_event('unload', function()
    config.save(settings)
    restorePointers()
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
        local cameraY, referenceY = snapVerticalCameraOffset(value)
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
        native.chat(127, '-  initialized: ' .. tostring(initialized))
        native.chat(127, '-  cameraDistance: ' .. tostring(settings.cameraDistance))
        native.chat(127, '-  battleDistance: ' .. tostring(settings.battleDistance))
        native.chat(127, '-  horizontalPanSpeed: ' .. tostring(settings.horizontalPanSpeed))
        native.chat(127, '-  verticalPanSpeed: ' .. tostring(settings.verticalPanSpeed))
        local cameraTask = getCameraTask()
        if cameraTask then
            native.chat(127, string.format('-  cameraY: %.2f', mem.read_float(cameraTask + 0x48)))
            native.chat(127, string.format('-  referenceY: %.2f', mem.read_float(cameraTask + 0x54)))
        end
        native.chat(127, '-  battleRange: ' .. tostring(settings.battleRange))
        native.chat(127, '-  battleRangeLocked: ' .. tostring(settings.battleRangeLocked))
        native.chat(127, '-  saveOnIncrement: ' .. tostring(settings.saveOnIncrement))
        native.chat(127, '-  autoCalcVertSpeed: ' .. tostring(settings.autoCalcVertSpeed))
    end
end)

