# DataLayer-CLI

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.ar.md) · **हिन्दी**

FIT/GPX गतिविधि डेटा से पारदर्शी टेलीमेट्री ओवरले या तैयार वीडियो बनाएं। टर्मिनल से DataLayer Studio के `.dlsproj` प्रोजेक्ट भी एक्सपोर्ट करें। कमांड का नाम `overlay` है।

## इंस्टॉल करें

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) से अपने प्लेटफ़ॉर्म का आर्काइव और उसकी `.sha256` फ़ाइल डाउनलोड करें। चेकसम सत्यापित करने के बाद आर्काइव खोलें।

| सिस्टम | आर्काइव नाम का अंतिम भाग |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

macOS बाइनरी हस्ताक्षरित है और Apple से नोटराइज़ की गई है। अलग रनटाइम इंस्टॉल करने की आवश्यकता नहीं है।

Windows/Linux पर **Swift 6.1.2**, FFmpeg, Cairo/Pango और DejaVu फ़ॉन्ट अलग से इंस्टॉल करने होंगे। [इंस्टॉलेशन गाइड](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md)

एक्ज़ीक्यूटेबल का फ़ोल्डर `PATH` में जोड़ें। ऐसा न करने पर नीचे दिए गए `overlay` की जगह macOS/Linux में `./overlay` या Windows PowerShell में `.\overlay.exe` लिखें।

```sh
overlay --help
```

## शुरुआत करें

गतिविधि डेटा से पारदर्शी ओवरले बनाएं:

```sh
overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

मूल ऑडियो बनाए रखते हुए वीडियो में टेलीमेट्री जोड़ें:

```sh
overlay --fit "activity.gpx" --video "video.mov" --export-mode video --codec h264 --output "finished.mov"
```

GUI में सहेजे गए प्रोजेक्ट को उसकी एक्सपोर्ट सेटिंग के साथ एक्सपोर्ट करें:

```sh
overlay --timeline-project "project.dlsproj" --output "result.mov"
```

## उपयोगी विकल्प

- `--sync-video 12 --sync-fit 45` (FIT/GPX): वीडियो के 12वें सेकंड को गतिविधि के 45वें सेकंड से मिलाएं।
- `--width 1920 --height 1080 --fps 30`: आउटपुट का आकार और फ़्रेम दर तय करें; चौड़ाई और ऊंचाई 2 से 16384 के बीच सम संख्याएं होनी चाहिए।
- `--layout-preset "layout.json"`: FIT/GPX इनपुट के साथ एक्सपोर्ट किया गया लेआउट JSON इस्तेमाल करें।
- `--force`: मौजूदा आउटपुट फ़ाइलें बदलें; इनपुट फ़ाइलें हमेशा सुरक्षित रहती हैं।

बिटरेट, इकाइयों, समय क्षेत्र, ट्रिमिंग और `--inspect` (रेंडर किए बिना मेटाडेटा देखने) के लिए `overlay --help` देखें।

## कोडेक

- **H.264 / HEVC** (`h264`, `hevc`): मूल ऑडियो के साथ तैयार वीडियो।
- **ProRes 4444** (`prores-4444`): तीनों प्लेटफ़ॉर्म पर पारदर्शी ओवरले।
- **HEVC Alpha** (`hevc-alpha`): केवल उन macOS सिस्टम पर जहां सिस्टम और एन्कोडर इसका समर्थन करते हैं। Windows/Linux इसे अस्वीकार करते हैं; अपारदर्शी फ़ॉर्मैट में अपने आप नहीं बदलते।

पारदर्शी ओवरले में ऑडियो ट्रैक नहीं होता।

## ध्यान दें

- प्रोजेक्ट की सहेजी हुई एक्सपोर्ट सेटिंग बहाल होती हैं। स्पष्ट रूप से दिए गए CLI विकल्प संबंधित सेटिंग बदलते हैं।
- प्रोजेक्ट को दूसरी जगह ले जाते समय मीडिया फ़ोल्डरों की सापेक्ष संरचना बनाए रखें। Apple बुकमार्क पर macOS की फ़ाइल एक्सेस अनुमतियां लागू रहती हैं।
- सहेजा गया मौसम डेटा प्रोजेक्ट कैश से बहाल होता है; CLI नया मौसम डेटा नहीं लाती।
- Windows/Linux सॉफ़्टवेयर एन्कोडिंग और वैकल्पिक फ़ॉन्ट इस्तेमाल करते हैं। टेक्स्ट, छायाएं, एंटी-अलायसिंग और Alpha किनारे macOS से अलग हो सकते हैं।

## बिल्ड और योगदान

[सोर्स से बिल्ड करें](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.hi.md) · [डेवलपमेंट गाइड (अंग्रेज़ी)](https://github.com/leeeboo/DataLayer-CLI/blob/main/CONTRIBUTING.md)

MIT लाइसेंस: [LICENSE](LICENSE) और तृतीय-पक्ष सूचनाओं के लिए [NOTICE.md](NOTICE.md) देखें।

macOS/iOS ऐप और CLI एक ही Core साझा करते हैं। GUI का रखरखाव अलग होता है और उसका मौजूदा लाइसेंस बना रहता है।
