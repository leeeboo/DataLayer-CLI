#include "CCairoRuntime.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
// Resolve explicitly configured runtime directories; never load project-local DLLs from CWD.
static void *open_library(const char *name) {
    DWORD length=GetEnvironmentVariableW(L"PATH",NULL,0);
    if(!length)return NULL;
    WCHAR *path=calloc(length,sizeof(WCHAR));
    if(!path)return NULL;
    if(!GetEnvironmentVariableW(L"PATH",path,length)){free(path);return NULL;}
    WCHAR filename[128];
    if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,name,-1,filename,128)){free(path);return NULL;}
    void *library=NULL;
    for(WCHAR *start=path; *start && !library;) {
        WCHAR *end=wcschr(start,L';'); if(end)*end=0;
        WCHAR *directory=start;
        size_t count=wcslen(directory);
        if(count>=2 && directory[0]==L'"' && directory[count-1]==L'"'){directory++;directory[count-2]=0;count-=2;}
        if((count>=3 && directory[1]==L':') || (count>=2 && directory[0]==L'\\' && directory[1]==L'\\')) {
            size_t size=count+wcslen(filename)+2;
            WCHAR *full=calloc(size,sizeof(WCHAR));
            if(full){wcscpy(full,directory);wcscat(full,L"\\");wcscat(full,filename);
                library=(void *)LoadLibraryExW(full,NULL,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);free(full);}
        }
        if(!end)break;start=end+1;
    }
    free(path);return library;
}
#define OPEN(name) open_library(name)
#define SYMBOL(handle, name) ((void *)GetProcAddress((HMODULE)handle, name))
#define THREAD_LOCAL __declspec(thread)
#else
#include <dlfcn.h>
#include <signal.h>
#define OPEN(name) dlopen(name, RTLD_NOW | RTLD_LOCAL)
#define SYMBOL(handle, name) dlsym(handle, name)
#define THREAD_LOCAL _Thread_local
#endif

// These declarations describe the stable C ABI, rather than copying library implementations.
typedef struct { int x, y, width, height; } PangoRectangle;
#define CAIRO_FUNCTIONS(X) \
 X(void *, image_surface_create_for_data, (unsigned char *, int, int, int, int)) \
 X(void *, image_surface_create, (int, int, int)) \
 X(unsigned char *, image_surface_get_data, (void *)) \
 X(int, image_surface_get_stride, (void *)) \
 X(void *, create, (void *)) \
 X(void, destroy, (void *)) \
 X(void, surface_destroy, (void *)) \
 X(void, surface_flush, (void *)) \
 X(void, surface_mark_dirty, (void *)) \
 X(int, surface_status, (void *)) \
 X(void *, get_target, (void *)) \
 X(void, save, (void *)) \
 X(void, restore, (void *)) \
 X(void, identity_matrix, (void *)) \
 X(void, translate, (void *, double, double)) \
 X(void, scale, (void *, double, double)) \
 X(void, move_to, (void *, double, double)) \
 X(void, line_to, (void *, double, double)) \
 X(void, curve_to, (void *, double, double, double, double, double, double)) \
 X(void, arc, (void *, double, double, double, double, double)) \
 X(void, arc_negative, (void *, double, double, double, double, double)) \
 X(void, close_path, (void *)) \
 X(void, new_path, (void *)) \
 X(void *, copy_path, (void *)) \
 X(void, append_path, (void *, void *)) \
 X(void, path_destroy, (void *)) \
 X(void, path_extents, (void *, double *, double *, double *, double *)) \
 X(void, set_line_width, (void *, double)) \
 X(double, get_line_width, (void *)) \
 X(void, set_line_cap, (void *, int)) \
 X(int, get_line_cap, (void *)) \
 X(void, set_line_join, (void *, int)) \
 X(int, get_line_join, (void *)) \
 X(void, set_source_rgba, (void *, double, double, double, double)) \
 X(void, set_source_surface, (void *, void *, double, double)) \
 X(void, fill, (void *)) \
 X(void, stroke, (void *)) \
 X(void, paint, (void *)) \
 X(void, set_antialias, (void *, int)) \
 X(void *, font_options_create, (void)) \
 X(void, font_options_destroy, (void *)) \
 X(void, font_options_set_hint_style, (void *, int)) \
 X(void, font_options_set_hint_metrics, (void *, int)) \
 X(void, font_options_set_antialias, (void *, int))
