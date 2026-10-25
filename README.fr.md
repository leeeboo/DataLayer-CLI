# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · **Français** · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

Transformez des activités FIT/GPX en incrustations de télémétrie transparentes ou en vidéos finales. Exportez des projets DataLayer Studio `.dlsproj` depuis le terminal. La commande est `overlay`.

## Installation

Téléchargez l’archive de votre plateforme et son fichier `.sha256` depuis [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest), vérifiez la somme de contrôle, puis décompressez.

| Système | Fin du nom de l’archive |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Le binaire macOS est signé et notarié. Aucun environnement d’exécution supplémentaire n’est nécessaire.

Windows/Linux nécessitent **Swift 6.1.2**, FFmpeg, Cairo/Pango et les polices DejaVu, installés séparément. [Guide d’installation (anglais)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md)

Ajoutez le dossier de l’exécutable au `PATH`. Sinon, remplacez `overlay` ci-dessous par `./overlay` sur macOS/Linux ou `.\overlay.exe` dans Windows PowerShell.

```sh
overlay --help
```

## Démarrage rapide

Créer une incrustation transparente à partir d’une activité :

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

Incruster les données dans une vidéo en conservant son audio :

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

Exporter un projet enregistré dans la GUI avec ses paramètres d’exportation :

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## Options utiles

- `--sync-video 12 --sync-fit 45` (FIT/GPX): aligne la seconde 12 de la vidéo sur la seconde 45 de l’activité.
- `--width 1920 --height 1080 --fps 30`: définit les dimensions et la fréquence d’images ; les dimensions doivent être paires, de 2 à 16384.
- `--layout-preset "layout.json"`: utilise un fichier JSON de mise en page exporté avec une entrée FIT/GPX.
- `--force`: remplace les sorties existantes ; les fichiers d’entrée sont toujours protégés.

Consultez `overlay --help` pour le débit, les unités, les fuseaux horaires, le découpage et `--inspect` (métadonnées sans rendu).

## Codecs

- **H.264 / HEVC** (`h264`, `hevc`): vidéo finale avec l’audio d’origine.
- **ProRes 4444** (`prores-4444`): incrustations transparentes sur les trois plateformes.
- **HEVC Alpha** (`hevc-alpha`): uniquement sur macOS si le système et l’encodeur le permettent. Windows/Linux le refusent sans basculer vers un format opaque.

Les incrustations transparentes ne contiennent pas de piste audio.

## À savoir

- Les projets restaurent leurs paramètres d’exportation. Les options CLI explicites remplacent les paramètres correspondants.
- Lors du déplacement d’un projet, conservez l’arborescence relative de ses médias. Les signets Apple restent soumis aux autorisations d’accès aux fichiers de macOS.
- La météo enregistrée est restaurée depuis le cache du projet ; la CLI ne récupère pas de nouvelles données météo.
- Windows/Linux utilisent un encodage logiciel et des polices de substitution. Le texte, les ombres, l’anticrénelage et les contours Alpha peuvent différer de macOS.

## Compiler et contribuer

[Compiler depuis les sources (anglais)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [Guide de développement (anglais)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

Licence MIT : voir [LICENSE](LICENSE) et les mentions tierces dans [NOTICE.md](NOTICE.md).

Les apps macOS/iOS et la CLI partagent un seul Core. La GUI est maintenue séparément sous sa licence actuelle.
