/* Keep the portable runtime private to this process and preserve the user's arguments. */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

int wmain(void) {
    WCHAR root[32768];
    DWORD size = GetModuleFileNameW(NULL, root, 32768);
    if (!size || size >= 32768 || !wcsrchr(root, L'\\')) return 125;
    *wcsrchr(root, L'\\') = 0;
    DWORD old_size = GetEnvironmentVariableW(L"PATH", NULL, 0);
    WCHAR *path = calloc(old_size + wcslen(root) + 32, sizeof(WCHAR));
    if (!path) return 125;
    swprintf(path, old_size + wcslen(root) + 32, L"%ls\\runtime\\bin;", root);
    GetEnvironmentVariableW(L"PATH", path + wcslen(path), old_size);
    if (!SetEnvironmentVariableW(L"PATH", path)) { free(path); return 125; }
    free(path);
    WCHAR fonts[32768];
    if (wcslen(root) + 32 >= 32768) return 125;
    swprintf(fonts, 32768, L"%ls\\runtime\\fonts.conf", root);
    if (!SetEnvironmentVariableW(L"FONTCONFIG_FILE", fonts)) return 125;
    WCHAR *tail = GetCommandLineW();
    if (*tail == L'"') { ++tail; while (*tail && *tail != L'"') ++tail; if (*tail) ++tail; }
    else { while (*tail && *tail != L' ' && *tail != L'\t') ++tail; }
    size_t length = wcslen(root) + wcslen(tail) + 40;
    WCHAR *command = calloc(length, sizeof(WCHAR));
    if (!command) return 125;
    swprintf(command, length, L"\"%ls\\runtime\\bin\\overlay.exe\"%ls", root, tail);
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION child = {0};
    startup.cb = sizeof(startup);
    BOOL created = CreateProcessW(NULL, command, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &child);
    free(command);
    if (!created) { fwprintf(stderr, L"Cannot start bundled CLI (Windows error %lu). Keep the complete extracted folder.\n", GetLastError()); return 125; }
    WaitForSingleObject(child.hProcess, INFINITE);
    DWORD status = 125;
    GetExitCodeProcess(child.hProcess, &status);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    return (int)status;
}
