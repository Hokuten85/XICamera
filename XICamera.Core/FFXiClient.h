// ============================================================================
//  XICamera.Core :: FFXiClient.h
//
//  Locates FFXiMain.dll inside the running process and exposes its image
//  base + size. The Camera class uses this once at init time so every
//  signature scan doesn't have to re-hit GetModuleHandle.
// ============================================================================

#pragma once

#include <cstddef>
#include <cstdint>

namespace XICamera {

class FFXiClient {
public:
    FFXiClient() = default;

    // Locate FFXiMain.dll. Idempotent — safe to call repeatedly. Returns
    // true if the module was found (or already located).
    bool Locate();

    bool         IsLoaded() const { return m_Base != nullptr; }
    const uint8_t* Base()   const { return m_Base; }
    size_t  Size()     const { return m_Size; }

private:
    const uint8_t* m_Base = nullptr;
    size_t    m_Size = 0;
};

} // namespace XICamera
