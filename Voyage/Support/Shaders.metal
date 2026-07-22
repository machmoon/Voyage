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

// MARK: - Airport world renderer

struct AirportWorldUniforms {
    float2 viewport;
    float elapsed;
    float roll;
    float climb;
    float pitch;
    float bank;
    float clouds;
    float visibility;
    float airport;
    float profile;
    float leftSide;
    float wet;
    float night;
};

struct AirportWorldVertexOut { float4 position [[position]]; };

vertex AirportWorldVertexOut airport_world_vertex(uint id [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    AirportWorldVertexOut out;
    out.position = float4(positions[id], 0.0, 1.0);
    return out;
}

static float worldHash(float2 p) { return fract(sin(dot(p, float2(41.31, 289.17))) * 43758.54); }

fragment float4 airport_world_fragment(AirportWorldVertexOut in [[stage_in]],
                                       constant AirportWorldUniforms &u [[buffer(0)]]) {
    float2 uv = in.position.xy / max(u.viewport, float2(1.0));
    uv.x = u.leftSide > 0.5 ? 1.0 - uv.x : uv.x;
    float horizon = mix(0.56, 0.35, u.climb);
    float3 skyDay = mix(float3(0.32, 0.52, 0.72), float3(0.72, 0.86, 0.94), uv.y);
    float3 sky = mix(skyDay, float3(0.02, 0.04, 0.10), u.night * 0.9);
    float3 color = sky;

    // Ground world: runway shoulder, grass, airport massing and runway markings.
    if (uv.y > horizon) {
        float groundT = (uv.y - horizon) / max(0.001, 1.0 - horizon);
        float3 grass = mix(float3(0.13, 0.25, 0.15), float3(0.08, 0.14, 0.10), groundT);
        float3 asphalt = u.wet > 0.5 ? float3(0.07, 0.09, 0.11) : float3(0.13, 0.14, 0.15);
        float runwayHalfWidth = mix(0.20, 0.88, groundT);
        float runwayCenter = 0.5 + u.bank * 0.025;
        float runwayMask = smoothstep(runwayHalfWidth + 0.015, runwayHalfWidth - 0.015, abs(uv.x - runwayCenter));
        color = mix(grass, asphalt, runwayMask);
        float motion = (uv.y * 35.0 + u.elapsed * (4.0 + u.roll * 20.0));
        float marking = step(0.94, fract(motion)) * step(abs(uv.x - runwayCenter), runwayHalfWidth * 0.11);
        color = mix(color, float3(0.88), marking * runwayMask * (1.0 - u.climb));
        float edge = smoothstep(0.022, 0.0, abs(abs(uv.x - runwayCenter) - runwayHalfWidth));
        color += edge * float3(0.38, 0.33, 0.20);
    }

    // Terminal and hangar silhouettes stay close to the horizon, making every supported airport legible.
    float buildingBand = smoothstep(horizon + 0.035, horizon - 0.015, uv.y);
    float buildingNoise = step(0.48, worldHash(floor(float2(uv.x * 20.0 + u.airport, u.airport))));
    float buildingHeight = (0.025 + worldHash(floor(float2(uv.x * 16.0, u.airport))) * 0.075) * buildingNoise;
    float building = step(horizon - buildingHeight, uv.y) * buildingBand;
    float3 terminal = mix(float3(0.20, 0.22, 0.23), float3(0.31, 0.35, 0.37), fract(u.airport * 0.23));
    color = mix(color, terminal, building);

    // SFO gets a broader bay and distant skyline, with two authored profile compositions.
    if (u.airport > 2.5 && u.airport < 3.5) {
        float bayStart = horizon + 0.025;
        float bay = smoothstep(bayStart + 0.18, bayStart, uv.y) * step(uv.x, u.profile > 0.5 ? 0.56 : 0.72);
        color = mix(color, mix(float3(0.12, 0.35, 0.48), float3(0.30, 0.57, 0.67), uv.y), bay * (1.0 - u.climb * 0.45));
        float skylineX = u.profile > 0.5 ? 0.63 : 0.78;
        float skyline = step(abs(uv.x - skylineX), 0.13) * step(horizon - 0.10, uv.y) * step(uv.y, horizon - 0.015);
        color = mix(color, float3(0.16, 0.19, 0.22), skyline);
    }

    // Cloud deck enters in front of the camera during climb; low visibility makes it arrive earlier.
    float cloudLine = mix(0.18, 0.68, u.climb) - (1.0 - u.visibility) * 0.18;
    float cloudNoise = fbm(uv * 6.5 + float2(u.elapsed * 0.03, u.elapsed * 0.01));
    float cloud = smoothstep(cloudLine - 0.16, cloudLine + 0.16, uv.y + (cloudNoise - 0.5) * 0.20);
    cloud *= smoothstep(0.10, 0.65, u.clouds);
    color = mix(color, mix(float3(0.78, 0.83, 0.86), float3(0.37, 0.43, 0.52), u.night), cloud * 0.82);
    color *= mix(0.62, 1.0, u.visibility);
    return float4(color, 1.0);
}

// MARK: - Continuous real-world window layers

/// Deterministic screen-space atmosphere composited over streamed terrain.
/// The map provider owns geographic depth; this shader owns cloud passage,
/// undercast, visibility haze, precipitation and day/night colour. Output is
/// premultiplied so it can sit over either Google or Apple imagery unchanged.
[[ stitchable ]] half4 flightAtmosphere(float2 position, half4 color,
                                        float2 viewport, float elapsed,
                                        float cloudAmount, float visibility,
                                        float altitude, float phase,
                                        float phaseProgress, float precipitation,
                                        float night, float golden) {
    float2 size = max(viewport, float2(1.0));
    float2 uv = position / size;
    float aspect = size.x / size.y;
    float2 p = float2(uv.x * aspect, uv.y);
    float t = fmod(max(0.0, elapsed), 4096.0);

    // Three offset noise fields read as depth while remaining inexpensive on
    // a phone-sized clipped window.
    float farNoise = fbm(p * 3.1 + float2(t * 0.004, -t * 0.001));
    float midNoise = fbm(p * 6.4 + float2(t * 0.010, t * 0.002));
    float nearNoise = fbm(p * 12.2 + float2(t * 0.022, -t * 0.006));
    float volume = farNoise * 0.48 + midNoise * 0.34 + nearNoise * 0.18;

    float isClimb = 1.0 - step(0.5, abs(phase - 1.0));
    float isCruise = 1.0 - step(0.5, abs(phase - 2.0));
    float isDescent = 1.0 - step(0.5, abs(phase - 3.0));
    float isGround = max(1.0 - step(0.5, abs(phase)),
                         1.0 - step(0.5, abs(phase - 4.0)));

    // Passing through a layer is strongest during the middle of climb or
    // descent. At cruise, keep the cloud deck below the aircraft so clear
    // terrain and mountains remain readable above it.
    float passage = smoothstep(0.08, 0.34, phaseProgress)
                  * (1.0 - smoothstep(0.64, 0.92, phaseProgress));
    float passageDensity = max(isClimb, isDescent) * passage;
    float cloudThreshold = mix(0.78, 0.46, saturate(cloudAmount));
    float cloudMask = smoothstep(cloudThreshold - 0.10, cloudThreshold + 0.12, volume);
    float cruiseDeck = smoothstep(0.54 + altitude * 0.08, 0.92, uv.y)
                     * smoothstep(cloudThreshold - 0.18, cloudThreshold + 0.08,
                                  farNoise * 0.62 + midNoise * 0.38);
    float groundCloud = isGround * smoothstep(0.76, 0.98, cloudAmount)
                      * smoothstep(0.72, 0.92, volume) * 0.34;
    float cloudAlpha = cloudMask * passageDensity * saturate(cloudAmount * 1.15)
                     + cruiseDeck * isCruise * saturate(cloudAmount * 0.82)
                     + groundCloud;
    cloudAlpha = saturate(cloudAlpha * mix(0.60, 0.96, visibility));

    float3 dayCloud = mix(float3(0.68, 0.73, 0.79), float3(0.98, 0.99, 1.0), farNoise);
    float3 nightCloud = mix(float3(0.09, 0.13, 0.22), float3(0.31, 0.38, 0.52), farNoise);
    float3 goldenCloud = mix(float3(0.88, 0.48, 0.30), float3(1.0, 0.86, 0.69), farNoise);
    float3 cloudColor = mix(dayCloud, goldenCloud, saturate(golden));
    cloudColor = mix(cloudColor, nightCloud, saturate(night));

    // Visibility haze grows toward the horizon/topographic distance. Keep
    // clear samples nearly transparent rather than washing out real terrain.
    float horizonBand = 1.0 - smoothstep(0.38, 0.88, uv.y);
    float hazeAlpha = (1.0 - saturate(visibility)) * (0.10 + horizonBand * 0.34);
    hazeAlpha += cloudAmount * 0.018 * horizonBand;
    float3 hazeColor = mix(float3(0.73, 0.84, 0.91), float3(0.11, 0.16, 0.27), night);
    hazeColor = mix(hazeColor, float3(0.94, 0.61, 0.40), golden * 0.42);

    // Rain/storm streaks and snow flakes are deterministic functions of pixel
    // position and elapsed trajectory time. They disappear above the weather.
    float weatherExposure = max(isGround, max(isClimb * (1.0 - altitude),
                                               isDescent * (1.0 - altitude)));
    float rain = 0.0;
    float snow = 0.0;
    if (precipitation > 0.5 && weatherExposure > 0.01) {
        float lane = floor(uv.x * 72.0);
        float laneSeed = hash21(float2(lane, 17.0));
        float rainY = fract(uv.y * 2.1 - t * (1.2 + laneSeed) + laneSeed);
        float rainX = abs(fract(uv.x * 72.0 + uv.y * 7.0) - 0.5);
        float rainKind = step(0.5, precipitation) * (1.0 - step(1.5, precipitation))
                       + step(2.5, precipitation);
        rain = smoothstep(0.035, 0.0, rainX) * smoothstep(0.22, 0.0, rainY)
             * rainKind;

        float2 snowCell = floor(float2(uv.x * 34.0, uv.y * 34.0));
        float snowSeed = hash21(snowCell);
        float2 snowUV = fract(float2(uv.x * 34.0 + sin(t + snowSeed * 9.0) * 0.22,
                                     uv.y * 34.0 - t * (0.25 + snowSeed * 0.18))) - 0.5;
        float snowKind = step(1.5, precipitation) * (1.0 - step(2.5, precipitation));
        snow = smoothstep(0.16, 0.02, length(snowUV)) * snowKind;
    }
    float lightning = step(2.5, precipitation)
                    * step(0.982, hash21(float2(floor(t * 1.7), 91.0)))
                    * (1.0 - uv.y) * weatherExposure;

    float alpha = saturate(cloudAlpha + hazeAlpha + (rain * 0.34 + snow * 0.68) * weatherExposure);
    float3 rgb = mix(hazeColor, cloudColor, saturate(cloudAlpha / max(alpha, 0.001)));
    rgb = mix(rgb, float3(0.72, 0.84, 1.0), rain * 0.28);
    rgb += lightning * float3(0.72, 0.79, 1.0);
    alpha = saturate(alpha + lightning * 0.44);
    return half4(half3(rgb * alpha), half(alpha));
}

/// Analytically lit camera-relative wing. The shape is deliberately rendered
/// as its own transparent layer so map depth and provider attribution remain
/// untouched. A rough dielectric BRDF gives the painted aluminium a stable
/// highlight without the cost of a second 3D scene.
[[ stitchable ]] half4 passengerWing(float2 position, half4 color,
                                     float2 viewport, float side,
                                     float bank, float night, float elapsed) {
    float2 uv = position / max(viewport, float2(1.0));
    if (side < 0.5) { uv.x = 1.0 - uv.x; }

    // Shallow sweep from a root below the sill: a steeper rise reads as a
    // blade laid across the view rather than a wing attached to a fuselage.
    float root = 1.06 - uv.x * 0.26 + bank * 0.0022;
    // The chord narrows outboard but never to a point — a real wingtip is a
    // blunt slab, and tapering to zero is what makes this look like a dagger.
    float thickness = mix(0.085, 0.030, smoothstep(0.05, 0.92, uv.x));
    float leading = root - thickness * 0.58;
    float trailing = root + thickness;
    float spanMask = smoothstep(0.035, 0.09, uv.x) * (1.0 - smoothstep(0.86, 0.90, uv.x));
    float wingMask = smoothstep(0.012, -0.006, leading - uv.y)
                   * smoothstep(0.014, -0.005, uv.y - trailing) * spanMask;

    // Upturned winglet: a raked blade standing off the blunt tip.
    float tipRoot = 1.06 - 0.88 * 0.26 + bank * 0.0022;
    // Short and blade-like. Tall and thin reads as an antenna, not a winglet.
    float wgT = saturate((tipRoot - uv.y) / 0.062);           // 0 at tip, 1 at top
    float wgCenter = 0.885 + wgT * 0.022;                     // rake aft with height
    float wgHalf = mix(0.020, 0.013, wgT);
    float wingletMask = smoothstep(wgHalf, wgHalf * 0.55, abs(uv.x - wgCenter))
                      * step(uv.y, tipRoot + 0.02) * smoothstep(-0.02, 0.06, wgT)
                      * (1.0 - smoothstep(0.93, 1.0, wgT));

    // Rounded engine nacelle below the inboard wing.
    float2 engineP = (uv - float2(0.30, root + 0.105)) / float2(0.125, 0.060);
    float engineMask = smoothstep(1.0, 0.86, dot(engineP, engineP));

    float normalZ = sqrt(saturate(1.0 - pow((uv.y - root) / max(thickness, 0.01), 2.0)));
    float ndl = saturate(0.38 + normalZ * 0.62 - bank * 0.012);
    float roughness = 0.24;
    float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(normalZ), 5.0);
    float specular = pow(saturate(normalZ * 0.88 + 0.12), mix(34.0, 8.0, roughness));
    // Painted aluminium seen against bright terrain reads mid-grey, not white.
    // Ceilings matter here: the sheen terms below are small and the result is
    // clamped, because a saturated wing loses all of its shape.
    float3 paint = mix(float3(0.27, 0.30, 0.34), float3(0.55, 0.58, 0.62), ndl);
    paint += (fresnel * 0.10 + specular * 0.12);
    paint = mix(paint, paint * float3(0.28, 0.34, 0.48), night * 0.72);

    float flapLine = smoothstep(0.008, 0.001, abs(uv.y - (root + thickness * 0.48)))
                   * smoothstep(0.18, 0.28, uv.x) * (1.0 - smoothstep(0.72, 0.82, uv.x));
    paint *= 1.0 - flapLine * 0.24;

    float3 engine = mix(float3(0.16, 0.18, 0.21), float3(0.78, 0.81, 0.84), ndl);
    engine = mix(engine, engine * float3(0.24, 0.30, 0.43), night * 0.76);

    // The winglet stands edge-on to the light, so it sits a shade darker than
    // the upper surface — that contrast is what makes the tip read as upturned.
    float3 wingletPaint = mix(float3(0.22, 0.25, 0.29), float3(0.52, 0.56, 0.61),
                              saturate(0.45 + wgT * 0.4));
    wingletPaint = mix(wingletPaint, wingletPaint * float3(0.26, 0.32, 0.45), night * 0.74);

    // Leading edge: brighten the existing paint rather than adding light to it.
    // An additive term here stacks on the sheen above and blows the surface out.
    float edgeBand = smoothstep(0.010, 0.0, abs(uv.y - leading)) * spanMask;
    paint = mix(paint, min(paint * 1.35 + 0.06, float3(0.88)), edgeBand * (1.0 - night * 0.6));

    // Nothing on the wing may reach full white; that is what erases its shape.
    paint = min(paint, float3(0.70));
    wingletPaint = min(wingletPaint, float3(0.64));

    float strobePhase = fmod(max(0.0, elapsed), 1.35);
    float strobe = (step(strobePhase, 0.055) + step(0.13, strobePhase) * step(strobePhase, 0.19));
    float tipGlow = smoothstep(0.030, 0.0,
                               length(uv - float2(0.905, tipRoot - 0.058))) * strobe;

    float surfaces = saturate(wingMask + wingletMask);
    float alpha = saturate(surfaces * 0.98 + engineMask * 0.96 + tipGlow * 0.72);
    float3 metal = mix(wingletPaint, paint, saturate(wingMask / max(surfaces, 0.001)));
    float3 rgb = mix(engine, metal, saturate(surfaces / max(alpha, 0.001)));
    rgb += tipGlow * float3(1.0, 0.96, 0.88) * 1.8;
    return half4(half3(rgb * alpha), half(alpha));
}
