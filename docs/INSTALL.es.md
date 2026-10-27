# Instalar DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · **Español** · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Volver al README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md)

Descarga el archivo de tu sistema y su `.sha256` desde [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Elige el paquete de plataforma, no “Source code” ni “dependency-sources”.

| Sistema | Archivo |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.2-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.2-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.2-Linux-x86_64.tar.gz` |

Desde **v0.1.1**, los archivos de Windows/Linux incluyen Swift, FFmpeg, Cairo/Pango y fuentes DejaVu. **No hace falta instalar compiladores ni entornos de ejecución.**

Conserva toda la carpeta extraída. Ejecuta el lanzador `overlay` de la carpeta principal; no muevas solo el ejecutable de `runtime/bin`.

## Windows / PowerShell

Verificar, extraer y ejecutar

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

Verificar, extraer y ejecutar

```sh
cli_directory="DataLayer-CLI-v0.1.2-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Verificar, extraer y ejecutar

```sh
cli_directory="DataLayer-CLI-v0.1.2-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

Crea una capa transparente desde la carpeta extraída. Sustituye los nombres por tus archivos; se protegen los resultados existentes.

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

Compilar desde el código fuente es opcional. Requiere Swift y las bibliotecas multimedia y gráficas; consulta [CONTRIBUTING](../CONTRIBUTING.md).

Si falta una DLL o biblioteca, vuelve a extraer todo el archivo. El ejecutable de Windows no está firmado; el de macOS está firmado y notarizado. El binario de Linux admite Ubuntu 24.04 x86_64.

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## Idioma de la ayuda

`-h` y `--help` admiten los 12 idiomas de la documentación. Siguen el idioma del sistema o terminal y usan inglés si no hay coincidencia. Usa `--language CODE` (o `--language=CODE`) antes o después de `--help` para elegirlo. Los registros y resúmenes de error siguen en inglés.

`overlay --language es --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
