--[[
    XICamera — Windower 5 addon

    Adjusts camera distance, pan speed, jitter, battle range, and the
    battle-camera lock by patching FFXiMain.dll. Feature-equivalent to
    the Ashita 3 / Ashita 4 lua addons in this repo.
]]

local chat       = require('core.chat')
local command    = require('core.command')
local ffi        = require('ffi')
local memory     = require('memory')
local scanner    = require('core.scanner')
local settings   = require('settings')
local struct_lib = require('struct')
local win32      = require('win32')

local ffi_new   = ffi.new
local ffi_cast  = ffi.cast
local ffi_gc    = ffi.gc
local add_text  = chat.add_text
local struct    = struct_lib.struct
local float     = struct_lib.float
local uint16    = struct_lib.uint16

-- ---------------------------------------------------------------------------
-- Win32 imports for unprotecting and code-cave allocation.
-- ---------------------------------------------------------------------------

local VirtualProtect = win32.def({
    name = 'VirtualProtect',
    returns = 'bool',
    parameters = { 'void*', 'size_t', 'DWORD', 'PDWORD' },
    failure = false
})
local HeapCreate = win32.def({
    name = 'HeapCreate',
    returns = 'void*',
    parameters = { 'uint32_t', 'size_t', 'size_t' },
    failure = false
})
local HeapAlloc = win32.def({
    name = 'HeapAlloc',
    returns = 'void*',
    parameters = { 'void*', 'uint32_t', 'size_t' },
    failure = false
})
local HeapDestroy = win32.def({
    name = 'HeapDestroy',
    returns = 'bool',
    parameters = { 'void*' },
    failure = false
})

local PAGE_READWRITE = 0x04

local function unprotect(p, n)
    VirtualProtect(ffi_cast('void*', p), n, PAGE_READWRITE, ffi_new('DWORD[1]'))
end

-- A small heap to hold our injected float constants. Persists for the
-- lifetime of the addon; freed on unload.
local cave_heap = HeapCreate(0x40000, 0, 0)

local function alloc_float(initial)
    local raw = HeapAlloc(cave_heap, 8, 4) -- HEAP_ZERO_MEMORY=0x8
    local f   = ffi_cast('float*', raw)
    f[0] = initial or 0.0
    return f
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local defaults = {
    distance           = 6.0,
    battleDistance     = 8.2,
    battleRange        = 4.0,
    horizontalPanSpeed = 3.0,
    verticalPanSpeed   = 10.7,
    saveOnIncrement    = false,
    autoCalcVertSpeed  = true,
    battleRangeLocked  = true,
}
local options = settings.load(defaults)

-- ---------------------------------------------------------------------------
-- Live state. Pointers are populated at load time after the signature scan.
-- ---------------------------------------------------------------------------

local state = {
    minDistance              = nil,  -- struct: { val = float }
    originalMinDistance      = nil,
    maxDistance              = nil,
    originalMaxDistance      = nil,
    minBattleDistance        = nil,
    originalMinBattleDistance = nil,
    maxBattleDistance        = nil,
    originalMaxBattleDistance = nil,

    horizontalPanSpeed       = nil,  -- struct: { val = float }
    originalHorizontalPanSpeed = nil,
    verticalPanSpeed         = nil,
    originalVerticalPanSpeed = nil,

    -- Pointer-rewrite sites: each is the ADDRESS of a float* slot inside
    -- FFXiMain.dll that the game reads from. We swap the slot to point
    -- at our injected `newMinDistanceConstant` so we can change the
    -- effective min camera distance everywhere it's read.
    zoomSetupSlot        = nil,
    walkAnimSlot         = nil,
    npcWalkAnimSlot      = nil,
    battleSoundSlot      = nil,
    originalMinDistanceSlotValue = nil,  -- whatever pointer those slots held originally
    newMinDistanceConstant = nil,        -- our float* override

    -- Jitter: two related proximity-push damping sites in sub_1001ED90.
    -- Site #2 (horizontal x/z arm) has two FMUL slots reading +0.125;
    -- we redirect both at `newJitter = 1.0`. Site #1 (vertical arm)
    -- has one FMUL slot reading -0.125; we redirect at `newJitterNeg
    -- = -1.0`. See docs/JITTER_INVESTIGATION.md.
    jitterMatch          = nil,
    originalJitterPtr    = nil,
    newJitter            = nil,
    jitterPush1Match     = nil,
    originalJitterPush1Ptr = nil,
    newJitterNeg         = nil,

    -- Battle camera range: pointer-rewrite + a 2-byte clamp at +0x04
    -- that we NOP-out (0x9090) when the user requests "unlock".
    battleRangeMatch     = nil,
    battleRangeSlot      = nil,         -- match + 0x15
    originalBattleRangePtr = nil,
    newBattleRange       = nil,
    battleRangeLockSlot  = nil,         -- match + 0x19  (the 2-byte clamp)
    originalBattleRangeLockBytes = nil,

    cameraManagerGlobal  = nil,
}

