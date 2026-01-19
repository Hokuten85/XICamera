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

		DWORD g_MinCameraAddress; // Camera Min distance address.
		DWORD g_MaxCameraAddress; // Camera Max distance address.
		DWORD g_MinBattleAddress; // Camera Max distance in Battle.
		DWORD g_MaxBattleAddress; // Camera Max distance in Battle.
		DWORD g_ZoomOnZoneInSetupAddress;
		DWORD g_WalkAnimationAddress;
		DWORD g_NPCWalkAnimationAddress;
		DWORD g_BattleSoundAddress;
		DWORD g_horizontalPanAddress; // horizontal pan address.
		DWORD g_verticalPanAddress; // vertical pan address.
		DWORD g_jitterSignature;
		DWORD g_originalJitterAddress;

		float g_OriginalMinDistance;
		float g_OriginalMaxDistance;
		float g_OriginalMinBattleDistance;
		float g_OriginalMaxBattleDistance;
		float g_NewMinDistance;
		float g_OriginalHorizontalPanSpeed;
		float g_OriginalVerticalPanSpeed;
		float g_newJitter = 1.0f;

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

		bool Camera::initCamera(void)
		{
			if (m_cameraSet == false)
			{
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

				g_BattleSoundAddress = XICamera::functions::FindPattern("FFXiMain.dll",      (BYTE*)"\xD9\x5C\x24\x14\x74\x1B\x48\x74\x10\xD9\x44\x24\x10\xD8\x0D", "xxxxxxxxxxxxxxx") + 0x0F;
				if (g_BattleSoundAddress == 0)
				{
					removeCamera();
					return 0;
				}
				*(DWORD*)g_BattleSoundAddress = (DWORD)&g_NewMinDistance;

				g_horizontalPanAddress = *(DWORD*)(XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\x4C\x24\x20\x8B\x06\x8B\xCE\xD8\x0D", "xxxxxxxxxx") + 0x0A);
				if (g_horizontalPanAddress == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find horizontal pan position");
					return 0;
				}
				g_OriginalHorizontalPanSpeed = *(FLOAT*)(g_horizontalPanAddress);

				g_verticalPanAddress = *(DWORD*)(XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\x4C\x24\x24\x8B\x16\x8B\xCE\xD8\x0D", "xxxxxxxxxx") + 0x0A);
				if (g_verticalPanAddress == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find vertical pan position");
					return 0;
				}
				g_OriginalVerticalPanSpeed = *(FLOAT*)(g_verticalPanAddress);

				g_jitterSignature = XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x8D\x54\x24\x2C\x8D\x44\x24\x2C\xD8\xC9\x52\x55\x50", "xxxxxxxxxxxxx");
				if (g_jitterSignature == 0)
				{
					removeCamera();
					m_logger->logMessage(ILogProvider::LogLevel::Info, "could not find jitter signature");
					return 0;
				}
				g_originalJitterAddress = *(DWORD*)(g_jitterSignature + 0x0F);
				*(DWORD*)(g_jitterSignature + 0x0F) = (DWORD)&g_newJitter;
				*(DWORD*)(g_jitterSignature + 0x1F) = (DWORD)&g_newJitter;


				setCameraDistance(m_cameraDistance);
				setBattleDistance(m_battleDistance);
				setHorizontalPanSpeed(m_horizontalPanSpeed);
				setVerticalPanSpeed(m_verticalPanSpeed);

				m_cameraSet = true;

				return m_cameraSet;
			}

			m_logger->logMessage(m_logDebug, "camera already set");
			return false;
		}

		bool Camera::removeCamera(void)
		{
			m_cameraSet = false;

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

			if (g_horizontalPanAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_horizontalPanAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_horizontalPanAddress) = g_OriginalHorizontalPanSpeed;
				VirtualProtect((void*)g_horizontalPanAddress, 4, dwProtect, new DWORD);
			}

			if (g_verticalPanAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_verticalPanAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_verticalPanAddress) = g_OriginalVerticalPanSpeed;
				VirtualProtect((void*)g_verticalPanAddress, 4, dwProtect, new DWORD);
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
			if (g_BattleSoundAddress != 0)
			{
				*(DWORD*)g_BattleSoundAddress = g_MinCameraAddress;
			}
			if (g_jitterSignature != 0)
			{
				*(DWORD*)(g_jitterSignature + 0x0F) = g_originalJitterAddress;
				*(DWORD*)(g_jitterSignature + 0x1F) = g_originalJitterAddress;
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

		bool Camera::setHorizontalPanSpeed(const int& newSpeed)
		{
			m_horizontalPanSpeed = newSpeed;

			if (g_horizontalPanAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_horizontalPanAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_horizontalPanAddress) = m_horizontalPanSpeed / 100.0;
				VirtualProtect((void*)g_horizontalPanAddress, 4, dwProtect, new DWORD);
			}

			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_horizontalPanSpeed = '%d'", m_horizontalPanSpeed);

			return true;
		}

		bool Camera::setVerticalPanSpeed(const int& newSpeed)
		{
			m_verticalPanSpeed = newSpeed;

			if (g_verticalPanAddress != 0)
			{
				DWORD dwProtect;
				VirtualProtect((void*)g_verticalPanAddress, 4, PAGE_READWRITE, &dwProtect);
				*(FLOAT*)(g_verticalPanAddress) = m_verticalPanSpeed / 100.0;
				VirtualProtect((void*)g_verticalPanAddress, 4, dwProtect, new DWORD);
			}

			m_logger->logMessageF(ILogProvider::LogLevel::Info, "m_verticalPanSpeed = '%d'", m_verticalPanSpeed);

			return true;
		}
	}
}