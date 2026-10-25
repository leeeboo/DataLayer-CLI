# Installer DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · **Français** · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Retour au README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md)

Choisissez votre système et suivez ses étapes dans l’ordre. Ne collez pas de commandes MSYS2 ou Bash dans PowerShell.

## Télécharger d’abord

Téléchargez l’archive adaptée **et son fichier `.sha256`** depuis [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Placez-les dans un nouveau dossier vide sans modifier leurs noms.

| Système | Fin du nom de l’archive |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Les commandes utilisent **v0.1.0**. Ses binaires Windows/Linux nécessitent **Swift 6.1.2**. Pour une autre version, utilisez ses noms de fichiers et prérequis. Les autres architectures et distributions Linux ne sont pas des cibles de distribution binaire.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Installer Swift 6.1.2

Pour une nouvelle installation de Swift, exécutez ceci dans **PowerShell** afin d’installer les outils C++ x64 et le SDK Windows. S’ils sont déjà installés, vérifiez ces composants dans Visual Studio Installer. Voir les [prérequis officiels](https://www.swift.org/install/windows/manual/).

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

Exécutez l’[installateur officiel Swift 6.1.2 x86_64](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe), terminez l’installation, puis **fermez et rouvrez PowerShell**. Cette commande doit afficher `6.1.2` :

```powershell
swift --version
```

### 2. Installer les dépendances multimédias et graphiques

Installez [MSYS2](https://www.msys2.org/), ouvrez **MSYS2 UCRT64**, puis mettez-le à jour :

```sh
pacman -Syu
```

Si la fermeture du terminal est demandée, fermez-le, rouvrez **UCRT64** et répétez la mise à jour. Une fois terminée, installez :

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. Vérifier et extraire

Revenez à **PowerShell**, ouvert dans le dossier du ZIP et de sa somme de contrôle. Copiez ce bloc : après extraction, il ouvre le dossier de l’exécutable :

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

### 4. Exécuter la CLI

Collez ceci dans la même fenêtre PowerShell. Les deux premières variables sont les chemins par défaut de Swift/MSYS2 ; adaptez-les si nécessaire. PATH ne change que pour ce terminal :

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. Installer les dépendances

Dans un terminal **Bash d’Ubuntu 24.04 x86_64**, exécutez :

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Installer Swift 6.1.2

Cette méthode utilise [Swiftly](https://www.swift.org/install/linux/swiftly/) sans installer d’abord le dernier Swift. Si Swiftly est déjà installé, seules les trois dernières commandes sont nécessaires. `+6.1.2` sélectionne la chaîne d’outils pour cette commande :

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

### 3. Vérifier et extraire

Dans Bash, ouvrez le dossier des fichiers `.tar.gz` et `.sha256` téléchargés. Vérifiez puis extrayez ; la dernière commande ouvre le dossier de l’exécutable :

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. Exécuter la CLI

Collez ce bloc dans le même terminal. Il trouve automatiquement les bibliothèques Swift 6.1.2 :

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Aucun environnement d’exécution supplémentaire n’est requis. L’exécutable est signé et notarié. Dans Terminal, ouvrez le dossier du ZIP et de sa somme de contrôle, puis exécutez :

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

## Essayer une exportation

Placez un fichier d’activité FIT/GPX dans le dossier de l’exécutable. Remplacez `activity.fit` par son vrai nom, avec la bonne extension. Choisissez un nouveau nom de sortie :

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 conserve la transparence sur les trois plateformes ; les incrustations transparentes n’ont pas de son. Windows/Linux ne prennent pas en charge HEVC Alpha et ne suppriment jamais automatiquement la transparence.

## Exécuter depuis un autre dossier

Facultatif : depuis le dossier de l’exécutable, ajoutez-le au PATH de ce terminal. Vous pouvez ensuite utiliser `overlay` au lieu de `./overlay` ou `.\overlay.exe` :

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

Dans un nouveau terminal, répétez l’étape 4 de Windows ou d’Ubuntu pour restaurer l’environnement. Revenez d’abord au dossier de l’exécutable ou utilisez son chemin complet. Ces commandes ne remplacent pas définitivement le PATH système.

## Facultatif : compiler depuis les sources

Ignorez cette section si vous utilisez les binaires. Il faut Git et Swift 5.9+ avec les outils en ligne de commande Xcode sur macOS, ou Swift 6.1.2 et ses prérequis sur Windows/Linux. La compilation sur Ubuntu nécessite aussi :

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

La dernière commande affiche le dossier de l’exécutable. Exécutez-y `./overlay` ou `.\overlay.exe`. Ces étapes de compilation ne sont pas nécessaires pour les binaires téléchargés.

## Dépannage

| Problème | Solution |
| --- | --- |
| `overlay` est introuvable | Utilisez `./overlay` / `.\overlay.exe` dans son dossier ou refaites la configuration PATH. |
| DLL Swift ou `.so` manquant | Utilisez Swift 6.1.2 et refaites l’étape d’environnement ; vérifiez les chemins personnalisés. |
| Cairo/Pango ou FFmpeg manquant | Installez tous les paquets UCRT64 ou Ubuntu indiqués et vérifiez `ffmpeg` et `ffprobe`. |
| Somme de contrôle incorrecte | Arrêtez-vous. Retéléchargez l’archive et sa somme correspondante ; ne l’exécutez pas. |
| Le dossier cible existe déjà | Choisissez un dossier neuf ; n’écrasez pas votre installation ni vos fichiers. |
| Une sortie existante est refusée | Choisissez un nouveau nom ou `--force` ; les entrées restent protégées. |
| HEVC Alpha est refusé sous Windows/Linux | Utilisez `--codec prores-4444` pour la transparence. |
| Architecture ou distribution Linux incorrecte | Utilisez une cible du tableau ci-dessus ; les autres ne sont pas couvertes ici. |
| `winget` | Installez [App Installer de Microsoft](https://learn.microsoft.com/windows/package-manager/winget/) ou ajoutez C++/SDK via Visual Studio Installer. |

Pour redistribuer, conservez [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) et [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md). Swift, FFmpeg, Cairo/Pango et les polices sont installés séparément et gardent leurs licences.
