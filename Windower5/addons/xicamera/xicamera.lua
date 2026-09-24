--[[
    XICamera — Windower 5 addon

    Adjusts camera distance, pan speed, jitter, battle range, and the
    battle-camera lock by patching FFXiMain.dll. The patch logic is the
    shared xicamera_core.lua next to this file; this file supplies the
    Windower 5 memory adapter, settings and commands.
]]

local chat       = require('core.chat')
local command    = require('core.command')
local ffi        = require('ffi')
local scanner    = require('core.scanner')
local settings   = require('settings')
local win32      = require('win32')
local Core       = require('xicamera_core')

local ffi_new   = ffi.new
local ffi_cast  = ffi.cast
local add_text  = chat.add_text

-- ---------------------------------------------------------------------------
-- Win32 imports for page protection and the float block.
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
local GetModuleHandleA = win32.def({
    name = 'GetModuleHandleA',
    returns = 'void*',
    parameters = { 'const char*' },
    failure = false
})

local PAGE_EXECUTE_READWRITE = 0x40

-- The block that holds XICamera's floats. Other tools may keep pointers into it after this
-- addon unloads, so the heap is created once per process and never destroyed.
local cave_heap = HeapCreate(0x40000, 0, 0)

local function addressOf(p)
    if p == nil then return 0 end
    return tonumber(ffi_cast('uintptr_t', p))
end

-- Writes go through a temporary RWX window on the page and restore the old protection.
local function protectedWrite(address, size, fn)
    local old = ffi_new('DWORD[1]')
    local p = ffi_cast('void*', address)
    VirtualProtect(p, size, PAGE_EXECUTE_READWRITE, old)
    fn()
    local ignored = ffi_new('DWORD[1]')
    VirtualProtect(p, size, old[0], ignored)
end

local mem = {
    find = function(sig)
        local p = scanner.scan(sig)
        return addressOf(p)
    end,
    read_u16    = function(a) return ffi_cast('uint16_t*', a)[0] end,
    read_u32    = function(a) return tonumber(ffi_cast('uint32_t*', a)[0]) end,
    read_float  = function(a) return ffi_cast('float*', a)[0] end,
    write_u16   = function(a, v) protectedWrite(a, 2, function() ffi_cast('uint16_t*', a)[0] = v end) end,
    write_u32   = function(a, v) protectedWrite(a, 4, function() ffi_cast('uint32_t*', a)[0] = v end) end,
    write_float = function(a, v) protectedWrite(a, 4, function() ffi_cast('float*', a)[0] = v end) end,
    alloc       = function(size) return addressOf(HeapAlloc(cave_heap, 8, size)) end,   -- HEAP_ZERO_MEMORY
    log         = function(text) add_text('[xicamera] ' .. text) end,
}
do
    local module = GetModuleHandleA('FFXiMain.dll')
    local base = addressOf(module)
    if base ~= 0 then
        local lfanew = mem.read_u32(base + 0x3C)
        mem.image_base = base
        mem.image_size = mem.read_u32(base + lfanew + 0x50)
    end
end

