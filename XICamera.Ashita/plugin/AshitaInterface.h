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

#include <string>
#include "ADK/Ashita.h"
#include "Camera.h"

namespace XICamera
{
	class AshitaInterface : public IPlugin, public Core::ILogProvider, private Core::Camera
	{

	public:
		AshitaInterface(void);
		virtual ~AshitaInterface(void) {};

		/* Ashita plugin requirements */

		plugininfo_t GetPluginInfo(void) override;

		bool Initialize(IAshitaCore *core, ILogManager *log, uint32_t id) override;
		void Release(void);

		bool HandleCommand(const char *command, int32_t type) override;

		/* ILogProvider */
		void logMessage(Core::ILogProvider::LogLevel level, std::string msg);
		void logMessageF(Core::ILogProvider::LogLevel level, std::string msg, ...);

	public:
		static plugininfo_t *s_pluginInfo;

	private:
		/* a little wrapper around Write() and Writef() with support for colours */
		void chatPrint(const char *msg);
		void chatPrintf(const char *fmt, ...);

		struct Settings
		{
			Settings();

			bool load(IConfigurationManager *config);
			void save(IConfigurationManager *config);

			bool debugLog;
			int cameraDistance;
			int battleDistance;
		};

		Settings               m_settings;

		/* UI state */
		bool                     m_showConfigWindow;

		struct
		{
			bool        debugState;
			bool		removeCamera;
			bool        initCamera;
		} m_uiConfig;

		/* Ashita runtime data */
		uint32_t               m_pluginId;

		IAshitaCore           *m_ashitaCore;
		ILogManager           *m_logManager;
		IDirect3DDevice8      *m_direct3DDevice;
		IConfigurationManager *m_config;
	};
}

