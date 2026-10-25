# DataLayer-CLI इंस्टॉल करें

[English](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-CN.md) · [繁體中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.zh-TW.md) · [日本語](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ja.md) · [한국어](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ko.md) · [Español](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.es.md) · [Français](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.fr.md) · [Deutsch](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.de.md) · [Português (Brasil)](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.pt-BR.md) · [Русский](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ru.md) · [العربية](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.ar.md) · **हिन्दी**

[README पर वापस जाएं](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.hi.md)

नीचे अपना सिस्टम चुनें और उसके चरण क्रम से पूरा करें। MSYS2 या Bash के कमांड PowerShell में न चिपकाएं।

## पहले डाउनलोड करें

[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest) से सही आर्काइव **और उसकी `.sha256` फ़ाइल** डाउनलोड करें। दोनों को नए, खाली फ़ोल्डर में रखें और उनके नाम न बदलें।

| सिस्टम | आर्काइव नाम का अंतिम भाग |
| --- | --- |
| macOS 13+ / Apple Silicon | `macOS-arm64.zip` |
| Windows / x86_64 | `Windows-x86_64.zip` |
| Ubuntu 24.04 / x86_64 | `Linux-x86_64.tar.gz` |

ये कमांड **v0.1.0** के लिए हैं। उसके Windows/Linux बाइनरी को **Swift 6.1.2** चाहिए। दूसरे रिलीज़ के लिए उससे जुड़े फ़ाइल नाम और आवश्यकताएं देखें। अन्य आर्किटेक्चर और Linux वितरण बाइनरी रिलीज़ के लक्ष्य नहीं हैं।

