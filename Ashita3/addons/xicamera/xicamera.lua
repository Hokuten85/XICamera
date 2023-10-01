_addon.author   = 'Hokuten'
_addon.name     = 'xicamera'
_addon.version  = '0.7.8'

require 'common'

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_config =
{
    distance    = 6,
	battleDistance = 8.2,
	horizontalPanSpeed = 3.0,
	verticalPanSpeed = 10.7,
	saveOnIncrement = false,
	autoCalcVertSpeed = true,
}
local configs = default_config
----------------------------------------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------------------------------------
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
local battleSoundSig
local originalMinDistancePtr
local newMinDistanceConstant

local horizontalPanSpeedPtr
local oringinalHorizontalPanSpeed
local verticalPanSpeedPtr
local oringinalVerticalPanSpeed

local setHorizontalPanSpeed = function(newSpeed)
	configs.horizontalPanSpeed = newSpeed 
	ashita.memory.write_float(horizontalPanSpeedPtr, newSpeed / 100.0)
end

local setVerticalPanSpeed = function(newSpeed)
	configs.verticalPanSpeed = newSpeed
	ashita.memory.write_float(verticalPanSpeedPtr, newSpeed / 100.0)
end

local setCameraDistance = function(newDistance)
	configs.distance = newDistance
	ashita.memory.write_float(minDistancePtr, newDistance - (originalMaxDistance - originalMinDistance))
	ashita.memory.write_float(maxDistancePtr, newDistance)

	if configs.autoCalcVertSpeed then
		setVerticalPanSpeed(default_config.verticalPanSpeed * newDistance / 6.0)
	end
end

local setBattleCameraDistance = function(newDistance)
	configs.battleDistance = newDistance
	ashita.memory.write_float(minBattleDistancePtr, newDistance - (originalMaxBattleDistance - originalMinBattleDistance))
	ashita.memory.write_float(maxBattleDistancePtr, newDistance)
