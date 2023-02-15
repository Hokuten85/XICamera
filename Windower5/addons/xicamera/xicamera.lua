local account = require('account')
local chat = require('core.chat')
local command = require('core.command')
local ffi = require('ffi')
local io = require('io')
local math = require('math')
local memory = require('memory')
local player = require('player')
local scanner = require('core.scanner')
local settings = require('settings')
local struct_lib = require('struct')
local windower = require('core.windower')
local win32 = require('win32')
local enumerable = require('enumerable')

local ffi_new = ffi.new
local ffi_gc = ffi.gc
local ffi_cast = ffi.cast
local ffi_C = ffi.C
local add_text = chat.add_text
local ptr = struct_lib.ptr
local struct = struct_lib.struct
local float = struct_lib.float
local uint32 = struct_lib.uint32
local bool = struct_lib.bool

local HeapAlloc = win32.def({
    name = 'HeapAlloc',
    returns = 'void*',
    parameters = {
        'void*',
        'uint32_t',
        'size_t'
    },
    failure = false
})
local HeapFree = win32.def({
    name = 'HeapFree',
    returns = 'bool',
    parameters = {
        'void*',
        'uint32_t',
        'void*'
    },
    failure = false
})
local HeapCreate = win32.def({
    name = 'HeapCreate',
    returns = 'void*',
    parameters = {
        'uint32_t',
        'size_t',
        'size_t'
    },
    failure = false
})
local HeapDestroy = win32.def({
    name = 'HeapDestroy',
    returns = 'bool',
    parameters = {
        'void*'
    },
    failure = false
})
local VirtualProtect = win32.def({
    name = 'VirtualProtect',
    returns = 'bool',
    parameters = {
        'void*',
        'size_t',
        'DWORD',
        'PDWORD'
    },
    failure = false
})

local defaults = {
    distance = 6,
    cameraSpeed = 1.0,
    battleDistance = 8.2
}
local options = settings.load(defaults)

local minDistance
local originalMinDistance
local maxDistance
local originalMaxDistance
local minBattleDistance
local originalMinBattleDistance
local maxBattleDistance
local originalMaxBattleDistance
local zoomOnZoneInSetup
local walkAnimation
local npcWalkAnimation

local setCameraDistance = function(newDistance)
	options.distance = newDistance
	minDistance.val = newDistance - (originalMaxDistance - originalMinDistance)
	maxDistance.val = newDistance
end

local setBattleCameraDistance = function(newDistance)
	options.battleDistance = newDistance
	minBattleDistance.val = newDistance - (originalMaxBattleDistance - originalMinBattleDistance)
	maxBattleDistance.val = newDistance
end

--###################################################
--# SET UP Camera Speed Adjustment
--###################################################
local originalValues = {
    0xD8, 0x4C, 0x24, 0x24, -- fmul dword ptr [esp+24]
    0x8B, 0x16, -- mov edx,[esi]
}

local codeCaveValues = {
    0xD8, 0x05, 0x00, 0x00, 0x00, 0x00, -- fadd dword ptr [00000000]
    0xD8, 0x4C, 0x24, 0x24, -- fmul dword ptr [esp+24]
    0x8B, 0x16, -- mov edx,[esi]
    0xE9, 0x00, 0x00, 0x00, 0x00 -- jmp to return point
}

local try = function(d, e)
    if d == false then
        error(e.ErrorMsg)
    end
    return d
end

--Create memory location to store Code Cave
local codeCaveHeap = try(ffi_gc(HeapCreate(0x40000, 0, 0), function(heap)
    destroyed = true
    HeapDestroy(codeCaveHeap)
end), {ErrorMsg = "Failed to create memory location for code cave."})

-- Allocate the space for the Code Cave
local codeCave = ffi_cast('uint8_t*', try(HeapAlloc(codeCaveHeap, 8, 17), {ErrorMsg = "Failed to allocate memory for code cave."}))

-- Populate general structure of code cave
for i = 1, #codeCaveValues do
    codeCave[i-1] = codeCaveValues[i]
end

-- Create memory location to store Camera Speed
local cameraSpeedAdjustmentPtr = ffi_new('float*', ffi_new('float[?]', 0))
cameraSpeedAdjustmentPtr[0] = tonumber(options.cameraSpeed)

-- Push in pointer to Camera Speed into the Code Cave
local camSpeedInCave = ffi_cast('float**',codeCave + 0x02)
camSpeedInCave[0] = cameraSpeedAdjustmentPtr; -- Push cam speed pointer into code cave

-- Get the point where we are injecting code to jump to code cave
local caveJmpPoint = ffi_cast('uint8_t*', scanner.scan('&D84C24248B168BCED80D'))

-- Push in pointer to the return point into the Code Cave
 local returnJmpOffset = ffi_cast('int32_t*', codeCave + 0x0D)
returnJmpOffset[0] = (caveJmpPoint + 0x06) - (codeCave + 0x0C) - 0x05

-- Get point where we are going to push in Pointer for where the Code Cave is
 local caveJmpOffset = ffi_cast('int32_t*', caveJmpPoint + 0x01)

-- Set up the Jump to the Code Cave
caveJmpPoint[0] = 0xE9
caveJmpOffset[0] = (codeCave - caveJmpPoint - 0x05)
caveJmpPoint[5] = 0x90

--###################################################
--# Camera Distance
--###################################################
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

minDistance = memory.minDistance
originalMinDistance = minDistance.val

maxDistance = memory.maxDistance
originalMaxDistance = maxDistance.val

