// ============================================================================
//  XICamera.Windower :: lua_module.cpp
// ============================================================================

#include "WindowerInterface.h"

extern "C" __declspec(dllexport) int luaopen__XICamera(lua_State* L) {
    return XICamera::WindowerInterface::registerInterface(L);
}

extern "C" __declspec(dllexport) int luaopen__WindowerMemory(lua_State* L) {
    return XICamera::WindowerInterface::registerInterface(L);
}
