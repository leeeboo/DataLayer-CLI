# Instalar o DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · **Português (Brasil)** · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[Voltar ao README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md)

Baixe o arquivo do seu sistema e o `.sha256` correspondente em [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). Escolha o pacote da plataforma, não “Source code” nem “dependency-sources”.

| Sistema | Arquivo |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.1-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.1-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.1-Linux-x86_64.tar.gz` |

A partir da **v0.1.1**, os arquivos Windows/Linux incluem Swift, FFmpeg, Cairo/Pango e fontes DejaVu. **Não é necessário instalar compilador ou ambiente de execução.**

Mantenha toda a pasta extraída. Use o inicializador `overlay` na raiz; não mova apenas o executável de `runtime/bin`.

## Windows / PowerShell

Verificar, extrair e executar

```powershell
$ErrorActionPreference = "Stop"
$cliDirectory = "DataLayer-CLI-v0.1.1-Windows-x86_64"
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

Verificar, extrair e executar

```sh
cli_directory="DataLayer-CLI-v0.1.1-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

Verificar, extrair e executar

```sh
cli_directory="DataLayer-CLI-v0.1.1-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

Crie uma sobreposição transparente na pasta extraída. Substitua os nomes pelos seus arquivos; as saídas existentes são protegidas.

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

Compilar a partir do código é opcional. Desenvolvedores ainda precisam de Swift e bibliotecas de mídia e gráficos; veja [CONTRIBUTING](../CONTRIBUTING.md).

Se faltar uma DLL ou biblioteca, extraia novamente o arquivo completo. O binário Windows não é assinado; o de macOS é assinado e notarizado. O binário Linux suporta Ubuntu 24.04 x86_64.

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`
