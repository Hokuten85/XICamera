addon.author   = 'Hokuten';
addon.name     = 'camera';
addon.version  = '0.0.1';
addon.desc     = 'Modifies the camera distance from the player.';

local common = require('common');
local ffi = require('ffi');

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_settings = T{
    distance    = 6,
    cameraSpeed = 1.0,
    pauseOnEvent = true
};
local settings = default_settings;

local entity = AshitaCore:GetMemoryManager():GetEntity();
local player = GetPlayerEntity();
local readyToRender = false

local runOnEvent = function()
    player = GetPlayerEntity();
    if (player == nil) then
        return false;
    end
    
    return not (settings.pauseOnEvent and entity:GetEventPointer(player.TargetIndex) ~= 0)
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

local speedAdjustment_ptr
local codeCave_ptr
local injectionPoint_ptr
local ptrToBaseCamera_ptr

----------------------------------------------------------------------------------------------------
-- config helpers
----------------------------------------------------------------------------------------------------

--[[
* Load an existing addon configuration and merge it with the provided defaults.
* Returns the a table containing the merged configuration.
*
* @param {defaults} - a table holding the default settings
]]--
local load_merged_settings = function(defaults)
    local config = AshitaCore:GetConfigurationManager();
    local ini_file = string.format('%s.ini', addon.name);
    local s = defaults:copy(true);
    if (config:Load(addon.name, ini_file)) then
        s.distance     = config:GetFloat(addon.name, 'default', 'distance',     defaults.distance);
        s.cameraSpeed  = config:GetFloat(addon.name, 'default', 'cameraSpeed',  defaults.cameraSpeed);
        s.pauseOnEvent = config:GetBool(addon.name,     'default', 'pauseOnEvent', defaults.pauseOnEvent);
    end
    return s;
end

--[[
* Save the passed configuration table to disk.
*
* @param {data} - the updated settings to store in the addon's ini file
]]--
local save_settings = function(data)
    local config = AshitaCore:GetConfigurationManager();
    local ini_file = string.format('%s.ini', addon.name);

    config:Delete(addon.name, ini_file);
    config:SetValue(addon.name, 'default', 'distance',     tostring(data.distance));
    config:SetValue(addon.name, 'default', 'cameraSpeed',  tostring(data.cameraSpeed));
    config:SetValue(addon.name, 'default', 'pauseOnEvent', tostring(data.pauseOnEvent));

    config:Save(addon.name, ini_file);
end

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'camera_load', function()
    -- Load the configuration file..
    settings = load_merged_settings(default_settings);

    -- Create location to store vertical camera speed adjustment
    speedAdjustment_ptr = ashita.memory.alloc(4);
    ashita.memory.write_float(speedAdjustment_ptr, settings.cameraSpeed);
    
    -- Create code cave to adjust vertical camera move speed
    codeCave_ptr = ashita.memory.alloc(17);
    
    ashita.memory.unprotect(codeCave_ptr, 17)
    ashita.memory.write_array(codeCave_ptr, codeCaveValues)
    
    -- Push in pointer to Camera Speed into the Code Cave
    ashita.memory.write_uint32(codeCave_ptr + 0x02, speedAdjustment_ptr)
    
    -- Get the point where we are injecting code to jump to code cave
    injectionPoint_ptr = ashita.memory.find('FFXiMain.dll', 0, 'D84C24248B168BCED80D', 0, 0);
    if (injectionPoint_ptr == 0) then error('Failed to locate critical signature #1!'); end
    
    local returnJmpPoint = codeCave_ptr + 0x0C
    
    -- Push in pointer to the return point into the Code Cave
    ashita.memory.write_int32(returnJmpPoint + 0x01, (injectionPoint_ptr + 0x06) - (returnJmpPoint) - 0x05)

    -- Set up the Jump to the Code Cave    
    ashita.memory.write_uint8(injectionPoint_ptr, 0xE9)
    ashita.memory.write_int32(injectionPoint_ptr + 0x01, (codeCave_ptr - injectionPoint_ptr - 0x05))
    ashita.memory.write_uint8(injectionPoint_ptr + 0x05, 0x90)
    
    local pointerToCameraPointer = ashita.memory.find('FFXiMain.dll', 0, 'C8E878010000EB0233C08BC8A3', 0, 0);
    if (pointerToCameraPointer == 0) then error('Failed to locate critical signature #2!'); end

    ptrToBaseCamera_ptr = ashita.memory.read_uint32(pointerToCameraPointer + 0x0D);
    if (ptrToBaseCamera_ptr == 0) then error('Failed to locate critical signature #3!'); end
    
    readyToRender = true
