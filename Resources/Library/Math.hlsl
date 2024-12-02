#pragma once
#include "Assets/Resources/Library/Macros.hlsl"

float Square(float x)
{
    return x * x;
}

float2 Square(float2 x)
{
    return x * x;
}

float3 Square(float3 x)
{
    return x * x;
}

float4 Square(float4 x)
{
    return x * x;
}

float pow2(float x)
{
    return x * x;
}

float2 pow2(float2 x)
{
    return x * x;
}

float3 pow2(float3 x)
{
    return x * x;
}

float4 pow2(float4 x)
{
    return x * x;
}

float pow3(float x)
{
    return x * x * x;
}

float2 pow3(float2 x)
{
    return x * x * x;
}

float3 pow3(float3 x)
{
    return x * x * x;
}

float4 pow3(float4 x)
{
    return x * x * x;
}

float pow4(float x)
{
    float xx = x * x;
    return xx * xx;
}

float2 pow4(float2 x)
{
    float2 xx = x * x;
    return xx * xx;
}

float3 pow4(float3 x)
{
    float3 xx = x * x;
    return xx * xx;
}

float4 pow4(float4 x)
{
    float4 xx = x * x;
    return xx * xx;
}

float pow5(float x)
{
    float xx = x * x;
    return xx * xx * x;
}

float2 pow5(float2 x)
{
    float2 xx = x * x;
    return xx * xx * x;
}

float3 pow5(float3 x)
{
    float3 xx = x * x;
    return xx * xx * x;
}

float4 pow5(float4 x)
{
    float4 xx = x * x;
    return xx * xx * x;
}

float pow6(float x)
{
    float xx = x * x;
    return xx * xx * xx;
}

float2 pow6(float2 x)
{
    float2 xx = x * x;
    return xx * xx * xx;
}

float3 pow6(float3 x)
{
    float3 xx = x * x;
    return xx * xx * xx;
}

float4 pow6(float4 x)
{
    float4 xx = x * x;
    return xx * xx * xx;
}
inline half min3(half a, half b, half c)
{
    return min(min(a, b), c);
}

inline half max3(half a, half b, half c)
{
    return max(a, max(b, c));
}

inline half4 min3(half4 a, half4 b, half4 c)
{
    return half4(
        min3(a.x, b.x, c.x),
        min3(a.y, b.y, c.y),
        min3(a.z, b.z, c.z),
        min3(a.w, b.w, c.w));
}

inline half4 max3(half4 a, half4 b, half4 c)
{
    return half4(
        max3(a.x, b.x, c.x),
        max3(a.y, b.y, c.y),
        max3(a.z, b.z, c.z),
        max3(a.w, b.w, c.w));
}

inline half acosFast(half inX)
{
    half x = abs(inX);
    half res = -0.156583f * x + (0.5 * PI);
    res *= sqrt(1 - x);
    return (inX >= 0) ? res : PI - res;
}

inline half asinFast(half x)
{
    return (0.5 * PI) - acosFast(x);
}

inline float linearstep(float min, float max, float value)
{
    return clamp((value - min) / (max - min), 0.0, 1.0);
}

float Unity_SphereMask_float4(float2 uv, float2 Center, float Radius, float Hardness)
{
    return 1 - saturate((distance(uv, Center) - Radius) / (1 - Hardness));
}

float2 Unity_Rotate_Degrees_float(float2 UV, float2 Center, float Rotation)
{
    Rotation = Rotation * (3.1415926f/180.0f);
    UV -= Center;
    float s = sin(Rotation);
    float c = cos(Rotation);
    float2x2 rMatrix = float2x2(c, -s, s, c);
    rMatrix *= 0.5;
    rMatrix += 0.5;
    rMatrix = rMatrix * 2 - 1;
    UV.xy = mul(UV.xy, rMatrix);
    UV += Center;
    
    return UV;
}