#define DECLARE(return_type, name, arguments) static return_type (*cairo_##name) arguments;
CAIRO_FUNCTIONS(DECLARE)
#undef DECLARE

static void *(*pango_cairo_font_map_new_for_font_type)(int);
static void *(*pango_font_map_create_context)(void *);
static void (*pango_cairo_context_set_font_options)(void *, void *);
static void *(*pango_layout_new)(void *);
static void *(*pango_font_description_new)(void);
static void (*pango_font_description_set_family)(void *, const char *);
static void (*pango_font_description_set_absolute_size)(void *, double);
static void (*pango_font_description_set_weight)(void *, int);
static void (*pango_font_description_set_style)(void *, int);
static void (*pango_font_description_free)(void *);
static void (*pango_layout_set_font_description)(void *, void *);
static void (*pango_layout_set_text)(void *, const char *, int);
static void (*pango_layout_get_extents)(void *, PangoRectangle *, PangoRectangle *);
static int (*pango_layout_get_baseline)(void *);
static void (*pango_cairo_show_layout)(void *, void *);
static void (*g_object_unref)(void *);

const char *dls_graphics_initialize(void) {
#ifdef _WIN32
    void *cairo = OPEN("libcairo-2.dll"), *pango = OPEN("libpango-1.0-0.dll");
    void *pangocairo = OPEN("libpangocairo-1.0-0.dll"), *gobject = OPEN("libgobject-2.0-0.dll");
#else
    void *cairo = OPEN("libcairo.so.2"), *pango = OPEN("libpango-1.0.so.0");
    void *pangocairo = OPEN("libpangocairo-1.0.so.0"), *gobject = OPEN("libgobject-2.0.so.0");
    // A failed encoder must become a Swift error, rather than terminating the CLI on EPIPE.
    signal(SIGPIPE, SIG_IGN);
#endif
    if (!cairo || !pango || !pangocairo || !gobject) return "Install Cairo, Pango and their runtime dependencies; on Windows add their DLL directory to PATH.";
#define LOAD(return_type, name, arguments) \
    cairo_##name = SYMBOL(cairo, "cairo_" #name); \
    if (!cairo_##name) return "Missing Cairo symbol: cairo_" #name;
    CAIRO_FUNCTIONS(LOAD)
#undef LOAD
#define BIND(library, name) name = SYMBOL(library, #name); if (!name) return "Missing graphics symbol: " #name;
    BIND(pangocairo, pango_cairo_font_map_new_for_font_type)
    BIND(pango, pango_font_map_create_context)
    BIND(pangocairo, pango_cairo_context_set_font_options)
    BIND(pango, pango_layout_new)
    BIND(pango, pango_font_description_new)
    BIND(pango, pango_font_description_set_family)
    BIND(pango, pango_font_description_set_absolute_size)
    BIND(pango, pango_font_description_set_weight)
    BIND(pango, pango_font_description_set_style)
    BIND(pango, pango_font_description_free)
    BIND(pango, pango_layout_set_font_description)
    BIND(pango, pango_layout_set_text)
    BIND(pango, pango_layout_get_extents)
    BIND(pango, pango_layout_get_baseline)
    BIND(pangocairo, pango_cairo_show_layout)
    BIND(gobject, g_object_unref)
#undef BIND
    void *font_probe = pango_cairo_font_map_new_for_font_type(1);
    if (!font_probe) return "Pango must include its FreeType/Cairo font backend.";
    g_object_unref(font_probe);
    return NULL;
}

typedef struct { void *context, *surface; int width, height; } Graphics;
void *dls_graphics_create(uint8_t *pixels, int width, int height, int stride) {
    Graphics *g = calloc(1, sizeof(*g));
    if (!g) return NULL;
    g->surface = cairo_image_surface_create_for_data(pixels, 0, width, height, stride);
    if (cairo_surface_status(g->surface)) { cairo_surface_destroy(g->surface); free(g); return NULL; }
    g->context = cairo_create(g->surface); g->width = width; g->height = height;
    cairo_translate(g->context, 0, height); cairo_scale(g->context, 1, -1);
    cairo_set_antialias(g->context, 2);
    return g;
}
void dls_graphics_destroy(void *context) {
    Graphics *g = context; cairo_surface_flush(g->surface);
    cairo_destroy(g->context); cairo_surface_destroy(g->surface); free(g);
}
#define CTX ((Graphics *)context)->context
void dls_graphics_save(void *context) { cairo_save(CTX); }
void dls_graphics_restore(void *context) { cairo_restore(CTX); }
void dls_graphics_antialias(void *context, int enabled) { cairo_set_antialias(CTX,enabled?2:1); }
void dls_graphics_move(void *context, double x, double y) { cairo_move_to(CTX, x, y); }
void dls_graphics_line(void *context, double x, double y) { cairo_line_to(CTX, x, y); }
void dls_graphics_curve(void *context, double a, double b, double c, double d, double e, double f) { cairo_curve_to(CTX, a,b,c,d,e,f); }
void dls_graphics_arc(void *context, double x, double y, double r, double a, double b, int clockwise) {
    if (clockwise) cairo_arc_negative(CTX,x,y,r,a,b); else cairo_arc(CTX,x,y,r,a,b);
}
void dls_graphics_close(void *context) { cairo_close_path(CTX); }
void dls_graphics_new_path(void *context) { cairo_new_path(CTX); }
void dls_graphics_width(void *context, double width) { cairo_set_line_width(CTX,width); }
void dls_graphics_cap(void *context, int cap) { cairo_set_line_cap(CTX,cap); }
void dls_graphics_join(void *context, int join) { cairo_set_line_join(CTX,join); }

// Three bounded box passes approximate a Gaussian shadow on the path's cropped surface.
static void blur(uint8_t *pixels, int width, int height, int stride, int radius) {
    if (radius < 1) return;
    uint8_t *temp = calloc((size_t)height, (size_t)stride);
    if (!temp) return;
    for (int pass=0; pass<3; pass++) {
        for (int y=0; y<height; y++) for (int channel=0; channel<4; channel++) {
            unsigned int sum=0;
            for (int x=-radius; x<width+radius; x++) {
                if (x+radius<width && x+radius>=0) sum+=pixels[y*stride+(x+radius)*4+channel];
                if (x-radius-1>=0 && x-radius-1<width) sum-=pixels[y*stride+(x-radius-1)*4+channel];
                if (x>=0 && x<width) temp[y*stride+x*4+channel]=(uint8_t)(sum/(2*radius+1));
            }
        }
        for (int x=0; x<width; x++) for (int channel=0; channel<4; channel++) {
            unsigned int sum=0;
            for (int y=-radius; y<height+radius; y++) {
                if (y+radius<height && y+radius>=0) sum+=temp[(y+radius)*stride+x*4+channel];
                if (y-radius-1>=0 && y-radius-1<height) sum-=temp[(y-radius-1)*stride+x*4+channel];
                if (y>=0 && y<height) pixels[y*stride+x*4+channel]=(uint8_t)(sum/(2*radius+1));
            }
        }
    }
    free(temp);
}

void dls_graphics_paint(void *context, int stroke, double r, double g, double b, double a,
                        double sx, double sy, double sb, const double *shadow) {
    Graphics *graphics=context; void *cr=graphics->context;
    if (shadow && shadow[3]>0) {
        double x1,y1,x2,y2; cairo_path_extents(cr,&x1,&y1,&x2,&y2);
        double pad=ceil(sb*3+cairo_get_line_width(cr)+2);
        x1=fmax(-pad, floor(x1-pad)); y1=fmax(-pad, floor(y1-pad));
        x2=fmin(graphics->width+pad, ceil(x2+pad)); y2=fmin(graphics->height+pad, ceil(y2+pad));
        int width=(int)(x2-x1), height=(int)(y2-y1);
        if (width>0 && height>0) {
            void *surface=cairo_image_surface_create(0,width,height);
            if (!cairo_surface_status(surface)) {
                void *mask=cairo_create(surface), *path=cairo_copy_path(cr);
                cairo_translate(mask,-x1,y2); cairo_scale(mask,1,-1); cairo_append_path(mask,path);
                cairo_path_destroy(path); cairo_set_source_rgba(mask,shadow[0],shadow[1],shadow[2],shadow[3]*a);
                cairo_set_line_width(mask,cairo_get_line_width(cr)); cairo_set_line_cap(mask,cairo_get_line_cap(cr));
                cairo_set_line_join(mask,cairo_get_line_join(cr));
                if(stroke)cairo_stroke(mask);else cairo_fill(mask);
                cairo_destroy(mask); cairo_surface_flush(surface);
                blur(cairo_image_surface_get_data(surface),width,height,cairo_image_surface_get_stride(surface),(int)ceil(sb/2));
                cairo_surface_mark_dirty(surface); cairo_save(cr); cairo_identity_matrix(cr);
                cairo_set_source_surface(cr,surface,x1+sx,graphics->height-y2-sy); cairo_paint(cr); cairo_restore(cr);
            }
            cairo_surface_destroy(surface);
        }
    }
    cairo_set_source_rgba(cr,r,g,b,a);
    if(stroke)cairo_stroke(cr);else cairo_fill(cr);
}

void dls_graphics_composite(uint8_t *destination, const uint8_t *source, int width, int height, int stride) {
    for(int y=0;y<height;y++) for(int x=0;x<width;x++) {
        int offset=y*stride+x*4, inverse=255-source[offset+3];
        for(int c=0;c<4;c++) destination[offset+c]=(uint8_t)(source[offset+c]+(destination[offset+c]*inverse+127)/255);
    }
}

static THREAD_LOCAL void *font_map;
void *dls_text_create(const char *text, const char *family, double size, int weight, int italic) {
    if(!font_map)font_map=pango_cairo_font_map_new_for_font_type(1); // FreeType on both Windows and Linux.
    if(!font_map)return NULL;
    void *context=pango_font_map_create_context(font_map), *options=cairo_font_options_create();
    cairo_font_options_set_hint_style(options,1); cairo_font_options_set_hint_metrics(options,1);
    cairo_font_options_set_antialias(options,2); pango_cairo_context_set_font_options(context,options);
    cairo_font_options_destroy(options);
    void *line=pango_layout_new(context), *font=pango_font_description_new();
    pango_font_description_set_family(font,family); pango_font_description_set_absolute_size(font,size*1024);
    pango_font_description_set_weight(font,weight); pango_font_description_set_style(font,italic?2:0);
    pango_layout_set_font_description(line,font); pango_layout_set_text(line,text,-1);
    pango_font_description_free(font); g_object_unref(context); return line;
}
void dls_text_destroy(void *line) { g_object_unref(line); }
DLSFontMetrics dls_text_metrics(void *line) {
    PangoRectangle ink,logical; pango_layout_get_extents(line,&ink,&logical);
    double baseline=pango_layout_get_baseline(line)/1024.0;
    return (DLSFontMetrics){ink.x/1024.0,baseline-(ink.y+ink.height)/1024.0,ink.width/1024.0,ink.height/1024.0,logical.width/1024.0};
}
void dls_text_draw(void *context, void *line, double x, double y, double r, double g, double b, double a) {
    void *cr=CTX, *path=cairo_copy_path(cr);
    // Cairo's graphics state excludes the path; CoreText drawing leaves that path intact.
    cairo_new_path(cr); cairo_save(cr); cairo_translate(cr,x,y); cairo_scale(cr,1,-1);
    cairo_move_to(cr,0,-pango_layout_get_baseline(line)/1024.0); cairo_set_source_rgba(cr,r,g,b,a);
    pango_cairo_show_layout(cr,line); cairo_restore(cr);
    cairo_new_path(cr); cairo_append_path(cr,path); cairo_path_destroy(path);
}

int dls_replace_file(const char *source, const char *destination) {
#ifdef _WIN32
    int source_count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,source,-1,NULL,0);
    int destination_count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,destination,-1,NULL,0);
    if(!source_count || !destination_count)return (int)GetLastError();
    WCHAR *s=malloc(source_count*sizeof(WCHAR)), *d=malloc(destination_count*sizeof(WCHAR));
    if(!s || !d){free(s);free(d);return ERROR_NOT_ENOUGH_MEMORY;}
    MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,source,-1,s,source_count);
    MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,destination,-1,d,destination_count);
    int error=MoveFileExW(s,d,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)?0:(int)GetLastError();
    free(s);free(d);return error;
#else
    return rename(source,destination)==0?0:errno;
#endif
}

int dls_process_is_running(int32_t pid) {
    if(pid<=0)return 1;
#ifdef _WIN32
    HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,(DWORD)pid);
    if(!process)return GetLastError()!=ERROR_INVALID_PARAMETER;
    DWORD code=STILL_ACTIVE;
    int running=!GetExitCodeProcess(process,&code) || code==STILL_ACTIVE;
    CloseHandle(process);return running;
#else
    return kill(pid,0)==0 || errno!=ESRCH;
#endif
}
