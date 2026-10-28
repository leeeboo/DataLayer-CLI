# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · **Português (Brasil)** · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

Transforme atividades FIT/GPX em sobreposições transparentes de telemetria ou vídeos finalizados. Exporte projetos `.dlsproj` do DataLayer Studio pelo terminal. O comando é `overlay`.

**[Abrir o editor de layouts de indicadores](https://leeeboo.github.io/DataLayer-CLI/?lang=pt-BR)** — Crie, importe e edite layouts no navegador e baixe o modelo de layout `.dlspreset` para usar com `--layout-preset`. Os arquivos ficam no seu navegador.

## Instalação

Baixe o arquivo da sua plataforma e a soma `.sha256` em [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest), verifique a soma e extraia o arquivo.

| Sistema | Final do nome do arquivo |
| --- | --- |
| macOS 13+ / Apple Silicon | [macOS-arm64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-macOS-arm64.zip) |
| Windows 10 1903+ / Windows 11 / x86_64 | [Windows-x86_64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-Windows-x86_64.zip) |
| Ubuntu 24.04 / x86_64 | [Linux-x86_64.tar.gz](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.3/DataLayer-CLI-v0.1.3-Linux-x86_64.tar.gz) |

O executável para macOS é assinado e notarizado. Não exige instalação adicional de runtime.

A partir da **v0.1.1**, os arquivos Windows/Linux incluem Swift, FFmpeg, Cairo/Pango e fontes DejaVu. **Não é necessário instalar compilador ou ambiente de execução.** [Guia de instalação](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md)

Adicione a pasta do executável ao `PATH`. Caso contrário, substitua `overlay` abaixo por `./overlay` no macOS/Linux ou `.\overlay.exe` no Windows PowerShell.

```sh
overlay --help
```

## Idioma da ajuda

`-h` e `--help` aceitam os 12 idiomas da documentação. A ajuda segue o idioma do sistema ou terminal, com inglês como alternativa. Use `--language CODE` (ou `--language=CODE`) antes ou depois de `--help` para escolher. Registros e resumos de erros continuam em inglês.

```sh
overlay --help
overlay --language pt-BR -h
```

`en, zh-CN, zh-TW, ja, ko, es, fr, de, pt-BR, ru, ar, hi`

## Início rápido

Crie uma sobreposição transparente a partir de uma atividade:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

Incorpore a telemetria ao vídeo, preservando o áudio original:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

Exporte um projeto salvo na GUI usando as configurações de exportação dele:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## Opções úteis

- `--sync-video 12 --sync-fit 45` (FIT/GPX): alinha o segundo 12 do vídeo ao segundo 45 da atividade.
- `--width 1920 --height 1080 --fps 30`: define as dimensões e a taxa de quadros; as dimensões devem ser pares, de 2 a 16384.
- `--layout-preset "layout.dlspreset"`: usa um modelo `.dlspreset` com uma entrada FIT/GPX.
- `--force`: substitui arquivos de saída existentes; os arquivos de entrada são sempre protegidos.

Consulte `overlay --help` para taxa de bits, unidades, fusos horários, cortes e `--inspect` (metadados sem renderização).

## Codecs

- **H.264 / HEVC** (`h264`, `hevc`): vídeo finalizado com o áudio original.
- **ProRes 4444** (`prores-4444`): sobreposições transparentes nas três plataformas.
- **HEVC Alpha** (`hevc-alpha`): somente no macOS, se o sistema e o codificador oferecerem suporte. Windows/Linux rejeitam a opção sem mudar para um formato opaco.

Sobreposições transparentes não incluem faixa de áudio.

## Informações importantes

- Os projetos restauram as configurações de exportação salvas. Opções explícitas da CLI substituem as configurações correspondentes.
- Ao mover um projeto, mantenha a estrutura relativa das pastas de mídia. Os marcadores da Apple continuam sujeitos às permissões de acesso a arquivos do macOS.
- Os dados meteorológicos salvos são restaurados do cache do projeto; a CLI não busca novos dados.
- Windows/Linux usam codificação por software e fontes alternativas. Texto, sombras, suavização e bordas Alpha podem diferir do macOS.

## Compilar e contribuir

[Guia de desenvolvimento (inglês)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

Licença MIT: consulte [LICENSE](LICENSE) e os avisos de terceiros em [NOTICE.md](NOTICE.md).

Os apps macOS/iOS e a CLI compartilham um único Core. A GUI é mantida separadamente com a licença atual.
