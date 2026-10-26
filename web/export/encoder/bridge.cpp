// SPDX-License-Identifier: MIT
#include <x265.h>
#include <algorithm>
#include <cstdint>
#include <vector>

static x265_encoder* encoder = nullptr;
static x265_param* param = nullptr;
static x265_picture picture;
static std::vector<uint8_t> rgba, planar, output;
static void collect(x265_nal* nals, uint32_t count) {
    output.clear();
    for (uint32_t i = 0; i < count; ++i)
        output.insert(output.end(), nals[i].payload, nals[i].payload + nals[i].sizeBytes);
}
extern "C" {
void close_encoder() {
    if (encoder) x265_encoder_close(encoder);
    if (param) x265_param_free(param);
    encoder = nullptr; param = nullptr;
    rgba.clear(); planar.clear(); output.clear();
    x265_cleanup();
}
int open_encoder(int width, int height, int fps, int kbps) {
    if (encoder || width < 64 || height < 64 || width > 1920 || height > 1920 || width % 2 || height % 2 || width * height > 2073600 || fps < 1 || fps > 30 || kbps < 100 || kbps > 100000) return -1;
    param = x265_param_alloc();
    if (!param || x265_param_default_preset(param, "ultrafast", "zerolatency") < 0) { close_encoder(); return -2; }
    param->sourceWidth = width; param->sourceHeight = height;
    param->fpsNum = fps; param->fpsDenom = 1;
    param->internalCsp = X265_CSP_I420; param->internalBitDepth = 8;
    param->bEnableAlpha = 1; param->numScalableLayers = 2; param->numLayers = 2;
    param->frameNumThreads = 1; x265_param_parse(param, "pools", "4");
    param->bEnableWavefront = 1; param->lookaheadDepth = 0; param->bframes = 0;
    // Sparse overlays benefit from larger empty blocks and a short motion search.
    param->maxCUSize = 64; param->minCUSize = 32; param->searchRange = 16;
    param->bCopyPicToFrame = 1; param->bAnnexB = 0; param->bRepeatHeaders = 0; param->bEmitInfoSEI = 0;
    param->rc.rateControlMode = X265_RC_ABR; param->rc.bitrate = kbps;
    param->keyframeMax = fps * 2; param->bOpenGOP = 0;
    param->vui.bEnableVideoSignalTypePresentFlag = 1;
    param->vui.bEnableColorDescriptionPresentFlag = 1;
    param->vui.colorPrimaries = 1; param->vui.transferCharacteristics = 1; param->vui.matrixCoeffs = 1;
    param->vui.bEnableVideoFullRangeFlag = 0;
    param->logLevel = X265_LOG_WARNING;
    encoder = x265_encoder_open(param);
    if (!encoder) { close_encoder(); return -3; }
    const int size = width * height;
    rgba.resize(size * 4); planar.resize(size * 5 / 2);
    x265_picture_init(param, &picture);
    picture.planes[0] = planar.data(); picture.planes[1] = planar.data() + size;
    picture.planes[2] = planar.data() + size * 5 / 4; picture.planes[3] = planar.data() + size * 3 / 2;
    picture.stride[0] = width; picture.stride[1] = picture.stride[2] = width / 2; picture.stride[3] = width;
    x265_nal* nals; uint32_t count;
    if (x265_encoder_headers(encoder, &nals, &count) < 0) { close_encoder(); return -4; }
    collect(nals, count); return 0;
}
uint8_t* input_pointer() { return rgba.data(); }
uint8_t* output_pointer() { return output.data(); }
int output_size() { return static_cast<int>(output.size()); }
int encode_frame(int index) {
    if (!encoder || index < -1) return -1;
    const int w = param->sourceWidth, h = param->sourceHeight;
    if (index >= 0) {
        auto clamp = [](int v) { return static_cast<uint8_t>(std::max(0, std::min(255, v))); };
        for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
            const int i = y * w + x, p = i * 4, r = rgba[p], g = rgba[p+1], b = rgba[p+2];
            planar[i] = clamp(16 + ((11966*r + 40254*g + 4064*b + 32768) >> 16));
            planar[w*h*3/2+i] = rgba[p+3];
            if (!(y % 2) && !(x % 2)) {
                int rs = 0, gs = 0, bs = 0;
                for (int dy = 0; dy < 2; ++dy) for (int dx = 0; dx < 2; ++dx) {
                    const int q = ((y+dy)*w+x+dx)*4; rs += rgba[q]; gs += rgba[q+1]; bs += rgba[q+2];
                }
                const int c = y/2*(w/2)+x/2;
                planar[w*h+c] = clamp(128 + ((-6596*rs -22189*gs +28785*bs +131072) >> 18));
                planar[w*h*5/4+c] = clamp(128 + ((28785*rs -26145*gs -2640*bs +131072) >> 18));
            }
        }
        picture.pts = index;
    }
    x265_nal* nals; uint32_t count;
    const int result = x265_encoder_encode(encoder, &nals, &count, index < 0 ? nullptr : &picture, nullptr);
    if (result < 0) return result;
    collect(nals, count); return result;
}
}