end

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.register_event('load', function()
    -- Load the configuration file..
    configs = ashita.settings.load_merged(_addon.path .. '/settings/settings.json', configs)
	
	--GET MIN CAMERA DISTANCE
	local minDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D8C9D9C0D8C1D9C2D80D????????D9C3DCC0D8EB', 0, 0)
	if (minDistanceSig == 0) then error('Failed to locate minDistanceSig!') end
	
	minDistancePtr = ashita.memory.read_uint32(minDistanceSig + 0x0A)
	originalMinDistance = ashita.memory.read_float(minDistancePtr)
	ashita.memory.unprotect(minDistancePtr, 4)
	
	--GET MAX CAMERA DISTANCE
	local maxDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D9442410D825????????51D80D', 0, 0)
	if (maxDistanceSig == 0) then error('Failed to locate maxDistanceSig!') end
	
	maxDistancePtr = ashita.memory.read_uint32(maxDistanceSig + 0x06)
	originalMaxDistance = ashita.memory.read_float(maxDistancePtr)
	ashita.memory.unprotect(maxDistancePtr, 4)
	
	-- GET MIN BATTLE DISTANCE
	local minBattleDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, '5152D8442424D905????????D8C1', 0, 0)
	if (minBattleDistanceSig == 0) then error('Failed to locate minBattleDistanceSig!') end
	
	minBattleDistancePtr = ashita.memory.read_uint32(minBattleDistanceSig + 0x08)
	originalMinBattleDistance = ashita.memory.read_float(minBattleDistancePtr)
	ashita.memory.unprotect(minBattleDistancePtr, 4)
	
	-- GET MAX BATTLE DISTANCE
	local battleMaxDistanceSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D8C1D8CAD95C2450D805????????D8C9', 0, 0)
	if (battleMaxDistanceSig == 0) then error('Failed to locate battleMaxDistanceSig!') end
	
	maxBattleDistancePtr = ashita.memory.read_uint32(battleMaxDistanceSig + 0x0A)
	originalMaxBattleDistance = ashita.memory.read_float(maxBattleDistancePtr)
	ashita.memory.unprotect(maxBattleDistancePtr, 4)
	
	-- GET LOCATION OF ZOOM LENSE SETUP
	zoomSetupSig = ashita.memory.findpattern('FFXiMain.dll', 0, '85C0741AD9442404D80D????????D80D????????D87C', 0, 0)
	if (zoomSetupSig == 0) then error('Failed to locate zoomSetupSig!') end
	
	originalMinDistancePtr = ashita.memory.read_uint32(zoomSetupSig + 0x10)
	newMinDistanceConstant = ashita.memory.alloc(4)
    ashita.memory.write_float(newMinDistanceConstant, originalMinDistance)
	
	-- Write new memloc to zoom setup function to fix zone-in bug
	ashita.memory.write_uint32(zoomSetupSig + 0x10, newMinDistanceConstant)
	
	-- GET LOCATION OF WALK ANIMATION
	walkAnimationSig = ashita.memory.findpattern('FFXiMain.dll', 0, '0F85????????D80D????????D913D81D', 0, 0)
	if (walkAnimationSig == 0) then error('Failed to locate walkAnimationSig!') end
	
	-- Write new memloc to walk animation
	ashita.memory.write_uint32(walkAnimationSig + 0x08, newMinDistanceConstant)
	
	-- GET LOCATION OF NPC WALK ANIMATION
	npcWalkAnimationSig = ashita.memory.findpattern('FFXiMain.dll', 0, '7514D9442410D80D????????D91B8B8E', 0, 0)
	if (npcWalkAnimationSig == 0) then error('Failed to locate npcWalkAnimationSig!') end
	
	-- Write new memloc to npc walk animation
	ashita.memory.write_uint32(npcWalkAnimationSig + 0x08, newMinDistanceConstant)
	
	-- GET LOCATION OF BATTLE SOUND CALCULATION
	battleSoundSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D95C2414741B487410D9442410D80D', 0, 0)
	if (battleSoundSig == 0) then error('Failed to locate battleSoundSig!') end
	
	-- Write new memloc to npc walk animation
	ashita.memory.write_uint32(battleSoundSig + 0x0F, newMinDistanceConstant)
	
	--Horizontal Cam Pan Speed
	local hPanSpeedSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D84C24208B068BCED80D', 0, 0)
	if (hPanSpeedSig == 0) then error('Failed to locate hPanSpeedSig!') end
	
	horizontalPanSpeedPtr = ashita.memory.read_uint32(hPanSpeedSig + 0x0A)
	oringinalHorizontalPanSpeed = ashita.memory.read_float(horizontalPanSpeedPtr)
	
	--Vertical Cam Pan Speed
	local vPanSpeedSig = ashita.memory.findpattern('FFXiMain.dll', 0, 'D84C24248B168BCED80D', 0, 0)
	if (vPanSpeedSig == 0) then error('Failed to locate vPanSpeedSig!') end
	
	verticalPanSpeedPtr = ashita.memory.read_uint32(vPanSpeedSig + 0x0A)
	oringinalVerticalPanSpeed = ashita.memory.read_float(verticalPanSpeedPtr)
	
	-- SET CAMERA DISTANCE BASED ON configs
	setCameraDistance(configs.distance)
	
	-- SET BATTLE DISTANCE BASED ON configs
	setBattleCameraDistance(configs.battleDistance)
	
	-- SET HORIZONTAL PAN SPEED BASED ON configs
	setHorizontalPanSpeed(configs.horizontalPanSpeed)
	
	-- SET VERTICAL PAN SPEED BASED ON configs
	if not configs.autoCalcVertSpeed then
		setVerticalPanSpeed(configs.verticalPanSpeed)
	end
end)

