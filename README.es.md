# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · **Español** · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

Convierte actividades FIT/GPX en superposiciones de telemetría transparentes o vídeos terminados. Exporta proyectos `.dlsproj` de DataLayer Studio desde la terminal. El comando es `overlay`.

**[Abrir el editor de diseños de indicadores](https://leeeboo.github.io/DataLayer-CLI/?lang=es)** — Crea, importa y edita diseños en el navegador; descarga el plantilla de diseño `.dlspreset` para usarlo con `--layout-preset`. Los archivos se procesan solo en tu navegador.

## Instalación

Descarga el archivo de tu plataforma y su suma `.sha256` desde [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest), verifica la suma y descomprime el archivo.

| Sistema | Final del nombre del archivo |
| --- | --- |
| macOS 13+ / Apple Silicon | [macOS-arm64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-macOS-arm64.zip) |
| Windows / x86_64 | [Windows-x86_64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-Windows-x86_64.zip) |
| Ubuntu 24.04 / x86_64 | [Linux-x86_64.tar.gz](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-Linux-x86_64.tar.gz) |

El ejecutable para macOS está firmado y notarizado. No necesita un entorno de ejecución adicional.

Desde **v0.1.1**, los archivos de Windows/Linux incluyen Swift, FFmpeg, Cairo/Pango y fuentes DejaVu. **No hace falta instalar compiladores ni entornos de ejecución.** [Guía de instalación](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md)

Añade la carpeta del ejecutable a `PATH`. Si no lo haces, sustituye `overlay` por `./overlay` en macOS/Linux o por `.\overlay.exe` en Windows PowerShell.

```sh
overlay --help
```

## Inicio rápido

Crea una superposición transparente a partir de una actividad:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

Incrusta la telemetría en un vídeo y conserva su audio:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

Exporta un proyecto guardado en la GUI con sus ajustes de exportación:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## Opciones útiles

- `--sync-video 12 --sync-fit 45` (FIT/GPX): alinea el segundo 12 del vídeo con el segundo 45 de la actividad.
- `--width 1920 --height 1080 --fps 30`: define las dimensiones y la tasa de fotogramas; las dimensiones deben ser pares, entre 2 y 16384.
- `--layout-preset "layout.dlspreset"`: usa una plantilla `.dlspreset` con una entrada FIT/GPX.
- `--force`: reemplaza archivos de salida existentes; los archivos de entrada siempre están protegidos.

Consulta `overlay --help` para la tasa de bits, unidades, zonas horarias, recortes y `--inspect` (metadatos sin renderizar).

## Códecs

- **H.264 / HEVC** (`h264`, `hevc`): vídeo terminado con el audio original.
- **ProRes 4444** (`prores-4444`): superposiciones transparentes en las tres plataformas.
- **HEVC Alpha** (`hevc-alpha`): solo en macOS si el sistema y el codificador lo admiten. Windows/Linux lo rechazan sin cambiar a un formato opaco.

Las superposiciones transparentes no incluyen una pista de audio.

## Notas

- Los proyectos recuperan sus ajustes de exportación. Las opciones explícitas de la CLI sustituyen los ajustes correspondientes.
- Al mover un proyecto, conserva la estructura relativa de carpetas de sus archivos multimedia. Los marcadores de Apple siguen sujetos a los permisos de acceso de macOS.
- El tiempo guardado se recupera de la caché del proyecto; la CLI no consulta nuevos datos meteorológicos.
- Windows/Linux usan codificación por software y fuentes alternativas. El texto, las sombras, el suavizado y los bordes Alpha pueden diferir de macOS.

## Compilar y contribuir

[Compilar desde el código fuente](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Guía de desarrollo (inglés)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

Licencia MIT: consulta [LICENSE](LICENSE) y los avisos de terceros en [NOTICE.md](NOTICE.md).

Las apps de macOS/iOS y la CLI comparten un único Core. La GUI se mantiene por separado con su licencia actual.
