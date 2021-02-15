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

		DWORD g_CameraAddress; // Camera address to identify where to start injecting.
		DWORD g_CameraSpeedReturnAddress; // Camera Speed return address to allow the code cave to return properly.
		DWORD g_SpeedAddress; // Camera Speed address to identify where to start injecting.
		//DWORD g_MaxCameraAddress; // Camera Max distance address to identify where to start injecting.
		//DWORD g_MaxCameraBattleAddress; // Camera Max distance in Battle address to identify where to start injecting.
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
			m_cameraSet = false;
			m_cameraDistance = 6.0f;
			g_cameraMoveSpeed = 0.0f;
		}

		Camera::~Camera()
		{
			removeCamera(); // just in case
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

		bool Camera::getCameraAddress(void) 
		{
			const auto pointerToCameraPointer = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xC8\xE8\x78\x01\x00\x00\xEB\x02\x33\xC0\x8B\xC8\xA3", "xxxxxxxxxxxxx");
			if (pointerToCameraPointer != 0)
			{
				const auto pointerToCamera = *(DWORD*)(pointerToCameraPointer + 0x0D);
				if (pointerToCamera != 0) {
					g_CameraAddress = *(DWORD*)(pointerToCamera);
					return g_CameraAddress != 0;
				}
			}

			return false;
		}

		bool Camera::setupCamera(void)
		{
			if (m_cameraSet == false)
			{
				m_cameraSet = getCameraAddress();

				if (m_cameraSet == false) {
					return false;
				}

				g_SpeedAddress = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\xD8\x4C\x24\x24\x8B\x16\x8B\xCE\xD8\x0D", "xxxxxxxxxx");
				if (g_SpeedAddress == 0)
				{
					m_cameraSet = false;
					return false;
				}
				auto caveSpeedDest = ((int)CameraSpeed - ((int)g_SpeedAddress)) - 5;
				g_CameraSpeedReturnAddress = g_SpeedAddress + 0x06;

				*(BYTE*)(g_SpeedAddress + 0x00) = 0xE9; // jmp
				*(UINT*)(g_SpeedAddress + 0x01) = caveSpeedDest;
				*(BYTE*)(g_SpeedAddress + 0x05) = 0x90; //nop

				return m_cameraSet;
			}

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

			return m_cameraSet;
		}

		bool Camera::setCameraDistance(const int &newDistance)
		{
			m_cameraDistance = newDistance;

			g_cameraMoveSpeed = newDistance / 6.0f;

			return true;
		}

		bool Camera::changeDistance(void)
		{
			const auto focal_x = *(FLOAT*)(g_CameraAddress + 0x50);
			const auto focal_z = *(FLOAT*)(g_CameraAddress + 0x54);
			const auto focal_y = *(FLOAT*)(g_CameraAddress + 0x58);

			const auto diff_x = *(FLOAT*)(g_CameraAddress + 0x44) - focal_x;
			const auto diff_z = *(FLOAT*)(g_CameraAddress + 0x48) - focal_z;
			const auto diff_y = *(FLOAT*)(g_CameraAddress + 0x4C) - focal_y;

			const auto distance = 1 / sqrtf(diff_x * diff_x + diff_z * diff_z + diff_y * diff_y) * m_cameraDistance;

			if (distance > 3)
			{
				*(FLOAT*)(g_CameraAddress + 0x44) = diff_x * distance + focal_x;
				*(FLOAT*)(g_CameraAddress + 0x48) = diff_z * distance + focal_z;
				*(FLOAT*)(g_CameraAddress + 0x4C) = diff_y * distance + focal_y;
			}

			return true;
		}
	}
}