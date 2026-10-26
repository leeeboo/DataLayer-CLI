# DataLayer-CLI Notices

Copyright (c) 2026 Leeeboo and DataLayer Studio contributors.

The CLI and shared core in this repository are licensed under MIT. The GUI,
app artwork, store configuration, and account integrations are not included
and retain their upstream licenses. The copyright license does not grant
rights to project names, logos, or other trademarks.

This distribution has no third-party Swift package dependencies. It uses
Apple system frameworks on macOS/iOS, including AVFoundation, CoreGraphics, CoreText,
CoreImage, Metal, and VideoToolbox, supplied by the Apple operating system and not redistributed.

The Windows/Linux backend dynamically loads Cairo/Pango shared libraries and
invokes FFmpeg/ffprobe as separate processes. Starting with v0.1.1, portable release
archives include their runtime dependencies, Swift runtime and DejaVu fonts.
These components retain their own licenses, including Apache, BSD, MIT, LGPL and GPL
terms; they are not relicensed under MIT. Each archive includes runtime/licenses,
runtime/DEPENDENCIES.json and THIRD_PARTY.md. Matching package sources and build
recipes are distributed as dependency-sources assets beside the binary downloads.
Libraries remain separate and replaceable. Native runtime binaries are not committed
to this source tree. See https://www.cairographics.org/ https://www.pango.org/
https://ffmpeg.org/legal.html and https://dejavu-fonts.github.io/ for upstream terms.
The FIT/GPX parsers implement file formats; no Garmin SDK or application
source code, activity files, fonts, LUT assets, or vendor binaries are bundled.

DataLayer-CLI is an independent project, not affiliated with or endorsed by
Apple, Garmin, COROS, OpenWeather, or Telemetry Overlay. Protocol names and
product references identify interoperability only.

The Web editor includes a separate GPL-2.0-or-later x265 WebAssembly encoder.
It is not part of the native CLI or Core. Its full source, build recipe and licenses
are in web/export/encoder; see that directory's README.md and COPYING.
