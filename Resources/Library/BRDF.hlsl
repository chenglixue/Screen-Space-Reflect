#pragma once
//#include "Assets/Resources/Library/Common.hlsl"
#include "Assets/Resources/Library/Transform.hlsl"

struct MyBRDFData
{
    float3 albedo;
    float  opacity;
    float3 normal;
    float3 emission;
    float  metallic;
    float3 specular;
    float  roughness;
    float  roughness2;
    float  AO;
    
    float3 F0;
    float3 radiance;

    float3 halfVector;
    float NoV;
    float NoH;
    float NoL;
    float HoV;
    float HoL;
    float HoX;
    float HoY;

    float LobeA;
    float LobeB;
    #if defined(_SHADINGMODEL_KAJIYAKAYHAIR)
        float anisotropy;    // hair
    #endif

    #if defined(_SHADINGMODEL_EYE)
    
    #endif
};
struct MyLightData
{
    half3  tangentWS;
    half3  bitTangentWS;
    half3  normalWS;
    half3  viewDirWS;
    float3 reflectDirWS;

    half3x3 TBN;
};

struct FDirectLighting
{
    float3	diffuse;
    float3	specular;
};

#pragma region Diffuse
float3 Diffuse_Lambert(float3 DiffuseColor)
{
    return DiffuseColor * (1 / PI);
}

// [Burley 2012, "Physically-Based Shading at Disney"]
// Lambert漫反射模型在边缘上通常太暗，而通过尝试添加菲涅尔因子以使其在物理上更合理，但会导致其更暗
// 根据对Merl 100材质库的观察，Disney开发了一种用于漫反射的新的经验模型，以在光滑表面的漫反射菲涅尔阴影和粗糙表面之间进行平滑过渡
// Disney使用了Schlick Fresnel近似，并修改掠射逆反射（grazing retroreflection response）以达到其特定值由粗糙度值确定，而不是简单为0
float3 Diffuse_Burley( float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH )
{
    float FD90 = 0.5 + 2 * VoH * VoH * Roughness;
    float FdV = 1 + (FD90 - 1) * pow5( 1 - NoV );
    float FdL = 1 + (FD90 - 1) * pow5( 1 - NoL );
    return DiffuseColor * ( (1 / PI) * FdV * FdL );
}

// [Gotanda 2012, "Beyond a Simple Physically Based Blinn-Phong Model in Real-Time"]
float3 Diffuse_OrenNayar( float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH )
{
    float a = Roughness * Roughness;
    float s = a;// / ( 1.29 + 0.5 * a );
    float s2 = s * s;
    float VoL = 2 * VoH * VoH - 1;		// double angle identity
    float Cosri = VoL - NoV * NoL;
    float C1 = 1 - 0.5 * s2 / (s2 + 0.33);
    float C2 = 0.45 * s2 / (s2 + 0.09) * Cosri * ( Cosri >= 0 ? rcp( max( NoL, NoV ) ) : 1 );
    return DiffuseColor / PI * ( C1 + C2 ) * ( 1 + Roughness * 0.5 );
}

#pragma endregion 

#pragma region NDF
// [Blinn 1977, "Models of light reflection for computer synthesized pictures"]
float NDF_Blinn( float roughness2, float NoH )
{
    float a2 = pow2(roughness2);
    float n = 2 / a2 - 2;
    return (n+2) / (2*PI) * pow( NoH, n );
}

// [Beckmann 1963, "The scattering of electromagnetic waves from rough surfaces"]
// Beckmann分布在某些方面与Phong分布非常相似
float D_Beckmann( float roughness2, float NoH )
{
    float a2 = pow2(roughness2);
    float NoH2 = NoH * NoH;
    return exp( (NoH2 - 1) / (a2 * NoH2) ) / ( PI * a2 * NoH2 * NoH2 );
}

// GGX / Trowbridge-Reitz
// [Walter et al. 2007, "Microfacet models for refraction through rough surfaces"]
// 在流行的模型中，GGX拥有最长的尾部。而GGX其实与Blinn (1977)推崇的Trowbridge-Reitz（TR）（1975）分布等同。然而，对于许多材质而言，即便是GGX分布，仍然没有足够长的尾部
float NDF_GGX( float roughness2, float NoH )
{
    const float a2 = pow2(roughness2);
    const float NoH2 = pow2(NoH);
    const float d = PI * pow2(NoH2 * (a2 - 1.f) + 1.f);
    
    if(d < FLT_EPS) return 1.f;
    
    return a2 / d;
}

