_addon.author   = 'Hokuten';
_addon.name     = 'camera';
_addon.version  = '0.0.1';

require 'common'

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_config =
{
    distance    = 6,
    cameraSpeed = 1.0,
    pauseOnEvent = true
};
local configs = default_config;
local readyToRender = false

local getPlayerPtr = function()
    local entity_map = AshitaCore:GetPointerManager():GetPointer('entitymap');
    if (entity_map == 0) then
        return nil;
    end
    -- Locate the player pointer..
    return ashita.memory.read_uint32(ashita.memory.read_uint32(entity_map) + (4 * GetPlayerEntity().TargetIndex));
end

local player = getPlayerPtr()
local runOnEvent = function()
    if not configs.pauseOnEvent then
        return true
    end

    if (player == nil) then
        return false;
    end
    
    local eventPointer = ashita.memory.read_uint32(player + 0xD4)
    return not (eventPointer ~= 0)
end

----------------------------------------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------------------------------------
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

local rootCameraAddress = 0
local cameraSpeedAdjustment
local codeCave
local caveJmpCavePoint
local pointerToCamera

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.register_event('load', function()
    -- Load the configuration file..
    configs = ashita.settings.load_merged(_addon.path .. '/settings/settings.json', configs);

    -- Create location to store vertical camera speed adjustment
    cameraSpeedAdjustment = ashita.memory.alloc(4);
    ashita.memory.write_float(cameraSpeedAdjustment, configs.cameraSpeed);
    
    -- Create code cave to adjust vertical camera move speed
    codeCave = ashita.memory.alloc(17)
    
    ashita.memory.unprotect(codeCave, 17)
    ashita.memory.write_array(codeCave, codeCaveValues)
    
    -- Push in pointer to Camera Speed into the Code Cave
    ashita.memory.write_uint32(codeCave + 0x02, cameraSpeedAdjustment)
    
    -- Get the point where we are injecting code to jump to code cave
    caveJmpCavePoint = ashita.memory.findpattern('FFXiMain.dll', 0, 'D84C24248B168BCED80D', 0, 0);
    if (caveJmpCavePoint == 0) then error('Failed to locate critical signature #1!'); end
    
    -- Push in pointer to the return point into the Code Cave
    ashita.memory.write_int32(codeCave + 0x0D, (caveJmpCavePoint + 0x06) - (codeCave + 0x0C) - 0x05)
    
    -- Set up the Jump to the Code Cave    
    ashita.memory.write_uint8(caveJmpCavePoint, 0xE9)
    ashita.memory.write_int32(caveJmpCavePoint + 0x01, (codeCave - caveJmpCavePoint - 0x05))
    ashita.memory.write_uint8(caveJmpCavePoint + 0x05, 0x90)
    
    local pointerToCameraPointer = ashita.memory.findpattern('FFXiMain.dll', 0, 'C8E878010000EB0233C08BC8A3', 0, 0);
    if (pointerToCameraPointer == 0) then error('Failed to locate critical signature #2!'); end
    
    pointerToCamera = ashita.memory.read_uint32(pointerToCameraPointer + 0x0D);
    if (pointerToCamera == 0) then error('Failed to locate critical signature #3!'); end
    
    readyToRender = true
end);

ashita.register_event('prerender', function()
    if pointerToCamera ~= 0 and runOnEvent() and readyToRender then
        rootCameraAddress = ashita.memory.read_uint32(pointerToCamera);

        if rootCameraAddress ~= 0 then
            local focal_x = ashita.memory.read_float(rootCameraAddress + 0x50)
            local focal_z = ashita.memory.read_float(rootCameraAddress + 0x54)
            local focal_y = ashita.memory.read_float(rootCameraAddress + 0x58)
            
            local diff_x = ashita.memory.read_float(rootCameraAddress + 0x44) - focal_x
            local diff_z = ashita.memory.read_float(rootCameraAddress + 0x48) - focal_z
            local diff_y = ashita.memory.read_float(rootCameraAddress + 0x4C) - focal_y
            
            local distance = 1 / math.sqrt(diff_x * diff_x + diff_z * diff_z + diff_y * diff_y) * configs.distance
            
            ashita.memory.write_float(rootCameraAddress + 0x44, diff_x * distance + focal_x)
            ashita.memory.write_float(rootCameraAddress + 0x48, diff_z * distance + focal_z)
            ashita.memory.write_float(rootCameraAddress + 0x4C, diff_y * distance + focal_y)
        end
    end
end);

ashita.register_event('incoming_packet', function(id, size, packet, packet_modified, blocked)
    if id == 0x00A then -- zone in packet
        ashita.timer.once(5, function()
            player = getPlayerPtr()
        end)
        readyToRender = true
    elseif (id == 0x04B) then -- logout acknowledgment
        readyToRender = false
    end

    return false
end);

local setCameraSpeed = function(newSpeed)
    ashita.memory.write_float(cameraSpeedAdjustment, newSpeed);
    configs.cameraSpeed = newSpeed
end

ashita.register_event('command', function(command, ntype)
    local command_args = command:lower():args()
    if table.hasvalue({'/camera', '/cam', '/xicamera', '/xicam'}, command_args[1]) then
        if table.hasvalue({'distance', 'd'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
                configs.distance = newDistance
                setCameraSpeed(newDistance / 6.0)
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs);
                print("Distance changed to " .. newDistance)
            end
        elseif (command_args[2] == 'start')  then
            readyToRender = true
        elseif (command_args[2] == 'stop')  then
            readyToRender = false
        elseif (command_args[2] == 'pauseonevent')  then
            local newSetting
            if table.hasvalue({'true', 't'}, command_args[3]) then
                newSetting = true
            elseif table.hasvalue({'false', 'f'}, command_args[3]) then
                newSetting = false
            elseif command_args[3] == nil then
                newSetting = not configs.pauseOnEvent
            end
            
            if newSetting ~= nil then
                configs.pauseOnEvent = newSetting
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs);
                print("Pause on event setting changed to " .. tostring(configs.pauseOnEvent))
            end
        elseif table.hasvalue({'help', 'h'}, command_args[2]) then
            print("Set Distance: </camera|/cam> <distance|d> <###>")
            print("Set Pause on event: </camera|/cam> <pauseonevent> [t|true|f|false]")
            print("Start/Stop: </camera|/cam> <start|stop>")
        elseif command_args[2] == 'derp' then
            local player = getPlayerPtr()
            local eventPointer = ashita.memory.read_uint32(player + 0xD4)
            print(tostring(eventPointer))
        end
    end

    return false
end)

----------------------------------------------------------------------------------------------------
-- func: unload
-- desc: Event called when the addon is being unloaded.
----------------------------------------------------------------------------------------------------
ashita.register_event('unload', function()
   -- Save the configuration file..
    ashita.settings.save(_addon.path .. '/settings/settings.json', configs);
    
    if (caveJmpCavePoint ~= 0 and caveJmpCavePoint ~= nil) then
        ashita.memory.write_array(caveJmpCavePoint, originalValues)
    end
    if (cameraSpeedAdjustment ~= 0 and cameraSpeedAdjustment ~= nil) then
        ashita.memory.dealloc(cameraSpeedAdjustment, 4)
    end
    if (codeCave ~= 0 and codeCave ~= nil) then
        ashita.memory.dealloc(codeCave, 17)
    end
end);
