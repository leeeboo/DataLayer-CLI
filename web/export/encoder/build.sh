#!/usr/bin/env bash
set -euo pipefail
encoder_dir="$(cd "$(dirname "$0")" && pwd)"
if ! emcc --version | head -n 1 | grep -q '4.0.23'; then
  echo 'Activate Emscripten SDK 4.0.23 before building.' >&2; exit 1
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/dls-alpha-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
python3 - "$encoder_dir" "$build_dir" <<'PY'
import hashlib,pathlib,sys,tarfile
root,build=map(pathlib.Path,sys.argv[1:]);archive=root/'x265_4.1.tar.gz'
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29'
with tarfile.open(archive) as tar: tar.extractall(build,filter='data')
p=build/'x265_4.1/source/CMakeLists.txt';s=p.read_text()
s=s.replace('SET CMP0025 OLD','SET CMP0025 NEW').replace('SET CMP0054 OLD','SET CMP0054 NEW')
s=s.replace('set(X86_ALIASES x86 i386 i686 x86_64 amd64)','if(EMSCRIPTEN)\n    set(SYSPROC wasm32)\nendif()\nset(X86_ALIASES x86 i386 i686 x86_64 amd64)')
p.write_text(s)
p=build/'x265_4.1/source/encoder/entropy.cpp';s=p.read_text()
old='WRITE_FLAG(vui.videoFullRangeFlag, "video_full_range_flag");'
assert s.count(old)==1
s=s.replace(old,'WRITE_FLAG(layer ? true : vui.videoFullRangeFlag, "video_full_range_flag");')
p.write_text(s)
PY
emcmake cmake -S "$build_dir/x265_4.1/source" -B "$build_dir/build" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DENABLE_ALPHA=ON -DENABLE_ASSEMBLY=OFF \
  -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_LIBNUMA=OFF -DENABLE_PIC=ON \
  -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_CXX_FLAGS=-pthread -msimd128 -O3 -ffile-prefix-map=$build_dir=." \
  "-DCMAKE_C_FLAGS=-pthread -msimd128 -O3 -ffile-prefix-map=$build_dir=."
cmake --build "$build_dir/build" -j 4
em++ "$encoder_dir/bridge.cpp" "$build_dir/build/libx265.a" \
  -I"$build_dir/x265_4.1/source" -I"$build_dir/build" -DENABLE_ALPHA=1 \
  "-ffile-prefix-map=$encoder_dir=." -O3 -msimd128 -pthread \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createAlphaEncoder \
  -sENVIRONMENT=web,worker,node -sPTHREAD_POOL_SIZE=10 -sALLOW_MEMORY_GROWTH=1 \
  -sINITIAL_MEMORY=67108864 -sMAXIMUM_MEMORY=536870912 -sSTACK_SIZE=2097152 \
  -sEXPORTED_RUNTIME_METHODS='["HEAPU8"]' \
  -sEXPORTED_FUNCTIONS='["_open_encoder","_close_encoder","_input_pointer","_output_pointer","_output_size","_encode_frame"]' \
  -o "$encoder_dir/x265.mjs"
