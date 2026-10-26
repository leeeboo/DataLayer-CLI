# HEVC Alpha Web prototype

The CLI and existing MIT sources retain their license. This standalone Web Worker encoder links x265;
**the `x265.wasm` binary is GPL-2.0-or-later**, not MIT. It is not linked into
Core, the native CLI, macOS or iOS. The separate worker exchanges RGBA frames and
encoded bytes with the MIT Web application. See [COPYING](COPYING).

Complete corresponding x265 source is included in [x265_4.1.tar.gz](x265_4.1.tar.gz),
SHA-256 `a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29`.
Upstream: <https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.1.tar.gz>,
release source reports `4.1+1-1d117be` (API 215). The bridge source and exact build
recipe are in this directory. x265 is copyright its respective upstream authors;
the archive retains their notices and all source. Standard-library notices are retained in [SYSTEM-LICENSES](SYSTEM-LICENSES).
The Emscripten runtime is
MIT/NCSA licensed: <https://github.com/emscripten-core/emscripten/blob/4.0.23/LICENSE>.

## Rebuild

Install and activate the official **Emscripten SDK 4.0.23** in a local directory
(<https://emscripten.org/docs/getting_started/downloads.html>), then run with CMake,
Make and Python 3.12+ available:

```sh
source /path/to/emsdk/emsdk_env.sh
bash web/export/encoder/build.sh
```

The script verifies the included source hash, enables Alpha, disables native
assembly, and enables WebAssembly SIMD and pthreads. It applies CMake compatibility changes:
CMP0025/CMP0054 use NEW behavior, and Emscripten uses a wasm32 target instead of
an x86 target. It also marks the Alpha SPS as full-range in `entropy.cpp`,
while preserving limited-range color in the base SPS, as required by the Apple
HEVC Alpha interoperability profile. Without this fix, native decoding expands
Alpha as video-range values and changes translucent opacity. `bridge.cpp` contains the RGBA-to-YUVA420 conversion and streaming
x265 API calls. It uses Main, BT.709 limited-range color, straight full-range
Alpha, ABR bitrate, no B-frames, one encoder frame thread per layer, four WPP workers, 64-pixel CTUs and 32-pixel minimum CUs and a short motion search for sparse overlays. The runtime starts with a 64 MiB shared heap, grows only as needed, and caps it at 512 MiB. The Worker refreshes its byte view from the shared memory before every access, including growth triggered by a pthread.
Build output is `x265.mjs` and `x265.wasm`. There is no remote encoder or upload.

## Browser hosting

Open `export/` through HTTPS (or localhost). The directory-scoped service worker
adds COOP/COEP response headers and reloads once, enabling SharedArrayBuffer on
GitHub Pages without a server. It does not cache files, proxy external hosts or
control the main editor. A dedicated Worker owns the WASM encoder and its thread
workers, and is terminated on completion, error, cancellation or page exit.

The prototype accepts a `.dlspreset` and local FIT/GPX, with the 703 default layout.
The entire activity is selected on import; the Full activity button restores that range. You can also choose a shorter start/duration, resolution, frame rate and target Mbps. Download
is an MP4 `hvc1` track containing both base and Alpha layers and the `muxa` brand.
Grid, selection handles, background video and audio are not part of the overlay.

The pixel and rate limits remain 2,073,600 pixels, 30 fps and 0.1–100 Mbps. The
60-second and 128 MiB output limits have been removed. Duration rounds up to the
next frame and is reported after encoding. MP4 uses a 64-bit `mdat` length, supports
files over 4 GiB, and retains one small size/index entry per encoded frame.

Frames are rendered through the existing Web renderer. Rendering the next frame
overlaps encoding the current frame, with at most two raw frames in flight. The
encoder Worker writes each compressed sample directly to an OPFS temporary file;
compressed video is never collected in RAM. After encoding, the service worker
streams that local file to the browser download, including byte-range requests.
The MP4 header and index are finalized only after every frame succeeds. No server,
remote encoder, API key or media upload is involved.

Temporary files live only in the browser's `dls-hevc-exports` directory. Web Locks
protect active encodes and downloads from deletion. Cancellation and replacement
remove the corresponding file; the next visit removes interrupted orphan files.
No other browser storage is cleared. Keep the page open during encoding, and
ensure sufficient free local storage. Private browsing or denied/full local
storage can prevent export. Reloading does not resume an unfinished export.
Bitrate is an ABR target; sparse layouts often produce much smaller files. Software
encoding speed varies by device and can be slower than real time.

Firefox may play the base layer without Alpha even when the exported file is
valid. Validate transparency with Safari/AVFoundation or another HEVC Alpha
capable application. Encoding and playback compatibility are separate checks.
This page uses activity/template weather only and does not read API keys or the
main editor's weather cache.
