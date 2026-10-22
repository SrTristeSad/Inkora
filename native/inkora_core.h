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

// RGBA8 straight alpha; caller retains ownership of the mutable buffer.
// API v2 leaves the original InkoraStroke layout intact to preserve ABI v1.
typedef struct InkoraStroke {
    uint8_t *pixels;
    int32_t width, height, stride;
    uint64_t buffer_bytes;
    float x0, y0, x1, y1;
    float diameter, hardness, opacity, spacing;
    float r, g, b, pressure0, pressure1;
    int32_t eraser;
} InkoraStroke;

typedef struct InkoraStrokeState {
    float distance_to_next; // in document pixels until the next dab
    int32_t initialized;
} InkoraStrokeState;

typedef struct InkoraRect {
    int32_t x, y, width, height; // empty rectangle: width == height == 0
} InkoraRect;

INKORA_API int32_t inkora_core_api_version(void);
// Legacy entry point, starts a fresh stroke with each call.
INKORA_API int32_t inkora_core_stroke(const InkoraStroke *stroke);
// Continuous stroke + dirty bounds. Returns 1 on success, 0 invalid input.
// Zero size dirty rect indicates no pixels updated (e.g. fully clipped).
INKORA_API int32_t inkora_core_stroke_v2(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty);

#ifdef __cplusplus
}
#endif
