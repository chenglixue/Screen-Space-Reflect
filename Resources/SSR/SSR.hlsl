#pragma once
#include "Assets/Resources/Library/Common.hlsl"
#include "Assets/Resources/Library/Random.hlsl"

#define HIZ_MIPMAP_LEVELS 5

cbuffer UnityPerMaterial
{
    float4 _ViewSize;
    float4 _BlueNoiseTexSize;
    float4 _RayMarchTexSize;
    float4 _ResolvedTexSize;
    float4 _TAATexSize;
    
    int    _HizMaxStep;
    int    _LinearMaxStep;
    int    _HiZBinaryStep;
    int    _LinearBinaryStep;
    int    _HiZThickness;
    float  _LinearThickness;
    float  _HiZMaxDistance;
    float  _LinearMaxDistance;
    
    float  _MaxRoughness;
    float  _BRDFBias;
    float  _EdgeFade;
    float  _TemporalScale;
    float  _TemporalWeight;
    float  _Brightness;
    static const int2 offset[9] =
    {
        int2(0.0, 0.0),
        int2(2.0, -2.0),
        int2(-2.0, -2.0),
        int2(0.0, 2.0),
        int2(0.0, -2.0),
        int2(-2.0, 0.0),
        int2(2.0, 0.0),
        int2(-2.0, 2.0),
        int2(2.0, 2.0)
    };
}

float4x4 _Pre_Matrix_VP;

Texture2D<float4> _GBuffer0;
Texture2D<float4> _GBuffer1;
Texture2D<float4> _GBuffer2;
Texture2D<float4> _GBuffer3;
Texture2D<float4> _CameraColorTexture;
Texture2D<float>  _CameraDepthTexture;
Texture2D<float2> _MotionVectorTex;

Texture2D<float4> _MainTex;
Texture2D<float> _LowResDepthTex;
Texture2D<float3> _BlueNoiseTex;
Texture2D<float3> _PreIntegratedTex;
Texture2D<float>  _HiZDepthTex0;
Texture2D<float4> _SSRHitDataTex;
Texture2D<float> _SSRHitPDFTex;
Texture2D<float4> _SSRResolvedTex;
Texture2D<float4> _SSRMipmapBlurReflectTex;
Texture2D<float4> _SSRTAAPreTex;
Texture2D<float4> _SSRTAACurrTex;
Texture2D<float4> _UpSampleTex;

struct VSInput
{
    uint   vertexID : SV_VertexID;
    float4 positionOS : POSITION;
    float2 uv         : TEXCOORD0;
};
struct PSInput
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
};
struct PSOutput
{
    float4 color : SV_Target;
};

struct Ray
{
    float3 positionVS;
    float3 directionVS;
};

float4 GetSourceColor(float2 uv)
{
    return _CameraColorTexture.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0);
}
float3 GetAlbedo(float2 uv)
{
    return _GBuffer0.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).rgb;
}
float GetRoughness(float2 uv)
{
    float roughness = _GBuffer1.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).g;
    roughness = clamp(roughness, 0.02, 1);
    return roughness;
}
float GetAO(float2 uv)
{
    return _GBuffer1.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).b;
}
float3 GetReflectProbe(float3 reflectDirWS, float roughness)
{
    float rgh                = roughness * (1.7 - 0.7 * roughness);
    float lod                = 6.f * rgh;
    return SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectDirWS, lod);
}

float GetDeviceDepth(float2 uv)
{
    return _CameraDepthTexture.SampleLevel(Smp_ClampU_ClampV_Point, uv, 0).r;
}
float GetLinearEyeDepth(float rawDepth)
{
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}
float GetHizDepth(float2 uv, int mipLevel)
{
    return _HiZDepthTex0.SampleLevel(Smp_ClampU_ClampV_Linear, uv, mipLevel).r;
}
float GetThicknessDiff(float depthDiff, float linearSampleDepth)
{
    return depthDiff / linearSampleDepth;
}

