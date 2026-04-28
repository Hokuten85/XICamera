// ============================================================================
//  XICamera.Core :: PatternScanner.cpp
// ============================================================================

#include "PatternScanner.h"

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <Psapi.h>

#pragma comment(lib, "Psapi.lib")

namespace XICamera {

namespace {

bool MaskCompare(const uint8_t* data, const uint8_t* pattern, const char* mask) {
    for (; *mask; ++mask, ++data, ++pattern) {
        if (*mask == 'x' && *data != *pattern)
            return false;
    }
    return *mask == '\0';
}

} // namespace

uintptr_t ScanForPattern(const uint8_t* base,
                         size_t size,
                         const uint8_t* pattern,
                         const char*    mask) {
    if (!base || !pattern || !mask || !*mask) return 0;
    const size_t maskLen = [&]() {
        size_t n = 0;
        while (mask[n]) ++n;
        return n;
    }();
    if (maskLen > size) return 0;

    const size_t stop = size - maskLen;
    for (size_t i = 0; i <= stop; ++i) {
        if (MaskCompare(base + i, pattern, mask))
            return reinterpret_cast<uintptr_t>(base + i);
    }
    return 0;
}

uintptr_t ScanModule(const char* moduleName,
                     const uint8_t* pattern,
                     const char*    mask) {
    HMODULE h = ::GetModuleHandleA(moduleName);
    if (!h) return 0;
    MODULEINFO info{};
    if (!::GetModuleInformation(::GetCurrentProcess(), h, &info, sizeof(info)))
        return 0;
    return ScanForPattern(static_cast<const uint8_t*>(info.lpBaseOfDll),
                          info.SizeOfImage, pattern, mask);
}

} // namespace XICamera
