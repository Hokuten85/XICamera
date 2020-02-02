#include "Redirector.h"
#include <rpc.h>
#include <cctype>
#include <algorithm>
#include "functions.h"

namespace XICamera
{
	namespace Core
	{
		Redirector* Redirector::s_instance = nullptr;

		DWORD g_CameraPositoinReturnAddress; // Camera return address to allow the code cave to return properly.
		DWORD g_CameraAddress; // Camera address to identify where to start injecting.
		int g_cameraDistance = 5;

		Redirector& Redirector::instance(void)
		{
			if (Redirector::s_instance == nullptr)
			{
				Redirector::s_instance = new Redirector();
			}
			return *Redirector::s_instance;
		}

		Redirector::Redirector()
			: m_redirectSet(false)
		{
			m_cameraDistance = 5;
			m_logger = DummyLogProvider::instance();
		}

		Redirector::~Redirector()
		{
			removeRedirect(); // just in case
		}

		void Redirector::setLogProvider(ILogProvider* newLogProvider)
		{
			if (newLogProvider == nullptr)
			{
				return;
			}
			m_logger = newLogProvider;
		}

		/**
		 * @brief Camera Position fix codecave.
		 */
		__declspec(naked) void CalcCameraPosition(void)
		{
			__asm fstp dword ptr [esi + 0x4C];
			__asm fstp st(0);

			__asm fld dword ptr [esi + 0x44];
			__asm fsubr dword ptr [esi + 0x50];
			__asm fld st(0);
			__asm fmulp st(1), st(0);

			__asm fld dword ptr [esi + 0x48];
			__asm fsubr dword ptr [esi + 0x54];
			__asm fld st(0);
			__asm fmulp st(1), st(0);

			__asm faddp st(1), st(0);

			__asm fld dword ptr [esi + 0x4C];
			__asm fsubr dword ptr [esi + 0x58];
			__asm fld st(0);
			__asm fmulp st(1), st(0);

			__asm faddp st(1), st(0);

			__asm fsqrt;

			__asm push g_cameraDistance;

			__asm fld dword ptr [esi + 0x44];
			__asm fsub dword ptr [esi + 0x50];
			__asm fdiv st(0), st(1);
			__asm fild [esp];
			__asm fmulp st(1), st(0);
			__asm fadd dword ptr [esi + 0x50];
			__asm fstp dword ptr [esi + 0x44];

			__asm fld dword ptr [esi + 0x48];
			__asm fsub dword ptr [esi + 0x54];
			__asm fdiv st(0), st(1);
			__asm fild [esp];
			__asm fmulp st(1), st(0);
			__asm fadd dword ptr [esi + 0x54];
			__asm fstp dword ptr [esi + 0x48];

			__asm fld dword ptr [esi + 0x4C];
			__asm fsub dword ptr [esi + 0x58];
			__asm fdiv st(0), st(1);
			__asm fild [esp];
			__asm fmulp st(1), st(0);
			__asm fadd dword ptr [esi + 0x58];
			__asm fstp dword ptr [esi + 0x4C];
			__asm fstp st(0);

			__asm add esp, 4;

			__asm jmp g_CameraPositoinReturnAddress;
		}


		bool Redirector::setupRedirect(void)
		{
			if (m_redirectSet == false)
			{
				m_redirectSet = true;

				// redirect set logic here
				g_CameraAddress = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD9\x5E\x4C\xDD\xD8\xE8", "xxxxxx");
				if (g_CameraAddress == 0)
				{
					// REPORT FAILURE
					//xiloader::console::output(xiloader::color::error, "Failed to locate main hairpin hack address!");
					//return 0;
				}
				auto caveDest = ((int)CalcCameraPosition - ((int)g_CameraAddress)) - 5;
				g_CameraPositoinReturnAddress = g_CameraAddress + 0x05;

				*(BYTE*)(g_CameraAddress + 0x00) = 0xE9; // jmp
				*(UINT*)(g_CameraAddress + 0x01) = caveDest;

				m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_redirectSet = %s", m_redirectSet ? "true" : "false");

				return m_redirectSet;
			}

			m_logger->logMessage(m_logDebug, "redirect already set");
			return false;
		}

		bool Redirector::removeRedirect(void)
		{
			if (m_redirectSet == true)
			{
				m_redirectSet = false;

				if (g_CameraAddress != 0)
				{
					*(BYTE*)(g_CameraAddress + 0x00) = 0xD9;
					*(BYTE*)(g_CameraAddress + 0x01) = 0x5E;
					*(BYTE*)(g_CameraAddress + 0x02) = 0x4C;
					*(BYTE*)(g_CameraAddress + 0x03) = 0xDD;
					*(BYTE*)(g_CameraAddress + 0x04) = 0xD8;
				}

				m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_redirectSet = %s", m_redirectSet ? "true" : "false");
				return m_redirectSet;
			}

			m_logger->logMessage(m_logDebug, "redirect already removed");
			return false;
		}

		void Redirector::setDebugLog(bool state)
		{
			m_logDebug = (state) ? ILogProvider::LogLevel::Debug : ILogProvider::LogLevel::Discard;
			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_logDebug = %s", state ? "Debug" : "Discard");
		}

		void Redirector::setCameraDistance(const int &newDistance)
		{
			g_cameraDistance = newDistance;
			m_cameraDistance = newDistance;
			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_cameraDistance = '%d'", m_cameraDistance);
		}
	}
}