[Windows](#windows--powershell) · [Ubuntu](#ubuntu-2404--bash--x86_64) · [macOS](#macos-13--apple-silicon)

## Windows / PowerShell

### 1. Swift 6.1.2 इंस्टॉल करें

Swift पहली बार इंस्टॉल करते समय x64 C++ बिल्ड टूल और Windows SDK के लिए **PowerShell** में यह कमांड चलाएं। यदि वे पहले से हैं, तो Visual Studio Installer में इन घटकों की जांच करें। [आधिकारिक आवश्यकताएं](https://www.swift.org/install/windows/manual/) देखें।

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --override "--wait --passive --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

[आधिकारिक Swift 6.1.2 x86_64 इंस्टॉलर](https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe) चलाकर इंस्टॉलेशन पूरा करें, फिर **PowerShell बंद करके दोबारा खोलें**। इस कमांड में `6.1.2` दिखना चाहिए:

```powershell
swift --version
```

### 2. मीडिया और ग्राफ़िक्स निर्भरताएं इंस्टॉल करें

[MSYS2](https://www.msys2.org/) इंस्टॉल करें। **MSYS2 UCRT64** टर्मिनल खोलकर अपडेट करें:

```sh
pacman -Syu
```

यदि टर्मिनल बंद करने को कहा जाए, तो उसे बंद करें, **UCRT64** दोबारा खोलें और अपडेट फिर चलाएं। पूरा होने पर ये पैकेज इंस्टॉल करें:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

### 3. सत्यापन करके आर्काइव खोलें

**PowerShell** में वापस आएं और उसे डाउनलोड किए गए ZIP और चेकसम वाले फ़ोल्डर में खोलें। यह ब्लॉक चलाएं; आर्काइव खुलने के बाद यह एक्ज़ीक्यूटेबल के फ़ोल्डर में जाएगा:

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

### 4. CLI चलाएं

उसी PowerShell विंडो में यह ब्लॉक चिपकाएं। पहले दो वेरिएबल Swift/MSYS2 की डिफ़ॉल्ट जगह बताते हैं; दूसरी जगह इंस्टॉल किया हो तो इन्हें बदलें। PATH सिर्फ इसी टर्मिनल में बदलेगा:

```powershell
$msysBin = "C:\msys64\ucrt64\bin"
$swiftRuntime = Join-Path $env:LOCALAPPDATA "Programs\Swift\Runtimes\6.1.2\usr\bin"
$env:Path = "$swiftRuntime;$msysBin;$env:Path"
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

## Ubuntu 24.04 / Bash / x86_64

### 1. निर्भरताएं इंस्टॉल करें

**Ubuntu 24.04 x86_64 का Bash** टर्मिनल इस्तेमाल करें और चलाएं:

```sh
sudo apt-get update &&
sudo apt-get install -y ca-certificates curl gnupg python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core libatomic1 libedit2 libsqlite3-0 libxml2 libz3-4 libncurses6 tzdata zlib1g
```

### 2. Swift 6.1.2 इंस्टॉल करें

यह पहले नवीनतम Swift इंस्टॉल किए बिना [Swiftly](https://www.swift.org/install/linux/swiftly/) इस्तेमाल करता है। Swiftly पहले से हो तो केवल अंतिम तीन कमांड चलाएं। `+6.1.2` उस कमांड के लिए टूलचेन चुनता है:

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

### 3. सत्यापन करके आर्काइव खोलें

Bash में डाउनलोड किए गए `.tar.gz` और `.sha256` वाले फ़ोल्डर में जाएं। सत्यापन करके आर्काइव खोलें; अंतिम कमांड एक्ज़ीक्यूटेबल के फ़ोल्डर में जाएगा:

```sh
cli_version="v0.1.0"
cli_dir="DataLayer-CLI-$cli_version-Linux-x86_64"
cli_archive="$cli_dir.tar.gz"
sha256sum -c "$cli_archive.sha256" &&
mkdir "$cli_dir" &&
tar -xzf "$cli_archive" &&
cd "$cli_dir"
```

### 4. CLI चलाएं

उसी टर्मिनल में यह ब्लॉक चिपकाएं। यह Swift 6.1.2 की लाइब्रेरी अपने आप ढूंढता है:

```sh
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" &&
swift_runtime_paths="$(swiftly run swift -print-target-info +6.1.2 | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')" &&
export LD_LIBRARY_PATH="$swift_runtime_paths${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" &&
./overlay --help
```

## macOS 13+ / Apple Silicon

अलग रनटाइम की आवश्यकता नहीं है। बाइनरी हस्ताक्षरित और Apple से नोटराइज़ है। Terminal में ZIP और चेकसम वाला फ़ोल्डर खोलकर चलाएं:

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

## एक्सपोर्ट आज़माएं

एक FIT/GPX गतिविधि फ़ाइल एक्ज़ीक्यूटेबल के फ़ोल्डर में रखें। `activity.fit` को उसके असली नाम और सही एक्सटेंशन से बदलें। आउटपुट के लिए नया नाम चुनें:

**macOS / Linux**

```sh
./overlay --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

**Windows PowerShell**

```powershell
.\overlay.exe --fit "activity.fit" --codec prores-4444 --output "overlay.mov"
```

ProRes 4444 तीनों प्लेटफ़ॉर्म पर पारदर्शिता का समर्थन करता है; पारदर्शी ओवरले में ऑडियो नहीं होता। Windows/Linux HEVC Alpha का समर्थन नहीं करते और पारदर्शिता अपने आप नहीं हटाते।

## दूसरे फ़ोल्डर से चलाएं

वैकल्पिक: एक्ज़ीक्यूटेबल के फ़ोल्डर में रहते हुए उसे इस टर्मिनल के PATH में जोड़ें। इसके बाद `./overlay` या `.\overlay.exe` की जगह `overlay` इस्तेमाल करें:

**Windows PowerShell**

```powershell
$env:Path = "$PWD;$env:Path"
```

**macOS / Linux Bash**

```sh
export PATH="$PWD:$PATH"
```

नए टर्मिनल में रनटाइम वातावरण बहाल करने के लिए Windows या Ubuntu का चरण 4 दोहराएं। पहले एक्ज़ीक्यूटेबल के फ़ोल्डर में जाएं या उसका पूरा पथ दें। ये कमांड सिस्टम PATH को स्थायी रूप से नहीं बदलते।

## वैकल्पिक: सोर्स से बिल्ड करें

डाउनलोड की गई बाइनरी इस्तेमाल करते हैं तो इसे छोड़ सकते हैं। Git और macOS पर Swift 5.9+/Xcode कमांड-लाइन टूल, या Windows/Linux पर Swift 6.1.2 और उसकी निर्भरताएं चाहिए। Ubuntu पर सोर्स बिल्ड के लिए ये भी चाहिए:

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

आखिरी कमांड एक्ज़ीक्यूटेबल का फ़ोल्डर दिखाता है। वहां `./overlay` या `.\overlay.exe` चलाएं। ये सोर्स बिल्ड के चरण हैं, डाउनलोड की गई बाइनरी के लिए ज़रूरी नहीं।

## समस्या निवारण

| समस्या | क्या करें |
| --- | --- |
| `overlay` नहीं मिला | उसके फ़ोल्डर में `./overlay` या `.\overlay.exe` चलाएं या PATH वाला चरण दोहराएं। |
| Swift DLL या `.so` नहीं मिली | Swift 6.1.2 इस्तेमाल करें, रनटाइम चरण दोहराएं और कस्टम इंस्टॉलेशन पथ जांचें। |
| Cairo/Pango या FFmpeg नहीं मिला | ऊपर दिए सभी UCRT64 या Ubuntu पैकेज इंस्टॉल करें और `ffmpeg` व `ffprobe` जांचें। |
| चेकसम मेल नहीं खाता | रुकें। आर्काइव और सही चेकसम दोबारा डाउनलोड करें; इसे न चलाएं। |
| लक्ष्य फ़ोल्डर पहले से मौजूद है | नया फ़ोल्डर इस्तेमाल करें; पुराने इंस्टॉलेशन या अपनी फ़ाइलों को न बदलें। |
| मौजूदा आउटपुट अस्वीकार हुआ | नया नाम या `--force` इस्तेमाल करें; इनपुट फ़ाइलें सुरक्षित रहती हैं। |
| Windows/Linux पर HEVC Alpha अस्वीकार हुआ | पारदर्शिता के लिए `--codec prores-4444` इस्तेमाल करें। |
| गलत आर्किटेक्चर या Linux वितरण | ऊपर की तालिका का समर्थित लक्ष्य चुनें; दूसरे लक्ष्य इन चरणों में शामिल नहीं हैं। |
| `winget` | Microsoft [App Installer](https://learn.microsoft.com/windows/package-manager/winget/) इंस्टॉल करें या Visual Studio Installer से C++/SDK घटक जोड़ें। |

पुनर्वितरण में [LICENSE](https://github.com/leeeboo/DataLayer-CLI/blob/main/LICENSE) और [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md) रखें। Swift, FFmpeg, Cairo/Pango और फ़ॉन्ट अलग से इंस्टॉल होते हैं और उनके अपने लाइसेंस बने रहते हैं।
