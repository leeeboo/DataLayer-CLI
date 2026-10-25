# DataLayer-CLI installieren

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · **Deutsch** · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Zurück zur README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md)

Wähle dein System und führe die Schritte der Reihe nach aus. Füge keine MSYS2- oder Bash-Befehle in PowerShell ein.

## Zuerst herunterladen

Lade das passende Archiv **und seine `.sha256`-Datei** von [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) herunter. Lege beide unverändert in einen neuen, leeren Ordner.

| System | Ende des Archivnamens |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Die Befehle verwenden **v0.1.0**. Die Windows-/Linux-Binärdateien benötigen **Swift 6.1.2**. Nutze bei anderen Releases die zugehörigen Dateinamen und Voraussetzungen. Andere Architekturen und Linux-Distributionen sind keine Ziele der Binärveröffentlichung.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Swift 6.1.2 installieren

Installiere bei einer neuen Swift-Einrichtung mit diesem Befehl in **PowerShell** die x64-C++-Buildtools und das Windows SDK. Prüfe bei vorhandener Installation diese Komponenten im Visual Studio Installer. Siehe die [offiziellen Voraussetzungen](https://www.swift.org/install/windows/manual/).

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

Führe den [offiziellen Swift-6.1.2-x86_64-Installer](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe) aus und **schließe PowerShell danach und öffne es neu**. Dieser Befehl muss `6.1.2` anzeigen:

```powershell
swift --version
```

### 2. Medien- und Grafikabhängigkeiten installieren

Installiere [MSYS2](https://www.msys2.org/), öffne **MSYS2 UCRT64** und aktualisiere es:

```sh
pacman -Syu
```

Falls du das Terminal schließen sollst, schließe es, öffne **UCRT64** erneut und wiederhole die Aktualisierung. Installiere danach:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. Prüfen und entpacken

Öffne wieder **PowerShell** im Ordner mit der ZIP-Datei und ihrer Prüfsumme. Dieser Block entpackt das Archiv und wechselt in den Programmordner:

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

### 4. CLI ausführen

Füge dies in dasselbe PowerShell-Fenster ein. Die ersten beiden Variablen enthalten die Standardpfade von Swift/MSYS2; passe sie bei anderer Installation an. PATH wird nur für dieses Terminal geändert:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. Abhängigkeiten installieren

Führe dies in einem **Bash-Terminal unter Ubuntu 24.04 x86_64** aus:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Swift 6.1.2 installieren

Hier wird [Swiftly](https://www.swift.org/install/linux/swiftly/) verwendet, ohne vorher das neueste Swift zu installieren. Ist Swiftly vorhanden, genügen die letzten drei Befehle. `+6.1.2` wählt die Toolchain für diesen Befehl:

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

### 3. Prüfen und entpacken

Wechsle in Bash in den Ordner mit den heruntergeladenen `.tar.gz`- und `.sha256`-Dateien. Nach Prüfung und Entpacken wechselt der letzte Befehl in den Programmordner:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. CLI ausführen

Kopiere diesen Block in dasselbe Terminal. Er findet die Swift-6.1.2-Bibliotheken automatisch:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Eine zusätzliche Laufzeitumgebung ist nicht nötig. Das Programm ist signiert und notarisiert. Öffne im Terminal den Ordner mit ZIP und Prüfsumme und führe Folgendes aus:

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

## Einen Export ausprobieren

Lege eine FIT-/GPX-Aktivitätsdatei in den Programmordner. Ersetze `activity.fit` durch ihren tatsächlichen Namen mit korrekter Erweiterung. Verwende einen neuen Ausgabenamen:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 unterstützt Transparenz auf allen drei Plattformen; transparente Overlays haben keine Tonspur. Windows/Linux unterstützen HEVC Alpha nicht und verwerfen Transparenz niemals automatisch.

## Aus einem anderen Ordner ausführen

Optional: Füge den aktuellen Programmordner zum PATH dieses Terminals hinzu. Danach kannst du `overlay` statt `./overlay` oder `.\overlay.exe` verwenden:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

Wiederhole in einem neuen Terminal Windows-Schritt 4 oder Ubuntu-Schritt 4 für die Laufzeitumgebung. Wechsle zuerst in den Programmordner oder verwende den vollständigen Pfad. Diese Befehle überschreiben den System-PATH nicht dauerhaft.

## Optional: aus dem Quellcode bauen

Bei Verwendung der Binärdateien ist dies nicht nötig. Du brauchst Git sowie Swift 5.9+ mit Xcode-Kommandozeilenwerkzeugen unter macOS oder Swift 6.1.2 samt Voraussetzungen unter Windows/Linux. Ubuntu-Quellcode-Builds benötigen zusätzlich:

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

Der letzte Befehl zeigt den Programmordner an. Führe dort `./overlay` oder `.\overlay.exe` aus. Diese Buildschritte sind für heruntergeladene Binärdateien nicht erforderlich.

## Fehlerbehebung

| Problem | Lösung |
| --- | --- |
| `overlay` wird nicht gefunden | Verwende `./overlay` / `.\overlay.exe` im Programmordner oder wiederhole den PATH-Schritt. |
| Swift-DLL oder `.so` fehlt | Verwende Swift 6.1.2, wiederhole den Laufzeitschritt und prüfe angepasste Installationspfade. |
| Cairo/Pango oder FFmpeg fehlt | Installiere alle genannten UCRT64- oder Ubuntu-Pakete und prüfe `ffmpeg` und `ffprobe`. |
| Prüfsumme stimmt nicht | Abbrechen. Lade Archiv und passende Prüfsumme erneut herunter; führe es nicht aus. |
| Zielordner existiert bereits | Verwende einen neuen Ordner; überschreibe keine bestehende Installation oder eigene Dateien. |
| Vorhandene Ausgabe wird abgelehnt | Wähle einen neuen Dateinamen oder `--force`; Eingaben bleiben geschützt. |
| HEVC Alpha wird unter Windows/Linux abgelehnt | Nutze `--codec prores-4444` für Transparenz. |
| Falsche Architektur oder Linux-Distribution | Nutze eines der oben aufgeführten Binärziele; andere werden hier nicht abgedeckt. |
| `winget` | Installiere Microsoft [App Installer](https://learn.microsoft.com/windows/package-manager/winget/) oder ergänze C++/SDK im Visual Studio Installer. |

Bewahre bei Weitergabe [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) und [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md) auf. Swift, FFmpeg, Cairo/Pango und Schriften werden separat installiert und behalten ihre eigenen Lizenzen.