// Berry(1923)
// 类似 Trowbridge-Reitz,但指数为1而不是2，从而导致了更长的尾部
float NDF_Berry( float roughness2, float NoH )
{
    float a2 = pow2(roughness2);
    float d = ( NoH * a2 - NoH ) * NoH + 1;	// 2 mad
    return a2 / ( PI*d );					
}

// Disney发现GGX 和 Berry有相似的形式，只是幂次不同，于是，Disney将Trowbridge-Reitz进行了N次幂的推广，并将其取名为GTR
// 基本形式是：c/pow((a^2*cos(NdotH)^2 + sin(NdotH)^2),b) . c为放缩常数，a为粗糙度
// Disney的BRDF使用两个specular lobe
// b=1为次级波瓣，用来表达清漆层
// b=2为主波瓣，用来表达基础材质
float D_GTR1(float NoH, float roughness)
{
    //考虑到粗糙度a在等于1的情况下，公式返回值无意义，因此固定返回1/pi，
    //说明在完全粗糙的情况下，各个方向的法线分布均匀，且积分后得1
    if (roughness >= 1) return 1/PI;
    
    float a2 = roughness * roughness;
    float cos2th = NoH * NoH;
    float den = (1.0 + (a2 - 1.0) * cos2th);
    
    return (a2 - 1.0) / (PI * log(a2) * den);
}

float D_GTR2(float roughness2, float NoH)
{
    float a2 = roughness2 * roughness2;
    float cos2th = NoH * NoH;
    float den = (1.0 + (a2 - 1.0) * cos2th);

    return a2 / (PI * den * den);
}

//主波瓣 各项异性
// VoX：Dot(H, 物体表面的切线向量)
// HdotY：为半角点乘切线空间中的副切线向量 
// ax 和 ay 分别是x、y2个方向上的可感粗糙度，范围是0~1
float GTR2_aniso(float NoH, float HoX, float HoY, float ax, float ay)
{
    return rcp(PI * ax*ay * pow2( pow2(HoX / ax) + pow2(HoY / ay) + pow2(NoH) ));
}
#pragma endregion

#pragma region Fresnel
float SchlickFresnel(float u)
{
    float m = clamp(1-u, 0, 1);
    float m2 = m * m;
    return m2 * m2 * m;
}

float3 SchlickFresnel(float HdotV, float3 F0)
{
    float m = clamp(1-HdotV, 0, 1);
    float m2 = m * m;
    float m5 = m2 * m2 * m; // pow(m,5)
    return F0 + (1.0 - F0) * m5;
}

// [Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"]
float3 F_Schlick(float HoV, float3 F0)
{
    return F0 + (1 - F0) * pow(1 - HoV , 5.0);
}

float3 F_Schlick(float3 F0, float3 F90, float VoH)
{
    float Fc = pow5(1 - VoH);
    return F90 * Fc + (1 - Fc) * F0;
}

float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
    return F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow5(1.0 - cosTheta);
}

inline float3 Fresnel_UE4(float VoH, float3 F0)
{
    return F0 + (float3(1, 1, 1) - F0) * pow(2, ((-5.55473) * VoH - 6.98316) * VoH);
}

#pragma endregion 

#pragma region Geometry
inline float SchlickGGX(float NdotV, float k)
{
    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k + 0.0001f;

    return nom / denom;
}

inline float Geometry_Smiths_SchlickGGX(float NoV, float NoL, float roughness)
{	
    const float k = pow2(roughness + 1.f) * rcp(8.f);
    const float Vis_SchlickV  = SchlickGGX(NoV, k);
    const float Vis_SchlickL  = SchlickGGX(NoL, k);
    if (Vis_SchlickV < FLT_EPS) return 1.0f;
    if (Vis_SchlickL < FLT_EPS) return 1.0f;
    
    return Vis_SchlickV * Vis_SchlickL;
}

float Vis_SmithJointApprox( float a2, float NoV, float NoL )
{
    float a = sqrt(a2);
    float Vis_SmithV = NoL * ( NoV * ( 1 - a ) + a );
    float Vis_SmithL = NoV * ( NoL * ( 1 - a ) + a );
    return 0.5 * rcp( Vis_SmithV + Vis_SmithL );
}

// 清漆层 次级波瓣
// 2012版disney,本质是Smith联合遮蔽阴影函数中的“分离的遮蔽阴影型”
// NoV视情况也可替换为NdotL，用于计算阴影相关的G1
// alphag被disney定义为0.25f
float G_GGX(float NoV, float alphag)
{
    float a = alphag * alphag;
    float b = NoV * NoV;
    return 1.0 / (NoV + sqrt(a + b - a * b));
}

