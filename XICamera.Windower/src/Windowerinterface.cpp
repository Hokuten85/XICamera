// ============================================================================
//  XICamera.Windower :: WindowerInterface.cpp
//
//  Windower-hosted Ashita memory namespace compatibility layer.
// ============================================================================

#include "WindowerInterface.h"

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <Psapi.h>

#include <cctype>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#pragma comment(lib, "Psapi.lib")

namespace XICamera {
namespace {

uintptr_t CheckAddress(lua_State* L, int index) {
    const lua_Number n = luaL_checknumber(L, index);
    if (n <= 0) {
        luaL_error(L, "address must be a positive number");
        return 0;
    }
    return static_cast<uintptr_t>(n);
}

uintptr_t OptAddress(lua_State* L, int index, uintptr_t fallback) {
    if (lua_isnoneornil(L, index)) return fallback;
    return static_cast<uintptr_t>(luaL_checknumber(L, index));
}

void PushAddress(lua_State* L, uintptr_t address) {
    lua_pushnumber(L, static_cast<lua_Number>(address));
}

bool LocateModule(const char* moduleName, const uint8_t** base, size_t* size) {
    HMODULE h = ::GetModuleHandleA(moduleName);
    if (!h) return false;

    MODULEINFO info{};
    if (!::GetModuleInformation(::GetCurrentProcess(), h, &info, sizeof(info)))
        return false;

    *base = static_cast<const uint8_t*>(info.lpBaseOfDll);
    *size = static_cast<size_t>(info.SizeOfImage);
    return *base != nullptr && *size != 0;
}

int HexValue(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

bool ParsePattern(const char* text, std::vector<uint8_t>& bytes, std::string& mask) {
    bytes.clear();
    mask.clear();

    const char* p = text;
    while (*p) {
        while (*p && std::isspace(static_cast<unsigned char>(*p))) ++p;
        if (!*p) break;

        if (*p == '?') {
            ++p;
            if (*p == '?') ++p;
            bytes.push_back(0);
            mask.push_back('?');
            continue;
        }

        const int hi = HexValue(*p++);
        if (hi < 0 || !*p) return false;
        const int lo = HexValue(*p++);
        if (lo < 0) return false;

        bytes.push_back(static_cast<uint8_t>((hi << 4) | lo));
        mask.push_back('x');
    }

    return !bytes.empty();
}

bool BytesMatch(const uint8_t* data, const std::vector<uint8_t>& bytes, const std::string& mask) {
    for (size_t i = 0; i < bytes.size(); ++i) {
        if (mask[i] == 'x' && data[i] != bytes[i]) return false;
    }
    return true;
}

uintptr_t ScanBytes(const uint8_t* base,
                    size_t size,
                    const std::vector<uint8_t>& bytes,
                    const std::string& mask,
                    size_t usage) {
    if (!base || bytes.empty() || bytes.size() != mask.size() || bytes.size() > size)
        return 0;

    const size_t stop = size - bytes.size();
    size_t seen = 0;
    for (size_t i = 0; i <= stop; ++i) {
        if (BytesMatch(base + i, bytes, mask)) {
            if (seen++ == usage) return reinterpret_cast<uintptr_t>(base + i);
        }
    }
    return 0;
}

bool MakeWritable(uintptr_t address, size_t size, DWORD* oldProtect) {
    return address != 0 && size != 0 &&
           ::VirtualProtect(reinterpret_cast<void*>(address), size, PAGE_EXECUTE_READWRITE, oldProtect) != 0;
}

template <typename T>
bool TryRead(uintptr_t address, T* out) {
    __try {
        *out = *reinterpret_cast<const T*>(address);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

template <typename T>
bool TryWrite(uintptr_t address, T value) {
    __try {
        *reinterpret_cast<T*>(address) = value;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool TryCopyFrom(uintptr_t address, void* dest, size_t size) {
    __try {
        std::memcpy(dest, reinterpret_cast<const void*>(address), size);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool TryCopyTo(uintptr_t address, const void* src, size_t size) {
    __try {
        std::memcpy(reinterpret_cast<void*>(address), src, size);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

template <typename T>
int ReadValue(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    T value{};
    if (!TryRead(address, &value)) {
        lua_pushnumber(L, 0);
        return 1;
    }
    lua_pushnumber(L, static_cast<lua_Number>(value));
    return 1;
}

template <typename T>
int WriteValue(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    const T value = static_cast<T>(luaL_checknumber(L, 2));

    DWORD oldProtect = 0;
    if (!MakeWritable(address, sizeof(T), &oldProtect)) return 0;

    TryWrite(address, value);

    DWORD ignored = 0;
    ::VirtualProtect(reinterpret_cast<void*>(address), sizeof(T), oldProtect, &ignored);
    return 0;
}

void RegisterFunctions(lua_State* L, const luaL_Reg* functions) {
    for (const auto* r = functions; r->name; ++r) {
        lua_pushstring(L, r->name);
        lua_pushcfunction(L, r->func);
        lua_settable(L, -3);
    }
}

} // namespace

int WindowerInterface::lua_get_base(lua_State* L) {
    const char* moduleName = luaL_checkstring(L, 1);
    const uint8_t* base = nullptr;
    size_t size = 0;
    PushAddress(L, LocateModule(moduleName, &base, &size) ? reinterpret_cast<uintptr_t>(base) : 0);
    return 1;
}

int WindowerInterface::lua_get_size(lua_State* L) {
    const char* moduleName = luaL_checkstring(L, 1);
    const uint8_t* base = nullptr;
    size_t size = 0;
    lua_pushnumber(L, LocateModule(moduleName, &base, &size) ? static_cast<lua_Number>(size) : 0);
    return 1;
}

int WindowerInterface::lua_find(lua_State* L) {
    const uint8_t* scanBase = nullptr;
    size_t scanSize = 0;

    if (lua_type(L, 1) == LUA_TSTRING) {
        const char* moduleName = luaL_checkstring(L, 1);
        if (!LocateModule(moduleName, &scanBase, &scanSize)) {
            lua_pushnumber(L, 0);
            return 1;
        }
    } else {
        scanBase = reinterpret_cast<const uint8_t*>(CheckAddress(L, 1));
        scanSize = static_cast<size_t>(luaL_checknumber(L, 2));
    }

    const char* patternText = luaL_checkstring(L, 3);
    const uintptr_t offset = OptAddress(L, 4, 0);
    const size_t usage = static_cast<size_t>(luaL_optnumber(L, 5, 0));

    std::vector<uint8_t> bytes;
    std::string mask;
    if (!ParsePattern(patternText, bytes, mask)) {
        luaL_error(L, "invalid hex pattern");
        return 0;
    }

    const uintptr_t match = ScanBytes(scanBase, scanSize, bytes, mask, usage);
    PushAddress(L, match == 0 ? 0 : match + offset);
    return 1;
}

int WindowerInterface::lua_alloc(lua_State* L) {
    const size_t size = static_cast<size_t>(luaL_checknumber(L, 1));
    void* p = ::VirtualAlloc(nullptr, size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!p) lua_pushnil(L);
    else PushAddress(L, reinterpret_cast<uintptr_t>(p));
    return 1;
}

int WindowerInterface::lua_dealloc(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    lua_pushboolean(L, ::VirtualFree(reinterpret_cast<void*>(address), 0, MEM_RELEASE) ? 1 : 0);
    return 1;
}

int WindowerInterface::lua_unprotect(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    const size_t size = static_cast<size_t>(luaL_checknumber(L, 2));
    DWORD oldProtect = 0;
    lua_pushboolean(L, MakeWritable(address, size, &oldProtect) ? 1 : 0);
    return 1;
}

int WindowerInterface::lua_read_uint8(lua_State* L) { return ReadValue<uint8_t>(L); }
int WindowerInterface::lua_read_uint16(lua_State* L) { return ReadValue<uint16_t>(L); }
int WindowerInterface::lua_read_uint32(lua_State* L) { return ReadValue<uint32_t>(L); }
int WindowerInterface::lua_read_uint64(lua_State* L) { return ReadValue<uint64_t>(L); }
int WindowerInterface::lua_read_int8(lua_State* L) { return ReadValue<int8_t>(L); }
int WindowerInterface::lua_read_int16(lua_State* L) { return ReadValue<int16_t>(L); }
int WindowerInterface::lua_read_int32(lua_State* L) { return ReadValue<int32_t>(L); }
int WindowerInterface::lua_read_int64(lua_State* L) { return ReadValue<int64_t>(L); }
int WindowerInterface::lua_read_float(lua_State* L) { return ReadValue<float>(L); }
int WindowerInterface::lua_read_double(lua_State* L) { return ReadValue<double>(L); }

int WindowerInterface::lua_read_array(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    const size_t size = static_cast<size_t>(luaL_checknumber(L, 2));
    std::vector<uint8_t> bytes(size);
    if (!TryCopyFrom(address, bytes.data(), size)) {
        lua_pushnil(L);
        return 1;
    }

    lua_createtable(L, static_cast<int>(size), 0);
    for (size_t i = 0; i < size; ++i) {
        lua_pushinteger(L, static_cast<lua_Integer>(i + 1));
        lua_pushinteger(L, bytes[i]);
        lua_settable(L, -3);
    }
    return 1;
}

int WindowerInterface::lua_read_string(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    const size_t size = static_cast<size_t>(luaL_checknumber(L, 2));
    std::string value(size, '\0');
    if (!TryCopyFrom(address, &value[0], size)) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushlstring(L, value.data(), value.size());
    return 1;
}

int WindowerInterface::lua_write_uint8(lua_State* L) { return WriteValue<uint8_t>(L); }
int WindowerInterface::lua_write_uint16(lua_State* L) { return WriteValue<uint16_t>(L); }
int WindowerInterface::lua_write_uint32(lua_State* L) { return WriteValue<uint32_t>(L); }
int WindowerInterface::lua_write_uint64(lua_State* L) { return WriteValue<uint64_t>(L); }
int WindowerInterface::lua_write_int8(lua_State* L) { return WriteValue<int8_t>(L); }
int WindowerInterface::lua_write_int16(lua_State* L) { return WriteValue<int16_t>(L); }
int WindowerInterface::lua_write_int32(lua_State* L) { return WriteValue<int32_t>(L); }
int WindowerInterface::lua_write_int64(lua_State* L) { return WriteValue<int64_t>(L); }
int WindowerInterface::lua_write_float(lua_State* L) { return WriteValue<float>(L); }
int WindowerInterface::lua_write_double(lua_State* L) { return WriteValue<double>(L); }

int WindowerInterface::lua_write_array(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    std::vector<uint8_t> bytes;

    if (lua_istable(L, 2)) {
        const size_t size = static_cast<size_t>(lua_objlen(L, 2));
        bytes.reserve(size);
        for (size_t i = 1; i <= size; ++i) {
            lua_rawgeti(L, 2, static_cast<int>(i));
            bytes.push_back(static_cast<uint8_t>(luaL_checknumber(L, -1)));
            lua_pop(L, 1);
        }
    } else {
        size_t size = 0;
        const char* raw = luaL_checklstring(L, 2, &size);
        bytes.assign(raw, raw + size);
    }

    DWORD oldProtect = 0;
    if (!MakeWritable(address, bytes.size(), &oldProtect)) return 0;
    TryCopyTo(address, bytes.data(), bytes.size());
    DWORD ignored = 0;
    ::VirtualProtect(reinterpret_cast<void*>(address), bytes.size(), oldProtect, &ignored);
    return 0;
}

int WindowerInterface::lua_write_string(lua_State* L) {
    const uintptr_t address = CheckAddress(L, 1);
    size_t size = 0;
    const char* value = luaL_checklstring(L, 2, &size);

    DWORD oldProtect = 0;
    if (!MakeWritable(address, size, &oldProtect)) return 0;
    TryCopyTo(address, value, size);
    DWORD ignored = 0;
    ::VirtualProtect(reinterpret_cast<void*>(address), size, oldProtect, &ignored);
    return 0;
}

int WindowerInterface::registerInterface(lua_State* L) {
    static const luaL_Reg memoryFunctions[] = {
        { "get_baseaddr",      &WindowerInterface::lua_get_base },
        { "get_base",          &WindowerInterface::lua_get_base },
        { "get_modulesize",    &WindowerInterface::lua_get_size },
        { "get_size",          &WindowerInterface::lua_get_size },
        { "unprotect_memory",  &WindowerInterface::lua_unprotect },
        { "unprotect",         &WindowerInterface::lua_unprotect },
        { "allocate_memory",   &WindowerInterface::lua_alloc },
        { "allocate",          &WindowerInterface::lua_alloc },
        { "alloc",             &WindowerInterface::lua_alloc },
        { "deallocate_memory", &WindowerInterface::lua_dealloc },
        { "deallocate",        &WindowerInterface::lua_dealloc },
        { "dealloc",           &WindowerInterface::lua_dealloc },
        { "findpattern",       &WindowerInterface::lua_find },
        { "find",              &WindowerInterface::lua_find },
        { "read_uint8",        &WindowerInterface::lua_read_uint8 },
        { "read_uint16",       &WindowerInterface::lua_read_uint16 },
        { "read_uint32",       &WindowerInterface::lua_read_uint32 },
        { "read_uint64",       &WindowerInterface::lua_read_uint64 },
        { "read_int8",         &WindowerInterface::lua_read_int8 },
        { "read_int16",        &WindowerInterface::lua_read_int16 },
        { "read_int32",        &WindowerInterface::lua_read_int32 },
        { "read_int64",        &WindowerInterface::lua_read_int64 },
        { "read_float",        &WindowerInterface::lua_read_float },
        { "read_double",       &WindowerInterface::lua_read_double },
        { "read_array",        &WindowerInterface::lua_read_array },
        { "read_string",       &WindowerInterface::lua_read_string },
        { "read_bytes",        &WindowerInterface::lua_read_string },
        { "write_uint8",       &WindowerInterface::lua_write_uint8 },
        { "write_uint16",      &WindowerInterface::lua_write_uint16 },
        { "write_uint32",      &WindowerInterface::lua_write_uint32 },
        { "write_uint64",      &WindowerInterface::lua_write_uint64 },
        { "write_int8",        &WindowerInterface::lua_write_int8 },
        { "write_int16",       &WindowerInterface::lua_write_int16 },
        { "write_int32",       &WindowerInterface::lua_write_int32 },
        { "write_int64",       &WindowerInterface::lua_write_int64 },
        { "write_float",       &WindowerInterface::lua_write_float },
        { "write_double",      &WindowerInterface::lua_write_double },
        { "write_array",       &WindowerInterface::lua_write_array },
        { "write_string",      &WindowerInterface::lua_write_string },
        { "write_bytes",       &WindowerInterface::lua_write_string },
        { nullptr, nullptr },
    };

    lua_newtable(L);                // memory
    RegisterFunctions(L, memoryFunctions);

    lua_newtable(L);                // _XICamera
    lua_pushvalue(L, -2);
    lua_setfield(L, -2, "memory");
    lua_setglobal(L, "_XICamera");

    lua_pushvalue(L, -2);
    lua_setglobal(L, "windower_memory");

    return 1;                       // return memory table from require()
}

} // namespace XICamera
