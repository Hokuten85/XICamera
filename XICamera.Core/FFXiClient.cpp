// ============================================================================
//  XICamera.Core :: FFXiClient.cpp
// ============================================================================

#include "FFXiClient.h"

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <Psapi.h>

#pragma comment(lib, "Psapi.lib")

namespace XICamera {

bool FFXiClient::Locate() {
    if (m_Base) return true;
    HMODULE h = ::GetModuleHandleA("FFXiMain.dll");
    if (!h) return false;
    MODULEINFO info{};
    if (!::GetModuleInformation(::GetCurrentProcess(), h, &info, sizeof(info)))
        return false;
    m_Base = static_cast<const uint8_t*>(info.lpBaseOfDll);
    m_Size = info.SizeOfImage;
    return m_Base != nullptr;
}

} // namespace XICamera
