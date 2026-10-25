# DataLayer-CLI

**English** · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

Turn FIT/GPX activity data into transparent telemetry overlays or finished videos. Export DataLayer Studio `.dlsproj` projects from your terminal. The command is `overlay`.

## Install

Download the matching archive and its `.sha256` checksum from [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest), verify the checksum, then extract.

| System | Archive ending |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

The macOS binary is signed and notarized. No extra runtime installation is needed.

Windows/Linux require **Swift 6.1.2**, FFmpeg, Cairo/Pango and DejaVu fonts, installed separately. [Setup guide (English)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md)

Add the executable’s folder to `PATH`. Without that, replace `overlay` below with `./overlay` on macOS/Linux or `.\overlay.exe` in Windows PowerShell.

```sh
overlay --help
```

## Quick start

Create a transparent overlay from an activity:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

Burn telemetry into a video, keeping its audio:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

Export a saved GUI project using its export settings:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## Useful options

- `--sync-video 12 --sync-fit 45` (FIT/GPX): align video 12s with activity 45s.
- `--width 1920 --height 1080 --fps 30`: set output dimensions and frame rate; dimensions must be even, from 2 to 16384.
- `--layout-preset "layout.json"`: use an exported layout JSON with FIT/GPX input.
- `--force`: replace existing outputs; input files are always protected.

Run `overlay --help` for bitrate, units, time zones, trimming and `--inspect` (metadata without rendering).

## Codecs

- **H.264 / HEVC** (`h264`, `hevc`): finished video with source audio.
- **ProRes 4444** (`prores-4444`): transparent overlays on all three platforms.
- **HEVC Alpha** (`hevc-alpha`): macOS only, when supported by the system/encoder. Windows/Linux reject it without falling back to an opaque format.

Transparent overlays have no audio track.

## Good to know

- Projects restore saved export settings. Explicit CLI options override the corresponding settings.
- When moving a project, keep its media in the same relative folder layout. Apple bookmarks still depend on macOS file-access permissions.
- Saved weather is restored from the project cache; the CLI does not fetch new weather.
- Windows/Linux use software encoding and substitute fonts. Text, shadows, antialiasing and Alpha edges can differ from macOS.

## Build and contribute

[Build from source (English)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [Development guide (English)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

MIT — see [LICENSE](LICENSE) and third-party notices in [NOTICE.md](NOTICE.md).

The macOS/iOS apps and CLI share one Core. The GUI is maintained separately under its existing license.