end);

ashita.events.register('d3d_beginscene', 'camera_beginscene', function()
    if ptrToBaseCamera_ptr ~= 0 and runOnEvent() and readyToRender then
        local baseCameraAddress = ashita.memory.read_uint32(ptrToBaseCamera_ptr);

        if baseCameraAddress ~= 0 then
            local focal_x = ashita.memory.read_float(baseCameraAddress + 0x50)
            local focal_z = ashita.memory.read_float(baseCameraAddress + 0x54)
            local focal_y = ashita.memory.read_float(baseCameraAddress + 0x58)
            
            local diff_x = ashita.memory.read_float(baseCameraAddress + 0x44) - focal_x
            local diff_z = ashita.memory.read_float(baseCameraAddress + 0x48) - focal_z
            local diff_y = ashita.memory.read_float(baseCameraAddress + 0x4C) - focal_y
            
            local distance = 1 / math.sqrt(diff_x * diff_x + diff_z * diff_z + diff_y * diff_y) * settings.distance
            
            ashita.memory.write_float(baseCameraAddress + 0x44, diff_x * distance + focal_x)
            ashita.memory.write_float(baseCameraAddress + 0x48, diff_z * distance + focal_z)
            ashita.memory.write_float(baseCameraAddress + 0x4C, diff_y * distance + focal_y)
        end
    end
end);

local setCameraSpeed = function(newSpeed)
    ashita.memory.write_float(speedAdjustment_ptr, newSpeed);
    settings.cameraSpeed = newSpeed
end

ashita.events.register('command', 'camera_command', function(e)
    local command_args = e.command:lower():args()
    if (command_args[1] ~= '/camera' and command_args[1] ~= '/cam') then
        return false
    elseif (command_args[1] == '/camera' or command_args[1] == '/cam') then
        if (command_args[2] == 'distance' or command_args[2] == 'd') then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
                settings.distance = newDistance
                setCameraSpeed(newDistance / 6.0)
                save_settings(settings);
                print("Distance changed to " .. newDistance)
            end
        elseif (command_args[2] == 'start')  then
            readyToRender = true
        elseif (command_args[2] == 'stop')  then
            readyToRender = false
        elseif (command_args[2] == 'pauseonevent')  then
            local newSetting
            if command_args[3] == 't' or command_args[3] == 'true' then
                newSetting = true
            elseif command_args[3] == 'f' or command_args[3] == 'false' then
                newSetting = false
            elseif command_args[3] == nil then
                newSetting = not settings.pauseOnEvent
            end
            
            if newSetting ~= nil then
                settings.pauseOnEvent = newSetting
                save_settings(settings);
                print("Pause on event setting changed to " .. tostring(settings.pauseOnEvent))
            end
        elseif (command_args[2] == 'help' or command_args[2] == 'h') then
            print("Set Distance: </camera|/cam> <distance|d> <###>")
            print("Set Pause on event: </camera|/cam> <pauseonevent> [t|true|f|false]")
            print("Start/Stop: </camera|/cam> <start|stop>")
        end
    end

    return false
end)

local restorePointers = function()
    if (injectionPoint_ptr ~= 0 and injectionPoint_ptr ~= nil) then
        ashita.memory.write_array(injectionPoint_ptr, originalValues)
    end
    if (speedAdjustment_ptr ~= 0 and speedAdjustment_ptr ~= nil) then
        ashita.memory.dealloc(speedAdjustment_ptr, 4)
    end
    if (codeCave_ptr ~= 0 and codeCave_ptr ~= nil) then
        ashita.memory.dealloc(codeCave_ptr, 17)
    end
end

----------------------------------------------------------------------------------------------------
-- func: unload
-- desc: Event called when the addon is being unloaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('unload', 'camera_unload', function()
    -- Save the configuration file..
    save_settings(settings);
    restorePointers();
end);

--TODO replace with unload event
gc_global = ffi.new('int*');

ffi.gc(gc_global, restorePointers);
