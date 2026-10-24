# DataLayer-CLI

MIT-licensed telemetry graphics and video export for **macOS 13+ on Apple Silicon**.
Render FIT/GPX activities as transparent overlays or composite them with video.
Open DataLayer Studio `.dlsproj` projects with the same renderer, cached weather,
media-path recovery, export settings, layouts, and fractional frame-rate timing.

The command remains `overlay`, preserving existing scripts. This repository
contains the CLI and shared core; the DataLayer Studio GUI retains its separate
license in the [upstream repository](https://github.com/leeeboo/DataLayer-Studio).

## Install

Download the signed macOS arm64 ZIP from
[Releases](https://github.com/leeeboo/DataLayer-CLI/releases), verify its SHA-256
against the accompanying checksum, and place `overlay` in a directory on your
`PATH`. Keep the included LICENSE and NOTICE when redistributing the package.

Or build using Xcode command-line tools with Swift 5.9 or later:

```sh
git clone https://github.com/leeeboo/DataLayer-CLI.git
cd DataLayer-CLI
swift build -c release --product overlay
.build/release/overlay --help
```

No third-party Swift packages are required. Windows and Linux are not supported;
rendering and encoding use Apple's system frameworks. Available codecs depend
on the Mac and macOS version; unavailable Alpha codecs fail without silently
changing the codec.

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
swift build -c release --product overlay
swift test
```

Tests synthesize media at runtime; do not commit personal videos, activities,
project files, credentials, or build output. Hardware-specific encoder tests
may skip on machines without that encoder; actual hardware validation remains
necessary before releasing Alpha export changes.

This is a generated distribution of one shared implementation. Submit shared
code changes to [DataLayer-Studio](https://github.com/leeeboo/DataLayer-Studio)
under its CLI/core MIT contribution terms. `SOURCE.json` records the upstream
revision and SHA-256 of every exported file. See [AUDIT.md](AUDIT.md) for scope
and provenance. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md) for licensing.

Maintainers package a clean, tested snapshot with
`DEVELOPER_ID_APPLICATION="your existing identity" scripts/package_release.sh vX.Y.Z`.
This requires configured Developer ID signing and `asc` public-API notarization
credentials. It verifies the signature, requires Apple's Accepted result, and
verifies the online notarization ticket before producing a SHA-256 checksum. Raw command executables
use online notarization tickets; they cannot carry a stapled app-bundle ticket.