-- ---------------------------------------------------------------------------
-- Signature scan + setup
-- ---------------------------------------------------------------------------

local function scan_setup()
    -- Min/max camera distance values themselves, plus min/max battle
    -- distance. These are 4-byte floats inside the data segment; the
    -- signatures find a load instruction and we follow the operand.
    memory.minDistance = struct({signature = 'D8C9D9C0D8C1D9C2D80D*????????D9C3DCC0D8EB'}, {
        val = {0x0, float}
    })
    memory.maxDistance = struct({signature = 'D9442410D825*????????51D80D'}, {
        val = {0x0, float}
    })
    memory.minBattleDistance = struct({signature = '5152D8442424D905*????????D8C1'}, {
        val = {0x0, float}
    })
    memory.maxBattleDistance = struct({signature = 'D8C1D8CAD95C2450D805*????????D8C9'}, {
        val = {0x0, float}
    })
    memory.horizontalPanSpeed = struct({signature = 'D84C24208B068BCED80D*'}, {
        val = {0x0, float}
    })
    memory.verticalPanSpeed = struct({signature = 'D84C24248B168BCED80D*'}, {
        val = {0x0, float}
    })

    state.minDistance        = memory.minDistance
    state.maxDistance        = memory.maxDistance
    state.minBattleDistance  = memory.minBattleDistance
    state.maxBattleDistance  = memory.maxBattleDistance
    state.horizontalPanSpeed = memory.horizontalPanSpeed
    state.verticalPanSpeed   = memory.verticalPanSpeed

    state.originalMinDistance        = state.minDistance.val
    state.originalMaxDistance        = state.maxDistance.val
    state.originalMinBattleDistance  = state.minBattleDistance.val
    state.originalMaxBattleDistance  = state.maxBattleDistance.val
    state.originalHorizontalPanSpeed = state.horizontalPanSpeed.val
    state.originalVerticalPanSpeed   = state.verticalPanSpeed.val

    -- Unprotect all of the scalar slots we plan to rewrite.
    unprotect(state.minDistance,        4)
    unprotect(state.maxDistance,        4)
    unprotect(state.minBattleDistance,  4)
    unprotect(state.maxBattleDistance,  4)
    unprotect(state.horizontalPanSpeed, 4)
    unprotect(state.verticalPanSpeed,   4)

    -- Allocate the float* override the game will see in place of the
    -- "min camera distance" pointer at four call sites.
    state.newMinDistanceConstant = alloc_float(state.originalMinDistance)

    local function patch_float_ptr_slot(sig)
        -- Each signature includes a `*` marker on the operand byte that
        -- holds the float* the game reads. scanner.scan returns the
        -- address of that operand; we cast it to float** and swap.
        local slot = ffi_cast('float**', scanner.scan(sig))
        if slot == nil then return nil end
        return slot
    end

    -- Zoom-on-zone-in setup, walk anim, npc walk anim, battle sound
    -- calculation. All four read the same float*; we point them all at
    -- our overridable copy so changing one value moves every reader.
    local zoom_slot      = patch_float_ptr_slot('85C0741AD9442404D80D????????D80D&????????D87C')
    local walk_slot      = patch_float_ptr_slot('0F85????????D80D&????????D913D81D')
    local npc_walk_slot  = patch_float_ptr_slot('7514D9442410D80D&????????D91B8B8E')
    local sound_slot     = patch_float_ptr_slot('D95C2414741B487410D9442410D80D&')

    -- Min-distance follower sites: each is independent, fail-soft per slot.
    if zoom_slot     ~= nil then state.zoomSetupSlot   = zoom_slot;     zoom_slot[0]     = state.newMinDistanceConstant
    else add_text('[xicamera] WARN: zoom-on-zone signature not found; that follower stays at stock min distance') end
    if walk_slot     ~= nil then state.walkAnimSlot    = walk_slot;     walk_slot[0]     = state.newMinDistanceConstant
    else add_text('[xicamera] WARN: walk anim signature not found; that follower stays at stock min distance') end
    if npc_walk_slot ~= nil then state.npcWalkAnimSlot = npc_walk_slot; npc_walk_slot[0] = state.newMinDistanceConstant
    else add_text('[xicamera] WARN: NPC walk anim signature not found; that follower stays at stock min distance') end
    if sound_slot    ~= nil then state.battleSoundSlot = sound_slot;    sound_slot[0]    = state.newMinDistanceConstant
    else add_text('[xicamera] WARN: battle sound signature not found; that follower stays at stock min distance') end

    -- Cache the *original* value so unload can restore it. Pick whichever
    -- slot survived (any one is sufficient — they all started identical).
    state.originalMinDistanceSlotValue =
        (zoom_slot and zoom_slot[0]) or
        (walk_slot and walk_slot[0]) or
        (npc_walk_slot and npc_walk_slot[0]) or
        (sound_slot and sound_slot[0])

    -- Jitter override site #2 (horizontal x/z arm): +1.0 instead of +0.125.
    -- See docs/JITTER_INVESTIGATION.md.
    local jitter_match = ffi_cast('uint8_t*', scanner.scan('8D54242C8D44242CD8C9525550'))
    if jitter_match == nil then
        add_text('[xicamera] WARN: jitter signature (push #2) not found; horizontal-axis damping unchanged')
    else
        state.jitterMatch = jitter_match
        state.newJitter   = alloc_float(1.0)
        local j0 = ffi_cast('float**', jitter_match + 0x0F)
        local j1 = ffi_cast('float**', jitter_match + 0x1F)
        state.originalJitterPtr = j0[0]
        j0[0] = state.newJitter
        j1[0] = state.newJitter
    end

    -- Jitter override site #1 (vertical/single-axis arm): -1.0 instead of -0.125.
    local jitter_push1_match = ffi_cast('uint8_t*', scanner.scan('D8642410518D44242CD80D&????????D91C24'))
    if jitter_push1_match == nil then
        add_text('[xicamera] WARN: jitter signature (push #1) not found; vertical-axis damping unchanged')
    else
        -- scanner.scan with `&` returns the operand address directly.
        state.jitterPush1Match = jitter_push1_match
        state.newJitterNeg     = alloc_float(-1.0)
        local slot = ffi_cast('float**', jitter_push1_match)
        state.originalJitterPush1Ptr = slot[0]
        slot[0] = state.newJitterNeg
    end

    -- Battle camera range: float* at +0x15, plus a 2-byte clamp at +0x19
    -- we NOP-out for 360deg rotation.
    local br_match = ffi_cast('uint8_t*', scanner.scan('D8C9D99C24DC000000DDD8D9442450D8442428D83D'))
    if br_match == nil then
        add_text('[xicamera] WARN: battle camera range signature not found; range/lock features unavailable')
    else
        state.battleRangeMatch = br_match
        local br_slot = ffi_cast('float**', br_match + 0x15)
        state.battleRangeSlot        = br_slot
        state.originalBattleRangePtr = br_slot[0]
        state.newBattleRange         = alloc_float(br_slot[0][0])
        br_slot[0] = state.newBattleRange
        state.battleRangeLockSlot = ffi_cast('uint16_t*', br_match + 0x19)
        state.originalBattleRangeLockBytes = state.battleRangeLockSlot[0]
    end

    local camera_manager_operand = ffi_cast('uint32_t*', scanner.scan('A1????????0594020000C39090909090A1&????????8B4050C3'))
    if camera_manager_operand ~= nil then
        state.cameraManagerGlobal = ffi_cast('uint32_t*', camera_manager_operand[0])
    else
        add_text('[xicamera] WARN: camera manager signature not found; vertical height snap unavailable')
    end
