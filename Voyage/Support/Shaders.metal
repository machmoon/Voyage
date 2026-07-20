#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Value-noise FBM used for the window's atmospheric haze layer.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

/// Soft drifting haze. Applied with `colorEffect` over a plain fill:
/// `density` scales overall opacity, `night` cools the tint.
[[ stitchable ]] half4 atmosphericHaze(float2 position, half4 color,
                                       float time, float density, float night) {
    float2 uv = position / 260.0;
    float n = fbm(uv + float2(time * 0.03, time * 0.008));
    float alpha = smoothstep(0.38, 0.95, n) * density;
    half3 dayTint = half3(1.0, 1.0, 1.0);
    half3 nightTint = half3(0.70, 0.76, 0.94);
    half3 tint = night > 0.5 ? nightTint : dayTint;
    // SwiftUI expects premultiplied alpha — without this the haze
    // renders as an over-bright wash across the whole scene.
    half a = half(alpha) * color.a;
    return half4(tint * a, a);
}
