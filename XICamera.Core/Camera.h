// ============================================================================
//  XICamera.Core :: Camera.h
//
//  The Camera class owns every patch site and exposes setters for the
//  user-facing knobs. One instance per process. Per-launcher shims
//  (Windower 4 DLL today; lua addons elsewhere) drive it through the
//  setters and dispatch chat commands.
// ============================================================================

#pragma once

#include "Logger.hpp"

#include <Windows.h>

namespace XICamera {
namespace Core {

class Camera {
public:
    virtual ~Camera();

    bool initCamera();
    bool removeCamera();

    bool cameraActive() const { return m_cameraSet; }

    // Inject a logger from the launcher shim. The Camera does not take
    // ownership; the shim is responsible for keeping it alive across
    // initCamera/removeCamera. Defaults to a NullLogger if never set.
    void setLogger(ILogger* logger);

    // Toggle debug-level logging on/off. When off, messages logged at
    // Debug level are filtered before reaching the underlying logger.
    void setDebugLog(bool state);

    bool setCameraDistance(const int& newDistance);
    const int& cameraDistance() const { return m_cameraDistance; }

    bool setBattleDistance(const int& newDistance);
    const int& battleDistance() const { return m_battleDistance; }

    bool setHorizontalPanSpeed(const int& newSpeed);
    const int& horizontalPanSpeed() const { return m_horizontalPanSpeed; }

    bool setVerticalPanSpeed(const int& newSpeed);
    const int& verticalPanSpeed() const { return m_verticalPanSpeed; }

    bool setBattleCameraRange(const int& newRange);
    const int& battleRange() const { return m_battleRange; }

    bool setBattleRangeLock(const bool& isLocked);
    const bool& battleRangeLocked() const { return m_battleRangeLocked; }

public:
    static Camera& instance();

protected:
    static Camera* s_instance;

    explicit Camera();

private:
    bool m_cameraSet = false;
    int  m_cameraDistance     = 0;
    int  m_battleDistance     = 0;
    int  m_horizontalPanSpeed = 0;
    int  m_verticalPanSpeed   = 0;
    int  m_battleRange        = 0;
    bool m_battleRangeLocked  = true;

    LogLevel  m_debugLevel = LogLevel::Off;
    ILogger*  m_logger     = nullptr;
};

} // namespace Core
} // namespace XICamera
