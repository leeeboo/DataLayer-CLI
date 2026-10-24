#pragma once
#include <stdint.h>

// Load the platform's Cairo/Pango shared libraries; no third-party code is embedded.
const char *dls_graphics_initialize(void);
void *dls_graphics_create(uint8_t *pixels, int width, int height, int stride);
void dls_graphics_destroy(void *context);
void dls_graphics_save(void *context);
void dls_graphics_restore(void *context);
void dls_graphics_move(void *context, double x, double y);
void dls_graphics_line(void *context, double x, double y);
void dls_graphics_curve(void *context, double x1, double y1, double x2, double y2, double x3, double y3);
void dls_graphics_arc(void *context, double x, double y, double radius, double start, double end, int clockwise);
void dls_graphics_close(void *context);
void dls_graphics_new_path(void *context);
void dls_graphics_width(void *context, double width);
void dls_graphics_cap(void *context, int cap);
void dls_graphics_join(void *context, int join);
void dls_graphics_paint(void *context, int stroke, double r, double g, double b, double a,
                        double shadow_x, double shadow_y, double shadow_blur, const double *shadow_rgba);
void dls_graphics_composite(uint8_t *destination, const uint8_t *source, int width, int height, int stride);

typedef struct { double x, y, width, height, advance; } DLSFontMetrics;
void *dls_text_create(const char *text, const char *family, double size, int weight, int italic);
void dls_text_destroy(void *line);
DLSFontMetrics dls_text_metrics(void *line);
void dls_text_draw(void *context, void *line, double x, double y, double r, double g, double b, double a);
// Atomically replace a file on the same volume; the destination survives a failed replacement.
int dls_replace_file(const char *source, const char *destination);
int dls_process_is_running(int32_t pid);
