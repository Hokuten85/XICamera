#include "Camera.h"
#include <rpc.h>
#include <cctype>
#include <algorithm>
#include "functions.h"

namespace XICamera
{
	namespace Core
	{
		Camera* Camera::s_instance = nullptr;

		DWORD g_SpeedReturnAddress; // Camera Speed return address to allow the code cave to return properly.
		DWORD g_SpeedAddress; // Camera Speed address to identify where to start injecting.
		DWORD g_MinCameraAddress; // Camera Min distance address.
		DWORD g_MaxCameraAddress; // Camera Max distance address.
		DWORD g_MinBattleAddress; // Camera Max distance in Battle.
		DWORD g_MaxBattleAddress; // Camera Max distance in Battle.
		DWORD g_ZoomOnZoneInSetupAddress;
		DWORD g_WalkAnimationAddress;
		DWORD g_NPCWalkAnimationAddress;

		float g_OriginalMinDistance;
		float g_OriginalMaxDistance;
		float g_OriginalMinBattleDistance;
		float g_OriginalMaxBattleDistance;
		float g_NewMinDistance;

		float g_cameraMoveSpeed;

		Camera& Camera::instance(void)
		{
			if (Camera::s_instance == nullptr)
			{
				Camera::s_instance = new Camera();
			}
			return *Camera::s_instance;
		}

		Camera::Camera()
			: m_cameraSet(false)
		{
			m_logger = DummyLogProvider::instance();
		}

		Camera::~Camera()
		{
			removeCamera(); // just in case
		}

		void Camera::setLogProvider(ILogProvider* newLogProvider)
		{
			if (newLogProvider == nullptr)
			{
				return;
			}
			m_logger = newLogProvider;
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

			__asm jmp g_SpeedReturnAddress;
		}