minBattleDistance = memory.minBattleDistance
originalMinBattleDistance = maxDistance.val

maxBattleDistance = memory.maxBattleDistance
originalMaxBattleDistance = maxBattleDistance.val

try(VirtualProtect(ffi_cast('void*', minDistance), 4, 0x04, ffi_new('DWORD[?]', 0)), {ErrorMsg = "Failed to remove minDistance Write Protection."})
try(VirtualProtect(ffi_cast('void*', maxDistance), 4, 0x04, ffi_new('DWORD[?]', 0)), {ErrorMsg = "Failed to remove maxDistance Write Protection."})
try(VirtualProtect(ffi_cast('void*', minBattleDistance), 4, 0x04, ffi_new('DWORD[?]', 0)), {ErrorMsg = "Failed to remove minBattleDistance Write Protection."})
try(VirtualProtect(ffi_cast('void*', maxBattleDistance), 4, 0x04, ffi_new('DWORD[?]', 0)), {ErrorMsg = "Failed to remove maxBattleDistance Write Protection."})

-- Setup new distance memory location
local newMinDistanceConstant = ffi_new('float*', ffi_new('float[?]', 0))
newMinDistanceConstant[0] = originalMinDistance

-- -- --###################################################
-- -- --# Zoom on zone-in setup?
-- -- --###################################################
zoomOnZoneInSetup = ffi_cast('float**', scanner.scan('85C0741AD9442404D80D????????D80D&????????D87C'))
zoomOnZoneInSetup[0] = newMinDistanceConstant

-- --###################################################
-- --# Walk Animation
-- --###################################################
walkAnimation = ffi_cast('float**', scanner.scan('0F85????????D80D&????????D913D81D'))
walkAnimation[0] = newMinDistanceConstant

-- --###################################################
-- --# NPC Walk Animation
-- --###################################################
npcWalkAnimation = ffi_cast('float**', scanner.scan('7514D9442410D80D&????????D91B8B8E'))
npcWalkAnimation[0] = newMinDistanceConstant

-- --###################################################
-- --# SET CAMERA DISTANCE BASED ON options
-- --###################################################
setCameraDistance(options.distance)
setBattleCameraDistance(options.battleDistance)

--###################################################
--# Restore logic on unload
--###################################################

local restorePointers = function()
    for i = 1, #originalValues do
        caveJmpPoint[i-1] = originalValues[i]
    end
	
	if (minDistance ~= 0 and minDistance ~= nil) then
		minDistance.val = originalMinDistance
	end
	if (maxDistance ~= 0 and maxDistance ~= nil) then
		maxDistance.val = originalMaxDistance
	end
	if (minBattleDistance ~= 0 and minBattleDistance ~= nil) then
		minBattleDistance.val = originalMinBattleDistance
	end
	if (battleMaxDistance ~= 0 and battleMaxDistance ~= nil) then
		battleMaxDistance.val = originalMaxBattleDistance
	end
	
	if (zoomOnZoneInSetup ~= 0 and zoomOnZoneInSetup ~= nil) then
		zoomOnZoneInSetup[0] = ffi_cast("float*", minDistance)
	end
    if (walkAnimation ~= 0 and walkAnimation ~= nil) then
		walkAnimation[0] = ffi_cast("float*", minDistance)
	end
    if (npcWalkAnimation ~= 0 and npcWalkAnimation ~= nil) then
		npcWalkAnimation[0] = ffi_cast("float*", minDistance)
	end
end

--###################################################
--# Commands
--###################################################
local setCameraSpeed = function(newSpeed)
    cameraSpeedAdjustmentPtr[0] = newSpeed
    options.cameraSpeed = newSpeed
end

local setDistance = function(newDistance)
    local num = tonumber(newDistance)
    if num ~= nil then
        setCameraDistance(newDistance)
        setCameraSpeed(num / 6.0)
        settings.save()
        add_text("Distance changed to " .. newDistance)
    end
end

local setBattleDistance = function(newDistance)
    local num = tonumber(newDistance)
    if num ~= nil then
        setBattleCameraDistance(newDistance)
        settings.save()
        add_text("Distance changed to " .. newDistance)
    end
end

local displayHelp = function()
    add_text("</xicamera | /camera | /xicam | /cam>")
    add_text("Set Distance: <distance|d> <###>")
    add_text("Set Battle Distance: <battle|b> <###>")
    add_text("Set Battle Distance: <battle|b> <###>")
    add_text("Displays status: <status|s>")
end

local displayStatus = function()
    add_text("- status")
	add_text("-  cameraDistance: " .. maxDistance.val)
	add_text("-  battleDistance: " .. maxBattleDistance.val)
end

local camera = command.new('camera')
local cam = command.new('cam')
local xicamera = command.new('xicamera')
local xicam = command.new('xicam')

-- define chat functions 
enumerable.all({camera, cam,  xicamera, xicam}, function(cmd)
    enumerable.all({'distance', 'd'}, function (fn) cmd:register(fn, setDistance, '<newDistance:integer>') end)
    enumerable.all({'battle', 'b'}, function (fn) cmd:register(fn, setBattleDistance, '<newDistance:integer>') end)
    enumerable.all({'help', 'h'}, function (fn) cmd:register(fn, displayHelp) end)
    enumerable.all({'status', 's'}, function (fn) cmd:register(fn, displayStatus) end)
end)

--TODO replace with unload event
gc_global = ffi_new('int*')
ffi_gc(gc_global, restorePointers)

--[[
Copyright © 2022, Hokuten
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Chiaia nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Chiaia BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
