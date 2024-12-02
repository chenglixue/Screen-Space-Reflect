#pragma once
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#include "Assets/Resources/Library/Math.hlsl"
#include "Assets/Resources/Library/Transform.hlsl"
#include "Assets/Resources/Library/Color.hlsl"

SamplerState Smp_ClampU_ClampV_Linear;
SamplerState Smp_ClampU_RepeatV_Linear;
SamplerState Smp_RepeatU_RepeatV_Linear;
SamplerState Smp_RepeatU_ClampV_Linear;
SamplerState Smp_ClampU_ClampV_Point;
SamplerState Smp_ClampU_RepeatV_Point;
SamplerState Smp_RepeatU_RepeatV_Point;
SamplerState Smp_RepeatU_ClampV_Point;

half2 GetMatCapUV(half3 viewDirWS, half3 normalWS)
{
    half3 cameraFoward = -viewDirWS;
    half3 viewUpDir = mul(UNITY_MATRIX_I_V, half4(half3 (0, 1, 0), 0)).xyz;
    half3 cameraRight = normalize(cross(viewUpDir,cameraFoward));
    half3 cameraUp = normalize(cross(cameraFoward,cameraRight));

    half2 uv = mul(float3x3(cameraRight,cameraUp,cameraFoward),normalWS).xy * 0.5 + 0.5;
    return uv;
}

float PackMaterialFlags(uint materialFlags)
{
    return materialFlags * (1.0h / 255.0h);
}

uint UnpackMaterialFlags(float packedMaterialFlags)
{
    return uint((packedMaterialFlags * 255.0h) + 0.5h);
}