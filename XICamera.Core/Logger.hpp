// ============================================================================
//  XICamera.Core :: Logger.hpp
//
//  Abstract logging interface. Each launcher shim supplies a concrete
//  implementation that routes to its native chat / log facility. Mirrors
//  the shape used by XIOverclock so future shared-tooling stays consistent.
//
//  Header-only on purpose — Logf() is one of the most-called helpers and
//  inlining it across launchers avoids a TU dependency on a tiny .cpp.
// ============================================================================

#pragma once

#include <cstdarg>
#include <cstdio>

namespace XICamera {

enum class LogLevel : int {
    Off     = 0,
    Error   = 1,
    Warn    = 2,
    Info    = 3,
    Debug   = 4,
    Verbose = 5,
};

class ILogger {
public:
    virtual ~ILogger() = default;
    virtual void Log(LogLevel level, const char* message) = 0;
};

// sprintf-style helper. Inline so it lives in every TU that needs it
// without forcing a .cpp dependency.
inline void Logf(ILogger* logger, LogLevel level, const char* fmt, ...) {
    if (!logger) return;
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    buf[sizeof(buf) - 1] = '\0';
    logger->Log(level, buf);
}

// No-op logger for default construction / tests.
class NullLogger : public ILogger {
public:
    void Log(LogLevel, const char*) override {}
};

} // namespace XICamera
