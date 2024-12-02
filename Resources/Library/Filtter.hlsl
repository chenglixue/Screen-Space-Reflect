#pragma once
#include "Assets/Resources/Library/Common.hlsl"

void SampleDepth3x3(Texture2D<float> depthTex, float2 uv, float2 duv,
    out float depths[9])
{
    float du = duv.x;
    float dv = duv.y;

    const float2 offsetUV[9] =
    {
        {-du, dv}, {0, dv}, {du, dv},
        {-du, 0}, {0, 0}, {du, 0},
        {-du, -dv}, {0, -dv}, {du, -dv}
    };

    [unroll]
    for(int i = 0; i < 9; ++i)
    {
        half depth = depthTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv + offsetUV[i], 0);
        depths[i] = depth;
    }
}
void SampleDepthCross(Texture2D<float> depthTex, float2 uv, float2 duv,
    out float depths[5])
{
    float du = duv.x;
    float dv = duv.y;

    const float2 offsetUV[5] =
    {
        {0, dv}, 
{-du, 0}, {0, 0}, {du, 0},
        {0, -dv}, 
};

    [unroll]
    for(int i = 0; i < 5; ++i)
    {
        half depth = depthTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv + offsetUV[i], 0);
        depths[i] = depth;
    }
}

void SampleColor3x3(Texture2D<float4> colorTex, float2 uv, float2 duv,
    out float3 colors[9])
{
    float du = duv.x;
    float dv = duv.y;

    const float2 offsetUV[9] =
    {
        {-du, dv}, {0, dv}, {du, dv},
        {-du, 0}, {0, 0}, {du, 0},
        {-du, -dv}, {0, -dv}, {du, -dv}
    };

    [unroll]
    for(int i = 0; i < 9; ++i)
    {
        half3 color = colorTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv + offsetUV[i], 0);
        colors[i] = color;
    }
}
void SampleColorCross(Texture2D<float4> colorTex, float2 uv, float2 duv,
    out float3 colors[5])
{
    float du = duv.x;
    float dv = duv.y;

    const float2 offsetUV[5] =
    {
        {0, dv}, 
{-du, 0}, {0, 0}, {du, 0},
        {0, -dv},
};

    [unroll]
    for(int i = 0; i < 5; ++i)
    {
        half3 color = colorTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv + offsetUV[i], 0);
        colors[i] = color;
    }
}

float2 SampleClosestUV3x3(Texture2D<float> depthTex, float2 uv, float2 duv)
{
    float depths[9];
    SampleDepth3x3(depthTex, uv, duv, depths);

    float du = duv.x;
    float dv = duv.y;

    #if UNITY_REVERSED_Z
    half minDepth = HALF_MIN;
    #else
    half minDepth = HALF_MAX;
    #endif
    float2 minUV = uv;
    const float2 offsetUV[9] =
    {
        {-du, dv}, {0, dv}, {du, dv},
        {-du, 0}, {0, 0}, {du, 0},
        {-du, -dv}, {0, -dv}, {du, -dv}
    };

    [unroll]
    for(int i = 0; i < 9; ++i)
    {
        #if UNITY_REVERSED_Z
        const float lerpFactor = step(minDepth, depths[i].r);
        #else
        const float lerpFactor = step(depths[i].r, minDepth);
        #endif

        minDepth = lerp(minDepth, depths[i], lerpFactor);
        minUV = lerp(minUV, minUV + offsetUV[i], lerpFactor);
    }

    return minUV;
}
float2 SampleClosestUVCross(Texture2D<float> depthTex, float2 uv, float2 duv)
{
    float depths[5];
    SampleDepthCross(depthTex, uv, duv, depths);

    float du = duv.x;
    float dv = duv.y;

    #if UNITY_REVERSED_Z
    half minDepth = HALF_MIN;
    #else
    half minDepth = HALF_MAX;
    #endif
    float2 minUV = uv;
    const float2 offsetUV[5] =
    {
        {0, dv}, 
{-du, 0}, {0, 0}, {du, 0},
        {0, -dv}, 
};

    [unroll]
    for(int i = 0; i < 5; ++i)
    {
        #if UNITY_REVERSED_Z
        const float lerpFactor = step(minDepth, depths[i].r);
        #else
        const float lerpFactor = step(depths[i].r, minDepth);
        #endif

        minDepth = lerp(minDepth, depths[i], lerpFactor);
        minUV = lerp(minUV, minUV + offsetUV[i], lerpFactor);
    }

    return minUV;
}

