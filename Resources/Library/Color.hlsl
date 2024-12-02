#pragma once

inline float Luma4(float3 Color)
{
    return (Color.g * 2.0) + (Color.r + Color.b);
}
inline float3 Luma(float3 Color)
{
    return dot( Color, float3( 0.3, 0.59, 0.11 ) );
}

float3 TransformRGB2YCoCg(float3 c)
{
    // Y  = R/4 + G/2 + B/4
    // Co = R/2 - B/2
    // Cg = -R/4 + G/2 - B/4
    return float3(
         c.x / 4.0 + c.y / 2.0 + c.z / 4.0,
         c.x / 2.0 - c.z / 2.0,
        -c.x / 4.0 + c.y / 2.0 - c.z / 4.0
    );
}
float3 TransformYCoCg2RGB(float3 c)
{
    // R = Y + Co - Cg
    // G = Y + Cg
    // B = Y - Co - Cg
    return saturate(float3(
        c.x + c.y - c.z,
        c.x + c.z,
        c.x - c.y - c.z
    ));
}

/// 计算权重值，用于调整颜色亮度以适应HDR显示
//  Exposure : 调整亮度计算结果
inline half HDRWeight4(half3 Color, half Exposure)
{
    return rcp(Luma4(Color) * Exposure + 4);
}
