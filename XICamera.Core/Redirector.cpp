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

		DWORD g_CameraPositionReturnAddress; // Camera return address to allow the code cave to return properly.
		DWORD g_CameraAddress; // Camera address to identify where to start injecting.
		DWORD g_CameraSpeedReturnAddress; // Camera Speed return address to allow the code cave to return properly.
		DWORD g_SpeedAddress; // Camera Speed address to identify where to start injecting.
		DWORD g_MaxCameraAddress; // Camera Max distance address to identify where to start injecting.
		DWORD g_MaxCameraBattleAddress; // Camera Max distance in Battle address to identify where to start injecting.
		int g_cameraDistance = 6;
		float g_cameraMoveSpeed = 0.0f;

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
			m_redirectSet = false;
			g_cameraDistance = 6;
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
			__asm fadd dword ptr [edi + 0x48];
			__asm fstp dword ptr [edi + 0x48];

			__asm fld dword ptr [edi + 0x44];
			__asm fsubr dword ptr [edi + 0x50];
			__asm fld st(0);
			__asm fmulp st(1), st(0);

			__asm fld dword ptr [edi + 0x48];
			__asm fsubr dword ptr [edi + 0x54];
			__asm fld st(0);
			__asm fmulp st(1), st(0);

			__asm faddp st(1), st(0);

			__asm fld dword ptr [edi + 0x4C];
			__asm fsubr dword ptr [edi + 0x58];
			__asm fld st(0);
			__asm fmulp st(1), st(0);

			__asm faddp st(1), st(0);

			__asm fsqrt;

			__asm push g_cameraDistance;

			__asm fild [esp];
			__asm fcomip st(0), st(1);
			__asm jb done_distance;

			__asm fld dword ptr [edi + 0x44];
			__asm fsub dword ptr [edi + 0x50];
			__asm fdiv st(0), st(1);
			__asm fild [esp];
			__asm fmulp st(1), st(0);
			__asm fadd dword ptr [edi + 0x50];
			__asm fstp dword ptr [edi + 0x44];

			__asm fld dword ptr [edi + 0x48];
			__asm fsub dword ptr [edi + 0x54];
			__asm fdiv st(0), st(1);
			__asm fild [esp];
			__asm fmulp st(1), st(0);
			__asm fadd dword ptr [edi + 0x54];
			__asm fstp dword ptr [edi + 0x48];

			__asm fld dword ptr [edi + 0x4C];
			__asm fsub dword ptr [edi + 0x58];
			__asm fdiv st(0), st(1);
			__asm fild [esp];
			__asm fmulp st(1), st(0);
			__asm fadd dword ptr [edi + 0x58];
			__asm fstp dword ptr [edi + 0x4C];

			__asm done_distance:;
			__asm fstp st(0);
			__asm add esp, 4;

			__asm jmp g_CameraPositionReturnAddress;
		}

		/**
		 * @brief Camera Speed fix codecave.
		 */
		__declspec(naked) void CameraSpeed(void)
		{
			__asm push g_cameraMoveSpeed;
			__asm fadd dword ptr [esp];
			__asm add esp, 4;

			__asm fmul dword ptr [esp + 0x24];
			__asm mov edx, [esi];

			__asm jmp g_CameraSpeedReturnAddress;
		}


		bool Redirector::setupRedirect(void)
		{
			if (m_redirectSet == false)
			{
				m_redirectSet = true;

				// redirect set logic here
				g_CameraAddress = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\x47\x48\xD9\x5F\x48\xE8", "xxxxxxx");
				if (g_CameraAddress == 0)
				{
					m_redirectSet = false;
					// REPORT FAILURE
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find camera position");
					return 0;
				}
				auto caveDest = ((int)CalcCameraPosition - ((int)g_CameraAddress)) - 5;
				g_CameraPositionReturnAddress = g_CameraAddress + 0x06;

				*(BYTE*)(g_CameraAddress + 0x00) = 0xE9; // jmp
				*(UINT*)(g_CameraAddress + 0x01) = caveDest;
				*(BYTE*)(g_CameraAddress + 0x05) = 0x90; // nop

				m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_redirectSet = %s", m_redirectSet ? "true" : "false");


				g_SpeedAddress = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\x4C\x24\x24\x8B\x16\x8B\xCE\xD8\x0D", "xxxxxxxxxx");
				if (g_SpeedAddress == 0)
				{
					m_redirectSet = false;
					// REPORT FAILURE
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find camera position");
					return 0;
				}
				auto caveSpeedDest = ((int)CameraSpeed - ((int)g_SpeedAddress)) - 5;
				g_CameraSpeedReturnAddress = g_SpeedAddress + 0x06;

				*(BYTE*)(g_SpeedAddress + 0x00) = 0xE9; // jmp
				*(UINT*)(g_SpeedAddress + 0x01) = caveSpeedDest;
				*(BYTE*)(g_SpeedAddress + 0x05) = 0x90; //nop

				m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_redirectSet = %s", m_redirectSet ? "true" : "false");

				g_MaxCameraAddress = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x00\x00\xC0\x40\xCE\xC1\xE4\x3C", "xxxxxxxx");
				if (g_MaxCameraAddress != 0)
				{
					DWORD dwProtect;
					VirtualProtect((void*)g_MaxCameraAddress, 4, PAGE_READWRITE, &dwProtect);
					*(FLOAT*)(g_MaxCameraAddress) = g_cameraDistance;
				}

				g_MaxCameraBattleAddress = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x9A\x99\x09\x41\x66\x66\xE6\x40", "xxxxxxxx");
				if (g_MaxCameraBattleAddress != 0)
				{
					DWORD dwProtect;
					VirtualProtect((void*)g_MaxCameraBattleAddress, 4, PAGE_READWRITE, &dwProtect);
					*(FLOAT*)(g_MaxCameraBattleAddress) = g_cameraDistance / 0.24f;
				}

				return m_redirectSet;
			}

			m_logger->logMessage(m_logDebug, "redirect already set");
			return false;
		}

		bool Redirector::removeRedirect(void)
		{
			m_redirectSet = false;
			if (g_CameraAddress != 0)
			{
				*(BYTE*)(g_CameraAddress + 0x00) = 0xD8;
				*(BYTE*)(g_CameraAddress + 0x01) = 0x47;
				*(BYTE*)(g_CameraAddress + 0x02) = 0x48;
				*(BYTE*)(g_CameraAddress + 0x03) = 0xD9;
				*(BYTE*)(g_CameraAddress + 0x04) = 0x5F;
				*(BYTE*)(g_CameraAddress + 0x05) = 0x48;
			}

			if (g_SpeedAddress != 0)
			{
				*(BYTE*)(g_SpeedAddress + 0x00) = 0xD8;
				*(BYTE*)(g_SpeedAddress + 0x01) = 0x4C;
				*(BYTE*)(g_SpeedAddress + 0x02) = 0x24;
				*(BYTE*)(g_SpeedAddress + 0x03) = 0x24;
				*(BYTE*)(g_SpeedAddress + 0x04) = 0x8B;
				*(BYTE*)(g_SpeedAddress + 0x05) = 0x16;
			}

			if (g_MaxCameraAddress != 0)
			{
				*(FLOAT*)(g_MaxCameraAddress) = 6.0f;
			}

			if (g_MaxCameraBattleAddress != 0)
			{
				*(FLOAT*)(g_MaxCameraBattleAddress) = 8.6f;
			}

			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_redirectSet = %s", m_redirectSet ? "true" : "false");
			return m_redirectSet;
		}

		void Redirector::setDebugLog(bool state)
		{
			m_logDebug = (state) ? ILogProvider::LogLevel::Debug : ILogProvider::LogLevel::Discard;
			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_logDebug = %s", state ? "Debug" : "Discard");
		}

		bool Redirector::setCameraDistance(const int &newDistance)
		{
			g_cameraDistance = newDistance;
			m_cameraDistance = newDistance;

			g_cameraMoveSpeed = newDistance / 10.0f;

			if (g_MaxCameraAddress != 0)
			{
				*(FLOAT*)(g_MaxCameraAddress) = g_cameraDistance;
			}

			if (g_MaxCameraBattleAddress != 0)
			{
				*(FLOAT*)(g_MaxCameraBattleAddress) = g_cameraDistance / 0.24f;
			}

			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_cameraDistance = '%d'", m_cameraDistance);

			return true;
		}
	}
}