		bool Camera::initCamera(void)
		{
			if (m_cameraSet == false)
			{
				g_SpeedAddress = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\x4C\x24\x24\x8B\x16\x8B\xCE\xD8\x0D", "xxxxxxxxxx");
				if (g_SpeedAddress == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find camera speed position");
					return 0;
				}
				auto caveSpeedDest = ((int)CameraSpeed - ((int)g_SpeedAddress)) - 5;
				g_SpeedReturnAddress = g_SpeedAddress + 0x06;

				*(BYTE*)(g_SpeedAddress + 0x00) = 0xE9; // jmp
				*(UINT*)(g_SpeedAddress + 0x01) = caveSpeedDest;
				*(BYTE*)(g_SpeedAddress + 0x05) = 0x90; //nop

				m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_cameraSet = %s", m_cameraSet ? "true" : "false");

				g_MinCameraAddress = *(DWORD*)(XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\xC9\xD9\xC0\xD8\xC1\xD9\xC2\xD8\x0D\xFF\xFF\xFF\xFF\xD9\xC3\xDC\xC0\xD8\xEB", "xxxxxxxxxx????xxxxxx") + 0x0A);
				if (g_MinCameraAddress == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find min camera distance");
					return 0;
				}
				g_OriginalMinDistance = *(FLOAT*)(g_MinCameraAddress);

				g_MaxCameraAddress = *(DWORD*)(XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD9\x44\x24\x10\xD8\x25\xFF\xFF\xFF\xFF\x51\xD8\x0D", "xxxxxx????xxx") + 0x06);
				if (g_MaxCameraAddress == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find max camera distance");
					return 0;
				}
				g_OriginalMaxDistance = *(FLOAT*)(g_MaxCameraAddress);

				g_MinBattleAddress = *(DWORD*)(XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x51\x52\xD8\x44\x24\x24\xD9\x05\xFF\xFF\xFF\xFF\xD8\xC1", "xxxxxxxx????xx") + 0x08);
				if (g_MinBattleAddress == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find min battle camera distance");
					return 0;
				}
				g_OriginalMinBattleDistance = *(FLOAT*)(g_MinBattleAddress);

				g_MaxBattleAddress = *(DWORD*)(XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\xC1\xD8\xCA\xD9\x5C\x24\x50\xD8\x05\xFF\xFF\xFF\xFF\xD8\xC9", "xxxxxxxxxx????xx") + 0x0A);
				if (g_MaxBattleAddress == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find max battle camera distance");
					return 0;
				}
				g_OriginalMaxBattleDistance = *(FLOAT*)(g_MaxBattleAddress);

				g_ZoomOnZoneInSetupAddress = XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x85\xC0\x74\x1A\xD9\x44\x24\x04\xD8\x0D\xFF\xFF\xFF\xFF\xD8\x0D\xFF\xFF\xFF\xFF\xD8\x7C", "xxxxxxxxxx????xx????xx") + 0x10;
				if (g_ZoomOnZoneInSetupAddress == 0)
				{
					removeCamera();
					return 0;
				}
				g_NewMinDistance = g_OriginalMinDistance;
				*(DWORD*)g_ZoomOnZoneInSetupAddress = (DWORD)&g_NewMinDistance;

				g_WalkAnimationAddress = XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x0F\x85\xFF\xFF\xFF\xFF\xD8\x0D\xFF\xFF\xFF\xFF\xD9\x13\xD8\x1D", "xx????xx????xxxx") + 0x08;
				if (g_WalkAnimationAddress == 0)
				{
					removeCamera();
					return 0;
				}
				*(DWORD*)g_WalkAnimationAddress = (DWORD)&g_NewMinDistance;

				
				g_NPCWalkAnimationAddress = XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x75\x14\xD9\x44\x24\x10\xD8\x0D\xFF\xFF\xFF\xFF\xD9\x1B\x8B\x8E", "xxxxxxxx????xxxx") + 0x08;
				if (g_NPCWalkAnimationAddress == 0)
				{
					removeCamera();
					return 0;
				}
				*(DWORD*)g_NPCWalkAnimationAddress = (DWORD)&g_NewMinDistance;

				setCameraDistance(m_cameraDistance);
				setBattleDistance(m_battleDistance);

				m_cameraSet = true;

				return m_cameraSet;
			}

			m_logger->logMessage(m_logDebug, "camera already set");
			return false;
		}

		bool Camera::removeCamera(void)
		{
			m_cameraSet = false;

			if (g_SpeedAddress != 0)
			{
				*(BYTE*)(g_SpeedAddress + 0x00) = 0xD8;
				*(BYTE*)(g_SpeedAddress + 0x01) = 0x4C;
				*(BYTE*)(g_SpeedAddress + 0x02) = 0x24;
				*(BYTE*)(g_SpeedAddress + 0x03) = 0x24;
				*(BYTE*)(g_SpeedAddress + 0x04) = 0x8B;
				*(BYTE*)(g_SpeedAddress + 0x05) = 0x16;
			}

			if (g_MinCameraAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MinCameraAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MinCameraAddress) = g_OriginalMinDistance;
				VirtualProtect((void*)g_MinCameraAddress, 4, dwProtect, new DWORD);
			}

			if (g_MaxCameraAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MaxCameraAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MaxCameraAddress) = g_OriginalMaxDistance;
				VirtualProtect((void*)g_MaxCameraAddress, 4, dwProtect, new DWORD);
			}

			if (g_MinBattleAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MinBattleAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MinBattleAddress) = g_OriginalMinBattleDistance	;
				VirtualProtect((void*)g_MinBattleAddress, 4, dwProtect, new DWORD);
			}

			if (g_MaxBattleAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MaxBattleAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MaxBattleAddress) = g_OriginalMaxBattleDistance;
				VirtualProtect((void*)g_MaxBattleAddress, 4, dwProtect, new DWORD);
			}

			if (g_ZoomOnZoneInSetupAddress != 0)
			{
				*(DWORD*)g_ZoomOnZoneInSetupAddress = g_MinCameraAddress;
			}
			if (g_WalkAnimationAddress != 0)
			{
				*(DWORD*)g_WalkAnimationAddress = g_MinCameraAddress;
			}
			if (g_NPCWalkAnimationAddress != 0)
			{
				*(DWORD*)g_NPCWalkAnimationAddress = g_MinCameraAddress;
			}

			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_cameraSet = %s", m_cameraSet ? "true" : "false");
			return m_cameraSet;
		}

		void Camera::setDebugLog(bool state)
		{
			m_logDebug = (state) ? ILogProvider::LogLevel::Debug : ILogProvider::LogLevel::Discard;
			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_logDebug = %s", state ? "Debug" : "Discard");
		}

		bool Camera::setCameraDistance(const int &newDistance)
		{
			m_cameraDistance = newDistance;
			g_cameraMoveSpeed = newDistance / 10.0f;

			if (g_MinCameraAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MinCameraAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MinCameraAddress) = m_cameraDistance - (g_OriginalMaxDistance - g_OriginalMinDistance);
				VirtualProtect((void*)g_MinCameraAddress, 4, dwProtect, new DWORD);
			}

			if (g_MaxCameraAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MaxCameraAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MaxCameraAddress) = m_cameraDistance;
				VirtualProtect((void*)g_MaxCameraAddress, 4, dwProtect, new DWORD);
			}

			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_cameraDistance = '%d'", m_cameraDistance);

			return true;
		}

		bool Camera::setBattleDistance(const int& newDistance)
		{
			m_battleDistance = newDistance;

			if (g_MinBattleAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MinBattleAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MinBattleAddress) = m_battleDistance - (g_OriginalMinBattleDistance - g_OriginalMinBattleDistance);
				VirtualProtect((void*)g_MinBattleAddress, 4, dwProtect, new DWORD);
			}

			if (g_MaxBattleAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_MaxBattleAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_MaxBattleAddress) = m_battleDistance;
				VirtualProtect((void*)g_MaxBattleAddress, 4, dwProtect, new DWORD);
			}

			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_battleDistance = '%d'", m_battleDistance);

			return true;
		}
	}
}