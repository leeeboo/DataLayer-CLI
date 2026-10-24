#!/usr/bin/env python3
"""Package a verified native executable; runtime dependencies are installed separately."""
import argparse
import hashlib
import json
import pathlib
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def package(version, binary, output):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        raise ValueError("Expected vX.Y.Z")
    system = platform.system()
    machine = platform.machine().lower()
    if system not in ("Linux", "Windows") or machine not in ("amd64", "x86_64"):
        raise ValueError("Portable release binaries currently target Windows/Linux x86_64")
    binary, output = pathlib.Path(binary).resolve(), pathlib.Path(output).resolve()
    if not binary.is_file():
        raise ValueError("Missing native executable")
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT).strip():
        raise ValueError("Commit source changes before packaging")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    name = f"DataLayer-CLI-{version}-{system}-x86_64"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / (name + (".zip" if system == "Windows" else ".tar.gz"))
    if archive.exists() or archive.with_suffix(archive.suffix + ".sha256").exists():
        raise FileExistsError(archive)
    with tempfile.TemporaryDirectory(prefix="staging.", dir=output) as temporary:
        stage = pathlib.Path(temporary) / name
        stage.mkdir()
        executable = stage / ("overlay.exe" if system == "Windows" else "overlay")
        shutil.copy2(binary, executable)
        for document in ["LICENSE", "NOTICE.md", "README.md", "AUDIT.md", "ORIGIN.json"]:
            shutil.copy2(ROOT / document, stage / document)
        (stage / "SOURCE.json").write_text(json.dumps({
            "repository": "https://github.com/leeeboo/DataLayer-CLI", "revision": revision,
            "working_tree_dirty": False, "platform": system, "architecture": "x86_64",
            "binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        }, indent=2) + "\n", encoding="utf-8")
        staged_archive = pathlib.Path(temporary) / archive.name
        if system == "Windows":
            with zipfile.ZipFile(staged_archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
                for file in sorted(stage.iterdir()):
                    bundle.write(file, name + "/" + file.name)
        else:
            with tarfile.open(staged_archive, "w:gz") as bundle:
                bundle.add(stage, arcname=name)
        staged_archive.rename(archive)
    archive.with_suffix(archive.suffix + ".sha256").write_text(
        hashlib.sha256(archive.read_bytes()).hexdigest() + "  " + archive.name + "\n", encoding="utf-8")
    print(archive)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("binary")
    parser.add_argument("output")
    args = parser.parse_args()
    package(args.version, args.binary, args.output)
