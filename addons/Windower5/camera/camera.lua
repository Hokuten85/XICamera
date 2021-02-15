local settings = require('settings')
local table = require('table')
local chat = require('core.chat')
local ffi = require('ffi')
local scanner = require('core.scanner')
local math = require('math')
local ui = require('core.ui')
local command = require('core.command')

ffi.cdef[[
    void* HeapAlloc(void*, uint32_t, size_t);
    bool HeapFree(void*, uint32_t, void*);
    void* HeapCreate(uint32_t, size_t, size_t);
    bool HeapDestroy(void*);
]]

local ffi_new = ffi.new
local ffi_gc = ffi.gc
local ffi_cast = ffi.cast
local ffi_C = ffi.C
local add_text = chat.add_text
local defaults = {
    distance = 6,
    cameraSpeed = 1.0
}
local options = settings.load(defaults)

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

-- Create memory location to store Camera Speed
local cameraSpeedAdjustmentHeap = ffi_gc(ffi_C.HeapCreate(0, 0, 0), function(heap)
    destroyed = true
    ffi_C.HeapDestroy(cameraSpeedAdjustmentHeap)
end)

-- Allocate and set Camera speed based on settings
local cameraSpeedAdjustment_Ptr = ffi_cast('float*', ffi_C.HeapAlloc(cameraSpeedAdjustmentHeap, 8, ffi.sizeof('float')))
cameraSpeedAdjustment_Ptr[0] = ffi_new('float', options.cameraSpeed)

--Create memory location to store Code Cave
local codeCaveHeap = ffi_gc(ffi_C.HeapCreate(0x40000, 0, 0), function(heap)
    destroyed = true
    ffi_C.HeapDestroy(codeCaveHeap)
end)

-- Allocate the space for the Code Cave
local codeCave = ffi_cast('uint8_t*', ffi_C.HeapAlloc(codeCaveHeap, 8, 17))

-- Populate general structure of code cave
for i = 1, #codeCaveValues do
    codeCave[i-1] = codeCaveValues[i]
end

-- Push in pointer to Camera Speed into the Code Cave
local camSpeedInCave = ffi_cast('float**',codeCave + 0x02)
camSpeedInCave[0] = cameraSpeedAdjustment_Ptr; -- Push cam speed pointer into code cave

-- Get the point where we are injecting code to jump to code cave
local caveJmpCavePoint = ffi_cast('uint8_t*', scanner.scan('&D84C24248B168BCED80D'))

-- Push in pointer to the return point into the Code Cave
local returnJmpPoint = ffi_cast('uint8_t*', codeCave + 0x0C)
local returnJmpOffset = ffi_cast('int32_t*', returnJmpPoint + 0x01)
returnJmpOffset[0] = (caveJmpCavePoint + 0x06) - (returnJmpPoint) - 0x05

-- Get point where we are going to push in Pointer for where the Code Cave is
 local caveJmpOffset = ffi_cast('int32_t*', caveJmpCavePoint + 0x01)

-- Set up the Jump to the Code Cave
caveJmpCavePoint[0] = 0xE9
caveJmpOffset[0] = (codeCave - caveJmpCavePoint - 0x05)
caveJmpCavePoint[5] = 0x90

--###################################################
--# Camera Distance
--###################################################

local pointerToCameraPointer = ffi_cast('uint8_t*', scanner.scan('&C8E878010000EB0233C08BC8A3'))
local pointerToCamera = ffi_cast('uint32_t*', pointerToCameraPointer + 0x0D)
local rootCameraAddress = ffi_cast('uint8_t*', ffi_cast('uint32_t*', pointerToCamera[0])[0])

local camera_x_ptr = ffi_cast('float*',rootCameraAddress + 0x44)
local camera_z_ptr = ffi_cast('float*',rootCameraAddress + 0x48)
local camera_y_ptr = ffi_cast('float*',rootCameraAddress + 0x4C)

local focal_x_ptr = ffi_cast('float*',rootCameraAddress + 0x50)
local focal_z_ptr = ffi_cast('float*',rootCameraAddress + 0x54)
local focal_y_ptr = ffi_cast('float*',rootCameraAddress + 0x58)

ui.display(function()
    local focal_x = focal_x_ptr[0]
    local focal_z = focal_z_ptr[0]
    local focal_y = focal_y_ptr[0]
    
    local diff_x = camera_x_ptr[0] - focal_x
    local diff_z = camera_z_ptr[0] - focal_z
    local diff_y = camera_y_ptr[0] - focal_y
    
    local distance = 1 / math.sqrt(diff_x * diff_x + diff_z * diff_z + diff_y * diff_y) * options.distance
    camera_x_ptr[0] = diff_x * distance + focal_x
    camera_z_ptr[0] = diff_z * distance + focal_z
    camera_y_ptr[0] = diff_y * distance + focal_y
end)

--###################################################
--# Commands
--###################################################

local camera = command.new('camera')
local cam = command.new('cam')

local setCameraSpeed = function(newSpeed)
    cameraSpeedAdjustment_Ptr[0] = newSpeed
    options.cameraSpeed = newSpeed
end

local setDistance = function(newDistance)
    local num = tonumber(newDistance)
    if num ~= nil then
        options.distance = num
        setCameraSpeed(num / 6.0)
        settings.save()
        add_text("Distance changed to " .. newDistance)
    end
end

camera:register('distance', setDistance, '<newDistance:integer>')
camera:register('d', setDistance, '<newDistance:integer>')
cam:register('distance', setDistance, '<newDistance:integer>')
cam:register('d', setDistance, '<newDistance:integer>')

--TODO replace with unload event
gc_global = ffi_new('int*')

ffi_gc(gc_global, function()
    for i = 1, #originalValues do
        caveJmpCavePoint[i-1] = originalValues[i]
    end
end)

--[[
Copyright © 2021, Hokuten
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
