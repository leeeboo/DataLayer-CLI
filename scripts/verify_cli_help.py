#!/usr/bin/env python3
"""Check actual CLI help bytes, locale precedence and parser exit status."""
import os
import pathlib
import subprocess
import sys

HEADINGS = {
    "en": "Usage", "zh-CN": "用法", "zh-TW": "用法", "ja": "使い方", "ko": "사용법",
    "es": "Uso", "fr": "Utilisation", "de": "Verwendung", "pt-BR": "Uso",
    "ru": "Использование", "ar": "الاستخدام", "hi": "उपयोग",
}
LOCALE_KEYS = ["LC_ALL", "LC_MESSAGES", "LANGUAGE", "LANG"]


def verify(binary, environment=None):
    binary = str(pathlib.Path(binary).resolve())
    clean = {k: v for k, v in (environment or os.environ).items() if k not in LOCALE_KEYS}

    def run(args, locale=None, status=0):
        result = subprocess.run([binary, *args], env={**clean, **(locale or {})},
                                capture_output=True, timeout=30)
        assert result.returncode == status, (args, result.returncode, result.stderr.decode("utf-8"))
        if status == 0:
            assert not result.stderr, result.stderr
            return result.stdout.decode("utf-8", errors="strict")
        assert not result.stdout, "Argument errors must leave stdout empty"
        assert result.stderr, "Argument errors must explain the failure on stderr"
        return result.stderr.decode("utf-8", errors="strict")

    texts = {}
    for code, heading in HEADINGS.items():
        text = run(["--language", code, "--help"], {"LC_ALL": "ja_JP.UTF-8"})
        assert text.startswith(heading + ":\n"), (code, text[:50])
        assert text == run(["-h", "--language=" + code])
        assert text == run(["--help", "--language", code])
        for token in ["--timeline-project PATH", "--layout-preset P", ".dlspreset", "--language CODE", "-h, --help"]:
            assert token in text, (code, token)
        assert "JSON" not in text and "\ufffd" not in text
        texts[code] = text
        assert text == run(["--help"], {"LANG": code.replace("-", "_") + ".UTF-8"})
    assert len(set(texts.values())) == 12
    for locale, code in [({"LC_ALL": "C", "LANG": "zh_CN.UTF-8"}, "en"),
                         ({"LC_ALL": "fr_CA.UTF-8", "LC_MESSAGES": "de", "LANG": "ja"}, "fr"),
                         ({"LC_MESSAGES": "zh_HK.UTF-8", "LANG": "en_US.UTF-8"}, "zh-TW"),
                         ({"LANGUAGE": "sv:pt_PT:ja", "LANG": "en"}, "pt-BR"),
                         ({"LC_ALL": "unsupported", "LANG": "zh"}, "en"),
                         ({"LANG": "zh-Hans-TW"}, "zh-CN")]:
        assert run(["--help"], locale) == texts[code], locale
    for args in [["--help", "--language=invalid"], ["-h", "--language"], ["--language=", "--help"]]:
        assert "--language" in run(args, status=2)
    for args, token in [(["--bogus"], "--bogus"), (["--output"], "--output")]:
        assert token in run(args, status=2)
    if os.name == "nt":
        verify_windows_console(binary, clean)
    print("CLI help: 12 languages, both flags, manual override, locale precedence, UTF-8 and error output streams passed.")


def verify_windows_console(binary, environment):
    import ctypes
    from ctypes import wintypes
    import msvcrt

    class COORD(ctypes.Structure):
        _fields_ = [("X", ctypes.c_short), ("Y", ctypes.c_short)]

    api = ctypes.WinDLL("kernel32", use_last_error=True)
    api.CreateConsoleScreenBuffer.argtypes = [wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, ctypes.c_void_p]
    api.CreateConsoleScreenBuffer.restype = wintypes.HANDLE
    api.SetConsoleScreenBufferSize.argtypes = [wintypes.HANDLE, COORD]
    api.ReadConsoleOutputCharacterW.argtypes = [wintypes.HANDLE, wintypes.LPWSTR, wintypes.DWORD, COORD, ctypes.POINTER(wintypes.DWORD)]
    allocated = bool(api.AllocConsole())
    handle = api.CreateConsoleScreenBuffer(0xC0000000, 3, None, 1, None)
    assert handle not in (None, wintypes.HANDLE(-1).value), ctypes.get_last_error()
    fd = msvcrt.open_osfhandle(handle, os.O_WRONLY)
    try:
        assert api.SetConsoleScreenBufferSize(handle, COORD(240, 1000))
        result = subprocess.run([binary, "--language", "ru", "--help"], env=environment,
                                stdout=fd, stderr=subprocess.PIPE, timeout=30)
        assert result.returncode == 0 and not result.stderr, result
        value = ctypes.create_unicode_buffer(20)
        read = wintypes.DWORD()
        assert api.ReadConsoleOutputCharacterW(handle, value, 19, COORD(0, 0), ctypes.byref(read))
        assert value.value.startswith(HEADINGS["ru"] + ":"), repr(value.value)
        print("Windows console: native Unicode screen-buffer output passed.")
    finally:
        os.close(fd)
        if allocated:
            api.FreeConsole()


if __name__ == "__main__":
    verify(sys.argv[1])
