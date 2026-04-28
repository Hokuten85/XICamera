// ============================================================================
//  XICamera.Core :: PatternScanner.h
//
//  Wildcard-aware byte-pattern scanner. Keeps the byte-array + char-mask API
//  the original signature scans were written against — every signature in
//  Camera.cpp is already shaped that way.
//
//  mask format:  'x' = compare byte exactly, '?' (or anything else) = wildcard
// ============================================================================

#pragma once

#include <cstdint>

namespace XICamera {

// Scan a [base, base+size) range for the first occurrence of `pattern`,
// using `mask` to decide which bytes to compare. Returns the absolute
// address of the match start, or 0 if not found. `mask` is null-terminated
// and its length determines how many bytes the pattern is.
uintptr_t ScanForPattern(const uint8_t* base,
                         size_t size,
                         const uint8_t* pattern,
                         const char*    mask);

// Convenience: scan a named module by image name (e.g. "FFXiMain.dll"). On
// miss returns 0 and leaves nothing protected. The module is looked up via
// GetModuleHandleA + K32GetModuleInformation; if the module isn't loaded
// we also return 0.
uintptr_t ScanModule(const char* moduleName,
                     const uint8_t* pattern,
                     const char*    mask);

} // namespace XICamera
