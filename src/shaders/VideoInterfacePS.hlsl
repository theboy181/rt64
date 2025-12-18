//
// RT64
//

#include "shared/rt64_video_interface.h"

[[vk::push_constant]] ConstantBuffer<VideoInterfaceCB> gConstants : register(b0);
Texture2D<float4> gInput : register(t1);
SamplerState gSampler : register(s2);

// Limit texture sampling to the area the VI can sample of the texture.

float4 SampleInput(float2 uv) {
    const float2 LowerRight = gConstants.videoResolution / gConstants.textureResolution;
    const float2 HalfPixel = float2(0.5f, 0.5f) / gConstants.textureResolution;
    float2 outsideBorder = step(LowerRight - HalfPixel, uv);
    float4 sampledColor = gInput.SampleLevel(gSampler, clamp(uv, HalfPixel, LowerRight - HalfPixel), 0);
    float4 gammaCorrectedColor = pow(sampledColor, gConstants.gamma);
    gammaCorrectedColor.rgb *= max(1.0f - outsideBorder.x - outsideBorder.y, 0.0f);
    gammaCorrectedColor.a = 1.0f;
    return gammaCorrectedColor;
}

#ifdef CRT_EFFECT
float3 ApplyCrt(float3 rgb, float2 uvNorm) {
    // Entire CRT overlay is gated by bit 0.
    if ((gConstants.viFlags & 1u) == 0u) {
        return rgb;
    }

    // Drive the CRT mask by the VI's effective resolution, but clamp to at least 1280x960 (2x 640x480)
    // to keep scanlines/triads from looking too low-res at 1x.
    float crtGridW = max(round(gConstants.videoResolution.x), 640.0f);
    float crtGridH = max(round(gConstants.videoResolution.y), 480.0f);

    float2 uvSat = saturate(uvNorm);
    float xFine = uvSat.x * crtGridW;
    float yFine = uvSat.y * crtGridH;

    uint crtX = (uint)floor(xFine);
    uint crtY = (uint)floor(yFine);

    // Smooth scanlines (cosine-shaped), alternating every line at the target grid.
    const float pi = 3.14159265f;
    float scanStrength = 0.50f;
    float scan = 1.0f - scanStrength * (0.5f + 0.5f * cos(pi * yFine));
    rgb *= scan;

    float triad = float(crtX % 3u);
    float3 mask =
        (triad < 1.0f) ? float3(1.05f, 0.95f, 0.95f) :
        (triad < 2.0f) ? float3(0.95f, 1.05f, 0.95f) :
                         float3(0.95f, 0.95f, 1.05f);
    rgb *= lerp(1.0f.xxx, mask, 0.25f);

    float2 v = uvNorm * (1.0f - uvNorm);
    float vignette = saturate(16.0f * v.x * v.y);
    rgb *= lerp(0.90f, 1.0f, vignette);

    return rgb;
}
#endif

//
// Sourced from https://www.shadertoy.com/view/csX3RH
//
float4 PixelAntialiasing(float2 uv) {
    float2 uvTexspace = uv * gConstants.videoResolution;
    float2 seam = floor(uvTexspace + 0.5f);
    uvTexspace = (uvTexspace - seam) / fwidth(uvTexspace) + seam;
    uvTexspace = clamp(uvTexspace, seam - 0.5f, seam + 0.5f);
    return SampleInput(uvTexspace / gConstants.textureResolution);
}

float4 PSMain(in float4 pos : SV_Position, in float2 uv : TEXCOORD0) : SV_TARGET {
    // Fullscreen triangle UVs are set to 0..2 at the vertices, but interpolate to 0..1 over the viewport.
    float2 uvNorm = uv;

    // Horizontal overscan crop (in output screen pixels) to hide edge artifacts (GlideN64-style).
    // Crops `cropPixels` from both the left and right sides, regardless of VI resolution.
    const float cropPixels = 20.0f;
    float viewportWidth = max(round(rcp(fwidth(uv.x))), 1.0f);
    float crop = cropPixels / viewportWidth;
    uvNorm.x = uvNorm.x * (1.0f - 2.0f * crop) + crop;
    float2 uvCropped = uvNorm;
#ifdef PIXEL_ANTIALIASING
    float4 color = PixelAntialiasing(uvCropped);
#ifdef CRT_EFFECT
    color.rgb = ApplyCrt(color.rgb, uvNorm);
#endif
    return color;
#else
    float4 color = SampleInput((uvCropped / gConstants.textureResolution) * gConstants.videoResolution);
#ifdef CRT_EFFECT
    color.rgb = ApplyCrt(color.rgb, uvNorm);
#endif
    return color;
#endif
}
