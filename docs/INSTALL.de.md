# DataLayer-CLI installieren

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · **Deutsch** · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Zurück zur README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md)

Lade das Archiv für dein System und die gleichnamige `.sha256`-Datei unter [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) herunter. Wähle das Plattformpaket, nicht „Source code“ oder „dependency-sources“.

| System | Archiv |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.2-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.2-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.2-Linux-x86_64.tar.gz` |

Ab **v0.1.1** enthalten die Windows/Linux-Archive Swift, FFmpeg, Cairo/Pango und DejaVu-Schriften. **Compiler und Laufzeitumgebungen müssen nicht installiert werden.**

Behalte den gesamten entpackten Ordner. Starte `overlay` im obersten Verzeichnis und verschiebe nicht nur die Datei aus `runtime/bin`.

## Windows / PowerShell

Prüfen, entpacken und starten

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

Prüfen, entpacken und starten

```sh
cli_directory="DataLayer-CLI-v0.1.2-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Prüfen, entpacken und starten

```sh
cli_directory="DataLayer-CLI-v0.1.2-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

Erstelle im entpackten Ordner ein transparentes Overlay. Ersetze die Dateinamen durch deine Dateien. Vorhandene Ausgaben bleiben geschützt.

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

Das Bauen aus dem Quellcode ist optional. Entwickler benötigen Swift sowie Medien- und Grafikbibliotheken; siehe [CONTRIBUTING](../CONTRIBUTING.md).

Fehlt eine DLL oder Bibliothek, entpacke das komplette Archiv erneut. Die Windows-Datei ist nicht signiert; die macOS-Datei ist signiert und notarisiert. Das Linux-Binärpaket unterstützt Ubuntu 24.04 x86_64.

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## Hilfesprache

`-h` und `--help` unterstützen die 12 Dokumentationssprachen. Die Hilfe folgt der System- oder Terminalsprache, ersatzweise Englisch. Mit `--language CODE` (oder `--language=CODE`) vor oder nach `--help` wird die Sprache festgelegt. Laufzeitprotokolle und Fehlerzusammenfassungen bleiben Englisch.

macOS / Linux: `./overlay --language de --help`

Windows / PowerShell: `.\overlay.exe --language de --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
