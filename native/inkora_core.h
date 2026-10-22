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

// Version 3 adds an optional procedural brush-tip configuration.
// tip: 0 = round, 1 = angled flat nib, 2 = grainy round tip.
// aspect: minor/major axis for flat tip (0.1..1).
// angle: degrees of the major axis relative to the bitmap x-axis.
// grain: deterministic world-space grain density (0..1).
typedef struct InkoraTip {
    int32_t tip;
    float aspect, angle, grain;
    uint32_t seed;
    // Canvas-space offset of this tile (anchors grain across tile boundaries).
    int32_t origin_x, origin_y;
} InkoraTip;

// ABI v4: optional 8-bit grayscale alpha mask, caller owned.
// Width/height are limited to 512 pixels; row stride is in bytes.
// If mask is null, the procedural round/flat/grain tip is used.
typedef struct InkoraMask {
    const uint8_t *alpha;
    int32_t width, height, stride;
    uint64_t buffer_bytes;
} InkoraMask;

// Layer compositor (C++ ABI v5): straight-alpha RGBA8, bottom-to-top.
// blend_mode: 0 normal, 1 multiply, 2 screen, 3 add, 4 overlay.
// out_rgba contains the current composed image; source is read-only.
// Strides and available byte counts are mandatory for memory safety.
INKORA_API int32_t inkora_core_blend_layer(
    uint8_t* out_rgba, uint64_t out_bytes, int32_t out_stride,
    const uint8_t* layer_rgba, uint64_t layer_bytes, int32_t layer_stride,
    int32_t width, int32_t height, float opacity, int32_t blend_mode);

// ABI v6: persistent layer alpha lock and transient rectangular selection.
// Selection is in document pixel coordinates, [left,right) x [top,bottom).
// Origin is obtained from InkoraTip.origin_x/y for tile-local strokes.
// This does not impose a selection on legacy ABI functions.
typedef struct InkoraPaintClip {
    int32_t alpha_lock, selection_enabled;
    int32_t left, top, right, bottom;
} InkoraPaintClip;

INKORA_API int32_t inkora_core_stroke_v6(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty,
    const InkoraTip *tip, const InkoraMask *mask, float flow,
    float pressure_opacity, const InkoraPaintClip *clip);


/* ABI v7 layer effects:
   Masks are RGBA8, with RED channel as coverage (0 = hidden, 255 = shown).
   Clipping uses the immediately preceding layer's source alpha, opacity,
   and optional mask, NOT the accumulated opaque background.
   All pointers are caller-owned for the duration of the call. */
typedef struct InkoraLayerEffects {
    const uint8_t *mask_rgba;
    uint64_t mask_bytes;
    int32_t mask_stride;

    int32_t clipping_enabled;
    const uint8_t *clip_rgba;
    uint64_t clip_bytes;
    int32_t clip_stride;
    float clip_opacity;

    const uint8_t *clip_mask_rgba;
    uint64_t clip_mask_bytes;
    int32_t clip_mask_stride;
} InkoraLayerEffects;

INKORA_API int32_t inkora_core_blend_layer_v7(
    uint8_t *out_rgba, uint64_t out_bytes, int32_t out_stride,
    const uint8_t *layer_rgba, uint64_t layer_bytes, int32_t layer_stride,
    int32_t width, int32_t height, float opacity, int32_t blend_mode,
    const InkoraLayerEffects *effects);

// ABI v8: nib direction follows the tangent of each stroke segment when
// follow_path=1. angle_degrees persists across mouse events, and is
// reproduced for every tile. Legacy v6 brushes retain a fixed tip angle.
typedef struct InkoraBrushDirection {
    int32_t follow_path;
    int32_t initialized;
    float angle_degrees;
} InkoraBrushDirection;

INKORA_API int32_t inkora_core_stroke_v8(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty,
    const InkoraTip *tip, const InkoraMask *mask, float flow,
    float pressure_opacity, const InkoraPaintClip *clip,
    InkoraBrushDirection *direction);

// ABI v9: deterministic texture, dab scattering and size variation.
// stamp_index is mutable stroke state: pass the same initial value to
// every tile of a segment, then retain the returned value once per segment.
// All three amounts are normalized to [0,1]; zero preserves ABI v8 visuals.
typedef struct InkoraBrushDynamics {
    float texture, scatter, size_jitter;
    uint32_t stamp_index;
} InkoraBrushDynamics;