float3 GetNormalWS(float2 uv)
{
    float3 normal = _GBuffer2.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).xyz;

    return SafeNormalize(normal);
}
float3 GetNormalVS(float3 normalWS)
{
    float3 normalVS = mul(Matrix_V, float4(normalWS, 0.f));
    normalVS = SafeNormalize(normalVS);

    return normalVS;
}
float3 GetViewDir(float3 positionWS)
{
    return normalize(positionWS - _WorldSpaceCameraPos);
}
float3 GerReflectDirWS(float3 invViewDir, float3 normalWS)
{
    float3 reflectDir = reflect(invViewDir, normalWS);
    reflectDir = normalize(reflectDir);

    return reflectDir;
}

float GenerateRandomFloat(float2 screenUV)
{
    float time = unity_DeltaTime.y * _Time.y; // accumulate the noise over time (frames)
    
    return GenerateHashedRandomFloat(uint3(screenUV * _ScreenSize.xy, time));
}

inline half EdgeFade(half2 pos, half value)
{
    half borderDist = min(1 - max(pos.x, pos.y), min(pos.x, pos.y));
    return saturate(borderDist > value ? 1 : borderDist / value);
}

void HiZRayMarching(Ray ray, float jitter,out float4 hitData)
{
    float maxDistance = ray.positionVS.z + ray.directionVS.z * _HiZMaxDistance > -_ProjectionParams.y ?
                    (-_ProjectionParams.y - ray.positionVS.z) / ray.directionVS.z : _HiZMaxDistance;
    float stepSize  = rcp(float(_HizMaxStep));

    float3 startPosVS = ray.positionVS;
    float3 endPosVS   = startPosVS + ray.directionVS * maxDistance;
    float4 startPosCS = mul(Matrix_P, float4(startPosVS, 1.f));
    float4 endPosCS   = mul(Matrix_P, float4(endPosVS, 1.f));
    float  startK     = rcp(startPosCS.w);
    float  endK       = rcp(endPosCS.w);
    float2 startUV    = startPosCS.xy * float2(1.f, -1.f) * startK * 0.5f + 0.5f;
    float2 endUV      = endPosCS.xy * float2(1.f, -1.f) * endK * 0.5f + 0.5f;

    float w0 = 0.f, w1 = 0.f;
    float mask = 0.f;
    int mipLevel = 0;
    bool isHit = false;
    float2 resultUV = 0;
    float resultDepth = 0;
    [loop]
    for(int i = 0; i < _HizMaxStep; ++i)
    {
        w1 = w0;
        w0 += stepSize;

        float  reflectK     = lerp(startK, endK, w0);
        float2 reflectUV    = lerp(startUV, endUV, w0);
        float4 reflectPosCS = lerp(startPosCS, endPosCS, w0);

        if(reflectUV.x < 0.f || reflectUV.y < 0.f || reflectUV.x > 1.f || reflectUV.y > 1.f) break;

        float sceneDepth    = GetHizDepth(reflectUV, mipLevel).r;
        sceneDepth          = GetLinearEyeDepth(sceneDepth);
        float rayDepth      = GetLinearEyeDepth(reflectPosCS.z * reflectK);
        float depthDiff     = rayDepth - sceneDepth;

        [flatten]
        if(depthDiff < 0.f)
        {
            mipLevel = min(mipLevel + 1, HIZ_MIPMAP_LEVELS - 1);
            w0 += stepSize;
        }
        else
        {
            [flatten]
            if(mipLevel <= 0)
            {
                if(i > 0 && depthDiff < _HiZThickness)
                {
                    mask = 1;
                    isHit = true;
                    resultUV = reflectUV;
                    resultDepth = reflectPosCS.z * reflectK;
                    break;
                }
            }
            else
            {
                mipLevel--;
                w0 -= stepSize;
            }
        }
    }

    if(isHit)
    {
        [loop]
        for(int i = 0; i < _HiZBinaryStep; ++i)
        {
            float w = 0.5f * (w0 + w1);
            float3 reflectPosCS = lerp(startPosCS, endPosCS, w);
            float2 reflectUV    = lerp(startUV, endUV, w);
            float  reflectK     = lerp(startK,  endK,  w);

            float sceneDepth    = GetDeviceDepth(reflectUV);
            sceneDepth          = LinearEyeDepth(sceneDepth, _ZBufferParams);
            float rayDepth      = LinearEyeDepth(reflectPosCS.z * reflectK, _ZBufferParams);
            float depthDiff     = rayDepth - sceneDepth;

            // 有交点，w0向w1靠近(深度慢慢缩小)
            [flatten]
            if(depthDiff > 0.f)
            {
                w0 = w;
                resultUV = reflectUV;
                resultDepth = reflectPosCS.z * reflectK;
            }
            // 无交点，交点比w1大，w0小(深度慢慢变大)
            else
            {
                w1 = w;
            }
        }   
    }
    
    hitData = float4(resultUV, resultDepth, mask);
}

