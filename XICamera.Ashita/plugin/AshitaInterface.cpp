/*
 * 	Copyright � 2019, Renee Koecher
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

#include <string>
#include "AshitaInterface.h"

#include <regex>

#define _XI_RESET    "\x1E\x01"
#define _XI_NORMAL   "\x1E\x01"
#define _XI_LGREEN   "\x1E\x02"
#define _XI_PINK     "\x1E\x05"
#define _XI_DEEPBLUE "\x1E\x05"
#define _XI_SEAFOAM  "\x1E\x53"
#define _XI_CREAM    "\x1F\x82"

namespace XICamera
{
	plugininfo_t *AshitaInterface::s_pluginInfo = nullptr;

	AshitaInterface::AshitaInterface(void)
	  : Core::Redirector(),
	
	    m_showConfigWindow(false),
	    m_pluginId(0),
	    m_ashitaCore(nullptr),
	    m_logManager(nullptr),
	    m_direct3DDevice(nullptr)
	{
		/* FIXME: does this play anywhere nice with reloads?
		 * FIXME: .. I hope it does
		 */
		Redirector::s_instance = this;

		m_uiConfig.debugState = false;
		m_uiConfig.setRedirect = false;
		m_uiConfig.removeRedirect = false;
	}

	plugininfo_t AshitaInterface::GetPluginInfo(void)
	{
		return *AshitaInterface::s_pluginInfo;
	}

	bool AshitaInterface::Initialize(IAshitaCore *core, ILogManager *log, uint32_t id)
	{
		m_ashitaCore = core;
		m_logManager = log;
		m_pluginId = id;
		m_config = (core ? core->GetConfigurationManager() : nullptr);

		instance().setLogProvider(this);

		if (m_config != nullptr)
		{
			if (m_settings.load(m_config))
			{
				instance().setDebugLog(m_settings.debugLog);
				instance().setCameraDistance(m_settings.cameraDistance);
			}
			m_settings.save(m_config);
		}

		return instance().setupRedirect();
	}

	void AshitaInterface::Release(void)
	{
		instance().removeRedirect();
	}

	bool AshitaInterface::HandleCommand(const char *command, int32_t /*type*/)
	{
		std::vector<std::string> args;
		Ashita::Commands::GetCommandArgs(command, &args);

		HANDLECOMMAND("/camera")
		{
			if (args.size() == 3)
			{
				if (args[1] == "d" || args[1] == "distance")
				{
					int distance = std::stoi(args[2]);
					if (instance().setCameraDistance(distance))
					{
						m_settings.cameraDistance = distance;
						m_settings.save(m_config);
					}
					else
					{
						chatPrintf("$cs(7)failed to set distance '$cs(9)%d$cs(7)'.$cr", distance);
					}

				}
			}
			else if (args.size() == 2 && (args[1] == "h" || args[1] == "help"))
			{
				chatPrintf("$cs(16)%s$cs(19) v.$cs(16)%.2f$cs(19) by $cs(14)%s$cr", s_pluginInfo->Name, s_pluginInfo->PluginVersion, s_pluginInfo->Author);
				chatPrintf("   $cs(9)d$cs(16)istance # $cs(19)- Sets the camera distance$cr");
			}
			return true;
		}

		return false;
	}

	/* ILogProvider */
	void AshitaInterface::logMessage(Core::ILogProvider::LogLevel level, std::string msg)
	{
		logMessageF(level, msg);
	}

	void AshitaInterface::logMessageF(Core::ILogProvider::LogLevel level, std::string msg, ...)
	{
		if (level != Core::ILogProvider::LogLevel::Discard)
		{
			char msgBuf[512];
			Ashita::LogLevel ashitaLevel = Ashita::LogLevel::None;

			switch (level)
			{
				case Core::ILogProvider::LogLevel::Discard: /* never acutally reached */
					return;

				case Core::ILogProvider::LogLevel::Debug:
					ashitaLevel = Ashita::LogLevel::Debug;
					break;

				case Core::ILogProvider::LogLevel::Info:
					ashitaLevel = Ashita::LogLevel::Information;
					break;

				case Core::ILogProvider::LogLevel::Warn:
					ashitaLevel = Ashita::LogLevel::Warning;
					break;

				case Core::ILogProvider::LogLevel::Error:
					ashitaLevel = Ashita::LogLevel::Error;
					break;
			}

			va_list args;
			va_start(args, msg);

			vsnprintf_s(msgBuf, 511, msg.c_str(), args);
			m_logManager->Log(static_cast<uint32_t>(ashitaLevel), "XICamera", msgBuf);

			va_end(args);
		}
	}

	/* private parts below */

	AshitaInterface::Settings::Settings()
	{
		cameraDistance = 5;
		debugLog = false;
	}

	bool AshitaInterface::Settings::load(IConfigurationManager *config)
	{
		if (config->Load("XICamera", "XICamera"))
		{
			const int32_t cD = config->get_int32("XICamera", "cameraDistance",5);
			const bool dbg = config->get_bool("XICamera", "debug_log", true);

			debugLog = dbg;
			cameraDistance = cD;

			return true;
		}
		return false;
	}

	void AshitaInterface::Settings::save(IConfigurationManager *config)
	{
		config->set_value("XICamera", "cameraDistance", std::to_string(cameraDistance).c_str());
		config->Save("XICamera", "XICamera");
	}

	void AshitaInterface::chatPrint(const char *msg)
	{
		/* chatPrint works just like the Write method of ChatManager, except that
		 * it adds some convenience escapes:
		 *  $cs(index)  - will change the text colour to `index` from the below table
		 *  $cr         - will reset the text colour
		 */
		static const char *colourTab[] = 
		{
			/* thanks to atom0s in the Ashita discord for figuring these out */
			"\x1e\x01", /* 0  - reset / white   */
			"\x1e\x02", /* 1  - neon green      */
			"\x1e\x03", /* 2  - deep periwinkle */
			"\x1e\x05", /* 3  - pink            */
			"\x1e\x06", /* 4  - deep cyan       */
			"\x1e\x07", /* 5  - cream           */
			"\x1e\x08", /* 6  - deep orange     */
			"\x1e\x44", /* 7  - red             */
			"\x1e\x45", /* 8  - yellow          */
			"\x1e\x47", /* 9  - slate blue      */
			"\x1e\x48", /* 10 - deep pink       */
			"\x1e\x49", /* 11 - light pink      */
			"\x1e\x4c", /* 12 - deep red        */
			"\x1e\x4f", /* 13 - green           */
			"\x1e\x51", /* 14 - purple          */
			"\x1e\x52", /* 15 - light cyan      */
			"\x1e\x53", /* 16 - seafoam         */
			"\x1e\x5d", /* 17 - light red       */
			"\x1e\x6d", /* 18 - light yellow    */
			"\x1f\x82", /* 19 - cream white     */
		};

		char *parsed = new char[strlen(msg) * 2], *p = parsed;

		memset(parsed, 0, strlen(msg) * 2);
		for (auto i = 0U; i < strlen(msg); )
		{
			switch (msg[i])
			{
				case '$':
				{
					auto j = i, ci = 0U;
					bool copyColour = false;

					/* check for a colour selection "$cs(123..)" */
					if (strncmp(&msg[i], "$cs(", 4) == 0)
					{
						j += 4;
						while (j < strlen(msg) && isdigit(msg[j]))
						{
							ci *= 10;
							ci += msg[j++] - '0';
						}

						if (msg[j] == ')')
						{
							/* if it's within the table mark it for copy */
							copyColour = (ci < sizeof(colourTab));
							i = j + 1;
						}
						else
						{
							*p++ = '$';
							++i;
						}
					}
					/* check for a colour reset $cr */
					else if (strncmp(&msg[i], "$cr", 3) == 0)
					{
						copyColour = true;
						ci = 0;
						i += 3;
					}
					else
					{
						if (strncmp(&msg[i], "$$", 2) == 0)
						{
							*p++ = '$';
							i += 2;
						}
						else
						{
							*p++ = '$';
							++i;
						}
					}

					if (copyColour)
					{
						auto len = strlen(colourTab[ci]);
						strncat_s(p, len + 1, colourTab[ci], len);
						p += strlen(colourTab[ci]);
					}
				}
				break;

			default:
				*p++ = msg[i++];
				break;
			}
		}

		if (m_ashitaCore != nullptr)
		{
			m_ashitaCore->GetChatManager()->Write(parsed);
		}
		delete[] parsed;
	}

	void AshitaInterface::chatPrintf(const char *fmt, ...)
	{
		char msg[512]; /* wildly random size.. */

		va_list args;
		va_start(args, fmt);
		vsnprintf_s(msg, sizeof(msg), sizeof(msg) - 1, fmt, args);
		va_end(args);

		chatPrint(msg);
	}
}
