addon.author   = 'Hokuten';
addon.name     = 'xicamera';
addon.version  = '0.7.1';
addon.desc     = 'Modifies the camera distance from the player.';

local common = require('common');
local settings = require('settings');

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_settings = T{
    distance    = 6,
    cameraSpeed = 1.0,
	battleDistance = 8.2
};
local configs = settings.load(default_settings);

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

local minDistancePtr
local originalMinDistance

local maxDistancePtr
local originalMaxDistance

local minBattleDistancePtr
local originalMinBattleDistance

local maxBattleDistancePtr
local originalMaxBattleDistance

local zoomSetupSig
local walkAnimationSig
local originalMinDistancePtr
local newMinDistanceConstant


----------------------------------------------------------------------------------------------------
-- config helpers
----------------------------------------------------------------------------------------------------
--[[
* Updates the addon settings.
*
* @param {table} s - The new settings table to use for the addon settings. (Optional.)
--]]
local function update_settings(s)
    -- Update the settings table..
    if (s ~= nil) then
        configs = s;
    end

    -- Save the current settings..
    settings.save();
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', update_settings);

local setCameraSpeed = function(newSpeed)
	configs.cameraSpeed = newSpeed
    ashita.memory.write_float(speedAdjustment, newSpeed);
end

local setCameraDistance = function(newDistance)
	configs.distance = newDistance
	ashita.memory.write_float(minDistancePtr, newDistance - (originalMaxDistance - originalMinDistance));
	ashita.memory.write_float(maxDistancePtr, newDistance);
end

local setBattleCameraDistance = function(newDistance)
	configs.battleDistance = newDistance
	ashita.memory.write_float(minBattleDistancePtr, newDistance - (originalMaxBattleDistance - originalMinBattleDistance));
	ashita.memory.write_float(maxBattleDistancePtr, newDistance);
end

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'camera_load', function()
    -- Create location to store vertical camera speed adjustment
    speedAdjustment = ashita.memory.alloc(4);
    ashita.memory.write_float(speedAdjustment, configs.cameraSpeed);
    
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
	
	--GET MIN CAMERA DISTANCE
	local minDistanceSig = ashita.memory.find('FFXiMain.dll', 0, 'D9442410D81DC02B', 0, 0);
	if (minDistanceSig == 0) then error('Failed to locate minDistanceSig!'); end
	
	minDistancePtr = ashita.memory.read_uint32(minDistanceSig + 0x06);
	originalMinDistance = ashita.memory.read_float(minDistancePtr)
	ashita.memory.unprotect(minDistancePtr, 4)
	
	--GET MAX CAMERA DISTANCE
	local maxDistanceSig = ashita.memory.find('FFXiMain.dll', 0, 'D9442410D8257032', 0, 0);
	if (maxDistanceSig == 0) then error('Failed to locate maxDistanceSig!'); end
	
	maxDistancePtr = ashita.memory.read_uint32(maxDistanceSig + 0x06);
	originalMaxDistance = ashita.memory.read_float(maxDistancePtr)
	ashita.memory.unprotect(maxDistancePtr, 4)
	
	-- GET MIN BATTLE DISTANCE
	local minBattleDistanceSig = ashita.memory.find('FFXiMain.dll', 0, 'D8442424D9053032', 0, 0);
	if (minBattleDistanceSig == 0) then error('Failed to locate minBattleDistanceSig!'); end
	
	minBattleDistancePtr = ashita.memory.read_uint32(minBattleDistanceSig + 0x06);
	originalMinBattleDistance = ashita.memory.read_float(minBattleDistancePtr)
	ashita.memory.unprotect(minBattleDistancePtr, 4)
	
	-- GET MAX BATTLE DISTANCE
	local battleMaxDistanceSig = ashita.memory.find('FFXiMain.dll', 0, 'D95C2450D8052C32', 0, 0);
	if (battleMaxDistanceSig == 0) then error('Failed to locate battleMaxDistanceSig!'); end
	
	maxBattleDistancePtr = ashita.memory.read_uint32(battleMaxDistanceSig + 0x06);
	originalMaxBattleDistance = ashita.memory.read_float(maxBattleDistancePtr)
	ashita.memory.unprotect(maxBattleDistancePtr, 4)
	
	-- GET LOCATION OF ZOOM LENS SETUP
	zoomSetupSig = ashita.memory.find('FFXiMain.dll', 0, 'D9442404D80D6C2B????D80D', 0, 0);
	if (zoomSetupSig == 0) then error('Failed to locate zoomSetupSig!'); end
	
	originalMinDistancePtr = ashita.memory.read_uint32(zoomSetupSig + 0x0C);
	newMinDistanceConstant = ashita.memory.alloc(4);
    ashita.memory.write_float(newMinDistanceConstant, originalMinDistance);
	
	-- Write new memloc to zoom setup function to fix zone-in bug
	ashita.memory.write_uint32(zoomSetupSig + 0x0C, newMinDistanceConstant);
	
	-- GET LOCATION OF WALK ANIMATION
	walkAnimationSig = ashita.memory.find('FFXiMain.dll', 0, 'D80DC02B????D913', 0, 0);
	if (walkAnimationSig == 0) then error('Failed to locate walkAnimationSig!'); end
	
	-- Write new memloc to walk animation
	ashita.memory.write_uint32(walkAnimationSig + 0x02, newMinDistanceConstant);
	
	-- SET CAMERA DISTANCE BASED ON configs
	setCameraDistance(configs.distance)
	
	-- SET BATTLE DISTANCE BASED ON configs
	setBattleCameraDistance(configs.battleDistance)

