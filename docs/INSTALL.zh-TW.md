# 安裝 DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · **繁體中文** · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[返回 README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md)

從 [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) 下載對應系統的壓縮檔及同名 `.sha256` 檔案。請選平台套件，不是「Source code」或「dependency-sources」。

| 系統 | 壓縮檔 |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.2-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.2-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.2-Linux-x86_64.tar.gz` |

從 **v0.1.1** 起，Windows/Linux 套件已包含 Swift、FFmpeg、Cairo/Pango 與 DejaVu 字型，**無須安裝編譯器或執行階段**。

請保留解壓縮後的完整資料夾。執行頂層的 `overlay` 啟動器，不要單獨移動 `runtime/bin` 內的程式。

## Windows / PowerShell

驗證、解壓縮並執行

```powershell
$ErrorActionPreference = "Stop"
$cliDirectory = "DataLayer-CLI-v0.1.2-Windows-x86_64"
$archive = "$cliDirectory.zip"
$expected = (Get-Content "$archive.sha256").Split(' ')[0]
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $expected) {
    throw "Archive checksum mismatch"
}
if (Test-Path $cliDirectory) { throw "Destination already exists: $cliDirectory" }
Expand-Archive $archive -DestinationPath .
Set-Location $cliDirectory
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

驗證、解壓縮並執行

```sh
cli_directory="DataLayer-CLI-v0.1.2-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

驗證、解壓縮並執行

```sh
cli_directory="DataLayer-CLI-v0.1.2-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

在解壓縮目錄建立透明浮層。請將檔名替換為自己的素材；指令會保護現有輸出。

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

從原始碼建置為選用步驟。開發者仍需安裝 Swift 工具鏈及媒體/圖形相依套件，詳見[開發指南](../CONTRIBUTING.md)。

若提示缺少 DLL 或程式庫，請重新完整解壓縮。Windows 程式尚未簽章；macOS 程式已簽章並公證。Linux 二進位支援目標為 Ubuntu 24.04 x86_64。

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## 說明語言

`-h` 和 `--help` 支援與文件相同的 12 種語言。預設跟隨系統或終端機語言，無法匹配時使用英文。以 `--language CODE`（或 `--language=CODE`）手動指定，可放在 `--help` 前後。執行記錄和錯誤摘要仍為英文。

`overlay --language zh-TW --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
