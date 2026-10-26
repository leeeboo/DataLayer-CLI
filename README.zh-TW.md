# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · **繁體中文** · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

將 FIT/GPX 運動資料匯出為透明資料圖層或合成影片，也可在終端機直接匯出 DataLayer Studio 的 `.dlsproj` 專案。指令名稱為 `overlay`。

**[開啟 GAUGE 布局編輯器](https://leeeboo.github.io/DataLayer-CLI/?lang=zh-TW)** — 在瀏覽器新增、匯入及編輯布局，下載 布局範本 `.dlspreset` 後透過 `--layout-preset` 使用。檔案僅在瀏覽器本機處理。

## 安裝

從 [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) 下載對應平台的壓縮檔及 `.sha256` 校驗檔，核對校驗值後解壓縮。

| 系統 | 壓縮檔後綴 |
| --- | --- |
| macOS 13+ / Apple Silicon | [macOS-arm64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-macOS-arm64.zip) |
| Windows / x86_64 | [Windows-x86_64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-Windows-x86_64.zip) |
| Ubuntu 24.04 / x86_64 | [Linux-x86_64.tar.gz](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-Linux-x86_64.tar.gz) |

macOS 版本已簽署並通過公證，不需額外安裝執行階段。

從 **v0.1.1** 起，Windows/Linux 套件已包含 Swift、FFmpeg、Cairo/Pango 與 DejaVu 字型，**無須安裝編譯器或執行階段**。 [安裝詳情](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md)

將執行檔所在目錄加入 `PATH`。尚未設定時，下方的 `overlay` 在 macOS/Linux 上改為 `./overlay`，Windows PowerShell 上改為 `.\overlay.exe`。

```sh
overlay --help
```

## 快速上手

從運動資料產生透明圖層：

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

將資料燒錄至影片，保留原始音訊：

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

直接匯出 GUI 儲存的專案，沿用專案匯出設定：

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## 常用選項

- `--sync-video 12 --sync-fit 45` (FIT/GPX): 將影片第 12 秒對齊運動第 45 秒。
- `--width 1920 --height 1080 --fps 30`: 設定輸出尺寸與影格率；寬高須為 2～16384 範圍內的偶數。
- `--layout-preset "layout.dlspreset"`: 為 FIT/GPX 輸入使用 `.dlspreset` 布局範本。
- `--force`: 覆寫現有輸出檔，始終保護輸入檔。

執行 `overlay --help` 查看位元率、單位、時區、裁剪與 `--inspect`（僅檢查中繼資料，不輸出影片）等選項。

## 編碼格式

- **H.264 / HEVC** (`h264`, `hevc`): 合成影片，保留原始音訊。
- **ProRes 4444** (`prores-4444`): 三個平台皆可匯出透明圖層。
- **HEVC Alpha** (`hevc-alpha`): 僅限系統與編碼器支援的 macOS。Windows/Linux 會明確拒絕，不會退回不透明格式。

透明圖層不含音軌。

## 使用須知

- 讀取專案儲存的匯出設定；明確傳入的 CLI 選項會覆寫對應設定。
- 移動專案時，請保留素材的相對目錄結構。Apple 書籤仍受 macOS 檔案存取權限限制。
- 天氣僅從專案快取還原，CLI 不會取得新天氣。
- Windows/Linux 使用軟體編碼與替代字型，文字、陰影、反鋸齒及 Alpha 邊緣可能與 macOS 不同。

## 編譯與貢獻

[從原始碼編譯](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [開發指南（英文）](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

採用 MIT 授權，詳見 [LICENSE](LICENSE)；第三方聲明見 [NOTICE.md](NOTICE.md)。

macOS、iOS 與 CLI 共用一份 Core；GUI 獨立維護，保留現有授權。
