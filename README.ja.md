# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · **日本語** · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

FIT/GPX のアクティビティデータから、透明なテレメトリーオーバーレイや合成動画を作成します。DataLayer Studio の `.dlsproj` プロジェクトもターミナルから書き出せます。コマンド名は `overlay` です。

## インストール

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) から対応するアーカイブと `.sha256` をダウンロードし、チェックサムを確認して展開します。

| システム | アーカイブ名の末尾 |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

macOS 版は署名・公証済みです。追加のランタイムは不要です。

Windows/Linux では **Swift 6.1.2**、FFmpeg、Cairo/Pango、DejaVu フォントを別途インストールしてください。 [セットアップ手順（英語）](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md)

実行ファイルのフォルダーを `PATH` に追加します。未設定の場合、以下の `overlay` を macOS/Linux では `./overlay`、Windows PowerShell では `.\overlay.exe` に置き換えてください。

```sh
overlay --help
```

## クイックスタート

アクティビティから透明なオーバーレイを作成：

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

元の音声を残して動画にデータを焼き込み：

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

GUI で保存したプロジェクトを、その書き出し設定で出力：

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## よく使うオプション

- `--sync-video 12 --sync-fit 45` (FIT/GPX): 動画の 12 秒とアクティビティの 45 秒を同期します。
- `--width 1920 --height 1080 --fps 30`: 出力サイズとフレームレートを指定します。幅と高さは 2～16384 の偶数です。
- `--layout-preset "layout.json"`: FIT/GPX 入力に、書き出したレイアウト JSON を適用します。
- `--force`: 既存の出力を上書きします。入力ファイルは保護されます。

ビットレート、単位、タイムゾーン、トリミング、`--inspect`（描画せずメタデータのみ確認）は `overlay --help` を参照してください。

## コーデック

- **H.264 / HEVC** (`h264`, `hevc`): 元の音声を含む合成動画。
- **ProRes 4444** (`prores-4444`): 3 つのプラットフォームで透明なオーバーレイを出力。
- **HEVC Alpha** (`hevc-alpha`): 対応するシステム・エンコーダーを備えた macOS のみ。Windows/Linux ではエラーになり、不透明な形式へ自動変更しません。

透明なオーバーレイに音声トラックは含まれません。

## 注意点

- プロジェクトに保存された書き出し設定を復元します。明示的な CLI オプションは対応する設定を上書きします。
- プロジェクトを移動する際は、素材との相対フォルダー構成を維持してください。Apple のブックマークには macOS のファイルアクセス権限が必要です。
- 保存済みの天気をプロジェクトのキャッシュから復元します。新しい天気は取得しません。
- Windows/Linux はソフトウェアエンコードと代替フォントを使用します。文字、影、アンチエイリアス、Alpha の境界は macOS と異なる場合があります。

## ビルドと開発への参加

[ソースからビルド（英語）](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [開発ガイド（英語）](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

MIT ライセンス：[LICENSE](LICENSE)。第三者に関する表記は [NOTICE.md](NOTICE.md) を参照してください。

macOS/iOS アプリと CLI は同じ Core を共有します。GUI は別途管理され、従来のライセンスが適用されます。