void LinearRayMarching(Ray ray, float jitter, out float4 hitData)
{
    float maxDistance = ray.positionVS.z + ray.directionVS.z * _LinearMaxDistance > -_ProjectionParams.y ?
                    (-_ProjectionParams.y - ray.positionVS.z) / ray.directionVS.z : _LinearMaxDistance;
    float stepSize  = rcp(float(_LinearMaxStep));

    float3 startPosVS   = ray.positionVS;
    float3 endPosVS     = startPosVS + ray.directionVS * maxDistance;
    float4 startPosCS   = mul(Matrix_P, float4(startPosVS, 1.f));
    float4 endPosCS     = mul(Matrix_P, float4(endPosVS, 1.f));
    float  startK       = rcp(startPosCS.w);
    float  endK         = rcp(endPosCS.w);
    float2 startUV      = startPosCS.xy * float2(1.f, -1.f) * startK * 0.5f + 0.5f;
    float2 endUV        = endPosCS.xy * float2(1.f, -1.f) * endK * 0.5f + 0.5f;
    float2 resultUV     = 0;
    float resultDepth   = 0;

    float w0 = 0.f, w1 = 0.f;
    float mask = 0.f;
    // isHit:           ray步进打中物体，且深度比物体深
    bool isHit = false;
    [loop]
    for(uint i = 0; i < _LinearMaxStep; ++i)
    {
        w1  = w0;
        w0 += stepSize * jitter;

        float  reflectK     = lerp(startK, endK, w0);
        float2 reflectUV    = lerp(startUV, endUV, w0);
        float4 reflectPosCS = lerp(startPosCS, endPosCS, w0);

        if(reflectUV.x < 0 || reflectUV.x > 1 || reflectUV.y < 0 || reflectUV.y > 1) break;

        float sceneDepth    = GetDeviceDepth(reflectUV).r;
        sceneDepth          = GetLinearEyeDepth(sceneDepth);
        float rayDepth      = GetLinearEyeDepth(reflectPosCS.z * reflectK);
        float depthDiff     = rayDepth - sceneDepth;

        if(depthDiff > 0.f)
        {
            // 交点在物体内
            if(depthDiff < _LinearThickness)
            {
                isHit = true;
                mask = 1;
                resultUV = reflectUV;
                resultDepth = reflectPosCS.z * reflectK;
                break;
            }
        }
    }

    if(isHit)
    {
        [loop]
        for(int i = 0; i < _LinearBinaryStep; ++i)
        {
            float w = 0.5f * (w0 + w1);
            float3 reflectPosCS = lerp(startPosCS, endPosCS, w);
            float2 reflectUV    = lerp(startUV, endUV, w);
            float  reflectK     = lerp(startK,  endK,  w);

            float sceneDepth    = GetDeviceDepth(reflectUV);
            sceneDepth          = LinearEyeDepth(sceneDepth, _ZBufferParams);
            float rayDepth      = LinearEyeDepth(reflectPosCS.z * reflectK, _ZBufferParams);
            float depthDiff     = rayDepth - sceneDepth;

            // 有交点，w0向w1靠近(深度慢慢缩小)
            [flatten]
            if(depthDiff > 0.f)
            {
                w0 = w;
                resultUV = reflectUV;
                resultDepth = reflectPosCS.z * reflectK;
            }
            // 无交点，交点比w1大，w0小(深度慢慢变大)
            else
            {
                w1 = w;
            }
        }
    }
    
    hitData = float4(resultUV, resultDepth, mask);
}