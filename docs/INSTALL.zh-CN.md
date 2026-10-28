# 安装 DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · **简体中文** · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[返回 README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md)

从 [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) 下载对应系统的压缩包和同名 `.sha256` 文件。请选择平台安装包，不是“Source code”或“dependency-sources”。

| 系统 | 压缩包 |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.3-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.3-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.3-Linux-x86_64.tar.gz` |

从 **v0.1.1** 起，Windows/Linux 安装包已包含 Swift、FFmpeg、Cairo/Pango 和 DejaVu 字体，**无需安装编译器或运行库**。

请保留解压后的整个文件夹。运行顶层的 `overlay` 启动器，不要单独移动 `runtime/bin` 中的程序。

## Windows / PowerShell

校验、解压并运行

```powershell
$ErrorActionPreference = "Stop"
$cliDirectory = "DataLayer-CLI-v0.1.3-Windows-x86_64"
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

校验、解压并运行

```sh
cli_directory="DataLayer-CLI-v0.1.3-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

校验、解压并运行

```sh
cli_directory="DataLayer-CLI-v0.1.3-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

在解压目录中创建透明浮层。请将文件名替换成自己的素材；命令会保护已存在的输出。

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

从源码构建是可选项。开发者仍需安装 Swift 工具链和媒体/图形依赖，详见[开发指南](../CONTRIBUTING.md)。

如果提示缺少 DLL 或库，请重新完整解压。Windows 程序尚未签名；macOS 程序已签名并公证。Linux 二进制支持目标为 Ubuntu 24.04 x86_64。

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## 帮助语言

`-h` 和 `--help` 支持与文档相同的 12 种语言。默认跟随系统或终端语言，无法匹配时回退英文。使用 `--language CODE`（或 `--language=CODE`）手动指定，放在 `--help` 前后均可。运行日志和错误摘要仍为英文。

macOS / Linux: `./overlay --language zh-CN --help`

Windows / PowerShell: `.\overlay.exe --language zh-CN --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
