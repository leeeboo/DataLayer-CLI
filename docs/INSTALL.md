# Install DataLayer-CLI

**English** · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Back to README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md)

Choose your system below. Follow its steps in order; do not paste MSYS2 commands into PowerShell or Bash commands into PowerShell.

## Download first

Download the matching archive **and its `.sha256` file** from [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Put both files in a new, empty folder. Keep both filenames unchanged.

| System | Archive ending |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Commands below use **v0.1.0**, whose Windows/Linux binaries require **Swift 6.1.2**. For another release, use its matching filenames and requirements. Other architectures and Linux distributions are not binary release targets.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Install Swift 6.1.2

For a new Swift installation, run this in **PowerShell** to install the x64 C++ build tools and Windows SDK. If already installed, check these components in Visual Studio Installer instead. See the [official prerequisites](https://www.swift.org/install/windows/manual/).

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

Run the [official Swift 6.1.2 x86_64 installer](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe), finish installation, then **close and reopen PowerShell**. This command should report `6.1.2`:

```powershell
swift --version
```

### 2. Install media and graphics dependencies

Install [MSYS2](https://www.msys2.org/). Open **MSYS2 UCRT64**, then update it:

```sh
pacman -Syu
```

If asked to close the terminal, close it, reopen **UCRT64** and repeat the update. Once finished, install:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. Verify and extract

Return to **PowerShell** and open it in the folder containing the downloaded ZIP and checksum. Copy this block; it enters the executable folder after extraction:

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

### 4. Run the CLI

In the same PowerShell window, paste this block. It uses the default Swift/MSYS2 locations; edit the first two variables if you chose different locations. PATH changes affect only this terminal:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. Install dependencies

Use an **Ubuntu 24.04 x86_64 Bash** terminal. Run:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Install Swift 6.1.2

This uses [Swiftly](https://www.swift.org/install/linux/swiftly/) without installing the latest Swift first. If Swiftly is already installed, run only the last three commands. `+6.1.2` explicitly selects the toolchain for that command:

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

### 3. Verify and extract

In Bash, go to the folder containing the downloaded `.tar.gz` and `.sha256`. Verify and extract; the last command enters the executable folder:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. Run the CLI

In the same terminal, copy this block. It locates the Swift 6.1.2 libraries automatically:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

No extra runtime is required. The executable is signed and notarized. In Terminal, open the folder containing the ZIP and checksum, then run:

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

## Try an export

Put a FIT/GPX activity file in the executable folder. Replace `activity.fit` below with its actual filename, including the correct extension. Use a new output filename:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 supports transparency on all three platforms; transparent overlays have no audio. Windows/Linux do not support HEVC Alpha and will not silently drop transparency.

## Run from another folder

Optional: while still in the executable folder, add it to PATH for this terminal. You can then use `overlay` instead of `./overlay` or `.\overlay.exe`:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

In a new terminal, repeat Windows step 4 or Ubuntu step 4 to restore the runtime environment. Return to the executable folder first, or use its full path. These commands do not permanently replace your system PATH.

## Optional: build from source

Binary users can skip this section. You need Git, Swift 5.9+ with Xcode command-line tools on macOS, or Swift 6.1.2 with its prerequisites on Windows/Linux. Ubuntu source builds also need:

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

The last command prints the executable directory. Run the binary there as `./overlay` or `.\overlay.exe`. These are source-build instructions, not steps required for the downloaded binary.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `overlay` is not found | Use `./overlay` / `.\overlay.exe` in its folder, or repeat the PATH step. |
| Missing Swift DLL / `.so` | Use Swift 6.1.2 and repeat the runtime step; check custom installation paths. |
| Cairo/Pango or FFmpeg is missing | Install all MSYS2 UCRT64 or Ubuntu packages above; confirm `ffmpeg` and `ffprobe` are found. |
| Checksum mismatch | Stop. Download the archive and its matching checksum again; do not run that archive. |
| Extraction target already exists | Use a fresh folder; do not overwrite an existing installation or your files. |
| Existing output is rejected | Use a new filename or `--force`; input files remain protected. |
| HEVC Alpha is rejected on Windows/Linux | Use `--codec prores-4444` for transparency. |
| Wrong architecture / unsupported Linux distribution | Use the supported binary target shown above; other targets are not covered by these steps. |
| `winget` | Install Microsoft [App Installer](https://learn.microsoft.com/windows/package-manager/winget/), or install the C++/SDK components through Visual Studio Installer. |

Keep [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) and [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md) when redistributing. Swift, FFmpeg, Cairo/Pango and fonts are installed separately and retain their own licenses.
