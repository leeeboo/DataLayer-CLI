# تثبيت DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · **العربية** · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

[العودة إلى README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md)

اختر نظامك واتبع خطواته بالترتيب. لا تلصق أوامر MSYS2 أو Bash في PowerShell.

## التنزيل أولًا

نزّل الأرشيف المناسب **وملف `.sha256` المقابل له** من [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). ضعهما في مجلد جديد وفارغ دون تغيير اسميهما.

| النظام | نهاية اسم الأرشيف |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

تستخدم الأوامر **v0.1.0**. تتطلب ملفاته التنفيذية على Windows/Linux إصدار **Swift 6.1.2**. للإصدارات الأخرى، استخدم أسماء الملفات والمتطلبات المقابلة. المعماريات وتوزيعات Linux الأخرى ليست أهدافًا للإصدارات الثنائية.

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. تثبيت Swift 6.1.2

لتثبيت Swift لأول مرة، شغّل الأمر التالي في **PowerShell** لتثبيت أدوات C++ x64 وWindows SDK. إن كانت مثبتة، فتحقّق من هذه المكونات في Visual Studio Installer. راجع [المتطلبات الرسمية](https://www.swift.org/install/windows/manual/).

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

شغّل [مثبّت Swift 6.1.2 x86_64 الرسمي](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe)، وأكمل التثبيت ثم **أغلق PowerShell وافتحه مجددًا**. يجب أن يعرض هذا الأمر `6.1.2`:

```powershell
swift --version
```

### 2. تثبيت مكتبات الوسائط والرسوميات

ثبّت [MSYS2](https://www.msys2.org/)، وافتح طرفية **MSYS2 UCRT64** ثم حدّثها:

```sh
pacman -Syu
```

إذا طُلب إغلاق الطرفية، فأغلقها وافتح **UCRT64** مجددًا وكرّر التحديث. بعد الانتهاء ثبّت:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. التحقق وفك الضغط

عُد إلى **PowerShell** وافتحه في المجلد الذي يحتوي على ZIP وملف بصمة التحقق. انسخ هذه الأوامر؛ ستنتقل إلى مجلد الملف التنفيذي بعد فك الضغط:

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

### 4. تشغيل CLI

الصق الأوامر في نافذة PowerShell نفسها. يستخدم المتغيران الأولان مساري Swift/MSYS2 الافتراضيين؛ عدّلهما إن اخترت مسارات أخرى. يتغير PATH لهذه الطرفية فقط:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. تثبيت المتطلبات

استخدم طرفية **Bash على Ubuntu 24.04 x86_64** وشغّل:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. تثبيت Swift 6.1.2

يستخدم هذا [Swiftly](https://www.swift.org/install/linux/swiftly/) دون تثبيت أحدث Swift أولًا. إن كان Swiftly مثبتًا، شغّل آخر ثلاثة أوامر فقط. يحدد `+6.1.2` سلسلة الأدوات لهذا الأمر:

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

### 3. التحقق وفك الضغط

في Bash، انتقل إلى مجلد ملفي `.tar.gz` و`.sha256` اللذين نزّلتهما. تحقّق ثم فك الضغط؛ سينقلك الأمر الأخير إلى مجلد الملف التنفيذي:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. تشغيل CLI

الصق هذه الأوامر في الطرفية نفسها. ستحدّد مكتبات Swift 6.1.2 تلقائيًا:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

لا تحتاج إلى بيئة تشغيل إضافية. الملف التنفيذي موقّع وموثّق لدى Apple. افتح مجلد ZIP وبصمة التحقق في Terminal ثم شغّل:

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

## جرّب التصدير

ضع ملف نشاط FIT/GPX في مجلد الملف التنفيذي. استبدل `activity.fit` باسم الملف الفعلي مع الامتداد الصحيح، واستخدم اسمًا جديدًا للإخراج:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

يدعم ProRes 4444 الشفافية على الأنظمة الثلاثة، ولا تحتوي الطبقات الشفافة على صوت. لا يدعم Windows/Linux ترميز HEVC Alpha ولا يحذفان الشفافية تلقائيًا.

## التشغيل من مجلد آخر

اختياري: من مجلد الملف التنفيذي، أضفه إلى PATH لهذه الطرفية. يمكنك بعدها استخدام `overlay` بدلًا من `./overlay` أو `.\overlay.exe`:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

في طرفية جديدة، كرّر الخطوة 4 من Windows أو Ubuntu لاستعادة بيئة التشغيل. عُد إلى مجلد الملف التنفيذي أولًا أو استخدم مساره الكامل. لا تستبدل هذه الأوامر PATH للنظام بشكل دائم.

## اختياري: البناء من المصدر

يمكن لمستخدمي الملفات التنفيذية تخطي هذا القسم. تحتاج إلى Git، وإلى Swift 5.9+ وأدوات Xcode لسطر الأوامر على macOS، أو Swift 6.1.2 ومتطلباته على Windows/Linux. يتطلب البناء على Ubuntu أيضًا:

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

يعرض الأمر الأخير مجلد الملف التنفيذي. شغّل فيه `./overlay` أو `.\overlay.exe`. هذه خطوات بناء من المصدر، وليست مطلوبة للملف التنفيذي الذي نزّلته.

## حل المشكلات

| المشكلة | ما يجب فعله |
| --- | --- |
| لم يتم العثور على `overlay` | استخدم `./overlay` أو `.\overlay.exe` في مجلده، أو كرّر إعداد PATH. |
| مكتبة Swift DLL أو `.so` مفقودة | استخدم Swift 6.1.2 وكرّر خطوة بيئة التشغيل، وتحقّق من مسارات التثبيت المخصصة. |
| Cairo/Pango أو FFmpeg غير موجود | ثبّت جميع حزم UCRT64 أو Ubuntu المذكورة، وتحقّق من العثور على `ffmpeg` و`ffprobe`. |
| بصمة التحقق غير متطابقة | توقف. نزّل الأرشيف وبصمته المقابلة مجددًا، ولا تشغّل هذا الأرشيف. |
| مجلد الاستخراج موجود مسبقًا | استخدم مجلدًا جديدًا ولا تكتب فوق تثبيتك أو ملفاتك الحالية. |
| رُفض ملف إخراج موجود | استخدم اسمًا جديدًا أو `--force`؛ تبقى ملفات الإدخال محمية. |
| رُفض HEVC Alpha على Windows/Linux | استخدم `--codec prores-4444` للحفاظ على الشفافية. |
| معمارية أو توزيعة Linux غير مناسبة | استخدم أحد الأهداف في الجدول أعلاه؛ لا تغطي هذه الخطوات الأهداف الأخرى. |
| `winget` | ثبّت [App Installer من Microsoft](https://learn.microsoft.com/windows/package-manager/winget/) أو أضف مكونات C++/SDK عبر Visual Studio Installer. |

عند إعادة التوزيع، احتفظ بملفي [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) و[NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md). تُثبّت Swift وFFmpeg وCairo/Pango والخطوط بشكل منفصل وتحتفظ بتراخيصها.
