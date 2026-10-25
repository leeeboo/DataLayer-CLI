# DataLayer-CLI のインストール

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · **日本語** · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[README に戻る](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md)

使用するシステムの手順を順番に実行してください。MSYS2 のコマンドや Bash のコマンドを PowerShell に貼り付けないでください。

## まずダウンロード

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) から対応するアーカイブと**同名の `.sha256` ファイル**をダウンロードし、名前を変えずに新しい空のフォルダーに置きます。

| システム | アーカイブ名の末尾 |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

以下は **v0.1.0** 用です。Windows/Linux のバイナリには **Swift 6.1.2** が必要です。別のリリースでは対応するファイル名と要件を確認してください。他のアーキテクチャや Linux ディストリビューションはバイナリ配布対象ではありません。

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Swift 6.1.2 をインストール

Swift を新規インストールする場合は、**PowerShell** で以下を実行し、x64 C++ ビルドツールと Windows SDK を導入します。導入済みなら Visual Studio Installer で必要なコンポーネントを確認してください。[公式の前提条件](https://www.swift.org/install/windows/manual/)も参照できます。

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

[公式 Swift 6.1.2 x86_64 インストーラー](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe)を実行して完了したら、**PowerShell を閉じて開き直します**。次のコマンドで `6.1.2` と表示されることを確認します：

```powershell
swift --version
```

### 2. メディアと描画の依存関係をインストール

[MSYS2](https://www.msys2.org/) をインストールし、**MSYS2 UCRT64** ターミナルを開いて更新します：

```sh
pacman -Syu
```

終了を求められたらターミナルを閉じ、**UCRT64** を開き直して更新を繰り返します。完了後、以下をインストールします：

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. 検証して展開

**PowerShell** に戻り、ダウンロードした ZIP とチェックサムのあるフォルダーで開きます。以下を貼り付けると、展開後に実行ファイルのフォルダーへ移動します：

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

### 4. CLI を実行

同じ PowerShell で実行します。最初の 2 変数は Swift/MSYS2 の標準インストール先です。別の場所に導入した場合は変更してください。PATH の変更はこのターミナルだけに適用されます：

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. 依存関係をインストール

**Ubuntu 24.04 x86_64 の Bash** ターミナルで実行します：

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Swift 6.1.2 をインストール

[Swiftly](https://www.swift.org/install/linux/swiftly/) を使用し、先に最新 Swift を入れることはありません。Swiftly が導入済みなら最後の 3 コマンドのみ実行します。`+6.1.2` はそのコマンドのツールチェーンを指定します：

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

### 3. 検証して展開

Bash でダウンロードした `.tar.gz` と `.sha256` のあるフォルダーに移動します。検証して展開し、最後に実行ファイルのフォルダーへ移動します：

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. CLI を実行

同じターミナルに以下を貼り付けます。Swift 6.1.2 のライブラリは自動的に検出されます：

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

追加ランタイムは不要です。実行ファイルは署名・公証済みです。ターミナルで ZIP とチェックサムのあるフォルダーを開いて実行します：

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

## 書き出しを試す

FIT/GPX のアクティビティファイルを実行ファイルのフォルダーに置き、`activity.fit` を実際のファイル名に置き換えてください。拡張子を正しく保ち、出力には新しいファイル名を使います：

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 は 3 つのプラットフォームで透明出力に対応します。透明なオーバーレイに音声はありません。Windows/Linux は HEVC Alpha 非対応で、透明度を自動的に捨てることはありません。

## 別のフォルダーから実行

任意：実行ファイルのフォルダーにいる状態で、このターミナルの PATH に追加します。以後は `./overlay` や `.\overlay.exe` の代わりに `overlay` を使えます：

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

新しいターミナルでは Windows の手順 4 または Ubuntu の手順 4 を繰り返し、実行環境を復元します。先に実行ファイルのフォルダーへ戻るかフルパスを指定してください。システムの PATH は恒久的に上書きしません。

## 任意：ソースからビルド

配布バイナリを使う場合は不要です。Git と、macOS では Swift 5.9+ と Xcode コマンドラインツール、Windows/Linux では Swift 6.1.2 とその依存関係が必要です。Ubuntu のソースビルドには追加で以下を導入します：

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

最後のコマンドで実行ファイルのディレクトリを確認し、そこで `./overlay` または `.\overlay.exe` を実行します。これはソースビルド用で、ダウンロードしたバイナリには不要です。

## トラブルシューティング

| 問題 | 対処 |
| --- | --- |
| `overlay` が見つからない | 実行ファイルのフォルダーで `./overlay` / `.\overlay.exe` を使うか、PATH の設定を繰り返します。 |
| Swift DLL / `.so` が見つからない | Swift 6.1.2 を使い、ランタイムの手順と独自のインストール先を確認します。 |
| Cairo/Pango や FFmpeg が見つからない | 上記の MSYS2 UCRT64 または Ubuntu パッケージをすべて導入し、`ffmpeg` と `ffprobe` を確認します。 |
| チェックサムが一致しない | 中止し、アーカイブと対応するチェックサムを再ダウンロードしてください。そのアーカイブは実行しません。 |
| 展開先が既に存在する | 新しいフォルダーを使い、既存のインストールやファイルを上書きしないでください。 |
| 既存の出力が拒否される | 新しいファイル名か `--force` を使います。入力ファイルは保護されます。 |
| Windows/Linux で HEVC Alpha が拒否される | 透明出力には `--codec prores-4444` を使います。 |
| アーキテクチャや Linux 環境が異なる | 上の表にある配布対象を使ってください。他の環境はこの手順の対象外です。 |
| `winget` | Microsoft の [App Installer](https://learn.microsoft.com/windows/package-manager/winget/) を導入するか、Visual Studio Installer で C++/SDK を手動導入します。 |

再配布時は [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) と [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md) を含めてください。Swift、FFmpeg、Cairo/Pango、フォントは別途導入し、それぞれのライセンスが適用されます。
