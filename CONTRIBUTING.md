# Contributing

CLI and shared-core contributions are licensed under MIT. Only submit work
you have the right to contribute, and preserve third-party notices where needed.

This repository is the source of truth for OverlayCore and its tests. Submit
Core changes here. DataLayer Studio's macOS and iOS clients consume its
`OverlayCore` Swift package product through a pinned Git submodule. Update
the app repository's submodule revision only after its integration checks pass;
do not synchronize copies of the Core source files.

Review provenance and update `audit/files.json` when adding Swift files.
Run `python3 -B scripts/test_source_boundary.py` before committing.

Run `swift test` and build the release `overlay` product. Use synthetic test
data; never attach personal activities, videos, GPS traces, credentials, or
private project paths to public reports.
