// ============================================================================
//  XICamera.Core :: Camera.cpp
//
//  Owns every patch site. initCamera() locates each, captures the original
//  bytes/values, and applies the patch; removeCamera() reverses everything.
//  All patches are pure data (in-place float overwrites and operand
//  pointer-rewrites) — no detours, no trampolines.
//
//  See docs/CAMERA_PATCH_TARGETS.md for what each signature targets.
// ============================================================================

#include "Camera.h"
#include "FFXiClient.h"
#include "PatternScanner.h"

#include <Windows.h>

namespace XICamera {
namespace Core {

// ---------------------------------------------------------------------------
//  Patch-site state. Globals so removeCamera() can reach them; one Camera
//  per process so the storage is fine here.
// ---------------------------------------------------------------------------

// Direct value-overwrite sites (the float address; we VirtualProtect+write).
DWORD g_MinCameraAddress       = 0;
DWORD g_MaxCameraAddress       = 0;
DWORD g_MinBattleAddress       = 0;
DWORD g_MaxBattleAddress       = 0;
DWORD g_horizontalPanAddress   = 0;
DWORD g_verticalPanAddress     = 0;

// Pointer-rewrite sites (the operand bytes inside an instruction; we replace
// the 4-byte address operand with the address of g_NewMinDistance).
DWORD g_ZoomOnZoneInSetupAddress = 0;
DWORD g_WalkAnimationAddress     = 0;
DWORD g_NPCWalkAnimationAddress  = 0;
DWORD g_BattleSoundAddress       = 0;

// Jitter (collision-response damping) site. The signature scan returns the
// match-start address; the operand rewrites are at +0x0F and +0x1F.
DWORD g_jitterMatchAddress       = 0;
DWORD g_originalJitterPtr        = 0;

// Battle camera range: same shape — match start at the signature, slot
// operand at +0x15, 2-byte clamp at +0x19.
DWORD g_battleCamRangeSlotAddress    = 0;
DWORD g_originalBattleCamRangePtr    = 0;
DWORD g_battleCamRangeLockAddress    = 0;
WORD  g_originalRangeLockValues      = 0;

// Original values to restore on uninstall.
float g_OriginalMinDistance        = 0.0f;
float g_OriginalMaxDistance        = 0.0f;
float g_OriginalMinBattleDistance  = 0.0f;
float g_OriginalMaxBattleDistance  = 0.0f;
float g_OriginalHorizontalPanSpeed = 0.0f;
float g_OriginalVerticalPanSpeed   = 0.0f;

// Our overrides — game reads these via the rewritten pointers.
float g_NewMinDistance     = 0.0f;
float g_newJitter          = 1.0f;
float g_newBattleCamRange  = 4.0f;

// ---------------------------------------------------------------------------
//  Local helpers
// ---------------------------------------------------------------------------

namespace {

NullLogger        s_nullLogger;
FFXiClient        s_client;

// Wrapper around ScanForPattern that targets the FFXiClient image. Returns
// the match start address (DWORD-sized to match the legacy globals).
DWORD findIn(const FFXiClient& c, const uint8_t* pattern, const char* mask) {
    return static_cast<DWORD>(
        ScanForPattern(c.Base(), c.Size(), pattern, mask));
}

// VirtualProtect(...) wrapper that writes a 4-byte float and restores the
// page protection. Replaces the leaky `new DWORD` pattern that was here
// before. Safe to call on a 0 address (no-op).
void writeFloat(DWORD addr, float value) {
    if (addr == 0) return;
    DWORD oldProtect = 0, tmp = 0;
    VirtualProtect(reinterpret_cast<void*>(addr), 4, PAGE_READWRITE, &oldProtect);
    *reinterpret_cast<float*>(addr) = value;
    VirtualProtect(reinterpret_cast<void*>(addr), 4, oldProtect, &tmp);
}

// Same shape but for a 4-byte DWORD (used for operand pointer rewrites).
void writeDword(DWORD addr, DWORD value) {
    if (addr == 0) return;
    DWORD oldProtect = 0, tmp = 0;
    VirtualProtect(reinterpret_cast<void*>(addr), 4, PAGE_READWRITE, &oldProtect);
    *reinterpret_cast<DWORD*>(addr) = value;
    VirtualProtect(reinterpret_cast<void*>(addr), 4, oldProtect, &tmp);
}

void writeWord(DWORD addr, WORD value) {
    if (addr == 0) return;
    DWORD oldProtect = 0, tmp = 0;
    VirtualProtect(reinterpret_cast<void*>(addr), 2, PAGE_READWRITE, &oldProtect);
    *reinterpret_cast<WORD*>(addr) = value;
    VirtualProtect(reinterpret_cast<void*>(addr), 2, oldProtect, &tmp);
}

} // namespace

// ---------------------------------------------------------------------------
//  Camera
// ---------------------------------------------------------------------------

Camera* Camera::s_instance = nullptr;

Camera& Camera::instance() {
    if (!s_instance) s_instance = new Camera();
    return *s_instance;
}

Camera::Camera() {
    m_logger = &s_nullLogger;
}

Camera::~Camera() {
    removeCamera(); // just in case
}

void Camera::setLogger(ILogger* logger) {
    if (logger) m_logger = logger;
}

void Camera::setDebugLog(bool state) {
    m_debugLevel = state ? LogLevel::Debug : LogLevel::Off;
    Logf(m_logger, LogLevel::Info, "debug logging = %s", state ? "on" : "off");
}

bool Camera::initCamera() {
    if (m_cameraSet) {
        Logf(m_logger, m_debugLevel, "camera already set");
        return false;
    }

    if (!s_client.Locate()) {
        Logf(m_logger, LogLevel::Error,
             "FFXiMain.dll not loaded; XICamera will be inactive");
        return false;
    }

    // ---- value-overwrite sites ----------------------------------------
    // These four scans find an FPU load instruction; the 4-byte operand at
    // the documented offset is the absolute address of the float we want
    // to overwrite. Each is independent — a miss only disables that one
    // value, the rest of XICamera continues to work.

    auto resolveValueSite = [](const uint8_t* pat, const char* mask, int operandOffset) -> DWORD {
        DWORD match = findIn(s_client, pat, mask);
        return match == 0 ? 0 : *reinterpret_cast<DWORD*>(match + operandOffset);
    };

    g_MinCameraAddress = resolveValueSite(
        (const uint8_t*)"\xD8\xC9\xD9\xC0\xD8\xC1\xD9\xC2\xD8\x0D\xFF\xFF\xFF\xFF\xD9\xC3\xDC\xC0\xD8\xEB",
        "xxxxxxxxxx????xxxxxx", 0x0A);
    if (g_MinCameraAddress == 0)
        Logf(m_logger, LogLevel::Warn, "min camera distance signature not found");
    else
        g_OriginalMinDistance = *reinterpret_cast<float*>(g_MinCameraAddress);

    g_MaxCameraAddress = resolveValueSite(
        (const uint8_t*)"\xD9\x44\x24\x10\xD8\x25\xFF\xFF\xFF\xFF\x51\xD8\x0D",
        "xxxxxx????xxx", 0x06);
    if (g_MaxCameraAddress == 0)
        Logf(m_logger, LogLevel::Warn, "max camera distance signature not found");
    else
        g_OriginalMaxDistance = *reinterpret_cast<float*>(g_MaxCameraAddress);

    g_MinBattleAddress = resolveValueSite(
        (const uint8_t*)"\x51\x52\xD8\x44\x24\x24\xD9\x05\xFF\xFF\xFF\xFF\xD8\xC1",
        "xxxxxxxx????xx", 0x08);
    if (g_MinBattleAddress == 0)
        Logf(m_logger, LogLevel::Warn, "min battle distance signature not found");
    else
        g_OriginalMinBattleDistance = *reinterpret_cast<float*>(g_MinBattleAddress);

    g_MaxBattleAddress = resolveValueSite(
        (const uint8_t*)"\xD8\xC1\xD8\xCA\xD9\x5C\x24\x50\xD8\x05\xFF\xFF\xFF\xFF\xD8\xC9",
        "xxxxxxxxxx????xx", 0x0A);
    if (g_MaxBattleAddress == 0)
        Logf(m_logger, LogLevel::Warn, "max battle distance signature not found");
    else
        g_OriginalMaxBattleDistance = *reinterpret_cast<float*>(g_MaxBattleAddress);

    g_horizontalPanAddress = resolveValueSite(
        (const uint8_t*)"\xD8\x4C\x24\x20\x8B\x06\x8B\xCE\xD8\x0D",
        "xxxxxxxxxx", 0x0A);
    if (g_horizontalPanAddress == 0)
        Logf(m_logger, LogLevel::Warn, "horizontal pan speed signature not found");
    else
        g_OriginalHorizontalPanSpeed = *reinterpret_cast<float*>(g_horizontalPanAddress);

    g_verticalPanAddress = resolveValueSite(
        (const uint8_t*)"\xD8\x4C\x24\x24\x8B\x16\x8B\xCE\xD8\x0D",
        "xxxxxxxxxx", 0x0A);
    if (g_verticalPanAddress == 0)
        Logf(m_logger, LogLevel::Warn, "vertical pan speed signature not found");
    else
        g_OriginalVerticalPanSpeed = *reinterpret_cast<float*>(g_verticalPanAddress);

    // ---- pointer-rewrite sites (min-distance followers) ---------------
    // Each redirects an in-instruction 4-byte operand to point at our own
    // float so we can move the effective min distance everywhere it's read.

    g_NewMinDistance = g_OriginalMinDistance;

    auto resolveOperandSite = [](const uint8_t* pat, const char* mask, int operandOffset) -> DWORD {
        DWORD match = findIn(s_client, pat, mask);
        return match == 0 ? 0 : match + operandOffset;
    };

    g_ZoomOnZoneInSetupAddress = resolveOperandSite(
        (const uint8_t*)"\x85\xC0\x74\x1A\xD9\x44\x24\x04\xD8\x0D\xFF\xFF\xFF\xFF\xD8\x0D\xFF\xFF\xFF\xFF\xD8\x7C",
        "xxxxxxxxxx????xx????xx", 0x10);
    if (g_ZoomOnZoneInSetupAddress)
        writeDword(g_ZoomOnZoneInSetupAddress, reinterpret_cast<DWORD>(&g_NewMinDistance));

    g_WalkAnimationAddress = resolveOperandSite(
        (const uint8_t*)"\x0F\x85\xFF\xFF\xFF\xFF\xD8\x0D\xFF\xFF\xFF\xFF\xD9\x13\xD8\x1D",
        "xx????xx????xxxx", 0x08);
    if (g_WalkAnimationAddress)
        writeDword(g_WalkAnimationAddress, reinterpret_cast<DWORD>(&g_NewMinDistance));

    g_NPCWalkAnimationAddress = resolveOperandSite(
        (const uint8_t*)"\x75\x14\xD9\x44\x24\x10\xD8\x0D\xFF\xFF\xFF\xFF\xD9\x1B\x8B\x8E",
        "xxxxxxxx????xxxx", 0x08);
    if (g_NPCWalkAnimationAddress)
        writeDword(g_NPCWalkAnimationAddress, reinterpret_cast<DWORD>(&g_NewMinDistance));

    g_BattleSoundAddress = resolveOperandSite(
        (const uint8_t*)"\xD9\x5C\x24\x14\x74\x1B\x48\x74\x10\xD9\x44\x24\x10\xD8\x0D",
        "xxxxxxxxxxxxxxx", 0x0F);
    if (g_BattleSoundAddress)
        writeDword(g_BattleSoundAddress, reinterpret_cast<DWORD>(&g_NewMinDistance));

    // ---- jitter / collision-response damping --------------------------
    g_jitterMatchAddress = findIn(s_client,
        (const uint8_t*)"\x8D\x54\x24\x2C\x8D\x44\x24\x2C\xD8\xC9\x52\x55\x50",
        "xxxxxxxxxxxxx");
    if (g_jitterMatchAddress == 0) {
        Logf(m_logger, LogLevel::Warn, "jitter signature not found");
    } else {
        g_originalJitterPtr = *reinterpret_cast<DWORD*>(g_jitterMatchAddress + 0x0F);
        writeDword(g_jitterMatchAddress + 0x0F, reinterpret_cast<DWORD>(&g_newJitter));
        writeDword(g_jitterMatchAddress + 0x1F, reinterpret_cast<DWORD>(&g_newJitter));
    }

    // ---- battle camera range + lock -----------------------------------
    DWORD battleRangeMatch = findIn(s_client,
        (const uint8_t*)"\xD8\xC9\xD9\x9C\x24\xDC\x00\x00\x00\xDD\xD8\xD9\x44\x24\x50\xD8\x44\x24\x28\xD8\x3D",
        "xxxxxxxxxxxxxxxxxxxxx");
    if (battleRangeMatch == 0) {
        Logf(m_logger, LogLevel::Warn, "battle camera range signature not found");
    } else {
        g_battleCamRangeSlotAddress    = battleRangeMatch + 0x15;
        g_originalBattleCamRangePtr    = *reinterpret_cast<DWORD*>(g_battleCamRangeSlotAddress);
        writeDword(g_battleCamRangeSlotAddress, reinterpret_cast<DWORD>(&g_newBattleCamRange));
        g_battleCamRangeLockAddress    = battleRangeMatch + 0x19;
        g_originalRangeLockValues      = *reinterpret_cast<WORD*>(g_battleCamRangeLockAddress);
    }

    // Apply current settings (re-applies whatever the launcher has loaded).
    setCameraDistance(m_cameraDistance);
    setBattleDistance(m_battleDistance);
    setHorizontalPanSpeed(m_horizontalPanSpeed);
    setVerticalPanSpeed(m_verticalPanSpeed);
    setBattleCameraRange(m_battleRange);
    setBattleRangeLock(m_battleRangeLocked);

    m_cameraSet = true;
    return true;
}

bool Camera::removeCamera() {
    m_cameraSet = false;

    writeFloat(g_MinCameraAddress,       g_OriginalMinDistance);
    writeFloat(g_MaxCameraAddress,       g_OriginalMaxDistance);
    writeFloat(g_MinBattleAddress,       g_OriginalMinBattleDistance);
    writeFloat(g_MaxBattleAddress,       g_OriginalMaxBattleDistance);
    writeFloat(g_horizontalPanAddress,   g_OriginalHorizontalPanSpeed);
    writeFloat(g_verticalPanAddress,     g_OriginalVerticalPanSpeed);

    // Min-distance followers all originally pointed at g_MinCameraAddress.
    if (g_ZoomOnZoneInSetupAddress) writeDword(g_ZoomOnZoneInSetupAddress, g_MinCameraAddress);
    if (g_WalkAnimationAddress)     writeDword(g_WalkAnimationAddress,     g_MinCameraAddress);
    if (g_NPCWalkAnimationAddress)  writeDword(g_NPCWalkAnimationAddress,  g_MinCameraAddress);
    if (g_BattleSoundAddress)       writeDword(g_BattleSoundAddress,       g_MinCameraAddress);

    if (g_jitterMatchAddress) {
        writeDword(g_jitterMatchAddress + 0x0F, g_originalJitterPtr);
        writeDword(g_jitterMatchAddress + 0x1F, g_originalJitterPtr);
    }

    if (g_battleCamRangeSlotAddress) {
        writeDword(g_battleCamRangeSlotAddress, g_originalBattleCamRangePtr);
        if (g_originalRangeLockValues != *reinterpret_cast<WORD*>(g_battleCamRangeLockAddress))
            writeWord(g_battleCamRangeLockAddress, g_originalRangeLockValues);
    }

    Logf(m_logger, LogLevel::Info, "camera reset");
    return true;
}

bool Camera::setCameraDistance(const int& newDistance) {
    m_cameraDistance = newDistance;
    if (g_MinCameraAddress)
        writeFloat(g_MinCameraAddress, m_cameraDistance - (g_OriginalMaxDistance - g_OriginalMinDistance));
    if (g_MaxCameraAddress)
        writeFloat(g_MaxCameraAddress, static_cast<float>(m_cameraDistance));
    Logf(m_logger, LogLevel::Info, "cameraDistance = %d", m_cameraDistance);
    return true;
}

bool Camera::setBattleDistance(const int& newDistance) {
    m_battleDistance = newDistance;
    if (g_MinBattleAddress)
        writeFloat(g_MinBattleAddress, m_battleDistance - (g_OriginalMaxBattleDistance - g_OriginalMinBattleDistance));
    if (g_MaxBattleAddress)
        writeFloat(g_MaxBattleAddress, static_cast<float>(m_battleDistance));
    Logf(m_logger, LogLevel::Info, "battleDistance = %d", m_battleDistance);
    return true;
}

bool Camera::setHorizontalPanSpeed(const int& newSpeed) {
    m_horizontalPanSpeed = newSpeed;
    if (g_horizontalPanAddress)
        writeFloat(g_horizontalPanAddress, m_horizontalPanSpeed / 100.0f);
    Logf(m_logger, LogLevel::Info, "horizontalPanSpeed = %d", m_horizontalPanSpeed);
    return true;
}

bool Camera::setVerticalPanSpeed(const int& newSpeed) {
    m_verticalPanSpeed = newSpeed;
    if (g_verticalPanAddress)
        writeFloat(g_verticalPanAddress, m_verticalPanSpeed / 100.0f);
    Logf(m_logger, LogLevel::Info, "verticalPanSpeed = %d", m_verticalPanSpeed);
    return true;
}

bool Camera::setBattleCameraRange(const int& newRange) {
    if (newRange < 0 || newRange > 100) return false;
    m_battleRange = newRange;
    g_newBattleCamRange = static_cast<float>(m_battleRange);
    Logf(m_logger, LogLevel::Info, "battleRange = %d", m_battleRange);
    return true;
}

bool Camera::setBattleRangeLock(const bool& isLocked) {
    m_battleRangeLocked = isLocked;
    if (g_battleCamRangeLockAddress == 0) return false;
    writeWord(g_battleCamRangeLockAddress,
              isLocked ? g_originalRangeLockValues : 0x9090);
    Logf(m_logger, LogLevel::Info, "battleRangeLocked = %d", m_battleRangeLocked);
    return true;
}

} // namespace Core
} // namespace XICamera
