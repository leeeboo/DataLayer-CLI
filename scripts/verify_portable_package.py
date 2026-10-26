#!/usr/bin/env python3
"""Exercise the extracted launcher without the build machine's toolchain paths."""
import argparse
import os
import pathlib
import platform
import subprocess
import verify_export_fixture


def verify(package, fixture, output):
    package, fixture, output = map(lambda p: pathlib.Path(p).resolve(), [package, fixture, output])
    moved = package.with_name(package.name + " QA 空格 &")
    package.rename(moved)
    package = moved
    windows = platform.system() == "Windows"
    binary = package / ("overlay.exe" if windows else "overlay")
    clean = {k: v for k, v in os.environ.items()
             if k.lower() not in ["path", "ld_library_path", "fontconfig_file", "fontconfig_path", "swift_runtime_library_path"]}
    clean["PATH"] = os.path.join(os.environ["SystemRoot"], "System32") if windows else "/usr/bin:/bin"
    subprocess.run([str(binary), "--help"], env=clean, check=True, timeout=30)
    smoke = output.with_name(output.name + " QA 空格 &-standalone.mov")
    subprocess.run([str(binary), "--timeline-project", str(fixture / "moved-project/prores-4444.dlsproj"),
                    "--output", str(smoke)], env=clean, check=True, timeout=240)
    assert smoke.stat().st_size > 1000
    # Inspect with the same bundled media tools; the standalone export above gets no library-path help.
    os.environ.clear()
    os.environ.update(clean)
    os.environ["PATH"] = str(package / "runtime/bin") + os.pathsep + clean["PATH"]
    if not windows:
        os.environ["LD_LIBRARY_PATH"] = str(package / "runtime/lib")
    verify_export_fixture.verify(binary, fixture, output)
    smoke.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("package")
    parser.add_argument("fixture")
    parser.add_argument("output")
    args = parser.parse_args()
    verify(args.package, args.fixture, args.output)
