#pragma once
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

			bool getCameraAddress(void);
			bool setupCamera(void);
			bool removeCamera(void);

			bool cameraActive(void) const { return m_cameraSet; };


			bool setCameraDistance(const int& newDistance);
			const float& cameraDistance(void) const { return m_cameraDistance; }

			bool changeDistance(void);

		public:
			static Camera& instance(void);

		protected:
			static Camera* s_instance;

			explicit Camera(void);

		private:
			bool m_cameraSet;
			float m_cameraDistance = 6.0f;
		};
	}
}


