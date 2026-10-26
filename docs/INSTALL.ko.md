# DataLayer-CLI 설치

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · **한국어** · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[README로 돌아가기](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md)

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest)에서 운영체제에 맞는 압축 파일과 같은 이름의 `.sha256` 파일을 받으세요. “Source code”나 “dependency-sources” 대신 플랫폼 패키지를 선택하세요.

| 시스템 | 압축 파일 |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.1-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.1-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.1-Linux-x86_64.tar.gz` |

**v0.1.1**부터 Windows/Linux 압축 파일에 Swift, FFmpeg, Cairo/Pango와 DejaVu 글꼴이 포함됩니다. **컴파일러나 런타임을 별도로 설치할 필요가 없습니다.**

압축을 푼 폴더 전체를 유지하세요. 최상위 `overlay` 실행기를 사용하고 `runtime/bin`의 실행 파일만 옮기지 마세요.

## Windows / PowerShell

확인, 압축 풀기, 실행

```powershell
$ErrorActionPreference = "Stop"
$cliDirectory = "DataLayer-CLI-v0.1.1-Windows-x86_64"
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

확인, 압축 풀기, 실행

```sh
cli_directory="DataLayer-CLI-v0.1.1-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

확인, 압축 풀기, 실행

```sh
cli_directory="DataLayer-CLI-v0.1.1-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

압축을 푼 폴더에서 투명 오버레이를 만듭니다. 파일명을 자신의 파일로 바꾸세요. 기존 출력은 보호됩니다.

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

소스 빌드는 선택 사항입니다. 개발자는 Swift 도구 체인과 미디어·그래픽 라이브러리가 필요합니다. [개발 안내](../CONTRIBUTING.md)를 참고하세요.

DLL이나 라이브러리가 없다는 메시지가 나오면 전체 압축 파일을 다시 풀어주세요. Windows 실행 파일은 서명되지 않았고 macOS 실행 파일은 서명 및 공증되었습니다. Linux 바이너리는 Ubuntu 24.04 x86_64를 지원합니다.

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`
