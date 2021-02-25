#include "Camera.h"
#include <rpc.h>
#include <cctype>
#include <algorithm>
#include "functions.h"

#include <iostream>
#include <fstream>
#include <stdio.h>
using namespace std;

namespace XICamera
{
	namespace Core
	{
		Camera* Camera::s_instance = nullptr;

		DWORD g_pointerToCamera;
		DWORD g_CameraAddress; // Camera address to identify where to start injecting.
		DWORD g_CameraSpeedReturnAddress; // Camera Speed return address to allow the code cave to return properly.
		DWORD g_SpeedAddress; // Camera Speed address to identify where to start injecting.
		//DWORD g_MaxCameraAddress; // Camera Max distance address to identify where to start injecting.
		//DWORD g_MaxCameraBattleAddress; // Camera Max distance in Battle address to identify where to start injecting.
		float g_cameraMoveSpeed;
		DWORD g_CameraConnect;
		DWORD g_isFirstPerson;
		ofstream myfile;

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
			myfile.open("C:\\camera.log");
		}

		Camera::~Camera()
		{
			removeCamera(); // just in case
			myfile.close();
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
			const auto pointerToCameraPointer = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x83\xC4\x04\x85\xC9\x74\x11\x8B\x11\x6A\x01\xFF\x52\x18\xC7\x05", "xxxxxxxxxxxxxxxx");
			if (pointerToCameraPointer != 0)
			{
				g_pointerToCamera = *(DWORD*)(pointerToCameraPointer + 0x10);
				if (g_pointerToCamera != 0) {
					g_CameraAddress = *(DWORD*)(g_pointerToCamera);
					return g_CameraAddress != 0;
				}
			}

			return false;
		}

		bool Camera::getCameraConnect(void)
		{
			const auto cameraConnectSig = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x80\xA0\xB2\x00\x00\x00\xFB\xC6\x05\xFF\xFF\xFF\xFF\x00", "xxxxxxxxx????x");
			if (cameraConnectSig != 0)
			{
				g_CameraConnect = *(DWORD*)(cameraConnectSig + 0x09);
				return g_CameraConnect != 0;
			}

			return false;
		}

		bool Camera::getFollow(void)
		{
			const auto firstPersonSig = (DWORD)XICamera::functions::FindPattern("FFXiMain.dll", (BYTE*)"\x8B\xCF\xE8\xFF\xFF\xFF\xFF\x8B\x0D\xFF\xFF\xFF\xFF\xE8\xFF\xFF\xFF\xFF\x8B\xE8\x85\xED\x75\x0C\xB9", "xxx????xx????x????xxxxxxx");
			if (firstPersonSig != 0)
			{
				const auto firstPersonPtr = *(DWORD*)(firstPersonSig + 0x19);
				if (firstPersonPtr != 0) {
					g_isFirstPerson = firstPersonPtr + 0x28;
					return g_isFirstPerson != 0;
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

				if (!getCameraConnect()) {
					return false;
				}

				if (!getFollow()) {
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

		struct camera_t
		{
			float X;
			float Z;
			float Y;
			float FocalX;
			float FocalZ;
			float FocalY;
		};

		bool Camera::changeDistance(void)
		{
			auto cameraAddress = *(DWORD*)(g_pointerToCamera);
			auto isConnected = *(BOOL*)(g_CameraConnect);
			auto isFirstPerson = *(BOOL*)(g_isFirstPerson);

			if (isConnected == 1 && isFirstPerson == 0 && cameraAddress != 0)
			{
				auto camera = *(camera_t*)(cameraAddress + 0x44);

				const auto diff_x = camera.X - camera.FocalX;
				const auto diff_z = camera.Z - camera.FocalZ;
				const auto diff_y = camera.Y - camera.FocalY;

				const auto distance = 1 / sqrtf(diff_x * diff_x + diff_z * diff_z + diff_y * diff_y) * m_cameraDistance;
					
				*(FLOAT*)(cameraAddress + 0x44) = diff_x * distance + camera.FocalX;
				*(FLOAT*)(cameraAddress + 0x48) = diff_z * distance + camera.FocalZ;
				*(FLOAT*)(cameraAddress + 0x4C) = diff_y * distance + camera.FocalY;
			}

			return true;
		}
	}
}