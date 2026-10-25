# DataLayer-CLI 설치

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · **한국어** · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[README로 돌아가기](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md)

아래에서 운영체제를 선택하고 순서대로 진행하세요. MSYS2 명령이나 Bash 명령을 PowerShell에 붙여 넣지 마세요.

## 먼저 다운로드

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest)에서 운영체제에 맞는 압축 파일과 **같은 이름의 `.sha256` 파일**을 다운로드하세요. 두 파일을 새로운 빈 폴더에 넣고 이름은 그대로 유지하세요.

| 시스템 | 압축 파일 이름 끝부분 |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

아래 명령은 **v0.1.0** 기준입니다. Windows/Linux 바이너리에는 **Swift 6.1.2**가 필요합니다. 다른 릴리스에서는 해당 파일 이름과 요구사항을 확인하세요. 다른 아키텍처와 Linux 배포판은 바이너리 배포 대상이 아닙니다.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Swift 6.1.2 설치

Swift를 처음 설치한다면 **PowerShell**에서 아래 명령으로 x64 C++ 빌드 도구와 Windows SDK를 설치하세요. 이미 설치했다면 Visual Studio Installer에서 해당 구성요소를 확인하세요. [공식 요구사항](https://www.swift.org/install/windows/manual/)도 참고하세요.

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

[공식 Swift 6.1.2 x86_64 설치 프로그램](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe)을 실행하고 설치를 마친 뒤 **PowerShell을 닫았다가 다시 여세요**. 다음 명령에서 `6.1.2`가 표시되어야 합니다:

```powershell
swift --version
```

### 2. 미디어 및 그래픽 의존성 설치

[MSYS2](https://www.msys2.org/)를 설치하고 **MSYS2 UCRT64** 터미널에서 먼저 업데이트하세요:

```sh
pacman -Syu
```

터미널을 닫으라는 안내가 나오면 닫았다가 **UCRT64**를 다시 열고 업데이트를 반복하세요. 완료되면 다음 패키지를 설치하세요:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. 검증 및 압축 해제

**PowerShell**로 돌아가 다운로드한 ZIP과 체크섬 파일이 있는 폴더에서 여세요. 다음 블록을 실행하면 압축 해제 후 실행 파일 폴더로 이동합니다:

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

### 4. CLI 실행

같은 PowerShell 창에서 실행하세요. 처음 두 변수는 Swift/MSYS2 기본 설치 위치입니다. 다른 위치에 설치했다면 수정하세요. PATH 변경은 현재 터미널에만 적용됩니다:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. 의존성 설치

**Ubuntu 24.04 x86_64의 Bash** 터미널에서 실행하세요:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Swift 6.1.2 설치

[Swiftly](https://www.swift.org/install/linux/swiftly/)를 사용하며 최신 Swift를 먼저 설치하지 않습니다. Swiftly가 있다면 마지막 세 명령만 실행하세요. `+6.1.2`는 해당 명령의 도구 체인을 지정합니다:

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

### 3. 검증 및 압축 해제

Bash에서 다운로드한 `.tar.gz`와 `.sha256` 파일이 있는 폴더로 이동하세요. 검증하고 압축을 풀면 마지막 명령이 실행 파일 폴더로 이동합니다:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. CLI 실행

같은 터미널에 다음 블록을 붙여 넣으세요. Swift 6.1.2 라이브러리 위치를 자동으로 찾습니다:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

별도 런타임은 필요하지 않습니다. 실행 파일은 서명 및 공증되었습니다. 터미널에서 ZIP과 체크섬 파일이 있는 폴더를 열고 실행하세요:

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

## 내보내기 실행

FIT/GPX 활동 파일을 실행 파일 폴더에 넣으세요. 아래 `activity.fit`을 실제 파일 이름으로 바꾸고 확장자를 올바르게 유지하세요. 출력은 새 파일 이름을 사용하세요:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444는 세 플랫폼에서 투명도를 지원하며 투명 오버레이에는 오디오가 없습니다. Windows/Linux는 HEVC Alpha를 지원하지 않으며 투명도를 자동으로 버리지 않습니다.

## 다른 폴더에서 실행

선택 사항: 실행 파일 폴더에 있는 상태에서 현재 터미널의 PATH에 추가하세요. 이후 `./overlay`나 `.\overlay.exe` 대신 `overlay`를 사용할 수 있습니다:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

새 터미널에서는 Windows 4단계 또는 Ubuntu 4단계를 반복해 실행 환경을 복원하세요. 먼저 실행 파일 폴더로 돌아가거나 전체 경로를 사용하세요. 이 명령은 시스템 PATH를 영구적으로 덮어쓰지 않습니다.

## 선택 사항: 소스에서 빌드

바이너리 사용자는 건너뛰어도 됩니다. Git과 macOS용 Swift 5.9+/Xcode 명령줄 도구, 또는 Windows/Linux용 Swift 6.1.2와 의존성이 필요합니다. Ubuntu 소스 빌드는 다음 패키지도 필요합니다:

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

마지막 명령이 실행 파일 디렉터리를 출력합니다. 해당 디렉터리에서 `./overlay` 또는 `.\overlay.exe`로 실행하세요. 다운로드한 바이너리를 사용하는 데는 소스 빌드가 필요하지 않습니다.

## 문제 해결

| 문제 | 해결 방법 |
| --- | --- |
| `overlay`를 찾을 수 없음 | 실행 파일 폴더에서 `./overlay` / `.\overlay.exe`를 사용하거나 PATH 단계를 반복하세요. |
| Swift DLL / `.so` 누락 | Swift 6.1.2를 선택하고 런타임 단계 및 사용자 지정 설치 경로를 확인하세요. |
| Cairo/Pango 또는 FFmpeg 누락 | 위의 MSYS2 UCRT64 또는 Ubuntu 패키지를 모두 설치하고 `ffmpeg`와 `ffprobe`를 확인하세요. |
| 체크섬 불일치 | 중단하세요. 압축 파일과 해당 체크섬을 다시 다운로드하고 기존 파일은 실행하지 마세요. |
| 압축 해제 대상이 이미 존재함 | 새 폴더를 사용하세요. 기존 설치나 사용자 파일을 덮어쓰지 마세요. |
| 기존 출력 파일이 거부됨 | 새 이름 또는 `--force`를 사용하세요. 입력 파일은 보호됩니다. |
| Windows/Linux에서 HEVC Alpha가 거부됨 | 투명 출력에는 `--codec prores-4444`를 사용하세요. |
| 아키텍처 또는 Linux 배포판이 다름 | 위 표의 지원 대상을 사용하세요. 다른 대상은 이 절차에 포함되지 않습니다. |
| `winget` | Microsoft [App Installer](https://learn.microsoft.com/windows/package-manager/winget/)를 설치하거나 Visual Studio Installer에서 C++/SDK 구성요소를 직접 설치하세요. |

재배포할 때 [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE)와 [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md)를 유지하세요. Swift, FFmpeg, Cairo/Pango 및 글꼴은 별도로 설치하며 각자의 라이선스를 따릅니다.
