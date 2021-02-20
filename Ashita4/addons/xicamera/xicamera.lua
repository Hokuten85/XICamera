addon.author   = 'Hokuten';
addon.name     = 'xicamera';
addon.version  = '0.0.1';
addon.desc     = 'Modifies the camera distance from the player.';

local common = require('common');
local ffi = require('ffi');
local ffi_new = ffi.new
local ffi_gc = ffi.gc
local ffi_cast = ffi.cast

ffi.cdef[[
    struct camera_t
    {
        uint8_t Unknown0000[0x44];
        float X;
        float Z;
        float Y;
        float FocalX;
        float FocalZ;
        float FocalY;
    };
]]

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
    
    return not (settings.pauseOnEvent and entity:GetEventPointer(player.TargetIndex) ~= 0 and entity:GetEventPointer(player.TargetIndex) ~= nil)
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

local speedAdjustment
local codeCave
local injectionPoint
local ptrToCamera
local baseCameraAddress
local currentBaseAddress
local camera

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
        s.pauseOnEvent = config:GetBool(addon.name,  'default', 'pauseOnEvent', defaults.pauseOnEvent);
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

local logToFile = function(stringToLog, boolPrint)
    local file = io.open('\\cameralog.txt', "a");
    file:write(tostring(stringToLog), "\n");
    file:close(file);
    
    if boolPrint then
        print(stringToLog)
    end
end

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'camera_load', function()
    -- Load the configuration file..
    settings = load_merged_settings(default_settings);

    -- Create location to store vertical camera speed adjustment
    speedAdjustment = ashita.memory.alloc(4);
    ashita.memory.write_float(speedAdjustment, settings.cameraSpeed);
    
    -- Create code cave to adjust vertical camera move speed
    codeCave = ashita.memory.alloc(17);
    
    ashita.memory.unprotect(codeCave, 17)
    ashita.memory.write_array(codeCave, codeCaveValues)
    
    -- Push in pointer to Camera Speed into the Code Cave
    ashita.memory.write_uint32(codeCave + 0x02, speedAdjustment)
    
    -- Get the point where we are injecting code to jump to code cave
    injectionPoint = ashita.memory.find('FFXiMain.dll', 0, 'D84C24248B168BCED80D', 0, 0);
    if (injectionPoint == 0) then error('Failed to locate critical signature #1!'); end
    
    -- Push in pointer to the return point into the Code Cave
    ashita.memory.write_int32(codeCave + 0x0D, (injectionPoint + 0x06) - (codeCave + 0x0C) - 0x05)

    -- Set up the Jump to the Code Cave    
    ashita.memory.write_uint8(injectionPoint, 0xE9)
    ashita.memory.write_int32(injectionPoint + 0x01, (codeCave - injectionPoint - 0x05))
    ashita.memory.write_uint8(injectionPoint + 0x05, 0x90)
    
    local pointerToCameraPointer = ashita.memory.find('FFXiMain.dll', 0, 'C8E878010000EB0233C08BC8A3', 0, 0);
    if (pointerToCameraPointer == 0) then error('Failed to locate critical signature #2!'); end

    ptrToCamera = ashita.memory.read_uint32(pointerToCameraPointer + 0x0D);
    if (ptrToCamera == 0) then error('Failed to locate critical signature #3!'); end

    baseCameraAddress = ffi_cast('uint32_t*', ptrToCamera);
    currentBaseAddress = baseCameraAddress[0]
    camera = ffi_cast('struct camera_t*', baseCameraAddress[0])

    readyToRender = true
end);

ashita.events.register('d3d_beginscene', 'camera_beginscene', function(isRenderingBackBuffer)
    if isRenderingBackBuffer and baseCameraAddress[0] ~= nil and runOnEvent() and readyToRender then
        if currentBaseAddress ~= baseCameraAddress[0] then
            camera = ffi_cast('struct camera_t*', baseCameraAddress[0])
            currentBaseAddress = baseCameraAddress[0]
        end
        if camera ~= nil then
            local diff_x = camera.X - camera.FocalX
            local diff_z = camera.Z - camera.FocalZ
            local diff_y = camera.Y - camera.FocalY
            
            local distance = 1 / math.sqrt(diff_x * diff_x + diff_z * diff_z + diff_y * diff_y) * settings.distance
            
            camera.X = diff_x * distance + camera.FocalX
            camera.Z = diff_z * distance + camera.FocalZ
            camera.Y = diff_y * distance + camera.FocalY
        end
    end
end);

local setCameraSpeed = function(newSpeed)
    ashita.memory.write_float(speedAdjustment, newSpeed);
    settings.cameraSpeed = newSpeed
end

ashita.events.register('command', 'camera_command', function(e)
    local command_args = e.command:lower():args()
    if table.contains({'/camera', '/cam', '/xicamera', '/xicam'}, command_args[1]) then
        if table.contains({'distance', 'd'}, command_args[2]) then
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
            if table.contains({'t', 'true'}, command_args[3]) then
                newSetting = true
            elseif table.contains({'f', 'false'}, command_args[3]) then
                newSetting = false
            elseif command_args[3] == nil then
                newSetting = not settings.pauseOnEvent
            end
            
            if newSetting ~= nil then
                settings.pauseOnEvent = newSetting
                save_settings(settings);
                print("Pause on event setting changed to " .. tostring(settings.pauseOnEvent))
            end
        elseif table.contains({'help', 'h'}, command_args[2]) then
            print("Set Distance: </camera|/cam> <distance|d> <###>")
            print("Set Pause on event: </camera|/cam> <pauseonevent> [t|true|f|false]")
            print("Start/Stop: </camera|/cam> <start|stop>")
        end
    end

    return false
end)

local restorePointers = function()
    if (injectionPoint ~= 0 and injectionPoint ~= nil) then
        ashita.memory.write_array(injectionPoint, originalValues)
        injectionPoint = nil
    end
    if (speedAdjustment ~= 0 and speedAdjustment ~= nil) then
        ashita.memory.dealloc(speedAdjustment, 4)
        speedAdjustment = nil
    end
    if (codeCave ~= 0 and codeCave ~= nil) then
        ashita.memory.dealloc(codeCave, 17)
        codeCave = nil
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
ffi_gc(gc_global, restorePointers);
