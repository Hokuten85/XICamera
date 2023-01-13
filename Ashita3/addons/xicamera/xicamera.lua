_addon.author   = 'Hokuten';
_addon.name     = 'xicamera';
_addon.version  = '0.7.3';

require 'common'

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_config =
{
    distance    = 6,
    cameraSpeed = 1.0,
	battledistance = 8.2
};
local configs = default_config;
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

local cameraSpeedAdjustment
local codeCave
local caveJmpCavePoint

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
local npcWalkAnimationSig
local originalMinDistancePtr
local newMinDistanceConstant

local setCameraSpeed = function(newSpeed)
    ashita.memory.write_float(cameraSpeedAdjustment, newSpeed);
    configs.cameraSpeed = newSpeed
end

local setCameraDistance = function(newDistance)
	configs.distance = newDistance
	ashita.memory.write_float(minDistancePtr, newDistance - (originalMaxDistance - originalMinDistance));
	ashita.memory.write_float(maxDistancePtr, newDistance);
end

local setBattleCameraDistance = function(newDistance)
	configs.battledistance = newDistance
	ashita.memory.write_float(minBattleDistancePtr, newDistance - (originalMaxBattleDistance - originalMinBattleDistance));
	ashita.memory.write_float(maxBattleDistancePtr, newDistance);
end

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
	
	--GET MIN CAMERA DISTANCE
	local minDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D9442410D81DC02B', 0, 0);
	if (minDistanceSig == 0) then error('Failed to locate minDistanceSig!'); end
	
	minDistancePtr = ashita.memory.read_uint32(minDistanceSig + 0x06);
	originalMinDistance = ashita.memory.read_float(minDistancePtr)
	ashita.memory.unprotect(minDistancePtr, 4)
	
	--GET MAX CAMERA DISTANCE
	local maxDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D9442410D8257032', 0, 0);
	if (maxDistanceSig == 0) then error('Failed to locate maxDistanceSig!'); end
	
	maxDistancePtr = ashita.memory.read_uint32(maxDistanceSig + 0x06);
	originalMaxDistance = ashita.memory.read_float(maxDistancePtr)
	ashita.memory.unprotect(maxDistancePtr, 4)
	
	-- GET MIN BATTLE DISTANCE
	local minBattleDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D8442424D9053032', 0, 0);
	if (minBattleDistanceSig == 0) then error('Failed to locate minBattleDistanceSig!'); end
	
	minBattleDistancePtr = ashita.memory.read_uint32(minBattleDistanceSig + 0x06);
	originalMinBattleDistance = ashita.memory.read_float(minBattleDistancePtr)
	ashita.memory.unprotect(minBattleDistancePtr, 4)
	
	-- GET MAX BATTLE DISTANCE
	local battleMaxDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D95C2450D8052C32', 0, 0);
	if (battleMaxDistanceSig == 0) then error('Failed to locate battleMaxDistanceSig!'); end
	
	maxBattleDistancePtr = ashita.memory.read_uint32(battleMaxDistanceSig + 0x06);
	originalMaxBattleDistance = ashita.memory.read_float(maxBattleDistancePtr)
	ashita.memory.unprotect(maxBattleDistancePtr, 4)
	
	-- GET LOCATION OF ZOOM LENSE SETUP
	zoomSetupSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D9442404D80D6C2B????D80D', 0, 0);
	if (zoomSetupSig == 0) then error('Failed to locate zoomSetupSig!'); end
	
	originalMinDistancePtr = ashita.memory.read_uint32(zoomSetupSig + 0x0C);
	newMinDistanceConstant = ashita.memory.alloc(4);
    ashita.memory.write_float(newMinDistanceConstant, originalMinDistance);
	
	-- Write new memloc to zoom setup function to fix zone-in bug
	ashita.memory.write_uint32(zoomSetupSig + 0x0C, newMinDistanceConstant);
	
	-- GET LOCATION OF WALK ANIMATION
	walkAnimationSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D80DC02B????D913', 0, 0);
	if (walkAnimationSig == 0) then error('Failed to locate walkAnimationSig!'); end
	
	-- Write new memloc to walk animation
	ashita.memory.write_uint32(walkAnimationSig + 0x02, newMinDistanceConstant);
	
	-- GET LOCATION OF NPC WALK ANIMATION
	npcWalkAnimationSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D9442410D80DC02B????D91B', 0, 0);
	if (npcWalkAnimationSig == 0) then error('Failed to locate npcWalkAnimationSig!'); end
	
	-- Write new memloc to npc walk animation
	ashita.memory.write_uint32(npcWalkAnimationSig + 0x06, newMinDistanceConstant);
	
	-- SET CAMERA DISTANCE BASED ON configs
	setCameraDistance(configs.distance)
	
	-- SET BATTLE DISTANCE BASED ON configs
	setBattleCameraDistance(configs.battledistance)
end);

ashita.register_event('command', function(command, ntype)
    local command_args = command:lower():args()
    if table.hasvalue({'/camera', '/cam', '/xicamera', '/xicam'}, command_args[1]) then
        if table.hasvalue({'distance', 'd'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
				setCameraDistance(newDistance)
                setCameraSpeed(newDistance / 6.0)
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs);
                print("Camera distance changed to " .. newDistance)
            end
		elseif table.hasvalue({'battle', 'b'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
				setBattleCameraDistance(newDistance)
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs);
                print("Battle distance changed to " .. newDistance)
            end
        elseif table.hasvalue({'help', 'h'}, command_args[2]) then
            print("Set Distance: </camera|/cam|> <distance|d> <###>")
			print("Set Battle Distance: </camera|/cam> <battle|b> <###>")
			print("Status: </camera|/cam> <status|s>")
		elseif table.hasvalue({'status', 's'}, command_args[2]) then
			print("- status")
			print("-  cameraDistance: " .. configs.distance)
			print("-  battleDistance: " .. configs.battledistance)
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
	
	if (minDistancePtr ~= 0 and minDistancePtr ~= nil) then
		ashita.memory.write_float(minDistancePtr, originalMinDistance)
	end
	if (maxDistancePtr ~= 0 and maxDistancePtr ~= nil) then
		ashita.memory.write_float(maxDistancePtr, originalMaxDistance)
	end
	if (minBattleDistancePtr ~= 0 and minBattleDistancePtr ~= nil) then
		ashita.memory.write_float(minBattleDistancePtr, originalMinBattleDistance)
	end
	if (maxBattleDistancePtr ~= 0 and maxBattleDistancePtr ~= nil) then
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
	if (npcWalkAnimationSig ~= 0 and npcWalkAnimationSig ~= nil) then
		ashita.memory.write_uint32(npcWalkAnimationSig + 0x06, originalMinDistancePtr)
		ashita.memory.dealloc(newMinDistanceConstant, 4)
	end
end);
