# DataLayer-CLI Notices

Copyright (c) 2026 Leeeboo and DataLayer Studio contributors.

The CLI and shared core in this repository are licensed under MIT. The GUI,
app artwork, store configuration, and account integrations are not included
and retain their upstream licenses. The copyright license does not grant
rights to project names, logos, or other trademarks.

This distribution has no third-party Swift package dependencies. It uses
Apple system frameworks on macOS/iOS, including AVFoundation, CoreGraphics, CoreText,
CoreImage, Metal, and VideoToolbox, supplied by the Apple operating system and not redistributed.

The Windows/Linux backend dynamically loads separately installed Cairo/Pango
shared libraries and invokes FFmpeg/ffprobe as external processes. Those projects
retain their own licenses; they are not relicensed under MIT and their binaries
are not included in this source tree. Refer to https://www.cairographics.org/
https://www.pango.org/ and https://ffmpeg.org/legal.html for their terms.
Portable text uses separately installed DejaVu fonts (https://dejavu-fonts.github.io/).
The FIT/GPX parsers implement file formats; no Garmin SDK or application
source code, activity files, fonts, LUT assets, or vendor binaries are bundled.

DataLayer-CLI is an independent project, not affiliated with or endorsed by
Apple, Garmin, COROS, OpenWeather, or Telemetry Overlay. Protocol names and
product references identify interoperability only.