end

-- ---------------------------------------------------------------------------
-- Mutators (mirror the Ashita 4 lua addon's surface)
-- ---------------------------------------------------------------------------

local function setHorizontalPanSpeed(newSpeed)
    options.horizontalPanSpeed = newSpeed
    state.horizontalPanSpeed.val = newSpeed / 100.0
end

local function setVerticalPanSpeed(newSpeed)
    options.verticalPanSpeed = newSpeed
    state.verticalPanSpeed.val = newSpeed / 100.0
end

local function setCameraDistance(newDistance)
    options.distance = newDistance
    state.minDistance.val = newDistance - (state.originalMaxDistance - state.originalMinDistance)
    state.maxDistance.val = newDistance
    if options.autoCalcVertSpeed then
        setVerticalPanSpeed(defaults.verticalPanSpeed * newDistance / 6.0)
    end
end

local function setBattleCameraDistance(newDistance)
    options.battleDistance = newDistance
    state.minBattleDistance.val = newDistance - (state.originalMaxBattleDistance - state.originalMinBattleDistance)
    state.maxBattleDistance.val = newDistance
end

local function setBattleCameraRange(newRange)
    options.battleRange = math.min(math.max(0, tonumber(newRange) or 0), 100)
    if state.newBattleRange ~= nil then
        state.newBattleRange[0] = options.battleRange
    end
end

local function setBattleRangeLock(isLocked)
    options.battleRangeLocked = isLocked
    if state.battleRangeLockSlot == nil then return end
    if isLocked then
        state.battleRangeLockSlot[0] = state.originalBattleRangeLockBytes
    else
        state.battleRangeLockSlot[0] = 0x9090
    end
end

local function getCameraTask()
    if state.cameraManagerGlobal == nil then return nil end
    local manager = tonumber(state.cameraManagerGlobal[0])
    if manager == 0 then return nil end
    local camera_task_slot = ffi_cast('uint32_t*', manager + 0x50)
    local camera_task = tonumber(camera_task_slot[0])
    if camera_task == 0 then return nil end
    return ffi_cast('float*', camera_task)
end

local function snapVerticalCameraOffset(offset)
    local cameraTask = getCameraTask()
    if cameraTask == nil then return nil end
    local referenceY = cameraTask[0x54 / 4]
    local cameraY = referenceY + offset
    cameraTask[0x48 / 4] = cameraY
    return cameraY, referenceY
end

local function applyAll()
    setCameraDistance(options.distance)
    setBattleCameraDistance(options.battleDistance)
    setHorizontalPanSpeed(options.horizontalPanSpeed)
    if not options.autoCalcVertSpeed then
        setVerticalPanSpeed(options.verticalPanSpeed)
    end
    setBattleCameraRange(options.battleRange)
    setBattleRangeLock(options.battleRangeLocked)
end

-- ---------------------------------------------------------------------------
-- Restore on unload
-- ---------------------------------------------------------------------------

local function restorePointers()
    if state.minDistance       then state.minDistance.val       = state.originalMinDistance       end
    if state.maxDistance       then state.maxDistance.val       = state.originalMaxDistance       end
    if state.minBattleDistance then state.minBattleDistance.val = state.originalMinBattleDistance end
    if state.maxBattleDistance then state.maxBattleDistance.val = state.originalMaxBattleDistance end
    if state.horizontalPanSpeed then state.horizontalPanSpeed.val = state.originalHorizontalPanSpeed end
    if state.verticalPanSpeed   then state.verticalPanSpeed.val   = state.originalVerticalPanSpeed   end

    if state.zoomSetupSlot   then state.zoomSetupSlot[0]   = state.originalMinDistanceSlotValue end
    if state.walkAnimSlot    then state.walkAnimSlot[0]    = state.originalMinDistanceSlotValue end
    if state.npcWalkAnimSlot then state.npcWalkAnimSlot[0] = state.originalMinDistanceSlotValue end
    if state.battleSoundSlot then state.battleSoundSlot[0] = state.originalMinDistanceSlotValue end

    if state.jitterMatch then
        local j0 = ffi_cast('float**', state.jitterMatch + 0x0F)
        local j1 = ffi_cast('float**', state.jitterMatch + 0x1F)
        j0[0] = state.originalJitterPtr
        j1[0] = state.originalJitterPtr
    end
    if state.jitterPush1Match then
        local slot = ffi_cast('float**', state.jitterPush1Match)
        slot[0] = state.originalJitterPush1Ptr
    end

    if state.battleRangeSlot then
        state.battleRangeSlot[0] = state.originalBattleRangePtr
    end
    if state.battleRangeLockSlot and
       state.battleRangeLockSlot[0] ~= state.originalBattleRangeLockBytes then
        state.battleRangeLockSlot[0] = state.originalBattleRangeLockBytes
    end

    if cave_heap then
        HeapDestroy(cave_heap)
        cave_heap = nil
    end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

scan_setup()
applyAll()
settings.save()

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

local function changeAndPersist(label, fn, value)
    fn(value)
    settings.save()
    add_text(label .. ' changed to ' .. tostring(value))
end

local function cmd_distance(arg)
    local n = tonumber(arg)
    if n then changeAndPersist('Distance', setCameraDistance, n) end
end

local function cmd_battle(arg)
    local n = tonumber(arg)
    if n then changeAndPersist('Battle distance', setBattleCameraDistance, n) end
end

local function cmd_hspeed(arg)
    local n = tonumber(arg)
    if n then changeAndPersist('Horizontal pan speed', setHorizontalPanSpeed, n) end
end

local function cmd_vspeed(arg)
    local n = tonumber(arg)
    if n then
        options.autoCalcVertSpeed = false
        changeAndPersist('Vertical pan speed', setVerticalPanSpeed, n)
    end
end

local function cmd_vheight(arg)
    local n = tonumber(arg)
    if not n then return end
    local cameraY, referenceY = snapVerticalCameraOffset(n)
    if cameraY then
        add_text(string.format('Camera height snapped to %.2f (reference %.2f + %.2f)', cameraY, referenceY, n))
    else
        add_text('[xicamera] WARN: camera task not available; vertical snap failed')
    end
end

local function cmd_brange(arg)
    local n = tonumber(arg)
    if n then
        setBattleRangeLock(true)
        changeAndPersist('Battle camera range', setBattleCameraRange, n)
    end
end

local function cmd_battlelock(arg)
    local on = ({['on']=true, ['true']=true, ['1']=true})[tostring(arg):lower()] == true
    local off = ({['off']=true, ['false']=true, ['0']=true})[tostring(arg):lower()] == true
    if on then
        setBattleRangeLock(true)
        settings.save()
        add_text('Battle camera range locked.')
    elseif off then
        setBattleRangeLock(false)
        settings.save()
        add_text('Battle camera range unlocked.')
    end
end

local function cmd_step(direction, isBattle)
    local current = isBattle and options.battleDistance or options.distance
    local next_v  = current + (direction > 0 and 1 or -1)
    local fn      = isBattle and setBattleCameraDistance or setCameraDistance
    fn(next_v)
    if options.saveOnIncrement then settings.save() end
    add_text((isBattle and 'Battle ' or '') .. 'Distance changed to ' .. next_v)
end

local function cmd_toggle_soi()
    options.saveOnIncrement = not options.saveOnIncrement
    settings.save()
    add_text('saveOnIncrement = ' .. tostring(options.saveOnIncrement))
end

local function cmd_toggle_acv()
    options.autoCalcVertSpeed = not options.autoCalcVertSpeed
    settings.save()
    add_text('autoCalcVertSpeed = ' .. tostring(options.autoCalcVertSpeed))
end

local function cmd_status()
    add_text('XICamera status')
    add_text('  cameraDistance:     ' .. options.distance)
    add_text('  battleDistance:     ' .. options.battleDistance)
    add_text('  battleRange:        ' .. options.battleRange)
    add_text('  battleRangeLocked:  ' .. tostring(options.battleRangeLocked))
    add_text('  horizontalPanSpeed: ' .. options.horizontalPanSpeed)
    add_text('  verticalPanSpeed:   ' .. options.verticalPanSpeed)
    local cameraTask = getCameraTask()
    if cameraTask ~= nil then
        add_text(string.format('  cameraY:            %.2f', cameraTask[0x48 / 4]))
        add_text(string.format('  referenceY:         %.2f', cameraTask[0x54 / 4]))
    end
    add_text('  autoCalcVertSpeed:  ' .. tostring(options.autoCalcVertSpeed))
    add_text('  saveOnIncrement:    ' .. tostring(options.saveOnIncrement))
end

local function cmd_help()
    add_text('XICamera — </camera | /cam | /xicamera | /xicam> ...')
    add_text('  d|distance <n>     set camera distance (default ' .. defaults.distance .. ')')
    add_text('  b|battle <n>       set battle camera distance (default ' .. defaults.battleDistance .. ')')
    add_text('  hs|hspeed <n>      set horizontal pan speed (default ' .. defaults.horizontalPanSpeed .. ')')
    add_text('  vs|vspeed <n>      set vertical pan speed (default ' .. defaults.verticalPanSpeed .. ', forces autoCalc off)')
    add_text('  vh|vheight <n>     snap camera height to character/reference height plus n')
    add_text('  br|brange <0-100>  set battle camera range, forces lock on')
    add_text('  bl|battlelock <on|off>  lock/unlock 360deg battle camera')
    add_text('  in|incr / de|decr  step camera distance by 1')
    add_text('  bin|bincr / bde|bdecr  step battle distance by 1')
    add_text('  soi|saveOnIncrement   toggle save-on-step')
    add_text('  acv|autoCalcVertSpeed toggle vertical-speed autocalc')
    add_text('  s|status           print current values')
end

-- Wire up to four command aliases (//camera, //cam, //xicamera, //xicam).
local commands = {
    command.new('camera'),
    command.new('cam'),
    command.new('xicamera'),
    command.new('xicam'),
}

for _, cmd in ipairs(commands) do
    cmd:register('distance',          cmd_distance,    '<n:number>')
    cmd:register('d',                 cmd_distance,    '<n:number>')
    cmd:register('battle',            cmd_battle,      '<n:number>')
    cmd:register('b',                 cmd_battle,      '<n:number>')
    cmd:register('hspeed',            cmd_hspeed,      '<n:number>')
    cmd:register('hs',                cmd_hspeed,      '<n:number>')
    cmd:register('vspeed',            cmd_vspeed,      '<n:number>')
    cmd:register('vs',                cmd_vspeed,      '<n:number>')
    cmd:register('vheight',           cmd_vheight,     '<n:number>')
    cmd:register('vh',                cmd_vheight,     '<n:number>')
    cmd:register('snapheight',        cmd_vheight,     '<n:number>')
    cmd:register('sh',                cmd_vheight,     '<n:number>')
    cmd:register('brange',            cmd_brange,      '<n:number>')
    cmd:register('br',                cmd_brange,      '<n:number>')
    cmd:register('battlelock',        cmd_battlelock,  '<state:string>')
    cmd:register('bl',                cmd_battlelock,  '<state:string>')
    cmd:register('incr',  function() cmd_step( 1, false) end)
    cmd:register('in',    function() cmd_step( 1, false) end)
    cmd:register('decr',  function() cmd_step(-1, false) end)
    cmd:register('de',    function() cmd_step(-1, false) end)
    cmd:register('bincr', function() cmd_step( 1, true ) end)
    cmd:register('bin',   function() cmd_step( 1, true ) end)
    cmd:register('bdecr', function() cmd_step(-1, true ) end)
    cmd:register('bde',   function() cmd_step(-1, true ) end)
    cmd:register('saveOnIncrement', cmd_toggle_soi)
    cmd:register('soi',             cmd_toggle_soi)
    cmd:register('autoCalcVertSpeed', cmd_toggle_acv)
    cmd:register('acv',               cmd_toggle_acv)
    cmd:register('status', cmd_status)
    cmd:register('s',      cmd_status)
    cmd:register('help',   cmd_help)
    cmd:register('h',      cmd_help)
end

-- Windower 5 currently has no first-class unload event, so we tie restore
-- to the GC of a sentinel object — the addon environment is collected on
-- unload, which triggers the finalizer.
local _gc_sentinel = ffi_new('int*')
ffi_gc(_gc_sentinel, restorePointers)

--[[
Copyright (c) 2026, Hokuten
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of XICamera nor the names of its contributors may
      be used to endorse or promote products derived from this software
      without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