half3 ClampBox(half3 historyColor, half3 minColor, half3 maxColor)
{
    return clamp(historyColor, minColor, maxColor);
}
half3 ClipBox(half3 currColor, half3 minColor, half3 maxColor)
{
    half3 averageColor = (minColor + maxColor) * 0.5f;
    
    half3 toEdgeVec = (maxColor - minColor) * 0.5f;
    half3 toCurrVec = currColor - averageColor;
    half3 unitVec = abs(toCurrVec / max(toEdgeVec, HALF_EPS));
    float unit = max(unitVec.x, max(unitVec.y, max(unitVec.z, HALF_EPS)));
    
    half3 o = lerp(currColor, averageColor + toCurrVec / unit, step(1.f, unit));
    return o;
}
half3 VarianceClipBox(half3 colorMin, half3 colorMax)
{
    half3 averageColor = (colorMin + colorMax) * 0.5f;

    float3 p_clip = 0.5 * (colorMax + colorMin);
    float3 e_clip = 0.5 * (colorMax - colorMin) + FLT_EPS;
    float3 v_clip = colorMax - p_clip;
    float3 v_unit = v_clip / e_clip;
    float3 a_unit = abs(v_unit);
    float ma_unit = max(a_unit.x, max(a_unit.y, a_unit.z));

    if (ma_unit > 1.0)
        return p_clip + v_clip / ma_unit;
    else
        return averageColor;
}

inline float2 GetCameraMotionVector(float rawDepth, float2 uv,
    float4x4 Matrix_I_VP, float4x4 _Pre_Matrix_VP, float4x4 Matrix_VP)
{
    float4 positionNDC = GetPositionNDC(uv, rawDepth);
    float4 positionWS  = TransformNDCToWS(positionNDC, Matrix_I_VP);

    float4 currPosCS = mul(Matrix_VP, positionWS);
    float4 prePosCS  = mul(_Pre_Matrix_VP, positionWS);

    float2 currPositionSS = currPosCS.xy / currPosCS.w;
    currPositionSS = (currPositionSS + 1) * 0.5f;
    float2 prePositionSS  = prePosCS.xy / prePosCS.w;
    prePositionSS  = (prePositionSS + 1) * 0.5f;

    return currPositionSS - prePositionSS;
}

inline void ResolverAABB(Texture2D<float4> currColor, float ExposureScale, float AABBScale, float2 uv,
    inout float Variance, inout float4 MinColor, inout float4 MaxColor, inout float4 FilterColor)
{
    const int2 sampleOffset[9] =
    {
        int2(-1.0, -1.0), int2(0.0, -1.0), int2(1.0, -1.0), int2(-1.0, 0.0), int2(0.0, 0.0), int2(1.0, 0.0), int2(-1.0, 1.0), int2(0.0, 1.0), int2(1.0, 1.0)
    };

    float4 sampleColors[9];
    for(uint i = 0; i < 9; ++i)
    {
        sampleColors[i] = currColor.SampleLevel(Smp_ClampU_ClampV_Linear, uv + sampleOffset[i], 0);
    }

    float sampleWeight[9];
    for(uint i = 0; i < 9; ++i)
    {
        sampleWeight[i] = HDRWeight4(sampleColors[i].rgb, ExposureScale);
    }

    float totalWeight = 0.f;
    for(uint i = 0; i < 9; ++i)
    {
        totalWeight += sampleWeight[i];
    }

    sampleColors[4] = (sampleColors[0] * sampleWeight[0] + sampleColors[1] * sampleWeight[1] + sampleColors[2] * sampleWeight[2]
        + sampleColors[3] * sampleWeight[3] + sampleColors[4] * sampleWeight[4] + sampleColors[5] * sampleWeight[5]
        + sampleColors[6] * sampleWeight[6] + sampleColors[7] * sampleWeight[7] + sampleColors[8] * sampleWeight[8]) * rcp(totalWeight);

    float4 m1 = 0.f, m2 = 0.f;
    for(uint x = 0; x < 9; ++x)
    {
        m1 += sampleColors[x];
        m2 += sampleColors[x] * sampleColors[x];
    }

    float4 mean = m1 * rcp(9.f);
    float4 stddev = sqrt(m2 * rcp(9.f) - pow2(mean));

    MinColor = mean - AABBScale * stddev;
    MaxColor = mean + AABBScale * stddev;

    FilterColor = sampleColors[4];
    MinColor = min(MinColor, FilterColor);
    MaxColor = max(MaxColor, FilterColor);

    float4 totalVariance = 0.f;
    for(uint i = 0; i < 9; ++i)
    {
        totalVariance += pow2(Luminance(sampleColors[i]) - Luminance(mean));
    }

    Variance = saturate(totalVariance / 9.f * 256.f);
    Variance *= FilterColor.a;
}