# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · **Deutsch** · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

Erstelle aus FIT/GPX-Aktivitäten transparente Telemetrie-Overlays oder fertige Videos. Exportiere DataLayer-Studio-Projekte im Format `.dlsproj` direkt im Terminal. Der Befehl heißt `overlay`.

**[Gauge-Layout-Editor öffnen](https://leeeboo.github.io/DataLayer-CLI/?lang=de)** — Layouts im Browser erstellen, importieren und bearbeiten; anschließend Layoutvorlage `.dlspreset` für `--layout-preset` herunterladen. Die Dateien bleiben in deinem Browser.

## Installation

Lade das passende Archiv und die zugehörige `.sha256`-Datei von [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) herunter, prüfe die Prüfsumme und entpacke das Archiv.

| System | Ende des Archivnamens |
| --- | --- |
| macOS 13+ / Apple Silicon | [macOS-arm64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-macOS-arm64.zip) |
| Windows 10 1903+ / Windows 11 / x86_64 | [Windows-x86_64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-Windows-x86_64.zip) |
| Ubuntu 24.04 / x86_64 | [Linux-x86_64.tar.gz](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-Linux-x86_64.tar.gz) |

Die macOS-Datei ist signiert und notarisiert. Es ist keine zusätzliche Laufzeitinstallation nötig.

Ab **v0.1.1** enthalten die Windows/Linux-Archive Swift, FFmpeg, Cairo/Pango und DejaVu-Schriften. **Compiler und Laufzeitumgebungen müssen nicht installiert werden.** [Installationsanleitung](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md)

Füge den Ordner der ausführbaren Datei zu `PATH` hinzu. Ersetze andernfalls `overlay` unten durch `./overlay` unter macOS/Linux oder `.\overlay.exe` in Windows PowerShell.

```sh
overlay --help
```

## Hilfesprache

`-h` und `--help` unterstützen die 12 Dokumentationssprachen. Die Hilfe folgt der System- oder Terminalsprache, ersatzweise Englisch. Mit `--language CODE` (oder `--language=CODE`) vor oder nach `--help` wird die Sprache festgelegt. Laufzeitprotokolle und Fehlerzusammenfassungen bleiben Englisch.

```sh
overlay --help
overlay --language de -h
```

`en, zh-CN, zh-TW, ja, ko, es, fr, de, pt-BR, ru, ar, hi`

## Schnellstart

Ein transparentes Overlay aus einer Aktivität erstellen:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

Telemetrie in ein Video einbetten und dessen Ton beibehalten:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

Ein gespeichertes GUI-Projekt mit seinen Exporteinstellungen exportieren:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## Nützliche Optionen

- `--sync-video 12 --sync-fit 45` (FIT/GPX): richtet Sekunde 12 des Videos an Sekunde 45 der Aktivität aus.
- `--width 1920 --height 1080 --fps 30`: legt Auflösung und Bildrate fest; Breite und Höhe müssen gerade Zahlen von 2 bis 16384 sein.
- `--layout-preset "layout.dlspreset"`: verwendet eine `.dlspreset`-Layoutvorlage für FIT/GPX-Daten.
- `--force`: überschreibt vorhandene Ausgabedateien; Eingabedateien bleiben geschützt.

`overlay --help` beschreibt Bitrate, Einheiten, Zeitzonen, Zuschnitt und `--inspect` (Metadaten ohne Rendering).

## Codecs

- **H.264 / HEVC** (`h264`, `hevc`): fertiges Video mit dem ursprünglichen Ton.
- **ProRes 4444** (`prores-4444`): transparente Overlays auf allen drei Plattformen.
- **HEVC Alpha** (`hevc-alpha`): nur unter macOS, wenn System und Encoder dies unterstützen. Windows/Linux lehnen es ab, statt ein undurchsichtiges Format zu verwenden.

Transparente Overlays enthalten keine Tonspur.

## Gut zu wissen

- Projekte stellen ihre gespeicherten Exporteinstellungen wieder her. Explizite CLI-Optionen überschreiben die entsprechenden Einstellungen.
- Behalte beim Verschieben eines Projekts die relativen Medienordner bei. Apple-Lesezeichen unterliegen weiterhin den macOS-Dateizugriffsrechten.
- Gespeicherte Wetterdaten werden aus dem Projektcache geladen; die CLI ruft keine neuen Wetterdaten ab.
- Windows/Linux verwenden Software-Encoding und Ersatzschriften. Text, Schatten, Kantenglättung und Alpha-Kanten können von macOS abweichen.

## Bauen und mitwirken

[Entwicklungsanleitung (Englisch)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

MIT-Lizenz: siehe [LICENSE](LICENSE) und die Hinweise zu Drittanbietern in [NOTICE.md](NOTICE.md).

macOS-/iOS-Apps und CLI teilen sich einen Core. Die GUI wird separat unter ihrer bisherigen Lizenz gepflegt.