local core = Core.new(mem)

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
-- Mutators (mirror the Ashita 4 lua addon's surface)
-- ---------------------------------------------------------------------------

local function setHorizontalPanSpeed(newSpeed)
    options.horizontalPanSpeed = newSpeed
    core:setHorizontalPanSpeed(newSpeed)
end

local function setVerticalPanSpeed(newSpeed)
    options.verticalPanSpeed = newSpeed
    core:setVerticalPanSpeed(newSpeed)
end

local function setCameraDistance(newDistance)
    options.distance = newDistance
    core:setCameraDistance(newDistance)
    if options.autoCalcVertSpeed then
        setVerticalPanSpeed(defaults.verticalPanSpeed * newDistance / 6.0)
    end
end

local function setBattleCameraDistance(newDistance)
    options.battleDistance = newDistance
    core:setBattleDistance(newDistance)
end

local function setBattleCameraRange(newRange)
    options.battleRange = math.min(math.max(0, tonumber(newRange) or 0), 100)
    core:setBattleRange(options.battleRange)
end

local function setBattleRangeLock(isLocked)
    options.battleRangeLocked = isLocked
    core:setBattleRangeLock(isLocked)
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
-- Commands
-- ---------------------------------------------------------------------------

local function requireNumber(value, syntax)
    local n = tonumber(value)
    if n == nil then add_text('[xicamera] usage: ' .. syntax) end
    return n
end

local function printStatus()
    add_text('[xicamera] status')
    add_text('  active: ' .. tostring(core:active()))
    add_text('  cameraDistance: ' .. tostring(options.distance))
    add_text('  battleDistance: ' .. tostring(options.battleDistance))
    add_text('  battleRange: ' .. tostring(options.battleRange))
    add_text('  horizontalPanSpeed: ' .. tostring(options.horizontalPanSpeed))
    add_text('  verticalPanSpeed: ' .. tostring(options.verticalPanSpeed))
    local cameraY, referenceY = core:cameraHeights()
    if cameraY then
        add_text(string.format('  cameraY: %.2f', cameraY))
        add_text(string.format('  referenceY: %.2f', referenceY))
    end
    add_text('  battleRangeLocked: ' .. tostring(options.battleRangeLocked))
    add_text('  saveOnIncrement: ' .. tostring(options.saveOnIncrement))
    add_text('  autoCalcVertSpeed: ' .. tostring(options.autoCalcVertSpeed))
    for _, site in ipairs(core:status(true)) do
        if site.state ~= 'patched' then
            add_text(string.format('  %s: %s%s', site.name, site.state, site.note and (' (' .. site.note .. ')') or ''))
        end
    end
end

local function printHelp()
    add_text('[xicamera] commands (//camera, //cam, //xicamera, //xicam):')
    add_text('  d|distance #        camera distance (default 6)')
    add_text('  b|battle #          battle camera distance (default 8.2)')
    add_text('  hs|hspeed #         horizontal pan speed (default 3)')
    add_text('  vs|vspeed #         vertical pan speed (default 10.7); turns auto calc off')
    add_text('  vh|vheight #        snap camera height to reference height plus #')
    add_text('  br|brange #         battle camera range 0..100 (default 4); turns the lock on')
    add_text('  bl|battlelock on|off  lock or unlock the battle camera range')
    add_text('  in|incr, de|decr, bin|bincr, bde|bdecr   step the distances by 1')
    add_text('  soi|saveOnIncrement  toggle saving on step commands')
    add_text('  acv|autoCalcVertSpeed  toggle vertical pan speed auto calc')
    add_text('  s|status            print status')
end

local function cmd_distance(arg)
    local n = requireNumber(arg, 'distance <number>')
    if n then setCameraDistance(n) settings.save() add_text('Distance changed to ' .. n) end
end

local function cmd_battle(arg)
    local n = requireNumber(arg, 'battle <number>')
    if n then setBattleCameraDistance(n) settings.save() add_text('Battle distance changed to ' .. n) end
end

local function cmd_hspeed(arg)
    local n = requireNumber(arg, 'hspeed <number>')
    if n then setHorizontalPanSpeed(n) settings.save() add_text('Horizontal pan speed changed to ' .. n) end
end

local function cmd_vspeed(arg)
    local n = requireNumber(arg, 'vspeed <number>')
    if n then
        options.autoCalcVertSpeed = false
        setVerticalPanSpeed(n) settings.save() add_text('Vertical pan speed changed to ' .. n)
    end
end

local function cmd_vheight(arg)
    local n = requireNumber(arg, 'vheight <offset>')
    if not n then return end
    local cameraY, referenceY = core:snapHeight(n)
    if cameraY then
        add_text(string.format('Camera height snapped to %.2f (reference %.2f + %.2f)', cameraY, referenceY, n))
    else
        add_text('[xicamera] WARN: camera task not available; vertical snap failed')
    end
end

local function cmd_brange(arg)
    local n = requireNumber(arg, 'brange <number>')
    if n then
        setBattleRangeLock(true) setBattleCameraRange(n) settings.save()
        add_text('Battle camera range changed to ' .. options.battleRange)
    end
end

local function cmd_battlelock(arg)
    local v = tostring(arg):lower()
    if v == 'on' or v == 'true' or v == '1' then
        setBattleRangeLock(true) settings.save() add_text('Battle camera range locked.')
    elseif v == 'off' or v == 'false' or v == '0' then
        setBattleRangeLock(false) settings.save() add_text('Battle camera range unlocked.')
    end
end

local function cmd_step(direction, isBattle)
    local current = isBattle and options.battleDistance or options.distance
    local next_v  = current + (direction > 0 and 1 or -1)
    if isBattle then setBattleCameraDistance(next_v) else setCameraDistance(next_v) end
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
    if options.autoCalcVertSpeed then setCameraDistance(options.distance) end
    settings.save()
    add_text('autoCalcVertSpeed = ' .. tostring(options.autoCalcVertSpeed))
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
    cmd:register('status', printStatus)
    cmd:register('s',      printStatus)
    cmd:register('help',   printHelp)
    cmd:register('h',      printHelp)
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

if core:install() then
    add_text('[xicamera] loaded. Try //camera status')
else
    local off = {}
    for _, g in ipairs(core:groupStatus()) do
        if g.required and not g.enabled then off[#off + 1] = g.name end
    end
    add_text('[xicamera] WARN: not every patch group is in (' .. table.concat(off, ', ') .. '); see //camera status')
end
applyAll()
settings.save()

-- Windower 5 currently has no first-class unload event, so we tie restore
-- to the GC of a sentinel object: the addon environment is collected on
-- unload, which triggers the finalizer.
local _gc_sentinel = ffi_new('int*')
ffi.gc(_gc_sentinel, function()
    settings.save()
    core:uninstall()
end)

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
