/*
 * 	Copyright © 2019, Renee Koecher
 * 	All rights reserved.
 * 
 * 	Redistribution and use in source and binary forms, with or without
 * 	modification, are permitted provided that the following conditions are met :
 * 
 * 	* Redistributions of source code must retain the above copyright
 * 	  notice, this list of conditions and the following disclaimer.
 * 	* Redistributions in binary form must reproduce the above copyright
 * 	  notice, this list of conditions and the following disclaimer in the
 * 	  documentation and/or other materials provided with the distribution.
 * 	* Neither the name of XICamera nor the
 * 	  names of its contributors may be used to endorse or promote products
 * 	  derived from this software without specific prior written permission.
 * 
 * 	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * 	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * 	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * 	DISCLAIMED.IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * 	DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * 	(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * 	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * 	ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * 	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * 	SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "WindowerInterface.h"

namespace XICamera
{
	int WindowerInterface::registerInterface(lua_State *L)
	{
		struct luaL_reg api[] = {
			{ "enable"         , WindowerInterface::lua_enable },
			{ "disable"        , WindowerInterface::lua_disable },
 
			{ "set_camera_distance"  , WindowerInterface::lua_setCameraDistance },
			{ "set_battle_distance"  , WindowerInterface::lua_setBattleDistance },
			{ "set_horizontal_pan_speed"  , WindowerInterface::lua_setHorizontalPanSpeed },
			{ "set_vertical_pan_speed"  , WindowerInterface::lua_setVerticalPanSpeed },

			{ "status"    , WindowerInterface::lua_getStatus },

			{ NULL, NULL }
		};

		luaL_register(L, "_XICamera", api);
		return 1;
	}

	int WindowerInterface::lua_enable(lua_State *L)
	{
		lua_pushboolean(L, instance().initCamera() ? TRUE : FALSE);
		return 1;
	}

	int WindowerInterface::lua_disable(lua_State *L)
	{
		lua_pushboolean(L, instance().removeCamera() ? TRUE : FALSE);
		return 1;
	}

	int WindowerInterface::lua_setCameraDistance(lua_State *L)
	{
		if (lua_gettop(L) != 1 || !lua_isnumber(L, 1))
		{
			lua_pushstring(L, "a valid distance argument is required");
			lua_error(L);
		}

		instance().setCameraDistance(lua_tonumber(L, 1));

		lua_pushnumber(L, instance().cameraDistance());
		return 1;
	}

	int WindowerInterface::lua_setBattleDistance(lua_State* L)
	{
		if (lua_gettop(L) != 1 || !lua_isnumber(L, 1))
		{
			lua_pushstring(L, "a valid distance argument is required");
			lua_error(L);
		}

		instance().setBattleDistance(lua_tonumber(L, 1));

		lua_pushnumber(L, instance().battleDistance());
		return 1;
	}

	int WindowerInterface::lua_setHorizontalPanSpeed(lua_State* L)
	{
		if (lua_gettop(L) != 1 || !lua_isnumber(L, 1))
		{
			lua_pushstring(L, "a valid distance argument is required");
			lua_error(L);
		}

		instance().setHorizontalPanSpeed(lua_tonumber(L, 1));

		lua_pushnumber(L, instance().horizontalPanSpeed());
		return 1;
	}

	int WindowerInterface::lua_setVerticalPanSpeed(lua_State* L)
	{
		if (lua_gettop(L) != 1 || !lua_isnumber(L, 1))
		{
			lua_pushstring(L, "a valid distance argument is required");
			lua_error(L);
		}

		instance().setVerticalPanSpeed(lua_tonumber(L, 1));

		lua_pushnumber(L, instance().verticalPanSpeed());
		return 1;
	}

	int WindowerInterface::lua_getStatus(lua_State* L)
	{
		/* push a table to hold the diagnostics as a whole */
		lua_createtable(L, 1, 2);

		lua_pushboolean(L, instance().cameraActive() ? TRUE : FALSE);
		lua_setfield(L, -2, "enabled");

		lua_pushnumber(L, instance().cameraDistance());
		lua_setfield(L, -2, "cameraDistance");

		lua_pushnumber(L, instance().battleDistance());
		lua_setfield(L, -2, "battleDistance");

		lua_pushnumber(L, instance().horizontalPanSpeed());
		lua_setfield(L, -2, "horizontalPanSpeed");

		lua_pushnumber(L, instance().verticalPanSpeed());
		lua_setfield(L, -2, "verticalPanSpeed");

		return 1;
	}
}

