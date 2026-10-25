# Contributing

[README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [Build instructions](https://github.com/leeeboo/DataLayer-CLI/blob/main/docs/INSTALL.md)

CLI and shared-core contributions are licensed under MIT. Only submit work
you have the right to contribute, and preserve third-party notices where needed.

## Local checks

Check `git config --get core.hooksPath` first. If no hooks are configured,
enable this repository’s checks with `git config core.hooksPath .githooks`.
Preserve an existing hooks configuration until compatibility is confirmed.

```sh
python3 -B scripts/test_source_boundary.py
python3 -B scripts/test_release_checks.py
swift build -c release --product overlay
swift test
```

Tests generate their own media. Do not commit personal videos, activities,
projects, credentials or build output. Add new documentation paths to
`audit/files.json` after reviewing their contents. The pre-commit hook checks
the audited file set, credentials and Core's UI import boundary without rewriting files.
Never attach personal activities, videos, GPS traces, credentials or private
project paths to public reports.

## One shared Core

`Sources/OverlayCore/` and its tests are maintained here. The macOS/iOS GUI apps
consume the `OverlayCore` SwiftPM product through a Git submodule pinned to a
tested commit; there is no second Core copy. Core supports macOS 13+ and iOS 26+,
plus native Windows/Linux CLI backends, and must not import SwiftUI/AppKit/UIKit.

Submit Core changes here. Update the app repository's submodule revision only
after its integration checks pass; do not synchronize copies of Core source files.

There are no third-party Swift package dependencies. Apple platforms use system
frameworks. Windows/Linux use separately installed Cairo/Pango for drawing and
FFmpeg/ffprobe for media, with software encoding. Dependencies retain their own licenses.

`ORIGIN.json` records the initial import revision and historical hashes. The
current Git commit identifies the current source. See [AUDIT.md](AUDIT.md) for
provenance, [LICENSE](LICENSE) for MIT terms and [NOTICE.md](NOTICE.md) for notices.
GUI code, artwork and account integrations are not part of this MIT repository.

## Export behavior and CI

- Projects retain export mode, codec, bitrate, trims, render scope, weather cache
  and relative media paths. CLI overrides replace only the corresponding settings.
- Fractional frame rates are preserved; output duration is rounded to complete frames.
- Transparent exports never silently fall back to an opaque codec. Availability of
  Apple codecs depends on the OS/encoder. Encoder-specific tests may skip when
  hardware is missing; actual hardware validation is needed for Alpha changes.
- Windows/Linux default to ProRes 4444 for activity-only overlays; Apple platforms
  retain their HEVC Alpha default. HEVC Alpha requests fail on Windows/Linux before writing output.
- Windows/Linux use DejaVu substitutes, not redistributed Apple fonts. Text,
  shadows, antialiasing, composition and Alpha edges may differ from Apple's backend.
  No GUI font migration or project-format change is required.
- The CLI restores cached weather offline and does not initialize Sentry.

CI generates one synthetic moved project and shares its exact project/media bytes
across macOS, Windows and Linux. It exports H.264, HEVC and ProRes 4444, checks
saved settings, every frame timestamp, audio duration and transparency, and compares
decoded pictures, Alpha and audible PCM. All-platform audio and Windows/Linux
picture/Alpha parity are gates. Apple/portable visual differences remain in reports
rather than being called pixel-identical. Windows/Linux archives are unpacked and
tested using their packaged executables. Core changes also require the related GUI regressions.

## Packaging

Package binaries only from a clean, tested source revision. On macOS, use the
existing Developer ID identity and configured `asc` public-API notarization credentials:

```sh
DEVELOPER_ID_APPLICATION="your existing identity" scripts/package_release.sh vX.Y.Z
```

The script verifies the signature, requires Apple's `Accepted` notarization result,
checks the online ticket and writes a SHA-256 checksum. A raw command executable
cannot carry an app bundle's stapled ticket. Windows/Linux CI uses
`scripts/package_portable_release.py` to create native archives with the source
revision, binary hash, MIT license and notices.

Archives contain the English README and licensing/provenance records. README
language and setup links use GitHub URLs so they also work outside a source checkout.
README translations and the detailed guides are maintained in the repository.
