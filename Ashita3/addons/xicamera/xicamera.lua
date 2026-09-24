_addon.author   = 'Hokuten'
_addon.name     = 'xicamera'
_addon.version  = '0.8.0'

require 'common'

-- the shared patch core lives next to this file
package.path = package.path .. ';' .. _addon.path .. '/?.lua'
local Core = require('xicamera_core')

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_config =
{
    distance    = 6,
	battleDistance = 8.2,
	battleRange = 4.0,
	horizontalPanSpeed = 3.0,
	verticalPanSpeed = 10.7,
	saveOnIncrement = false,
	autoCalcVertSpeed = true,
	battleRangeLocked = true,
}
local configs = default_config

local function saveConfig()
	ashita.settings.save(_addon.path .. '/settings/settings.json', configs)
end

----------------------------------------------------------------------------------------------------
-- Memory adapter for the shared core
----------------------------------------------------------------------------------------------------
local mem = {
	find        = function(sig) return ashita.memory.findpattern('FFXiMain.dll', 0, sig, 0, 0) end,
	read_u16    = function(a) return ashita.memory.read_uint16(a) end,
	read_u32    = function(a) return ashita.memory.read_uint32(a) end,
	read_float  = function(a) return ashita.memory.read_float(a) end,
	write_u16   = function(a, v) ashita.memory.write_uint16(a, v) end,
	write_u32   = function(a, v) ashita.memory.write_uint32(a, v) end,
	write_float = function(a, v) ashita.memory.write_float(a, v) end,
	alloc       = function(size) return ashita.memory.alloc(size) end,
	log         = function(text) print('[xicamera] ' .. text) end,
}
local core = Core.new(mem)

----------------------------------------------------------------------------------------------------
-- Setters: keep configs and the core's slots in step
----------------------------------------------------------------------------------------------------
local setHorizontalPanSpeed = function(newSpeed)
	configs.horizontalPanSpeed = newSpeed
	core:setHorizontalPanSpeed(newSpeed)
end

local setVerticalPanSpeed = function(newSpeed)
	configs.verticalPanSpeed = newSpeed
	core:setVerticalPanSpeed(newSpeed)
end

local setCameraDistance = function(newDistance)
	configs.distance = newDistance
	core:setCameraDistance(newDistance)
	if configs.autoCalcVertSpeed then
		setVerticalPanSpeed(default_config.verticalPanSpeed * newDistance / 6.0)
	end
end

local setBattleCameraDistance = function(newDistance)
	configs.battleDistance = newDistance
	core:setBattleDistance(newDistance)
end

local setBattleCameraRange = function(newRange)
	configs.battleRange = math.min(math.max(0, tonumber(newRange)), 100)
	core:setBattleRange(configs.battleRange)
end

local setBattleRangeLock = function(isLocked)
	configs.battleRangeLocked = isLocked
	core:setBattleRangeLock(isLocked)
end

local applySettings = function()
	setCameraDistance(configs.distance)
	setBattleCameraDistance(configs.battleDistance)
	setHorizontalPanSpeed(configs.horizontalPanSpeed)
	if not configs.autoCalcVertSpeed then
		setVerticalPanSpeed(configs.verticalPanSpeed)
	end
	setBattleCameraRange(configs.battleRange)
	setBattleRangeLock(configs.battleRangeLocked)
