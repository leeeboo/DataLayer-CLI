# Instalar o DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · **Português (Brasil)** · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Voltar ao README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md)

Escolha seu sistema e siga os passos em ordem. Não cole comandos do MSYS2 ou do Bash no PowerShell.

## Primeiro, baixe os arquivos

Baixe o arquivo da sua plataforma **e o arquivo `.sha256` correspondente** em [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Coloque ambos em uma pasta nova e vazia, sem alterar os nomes.

| Sistema | Final do nome do arquivo |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

Os comandos usam **v0.1.0**. Os binários Windows/Linux dessa versão exigem **Swift 6.1.2**. Para outra versão, use os nomes e requisitos correspondentes. Outras arquiteturas e distribuições Linux não são destinos dos binários publicados.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Instalar o Swift 6.1.2

Em uma nova instalação do Swift, execute isto no **PowerShell** para instalar as ferramentas C++ x64 e o SDK do Windows. Se já estiverem instalados, confira esses componentes no Visual Studio Installer. Veja os [pré-requisitos oficiais](https://www.swift.org/install/windows/manual/).

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

Execute o [instalador oficial do Swift 6.1.2 x86_64](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe), conclua a instalação e **feche e reabra o PowerShell**. Este comando deve mostrar `6.1.2`:

```powershell
swift --version
```

### 2. Instalar as dependências de mídia e gráficos

Instale o [MSYS2](https://www.msys2.org/), abra o terminal **MSYS2 UCRT64** e atualize:

```sh
pacman -Syu
```

Se for solicitado fechar o terminal, feche-o, reabra o **UCRT64** e repita a atualização. Ao terminar, instale:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. Verificar e extrair

Volte ao **PowerShell** e abra-o na pasta do ZIP baixado e da soma de verificação. Copie este bloco; após a extração, ele entra na pasta do executável:

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

### 4. Executar a CLI

Cole este bloco na mesma janela do PowerShell. As duas primeiras variáveis usam os locais padrão do Swift/MSYS2; ajuste-as se instalou em outro lugar. O PATH muda apenas neste terminal:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. Instalar dependências

Use um terminal **Bash do Ubuntu 24.04 x86_64** e execute:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Instalar o Swift 6.1.2

Este método usa o [Swiftly](https://www.swift.org/install/linux/swiftly/) sem instalar antes o Swift mais recente. Se já tiver Swiftly, execute apenas os três últimos comandos. `+6.1.2` seleciona a cadeia de ferramentas para esse comando:

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

### 3. Verificar e extrair

No Bash, entre na pasta dos arquivos `.tar.gz` e `.sha256` baixados. Verifique e extraia; o último comando entra na pasta do executável:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. Executar a CLI

Na mesma janela, cole este bloco. Ele localiza automaticamente as bibliotecas do Swift 6.1.2:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Não é necessário outro runtime. O executável é assinado e notarizado. No Terminal, abra a pasta do ZIP e da soma de verificação e execute:

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

## Testar uma exportação

Coloque um arquivo de atividade FIT/GPX na pasta do executável. Substitua `activity.fit` pelo nome real, mantendo a extensão correta. Use um nome de saída novo:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 oferece transparência nas três plataformas; sobreposições transparentes não têm áudio. Windows/Linux não oferecem HEVC Alpha e nunca removem a transparência automaticamente.

## Executar de outra pasta

Opcional: ainda na pasta do executável, adicione-a ao PATH deste terminal. Depois, use `overlay` em vez de `./overlay` ou `.\overlay.exe`:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

Em um novo terminal, repita o passo 4 do Windows ou Ubuntu para restaurar o ambiente. Primeiro volte à pasta do executável ou use o caminho completo. Esses comandos não substituem permanentemente o PATH do sistema.

## Opcional: compilar a partir do código-fonte

Quem usa os binários pode pular esta seção. É necessário Git e Swift 5.9+ com as ferramentas de linha de comando do Xcode no macOS, ou Swift 6.1.2 com os pré-requisitos no Windows/Linux. A compilação no Ubuntu também exige:

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

O último comando mostra a pasta do executável. Nela, use `./overlay` ou `.\overlay.exe`. Esses passos de compilação não são necessários para os binários baixados.

## Solução de problemas

| Problema | O que fazer |
| --- | --- |
| `overlay` não foi encontrado | Use `./overlay` / `.\overlay.exe` na pasta dele ou repita o passo do PATH. |
| DLL do Swift ou `.so` ausente | Use o Swift 6.1.2 e repita a etapa do runtime; confira caminhos personalizados. |
| Cairo/Pango ou FFmpeg ausente | Instale todos os pacotes UCRT64 ou Ubuntu indicados e confirme `ffmpeg` e `ffprobe`. |
| A soma de verificação não confere | Pare. Baixe novamente o arquivo e a soma correspondente; não o execute. |
| A pasta de destino já existe | Use uma pasta nova; não sobrescreva instalações nem arquivos próprios. |
| Uma saída existente foi recusada | Use um novo nome ou `--force`; os arquivos de entrada continuam protegidos. |
| HEVC Alpha é recusado no Windows/Linux | Use `--codec prores-4444` para manter a transparência. |
| Arquitetura ou distribuição Linux incorreta | Use um destino da tabela acima; os outros não são cobertos por estes passos. |
| `winget` | Instale o [App Installer da Microsoft](https://learn.microsoft.com/windows/package-manager/winget/) ou adicione C++/SDK pelo Visual Studio Installer. |

Ao redistribuir, mantenha [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) e [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md). Swift, FFmpeg, Cairo/Pango e fontes são instalados separadamente e mantêm as próprias licenças.
