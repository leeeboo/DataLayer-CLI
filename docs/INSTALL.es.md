# Instalar DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · **Español** · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Volver al README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md)

Elige tu sistema y sigue sus pasos en orden. No pegues comandos de MSYS2 ni de Bash en PowerShell.

## Descarga primero

Descarga el archivo de tu plataforma **y su archivo `.sha256`** desde [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Guarda ambos en una carpeta nueva y vacía sin cambiar sus nombres.

| Sistema | Final del nombre del archivo |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Los comandos usan **v0.1.0**. Sus binarios para Windows/Linux requieren **Swift 6.1.2**. Para otra versión, usa sus nombres y requisitos correspondientes. Otras arquitecturas y distribuciones Linux no son destinos de los binarios publicados.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Instalar Swift 6.1.2

Para una instalación nueva de Swift, ejecuta esto en **PowerShell** para instalar las herramientas C++ x64 y el SDK de Windows. Si ya están instalados, comprueba esos componentes en Visual Studio Installer. Consulta los [requisitos oficiales](https://www.swift.org/install/windows/manual/).

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

Ejecuta el [instalador oficial de Swift 6.1.2 x86_64](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe), termina la instalación y **cierra y vuelve a abrir PowerShell**. Este comando debe mostrar `6.1.2`:

```powershell
swift --version
```

### 2. Instalar las dependencias multimedia y gráficas

Instala [MSYS2](https://www.msys2.org/), abre **MSYS2 UCRT64** y actualiza:

```sh
pacman -Syu
```

Si te pide cerrar la terminal, ciérrala, vuelve a abrir **UCRT64** y repite la actualización. Cuando termine, instala:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. Verificar y extraer

Vuelve a **PowerShell** y ábrelo en la carpeta con el ZIP descargado y su suma de comprobación. Copia este bloque; al terminar entra en la carpeta del ejecutable:

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

### 4. Ejecutar la CLI

En la misma ventana de PowerShell, pega este bloque. Las dos primeras variables usan las rutas predeterminadas de Swift/MSYS2; cámbialas si instalaste en otra ubicación. PATH solo cambia para esta terminal:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. Instalar dependencias

Usa una terminal **Bash de Ubuntu 24.04 x86_64** y ejecuta:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Instalar Swift 6.1.2

Se usa [Swiftly](https://www.swift.org/install/linux/swiftly/) sin instalar antes la última versión de Swift. Si ya tienes Swiftly, ejecuta solo los tres últimos comandos. `+6.1.2` selecciona la cadena de herramientas para ese comando:

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

### 3. Verificar y extraer

En Bash, entra en la carpeta con los archivos `.tar.gz` y `.sha256` descargados. Verifica y extrae; el último comando entra en la carpeta del ejecutable:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. Ejecutar la CLI

En la misma terminal, pega este bloque. Localiza automáticamente las bibliotecas de Swift 6.1.2:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

No requiere otro entorno de ejecución. El ejecutable está firmado y notarizado. En Terminal, abre la carpeta del ZIP y la suma de comprobación y ejecuta:

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

## Prueba una exportación

Pon un archivo de actividad FIT/GPX en la carpeta del ejecutable. Sustituye `activity.fit` por su nombre real y conserva la extensión correcta. Usa un nombre de salida nuevo:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 admite transparencia en las tres plataformas; las superposiciones transparentes no tienen audio. Windows/Linux no admiten HEVC Alpha y nunca descartan la transparencia automáticamente.

## Ejecutar desde otra carpeta

Opcional: estando en la carpeta del ejecutable, añádela al PATH de esta terminal. Después puedes usar `overlay` en lugar de `./overlay` o `.\overlay.exe`:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

En una terminal nueva, repite el paso 4 de Windows o Ubuntu para recuperar el entorno. Vuelve primero a la carpeta del ejecutable o usa su ruta completa. Estos comandos no reemplazan permanentemente el PATH del sistema.

## Opcional: compilar desde el código fuente

Si usas los binarios, omite esta sección. Necesitas Git y Swift 5.9+ con las herramientas de Xcode en macOS, o Swift 6.1.2 con sus requisitos en Windows/Linux. Para compilar en Ubuntu también necesitas:

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

El último comando muestra la carpeta del ejecutable. Allí usa `./overlay` o `.\overlay.exe`. Estos pasos son solo para compilar; no son necesarios para los binarios descargados.

## Solución de problemas

| Problema | Qué hacer |
| --- | --- |
| No se encuentra `overlay` | Usa `./overlay` / `.\overlay.exe` en su carpeta o repite el paso de PATH. |
| Falta una DLL de Swift o `.so` | Usa Swift 6.1.2 y repite el paso del entorno; comprueba las rutas personalizadas. |
| Falta Cairo/Pango o FFmpeg | Instala todos los paquetes UCRT64 o Ubuntu indicados y comprueba `ffmpeg` y `ffprobe`. |
| La suma no coincide | Detente. Descarga de nuevo el archivo y su suma correspondiente; no lo ejecutes. |
| La carpeta de destino ya existe | Usa una carpeta nueva; no sobrescribas instalaciones ni archivos propios. |
| Se rechaza una salida existente | Usa otro nombre o `--force`; los archivos de entrada siguen protegidos. |
| Se rechaza HEVC Alpha en Windows/Linux | Usa `--codec prores-4444` para conservar la transparencia. |
| Arquitectura o distribución Linux incorrecta | Usa un destino de la tabla anterior; otros no están cubiertos por estos pasos. |
| `winget` | Instala [App Installer de Microsoft](https://learn.microsoft.com/windows/package-manager/winget/) o añade los componentes C++/SDK con Visual Studio Installer. |

Al redistribuir, conserva [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) y [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md). Swift, FFmpeg, Cairo/Pango y las fuentes se instalan por separado y mantienen sus licencias.