end

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.register_event('load', function()
    -- Load the configuration file..
    configs = ashita.settings.load_merged(_addon.path .. '/settings/settings.json', configs)

	if not core:install() then
		local off = {}
		for _, g in ipairs(core:groupStatus()) do
			if g.required and not g.enabled then off[#off + 1] = g.name end
		end
		print('[xicamera] WARN: not every patch group is in (' .. table.concat(off, ', ') .. '); see /cam status')
	end
	applySettings()
end)

ashita.register_event('command', function(command, ntype)
    local command_args = command:lower():args()
    if table.hasvalue({'/camera', '/cam', '/xicamera', '/xicam'}, command_args[1]) then
        if table.hasvalue({'distance', 'd'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
				setCameraDistance(newDistance)
                saveConfig()
                print("Camera distance changed to " .. newDistance)
            end
		elseif table.hasvalue({'battle', 'b'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
				setBattleCameraDistance(newDistance)
                saveConfig()
                print("Battle distance changed to " .. newDistance)
            end
		elseif table.hasvalue({'hspeed', 'hs'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newSpeed = tonumber(command_args[3])
				setHorizontalPanSpeed(newSpeed)
                saveConfig()
                print("Horizontal pan speed changed to " .. newSpeed)
            end
		elseif table.hasvalue({'vspeed', 'vs'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newSpeed = tonumber(command_args[3])
				configs.autoCalcVertSpeed = false
				setVerticalPanSpeed(newSpeed)
                saveConfig()
                print("Vertical pan speed changed to " .. newSpeed)
            end
		elseif table.hasvalue({'vheight', 'vh', 'snapheight', 'sh'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local offset = tonumber(command_args[3])
				local cameraY, referenceY = core:snapHeight(offset)
				if (cameraY ~= nil) then
					print(string.format("Camera height snapped to %.2f (reference %.2f + %.2f)", cameraY, referenceY, offset))
				else
					print("[xicamera] WARN: camera task not available; vertical snap failed")
				end
            end
		elseif table.hasvalue({'brange', 'br'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newRange = math.min(math.max(0, tonumber(command_args[3])), 100)
				setBattleRangeLock(true)
				setBattleCameraRange(newRange)
				saveConfig()
				print("Battle camera range changed to " .. newRange)
            end
		elseif table.hasvalue({'battlelock', 'bl'}, command_args[2]) then
			if table.hasvalue({'on', 'true' , '1'}, tostring(command_args[3])) then
				setBattleRangeLock(true)
				saveConfig()
				print("Battle camera range locked.")
			elseif table.hasvalue({'off', 'false' , '0'}, tostring(command_args[3])) then
				setBattleRangeLock(false)
				saveConfig()
				print("Battle camera range unlocked.")
			end
		elseif table.hasvalue({'incr', 'in', 'bincr', 'bin', 'decr', 'de', 'bdecr', 'bde'}, command_args[2]) then
			local isIncr = string.find(command_args[2], 'in')
			local isBattle = string.find(command_args[2], 'b')
			local newDistance = (isBattle and configs.battleDistance or configs.distance) + (isIncr and 1 or -1)
			local camTypeFunction = isBattle and setBattleCameraDistance or setCameraDistance
			camTypeFunction(newDistance)
			if configs.saveOnIncrement then saveConfig() end
			print((isBattle and 'Battle ' or '') .. "Distance changed to " .. newDistance)
		elseif table.hasvalue({'saveonincrement', 'soi'}, command_args[2]) then
			configs.saveOnIncrement = not configs.saveOnIncrement
			print("saveOnIncrement changed to " .. tostring(configs.saveOnIncrement))
			saveConfig()
		elseif table.hasvalue({'autocalcvertspeed', 'acv'}, command_args[2]) then
			configs.autoCalcVertSpeed = not configs.autoCalcVertSpeed
			if configs.autoCalcVertSpeed then setCameraDistance(configs.distance) end
			print("autoCalcVertSpeed changed to " .. tostring(configs.autoCalcVertSpeed))
			saveConfig()
        elseif table.hasvalue({'help', 'h'}, command_args[2]) then
            print("Set Distance: </camera|/cam> <distance|d> <###> - FFXI Default: 6")
			print("Set Battle Distance: </camera|/cam> <battle|b> <###> - FFXI Default: 8")
			print("Set Battle Camera Range: </camera|/cam> <brange|br> <###> - FFXI Default: 4, min: 0, max: 100, forces battle range lock on")
			print("Set Horizontal Pan Speed: </camera|/cam> <hspeed|hs> <###> - FFXI Default: 3")
			print("Set Vertical Pan Speed: </camera|/cam> <vspeed|vs> <###> - FFXI Default: 10, forces auto calc off")
			print("Snap Vertical Height: </camera|/cam> <vheight|vh> <offset> - camera Y = reference Y + offset")
			print("Unlock Battle Camera Range: </camera|/cam> <battlelock|bl> <on|true|1|off|false|0>")
			print("Increments Distance: </camera|/cam> <incr|in>")
			print("Decrements Distance: </camera|/cam> <de|decr>")
			print("Increments Battle Distance: </camera|/cam> <bin|bincr>")
			print("Decrements Battle Distance: </camera|/cam> <bde|bdecr>")
			print("Toggles save on Increment/Decrement behavior: </camera|/cam> <saveOnIncrement|soi> - Default: off")
			print("Toggles Vertical pan speed autocalc: </camera|/cam> <autoCalcVertSpeed|acv> - Default: on")
			print("Status: </camera|/cam> <status|s>")
		elseif table.hasvalue({'status', 's'}, command_args[2]) then
			print("- status")
			print("-  active: " .. tostring(core:active()))
			print("-  cameraDistance: " .. configs.distance)
			print("-  battleDistance: " .. configs.battleDistance)
			print("-  battleRange: " .. configs.battleRange)
			print("-  horizontalPanSpeed: " .. configs.horizontalPanSpeed)
			print("-  verticalPanSpeed: " .. configs.verticalPanSpeed)
			local cameraY, referenceY = core:cameraHeights()
			if (cameraY ~= nil) then
				print(string.format("-  cameraY: %.2f", cameraY))
				print(string.format("-  referenceY: %.2f", referenceY))
			end
			print("-  battleRangeLocked: " .. tostring(configs.battleRangeLocked))
			print("-  saveOnIncrement: " .. tostring(configs.saveOnIncrement))
			print("-  autoCalcVertSpeed: " .. tostring(configs.autoCalcVertSpeed))
			for _, site in ipairs(core:status(true)) do
				if site.state ~= 'patched' then
					print(string.format("-  %s: %s%s", site.name, site.state, site.note and (' (' .. site.note .. ')') or ''))
				end
			end
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
    saveConfig()
	core:uninstall()
end)
