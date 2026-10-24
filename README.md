# DataLayer-CLI

MIT-licensed telemetry graphics and video export.

Windows/Linux support is being validated on the `codex/cross-platform-cli` branch;
no cross-platform release is published until its complete CI and media acceptance pass.
The stable macOS backend continues to require **macOS 13+ on Apple Silicon**.
Render FIT/GPX activities as transparent overlays or composite them with video.
Open DataLayer Studio `.dlsproj` projects with the same renderer, cached weather,
media-path recovery, export settings, layouts, and fractional frame-rate timing.

The command remains `overlay`, preserving existing scripts. This repository
contains the CLI and the single shared Core implementation used by the macOS
and iOS apps. The DataLayer Studio GUI repository remains private under its
existing separate license.

## Install

Build from source using Xcode command-line tools with Swift 5.9 or later:

```sh
git clone https://github.com/leeeboo/DataLayer-CLI.git
cd DataLayer-CLI
swift build -c release --product overlay
.build/release/overlay --help
```

Place the built `overlay` in a directory on your `PATH`. Keep the included
LICENSE and NOTICE when redistributing the package.

No third-party Swift packages are required. macOS/iOS retain their existing Apple
system-framework backend. The Windows/Linux backend uses the same Core renderer,
layout, telemetry, project schema, cache and frame-timing logic, with Cairo/Pango
for drawing and FFmpeg/ffprobe as separate media processes. It currently uses
software encoding. Install the official Swift toolchain and these runtime dependencies:

- Ubuntu: `ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core`.
- Windows: native UCRT64 Cairo, Pango, FFmpeg and DejaVu fonts from MSYS2; add
  the UCRT64 `bin` directory to `PATH`. The CLI itself runs as a native Windows executable.

Portable codecs are H.264, HEVC and ProRes 4444 with Alpha. Explicit HEVC Alpha
requests fail before writing any output. Activity-only portable exports default
to ProRes 4444; Apple platforms retain their HEVC Alpha default. Codec, bit rate,
weather, trim, layout and relative asset paths saved in projects are preserved.
Apple security-scoped bookmarks are Apple-only; moved projects resolve their
relative media paths on Windows/Linux.

Apple font selections use explicit DejaVu substitutes on Windows/Linux. This
keeps portable platforms reproducible; Apple and portable glyph rasterization
can differ and is part of the media acceptance comparison. No Apple font files
are copied or distributed. Existing macOS/iOS font selection and rendering remain
unchanged. Available Apple codecs depend on the hardware/OS; unavailable Alpha
codecs always fail without silently changing the codec.

## Use

```sh
# Export a GUI project, inheriting saved output settings.
overlay --timeline-project /path/to/project.dlsproj --output /path/to/result.mov

# Export a transparent intermediate from an activity.
overlay --fit /path/to/activity.fit --codec prores-4444 --output /path/to/overlay.mov

# Composite telemetry onto footage, retaining its audio.
overlay --fit /path/to/activity.gpx --video /path/to/video.mov \
  --export-mode video --codec hevc --output /path/to/finished.mov

# Generate synthetic telemetry, without using personal activity data.
python3 examples/make_sample.py /tmp/datalayer-sample.gpx
overlay --fit /tmp/datalayer-sample.gpx --codec prores-4444 \
  --output /tmp/datalayer-overlay.mov
```

Supported codecs: `h264`, `hevc` (composited video); `hevc-alpha`, `prores-4444`
(transparent overlays). Transparent overlays do not include an audio track.
Use `--help` for alignment, activity trimming, layout, units, time zones, and
inspection options. Project weather caches are restored locally; the CLI does
not fetch new weather or initialize Sentry.

Existing outputs require `--force`; input files are always protected from
overwrite. Place moved projects and their media in the same relative layout
to recover paths. Bookmarks remain subject to macOS file-access permissions.
Video durations are rounded to complete frames at the selected frame rate.

## Development

```sh
git config core.hooksPath .githooks
swift build -c release --product overlay
swift test
```

Tests synthesize media at runtime; do not commit personal videos, activities,
project files, credentials, or build output. Hardware-specific encoder tests
may skip on machines without that encoder; actual hardware validation remains
necessary before releasing Alpha export changes.

Core changes and their regression tests are maintained in this repository.
DataLayer Studio consumes the `OverlayCore` Swift package product through a
Git submodule pinned to a tested commit; it does not keep a second Core copy.
The package supports macOS 13+ and iOS 26+ for Core. The released CLI is macOS-only;
this development branch adds native Windows and Linux CLI backends.

CI generates one synthetic moved project and shares its exact media/project bytes
across macOS, Windows and Linux. It exports H.264, HEVC and ProRes 4444, checks every
frame timestamp, saved settings, audio duration and Alpha, then compares decoded
picture, Alpha and audible PCM. Visual differences remain a failing release gate.

`ORIGIN.json` preserves the initial import revision and hashes as historical
provenance; current source identity is the Git commit. See [AUDIT.md](AUDIT.md)
for scope and provenance, and [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md)
for licensing. Run `python3 -B scripts/test_source_boundary.py` before committing.

Maintainers package a clean, tested commit with
`DEVELOPER_ID_APPLICATION="your existing identity" scripts/package_release.sh vX.Y.Z`.
This requires configured Developer ID signing and `asc` public-API notarization
credentials. It verifies the signature, requires Apple's Accepted result, and
verifies the online notarization ticket before producing a SHA-256 checksum. Raw command executables
use online notarization tickets; they cannot carry a stapled app-bundle ticket.
