# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · **한국어** · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

FIT/GPX 활동 데이터를 투명한 텔레메트리 오버레이 또는 합성 동영상으로 내보냅니다. 터미널에서 DataLayer Studio `.dlsproj` 프로젝트도 내보낼 수 있습니다. 명령어 이름은 `overlay`입니다.

**[게이지 레이아웃 편집기 열기](https://leeeboo.github.io/DataLayer-CLI/?lang=ko)** — 브라우저에서 레이아웃을 만들고 가져와 편집한 뒤, 레이아웃 프리셋 `.dlspreset`을 다운로드하여 `--layout-preset`으로 사용하세요. 파일은 브라우저 안에서만 처리됩니다.

## 설치

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest)에서 운영체제에 맞는 압축 파일과 `.sha256` 파일을 다운로드하고, 체크섬을 확인한 후 압축을 풉니다.

| 시스템 | 압축 파일 이름 끝부분 |
| --- | --- |
| macOS 13+ / Apple Silicon | [macOS-arm64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-macOS-arm64.zip) |
| Windows 10 1903+ / Windows 11 / x86_64 | [Windows-x86_64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-Windows-x86_64.zip) |
| Ubuntu 24.04 / x86_64 | [Linux-x86_64.tar.gz](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-Linux-x86_64.tar.gz) |

macOS 실행 파일은 서명 및 공증되었습니다. 별도 런타임 설치가 필요하지 않습니다.

**v0.1.1**부터 Windows/Linux 압축 파일에 Swift, FFmpeg, Cairo/Pango와 DejaVu 글꼴이 포함됩니다. **컴파일러나 런타임을 별도로 설치할 필요가 없습니다.** [설치 안내](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md)

실행 파일이 있는 폴더를 `PATH`에 추가하세요. 설정하지 않았다면 아래의 `overlay`를 macOS/Linux에서는 `./overlay`, Windows PowerShell에서는 `.\overlay.exe`로 바꾸세요.

```sh
overlay --help
```

## 도움말 언어

`-h`와 `--help`는 문서와 동일한 12개 언어를 지원합니다. 시스템 또는 터미널 언어를 따르며 미지원 시 영어를 사용합니다. `--language CODE`(또는 `--language=CODE`)로 지정할 수 있으며 `--help` 앞뒤 모두 가능합니다. 실행 로그와 오류 요약은 계속 영어로 표시됩니다.

```sh
overlay --help
overlay --language ko -h
```

`en, zh-CN, zh-TW, ja, ko, es, fr, de, pt-BR, ru, ar, hi`

## 빠른 시작

활동 데이터로 투명 오버레이 만들기:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

원본 오디오를 유지하면서 동영상에 데이터 합성하기:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

GUI에서 저장한 프로젝트를 기존 내보내기 설정으로 내보내기:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## 주요 옵션

- `--sync-video 12 --sync-fit 45` (FIT/GPX): 동영상의 12초 지점을 활동의 45초 지점과 맞춥니다.
- `--width 1920 --height 1080 --fps 30`: 출력 크기와 프레임 속도를 설정합니다. 너비와 높이는 2~16384 사이의 짝수여야 합니다.
- `--layout-preset "layout.dlspreset"`: FIT/GPX 입력에 `.dlspreset` 레이아웃 프리셋을 적용합니다.
- `--force`: 기존 출력 파일을 덮어씁니다. 입력 파일은 항상 보호됩니다.

비트레이트, 단위, 시간대, 자르기 및 `--inspect`(렌더링 없이 메타데이터만 확인)는 `overlay --help`를 참고하세요.

## 코덱

- **H.264 / HEVC** (`h264`, `hevc`): 원본 오디오가 포함된 합성 동영상.
- **ProRes 4444** (`prores-4444`): 세 플랫폼 모두에서 투명 오버레이를 내보냅니다.
- **HEVC Alpha** (`hevc-alpha`): 시스템과 인코더가 지원하는 macOS에서만 사용할 수 있습니다. Windows/Linux에서는 오류를 표시하며 불투명 형식으로 자동 전환하지 않습니다.

투명 오버레이에는 오디오 트랙이 없습니다.

## 알아둘 점

- 프로젝트에 저장된 내보내기 설정을 복원합니다. 명시적으로 지정한 CLI 옵션이 해당 설정을 덮어씁니다.
- 프로젝트를 이동할 때 미디어 파일의 상대 폴더 구조를 유지하세요. Apple 북마크에는 여전히 macOS 파일 접근 권한이 필요합니다.
- 날씨는 프로젝트 캐시에서 복원합니다. CLI는 새로운 날씨 데이터를 가져오지 않습니다.
- Windows/Linux는 소프트웨어 인코딩과 대체 글꼴을 사용합니다. 텍스트, 그림자, 안티앨리어싱 및 Alpha 경계가 macOS와 다를 수 있습니다.

## 빌드 및 기여

[개발 안내 (영어)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

MIT 라이선스입니다. [LICENSE](LICENSE)와 타사 고지 [NOTICE.md](NOTICE.md)를 확인하세요.

macOS/iOS 앱과 CLI는 하나의 Core를 공유합니다. GUI는 별도로 유지 관리되며 기존 라이선스를 따릅니다.
