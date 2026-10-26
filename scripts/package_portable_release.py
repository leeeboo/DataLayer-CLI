#!/usr/bin/env python3
"""Package a native executable with its collected runtime and matching source archives."""
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
from collect_portable_runtime import digest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def package(version, binary, output, runtime, sources):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        raise ValueError("Expected vX.Y.Z")
    system = platform.system()
    machine = platform.machine().lower()
    if system not in ("Linux", "Windows") or machine not in ("amd64", "x86_64"):
        raise ValueError("Portable release binaries currently target Windows/Linux x86_64")
    binary, output = pathlib.Path(binary).resolve(), pathlib.Path(output).resolve()
    runtime, sources = pathlib.Path(runtime).resolve(), pathlib.Path(sources).resolve()
    manifest = json.loads((runtime / "DEPENDENCIES.json").read_text(encoding="utf-8"))
    if manifest["platform"] != system or not manifest["sources"]:
        raise ValueError("Missing matching runtime sources")
    for entry in manifest.get("files", []):
        file = runtime / entry["path"]
        if not file.resolve().is_relative_to(runtime) or digest(file) != entry["sha256"]:
            raise ValueError("Runtime file checksum mismatch")
    for entry in manifest["sources"]:
        source = sources / entry["file"]
        if source.parent != sources or digest(source) != entry["sha256"]:
            raise ValueError("Runtime source checksum mismatch")
    if not binary.is_file():
        raise ValueError("Missing native executable")
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT).strip():
        raise ValueError("Commit source changes before packaging")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    name = f"DataLayer-CLI-{version}-{system}-x86_64"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / (name + (".zip" if system == "Windows" else ".tar.gz"))
    source_archive = output / (name + "-dependency-sources.tar")
    if any(p.exists() or p.with_suffix(p.suffix + ".sha256").exists() for p in [archive, source_archive]):
        raise FileExistsError(archive)
    with tempfile.TemporaryDirectory(prefix="staging.", dir=output) as temporary:
        stage = pathlib.Path(temporary) / name
        stage.mkdir()
        shutil.copytree(runtime, stage / "runtime")
        executable_name = "overlay.exe" if system == "Windows" else "overlay"
        executable = stage / "runtime/bin" / executable_name
        if digest(binary) != manifest["build_binary_sha256"]:
            raise ValueError("Collected CLI does not match release executable")
        (stage / "runtime" / ("launcher.exe" if system == "Windows" else "launcher")).rename(stage / executable_name)
        for document in ["LICENSE", "NOTICE.md", "README.md", "AUDIT.md", "ORIGIN.json"]:
            shutil.copy2(ROOT / document, stage / document)
        shutil.copytree(ROOT / "docs", stage / "docs")
        for readme in ROOT.glob("README.*.md"):
            shutil.copy2(readme, stage / readme.name)
        (stage / "THIRD_PARTY.md").write_text(
            "# Bundled runtime\n\nDataLayer-CLI and Core remain MIT. Runtime components retain their own licenses; "
            "see runtime/licenses and runtime/DEPENDENCIES.json.\n\nMatching package sources and build recipes: "
            f"https://github.com/leeeboo/DataLayer-CLI/releases/download/{version}/{source_archive.name}\n"
            "\nLibraries remain separate and replaceable. Keep the entire extracted folder together.\n", encoding="utf-8")
        (stage / "SOURCE.json").write_text(json.dumps({
            "repository": "https://github.com/leeeboo/DataLayer-CLI", "revision": revision,
            "working_tree_dirty": False, "platform": system, "architecture": "x86_64",
            "binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
            "build_binary_sha256": digest(binary),
            "native_executable": "runtime/bin/" + executable_name,
            "dependency_sources": source_archive.name,
        }, indent=2) + "\n", encoding="utf-8")
        staged_archive = pathlib.Path(temporary) / archive.name
        if system == "Windows":
            with zipfile.ZipFile(staged_archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
                for file in sorted(stage.rglob("*")):
                    if file.is_file():
                        bundle.write(file, name + "/" + file.relative_to(stage).as_posix())
        else:
            with tarfile.open(staged_archive, "w:gz") as bundle:
                bundle.add(stage, arcname=name)
        with tarfile.open(pathlib.Path(temporary) / source_archive.name, "w") as bundle:
            bundle.add(sources, arcname="dependency-sources")
        staged_archive.rename(archive)
        (pathlib.Path(temporary) / source_archive.name).rename(source_archive)
    for path in [archive, source_archive]:
        with path.open("rb") as stream:
            checksum = hashlib.file_digest(stream, "sha256").hexdigest()
        path.with_suffix(path.suffix + ".sha256").write_text(checksum + "  " + path.name + "\n", encoding="utf-8")
    print(archive)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("binary")
    parser.add_argument("output")
    parser.add_argument("runtime")
    parser.add_argument("sources")
    args = parser.parse_args()
    package(args.version, args.binary, args.output, args.runtime, args.sources)
