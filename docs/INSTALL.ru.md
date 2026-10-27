# Установка DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · **Русский** · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Вернуться к README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md)

Скачайте архив для своей системы и одноимённый файл `.sha256` из [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Выбирайте пакет платформы, а не «Source code» или «dependency-sources».

| Система | Архив |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.2-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.2-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.2-Linux-x86_64.tar.gz` |

Начиная с **v0.1.1**, архивы Windows/Linux включают Swift, FFmpeg, Cairo/Pango и шрифты DejaVu. **Устанавливать компилятор или среду выполнения не нужно.**

Сохраняйте всю распакованную папку. Запускайте `overlay` в её корне; не переносите отдельно исполняемый файл из `runtime/bin`.

## Windows / PowerShell

Проверка, распаковка и запуск

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

Проверка, распаковка и запуск

```sh
cli_directory="DataLayer-CLI-v0.1.2-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Проверка, распаковка и запуск

```sh
cli_directory="DataLayer-CLI-v0.1.2-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

Создайте прозрачный слой из распакованной папки. Замените имена своими файлами; существующие результаты защищены от перезаписи.

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

Сборка из исходников необязательна. Разработчикам нужны Swift и мультимедийные и графические библиотеки; см. [CONTRIBUTING](../CONTRIBUTING.md).

Если отсутствует DLL или библиотека, распакуйте архив целиком ещё раз. Бинарный файл Windows не подписан; файл macOS подписан и нотариально проверен Apple. Бинарный пакет Linux предназначен для Ubuntu 24.04 x86_64.

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## Язык справки

`-h` и `--help` поддерживают 12 языков документации. По умолчанию используется язык системы или терминала, иначе английский. Укажите `--language CODE` (или `--language=CODE`) до или после `--help` для выбора. Журналы выполнения и краткие сообщения об ошибках остаются на английском.

`overlay --language ru --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
