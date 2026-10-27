# Installer DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · **Français** · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Retour au README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md)

Téléchargez l’archive de votre système et son fichier `.sha256` dans [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Choisissez l’archive de la plateforme, pas « Source code » ni « dependency-sources ».

| Système | Archive |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.2-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.2-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.2-Linux-x86_64.tar.gz` |

À partir de **v0.1.1**, les archives Windows/Linux incluent Swift, FFmpeg, Cairo/Pango et les polices DejaVu. **Aucun compilateur ni environnement d’exécution à installer.**

Conservez le dossier extrait complet. Lancez `overlay` à la racine du dossier ; ne déplacez pas uniquement l’exécutable de `runtime/bin`.

## Windows / PowerShell

Vérifier, extraire et lancer

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

Vérifier, extraire et lancer

```sh
cli_directory="DataLayer-CLI-v0.1.2-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Vérifier, extraire et lancer

```sh
cli_directory="DataLayer-CLI-v0.1.2-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

Créez une surcouche transparente depuis le dossier extrait. Remplacez les noms par vos fichiers ; les sorties existantes sont protégées.

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

La compilation depuis les sources est facultative. Les développeurs doivent installer Swift et les bibliothèques multimédias et graphiques ; voir [CONTRIBUTING](../CONTRIBUTING.md).

Si une DLL ou bibliothèque manque, extrayez à nouveau toute l’archive. Le binaire Windows n’est pas signé ; celui de macOS est signé et notarié. Le binaire Linux cible Ubuntu 24.04 x86_64.

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## Langue de l’aide

`-h` et `--help` prennent en charge les 12 langues de la documentation. L’aide suit la langue du système ou terminal, avec repli sur l’anglais. Utilisez `--language CODE` (ou `--language=CODE`) avant ou après `--help` pour la choisir. Les journaux et résumés d’erreur restent en anglais.

macOS / Linux: `./overlay --language fr --help`

Windows / PowerShell: `.\overlay.exe --language fr --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
