# 安裝 DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · **繁體中文** · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[返回 README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md)

選擇下方對應系統，依序操作。請勿將 MSYS2 指令貼到 PowerShell，也不要在 PowerShell 中執行 Bash 指令。

## 先下載安裝包

從 [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) 下載對應壓縮檔**及同名 `.sha256` 檔案**，將兩者放入新的空資料夾，保留原檔名。

| 系統 | 壓縮檔後綴 |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

下方指令使用 **v0.1.0**，其 Windows/Linux 安裝包需要 **Swift 6.1.2**。其他版本請使用對應檔名與相依套件。其他架構及 Linux 發行版不屬於二進位發佈目標。

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. 安裝 Swift 6.1.2

首次安裝 Swift 時，在 **PowerShell** 執行下方指令，安裝 x64 C++ 建置工具與 Windows SDK。若已安裝，請在 Visual Studio Installer 核對這些元件。參閱[官方相依套件說明](https://www.swift.org/install/windows/manual/)。

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

執行[官方 Swift 6.1.2 x86_64 安裝程式](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe)，完成後**關閉並重新開啟 PowerShell**。下方指令應顯示 `6.1.2`：

```powershell
swift --version
```

### 2. 安裝媒體與圖形相依套件

安裝 [MSYS2](https://www.msys2.org/)，開啟 **MSYS2 UCRT64** 終端機，先更新：

```sh
pacman -Syu
```

若提示關閉終端機，請關閉後重新開啟 **UCRT64**，再次執行更新指令。完成後安裝：

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. 校驗並解壓縮

回到 **PowerShell**，在下載的 ZIP 與校驗檔所在資料夾開啟終端機，貼上下方指令。解壓縮後會自動進入執行檔目錄：

```powershell
$ErrorActionPreference = "Stop"
$cliVersion = "v0.1.0"
$cliDirectory = "DataLayer-CLI-$cliVersion-Windows-x86_64"
$archive = "$cliDirectory.zip"
$expected = (Get-Content "$archive.sha256").Split(' ')[0]
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $expected) {
    throw "Archive checksum mismatch"
}
if (Test-Path $cliDirectory) { throw "Destination already exists: $cliDirectory" }
Expand-Archive $archive -DestinationPath .
Set-Location $cliDirectory
```

### 4. 執行 CLI

在同一個 PowerShell 視窗貼上下方指令。前兩行使用 Swift/MSYS2 預設安裝位置；若使用自訂位置，請修改這兩個變數。PATH 僅對目前終端機生效：

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. 安裝相依套件

使用 **Ubuntu 24.04 x86_64 的 Bash** 終端機，執行：

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. 安裝 Swift 6.1.2

使用 [Swiftly](https://www.swift.org/install/linux/swiftly/)，不會先安裝最新版 Swift。已安裝 Swiftly 時，只需執行最後三條指令。`+6.1.2` 為該次指令明確選擇工具鏈：

```sh
swiftly_setup_dir="$(mktemp -d)"
(
  cd "$swiftly_setup_dir" &&
  curl -fL "https://download.swift.org/swiftly/linux/swiftly-1.1.2-x86_64.tar.gz" -o swiftly.tar.gz &&
  tar -xzf swiftly.tar.gz &&
  ./swiftly init --skip-install --assume-yes --quiet-shell-followup
) &&
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swiftly install 6.1.2 --assume-yes &&
swiftly run swift --version +6.1.2
```

### 3. 校驗並解壓縮

在 Bash 進入下載的 `.tar.gz` 與 `.sha256` 所在資料夾。校驗並解壓縮，最後一行會進入執行檔目錄：

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. 執行 CLI

在同一個終端機貼上下方指令，它會自動找到 Swift 6.1.2 的執行階段程式庫：

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

不需額外安裝執行階段，執行檔已簽署並通過公證。在「終端機」進入 ZIP 與校驗檔所在資料夾，執行：

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-macOS-arm64"
cli_archive="$cli_dir.zip"
shasum -a 256 -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
unzip "$cli_archive" &&
cd "$cli_dir" &&
./overlay --help
```

## 試著匯出

將一個 FIT/GPX 運動檔案放入執行檔目錄。將下方 `activity.fit` 改為實際檔名，保留正確副檔名；輸出請使用新檔名：

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 在三個平台皆支援透明匯出，透明圖層不含音軌。Windows/Linux 不支援 HEVC Alpha，不會自動捨棄透明通道。

## 從其他資料夾執行

選用：保持在執行檔目錄，將其加入目前終端機的 PATH。之後可使用 `overlay` 代替 `./overlay` 或 `.\overlay.exe`：

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

開啟新終端機後，重做 Windows 第 4 步或 Ubuntu 第 4 步以還原執行環境。請先回到執行檔目錄，或使用其完整路徑。以上指令不會永久覆寫系統 PATH。

## 選用：從原始碼編譯

使用安裝包可略過本節。需要 Git；macOS 需要 Swift 5.9+ 與 Xcode 命令列工具，Windows/Linux 使用 Swift 6.1.2 及其相依套件。Ubuntu 從原始碼編譯還需：

**Ubuntu**

```sh
sudo apt-get install -y build-essential git pkg-config libcurl4-openssl-dev libxml2-dev libncurses-dev libz3-dev libpython3-dev zlib1g-dev
```

```sh
git clone https://github.com/leeeboo/DataLayer-CLI.git
cd DataLayer-CLI
```

**macOS / Windows**

```sh
swift build -c release --product overlay
swift build -c release --show-bin-path
```

**Linux**

```sh
swiftly run swift build -c release --product overlay +6.1.2
swiftly run swift build -c release --show-bin-path +6.1.2
```

最後一條指令會顯示執行檔目錄。在該目錄使用 `./overlay` 或 `.\overlay.exe` 執行。此處僅供原始碼編譯，使用下載的安裝包不需要這些步驟。

## 常見問題

| 問題 | 處理方式 |
| --- | --- |
| 找不到 `overlay` | 在程式目錄使用 `./overlay` / `.\overlay.exe`，或重做 PATH 步驟。 |
| 缺少 Swift DLL / `.so` | 確認 Swift 為 6.1.2，重做執行階段步驟並核對自訂安裝路徑。 |
| 找不到 Cairo/Pango 或 FFmpeg | 安裝上方全部 MSYS2 UCRT64 或 Ubuntu 相依套件，確認能找到 `ffmpeg` 和 `ffprobe`。 |
| 校驗值不符 | 停止操作，重新下載壓縮檔及對應校驗檔，請勿執行該壓縮檔內的程式。 |
| 解壓縮目標已存在 | 改用新的資料夾，不要覆寫現有安裝或自己的檔案。 |
| 拒絕覆寫現有輸出 | 更換輸出檔名，或使用 `--force`；輸入檔仍受保護。 |
| Windows/Linux 拒絕 HEVC Alpha | 透明匯出請使用 `--codec prores-4444`。 |
| 架構或 Linux 發行版不符 | 使用上表支援的二進位目標，其他目標不在本指南的安裝範圍內。 |
| `winget` | 安裝 Microsoft [App Installer](https://learn.microsoft.com/windows/package-manager/winget/)，或透過 Visual Studio Installer 手動安裝 C++/SDK 元件。 |

重新散布時保留 [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) 與 [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md)。Swift、FFmpeg、Cairo/Pango 與字型均另行安裝，保留各自授權。
