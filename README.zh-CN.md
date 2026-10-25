# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · **简体中文** · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

将 FIT/GPX 运动数据导出为透明数据浮层或合成视频，也可在终端直接导出 DataLayer Studio 的 `.dlsproj` 工程。命令名为 `overlay`。

## 安装

从 [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) 下载对应平台的压缩包及 `.sha256` 校验文件，核对校验值后解压。

| 系统 | 压缩包后缀 |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

macOS 版本已签名并公证，无需额外安装运行库。

Windows/Linux 需另行安装 **Swift 6.1.2**、FFmpeg、Cairo/Pango 和 DejaVu 字体。 [安装详情](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md)

将可执行文件所在目录加入 `PATH`。未配置时，下方的 `overlay` 在 macOS/Linux 上改为 `./overlay`，Windows PowerShell 上改为 `.\overlay.exe`。

```sh
overlay --help
```

## 快速上手

从运动数据生成透明浮层：

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

将数据烧录到视频中，保留原视频音频：

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

直接导出 GUI 保存的工程，沿用工程导出设置：

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## 常用选项

- `--sync-video 12 --sync-fit 45` (FIT/GPX): 将视频第 12 秒对齐到运动第 45 秒。
- `--width 1920 --height 1080 --fps 30`: 设置输出尺寸和帧率；宽高须为 2～16384 范围内的偶数。
- `--layout-preset "layout.json"`: 为 FIT/GPX 输入使用导出的布局 JSON。
- `--force`: 覆盖已有输出文件；始终保护输入文件。

运行 `overlay --help` 查看码率、单位、时区、裁剪和 `--inspect`（仅检查元数据，不渲染）等选项。

## 编码格式

- **H.264 / HEVC** (`h264`, `hevc`): 合成成片，保留原视频音频。
- **ProRes 4444** (`prores-4444`): 三个平台均可导出透明浮层。
- **HEVC Alpha** (`hevc-alpha`): 仅限系统和编码器支持的 macOS。Windows/Linux 会明确拒绝，不会退回不透明格式。

透明浮层不包含音轨。

## 使用须知

- 读取工程保存的导出设置；显式传入的 CLI 选项会覆盖对应设置。
- 移动工程时，请保持素材的相对目录结构。Apple 书签仍受 macOS 文件访问权限限制。
- 天气仅从工程缓存恢复，CLI 不会获取新天气。
- Windows/Linux 使用软件编码和替代字体，文字、阴影、抗锯齿及 Alpha 边缘可能与 macOS 不同。

## 编译与贡献

[从源码编译](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [开发指南（英文）](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

采用 MIT 协议，详见 [LICENSE](LICENSE)；第三方声明见 [NOTICE.md](NOTICE.md)。

macOS、iOS 和 CLI 共用一份 Core；GUI 独立维护，保留现有授权。
