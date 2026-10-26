# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · **العربية** · [हिन्दी](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

حوّل بيانات الأنشطة بصيغة FIT/GPX إلى طبقات بيانات شفافة أو فيديوهات جاهزة. يمكنك أيضًا تصدير مشاريع DataLayer Studio بصيغة `.dlsproj` من الطرفية. اسم الأمر هو `overlay`.

**[فتح محرر تخطيط المؤشرات](https://leeeboo.github.io/DataLayer-CLI/?lang=ar)** — أنشئ التخطيطات واستوردها وعدّلها في المتصفح، ثم نزّل قالب التخطيط `.dlspreset` لاستخدامه مع `--layout-preset`. تبقى الملفات داخل المتصفح.

## التثبيت

نزّل الأرشيف المناسب لنظامك وملف التحقق `.sha256` من [Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest)، ثم تحقّق من البصمة وفك الضغط.

| النظام | نهاية اسم الأرشيف |
| --- | --- |
| macOS 13+ / Apple Silicon | [macOS-arm64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-macOS-arm64.zip) |
| Windows / x86_64 | [Windows-x86_64.zip](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-Windows-x86_64.zip) |
| Ubuntu 24.04 / x86_64 | [Linux-x86_64.tar.gz](https://github.com/leeeboo/DataLayer-CLI/releases/download/v0.1.1/DataLayer-CLI-v0.1.1-Linux-x86_64.tar.gz) |

الملف التنفيذي لنظام macOS موقّع وموثّق لدى Apple، ولا يحتاج إلى تثبيت بيئة تشغيل إضافية.

بدءًا من **v0.1.1**، تتضمن حزم Windows/Linux مكتبات Swift وFFmpeg وCairo/Pango وخطوط DejaVu. **لا تحتاج إلى تثبيت مترجم أو بيئة تشغيل.** [دليل التثبيت](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md)

أضف مجلد الملف التنفيذي إلى `PATH`. إن لم تفعل، استبدل `overlay` في الأمثلة بـ `./overlay` على macOS/Linux أو بـ `.\overlay.exe` في Windows PowerShell.

```sh
overlay --help
```

## البدء السريع

إنشاء طبقة شفافة من بيانات نشاط:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

دمج البيانات في فيديو مع الحفاظ على صوته الأصلي:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

تصدير مشروع محفوظ من الواجهة الرسومية باستخدام إعدادات التصدير الخاصة به:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## خيارات مفيدة

- `--sync-video 12 --sync-fit 45` (FIT/GPX): محاذاة الثانية 12 من الفيديو مع الثانية 45 من النشاط.
- `--width 1920 --height 1080 --fps 30`: تحديد الأبعاد ومعدل الإطارات؛ يجب أن يكون العرض والارتفاع عددين زوجيين بين 2 و16384.
- `--layout-preset "layout.dlspreset"`: استخدم قالب `.dlspreset` مع مدخل FIT/GPX.
- `--force`: استبدال ملفات الإخراج الموجودة؛ تظل ملفات الإدخال محمية دائمًا.

استخدم `overlay --help` لمعرفة خيارات معدل البت والوحدات والمناطق الزمنية والقص و`--inspect` (عرض البيانات الوصفية دون تصيير).

## الترميزات

- **H.264 / HEVC** (`h264`, `hevc`): فيديو جاهز يتضمن الصوت الأصلي.
- **ProRes 4444** (`prores-4444`): طبقات شفافة على الأنظمة الثلاثة.
- **HEVC Alpha** (`hevc-alpha`): متاح فقط على macOS إذا كان النظام والمُرمّز يدعمانه. يرفضه Windows/Linux دون التحويل إلى تنسيق غير شفاف.

لا تتضمن الطبقات الشفافة مسارًا صوتيًا.

## ملاحظات مهمة

- تستعيد المشاريع إعدادات التصدير المحفوظة. تتجاوز خيارات CLI المحددة صراحةً الإعدادات المقابلة.
- عند نقل المشروع، حافظ على البنية النسبية لمجلدات الوسائط. تبقى إشارات Apple المرجعية خاضعة لأذونات الوصول إلى الملفات في macOS.
- تُستعاد بيانات الطقس المحفوظة من ذاكرة المشروع المؤقتة؛ لا تجلب CLI بيانات طقس جديدة.
- يستخدم Windows/Linux الترميز البرمجي وخطوطًا بديلة. قد تختلف النصوص والظلال وتنعيم الحواف وحواف Alpha عن macOS.

## البناء والمساهمة

[البناء من المصدر](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · [دليل التطوير (بالإنجليزية)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

الترخيص MIT؛ راجع [LICENSE](LICENSE) وإشعارات الجهات الخارجية في [NOTICE.md](NOTICE.md).

تتشارك تطبيقات macOS/iOS وCLI نواة Core واحدة. تُطوَّر الواجهة الرسومية بشكل منفصل وتحتفظ بترخيصها الحالي.
