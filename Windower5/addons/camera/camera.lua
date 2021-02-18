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
local ptr = struct_lib.ptr
local struct = struct_lib.struct
local array = struct_lib.array
local float = struct_lib.float
local uint32 = struct_lib.uint32

local defaults = {
    distance = 6,
    cameraSpeed = 1.0,
    pauseOnEvent = true
}
local options = settings.load(defaults)

local entity_event = struct({ event_ptr = {0xD4, ptr()} })
memory.entity_events = array({signature = '8B560C8B042A8B0485'}, ptr(entity_event), 0x900)

local readyToRender = false
local runOnEvent = function()
    local player_event = memory.entity_events[player.index]
    return not (options.pauseOnEvent and player_event ~= nil and player_event.event_ptr ~= nil)
end

local logToFile = function(stringToLog, boolPrint)
    local file = io.open(windower.user_path .. '\\cameralog.txt', "a");
    file:write(tostring(stringToLog), "\n");
    file:close(file);
    
    if boolPrint then
        print(stringToLog)
    end
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

 -- Create memory location to store Camera Speed
 local cameraSpeedAdjustmentHeap = ffi_gc(ffi_C.HeapCreate(0x40000, 0, 0), function(heap)
     destroyed = true
     ffi_C.HeapDestroy(cameraSpeedAdjustmentHeap)
 end)

 -- Allocate and set Camera speed based on settings
local cameraSpeedAdjustment_Ptr = ffi_cast('float*', ffi_C.HeapAlloc(cameraSpeedAdjustmentHeap, 8, ffi.sizeof('float')))
cameraSpeedAdjustment_Ptr[0] = ffi_new('float', options.cameraSpeed)

 -- Push in pointer to Camera Speed into the Code Cave
 local camSpeedInCave = ffi_cast('float**',codeCave + 0x02)
 camSpeedInCave[0] = cameraSpeedAdjustment_Ptr; -- Push cam speed pointer into code cave

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
local vector_3f = struct({
    x = {0x0, float},
    z = {0x4, float},
    y = {0x8, float},
})
local camera = struct({
    position = {0x44, vector_3f},
    focal    = {0x44, vector_3f}
})
local pointerToCamera = struct({
    camera = {0x0, ptr(camera)}
})
memory.pointerToCameraPointer = struct({signature = 'C8E878010000EB0233C08BC8A3'}, {
    --camera    = {0x0, ptr(rootCamera)}
    pointerToCamera = {0x0, pointerToCamera}
})

local ptrToCamera = memory.pointerToCameraPointer.pointerToCamera
readyToRender = true

local coroutine_sleep_frame = coroutine.sleep_frame
--ui.display(function()
coroutine.schedule(function()
    while(true) do
        if readyToRender and runOnEvent() and ptrToCamera and ptrToCamera.camera ~= nil then
            local camera = ptrToCamera.camera
            local diff_x = camera.position.x - camera.focal.x
            local diff_z = camera.position.z - camera.focal.z
            local diff_y = camera.position.y - camera.focal.y

            local distance = 1 / math.sqrt(diff_x * diff_x + diff_z * diff_z + diff_y * diff_y) * options.distance
            camera.position.x = diff_x * distance + camera.focal.x
            camera.position.z = diff_z * distance + camera.focal.z
            camera.position.y = diff_y * distance + camera.focal.y
        end
        coroutine_sleep_frame()
    end
end)

local restorePointers = function()
    for i = 1, #originalValues do
        caveJmpPoint[i-1] = originalValues[i]
    end
end

account.login:register(function ()
    coroutine.schedule(function()
        readyToRender = true;
    end, 5);
end)
account.logout:register(function()
    readyToRender = false;
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

local startRender = function()
    readyToRender = true
    add_text("Starting distance adjustment")
end

local stopRender = function()
    readyToRender = true
    add_text("Stopping distance adjustment")
end

local setPauseOnEvent = function(pauseOnEvent)
    local newSetting
    if pauseOnEvent == 't' or pauseOnEvent == 'true' then
        newSetting = true
    elseif pauseOnEvent == 'f' or pauseOnEvent == 'false' then
        newSetting = false
    elseif pauseOnEvent == nil then
        newSetting = not options.pauseOnEvent
    end
    
    if newSetting ~= nil then
        options.pauseOnEvent = newSetting
        settings.save()
        add_text("Pause on event setting changed to " .. tostring(options.pauseOnEvent))
    end
end

local displayHelp = function()
    add_text("Set Distance: </camera|/cam> <distance|d> <###>")
    add_text("Set Pause on event: </camera|/cam> <pauseonevent> [t|true|f|false]")
    add_text("Start/Stop: </camera|/cam> <start|stop>")
end

camera:register('distance', setDistance, '<newDistance:integer>')
camera:register('d', setDistance, '<newDistance:integer>')
cam:register('distance', setDistance, '<newDistance:integer>')
cam:register('d', setDistance, '<newDistance:integer>')
cam:register('start', startRender)
cam:register('stop', stopRender)
cam:register('pauseonevent', setPauseOnEvent, '[pauseOnEvent:one_of(t,true,f,false)]')
cam:register('help', displayHelp)
cam:register('h', displayHelp)

--TODO replace with unload event
gc_global = ffi_new('int*')
ffi_gc(gc_global, restorePointers)

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