end);

ashita.events.register('command', 'camera_command', function(e)
    local command_args = e.command:lower():args()
    if table.contains({'/camera', '/cam', '/xicamera', '/xicam'}, command_args[1]) then
        if table.contains({'distance', 'd'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
                setCameraDistance(newDistance)
                setCameraSpeed(newDistance / 6.0)
                update_settings()
                print("Distance changed to " .. newDistance)
            end
		elseif table.contains({'battle', 'b'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
				setBattleCameraDistance(newDistance)
                update_settings()
                print("Battle distance changed to " .. newDistance)
            end	
        elseif table.contains({'help', 'h'}, command_args[2]) then
            print("Set Distance: </camera|/cam> <distance|d> <###>")
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
	
	if (minDistancePtr ~= 0 and minDistancePtr ~= nil) then
		ashita.memory.write_float(minDistancePtr, originalMinDistance)
	end
	if (maxDistancePtr ~= 0 and maxDistancePtr ~= nil) then
		ashita.memory.write_float(maxDistancePtr, originalMaxDistance)
	end
	if (minBattleDistancePtr ~= 0 and minBattleDistancePtr ~= nil) then
		ashita.memory.write_float(minBattleDistancePtr, originalMinBattleDistance)
	end
	if (battleMaxDistancePtr ~= 0 and battleMaxDistancePtr ~= nil) then
		ashita.memory.write_float(maxBattleDistancePtr, originalMaxBattleDistance)
	end
	
	if (zoomSetupSig ~= 0 and zoomSetupSig ~= nil) then
		ashita.memory.write_uint32(zoomSetupSig + 0x0C, originalMinDistancePtr)
		ashita.memory.dealloc(newMinDistanceConstant, 4)
	end
	if (walkAnimationSig ~= 0 and walkAnimationSig ~= nil) then
		ashita.memory.write_uint32(walkAnimationSig + 0x02, originalMinDistancePtr)
		ashita.memory.dealloc(newMinDistanceConstant, 4)
	end
end

----------------------------------------------------------------------------------------------------
-- func: unload
-- desc: Event called when the addon is being unloaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('unload', 'camera_unload', function()
    -- Save the configuration file..
    update_settings()
    restorePointers();
end);
