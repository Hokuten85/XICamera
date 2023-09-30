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

#pragma once

extern "C"
{
#	define LUA_BUILD_AS_DLL

#	include "lauxlib.h"
#	include "lua.h"
}

#include "Camera.h"

namespace XICamera
{
	/* a simple, mostly static interface addon-on to
	 * provide interopperability with the LUA-C API 
	 */
	class WindowerInterface : public Core::Camera
	{
		public:
			~WindowerInterface(void) {};

			static int registerInterface(lua_State *L);

			/* interface methods */

			/* internally calls Camera::setupHooks
			 *
			 * arguments: none
			 * returns: a boolean indicating the operation result
			 */
			static int lua_enable(lua_State *L);

			/* internally calls Camera::removeHooks
			 *
			 * arguments: none
			 * returns: a boolean representing the operation result
			 */
			static int lua_disable(lua_State *L);

			/* internally calls Camera::setCameraDistance
			 *
			 * arguments: [1] - int: newDistance
			 * returns: a boolean representing the operation result
			 */
			static int lua_setCameraDistance(lua_State *L);

			/* internally calls Camera::setBattleDistance
			 *
			 * arguments: [1] - int: newDistance
			 * returns: a boolean representing the operation result
			 */
			static int lua_setBattleDistance(lua_State* L);

			/* internally calls Camera::setHorizontalPanSpeed
			 *
			 * arguments: [1] - int: newSpeed
			 * returns: a boolean representing the operation result
			 */
			static int lua_setHorizontalPanSpeed(lua_State* L);

			/* internally calls Camera::setVerticalPanSpeed
			 *
			 * arguments: [1] - int: newSpeed
			 * returns: a boolean representing the operation result
			 */
			static int lua_setVerticalPanSpeed(lua_State* L);

			/* collects some of the internal data of the Camera
			 *
			 * arguments: none
			 * returns: a table of the following make-up
			 *  {
			 *		"enabled": <boolean>,
			 *      "camera distance": <int>
			 *      "battle distance": <int>
			 *  }
			 */
			static int lua_getStatus(lua_State* L);

		protected:
			WindowerInterface(void) : Camera() {};
	};
}

