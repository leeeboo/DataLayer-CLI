#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: scripts/package_release.sh vX.Y.Z}"
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version" >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo "Build on Apple Silicon" >&2; exit 1; }
identity="${DEVELOPER_ID_APPLICATION:?Set the existing Developer ID Application identity}"
python3 -B scripts/check_source_boundary.py
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Commit source changes before packaging" >&2; exit 1; }
swift build -c release --product overlay
binary_directory="$(swift build -c release --show-bin-path)"
release_directory="$PWD/.build/releases"
mkdir -p "$release_directory"
name="DataLayer-CLI-${version}-macOS-arm64"
archive="$release_directory/$name.zip"
[[ ! -e "$archive" ]] || { echo "Release archive already exists" >&2; exit 1; }
stage="$(mktemp -d "$release_directory/staging.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/$name"
cp "$binary_directory/overlay" "$stage/$name/overlay"
cp LICENSE NOTICE.md README.md AUDIT.md ORIGIN.json "$stage/$name/"
cp README.*.md "$stage/$name/"
cp -R docs "$stage/$name/"
python3 - "$stage/$name/SOURCE.json" <<'PY'
import json, pathlib, subprocess, sys
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "repository": "https://github.com/leeeboo/DataLayer-CLI",
    "revision": revision, "working_tree_dirty": False,
}, indent=2) + "\n")
PY
codesign --force --options runtime --timestamp --sign "$identity" "$stage/$name/overlay"
codesign --verify --strict --verbose=2 "$stage/$name/overlay"
ditto -c -k --keepParent "$stage/$name" "$archive"
asc notarization submit --file "$archive" --wait --output json > "$stage/notary.json"
python3 - "$stage/notary.json" "$archive.notarization.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
record = data.get("data", data)
attributes = record.get("attributes", record)
status = attributes.get("status")
if status != "Accepted":
    raise SystemExit("Notarization not accepted: " + str(status))
receipt = {"id": record.get("id"), "status": status}
pathlib.Path(sys.argv[2]).write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt))
PY
# Raw Mach-O is not an app bundle; require its online notarization ticket.
codesign --verify --strict --verbose=4 -R="notarized" --check-notarization "$stage/$name/overlay"
(cd "$release_directory" && shasum -a 256 "$name.zip" > "$name.zip.sha256")
echo "$archive"