// 各向异性
float smithG_GGX_aniso(float NoV, float VoX, float VoY, float ax, float ay)
{
    return 1 / (NoV + sqrt( pow2(VoX*ax) + pow2(VoY*ay) + pow2(NoV) ));
}
#pragma endregion 

#pragma region GI Diffuse


float3 SH_IndirectionDiff(float3 normalWS)
{

    float4 SHCoefficients[7];

    SHCoefficients[0] = unity_SHAr;

    SHCoefficients[1] = unity_SHAg;

    SHCoefficients[2] = unity_SHAb;

    SHCoefficients[3] = unity_SHBr;

    SHCoefficients[4] = unity_SHBg;

    SHCoefficients[5] = unity_SHBb;

    SHCoefficients[6] = unity_SHC;

    float3 Color = SampleSH9(SHCoefficients,normalWS);

    return max(0,Color);
}
#pragma endregion

#pragma region GI Specular
float3 IndirSpeCube(float3 normalWS,float3 viewWS,float roughness,float AO)
{
    float3 reflectDirWS=reflect(-viewWS,normalWS);

    roughness=roughness*(1.7-0.7*roughness);//Unity内部不是线性 调整下拟合曲线求近似

    float MidLevel=roughness*6;//把粗糙度remap到0-6 7个阶级 然后进行lod采样

    float4 speColor=SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0,reflectDirWS,MidLevel);//根据不同的等级进行采样

    #if !defined(UNITY_USE_NATIVE_HDR)

    return DecodeHDREnvironment(speColor,unity_SpecCube0_HDR)*AO;//用DecodeHDREnvironment将颜色从HDR编码下解码。可以看到采样出的rgbm是一个4通道的值，最后一个m存的是一个参数，解码时将前三个通道表示的颜色乘上xM^y，x和y都是由环境贴图定义的系数，存储在unity_SpecCube0_HDR这个结构中。

    #else

    return speColor.xyz*AO;

    #endif

}

//间接高光 曲线拟合 放弃LUT采样而使用曲线拟合

float3 IndirSpeFactor(float roughness, float smoothness, float3 BRDFspe, float3 F0, float NdotV)
{

    #ifdef UNITY_COLORSPACE_GAMMA

    float SurReduction=1-0.28*roughness,roughness;

    #else

    float SurReduction=1/(roughness*roughness+1);

    #endif

    #if defined(SHADER_API_GLES)//Lighting.hlsl 261行

    float Reflectivity=BRDFspe.x;

    #else

    float Reflectivity=max(max(BRDFspe.x,BRDFspe.y),BRDFspe.z);

    #endif

    half GrazingTSection = saturate(Reflectivity+smoothness);

    float Fre = Pow4(1-NdotV);

    return lerp(F0,GrazingTSection,Fre)*SurReduction;
}
#pragma endregion 

float4 TransformTangentToView(float3 normalVS, float4 H)
{
    float3 upDir        = normalVS.z < 0.999f ? float3(0.f, 0.f, 1.f) : float3(1.f, 0.f, 0.f);
    float3 tangent      = normalize(cross(upDir, normalVS));
    float  bitTangent   = cross(normalVS, tangent);

    return float4(tangent * H.x + bitTangent * H.y + normalVS * H.z, H.w);
}

float4 ImportanceSampleGGX(float2 Xi, float Roughness)
{
    float m = Roughness * Roughness;
    float m2 = m * m;
    
    float Phi = 2 * PI * Xi.x;
	
    float CosTheta = sqrt((1.0 - Xi.y) / (1.0 + (m2 - 1.0) * Xi.y));
    float SinTheta = sqrt(max(1e-5, 1.0 - CosTheta * CosTheta));

    // 半程向量(采样方向)
    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;
    
    float d = (CosTheta * m2 - CosTheta) * CosTheta + 1;
    float D = m2 / (PI * d * d);
    float pdf = D * CosTheta;

    return float4(H, pdf);
}

// [ Duff et al. 2017, "Building an Orthonormal Basis, Revisited" ]
// Discontinuity at TangentZ.z == 0
float3x3 GetTangentBasis( float3 TangentZ )
{
    const float Sign = TangentZ.z >= 0 ? 1 : -1;
    const float a = -rcp( Sign + TangentZ.z );
    const float b = TangentZ.x * TangentZ.y * a;
	
    float3 TangentX = { 1 + Sign * a * pow2( TangentZ.x ), Sign * b, -Sign * TangentZ.x };
    float3 TangentY = { b,  Sign + a * pow2( TangentZ.y ), -TangentZ.y };

    return float3x3( TangentX, TangentY, TangentZ );
}

