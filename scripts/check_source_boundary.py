#!/usr/bin/env python3
"""Check the audited source set and keep GUI code and credentials outside Core."""
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SECRET = re.compile(rb"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}")
UI_IMPORT = re.compile(rb"^\s*(?:@[\w]+\s+)?import\s+(?:SwiftUI|AppKit|UIKit)\b", re.MULTILINE)


def check_content(relative, data):
    if SECRET.search(data):
        raise ValueError("Possible credential in " + relative)
    if relative.startswith("Sources/OverlayCore/") and UI_IMPORT.search(data):
        raise ValueError("UI framework in platform-neutral Core: " + relative)
    return data


def checked_file(root, relative):
    path = pathlib.PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError("Invalid source path")
    source = root / path
    if source.is_symlink() or not source.resolve().is_relative_to(root.resolve()):
        raise ValueError("Symlink or escaped source: " + relative)
    return check_content(relative, source.read_bytes())


def validate_sources(root, staged=False):
    # Hooks export their repository context; -C alone does not override it.
    git_env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    if staged and "GIT_INDEX_FILE" in os.environ:
        git_env["GIT_INDEX_FILE"] = os.environ["GIT_INDEX_FILE"]
    if staged:
        entries = subprocess.check_output(["git", "-C", str(root), "ls-files", "--stage", "-z"], env=git_env).decode().split("\0")
        files = {}
        for entry in filter(None, entries):
            metadata, relative = entry.split("\t", 1)
            if metadata.split()[0] not in ("100644", "100755"):
                raise ValueError("Symlink or nested repository in CLI: " + relative)
            data = subprocess.check_output(["git", "-C", str(root), "show", ":" + relative], env=git_env)
            files[relative] = check_content(relative, data)
    else:
        paths = subprocess.check_output(["git", "-C", str(root), "ls-files", "-c", "-o",
                                         "--exclude-standard", "-z"], env=git_env).decode().split("\0")
        files = {name: checked_file(root, name) for name in filter(None, paths)
                 if (root / name).exists() or (root / name).is_symlink()}
    expected = json.loads(files["audit/files.json"])
    if len(expected) != len(set(expected)) or set(expected) != set(files):
        raise ValueError("File set changed; review provenance and update audit/files.json")


if __name__ == "__main__":
    validate_sources(ROOT, staged="--staged" in sys.argv[1:])
    print("CLI source, credential and Core import boundaries passed.")
