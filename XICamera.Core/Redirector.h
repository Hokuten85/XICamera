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
		class Redirector
		{
		public:
			virtual ~Redirector(void);

			bool setupRedirect(void);
			bool removeRedirect(void);

			bool redirectActive(void) const { return m_redirectSet; };

			void setLogProvider(ILogProvider* logProvider);

			/* toggle debug logging on/off */
			void setDebugLog(bool state);

			void setCameraDistance(const int& newDistance);
			const int& cameraDistance(void) const { return m_cameraDistance; }

		public:
			static Redirector& instance(void);

		protected:
			static Redirector* s_instance;

			explicit Redirector(void);

		private:
			bool m_redirectSet;
			int m_cameraDistance;

			ILogProvider::LogLevel m_logDebug;
			ILogProvider* m_logger;
		};
	}
}


