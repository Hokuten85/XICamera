#pragma once

extern "C" {
#   ifndef LUA_BUILD_AS_DLL
#       define LUA_BUILD_AS_DLL
#   endif
#   include "lauxlib.h"
#   include "lua.h"
}

namespace XICamera {

class WindowerInterface {
public:
    static int registerInterface(lua_State* L);

private:
    static int lua_get_base(lua_State* L);
    static int lua_get_size(lua_State* L);
    static int lua_find(lua_State* L);
    static int lua_alloc(lua_State* L);
    static int lua_dealloc(lua_State* L);
    static int lua_unprotect(lua_State* L);

    static int lua_read_uint8(lua_State* L);
    static int lua_read_uint16(lua_State* L);
    static int lua_read_uint32(lua_State* L);
    static int lua_read_uint64(lua_State* L);
    static int lua_read_int8(lua_State* L);
    static int lua_read_int16(lua_State* L);
    static int lua_read_int32(lua_State* L);
    static int lua_read_int64(lua_State* L);
    static int lua_read_float(lua_State* L);
    static int lua_read_double(lua_State* L);
    static int lua_read_array(lua_State* L);
    static int lua_read_string(lua_State* L);

    static int lua_write_uint8(lua_State* L);
    static int lua_write_uint16(lua_State* L);
    static int lua_write_uint32(lua_State* L);
    static int lua_write_uint64(lua_State* L);
    static int lua_write_int8(lua_State* L);
    static int lua_write_int16(lua_State* L);
    static int lua_write_int32(lua_State* L);
    static int lua_write_int64(lua_State* L);
    static int lua_write_float(lua_State* L);
    static int lua_write_double(lua_State* L);
    static int lua_write_array(lua_State* L);
    static int lua_write_string(lua_State* L);
};

} // namespace XICamera
