# Установка DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · **Русский** · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Вернуться к README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md)

Выберите свою систему и выполняйте шаги по порядку. Не вставляйте команды MSYS2 или Bash в PowerShell.

## Сначала скачайте файлы

Скачайте архив для своей платформы **и соответствующий файл `.sha256`** из [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Поместите оба в новую пустую папку, не меняя имён.

| Система | Окончание имени архива |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Команды рассчитаны на **v0.1.0**. Её двоичные файлы Windows/Linux требуют **Swift 6.1.2**. Для другого выпуска используйте соответствующие имена и требования. Другие архитектуры и дистрибутивы Linux не являются целями двоичных выпусков.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Установите Swift 6.1.2

При новой установке Swift выполните эту команду в **PowerShell**, чтобы установить инструменты C++ x64 и Windows SDK. Если они уже установлены, проверьте компоненты в Visual Studio Installer. См. [официальные требования](https://www.swift.org/install/windows/manual/).

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

Запустите [официальный установщик Swift 6.1.2 x86_64](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe), завершите установку, затем **закройте и снова откройте PowerShell**. Команда должна показать `6.1.2`:

```powershell
swift --version
```

### 2. Установите зависимости для медиа и графики

Установите [MSYS2](https://www.msys2.org/), откройте терминал **MSYS2 UCRT64** и обновите его:

```sh
pacman -Syu
```

Если потребуется закрыть терминал, закройте его, снова откройте **UCRT64** и повторите обновление. После завершения установите:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. Проверьте и распакуйте

Вернитесь в **PowerShell** и откройте его в папке со скачанным ZIP и контрольной суммой. Вставьте блок: после распаковки он перейдёт в папку программы:

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

### 4. Запустите CLI

В том же окне PowerShell вставьте блок ниже. Первые две переменные задают стандартные пути Swift/MSYS2; измените их при нестандартной установке. PATH изменяется только в этом терминале:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. Установите зависимости

В терминале **Bash на Ubuntu 24.04 x86_64** выполните:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Установите Swift 6.1.2

Используется [Swiftly](https://www.swift.org/install/linux/swiftly/) без предварительной установки новейшего Swift. Если Swiftly уже установлен, выполните только последние три команды. `+6.1.2` выбирает набор инструментов для этой команды:

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

### 3. Проверьте и распакуйте

В Bash перейдите в папку со скачанными `.tar.gz` и `.sha256`. Проверьте и распакуйте архив; последняя команда перейдёт в папку программы:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. Запустите CLI

Вставьте блок в том же терминале. Он автоматически найдёт библиотеки Swift 6.1.2:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Дополнительная среда выполнения не нужна. Программа подписана и нотариально заверена Apple. В Терминале откройте папку с ZIP и контрольной суммой и выполните:

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

## Попробуйте экспорт

Поместите файл тренировки FIT/GPX в папку программы. Замените `activity.fit` его настоящим именем с правильным расширением. Выберите новое имя выходного файла:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 поддерживает прозрачность на всех трёх платформах; прозрачные слои не содержат звука. Windows/Linux не поддерживают HEVC Alpha и не отбрасывают прозрачность автоматически.

## Запуск из другой папки

Необязательно: находясь в папке программы, добавьте её в PATH текущего терминала. Затем можно использовать `overlay` вместо `./overlay` или `.\overlay.exe`:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

В новом терминале повторите шаг 4 для Windows или Ubuntu, чтобы восстановить окружение. Сначала вернитесь в папку программы или используйте полный путь. Эти команды не заменяют системный PATH навсегда.

## Необязательно: сборка из исходников

Пользователям готовых файлов этот раздел не нужен. Требуются Git и Swift 5.9+ с инструментами командной строки Xcode на macOS либо Swift 6.1.2 с его зависимостями на Windows/Linux. Для сборки на Ubuntu дополнительно нужны:

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

Последняя команда выводит папку программы. Запускайте в ней `./overlay` или `.\overlay.exe`. Эти шаги сборки не нужны для скачанных двоичных файлов.

## Решение проблем

| Проблема | Что делать |
| --- | --- |
| `overlay` не найден | Используйте `./overlay` / `.\overlay.exe` в папке программы или повторите настройку PATH. |
| Отсутствует DLL Swift или `.so` | Используйте Swift 6.1.2, повторите настройку среды и проверьте нестандартные пути установки. |
| Отсутствует Cairo/Pango или FFmpeg | Установите все указанные пакеты UCRT64 или Ubuntu и проверьте `ffmpeg` и `ffprobe`. |
| Контрольная сумма не совпадает | Остановитесь. Скачайте архив и соответствующую сумму повторно; не запускайте этот архив. |
| Папка назначения уже существует | Используйте новую папку; не перезаписывайте установленную программу и свои файлы. |
| Существующий выходной файл отклонён | Выберите новое имя или `--force`; входные файлы защищены. |
| HEVC Alpha отклоняется на Windows/Linux | Для прозрачности используйте `--codec prores-4444`. |
| Другая архитектура или дистрибутив Linux | Используйте цель из таблицы выше; остальные не покрываются этими шагами. |
| `winget` | Установите Microsoft [App Installer](https://learn.microsoft.com/windows/package-manager/winget/) или добавьте C++/SDK через Visual Studio Installer. |

При распространении сохраняйте [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) и [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md). Swift, FFmpeg, Cairo/Pango и шрифты устанавливаются отдельно и сохраняют свои лицензии.
