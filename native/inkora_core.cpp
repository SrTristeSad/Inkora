#include "inkora_core.h"
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace {
float saturate(float v) { return std::max(0.0f, std::min(1.0f, v)); }
uint8_t byte(float v) { return static_cast<uint8_t>(std::lround(saturate(v) * 255.0f)); }
float unit(uint8_t n) { return static_cast<float>(n) / 255.0f; }

void dab(const InkoraStroke &s, float cx, float cy, float pressure) {
    const float radius = std::max(0.5f, s.diameter * (0.2f + 0.8f * saturate(pressure)) * 0.5f);
    const float inner = radius * saturate(s.hardness);
    const float outer = radius + 0.5f;
    const int minX = std::max(0, static_cast<int>(std::floor(cx - outer)));
    const int maxX = std::min(s.width - 1, static_cast<int>(std::ceil(cx + outer)));
    const int minY = std::max(0, static_cast<int>(std::floor(cy - outer)));
    const int maxY = std::min(s.height - 1, static_cast<int>(std::ceil(cy + outer)));
    for (int y = minY; y <= maxY; ++y) {
        for (int x = minX; x <= maxX; ++x) {
            const float dx = (x + 0.5f) - cx;
            const float dy = (y + 0.5f) - cy;
            const float distance = std::sqrt(dx * dx + dy * dy);
            const float coverage = distance <= inner ? 1.0f :
                saturate((outer - distance) / std::max(0.001f, outer - inner));
            const float strength = saturate(s.opacity) * coverage;
            if (strength <= 0.0f) continue;
            const auto offset = static_cast<size_t>(y) * static_cast<size_t>(s.stride)
                + static_cast<size_t>(x) * 4u;
            uint8_t *p = s.pixels + offset;
            const float oldA = unit(p[3]);
            if (s.eraser) {
                const float nextA = oldA * (1.0f - strength);
                if (nextA < 1.0f / 512.0f) {
                    p[0] = p[1] = p[2] = p[3] = 0;
                } else {
                    p[3] = byte(nextA);
                }
                continue;
            }
            const float newA = strength + oldA * (1.0f - strength);
            if (newA < 1.0f / 512.0f) continue;
            const float mixedOld = oldA * (1.0f - strength);
            p[0] = byte((saturate(s.r) * strength + unit(p[0]) * mixedOld) / newA);
            p[1] = byte((saturate(s.g) * strength + unit(p[1]) * mixedOld) / newA);
            p[2] = byte((saturate(s.b) * strength + unit(p[2]) * mixedOld) / newA);
            p[3] = byte(newA);
        }
    }
}
bool finite(float x) { return std::isfinite(x); }
} // namespace

extern "C" int32_t inkora_core_api_version(void) { return 1; }

extern "C" int32_t inkora_core_stroke(const InkoraStroke *ptr) {
    if (!ptr || !ptr->pixels) return 0;
    const InkoraStroke &s = *ptr;
    if (s.width < 1 || s.height < 1 || s.width > 16384 || s.height > 16384) return 0;
    if (static_cast<int64_t>(s.stride) < static_cast<int64_t>(s.width) * 4) return 0;
    const uint64_t needed = static_cast<uint64_t>(s.height - 1) * static_cast<uint64_t>(s.stride)
        + static_cast<uint64_t>(s.width) * 4;
    if (s.buffer_bytes < needed) return 0;
    const float params[] = {s.x0, s.y0, s.x1, s.y1, s.diameter,
        s.hardness, s.opacity, s.spacing, s.r, s.g, s.b, s.pressure0, s.pressure1};
    for (const float p : params) if (!finite(p)) return 0;
    if (s.diameter < 0.5f || s.diameter > 2048.0f || s.spacing <= 0.0f) return 0;
    if (s.eraser != 0 && s.eraser != 1) return 0;
    // Huge coordinates are never useful, and casting them to int would overflow.
    if (std::abs(s.x0) > 100000 || std::abs(s.y0) > 100000 ||
        std::abs(s.x1) > 100000 || std::abs(s.y1) > 100000) return 0;
    const float dx = s.x1 - s.x0, dy = s.y1 - s.y0;
    const float length = std::sqrt(dx * dx + dy * dy);
    const float step = std::max(0.75f, s.diameter * s.spacing);
    const int count = std::max(1, static_cast<int>(std::ceil(length / step)));
    for (int i = 0; i <= count; ++i) {
        // Avoid double-dabbing stationary strokes (especially at low opacity).
        if (i == 1 && length < 0.0001f) break;
        const float t = static_cast<float>(i) / static_cast<float>(count);
        const float pressure = s.pressure0 + (s.pressure1 - s.pressure0) * t;
        dab(s, s.x0 + dx*t, s.y0 + dy*t, pressure);
    }
    return 1;
}
