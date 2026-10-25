# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · **Русский** · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

Создавайте прозрачные слои телеметрии или готовые видео из тренировок FIT/GPX. Экспортируйте проекты DataLayer Studio `.dlsproj` из терминала. Команда называется `overlay`.

**[Открыть редактор расположения индикаторов](https://leeeboo.github.io/DataLayer-CLI/?lang=en)** — Создавайте, импортируйте и редактируйте макеты в браузере, затем скачайте JSON для `--layout-preset`. Файлы обрабатываются только в браузере.

## Установка

Скачайте архив для своей платформы и файл `.sha256` из [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest), проверьте контрольную сумму и распакуйте архив.

| Система | Окончание имени архива |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Файл для macOS подписан и нотариально заверен Apple. Дополнительная среда выполнения не нужна.

Для Windows/Linux отдельно установите **Swift 6.1.2**, FFmpeg, Cairo/Pango и шрифты DejaVu. [Инструкция по установке](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md)

Добавьте папку с исполняемым файлом в `PATH`. Иначе заменяйте `overlay` в примерах на `./overlay` в macOS/Linux или `.\overlay.exe` в Windows PowerShell.

```sh
overlay --help
```

## Быстрый старт

Создать прозрачный слой из данных тренировки:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

Наложить телеметрию на видео, сохранив исходный звук:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

Экспортировать сохранённый в GUI проект с его настройками экспорта:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## Полезные параметры

- `--sync-video 12 --sync-fit 45` (FIT/GPX): совместить 12-ю секунду видео с 45-й секундой тренировки.
- `--width 1920 --height 1080 --fps 30`: задать размер и частоту кадров; ширина и высота должны быть чётными числами от 2 до 16384.
- `--layout-preset "layout.json"`: применить экспортированный JSON макета к входным данным FIT/GPX.
- `--force`: заменить существующие выходные файлы; входные файлы всегда защищены.

Параметры битрейта, единиц, часового пояса, обрезки и `--inspect` (метаданные без рендеринга) описаны в `overlay --help`.

## Кодеки

- **H.264 / HEVC** (`h264`, `hevc`): готовое видео с исходным звуком.
- **ProRes 4444** (`prores-4444`): прозрачные слои на всех трёх платформах.
- **HEVC Alpha** (`hevc-alpha`): только в macOS при поддержке системой и кодировщиком. Windows/Linux возвращают ошибку без перехода к непрозрачному формату.

Прозрачные слои не содержат звуковой дорожки.

## Важно знать

- Проекты восстанавливают сохранённые настройки экспорта. Явно заданные параметры CLI заменяют соответствующие настройки.
- При переносе проекта сохраняйте относительную структуру папок с медиафайлами. Закладки Apple по-прежнему зависят от разрешений macOS на доступ к файлам.
- Сохранённая погода восстанавливается из кеша проекта; CLI не загружает новые данные о погоде.
- Windows/Linux используют программное кодирование и замену шрифтов. Текст, тени, сглаживание и края Alpha могут отличаться от macOS.

## Сборка и участие в разработке

[Сборка из исходников](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [Руководство разработчика (английский)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

Лицензия MIT: см. [LICENSE](LICENSE) и уведомления о сторонних компонентах в [NOTICE.md](NOTICE.md).

Приложения macOS/iOS и CLI используют единый Core. GUI разрабатывается отдельно и сохраняет прежнюю лицензию.
