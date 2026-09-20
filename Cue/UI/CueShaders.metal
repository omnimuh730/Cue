#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// SwiftUI `colorEffect` shaders. Colors arrive premultiplied; every function keeps the alpha it
// was given so the effect stays inside the glyph or shape it is applied to.

static float cueHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

/// Aurora: a field of drifting pastel light. It is the material of Cue's orb and of the glow
/// that rings the composer while a reply streams. `energy` 0 is a slow idle drift, 1 a quick,
/// bright flow; `tilt` (−1…1 per axis) shifts the field with the viewing angle. `rounded` 1
/// clips the field to the circle inscribed in `bounds` and shades it as a sphere: a glassy core
/// and a darker rim. 0 keeps whatever shape the effect is drawn on.
[[ stitchable ]] half4 cueAurora(float2 position, half4 color, float4 bounds, float time, float2 tilt, float energy, float rounded) {
    if (color.a <= 0.002h) { return color; }
    float2 uv = ((position - bounds.xy) / max(bounds.zw, float2(1.0))) * 2.0 - 1.0;
    float r = length(uv);
    float t = time * (0.28 + energy * 1.1);
    float3 palette[5] = {
        float3(0.99, 0.56, 0.82),   // pink
        float3(0.63, 0.52, 1.00),   // violet
        float3(0.42, 0.74, 1.00),   // sky
        float3(1.00, 0.79, 0.58),   // peach
        float3(0.56, 0.95, 0.90)    // mint
    };
    float3 acc = float3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float a = t * (0.55 + 0.17 * fi) + fi * 1.9;
        float b = t * (0.41 + 0.13 * fi) + fi * 0.7;
        float2 d = uv - (float2(cos(a), sin(b)) * 0.62 + tilt * 0.35);
        float w = exp(-dot(d, d) * 2.2);
        acc += palette[i] * w;
        wsum += w;
    }
    float3 col = mix(acc / max(wsum, 0.0005), float3(1.0), 0.10 + 0.18 * energy);
    float alpha = 1.0;
    if (rounded > 0.5) {
        col = mix(col, float3(1.0), 0.22 * (1.0 - smoothstep(0.0, 0.75, r)));
        col *= 1.0 - 0.22 * smoothstep(0.55, 1.0, r);
        alpha = 1.0 - smoothstep(0.93, 1.0, r);
    }
    alpha *= float(color.a);
    return half4(half3(col * alpha), half(alpha));
}

/// The aurora field shaped as a glowing ring around a rounded rectangle inset `inset` points
/// from `bounds` with corner radius `radius`: one pass, no blur. The glow falls off over `spread`
/// points on both sides of the edge, with a crisp hairline on the edge itself.
[[ stitchable ]] half4 cueAuroraRing(float2 position, half4 color, float4 bounds, float time, float radius, float inset, float spread) {
    float2 half_size = bounds.zw * 0.5 - inset;
    float2 centered = position - bounds.xy - bounds.zw * 0.5;
    float2 q = abs(centered) - half_size + radius;
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float d = abs(distance);
    float glow = exp(-d / spread) * 0.55 + exp(-d * 1.6) * 0.5;
    if (glow < 0.004) { return half4(0.0h); }
    float2 uv = ((position - bounds.xy) / max(bounds.zw, float2(1.0))) * 2.0 - 1.0;
    float t = time * 1.35;
    float3 palette[5] = {
        float3(0.99, 0.56, 0.82),
        float3(0.63, 0.52, 1.00),
        float3(0.42, 0.74, 1.00),
        float3(1.00, 0.79, 0.58),
        float3(0.56, 0.95, 0.90)
    };
    float3 acc = float3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float a = t * (0.55 + 0.17 * fi) + fi * 1.9;
        float b = t * (0.41 + 0.13 * fi) + fi * 0.7;
        float2 dd = uv - float2(cos(a), sin(b)) * 0.9;
        float w = exp(-dot(dd, dd) * 1.4);
        acc += palette[i] * w;
        wsum += w;
    }
    float3 col = mix(acc / max(wsum, 0.0005), float3(1.0), 0.28);
    float alpha = min(glow, 1.0);
    return half4(half3(col * alpha), half(alpha));
}

/// A soft band of light sweeping left to right once per `progress` cycle (0…1).
[[ stitchable ]] half4 cueShimmer(float2 position, half4 color, float4 bounds, float progress, float strength) {
    if (color.a <= 0.002h) { return color; }
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    float band = uv.x + uv.y * 0.15;
    float center = mix(-0.35, 1.35, progress);
    float glow = smoothstep(0.28, 0.0, abs(band - center)) * strength;
    half3 rgb = color.rgb + half3(glow) * color.a;
    return half4(min(rgb, half3(color.a)), color.a);
}

/// Pinpoint glints that twinkle at fixed spots inside the shape. `time` drives their life cycle;
/// `strength` is the peak brightness, which the caller fades to zero to end a burst.
[[ stitchable ]] half4 cueSparkle(float2 position, half4 color, float4 bounds, float time, float strength) {
    if (color.a <= 0.002h || strength <= 0.001) { return color; }
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    float glow = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float phase = fract(time * 0.9 + cueHash(float2(fi, 3.1)));
        float life = sin(phase * 3.14159);
        float2 spot = 0.18 + 0.64 * float2(cueHash(float2(fi, 1.7)), cueHash(float2(fi, 9.2)));
        float2 d = (uv - spot) * bounds.zw;
        float core = exp(-length(d) * 0.9);
        float rays = 0.55 * (exp(-abs(d.x) * 0.45 - abs(d.y) * 1.6) + exp(-abs(d.y) * 0.45 - abs(d.x) * 1.6));
        glow += (core + rays) * life;
    }
    half3 rgb = color.rgb + half3(glow * strength) * color.a;
    return half4(min(rgb, half3(color.a)), color.a);
}
