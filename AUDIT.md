# DataLayer-CLI copyright and distribution audit

Audit date: 2026-10-24. Baseline: DataLayer-Studio commit
`5e9772f1e30a3463d94d03a24f74d82146a314d9`.

## Scope and authorization

The project owner explicitly authorized a standalone public DataLayer-CLI
repository under MIT, including its required shared core. The GUI retains
its existing license. The audited source and distribution file set is maintained in `audit/files.json` in
DataLayer-CLI. `ORIGIN.json` preserves the initial import revision and hashes;
current source identity is the CLI Git commit. No private Git history is exported.

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
  user activity, video, FIT/GPX file, or user GUI project is distributed. The shared
  export fixture is an original synthetic project; its media is generated in CI.
- Explicit allowlisting, path/symlink validation, credential-pattern checks,
  and per-file hashes protect the exported tree. The GUI's license remains
  unchanged except for the explicit MIT exception for the selected paths;
  app bundles also carry the MIT notice for the shared core.

## Ongoing checks and limits

New files require an audit/files.json update and renewed provenance review.
New dependencies or copied/adapted code require compatible notices before publication.
Public CLI/core contributions are MIT; other upstream contributions retain
the existing GUI/project terms. Project names and logos have separate rights.

This is a repository-history, source-header, dependency, and distribution-tree
audit. Git authorship alone cannot prove all possible off-repository provenance;
the report does not certify patent rights or ownership of unrecorded material.

## Single-Core maintenance

As of 2026-10-24, DataLayer-CLI owns OverlayCore and its tests. DataLayer
Studio removes its duplicate Core and consumes the `OverlayCore` Swift package
product from the `Packages/DataLayer-CLI` Git submodule, including its native
macOS Xcode project and the iOS package graph. The gitlink pins an exact CLI
commit. Core files retain their original contents during this dependency change.
The initial import metadata was renamed from SOURCE.json to ORIGIN.json to
avoid treating historical hashes as current source identity.

Core changes are made and tested in DataLayer-CLI, then the GUI repository
updates its submodule revision after integration validation. CI checks out
the locked Core revision and runs the standalone CLI/Core suite and GUI tests.
No export or source-copy synchronization is required. The CLI package's source
boundary checks protect the audited file set, credential and UI import boundaries.
Release packages generate SOURCE.json from the current CLI Git commit.
Publish source only after both repositories' required CI and real-path
acceptance pass. macOS binary releases additionally require signing and notarization.
Only the CLI and shared Core are published under MIT; the GUI repository
remains private under its existing license.

## Windows/Linux backend review

The new C ABI adapter and Swift platform adapters are original project code.
They implement only the graphics operations used by the existing shared renderer;
no Cairo, Pango, FFmpeg, font or other vendor implementation/binary is copied.
Portable platform dependencies are runtime shared libraries or separate processes.
Their individual licenses remain applicable when separately distributing them.
Apple implementations remain behind their platform conditions; the component
renderer, models, telemetry, project format and fractional timing are maintained
once. Native Apple tests remain enabled on macOS, and shared/portable tests run
on Linux and Windows. Cross-platform release remains gated on all three CI jobs,
Apple GUI/iOS integration and same-project real-export acceptance.

The owner accepted Apple/portable font and rendering differences provided the GUI
keeps its existing behavior. Acceptance therefore requires identical fixture inputs,
saved settings, timing, audible audio and real Alpha on every platform, plus strict
picture/Alpha parity between Windows and Linux. Apple/portable visual differences
remain visible in the comparison report and release notes, rather than being called
pixel-identical. No GUI font replacement, migration mode or schema change is included.

Starting with v0.1.1, portable binary archives include the native executable and a
separate runtime directory containing Swift, Cairo/Pango, FFmpeg, DejaVu fonts and
their dependency closure. Each dependency keeps its upstream license. The archive
retains package notices, dependency versions and hashes; matching distribution
source packages and build recipes are published beside the executable archives.
The original MIT Core is not linked against GPL FFmpeg libraries: FFmpeg remains
a separate executable, and Cairo/Pango libraries remain dynamic and replaceable.
CI verifies checksums, removes compiler/runtime installation paths, relocates the
package into a Unicode path and exports the shared fixture. Linux additionally
runs in a fresh Ubuntu container without the media/graphics or Swift runtimes
installed. macOS retains its existing signing/notarization requirements.
