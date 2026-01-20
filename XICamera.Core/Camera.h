#pragma once
#include "LogProvider.h"

#include <Windows.h>

#include <map>
#include <vector>
#include <string>

namespace XICamera
{
	namespace Core
	{
		class Camera
		{
		public:
			virtual ~Camera(void);

			bool initCamera(void);
			bool removeCamera(void);

			bool cameraActive(void) const { return m_cameraSet; };

			void setLogProvider(ILogProvider* logProvider);

			/* toggle debug logging on/off */
			void setDebugLog(bool state);

			bool setCameraDistance(const int& newDistance);
			const int& cameraDistance(void) const { return m_cameraDistance; }

			bool setBattleDistance(const int& newDistance);
			const int& battleDistance(void) const { return m_battleDistance; }

			bool setHorizontalPanSpeed(const int& newSpeed);
			const int& horizontalPanSpeed(void) const { return m_horizontalPanSpeed; }

			bool setVerticalPanSpeed(const int& newSpeed);
			const int& verticalPanSpeed(void) const { return m_verticalPanSpeed; }

			bool setBattleCameraRange(const int& newRange);
			const int& battleRange(void) const { return m_battleRange; }

			bool setBattleRangeLock(const bool& isLocked);
			const bool& battleRangeLocked(void) const { return m_battleRangeLocked; }

		public:
			static Camera& instance(void);

		protected:
			static Camera* s_instance;

			explicit Camera(void);

		private:
			bool m_cameraSet;
			int m_cameraDistance;
			int m_battleDistance;
			int m_horizontalPanSpeed;
			int m_verticalPanSpeed;
			int m_battleRange;
			bool m_battleRangeLocked;

			ILogProvider::LogLevel m_logDebug;
			ILogProvider* m_logger;
		};
	}
}


