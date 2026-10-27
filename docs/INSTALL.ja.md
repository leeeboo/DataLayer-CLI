# DataLayer-CLI のインストール

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · **日本語** · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[README に戻る](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md)

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) から対応するアーカイブと同名の `.sha256` ファイルをダウンロードしてください。「Source code」や「dependency-sources」ではなく、お使いの OS 用のパッケージを選びます。

| システム | アーカイブ |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.2-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.2-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.2-Linux-x86_64.tar.gz` |

**v0.1.1** 以降の Windows/Linux アーカイブには Swift、FFmpeg、Cairo/Pango、DejaVu フォントが含まれます。**コンパイラやランタイムのインストールは不要です。**

展開したフォルダ全体を保持してください。最上位の `overlay` ランチャーを実行し、`runtime/bin` 内の実行ファイルだけを移動しないでください。

## Windows / PowerShell

検証・展開・実行

```powershell
$ErrorActionPreference = "Stop"
$cliDirectory = "DataLayer-CLI-v0.1.2-Windows-x86_64"
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

検証・展開・実行

```sh
cli_directory="DataLayer-CLI-v0.1.2-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

検証・展開・実行

```sh
cli_directory="DataLayer-CLI-v0.1.2-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

展開したフォルダで透明オーバーレイを作成します。ファイル名は自分の素材に置き換えてください。既存の出力は保護されます。

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

ソースからのビルドは任意です。開発には Swift ツールチェーンとメディア・描画用ライブラリが必要です。[開発ガイド](../CONTRIBUTING.md)をご覧ください。

DLL やライブラリが不足する場合はアーカイブ全体を再展開してください。Windows 版は未署名、macOS 版は署名・公証済みです。Linux バイナリの対象は Ubuntu 24.04 x86_64 です。

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## ヘルプの言語

`-h` と `--help` はドキュメントと同じ 12 言語に対応します。システムまたは端末の言語に従い、未対応の場合は英語を使用します。`--language CODE`（または `--language=CODE`）で指定でき、`--help` の前後どちらでも使用できます。実行ログとエラーの要約は引き続き英語です。

macOS / Linux: `./overlay --language ja --help`

Windows / PowerShell: `.\overlay.exe --language ja --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