ashita.register_event('command', function(command, ntype)
    local command_args = command:lower():args()
    if table.hasvalue({'/camera', '/cam', '/xicamera', '/xicam'}, command_args[1]) then
        if table.hasvalue({'distance', 'd'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
				setCameraDistance(newDistance)
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
                print("Camera distance changed to " .. newDistance)
            end
		elseif table.hasvalue({'battle', 'b'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
				setBattleCameraDistance(newDistance)
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
                print("Battle distance changed to " .. newDistance)
            end
		elseif table.hasvalue({'hspeed', 'hs'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newSpeed = tonumber(command_args[3])
				setHorizontalPanSpeed(newSpeed)
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
                print("Horizontal pan speed changed to " .. newSpeed)
            end
		elseif table.hasvalue({'vspeed', 'vs'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newSpeed = tonumber(command_args[3])
				setVerticalPanSpeed(newSpeed)
				configs.autoCalcVertSpeed = false
                ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
                print("Vertical pan speed changed to " .. newSpeed)
            end
		elseif table.hasvalue({'incr', 'in', 'bincr', 'bin', 'decr', 'de', 'bdecr', 'bde'}, command_args[2]) then
			local isIncr = string.find(command_args[2], 'in')
			local isBattle = string.find(command_args[2], 'b')
			local newDistance = (isBattle and configs.battleDistance or configs.distance) + (isIncr and 1 or -1)
			local camTypeFunction = isBattle and setBattleCameraDistance or setCameraDistance
			camTypeFunction(newDistance)
			if configs.saveOnIncrement then ashita.settings.save(_addon.path .. '/settings/settings.json', configs) end
			print((isBattle and 'Battle ' or '') .. "Distance changed to " .. newDistance)
		elseif table.hasvalue({'saveonincrement', 'soi'}, command_args[2]) then
			configs.saveOnIncrement = not configs.saveOnIncrement
			print("saveOnIncrement changed to " .. tostring(configs.saveOnIncrement))
			ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
		elseif table.hasvalue({'autocalcvertspeed', 'acv'}, command_args[2]) then
			configs.autoCalcVertSpeed = not configs.autoCalcVertSpeed
			print("autoCalcVertSpeed changed to " .. tostring(configs.autoCalcVertSpeed))
			ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
        elseif table.hasvalue({'help', 'h'}, command_args[2]) then
            print("Set Distance: </camera|/cam> <distance|d> <###> - FFXI Default: 6")
			print("Set Battle Distance: </camera|/cam> <battle|b> <###> - FFXI Default: 8")
			print("Set Horizontal Pan Speed: </camera|/cam> <hspeed|hs> <###> - FFXI Default: 3")
			print("Set Vertical Pan Speed: </camera|/cam> <vspeed|vs> <###> - FFXI Default: 10, forces auto calc off")
			print("Increments Distance: </camera|/cam> <incr|in>")
			print("Decrements Distance: </camera|/cam> <de|decr>")
			print("Increments Battle Distance: </camera|/cam> <bin|bincr>")
			print("Decrements Battle Distance: </camera|/cam> <bde|bdecr>")
			print("Toggles save on Increment/Decrement behavior: </camera|/cam> <saveOnIncrement|soi> - Default: off")
			print("Toggles Vertical pan speed autocalc: </camera|/cam> <autoCalcVertSpeed|acv> - Default: on")
			print("Status: </camera|/cam> <status|s>")
		elseif table.hasvalue({'status', 's'}, command_args[2]) then
			print("- status")
			print("-  cameraDistance: " .. configs.distance)
			print("-  battleDistance: " .. configs.battleDistance)
			print("-  horizontalPanSpeed: " .. configs.horizontalPanSpeed)
			print("-  verticalPanSpeed: " .. configs.verticalPanSpeed)
			print("-  saveOnIncrement: " .. tostring(configs.saveOnIncrement))
			print("-  autoCalcVertSpeed: " .. tostring(configs.autoCalcVertSpeed))
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
    ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
	
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
	
	if (horizontalPanSpeedPtr ~= 0 and horizontalPanSpeedPtr ~= nil) then
		ashita.memory.write_float(horizontalPanSpeedPtr, oringinalHorizontalPanSpeed)
	end
	if (verticalPanSpeedPtr ~= 0 and verticalPanSpeedPtr ~= nil) then
		ashita.memory.write_float(verticalPanSpeedPtr, oringinalVerticalPanSpeed)
	end
	
	if (zoomSetupSig ~= 0 and zoomSetupSig ~= nil) then
		ashita.memory.write_uint32(zoomSetupSig + 0x10, originalMinDistancePtr)
		ashita.memory.dealloc(newMinDistanceConstant, 4)
	end
	if (walkAnimationSig ~= 0 and walkAnimationSig ~= nil) then
		ashita.memory.write_uint32(walkAnimationSig + 0x08, originalMinDistancePtr)
		ashita.memory.dealloc(newMinDistanceConstant, 4)
	end
	if (npcWalkAnimationSig ~= 0 and npcWalkAnimationSig ~= nil) then
		ashita.memory.write_uint32(npcWalkAnimationSig + 0x08, originalMinDistancePtr)
		ashita.memory.dealloc(newMinDistanceConstant, 4)
	end
	if (battleSoundSig ~= 0 and battleSoundSig ~= nil) then
		ashita.memory.write_uint32(battleSoundSig + 0x0F, originalMinDistancePtr)
		ashita.memory.dealloc(newMinDistanceConstant, 4)
	end
end)
