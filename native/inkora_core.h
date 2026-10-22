#pragma once
#include <stdint.h>
#ifdef _WIN32
  #ifdef INKORA_CORE_BUILD
    #define INKORA_API __declspec(dllexport)
  #else
    #define INKORA_API __declspec(dllimport)
  #endif
#else
  #define INKORA_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// C ABI v1. RGBA8 straight alpha, rows in top-down order.
// Pixel storage is owned by the caller and must be mutable.
// All floats are finite. Colors, opacity, hardness and pressure are in [0, 1].
// coordinates are expressed in bitmap pixels; no screen scaling.
// No allocation escapes from this API; thread-safety is caller's responsibility.
typedef struct InkoraStroke {
    uint8_t *pixels;
    int32_t width, height, stride;
    uint64_t buffer_bytes;
    float x0, y0, x1, y1;
    float diameter, hardness, opacity, spacing;
    float r, g, b, pressure0, pressure1;
    int32_t eraser;
} InkoraStroke;

// 0 = error / invalid input, 1 = success, including fully clipped strokes.
INKORA_API int32_t inkora_core_api_version(void);
INKORA_API int32_t inkora_core_stroke(const InkoraStroke *stroke);

#ifdef __cplusplus
}
#endif
