# DataLayer-CLI इंस्टॉल करें

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · **हिन्दी**

[README पर वापस जाएं](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) से अपने सिस्टम का पैकेज और उसी नाम की `.sha256` फ़ाइल डाउनलोड करें। “Source code” या “dependency-sources” के बजाय प्लेटफ़ॉर्म पैकेज चुनें।

| सिस्टम | पैकेज |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.2-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.2-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.2-Linux-x86_64.tar.gz` |

**v0.1.1** से Windows/Linux पैकेज में Swift, FFmpeg, Cairo/Pango और DejaVu फ़ॉन्ट शामिल हैं। **कंपाइलर या रनटाइम अलग से इंस्टॉल करने की ज़रूरत नहीं है।**

निकाले गए पूरे फ़ोल्डर को साथ रखें। सबसे ऊपर का `overlay` लॉन्चर चलाएं; `runtime/bin` की केवल executable फ़ाइल को अलग न करें।

## Windows / PowerShell

जांचें, निकालें और चलाएं

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

जांचें, निकालें और चलाएं

```sh
cli_directory="DataLayer-CLI-v0.1.2-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

जांचें, निकालें और चलाएं

```sh
cli_directory="DataLayer-CLI-v0.1.2-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

निकाले गए फ़ोल्डर में पारदर्शी ओवरले बनाएं। फ़ाइल नाम अपनी फ़ाइलों से बदलें; मौजूदा आउटपुट सुरक्षित रहते हैं।

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

सोर्स से बिल्ड करना वैकल्पिक है। डेवलपर को Swift और मीडिया/ग्राफ़िक्स लाइब्रेरी चाहिए; [CONTRIBUTING](../CONTRIBUTING.md) देखें।

DLL या लाइब्रेरी न मिले तो पूरा पैकेज दोबारा निकालें। Windows executable साइन नहीं है; macOS executable साइन और notarize किया गया है। Linux बाइनरी Ubuntu 24.04 x86_64 के लिए है।

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`

## सहायता की भाषा

`-h` और `--help` दस्तावेज़ों की सभी 12 भाषाओं में उपलब्ध हैं। सहायता सिस्टम या टर्मिनल की भाषा चुनती है, मेल न मिलने पर अंग्रेज़ी उपयोग होती है। `--help` के पहले या बाद में `--language CODE` (या `--language=CODE`) से भाषा चुनें। रनटाइम लॉग और त्रुटि सारांश अभी अंग्रेज़ी में हैं।

`overlay --language hi --help`

`LC_ALL` → `LC_MESSAGES` → `LANGUAGE` → `LANG` → OS. `C` / `POSIX` → English.
