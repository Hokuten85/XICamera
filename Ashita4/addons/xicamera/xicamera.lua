addon.author   = 'Hokuten'
addon.name     = 'xicamera'
addon.version  = '0.8.0'
addon.desc     = 'Modifies the camera distance from the player.'

local common = require('common')
local settings = require('settings')
local imgui = require('imgui')
local Core = require('xicamera_core')

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_settings = T{
    distance    = 6.0,
	battleDistance = 8.2,
	battleRange = 4.0,
	horizontalPanSpeed = 3.0,
	verticalPanSpeed = 10.7,
	saveOnIncrement = false,
	autoCalcVertSpeed = true,
	battleRangeLocked = true,
}
local configs = settings.load(default_settings)

----------------------------------------------------------------------------------------------------
-- Memory adapter for the shared core
----------------------------------------------------------------------------------------------------
local mem = {
	find        = function(sig) return ashita.memory.find('FFXiMain.dll', 0, sig, 0, 0) end,
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

-- Settings window state. ImGui writes widget values back into these one-element tables.
local ui = T{
	is_open            = T{ false },
	distance           = T{ 0 },
	battleDistance     = T{ 0 },
	battleRange        = T{ 0 },
	battleRangeLocked  = T{ true },
	horizontalPanSpeed = T{ 0 },
	verticalPanSpeed   = T{ 0 },
	autoCalcVertSpeed  = T{ true },
	saveOnIncrement    = T{ false },
	heightOffset       = T{ 0 },
	lastSnap           = nil,
}

----------------------------------------------------------------------------------------------------
-- Setters: keep configs and the core's slots in step
----------------------------------------------------------------------------------------------------
function setHorizontalPanSpeed(newSpeed)
	configs.horizontalPanSpeed = newSpeed
	core:setHorizontalPanSpeed(newSpeed)
end

function setVerticalPanSpeed(newSpeed)
	configs.verticalPanSpeed = newSpeed
	core:setVerticalPanSpeed(newSpeed)
end

function setCameraDistance(newDistance)
	configs.distance = newDistance
	core:setCameraDistance(newDistance)
	if configs.autoCalcVertSpeed then
		setVerticalPanSpeed(default_settings.verticalPanSpeed * newDistance / 6.0)
	end
end

function setBattleCameraDistance(newDistance)
	configs.battleDistance = newDistance
	core:setBattleDistance(newDistance)
end

function setBattleCameraRange(newRange)
	configs.battleRange = math.min(math.max(0, tonumber(newRange)), 100)
	core:setBattleRange(configs.battleRange)
end

function setBattleRangeLock(isLocked)
	configs.battleRangeLocked = isLocked
	core:setBattleRangeLock(isLocked)
end

function setDistances()
	setCameraDistance(configs.distance)
	setBattleCameraDistance(configs.battleDistance)
	setHorizontalPanSpeed(configs.horizontalPanSpeed)
	if not configs.autoCalcVertSpeed then
		setVerticalPanSpeed(configs.verticalPanSpeed)
	end
	setBattleCameraRange(configs.battleRange)
	setBattleRangeLock(configs.battleRangeLocked)
end

--[[
* Updates the addon settings.
*
* @param {table} s - The new settings table to use for the addon settings. (Optional.)
--]]
local function update_settings(s)
    -- Update the settings table..
    if (s ~= nil) then
        configs = s
    end

    -- Save the current settings..
    settings.save()

	if core.installed then setDistances() end
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', update_settings)

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'camera_load', function()
	if core:install() then
		setDistances()
	else
		local off = {}
		for _, g in ipairs(core:groupStatus()) do
			if g.required and not g.enabled then off[#off + 1] = g.name end
		end
		print('[xicamera] WARN: not every patch group is in (' .. table.concat(off, ', ') .. '); see /cam ui for details')
		setDistances()   -- groups that are in still follow the settings
	end
end)

-- Commands that load or unload another addon or plugin. Every addon sees every command, so
-- this is where XICamera learns that the tools sharing its bytes may have changed.
local function isToolChangeCommand(args)
	local c = args[1]
	if c == '/load' or c == '/unload' or c == '/reload' then return true end
	if c == '/addon' or c == '/addons' then
		return table.contains({'load', 'unload', 'reload', 'reloadall', 'unloadall'}, args[2])
	end
	return false
end

ashita.events.register('command', 'camera_command', function(e)
    local command_args = e.command:lower():args()
    if isToolChangeCommand(command_args) then
        core:beginRecheckWindow(Core.RECHECK_AFTER_TOOL_CHANGE)
        return false
    end
    if table.contains({'/camera', '/cam', '/xicamera', '/xicam'}, command_args[1]) then
        if (command_args[2] == nil or table.contains({'ui', 'settings'}, command_args[2])) then
            ui.is_open[1] = not ui.is_open[1]
        elseif table.contains({'distance', 'd'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newDistance = tonumber(command_args[3])
                setCameraDistance(newDistance)
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
		elseif table.contains({'hspeed', 'hs'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newSpeed = tonumber(command_args[3])
				setHorizontalPanSpeed(newSpeed)
				update_settings()
                print("Horizontal pan speed changed to " .. newSpeed)
            end
		elseif table.contains({'vspeed', 'vs'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newSpeed = tonumber(command_args[3])
				configs.autoCalcVertSpeed = false
				setVerticalPanSpeed(newSpeed)
				update_settings()
                print("Vertical pan speed changed to " .. newSpeed)
            end
		elseif table.contains({'vheight', 'vh', 'snapheight', 'sh'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local offset = tonumber(command_args[3])
				local cameraY, referenceY = core:snapHeight(offset)
				if (cameraY ~= nil) then
					print(string.format("Camera height snapped to %.2f (reference %.2f + %.2f)", cameraY, referenceY, offset))
				else
					print("[xicamera] WARN: camera task not available; vertical snap failed")
				end
            end
		elseif table.contains({'brange', 'br'}, command_args[2]) then
            if (tonumber(command_args[3])) then
                local newRange = math.min(math.max(0, tonumber(command_args[3])), 100)
				setBattleRangeLock(true)
				setBattleCameraRange(newRange)
				update_settings()
				print("Battle camera range changed to " .. newRange)
            end
		elseif table.contains({'battlelock', 'bl'}, command_args[2]) then
			if table.contains({'on', 'true' , '1'}, tostring(command_args[3])) then
				setBattleRangeLock(true)
				update_settings()
				print("Battle camera range locked.")
			elseif table.contains({'off', 'false' , '0'}, tostring(command_args[3])) then
				setBattleRangeLock(false)
				update_settings()
				print("Battle camera range unlocked.")
			end
		elseif table.contains({'incr', 'in', 'bincr', 'bin', 'decr', 'de', 'bdecr', 'bde'}, command_args[2]) then
			local isIncr = string.find(command_args[2], 'in')
			local isBattle = string.find(command_args[2], 'b')
			local newDistance = (isBattle and configs.battleDistance or configs.distance) + (isIncr and 1 or -1)
			local camTypeFunction = isBattle and setBattleCameraDistance or setCameraDistance
			camTypeFunction(newDistance)
			if configs.saveOnIncrement then update_settings() end
			print((isBattle and 'Battle ' or '') .. "Distance changed to " .. newDistance)
		elseif table.contains({'saveOnIncrement', 'soi'}, command_args[2]) then
			configs.saveOnIncrement = not configs.saveOnIncrement
			print("saveOnIncrement changed to " .. tostring(configs.saveOnIncrement))
			update_settings()
		elseif table.contains({'autocalcvertspeed', 'acv'}, command_args[2]) then
			configs.autoCalcVertSpeed = not configs.autoCalcVertSpeed
			print("autoCalcVertSpeed changed to " .. tostring(configs.autoCalcVertSpeed))
			update_settings()
        elseif table.contains({'help', 'h'}, command_args[2]) then
            print("Toggle Settings Window: </camera|/cam> [ui]")
            print("Set Distance: </camera|/cam> <distance|d> <###> - FFXI Default: 6")
			print("Set Battle Distance: </camera|/cam> <battle|b> <###> - FFXI Default 8")
			print("Set Battle Camera Range: </camera|/cam> <brange|br> <###> - FFXI Default: 4, min: 0, max: 100, forces battle range lock on")
			print("Set Horizontal Pan Speed: </camera|/cam> <hspeed|hs> <###> - FFXI Default 3")
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
		elseif table.contains({'status', 's'}, command_args[2]) then
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
			for _, site in ipairs(core:status()) do
				if site.state ~= 'patched' then
					print(string.format("-  %s: %s%s", site.name, site.state, site.note and (' (' .. site.note .. ')') or ''))
				end
			end
        end
    end

    return false
end)

----------------------------------------------------------------------------------------------------
-- Settings window
----------------------------------------------------------------------------------------------------
local headerColor = { 1.0, 0.65, 0.26, 1.0 }
local okColor     = { 0.55, 0.85, 0.55, 1.0 }
local warnColor   = { 0.95, 0.80, 0.40, 1.0 }
local badColor    = { 0.95, 0.45, 0.45, 1.0 }

-- Chat commands change configs directly, so the widgets re-read it every frame.
local function syncUiFromConfigs()
	ui.distance[1]           = configs.distance
	ui.battleDistance[1]     = configs.battleDistance
	ui.battleRange[1]        = configs.battleRange
	ui.battleRangeLocked[1]  = configs.battleRangeLocked
	ui.horizontalPanSpeed[1] = configs.horizontalPanSpeed
	ui.verticalPanSpeed[1]   = configs.verticalPanSpeed
	ui.autoCalcVertSpeed[1]  = configs.autoCalcVertSpeed
	ui.saveOnIncrement[1]    = configs.saveOnIncrement
end

-- A slider that applies every change to the game at once and saves when the drag or edit ends.
local function sliderFloat(label, ref, min, max, fmt, apply, help)
	if imgui.SliderFloat(label, ref, min, max, fmt) then apply(ref[1]) end
	if imgui.IsItemDeactivatedAfterEdit() then update_settings() end
	if help then imgui.ShowHelp(help) end
end

local function applyDefaults()
	configs.autoCalcVertSpeed = default_settings.autoCalcVertSpeed
	configs.saveOnIncrement = default_settings.saveOnIncrement
	setCameraDistance(default_settings.distance)
	if not configs.autoCalcVertSpeed then setVerticalPanSpeed(default_settings.verticalPanSpeed) end
	setBattleCameraDistance(default_settings.battleDistance)
	setHorizontalPanSpeed(default_settings.horizontalPanSpeed)
	setBattleCameraRange(default_settings.battleRange)
	setBattleRangeLock(default_settings.battleRangeLocked)
	update_settings()
end

local stateColors = { patched = okColor, restored = okColor, neutral = warnColor, skipped = warnColor }

local function drawPatchStatus()
	if not imgui.CollapsingHeader('Patch status') then return end
	for _, g in ipairs(core:groupStatus()) do
		if not g.enabled then
			imgui.TextColored(g.required and badColor or warnColor, g.name .. ' group off: ' .. tostring(g.why))
		end
	end
	local rows = core:status()
	if #rows == 0 then imgui.TextDisabled('No signatures scanned yet.') return end
	for _, site in ipairs(rows) do
		imgui.TextColored(stateColors[site.state] or badColor, string.format('%-8s', site.state))
		imgui.SameLine()
		imgui.Text(site.name)
		if site.note then
			imgui.SameLine()
			imgui.TextDisabled('- ' .. site.note)
		end
	end
	imgui.TextDisabled('neutral: another tool already holds the value XICamera uses, so it is left alone.')
end

local function drawSettings()
	imgui.PushItemWidth(240)

	imgui.TextColored(headerColor, 'Camera')
	imgui.Separator()
	sliderFloat('Distance', ui.distance, 1.0, 40.0, '%.1f', setCameraDistance,
		'Third-person camera distance. FFXI default: 6.\n\nCtrl+click to type a value.')
	sliderFloat('Horizontal pan speed', ui.horizontalPanSpeed, 0.5, 20.0, '%.1f', setHorizontalPanSpeed,
		'Left/right camera pan speed. FFXI default: 3.')
	if imgui.Checkbox('Auto-calculate vertical pan speed', ui.autoCalcVertSpeed) then
		configs.autoCalcVertSpeed = ui.autoCalcVertSpeed[1]
		if configs.autoCalcVertSpeed then setCameraDistance(configs.distance) end
		update_settings()
	end
	imgui.ShowHelp('Scales the vertical pan speed with the camera distance.\nSetting the vertical speed by hand turns this off.')
	if imgui.SliderFloat('Vertical pan speed', ui.verticalPanSpeed, 0.5, 40.0, '%.1f') then
		configs.autoCalcVertSpeed = false
		setVerticalPanSpeed(ui.verticalPanSpeed[1])
	end
	if imgui.IsItemDeactivatedAfterEdit() then update_settings() end
	imgui.ShowHelp('Up/down camera pan speed. FFXI default: 10.7.')
	if configs.autoCalcVertSpeed then
		imgui.TextDisabled(string.format('auto: %.1f for distance %.1f', configs.verticalPanSpeed, configs.distance))
	end

	imgui.Spacing()
	imgui.TextColored(headerColor, 'Battle camera')
	imgui.Separator()
	sliderFloat('Battle distance', ui.battleDistance, 1.0, 40.0, '%.1f', setBattleCameraDistance,
		'Camera distance while engaged. FFXI default: 8.2.')
	sliderFloat('Battle range', ui.battleRange, 0.0, 100.0, '%.0f',
		function(v) setBattleRangeLock(true) setBattleCameraRange(v) end,
		'How far the battle camera may swing around the target: about 180 degrees at 100. FFXI default: 4.\nChanging it turns the range lock on.')
	if imgui.Checkbox('Lock battle range', ui.battleRangeLocked) then
		setBattleRangeLock(ui.battleRangeLocked[1])
		update_settings()
	end
	imgui.ShowHelp('Off lets the battle camera rotate 360 degrees around the target.')

	imgui.Spacing()
	imgui.TextColored(headerColor, 'Camera height')
	imgui.Separator()
	imgui.InputFloat('Height offset', ui.heightOffset, 0.1, 1.0, '%.2f')
	imgui.ShowHelp('Camera Y = reference Y + offset. Applied once; the game keeps moving the camera afterwards.')
	if imgui.Button('Snap height') then
		local cameraY, referenceY = core:snapHeight(ui.heightOffset[1])
		if cameraY ~= nil then
			ui.lastSnap = string.format('Snapped to %.2f (reference %.2f)', cameraY, referenceY)
		else
			ui.lastSnap = 'Camera task not available'
		end
	end
	local cameraY, referenceY = core:cameraHeights()
	if cameraY ~= nil then
		imgui.SameLine()
		imgui.TextDisabled(string.format('camera Y %.2f, reference Y %.2f', cameraY, referenceY))
	end
	if ui.lastSnap ~= nil then imgui.TextDisabled(ui.lastSnap) end

	imgui.Spacing()
	imgui.TextColored(headerColor, 'Options')
	imgui.Separator()
	if imgui.Checkbox('Save on increment/decrement', ui.saveOnIncrement) then
		configs.saveOnIncrement = ui.saveOnIncrement[1]
		update_settings()
	end
	imgui.ShowHelp('Saves settings when incr, decr, bincr or bdecr change a distance.')
	imgui.PopItemWidth()

	imgui.Spacing()
	if imgui.Button('Save') then update_settings() end
	imgui.SameLine()
	if imgui.Button('Reset to defaults') then applyDefaults() end
	imgui.SameLine()
	imgui.TextDisabled('Settings save per character.')
end

local function drawSettingsWindow()
	if not ui.is_open[1] then return end
	syncUiFromConfigs()

	imgui.SetNextWindowSize({ 460, 0 }, ImGuiCond_FirstUseEver)
	-- ### keeps the window's saved position across version bumps.
	if imgui.Begin('XICamera v' .. addon.version .. '###xicamera_settings', ui.is_open, ImGuiWindowFlags_AlwaysAutoResize) then
		if not core.installed then
			imgui.TextColored(badColor, 'XICamera is not active: the float block could not be allocated.')
		elseif not core:active() then
			imgui.TextColored(warnColor, 'Some patch groups are off; those settings have no effect. See Patch status.')
			imgui.Separator()
		end
		if core.installed then drawSettings() end
		imgui.Spacing()
		drawPatchStatus()
	end
	imgui.End()
end

ashita.events.register('d3d_present', 'camera_present', function()
	core:recheck()
	drawSettingsWindow()
end)

-- 0x000A is the zone-in packet. The core re-checks its sites for a minute the first time the
-- character enters the world after the addon loaded; later zones are ignored.
ashita.events.register('packet_in', 'camera_packet_in', function(e)
	if e.id == 0x000A then core:onEnterWorld() end
	return false
end)

----------------------------------------------------------------------------------------------------
-- func: unload
-- desc: Event called when the addon is being unloaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('unload', 'camera_unload', function()
    -- Save the configuration file..
    update_settings()
    core:uninstall()
end)
