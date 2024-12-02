Shader "Elysia/SSR"
{
    SubShader
    {
        Tags {"LightMode" = "UniversalForward" }
        Cull Off
        ZWrite Off
        ZTest Always

        HLSLINCLUDE
        #pragma target 4.5
        #pragma enable_d3d11_debug_symbols
        #pragma exclude_renderers glcore gles xboxone n3ds wiiu ps4 metal
        #include_with_pragmas "Assets/Resources/SSR/SSR.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        PSInput VS(VSInput i)
        {
            PSInput o = (PSInput)0;
            
            o.positionCS = GetQuadVertexPosition(i.vertexID);
            o.positionCS.xy = o.positionCS.xy * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f);
            o.uv = GetQuadTexCoord(i.vertexID);

            return o;
        }
        
        ENDHLSL
        
        // Copy Depth
        Pass
        {
            Name "Copy Depth"
            HLSLPROGRAM
            #pragma vertex VS
            #pragma fragment CopyDepth
            
            void CopyDepth(PSInput i, out PSOutput o)
            {
                o.color.r = GetDeviceDepth(i.uv);
            }
            ENDHLSL
        }
        
        // Ray March
        Pass
        {
            Name "Ray March"
            
            HLSLPROGRAM
            #pragma vertex VS
            #pragma fragment SSRScreenSpacePS
            #include "Assets/Resources/Library/BRDF.hlsl"

            void SSRScreenSpacePS(PSInput i, out float4 color : SV_TARGET0, out float PDF : SV_TARGET1)
            {
                color = 0;
                PDF = 0;
                
                float2 screenUV   = i.uv;
                float rawDepth = GetDeviceDepth(screenUV);
                float roughness = GetRoughness(screenUV);
                if(rawDepth == 0.f || roughness > _MaxRoughness)
                {
                    return;
                }
                
                float4 posCS       = GetPositionNDC(screenUV, rawDepth);
                float4 posVS       = GetPositionVS(posCS, Matrix_I_P);
                float4 posWS       = GetPositionWS(posVS, Matrix_I_V);
                float3 normalWS    = GetNormalWS(screenUV);
                float3 viewDirWS   = normalize(_WorldSpaceCameraPos - posWS);

                float2 resultUV = 0;
                float resultDepth = 0;
                float resultMask = 0;
                float3 reflectDir = 0.f;
                if(roughness > 0.1)
                {
                    float2 E = _BlueNoiseTex.SampleLevel(Smp_RepeatU_RepeatV_Linear, screenUV + Rand1SPPDenoiserInput(screenUV), 0).xy;
                    E.x = lerp(E.x, 0.f, _BRDFBias);
                    // 获取当前法线在切线空间的3个正交的基向量
                    float3x3 TangentBasis = GetTangentBasis( normalWS );
                    // 切线空间的viewDir向量
			        float3 TangentV = mul( TangentBasis, viewDirWS );
                    float4 halfVectorOS = ImportanceSampleVisibleGGX(E, pow2(roughness), TangentV );
                    PDF = halfVectorOS.w;
                    float4 H = float4(mul(halfVectorOS.xyz, TangentBasis ), halfVectorOS.w);
                    reflectDir = reflect(-viewDirWS, H.xyz);
                }
                else
                {
                    reflectDir = reflect(-viewDirWS, normalWS);
                    PDF = 1;
                }

                Ray ray;
                ray.positionVS  = posVS;
                ray.directionVS = normalize(mul(Matrix_V, float4(reflectDir, 0.f)));

                float4 hitData = 0;
                if(roughness < _MaxRoughness)
                {
                    float jitter = InterleavedGradientNoise(screenUV) + 1;
                    if(roughness < 0.3)
                    {
                        HiZRayMarching(ray, jitter, hitData);
                    }
                    else
                    {
                        LinearRayMarching(ray, jitter, hitData);
                    }
                    
                    resultUV += hitData.xy;
                    resultDepth += hitData.z;
                    resultMask += hitData.w;
                    color = float4(resultUV, resultDepth, resultMask * EdgeFade(resultUV, _EdgeFade));
                }
            }
            ENDHLSL
        }

        // Resolved
        Pass
        {
            Name "Resolved"
            
            HLSLPROGRAM
            #pragma vertex VS
            #pragma fragment Resolved
            #pragma multi_compile _ _SSR_QUALITY_LOW _SSR_QUALITY_MIDDLE _SSR_QUALITY_HIGH
            #include "Assets/Resources/Library/BRDF.hlsl"
            
            void Resolved(PSInput i, out PSOutput o)
            {
                float2 uv = i.uv;

                float   roughness   = GetRoughness(uv);
                float   rawDepth    = GetDeviceDepth(uv);
                if(rawDepth == 0 || roughness > _MaxRoughness)
                {
                    o.color = 0;
                    return;
                }
                float4 positionNDC  = GetPositionNDC(uv, rawDepth);
                float4 positionVS   = GetPositionVS(positionNDC, Matrix_I_P);
                float3 positionWS   = GetPositionWS(positionVS, Matrix_I_V);
                float3 normalWS     = GetNormalWS(uv);
                float3 normalVS     = GetNormalVS(normalWS);
                float3 invviewDirWS = GetViewDir(positionWS);

                half3 blueNoise = _BlueNoiseTex.SampleLevel(Smp_RepeatU_RepeatV_Linear, uv + Rand1SPPDenoiserInput(uv), 0);
                half2x2 offsetRotationMatrix = half2x2(blueNoise.x, blueNoise.y, -blueNoise.y, -blueNoise.x);
                
                uint numRays = 1;

                half totalWeight = 0;
	            half4 totalColor = 0, currColor = 0;
                if(roughness > 0.1)
                {
                    #if defined (_SSR_QUALITY_LOW)
                        numRays = 4;
                    #elif defined (_SSR_QUALITY_MIDDLE)
                        numRays = 6;
                    #elif defined (_SSR_QUALITY_HIGH)
                        numRays = 8;
                    #endif
                }
                else
                {
                    numRays = 1;
                }
                
                for(uint i = 0; i < numRays; ++i)
                {
                    float2 offsetUV = mul(offsetRotationMatrix, offset[i] * _RayMarchTexSize.zw);
		            float2 neighborUV = uv + offsetUV;

                    float4 hitData  = _SSRHitDataTex.SampleLevel(Smp_ClampU_ClampV_Linear, neighborUV, 0);
                    float hitPDF    = _SSRHitPDFTex.SampleLevel(Smp_ClampU_ClampV_Linear, neighborUV, 0);
                    float2 hitUV    = hitData.rg;
                    float hitDepth  = hitData.b;
                    float hitMask   = hitData.a;

                    float4 hitPositionNDC = GetPositionNDC(hitUV, hitDepth);
                    float3 hitPositionVS = GetPositionVS(hitPositionNDC, Matrix_I_P);

                    half currWeight = BRDF_UE4(normalize(-positionVS), normalize(hitPositionVS - positionVS), normalVS, roughness) / max(1e-5, hitPDF);
                    
                    currColor.rgb = _CameraColorTexture.SampleLevel(Smp_ClampU_ClampV_Linear, hitUV, 0);
                    currColor.a = hitMask;

                    totalColor += currColor * currWeight;
                    totalWeight += currWeight;
                }

                totalColor /= totalWeight;
                o.color = totalColor;
            }
            ENDHLSL
        }

        // Blur Reflect
        Pass
        {
            Name "Blur Reflect"
            
            HLSLPROGRAM
            half4 _BlurOffset;
            
            #pragma vertex VS
            #pragma fragment GaussianBlur

            void GaussianBlur(PSInput i, out PSOutput o)
            {
                float2 uv = i.uv;
                float4 uv01 = uv.xyxy + _BlurOffset.xyxy * float4(1, 1, -1, -1);
                float4 uv23 = uv.xyxy + _BlurOffset.xyxy * float4(1, 1, -1, -1) * 2.f;
                float4 uv45 = uv.xyxy + _BlurOffset.xyxy * float4(1, 1, -1, -1) * 6.f;

                half4 color = 0.f;
                color += 0.4  * _MainTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv,      0);
                color += 0.15 * _MainTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv01.xy, 0);
                color += 0.15 * _MainTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv01.zw, 0);
                color += 0.10 * _MainTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv23.xy, 0);
                color += 0.10 * _MainTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv23.zw, 0);
                color += 0.05 * _MainTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv45.xy, 0);
                color += 0.05 * _MainTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv45.zw, 0);

                o.color = saturate(color);
            }
            ENDHLSL
        }

        // Temporalfilter
        Pass
        {
            Name "Temporalfilter"
            
            HLSLPROGRAM
            #pragma vertex VS
            #pragma fragment Temporalfilter
            #include "Assets/Resources/Library/Filtter.hlsl"
            
            void Temporalfilter(PSInput i, out PSOutput o)
            {
                //return;
                float2 uv = i.uv;
                float  hitDepth = _SSRHitDataTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).b;
                float  roughness = GetRoughness(uv);
                float3 normalWS = GetNormalWS(uv);
                
                float2 velocity	= _MotionVectorTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0);
                float2 rayVelocity = GetCameraMotionVector(hitDepth, uv, Matrix_I_VP, _Pre_Matrix_VP, Matrix_VP);
                float velocityWeight = saturate(dot(normalWS, float3(0, 1, 0)));
                velocity = lerp(velocity, rayVelocity, velocityWeight);
                float2 preUV = uv - velocity;

                float2 du = float2(_ResolvedTexSize.z, 0);
                float2 dv = float2(0, _ResolvedTexSize.w);

                float4 minColor = FLT_MAX, maxColor = 0;
                for(int i = -1; i <= 1; ++i)
                {
                    for(int j = -1; j <= 1; ++j)
                    {
                        float4 targetColor = _SSRResolvedTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv + du * i + dv * j, 0);
                        minColor = min(minColor, targetColor);
                        maxColor = max(maxColor, targetColor);
                    }
                }
                float4 averageColor = (minColor + maxColor) * 0.5f;
                minColor = (minColor - averageColor) * _TemporalScale + averageColor;
                maxColor = (maxColor - averageColor) * _TemporalScale + averageColor;

                float4 historyFrame = _SSRTAAPreTex.SampleLevel(Smp_ClampU_ClampV_Linear, preUV, 0);
                float3 historyColor = clamp(historyFrame.rgb, minColor, maxColor);
                float3 currColor = _SSRResolvedTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0);

                float TAAWeight = _TemporalWeight;
                if(roughness > 0.1)
                {
                    TAAWeight = _TemporalWeight;
                }
                else
                {
                    TAAWeight = 0.9f;
                }

                float weight = saturate(TAAWeight * (1.f - length(velocity) * 8));
                float3 reflectColor = lerp(currColor, historyColor, weight);

                o.color = float4(saturate(reflectColor), 1.f);
            }
            ENDHLSL
        }

        // Combine
        Pass
        {
            Name "Combine"
            HLSLPROGRAM
            #pragma vertex VS
            #pragma fragment Combine
            #pragma multi_compile_fragment _ _DEBUG_HITUV _DEBUG_HITDEPTH _DEBUG_HITMASK
            #include "Assets/Resources/Library/BRDF.hlsl"
            
            void Combine(PSInput i, out PSOutput o)
            {
                float2 uv = i.uv;

                float roughness = GetRoughness(uv);
                float rawDepth = GetDeviceDepth(uv);
                float rgh                = roughness * (1.7 - 0.7 * roughness);
                float lod                = 6.f * rgh;
                if(rawDepth == 0.f)
                {
                    o.color = GetSourceColor(uv);
                    return;
                }
                #if defined(_DEBUG_HITUV)
                    o.color = float4(_SSRHitDataTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).rg, 0.f, 0.f);
                    return;
                #elif defined(_DEBUG_HITDEPTH)
                    o.color = float4(_SSRHitDataTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).b, 0.f, 0.f, 0.f);
                    return;
                #elif defined(_DEBUG_HITMASK)
                    o.color = float4(_SSRHitDataTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, lod).a, 0.f, 0.f, 0.f);
                    return;
                #else
                
                float4 positionNDC  = GetPositionNDC(uv, rawDepth);
                float4 positionVS   = GetPositionVS(positionNDC, Matrix_I_P);
                float4 positionWS   = GetPositionWS(positionVS, Matrix_I_V);
                float3 normalWS     = GetNormalWS(uv);
                float3 normalVS     = GetNormalVS(normalWS);
                float3 invViewDirWS = GetViewDir(positionWS);

                float NoV = saturate(dot(normalWS, -invViewDirWS));
                float3 specular = _GBuffer3.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).rgb;
                half3 EnergyCompensation = 0;
                half4 preIntegratedGF = PreintegratedDGF_LUT(_PreIntegratedTex, EnergyCompensation, specular, roughness, NoV);
                
                float ao = GetAO(uv);
                float mask = _SSRHitDataTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, lod).a;
                float3 cubemapColor = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflect(invViewDirWS, normalWS), lod).rgb;
                float3 sceneColor = _CameraColorTexture.SampleLevel(Smp_ClampU_ClampV_Linear, uv, 0).rgb;
                sceneColor  = max(1e-5, sceneColor - cubemapColor * ao);

                lod = clamp(roughness * 8, 0, 4);
                float3 reflectColor = _UpSampleTex.SampleLevel(Smp_ClampU_ClampV_Linear, uv, lod) * _Brightness;
                //reflectColor = cubemapColor * (1 - mask) + reflectColor * preIntegratedGF * ao * mask;
                reflectColor = cubemapColor * ao + reflectColor * ao * preIntegratedGF;
                
                o.color = float4(sceneColor + reflectColor, 1);
                #endif
            }
            ENDHLSL
        }

        // Up sample
        Pass
        {
            Name"Up Sample"
            
            HLSLPROGRAM
            #pragma vertex VS
            #pragma fragment UpSample

            void UpSample(PSInput i, out PSOutput o)
            {
                o.color = 0.f;
                float2 uv = i.uv;
                
                float highResDepth = _CameraDepthTexture.Sample(Smp_ClampU_ClampV_Linear, uv).r;
                highResDepth = Linear01Depth(highResDepth, _ZBufferParams);
                float lowResDepth1 = Linear01Depth(_LowResDepthTex.Sample(Smp_ClampU_ClampV_Linear, uv, int2(0, 0.5f)), _ZBufferParams);
                float lowResDepth2 = Linear01Depth(_LowResDepthTex.Sample(Smp_ClampU_ClampV_Linear, uv, int2(0, -0.5f)), _ZBufferParams);
                float lowResDepth3 = Linear01Depth(_LowResDepthTex.Sample(Smp_ClampU_ClampV_Linear, uv, int2(0.5f, 0)), _ZBufferParams);
                float lowResDepth4 = Linear01Depth(_LowResDepthTex.Sample(Smp_ClampU_ClampV_Linear, uv, int2(-0.5f, 0)), _ZBufferParams);

                float depthDiff1 = abs(highResDepth - lowResDepth1);
                float depthDiff2 = abs(highResDepth - lowResDepth2);
                float depthDiff3 = abs(highResDepth - lowResDepth3);
                float depthDiff4 = abs(highResDepth - lowResDepth4);

                float depthDiffMin = min(min(depthDiff1, depthDiff2), min(depthDiff3, depthDiff4));
                int index = -1;
                if(depthDiffMin == depthDiff1) index = 0;
                else if(depthDiffMin == depthDiff2) index = 1;
                else if(depthDiffMin == depthDiff3) index = 2;
                else if(depthDiffMin == depthDiff4) index = 3;

                half4 result = 0.h;
                switch(index)
                {
                    case 0:
                        result += _SSRTAACurrTex.Sample(Smp_ClampU_ClampV_Point, uv, int2(0, 0.5f));
                        break;
                    case 1:
                        result += _SSRTAACurrTex.Sample(Smp_ClampU_ClampV_Point, uv, int2(0, -0.5f));
                        break;
                    case 2:
                        result += _SSRTAACurrTex.Sample(Smp_ClampU_ClampV_Point, uv, int2(0.5f, 0));
                        break;
                    case 3:
                        result += _SSRTAACurrTex.Sample(Smp_ClampU_ClampV_Point, uv, int2(-0.5f, 0));
                        break;
                    default:
                        result += _SSRTAACurrTex.Sample(Smp_ClampU_ClampV_Point, uv);
                        break;
                }
                
                o.color += result;
            }
            ENDHLSL
        }
    }
}
