# 安装 DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · **简体中文** · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[返回 README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md)

选择下方对应系统，按顺序操作。不要把 MSYS2 命令粘贴到 PowerShell，也不要在 PowerShell 中运行 Bash 命令。

## 先下载安装包

从 [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) 下载对应压缩包**及同名 `.sha256` 文件**，将两者放进一个新的空文件夹，保留原文件名。

| 系统 | 压缩包后缀 |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

下方命令使用 **v0.1.0**，其 Windows/Linux 安装包需要 **Swift 6.1.2**。其他版本请使用对应文件名和依赖。其他架构及 Linux 发行版不属于二进制发布目标。

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. 安装 Swift 6.1.2

首次安装 Swift 时，在 **PowerShell** 中运行下方命令，安装 x64 C++ 构建工具及 Windows SDK。若已安装，请在 Visual Studio Installer 中核对这些组件。参见[官方依赖说明](https://www.swift.org/install/windows/manual/)。

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

运行[官方 Swift 6.1.2 x86_64 安装程序](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe)，完成安装后，**关闭并重新打开 PowerShell**。下方命令应显示 `6.1.2`：

```powershell
swift --version
```

### 2. 安装媒体与图形依赖

安装 [MSYS2](https://www.msys2.org/)，打开 **MSYS2 UCRT64** 终端，先更新：

```sh
pacman -Syu
```

若提示关闭终端，请关闭后重新打开 **UCRT64**，再次运行更新命令。更新完成后安装：

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. 校验并解压

回到 **PowerShell**，在下载的 ZIP 和校验文件所在文件夹打开终端，复制下方命令。解压后会自动进入可执行文件目录：

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

### 4. 运行 CLI

在同一个 PowerShell 窗口粘贴下方命令。前两行使用 Swift/MSYS2 默认安装位置；若使用了自定义位置，请修改这两个变量。PATH 仅对当前终端生效：

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. 安装依赖

使用 **Ubuntu 24.04 x86_64 的 Bash** 终端，运行：

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. 安装 Swift 6.1.2

使用 [Swiftly](https://www.swift.org/install/linux/swiftly/)，不会先安装最新版 Swift。已安装 Swiftly 时，只需运行最后三条命令。`+6.1.2` 为该次命令明确选择工具链：

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

### 3. 校验并解压

在 Bash 中进入下载的 `.tar.gz` 和 `.sha256` 所在文件夹。校验并解压，最后一行会进入可执行文件目录：

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. 运行 CLI

在同一个终端复制下方命令，它会自动定位 Swift 6.1.2 的运行库：

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

无需额外安装运行库，可执行文件已签名并公证。在“终端”中进入 ZIP 和校验文件所在文件夹，运行：

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

## 试一次导出

将一个 FIT/GPX 运动文件放进可执行文件目录。把下方的 `activity.fit` 改为实际文件名，保留正确扩展名；输出请使用新文件名：

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 在三个平台均支持透明导出，透明浮层不含音轨。Windows/Linux 不支持 HEVC Alpha，不会自动丢弃透明通道。

## 从其他文件夹运行

可选：保持在可执行文件目录中，将其加入当前终端的 PATH。之后可用 `overlay` 代替 `./overlay` 或 `.\overlay.exe`：

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

新开终端后，重复 Windows 第 4 步或 Ubuntu 第 4 步以恢复运行环境。请先回到可执行文件目录，或使用其完整路径。以上命令不会永久覆盖系统 PATH。

## 可选：从源码编译

使用安装包可跳过本节。需要 Git；macOS 需要 Swift 5.9+ 和 Xcode 命令行工具，Windows/Linux 使用 Swift 6.1.2 及其依赖。Ubuntu 从源码编译还需：

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

最后一条命令会显示可执行文件目录。在该目录使用 `./overlay` 或 `.\overlay.exe` 运行。此处仅供源码编译，使用下载的安装包不需要这些步骤。

## 常见问题

| 问题 | 处理方法 |
| --- | --- |
| 找不到 `overlay` | 在程序目录使用 `./overlay` / `.\overlay.exe`，或重做 PATH 步骤。 |
| 缺少 Swift DLL / `.so` | 确认 Swift 为 6.1.2，重做运行库步骤，并核对自定义安装路径。 |
| 找不到 Cairo/Pango 或 FFmpeg | 安装上方全部 MSYS2 UCRT64 或 Ubuntu 依赖，确认能找到 `ffmpeg` 和 `ffprobe`。 |
| 校验值不匹配 | 停止操作，重新下载压缩包及对应校验文件，不要运行该压缩包内的程序。 |
| 解压目标已存在 | 换一个新文件夹，不要覆盖已有安装或自己的文件。 |
| 拒绝覆盖已有输出 | 更换输出文件名，或使用 `--force`；输入文件仍受保护。 |
| Windows/Linux 拒绝 HEVC Alpha | 透明导出请使用 `--codec prores-4444`。 |
| 架构或 Linux 发行版不匹配 | 使用上表支持的二进制目标，其他目标不在本指南的安装范围内。 |
| `winget` | 安装微软 [App Installer](https://learn.microsoft.com/windows/package-manager/winget/)，或通过 Visual Studio Installer 手动安装 C++/SDK 组件。 |

重新分发时保留 [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) 和 [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md)。Swift、FFmpeg、Cairo/Pango 和字体均单独安装，保留各自协议。
