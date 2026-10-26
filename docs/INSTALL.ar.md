# تثبيت DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · **العربية** · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[العودة إلى README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md)

نزّل حزمة نظامك وملف `.sha256` المطابق من [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). اختر حزمة المنصة، وليس “Source code” أو “dependency-sources”.

| النظام | الحزمة |
| --- | --- |
| macOS 13+ / Apple Silicon | `DataLayer-CLI-v0.1.1-macOS-arm64.zip` |
| Windows 10 1903+ / Windows 11 / x86_64 | `DataLayer-CLI-v0.1.1-Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `DataLayer-CLI-v0.1.1-Linux-x86_64.tar.gz` |

بدءًا من **v0.1.1**، تتضمن حزم Windows/Linux مكتبات Swift وFFmpeg وCairo/Pango وخطوط DejaVu. **لا تحتاج إلى تثبيت مترجم أو بيئة تشغيل.**

احتفظ بالمجلد المستخرج كاملًا. شغّل `overlay` الموجود في جذر المجلد؛ لا تنقل الملف التنفيذي وحده من `runtime/bin`.

## Windows / PowerShell

التحقق والاستخراج والتشغيل

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

التحقق والاستخراج والتشغيل

```sh
cli_directory="DataLayer-CLI-v0.1.1-Linux-x86_64"
sha256sum -c "$cli_directory.tar.gz.sha256" &&
tar -xzf "$cli_directory.tar.gz" &&
cd "$cli_directory" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

التحقق والاستخراج والتشغيل

```sh
cli_directory="DataLayer-CLI-v0.1.1-macOS-arm64"
shasum -a 256 -c "$cli_directory.zip.sha256" &&
unzip "$cli_directory.zip" &&
cd "$cli_directory" &&
./overlay --help
```

---

أنشئ طبقة شفافة من داخل المجلد المستخرج. استبدل أسماء الملفات بملفاتك؛ تُحمى المخرجات الموجودة من الاستبدال.

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
./overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --codec prores-4444 --output "custom.mov"
```

البناء من المصدر اختياري. يحتاج المطورون إلى Swift ومكتبات الوسائط والرسومات؛ راجع [CONTRIBUTING](../CONTRIBUTING.md).

إذا فقدت مكتبة DLL أو مكتبة أخرى، فاستخرج الحزمة كاملة مرة أخرى. ملف Windows غير موقّع؛ ملف macOS موقّع وموثّق لدى Apple. تستهدف حزمة Linux نظام Ubuntu 24.04 x86_64.

[LICENSE](../LICENSE) · [NOTICE](../NOTICE.md) · `runtime/licenses` · `runtime/DEPENDENCIES.json`
