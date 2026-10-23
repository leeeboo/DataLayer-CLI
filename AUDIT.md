# DataLayer-CLI copyright and distribution audit

Audit date: 2026-10-24. Baseline: DataLayer-Studio commit
`5e9772f1e30a3463d94d03a24f74d82146a314d9`.

## Scope and authorization

The project owner explicitly authorized a standalone public DataLayer-CLI
repository under MIT, including its required shared core. The GUI retains
its existing license. The exact current export allowlist is maintained in
`distribution/cli/files.json` upstream; each snapshot's `SOURCE.json` records
its source revision and per-file SHA-256. No upstream Git history is exported.

The audited code covers OverlayCore, the CLI, the video worker, their tests,
and the two project-persistence/export services and their tests moved from
OverlayStudioKit into OverlayCore. Only the module imports change during
that move; rendering, parsing, path resolution, weather merging, project
schema, and export validation behavior are preserved.

## Provenance findings

- Git history for every selected pre-existing source/test path attributes
  the commits to Albert, the maintainer identity associated with Leeeboo.
  Selected history contains AI-tool coauthor trailers, but no additional
  human contribution author was found. Copyright notices retain Leeeboo and
  DataLayer Studio contributors; the owner authorized the MIT grant.
- No selected Swift file carries a conflicting third-party copyright or
  license header. Imports and package dependencies were reviewed: the CLI
  distribution uses Apple system frameworks and has no third-party Swift
  package dependencies. Those frameworks are provided by macOS, not bundled.
- FIT/GPX parsing code is the repository's Swift implementation. No Garmin
  SDK, python-garminconnect, ZIPFoundation, vendor binaries, or protocol
  reference documents are copied into this distribution. CRC lookup values,
  format identifiers, and XML namespace identifiers are format/algorithm
  constants, not bundled SDK material.
- Sentry, account/authorization services, JianYing draft interoperability,
  SwiftUI/AppKit/UIKit UI, StoreKit, app resources, fonts, LUT assets, icons,
  screenshots, signing configuration, and personal media are excluded.
- Tests generate synthetic telemetry and media in temporary directories;
  the sample generator writes synthetic coordinates near 0,0. No recorded
  user activity, video, FIT/GPX file, or GUI project is distributed.
- Explicit allowlisting, path/symlink validation, credential-pattern checks,
  and per-file hashes protect the exported tree. The GUI's license remains
  unchanged except for the explicit MIT exception for the selected paths;
  app bundles also carry the MIT notice for the shared core.

## Ongoing checks and limits

New files require an allowlist update and renewed provenance review. New
dependencies or copied/adapted code require compatible notices before export.
Public CLI/core contributions are MIT; other upstream contributions retain
the existing GUI/project terms. Project names and logos have separate rights.

This is a repository-history, source-header, dependency, and distribution-tree
audit. Git authorship alone cannot prove all possible off-repository provenance;
the report does not certify patent rights or ownership of unrecorded material.

## Maintainer synchronization

Run `python3 scripts/export_cli_repository.py /path/to/new/cli-snapshot` from
the upstream repository. The destination must not exist. Review the exported
file hashes and require `SOURCE.json` to report a clean working tree. The
upstream CI builds and tests this standalone package as well as the complete
GUI app. Publish a snapshot only after that upstream revision's entire CI is
successful; publish release assets only after the standalone repository's CI
and signing/notarization checks are successful. Updates flow upstream to the
CLI repository; do not maintain a second implementation in the snapshot.