float VisibleGGXPDF_aniso(float3 V, float3 H, float2 Alpha, bool bLimitVDNFToReflection = true)
{
    float NoV = V.z;
    float NoH = H.z;
    float VoH = dot(V, H);
    float a2 = Alpha.x * Alpha.y;
    float3 Hs = float3(Alpha.y * H.x, Alpha.x * H.y, a2 * NoH);
    float S = dot(Hs, Hs);
    float D = (1.0f / PI) * a2 * Square(a2 / S);
    float LenV = length(float3(V.x * Alpha.x, V.y * Alpha.y, NoV));
    float k = 1.0;
    #if GGX_BOUNDED_VNDF_SAMPLING
    if (bLimitVDNFToReflection)
    {
        float a = saturate(min(Alpha.x, Alpha.y));
        float s = 1.0f + length(V.xy);
        float ka2 = a * a, s2 = s * s;
        k = (s2 - ka2 * s2) / (s2 + ka2 * V.z * V.z); // Eq. 5
    }
    #endif
    float Pdf = (2 * D * VoH) / (k * NoV + LenV);
    return Pdf;
}

// PDF = G_SmithV * VoH * D / NoV / (4 * VoH)
// PDF = G_SmithV * D / (4 * NoV)
float4 ImportanceSampleVisibleGGX(float2 E, float2 Alpha, float3 V, bool bLimitVDNFToReflection = true)
{
    // stretch
    float3 Vh = normalize(float3(Alpha * V.xy, V.z));

    // "Sampling Visible GGX Normals with Spherical Caps"
    // Jonathan Dupuy & Anis Benyoub - High Performance Graphics 2023
    float Phi = (2 * PI) * E.x;
    float k = 1.0;
    #if GGX_BOUNDED_VNDF_SAMPLING
    if (bLimitVDNFToReflection)
    {
        // If we know we will be reflecting the view vector around the sampled micronormal, we can
        // tweak the range a bit more to eliminate some of the vectors that will point below the horizon
        float a = saturate(min(Alpha.x, Alpha.y));
        float s = 1.0 + length(V.xy);
        float a2 = a * a, s2 = s * s;
        k = (s2 - a2 * s2) / (s2 + a2 * V.z * V.z);
    }
    #endif
    float Z = lerp(1.0, -k * Vh.z, E.y);
    float SinTheta = sqrt(saturate(1 - Z * Z));
    float X = SinTheta * cos(Phi);
    float Y = SinTheta * sin(Phi);
    float3 H = float3(X, Y, Z) + Vh;

    // unstretch
    H = normalize(float3(Alpha * H.xy, max(0.0, H.z)));

    return float4(H, VisibleGGXPDF_aniso(V, H, Alpha));
}

float G_GGX(float Roughness, float NdotL, float NdotV)
{
    float m = Roughness * Roughness;
    float m2 = m * m;

    float G_L = 1.0f / (NdotL + sqrt(m2 + (1 - m2) * NdotL * NdotL));
    float G_V = 1.0f / (NdotV + sqrt(m2 + (1 - m2) * NdotV * NdotV));
    float G = G_L * G_V;
	
    return G;
}

float BRDF_UE4(float3 V, float3 L, float3 N, float Roughness)
{
    float3 H = normalize(L + V);

    float NdotH = saturate(dot(N,H));
    float NdotL = saturate(dot(N,L));
    float NdotV = saturate(dot(N,V));

    float D = NDF_GGX(Roughness, NdotH);
    float G = G_GGX(Roughness, NdotL, NdotV);

    return D * G;
}

half4 PreintegratedDGF_LUT(Texture2D<real3> PreintegratedLUT, inout half3 EnergyCompensation, half3 SpecularColor, half Roughness, half NoV)
{
    half3 Enviorfilter_GFD = PreintegratedLUT.SampleLevel(Smp_ClampU_ClampV_Linear, float2(Roughness, NoV), 0);
    half3 ReflectionGF = lerp( saturate(50.0 * SpecularColor.g) * Enviorfilter_GFD.ggg, Enviorfilter_GFD.rrr, SpecularColor );

    #if Multi_Scatter
    EnergyCompensation = 1.0 + SpecularColor * (1.0 / Enviorfilter_GFD.r - 1.0);
    #else
    EnergyCompensation = 1.0;
    #endif

    return half4(ReflectionGF, Enviorfilter_GFD.b);
}