INKORA_API int32_t inkora_core_stroke_v9(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty,
    const InkoraTip *tip, const InkoraMask *mask, float flow,
    float pressure_opacity, const InkoraPaintClip *clip,
    InkoraBrushDirection *direction, InkoraBrushDynamics *dynamics);

// ABI v10: optional local wet-pigment mixing. Wetness and pigment load
// are normalized [0,1]; zero wetness produces the exact ABI v9 result.
// Mixing samples the existing RGBA8 pixel on the *same* source layer.
typedef struct InkoraWetPaint {
    float wetness, pigment_load;
} InkoraWetPaint;

INKORA_API int32_t inkora_core_stroke_v10(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty,
    const InkoraTip *tip, const InkoraMask *mask, float flow,
    float pressure_opacity, const InkoraPaintClip *clip,
    InkoraBrushDirection *direction, InkoraBrushDynamics *dynamics,
    const InkoraWetPaint *wet);

// ABI v11: pigment is picked up from a single RGBA sample per input
// segment, supplied by the caller BEFORE painting tiles. The mutable
// reservoir persists across segments and is copied to all tiles using
// the same original state. Zero pickup preserves ABI v10 exactly.
typedef struct InkoraPigmentCarry {
    float pickup, retention;
    float sample_r, sample_g, sample_b, sample_a;
    float reservoir_r, reservoir_g, reservoir_b;
    int32_t initialized;
} InkoraPigmentCarry;

INKORA_API int32_t inkora_core_stroke_v11(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty,
    const InkoraTip *tip, const InkoraMask *mask, float flow,
    float pressure_opacity, const InkoraPaintClip *clip,
    InkoraBrushDirection *direction, InkoraBrushDynamics *dynamics,
    const InkoraWetPaint *wet, InkoraPigmentCarry *carry);

// ABI v12: the caller samples untouched source-layer pixels at EACH dab
// before rendering the segment. Samples are straight-alpha RGBA8 and ordered
// identically to inkora_core_dab_positions_v12. Each tile receives the SAME
// sample list and the SAME initial pigment state, preventing tile seams.
// The function rejects a mismatched count before modifying any pixels.
typedef struct InkoraDabSamples {
    const uint8_t *rgba;
    uint64_t buffer_bytes;
    uint32_t count;
} InkoraDabSamples;

// Two-pass API: first call with out_xy=null and capacity=0 to obtain count;
// then allocate 2*count floats and call again for exact dab center positions.
INKORA_API int32_t inkora_core_dab_positions_v12(
    const InkoraStrokeState *state,
    float x0, float y0, float x1, float y1, float diameter, float spacing,
    float *out_xy, uint32_t capacity, uint32_t *count);

INKORA_API int32_t inkora_core_stroke_v12(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty,
    const InkoraTip *tip, const InkoraMask *mask, float flow,
    float pressure_opacity, const InkoraPaintClip *clip,
    InkoraBrushDirection *direction, InkoraBrushDynamics *dynamics,
    const InkoraWetPaint *wet, InkoraPigmentCarry *carry,
    const InkoraDabSamples *samples);

INKORA_API int32_t inkora_core_api_version(void);
// Legacy entry point, starts a fresh stroke with each call.
INKORA_API int32_t inkora_core_stroke(const InkoraStroke *stroke);
// Continuous stroke + dirty bounds. Returns 1 on success, 0 invalid input.
// Zero size dirty rect indicates no pixels updated (e.g. fully clipped).
INKORA_API int32_t inkora_core_stroke_v2(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty);
// New style entry point. Original InkoraStroke and v2 symbol remain available.
INKORA_API int32_t inkora_core_stroke_v3(
    const InkoraStroke *stroke, InkoraStrokeState *state,
    InkoraRect *dirty, const InkoraTip *tip);

// Native brush pipeline with custom mask and dynamic paint flow.
// flow (0..1) scales ink deposited PER DAB.
// pressure_opacity (0..1) controls pressure influence on ink deposition.
// Pressure also affects brush size as in v3.
INKORA_API int32_t inkora_core_stroke_v4(
    const InkoraStroke *stroke, InkoraStrokeState *state, InkoraRect *dirty,
    const InkoraTip *tip, const InkoraMask *mask, float flow, float pressure_opacity);

#ifdef __cplusplus
}
#endif
