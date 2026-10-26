#!/usr/bin/env python3
"""Collect native runtime dependencies, notices and matching package sources in CI."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SWIFT_TAG = "swift-6.1.2-RELEASE"
LINUX_LAUNCHER = '''#!/bin/sh
set -eu
root=$(dirname "$(readlink -f "$0")")
export PATH="$root/runtime/bin:$PATH"
export LD_LIBRARY_PATH="$root/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export FONTCONFIG_FILE="$root/runtime/fonts.conf"
exec "$root/runtime/bin/overlay" "$@"
'''
FONT_CONFIG = '''<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig><dir prefix="relative">fonts</dir><cachedir prefix="xdg">fontconfig</cachedir></fontconfig>
'''


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE).strip()


def digest(path):
    with pathlib.Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download(url, path):
    print("Fetching " + path.name, flush=True)
    with urllib.request.urlopen(url, timeout=120) as response, path.open("wb") as output:
        shutil.copyfileobj(response, output)


def windows_utf8_manifest(binary):
    kits = pathlib.Path(os.environ["ProgramFiles(x86)"]) / "Windows Kits/10/bin"
    tools = sorted(kits.glob("*/x64/mt.exe"), reverse=True)
    if not tools:
        raise ValueError("Windows SDK manifest tool is missing")
    with tempfile.TemporaryDirectory() as temporary:
        manifest = pathlib.Path(temporary) / "application.manifest"
        subprocess.run([str(tools[0]), "-nologo", "-inputresource:" + str(binary) + ";#1",
                        "-out:" + str(manifest)], check=True)
        document = ET.parse(manifest)
        root = document.getroot()
        namespace = "{urn:schemas-microsoft-com:asm.v3}"
        application = root.find(namespace + "application")
        if application is None:
            application = ET.SubElement(root, namespace + "application")
        settings = application.find(namespace + "windowsSettings")
        if settings is None:
            settings = ET.SubElement(application, namespace + "windowsSettings")
        codepage = "{http://schemas.microsoft.com/SMI/2019/WindowsSettings}activeCodePage"
        node = settings.find(codepage)
        if node is None:
            node = ET.SubElement(settings, codepage)
        node.text = "UTF-8"
        document.write(manifest, encoding="utf-8", xml_declaration=True)
        subprocess.run([str(tools[0]), "-nologo", "-manifest", str(manifest),
                        "-outputresource:" + str(binary) + ";#1"], check=True)


def linux_dependencies(binary):
    text = run("ldd", str(binary))
    if "not found" in text:
        raise ValueError("Unresolved runtime dependency: " + text)
    # The target is Ubuntu 24.04; its loader and glibc remain operating-system components.
    system = re.compile(r"^(?:ld-linux-.*|lib(?:c|m|dl|pthread|rt|resolv|util|anl)\.so\..*)$")
    return [pathlib.Path(p) for p in re.findall(r"(?:=>\s+)?(/[^\s]+)", text)
            if not system.match(pathlib.Path(p).name)]


def windows_dependencies(binary, objdump, search):
    names = re.findall(r"DLL Name:\s*(\S+)", run(str(objdump), "-p", str(binary)), re.I)
    dependencies = []
    for name in names:
        found = next((folder / name for folder in search if (folder / name).is_file()), None)
        if found:
            dependencies.append(found)
        elif not (name.lower().startswith(("api-ms-win-", "ext-ms-win-")) or
                  (pathlib.Path(os.environ["SystemRoot"]) / "System32" / name).is_file()):
            raise ValueError("Unresolved Windows dependency: " + name)
        elif name.lower().startswith(("msvcp", "vcruntime", "concrt")):
            raise ValueError("Missing redistributable Microsoft runtime: " + name)
    return dependencies


def collect(binary, destination, source_directory):
    system = platform.system()
    if system not in ("Linux", "Windows"):
        raise ValueError("Collect on the native Windows/Linux build host")
    binary, destination = pathlib.Path(binary).resolve(), pathlib.Path(destination).resolve()
    source_directory = pathlib.Path(source_directory).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    source_directory.mkdir(parents=True, exist_ok=False)
    for folder in ["bin", "lib", "fonts", "licenses"]:
        (destination / folder).mkdir()
    configuration = subprocess.run([shutil.which("ffmpeg"), "-buildconf"], text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True).stdout
    if "--enable-nonfree" in configuration:
        raise ValueError("Refusing a non-redistributable FFmpeg build")
    packages, files = {}, []
    target = json.loads(run("swift", "-print-target-info"))
    assert "6.1.2" in target["compilerVersion"], target
    swift_dirs = [pathlib.Path(p).resolve() for p in target["paths"]["runtimeLibraryPaths"]]
    if system == "Windows":
        # Fontconfig reads narrow environment paths; an UTF-8 process code page preserves Unicode installs.
        windows_utf8_manifest(binary)
        swift_dirs += [pathlib.Path(shutil.which("swift")).resolve().parent]
        msys = pathlib.Path(os.environ["MSYS2_LOCATION"])
        ucrt = msys / "ucrt64"
        pacman, objdump = msys / "usr/bin/pacman.exe", ucrt / "bin/objdump.exe"
        swift_dirs += [pathlib.Path(p) for p in os.environ["PATH"].split(";") if "swift" in p.lower()]
        crt = [p for base in [pathlib.Path(os.environ.get("ProgramFiles", "C:/Program Files")),
                              pathlib.Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)"))]
               for p in base.glob("Microsoft Visual Studio/2022/*/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT")]
        search = [ucrt / "bin", *swift_dirs, *crt]
        seeds = [ucrt / "bin" / n for n in ["ffmpeg.exe", "ffprobe.exe", "libcairo-2.dll", "libpangocairo-1.0-0.dll"]]
        dependencies = lambda p: windows_dependencies(p, objdump, search)
        fonts = ucrt / "share/fonts/TTF"
    else:
        seeds = [pathlib.Path(shutil.which(n)) for n in ["ffmpeg", "ffprobe"]]
        cache = run("ldconfig", "-p")
        for name in ["libcairo.so.2", "libpangocairo-1.0.so.0"]:
            seeds.append(pathlib.Path(re.search(r"\b" + re.escape(name) + r"\s+.*?=>\s+(\S+)", cache)[1]))
        dependencies = linux_dependencies
        fonts = pathlib.Path("/usr/share/fonts/truetype/dejavu")
        shutil.copytree("/usr/share/common-licenses", destination / "licenses/common")

    def provider(path):
        if system == "Windows" and path.name.lower().startswith(("msvcp", "vcruntime", "concrt")):
            return "Microsoft-VC-Runtime"
        if any(path.resolve().is_relative_to(p) for p in swift_dirs):
            return "Swift"
        if system == "Windows":
            if any(path.is_relative_to(p) for p in crt):
                return "Microsoft-VC-Runtime"
            query = run(str(pacman), "-Qqo", "/" + path.relative_to(msys).as_posix()).splitlines()[0]
            if query not in packages:
                info = run(str(pacman), "-Qi", query)
                version = re.search(r"^Version\s*:\s*(\S+)", info, re.M)[1]
                desc = (msys / "var/lib/pacman/local" / (query + "-" + version) / "desc").read_text()
                base = re.search(r"%BASE%\n([^\n]+)", desc)
                base = base[1] if base else re.sub(r"^mingw-w64-ucrt-x86_64-", "mingw-w64-", query)
                packages[query] = {"version": version, "source": base + "-" + version,
                                   "license": re.search(r"^Licenses\s*:\s*(.+)", info, re.M)[1]}
                paths = run(str(pacman), "-Qlq", query).splitlines()
                for f in paths:
                    if "/share/licenses/" in f and not f.endswith("/"):
                        local = pathlib.Path(f) if pathlib.Path(f).exists() else msys / f.lstrip("/")
                        if local.is_file():
                            dest = destination / "licenses" / query / f.split("/share/licenses/", 1)[1]
                            dest.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copy2(local, dest)
            return query
        for candidate in [path, path.resolve(), pathlib.Path(str(path).replace("/usr/lib/", "/lib/")),
                          pathlib.Path("/usr" + str(path))]:
            try:
                query = run("dpkg-query", "-S", str(candidate)).split(": ", 1)[0]
                break
            except subprocess.CalledProcessError:
                pass
        else:
            raise ValueError("Unknown Linux library owner: " + str(path))
        if query not in packages:
            source, source_version, version = run("dpkg-query", "-W", "-f=${source:Package}\t${source:Version}\t${Version}", query).split("\t")
            packages[query] = {"version": version, "source": source + "=" + source_version}
            shutil.copy2(pathlib.Path("/usr/share/doc") / query.split(":")[0] / "copyright",
                         destination / "licenses" / (query.replace(":", "_") + ".copyright"))
        return query

    seen, queue = set(), [binary, *seeds]
    while queue:
        path = queue.pop()
        key = str(path.resolve()).lower() if system == "Windows" else str(path.resolve())
        if key in seen:
            continue
        seen.add(key)
        queue.extend(dependencies(path))
        folder = "bin" if system == "Windows" or path in [binary, *seeds[:2]] else "lib"
        name = ("overlay.exe" if system == "Windows" else "overlay") if path == binary else path.name
        output = destination / folder / name
        if output.exists() and digest(output) != digest(path):
            raise ValueError("Conflicting runtime libraries: " + name)
        shutil.copy2(path, output)
        if system == "Windows" and path in seeds[:2]:
            windows_utf8_manifest(output)
        files.append({"path": output.relative_to(destination).as_posix(), "sha256": digest(output),
                      "provider": "DataLayer-CLI" if path == binary else provider(path)})
        if len(files) % 25 == 0:
            print(f"Collected {len(files)} runtime files", flush=True)
    font_files = sorted(fonts.glob("DejaVu*.ttf"))
    if not font_files:
        raise ValueError("Missing DejaVu fonts")
    for path in font_files:
        shutil.copy2(path, destination / "fonts" / path.name)
        provider(path)
    (destination / "fonts.conf").write_text(FONT_CONFIG, encoding="utf-8")
    for repo, license in [("swift", "LICENSE.txt"), ("swift-corelibs-foundation", "LICENSE"),
                          ("swift-corelibs-libdispatch", "LICENSE"), ("swift-foundation", "LICENSE.md"),
                          ("swift-foundation-icu", "LICENSE.md")]:
        download(f"https://raw.githubusercontent.com/swiftlang/{repo}/{SWIFT_TAG}/{license}",
                 destination / "licenses" / (repo + ".txt"))
    if system == "Windows":
        # Preserve the redistribution terms of the app-local Microsoft CRT, if used.
        if any(f["provider"] == "Microsoft-VC-Runtime" for f in files):
            license = destination / "licenses/Microsoft-VC-Runtime.docx"
            download("https://visualstudio.microsoft.com/wp-content/uploads/2021/09/Visual-C-Runtime-2015-2022-License-1.docx", license)
            with zipfile.ZipFile(license) as archive:
                text = ET.fromstring(archive.read("word/document.xml"))
                ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
                paragraphs = ["".join(p.itertext()) for p in text.findall(".//w:p", ns)]
                license.with_suffix(".txt").write_text("\n".join(paragraphs), encoding="utf-8")
        index = urllib.request.urlopen("https://repo.msys2.org/mingw/sources/", timeout=120).read().decode()
        for package in packages.values():
            name = next((package["source"] + suffix for suffix in [".src.tar.zst", ".src.tar.gz", ".src.tar.xz"]
                         if '"' + package["source"] + suffix + '"' in index), None)
            if name is None:
                raise ValueError("No matching MSYS2 source archive: " + package["source"])
            if not (source_directory / name).exists():
                download("https://repo.msys2.org/mingw/sources/" + name, source_directory / name)
            package["source_archive"] = name
        subprocess.run([str(ucrt / "bin/gcc.exe"), "-municode", "-static-libgcc", "-Os",
                        str(ROOT / "scripts/portable_launcher.c"), "-o", str(destination / "launcher.exe")], check=True)
    else:
        subprocess.run(["apt-get", "source", "--download-only", *sorted({p["source"] for p in packages.values()})],
                       cwd=source_directory, check=True)
        (destination / "launcher").write_text(LINUX_LAUNCHER, encoding="utf-8")
        (destination / "launcher").chmod(0o755)
    manifest = {"platform": system, "swift": "6.1.2", "files": files, "packages": packages,
                "windows_manifest_change": "Executable resources set activeCodePage UTF-8; codec and renderer code are unchanged." if system == "Windows" else None,
                "sources": [{"file": p.name, "sha256": digest(p)} for p in sorted(source_directory.iterdir()) if p.is_file()]}
    (destination / "DEPENDENCIES.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    shutil.copy2(destination / "DEPENDENCIES.json", source_directory / "DEPENDENCIES.json")
    recipes = source_directory / "repack"
    recipes.mkdir()
    for name in ["collect_portable_runtime.py", "portable_launcher.c", "package_portable_release.py"]:
        shutil.copy2(ROOT / "scripts" / name, recipes / name)
    shutil.copy2(ROOT / "LICENSE", recipes / "LICENSE")
    print(f"Collected {len(files)} runtime files from {len(packages)} packages.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("runtime")
    parser.add_argument("sources")
    args = parser.parse_args()
    collect(args.binary, args.runtime, args.sources)
