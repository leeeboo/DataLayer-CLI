# Installation and source builds

[README](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.md) · [简体中文](https://github.com/leeeboo/DataLayer-CLI/blob/main/README.zh-CN.md)

## Download and verify

Get the archive for your OS and architecture, plus its `.sha256` file, from
[Releases](https://github.com/leeeboo/DataLayer-CLI/releases/latest). The supported
binary targets are macOS 13+ on Apple Silicon, Windows x86_64 and Ubuntu 24.04
x86_64. Other Linux distributions and architectures are not binary release targets.

These examples use v0.1.0. Verify your archive **before extracting it**:

```sh
# macOS
shasum -a 256 -c DataLayer-CLI-v0.1.0-macOS-arm64.zip.sha256

# Linux
sha256sum -c DataLayer-CLI-v0.1.0-Linux-x86_64.tar.gz.sha256
```

```powershell
# Windows PowerShell
$archive = "DataLayer-CLI-v0.1.0-Windows-x86_64.zip"
$expected = (Get-Content "$archive.sha256").Split(' ')[0]
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $expected) {
    throw "Archive checksum mismatch"
}
Expand-Archive $archive -DestinationPath .
```

Adjust the version in these filenames for a later release. After extraction,
open a terminal in the folder containing `overlay` or `overlay.exe`.

## macOS

The release executable is Developer ID signed and notarized. It uses Apple
system frameworks, so it does not need a separate Swift, FFmpeg or graphics
runtime installation.

```sh
./overlay --help
```

## Ubuntu 24.04 (x86_64)

1. Install and select **Swift 6.1.2** using the [official Swift Linux guide](https://www.swift.org/install/linux/).
   The downloaded portable executable was built with that version; check with `swift --version`.
2. Install the media, graphics and font dependencies:

```sh
sudo apt-get update
sudo apt-get install -y python3 ffmpeg libcairo2 libpangocairo-1.0-0 fonts-dejavu-core
```

3. Expose the selected Swift runtime libraries in the current Bash session:

```sh
export LD_LIBRARY_PATH="$(swift -print-target-info | python3 -c 'import json,sys; print(":".join(json.load(sys.stdin)["paths"]["runtimeLibraryPaths"]))')${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
./overlay --help
```

Repeat the environment setup in a new terminal, or add it to your shell profile
after confirming that the intended Swift version is selected.

## Windows (x86_64)

1. Follow the [official Swift Windows instructions](https://www.swift.org/install/windows/),
   including the platform prerequisites. Select **Swift 6.1.2 x86_64** under
   **Previous Releases** for the prebuilt CLI, then restart the terminal.
2. Install [MSYS2](https://www.msys2.org/). In its **UCRT64** terminal, run:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-cairo mingw-w64-ucrt-x86_64-pango mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-ttf-dejavu
```

3. Add the Swift runtime DLL directory and MSYS2's `ucrt64\bin` to `PATH`.
   For a default MSYS2 installation, this adds the latter for the current PowerShell session:

```powershell
$env:Path = "C:\msys64\ucrt64\bin;$env:Path"
swift --version
Get-Command ffmpeg, ffprobe
.\overlay.exe --help
```

Adjust the path if MSYS2 is installed elsewhere. `overlay.exe` is a native Windows
program; after installing the dependencies, it can run directly in PowerShell.

## Run from any folder

Add the directory containing the executable to your `PATH` to use `overlay`
as shown in the README. Otherwise, use its full path, or `./overlay` /
`.\overlay.exe` when it is in the current folder. Quote paths containing spaces.

Keep the included `LICENSE` and `NOTICE.md` when redistributing an archive.
Windows/Linux dependencies are installed separately, not bundled or relicensed
under MIT. See [NOTICE.md](https://github.com/leeeboo/DataLayer-CLI/blob/main/NOTICE.md).

## Build from source

Use Swift 5.9+ and Xcode command-line tools on macOS. Windows/Linux builds are
tested with Swift 6.1.2 and need the platform dependencies above.

```sh
git clone https://github.com/leeeboo/DataLayer-CLI.git
cd DataLayer-CLI
swift build -c release --product overlay
swift build -c release --show-bin-path
```

The final command prints the executable directory. Run `overlay --help` from
that directory, using `./overlay` on macOS/Linux or `.\overlay.exe` in PowerShell.

To try synthetic data from the source checkout, with Python 3 installed:

```sh
python3 examples/make_sample.py sample.gpx
swift run -c release overlay --fit sample.gpx --codec prores-4444 --output sample-overlay.mov
```

The generator refuses to overwrite an existing sample. It generates activity
data rather than reading personal recordings. On Windows, use `python` instead
of `python3` if that is how Python 3 is installed. The `examples/` directory is
in the source checkout, not in the binary archives.

## Common issues

| Symptom | Check |
| --- | --- |
| `overlay` is not found | Add its folder to `PATH`, or use `./overlay` / `.\overlay.exe`. |
| Missing Swift DLL or `.so` | Select Swift 6.1.2 and configure the runtime paths above. |
| Missing Cairo/Pango, FFmpeg or fonts | Install all platform dependencies, then restart the terminal. |
| Existing output is rejected | Choose a new output name, or add `--force`. Inputs remain protected. |
| Moved project cannot find media | Preserve the relative folder layout of the project and its media. |
| `hevc-alpha` is rejected | Use `prores-4444` for transparency on Windows/Linux. No opaque fallback is applied. |
