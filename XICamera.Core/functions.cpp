/*
===========================================================================

Copyright (c) 2010-2014 Darkstar Dev Teams

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see http://www.gnu.org/licenses/

This file is part of DarkStar-server source code.

===========================================================================
*/

#include "functions.h"

namespace XICamera
{
    /**
     * @brief Compares a pattern against a given memory pointer.
     *
     * @param lpDataPtr     The live data to compare with.
     * @param lpPattern     The pattern of bytes to compare with.
     * @param pszMask       The mask to compare against.
     *
     * @return True if pattern was found, false otherwise.
     */
    bool functions::MaskCompare(const unsigned char* lpDataPtr, const unsigned char* lpPattern, const char* pszMask)
    {
        for (; *pszMask; ++pszMask, ++lpDataPtr, ++lpPattern)
        {
            if (*pszMask == 'x' && *lpDataPtr != *lpPattern)
                return false;
        }
        return (*pszMask) == NULL;
    }

    /**
     * @brief Locates a signature of bytes using the given mask within the given module.
     *
     * @param moduleName    The name of the module to scan within.
     * @param lpPattern     The pattern of bytes to compare with.
     * @param pszMask       The mask to compare against.
     *
     * @return Start address of where the pattern was found, NULL otherwise.
     */
    DWORD functions::FindPattern(const char* moduleName, const unsigned char* lpPattern, const char* pszMask)
    {
        MODULEINFO mod = { 0 };
        if (!GetModuleInformation(GetCurrentProcess(), GetModuleHandleA(moduleName), &mod, sizeof(MODULEINFO)))
            return 0;

        for (DWORD x = 0; x < mod.SizeOfImage; x++)
        {
            if (functions::MaskCompare(reinterpret_cast<unsigned char*>((DWORD)mod.lpBaseOfDll + x), lpPattern, pszMask))
                return ((DWORD)mod.lpBaseOfDll + x);
        }
        return 0;
    }

    /**
     * @brief Obtains the PlayOnline registry key.
     *  "SOFTWARE\PlayOnlineXX"
     *
     * @param lang      The language id the loader was started with.
     *
     * @return registry pathname.
     */
    const char* functions::GetRegistryPlayOnlineKey(int lang)
    {
        static const char*  RegistryKeys[3] =
        {
            "SOFTWARE\\PlayOnline",   // xiloader::Japanese
            "SOFTWARE\\PlayOnlineUS", // xiloader::English
            "SOFTWARE\\PlayOnlineEU"  // xiloader::European
        };

        if(lang < 0)
            lang = 0;
        if(lang > 2)
            lang = 2;

        return RegistryKeys[lang];
    }

    /**
     * @brief Obtains the PlayOnline language id from the system registry.
     *
     * @param lang          The language id the loader was started with.
     *
     * @return The language id from the registry, 1 otherwise.
     */
    int functions::GetRegistryPlayOnlineLanguage(int lang)
    {
        const char*  SquareEnix = (lang == 0 /*xiloader::Japanese*/) ? "Square" : "SquareEnix";

        char  szRegistryPath[MAX_PATH];
        sprintf_s(szRegistryPath, MAX_PATH, "%s\\%s\\PlayOnlineViewer\\Settings", functions::GetRegistryPlayOnlineKey(lang), SquareEnix);

        HKEY  hKey = NULL;
        DWORD dwRegValue = 0;
        DWORD dwRegSize = sizeof(DWORD);
        DWORD dwRegType = REG_DWORD;

        if (::RegOpenKeyExA(HKEY_LOCAL_MACHINE, szRegistryPath, 0, KEY_QUERY_VALUE | KEY_WOW64_32KEY, &hKey) == ERROR_SUCCESS)
        {
            if (::RegQueryValueExA(hKey, "Language", NULL, &dwRegType, (LPBYTE)&dwRegValue, &dwRegSize) == ERROR_SUCCESS)
            {
                if (dwRegType == REG_DWORD && dwRegSize == sizeof(DWORD))
                    lang = (int) dwRegValue;
            }
            ::RegCloseKey(hKey);
        }

        return lang;
    }

    /**
     * @brief Obtains the PlayOnlineViewer folder from the system registry.
     *  "C:\Program Files\PlayOnline\PlayOnlineViewer"
     *
     * @param lang      The language id the loader was started with.
     *
     * @return installation folder path.
     */
    const char* functions::GetRegistryPlayOnlineInstallFolder(int lang)
    {
        static char  InstallFolder[MAX_PATH] = {0};

        char  szRegistryPath[MAX_PATH];
        sprintf_s(szRegistryPath, MAX_PATH, "%s\\InstallFolder", functions::GetRegistryPlayOnlineKey(lang));

        HKEY  hKey = NULL;
        DWORD dwRegSize = sizeof(InstallFolder);
        DWORD dwRegType = REG_SZ;
        bool  found = false;

        if (::RegOpenKeyExA( HKEY_LOCAL_MACHINE, szRegistryPath, 0, KEY_QUERY_VALUE | KEY_WOW64_32KEY, &hKey) == ERROR_SUCCESS)
        {
            if (::RegQueryValueExA(hKey, "1000", NULL, &dwRegType, (LPBYTE)InstallFolder, &dwRegSize) == ERROR_SUCCESS)
            {
                if (dwRegType == REG_SZ && dwRegSize > 0 && dwRegSize < sizeof(InstallFolder))
                     found = true;
            }
            ::RegCloseKey(hKey);
        }

        if (found == false)
            InstallFolder[0] = '\0';

        return InstallFolder;
    }

};
