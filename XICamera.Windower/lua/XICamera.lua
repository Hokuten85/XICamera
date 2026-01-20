--[[
 	Copyright © 2019, Hokuten
 	All rights reserved.
 
 	Redistribution and use in source and binary forms, with or without
 	modification, are permitted provided that the following conditions are met :
 
 	* Redistributions of source code must retain the above copyright
 	  notice, this list of conditions and the following disclaimer.
 	* Redistributions in binary form must reproduce the above copyright
 	  notice, this list of conditions and the following disclaimer in the
 	  documentation and/or other materials provided with the distribution.
 	* Neither the name of XICamera nor the
 	  names of its contributors may be used to endorse or promote products
 	  derived from this software without specific prior written permission.
 
 	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 	DISCLAIMED.IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 	DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 	(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 	ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 	SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name = 'XICamera'
_addon.author = 'Hokuten'
_addon.version = '0.7.10'
_addon.commands = {'camera','cam','xicamera','xicam'}

config = require('config')
require('pack')
require('lists')
require('tables')

defaults = T{
    cameraDistance = 6,
	battleDistance = 8.2,
	horizontalPanSpeed = 3.0,
	verticalPanSpeed = 10.7,
	saveOnIncrement = false,
	autoCalcVertSpeed = true,
	battleRange = 4.0,
	battleRangeLocked = true,
}

settings = config.load(defaults)
config.save(settings)

local addon_path = windower.addon_path:gsub('\\', '/')	
package.cpath = package.cpath .. ';' .. addon_path .. '/libs/?.dll'
require('_XICamera')

windower.register_event('load', function()
    _XICamera.disable()
    _XICamera.set_camera_distance(settings.cameraDistance)
	_XICamera.set_battle_distance(settings.battleDistance)
	_XICamera.set_horizontal_pan_speed(settings.horizontalPanSpeed)
	if settings.autoCalcVertSpeed then
		_XICamera.set_vertical_pan_speed(defaults.verticalPanSpeed * settings.cameraDistance / 6)
	else
		_XICamera.set_vertical_pan_speed(settings.verticalPanSpeed)
	end
	_XICamera.set_battle_camera_range(settings.battleRange)
	_XICamera.set_battle_range_lock(settings.battleRangeLocked)
    _XICamera.enable()
end)

windower.register_event('unload', function()
	_XICamera.disable()
end)

windower.register_event('addon command', function(command, ...)
	command = command and command:lower() or 'help'
	local args = L{...}

	if table.contains(T{'help', 'h'}, command)  then
		windower.add_to_chat(8, _addon.name .. ' v.' .. _addon.version)
		windower.add_to_chat(8, '   d|distance # - sets the camera distance - default: 6')
		windower.add_to_chat(8, '   b|battle # - sets the camera distance - default: 8')
		windower.add_to_chat(8, '   hs|hspeed # - sets the horizontal pan speed - default: 3')
		windower.add_to_chat(8, '   vs|vspeed # - sets the vertical pan - default: 10, forces auto calc off')
		windower.add_to_chat(8, '   s|status - Print status and diagnostic info')
		windower.add_to_chat(8, '   in|incr - Increment current camera distance by one')
        windower.add_to_chat(8, '   de|decr - Decrement current camera distance by one')
		windower.add_to_chat(8, '   bin|bincr - Increment current battle camera distance by one')
        windower.add_to_chat(8, '   bde|bdecr - Decrement current battle camera distance by one')
		windower.add_to_chat(8, '   saveOnIncrement|soi - Toggles Saving on increment/decrement behavior - default: off')
		windower.add_to_chat(8, '   autoCalcVertSpeed|acv - Toggles Vertical pan speed autocalc - default: on')
		windower.add_to_chat(8, '   brange|br # - Set Battle Camera Range: - default: 4, , min: 0, max: 100, forces battle range lock on')
		windower.add_to_chat(8, '   battlelock|bl <on|true|1|off|false|0> - Unlock Battle Camera Range')

	elseif table.contains(T{'distance', 'd'}, command) then
		if not args[1] then
			error('Invalid syntax: //camera distance <number>')
			return
		end

		if _XICamera.set_camera_distance(tonumber(args[1])) > 0 then
            windower.add_to_chat(8, 'set camera distance to "' .. tonumber(args[1]) .. '"')
            settings.cameraDistance = tonumber(args[1])
			config.save(settings)

			if settings.autoCalcVertSpeed then
				_XICamera.set_vertical_pan_speed(defaults.verticalPanSpeed * settings.cameraDistance / 6)
			end
		else
			windower.add_to_chat(8, 'failed to change distance "' .. args[1] .. '"')
		end
	elseif table.contains(T{'battle', 'b'}, command) then
		if not args[1] then
			error('Invalid syntax: //camera battle <number>')
			return
		end

		if _XICamera.set_battle_distance(tonumber(args[1])) > 0 then
            windower.add_to_chat(8, 'set battle distance to "' .. tonumber(args[1]) .. '"')
            settings.battleDistance = tonumber(args[1])
			config.save(settings)
		else
			windower.add_to_chat(8, 'failed to change battle distance "' .. args[1] .. '"')
		end
	elseif table.contains(T{'hspeed', 'hs'}, command) then
		if not args[1] then
			error('Invalid syntax: //camera hspeed <number>')
			return
		end

		if _XICamera.set_horizontal_pan_speed(tonumber(args[1])) > 0 then
            windower.add_to_chat(8, 'set horizontal pan speed to "' .. tonumber(args[1]) .. '"')
            settings.horizontalPanSpeed = tonumber(args[1])
			config.save(settings)
		else
			windower.add_to_chat(8, 'failed to set horizontal pan speed "' .. args[1] .. '"')
		end
	elseif table.contains(T{'vspeed', 'vs'}, command) then
		if not args[1] then
			error('Invalid syntax: //camera vspeed <number>')
			return
		end

		if _XICamera.set_vertical_pan_speed(tonumber(args[1])) > 0 then
            windower.add_to_chat(8, 'set vertical pan speed to "' .. tonumber(args[1]) .. '"')
            settings.verticalPanSpeed = tonumber(args[1])
			settings.autoCalcVertSpeed = false
			config.save(settings)
		else
			windower.add_to_chat(8, 'failed to set vertical pan speed "' .. args[1] .. '"')
		end
	elseif table.contains(T{'incr', 'in', 'bincr', 'bin', 'decr', 'de', 'bdecr', 'bde'}, command) then
		local isIncr = string.find(command, 'in')
		local isBattle = string.find(command, 'b')
		local newDistance = (isBattle and settings.battleDistance or settings.cameraDistance) + (isIncr and 1 or -1)
		local camTypeFunction = isBattle and _XICamera.set_battle_distance or _XICamera.set_camera_distance
		if camTypeFunction(newDistance) > 0 then
			windower.add_to_chat(8, 'set ' .. (isBattle and 'battle ' or '') .. 'camera distance to "' .. newDistance .. '"')
			if isBattle then settings.battleDistance = newDistance else settings.cameraDistance = newDistance end
			if settings.saveOnIncrement then config.save(settings) end
		else
			windower.add_to_chat(8, 'failed to change ' .. (isBattle and 'battle ' or '') .. 'distance "' .. newDistance .. '"')
		end
	elseif table.contains(T{'saveOnIncrement', 'soi'}, command) then
		settings.saveOnIncrement = not settings.saveOnIncrement
		windower.add_to_chat(8, 'set saveOnIncrement to "' .. tostring(settings.saveOnIncrement) .. '"')
		config.save(settings)
	elseif table.contains({'autocalcvertspeed', 'acv'}, command) then
		settings.autoCalcVertSpeed = not settings.autoCalcVertSpeed
		windower.add_to_chat(8, "autoCalcVertSpeed changed to " .. tostring(settings.autoCalcVertSpeed))
		config.save(settings)
	elseif table.contains({'brange', 'br'}, command) then
		if (tonumber(args[1])) then
		    local newRange = math.min(math.max(0, tonumber(args[1])), 100)

			_XICamera.set_battle_range_lock(true)
			if _XICamera.set_battle_camera_range(newRange) > 0 then
				settings.battleRange = newRange
				config.save(settings)
				windower.add_to_chat(8, 'Battle camera range changed to "' .. newRange .. '"')
			else
				windower.add_to_chat(8, 'failed to set battle camera range "' .. newRange .. '"')
			end
		end
	elseif table.contains({'battlelock', 'bl'}, command) then
		if table.contains({'on', 'true' , '1'}, tostring(args[1])) then
			_XICamera.set_battle_range_lock(true)
			settings.battleRangeLocked = true
			config.save(settings)
			windower.add_to_chat(8, 'Battle camera range locked.')
		elseif table.contains({'off', 'false' , '0'}, tostring(args[1])) then
			_XICamera.set_battle_range_lock(false)
			settings.battleRangeLocked = false
			config.save(settings)
			windower.add_to_chat(8, 'Battle camera range unlocked.')
		end
	elseif table.contains(T{'status', 's'}, command) then
		local stats = _XICamera.status()
		windower.add_to_chat(127,'- status')
		windower.add_to_chat(127, '-  cameraDistance: ' .. stats['cameraDistance'])
		windower.add_to_chat(127, '-  battleDistance: ' .. stats['battleDistance'])
		windower.add_to_chat(127, '-  horizontalPanSpeed: ' .. stats['horizontalPanSpeed'])
		windower.add_to_chat(127, '-  verticalPanSpeed: ' .. stats['verticalPanSpeed'])
		windower.add_to_chat(127, '-  saveOnIncrement: ' .. tostring(settings.saveOnIncrement))
		windower.add_to_chat(127, '-  autoCalcVertSpeed: ' .. tostring(settings.autoCalcVertSpeed))
		windower.add_to_chat(127, '-  battleRange: ' .. tostring(settings.battleRange))
		windower.add_to_chat(127, '-  battleRangeLocked: ' .. tostring(settings.battleRangeLocked))
	end
end)
