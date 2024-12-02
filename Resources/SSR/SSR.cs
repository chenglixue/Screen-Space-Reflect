using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;
using AmplifyShaderEditor;
using Unity.Mathematics;
using UnityEngine.Assertions;

namespace Elysia
{
    public enum SSRDebugMode
    {
        Hituv,
        HitDepth,
        HitMask,
    }
    [System.Serializable]
    public class SSRHizSetting
    {
        [Range(0, 2f)]   public float thickness;
        [Range(0, 1000)] public float maxDistance     = 300f;
        [Range(1, 256)]  public int   maxStep         = 64;
        [Range(0, 8)]    public int   binaryStep      = 4;
    }
    [System.Serializable]
    public class SSRLinearSetting
    {
        [Range(0, 2f)]   public float thickness;
        [Range(0, 1000)] public float maxDistance     = 300f;
        [Range(1, 128)]  public int   maxStep         = 64;
        [Range(0, 8)]    public int   binaryStep      = 4;
    }
    
    [System.Serializable]
    public class SSRSetting
    {
        public string profilerTag = "SSR";
        public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingTransparents;
        
        public enum SSRQuality
        {
            Low,
            Middle,
            High
        };
        public SSRQuality quality = SSRQuality.High;

        [Range(0, 2f)]   public float brightness = 0.5f;
        [Range(1, 4)]    public int downSample   = 1;
        [Range(0, 5)]    public float blurRadius      = 5;
        
        [Range(0, 1)]    public float maxRoughness    = 1f;
        [Range(0, 1)]    public float edgeFade        = 0.7f;
        [Range(0, 1)]    public float BRDFBias        = 0.7f;
        [Range(0, 5)]    public float temporalScale   = 2.5f;
        [Range(0, 1)]    public float temporalWeight  = 0.8f;
    }

    [System.Serializable]
    public class SSRDebugSetting
    {
        public bool enableDebug = false;
        public SSRDebugMode debugMode;
    }
    
    public class SSR : ScriptableRendererFeature
    {
        #region Variable

        public SSRSetting m_SSRSetting = new SSRSetting();
        public SSRHizSetting m_hizSetting = new SSRHizSetting();
        public SSRLinearSetting m_linearSetting = new SSRLinearSetting();
        public SSRDebugSetting m_SSRDebugSetting = new SSRDebugSetting();
        SSRRenderPass m_SSSRPass;
        #endregion
        
        public override void Create()
        {
            m_SSSRPass = new SSRRenderPass();
        }
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            m_SSSRPass.ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Motion);
            
            m_SSSRPass.Setup(m_SSRSetting, m_SSRDebugSetting, m_hizSetting, m_linearSetting, (UniversalRenderer)renderer);
            renderer.EnqueuePass(m_SSSRPass);
        }
    }
    
    class SSRRenderPass : ScriptableRenderPass
    {
        #region  Variable
        private SSRSetting              m_SSRSetting;
        private SSRDebugSetting         m_SSRDebugSetting;
        private SSRHizSetting           m_hizSetting;
        private SSRLinearSetting        m_linearSetting;
        private UniversalRenderer       m_renderer;
        private Shader                  m_shader;
        private ComputeShader           m_computeShader;
        private ComputeShader           m_blurCS;
        private Material                m_material;
        private RenderTextureDescriptor m_descriptor;
        public struct BlurLevel
        {
            public int downVertical;
            public int downHorizontal;
            public int upVertical;
            public int upHorizontal;
        }
        private BlurLevel[] m_blurLevels;
        
        private Texture2D m_blueNoiseTex;
        private Texture2D m_preIntegratedTex;
        private Vector4   m_screenSize;
        private Vector4   m_rayMarchTexSize;
        private Vector4   m_resolvedTexSize;
        private Vector4   m_TAATexSize;
        private bool      m_isFirstPreTex = true;
        private const int m_maxHizMipMapLevels = 5;
        private const int m_MaxPyramidSize = 4;

        private class RTIs
        {
            public static RenderTargetIdentifier[] m_HiZDepthRT = new RenderTargetIdentifier[m_maxHizMipMapLevels];
            public static RenderTargetIdentifier[] m_HitDataRTIs = new RenderTargetIdentifier[2];
            public static RenderTargetIdentifier   m_upSample;
        }

        private class ShaderIDs
        {
            public static int   m_screenSize       = Shader.PropertyToID("_ViewSize");
            public static int   m_rayMarchTexSize  = Shader.PropertyToID("_RayMarchTexSize");
            public static int   m_resolvedTexSize  = Shader.PropertyToID("_ResolvedTexSize");
            public static int   m_TAATexSize       = Shader.PropertyToID("_TAATexSize");
            public static int   m_blueNoiseTexSize = Shader.PropertyToID("_BlueNoiseTexSize");
            public static int   m_hizMaxStep       = Shader.PropertyToID("_HizMaxStep");
            public static int   m_linearMaxStep    = Shader.PropertyToID("_LinearMaxStep");
            public static int   m_hizBinaryCount   = Shader.PropertyToID("_HiZBinaryStep");
            public static int   m_linearBinaryCount= Shader.PropertyToID("_LinearBinaryStep");
            public static int   m_hizThickness     = Shader.PropertyToID("_HiZThickness");
            public static int   m_linearThickness  = Shader.PropertyToID("_LinearThickness");
            public static int   m_hizMaxDistance   = Shader.PropertyToID("_HiZMaxDistance");
            public static int   m_LinearMaxDistance= Shader.PropertyToID("_LinearMaxDistance");
            public static int   m_maxRoughness     = Shader.PropertyToID("_MaxRoughness");
            public static int   m_edgeFade         = Shader.PropertyToID("_EdgeFade");
            public static int   m_BRDFBias         = Shader.PropertyToID("_BRDFBias");
            public static int   m_temporalScale    = Shader.PropertyToID("_TemporalScale");
            public static int   m_temporalWeight   = Shader.PropertyToID("_TemporalWeight");
            public static int   m_brightness       = Shader.PropertyToID("_Brightness");
            public static int   m_blurOffset       = Shader.PropertyToID("_BlurOffset");
            
            public static int   m_blueNoiseTex     = Shader.PropertyToID("_BlueNoiseTex");
            public static int   m_preIntegratedTex = Shader.PropertyToID("_PreIntegratedTex");
            
            public static int   m_lowResDepthTex   = Shader.PropertyToID("_LowResDepthTex");
            public static int[] m_HiZDepthTex      = new int[m_maxHizMipMapLevels];
            public static int   m_hitDataTex       = Shader.PropertyToID("_SSRHitDataTex");
            public static int   m_hitPDFTex        = Shader.PropertyToID("_SSRHitPDFTex");
            public static int   m_resolvedTex      = Shader.PropertyToID("_SSRResolvedTex");
            public static int   m_TAATex           = Shader.PropertyToID("_SSRTAACurrTex");
            public static int   m_TAAPreTex        = Shader.PropertyToID("_SSRTAAPreTex");
            public static int   m_upSampleTex      = Shader.PropertyToID("_UpSampleTex");
            public static int   m_combineTex       = Shader.PropertyToID("_SSRCombineTex");
            
        }

        private class Passes
        {
            public static int m_copyDepth;
            public static int m_rayMarch;
            public static int m_resolved;
            public static int m_temporalfilter;
            public static int m_upSample;
            public static int m_blurReflect;
            public static int m_combine;
        }

        private Matrix4x4 _Pre_Matrix_VP;
        private Matrix4x4 _Curr_Matrix_VP;
        #endregion
        
        public SSRRenderPass()
        {
            m_shader = Shader.Find("Elysia/SSR");
            m_material = CoreUtils.CreateEngineMaterial(m_shader);

            m_blueNoiseTex = Resources.Load<Texture2D>("Tex/LDR_RGBA_0");
            m_preIntegratedTex = Resources.Load<Texture2D>("Tex/GI/PreIntegrated_LUT");
            if (m_blueNoiseTex == null)
            {
                Debug.LogError("Blue Noise Tex miss!");
            }

            FindPasses();
        }
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            m_descriptor                 = cameraTextureDescriptor;
            m_descriptor.msaaSamples     = 1;
            m_descriptor.depthBufferBits = 0;
            m_descriptor.width = m_descriptor.width / m_SSRSetting.downSample;
            m_descriptor.height = m_descriptor.height / m_SSRSetting.downSample;
            m_screenSize                 = GetTextureSizeParams(new Vector2Int(m_descriptor.width, m_descriptor.height));
            m_rayMarchTexSize            = GetTextureSizeParams(new Vector2Int(m_descriptor.width, m_descriptor.height ));
            m_resolvedTexSize            = GetTextureSizeParams(new Vector2Int(m_descriptor.width, m_descriptor.height));
            m_TAATexSize                 = GetTextureSizeParams(new Vector2Int(m_descriptor.width, m_descriptor.height));
            
            m_descriptor.colorFormat = RenderTextureFormat.RFloat;
            cmd.GetTemporaryRT(ShaderIDs.m_lowResDepthTex, m_descriptor, FilterMode.Point);
            
            m_descriptor.colorFormat = RenderTextureFormat.RFloat;
            cmd.GetTemporaryRT(ShaderIDs.m_lowResDepthTex, m_descriptor, FilterMode.Point);
            
            ShaderIDs.m_HiZDepthTex[0] = Shader.PropertyToID("_HiZDepthTex0");
            InitRTI(ref RTIs.m_HiZDepthRT[0], ShaderIDs.m_HiZDepthTex[0], m_descriptor, cmd,
                1, 1, RenderTextureFormat.RFloat, 0, true, false, FilterMode.Point);
            
            InitRTI(ref RTIs.m_HitDataRTIs[0], ShaderIDs.m_hitDataTex, m_descriptor, cmd,
                1, 1, RenderTextureFormat.ARGBFloat, 0, true, true, FilterMode.Point);
            
            InitRTI(ref RTIs.m_HitDataRTIs[1], ShaderIDs.m_hitPDFTex, m_descriptor, cmd,
                1, 1, RenderTextureFormat.RFloat, 0, true, true, FilterMode.Point);
            
            m_descriptor.colorFormat = RenderTextureFormat.ARGB64;
            cmd.GetTemporaryRT(ShaderIDs.m_resolvedTex, m_descriptor, FilterMode.Point);
            cmd.GetTemporaryRT(ShaderIDs.m_TAATex, m_descriptor, FilterMode.Point);
            cmd.GetTemporaryRT(ShaderIDs.m_TAAPreTex, m_descriptor, FilterMode.Point);
            
            m_descriptor.width  *= m_SSRSetting.downSample;
            m_descriptor.height *= m_SSRSetting.downSample;
            InitRTI(ref RTIs.m_upSample, ShaderIDs.m_upSampleTex, m_descriptor, cmd,
                1, 1, RenderTextureFormat.ARGB64, 0, true, false, FilterMode.Point);
            
            m_blurLevels = new BlurLevel[m_MaxPyramidSize];
            for (int i = 0; i < m_MaxPyramidSize; ++i)
            {
                m_blurLevels[i] = new BlurLevel
                {
                    downVertical = Shader.PropertyToID("_BlurDownVertical" + i),
                    downHorizontal = Shader.PropertyToID("_BlurDownHorizontal" + i),
                    upVertical = Shader.PropertyToID("_BlurUpVertical" + i),
                    upHorizontal = Shader.PropertyToID("_BlurUpHorizontal" + i)
                };
            }

            m_descriptor.colorFormat = RenderTextureFormat.DefaultHDR;
            cmd.GetTemporaryRT(ShaderIDs.m_combineTex, m_descriptor, FilterMode.Point);
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("SSSR");

            if (m_material == null) return;
            UpdateParas();
            UpdataMatrixs(ref renderingData);

            {
                DoCopyLowResDepth(cmd);
                DoCopyDepth(cmd);
                DoHizDepth(cmd);
                
                DoRayMarch(cmd, ref renderingData, context);

                DoResolved(cmd);
                DoTAA(cmd);
                DoUpSample(cmd);
                DoMipMapBlurReflect(cmd);
                
                DoCombine(cmd, ref renderingData);
                cmd.Blit(ShaderIDs.m_combineTex, m_renderer.cameraColorTarget);
                
                cmd.SetRenderTarget(m_renderer.cameraColorTarget, m_renderer.cameraDepthTarget);
            }
            
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(ShaderIDs.m_HiZDepthTex[0]);
            cmd.ReleaseTemporaryRT(ShaderIDs.m_hitDataTex);
            cmd.ReleaseTemporaryRT(ShaderIDs.m_hitPDFTex);
            cmd.ReleaseTemporaryRT(ShaderIDs.m_resolvedTex);
            cmd.ReleaseTemporaryRT(ShaderIDs.m_TAATex);
            cmd.ReleaseTemporaryRT(ShaderIDs.m_TAAPreTex);
            cmd.ReleaseTemporaryRT(ShaderIDs.m_combineTex);
            for (int i = 0; i < m_maxHizMipMapLevels; ++i)
            {
                cmd.ReleaseTemporaryRT(ShaderIDs.m_HiZDepthTex[i]);
            }

            for (int i = 0; i < m_MaxPyramidSize; ++i)
            {
                cmd.ReleaseTemporaryRT(m_blurLevels[i].downHorizontal);
                cmd.ReleaseTemporaryRT(m_blurLevels[i].downVertical);
                cmd.ReleaseTemporaryRT(m_blurLevels[i].upHorizontal);
                cmd.ReleaseTemporaryRT(m_blurLevels[i].upVertical);
            }
        }

        /// <summary>
        /// find shader pass
        /// </summary>
        private void FindPasses()
        {
            Passes.m_copyDepth      = m_material.FindPass("Copy Depth");
            Passes.m_rayMarch       = m_material.FindPass("Ray March");
            Passes.m_resolved       = m_material.FindPass("Resolved");
            Passes.m_blurReflect    = m_material.FindPass("Blur Reflect");
            Passes.m_temporalfilter = m_material.FindPass("Temporalfilter");
            Passes.m_upSample       = m_material.FindPass("Up Sample");
            Passes.m_combine        = m_material.FindPass("Combine");
        }
        
        public void Setup(SSRSetting passSetting, SSRDebugSetting debugSetting, SSRHizSetting hizSetting, SSRLinearSetting linearSetting, UniversalRenderer renderer)
        {
            m_SSRSetting = passSetting;
            m_SSRDebugSetting = debugSetting;
            m_hizSetting = hizSetting;
            m_linearSetting = linearSetting;
            this.renderPassEvent = m_SSRSetting.passEvent;
            
            m_renderer = renderer;
        }
        
        private Vector4 GetTextureSizeParams(Vector2Int size)
        {
            return new Vector4(size.x, size.y, 1.0f / size.x, 1.0f / size.y);
        }
        
        void InitRTI(ref RenderTargetIdentifier RTI, int texID, RenderTextureDescriptor descriptor, CommandBuffer cmd,
            int downSampleWidth, int downSampleHeight, RenderTextureFormat colorFormat, 
            int depthBufferBits, bool isUseMipmap, bool isAutoGenerateMips,
            FilterMode filterMode)
        {
            descriptor.width           /= downSampleWidth;
            descriptor.height          /= downSampleHeight;
            descriptor.colorFormat      = colorFormat;
            descriptor.depthBufferBits  = depthBufferBits;
            descriptor.useMipMap        = isUseMipmap;
            descriptor.autoGenerateMips = isAutoGenerateMips;
            
            
            RTI = new RenderTargetIdentifier(texID);
            cmd.GetTemporaryRT(texID, descriptor, filterMode);
            cmd.SetGlobalTexture(texID, RTI);
        }

        void UpdateParas()
        {
            m_material.SetVector(ShaderIDs.m_screenSize,          m_screenSize);
            m_material.SetVector(ShaderIDs.m_rayMarchTexSize,     m_rayMarchTexSize);
            m_material.SetVector(ShaderIDs.m_resolvedTexSize,     m_resolvedTexSize);
            m_material.SetVector(ShaderIDs.m_TAATexSize,          m_TAATexSize);
            m_material.SetVector(ShaderIDs.m_blueNoiseTexSize,GetTextureSizeParams(new Vector2Int(m_blueNoiseTex.width, m_blueNoiseTex.height)));
            m_material.SetInt(ShaderIDs.m_hizMaxStep,     m_hizSetting.maxStep);
            m_material.SetInt(ShaderIDs.m_linearMaxStep,m_linearSetting.maxStep);
            m_material.SetFloat(ShaderIDs.m_hizThickness,         m_hizSetting.thickness);
            m_material.SetFloat(ShaderIDs.m_linearThickness,      m_linearSetting.thickness);
            m_material.SetFloat(ShaderIDs.m_hizMaxDistance,       m_hizSetting.maxDistance);
            m_material.SetFloat(ShaderIDs.m_LinearMaxDistance,    m_linearSetting.maxDistance);
            m_material.SetFloat(ShaderIDs.m_hizBinaryCount,       m_hizSetting.binaryStep);
            m_material.SetFloat(ShaderIDs.m_linearBinaryCount,    m_linearSetting.binaryStep);
            m_material.SetFloat(ShaderIDs.m_maxRoughness,         m_SSRSetting.maxRoughness);
            m_material.SetFloat(ShaderIDs.m_edgeFade,             m_SSRSetting.edgeFade);
            m_material.SetFloat(ShaderIDs.m_temporalScale,        m_SSRSetting.temporalScale);
            m_material.SetFloat(ShaderIDs.m_temporalWeight,       m_SSRSetting.temporalWeight);
            m_material.SetFloat(ShaderIDs.m_brightness,           m_SSRSetting.brightness);
            m_material.SetFloat(ShaderIDs.m_BRDFBias,             m_SSRSetting.BRDFBias);
                
            m_material.SetTexture(ShaderIDs.m_blueNoiseTex, m_blueNoiseTex);
            m_material.SetTexture(ShaderIDs.m_preIntegratedTex, m_preIntegratedTex);
        }
        void UpdataMatrixs(ref RenderingData renderingData)
        {
            var viewMatrix = renderingData.cameraData.GetViewMatrix();
            var projectionMatrix = renderingData.cameraData.GetGPUProjectionMatrix();
            m_material.SetMatrix("Matrix_V", viewMatrix);
            m_material.SetMatrix("Matrix_I_V", viewMatrix.inverse);
            m_material.SetMatrix("Matrix_P", projectionMatrix);
            m_material.SetMatrix("Matrix_I_P", projectionMatrix.inverse);
            _Curr_Matrix_VP = projectionMatrix * viewMatrix;
            m_material.SetMatrix("Matrix_VP", _Curr_Matrix_VP);
            m_material.SetMatrix("Matrix_I_VP", _Curr_Matrix_VP.inverse);
            m_material.SetMatrix("_Pre_Matrix_VP", _Pre_Matrix_VP);
        }
        
        void BlitSp(CommandBuffer cmd, RenderTargetIdentifier dest,
            RenderTargetIdentifier depth, Material mat, int passIndex)
        {
            cmd.SetRenderTarget(dest, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, 
                depth, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
            cmd.ClearRenderTarget(false, true, Color.clear);
            cmd.DrawProcedural(Matrix4x4.identity, mat, passIndex, MeshTopology.Quads, 4, 1, null);
        }

        void DoCopyLowResDepth(CommandBuffer cmd)
        {
            cmd.BeginSample("Down Sample Depth");
            cmd.Blit(null, ShaderIDs.m_lowResDepthTex, m_material, Passes.m_copyDepth);
            cmd.EndSample("Down Sample Depth");
        }
        
        void DoCopyDepth(CommandBuffer cmd)
        {
            cmd.BeginSample("Copy Depth");
            cmd.Blit(null, ShaderIDs.m_HiZDepthTex[0], m_material, Passes.m_copyDepth);
            //BlitSp(cmd, ShaderIDs.m_HiZDepthTex[0], m_renderer.cameraDepthTarget, m_material, Passes.m_copyDepth);
            cmd.EndSample("Copy Depth");
            
        }

        void DoHizDepth(CommandBuffer cmd)
        {
            cmd.BeginSample("Hiz");
            var computeShader = Resources.Load<ComputeShader>("HiZ/CS_HiZ");
            if (computeShader == null) return;
            
            var tempDesc = m_descriptor;
            tempDesc.width  /= m_SSRSetting.downSample;
            tempDesc.height /= m_SSRSetting.downSample;
            tempDesc.enableRandomWrite = true;
            tempDesc.colorFormat       = RenderTextureFormat.RFloat;
            tempDesc.useMipMap         = true;
            tempDesc.autoGenerateMips  = false;
            
            Vector2Int currTexSize = new Vector2Int(tempDesc.width, tempDesc.height);
            Vector2Int lastTexSize = currTexSize;
            var lastHizDepthRT = ShaderIDs.m_HiZDepthTex[0];
            
            for (int i = 1; i < m_maxHizMipMapLevels; ++i)
            {
                currTexSize.x /= 2;
                currTexSize.y /= 2;

                tempDesc.width = currTexSize.x;
                tempDesc.height = currTexSize.y;
                ShaderIDs.m_HiZDepthTex[i] = Shader.PropertyToID("_HiZDepthTex" + i);
                RTIs.m_HiZDepthRT[i] = ShaderIDs.m_HiZDepthTex[i];
                cmd.GetTemporaryRT(ShaderIDs.m_HiZDepthTex[i], tempDesc, FilterMode.Point);

                int kernelID = computeShader.FindKernel("GetHiZ");
                cmd.SetComputeTextureParam(computeShader, kernelID, Shader.PropertyToID("_SourceTex"), lastHizDepthRT);
                cmd.SetComputeTextureParam(computeShader, kernelID, Shader.PropertyToID("_RW_OutputTex"), ShaderIDs.m_HiZDepthTex[i]);
                cmd.SetComputeVectorParam(computeShader, Shader.PropertyToID("_HiZTexSize"), 
                    new Vector4(1f / lastTexSize.x, 1f / lastTexSize.y, 1f / currTexSize.x, 1f / currTexSize.y));
                cmd.DispatchCompute(computeShader, kernelID,
                    Mathf.CeilToInt((float)currTexSize.x / 8),
                    Mathf.CeilToInt((float)currTexSize.y / 8),
                    1);
                
                cmd.CopyTexture(ShaderIDs.m_HiZDepthTex[i], 0, 0,ShaderIDs.m_HiZDepthTex[0], 0, i);

                lastTexSize = currTexSize;
                lastHizDepthRT = ShaderIDs.m_HiZDepthTex[i];
            }

            for (int i = 1; i < m_maxHizMipMapLevels; ++i)
            {
                cmd.ReleaseTemporaryRT(ShaderIDs.m_HiZDepthTex[i]);
            }
            cmd.EndSample("Hiz");
        }
        
        void DoRayMarch(CommandBuffer cmd, ref RenderingData renderingData, ScriptableRenderContext context)
        {
            cmd.BeginSample("Ray March");
            
            cmd.SetRenderTarget(RTIs.m_HitDataRTIs, ShaderIDs.m_lowResDepthTex);
            cmd.ClearRenderTarget(false, true, clearColor);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            DrawingSettings drawingSettings = CreateDrawingSettings(
                new ShaderTagId("UniversalForward"),
                ref renderingData,
                renderingData.cameraData.defaultOpaqueSortFlags);
            drawingSettings.overrideMaterial = m_material;
            drawingSettings.overrideMaterialPassIndex = Passes.m_rayMarch;
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.all);
            
            CoreUtils.SetKeyword(cmd, "_SSR_QUALITY_LOW", m_SSRSetting.quality == SSRSetting.SSRQuality.Low);
            CoreUtils.SetKeyword(cmd, "_SSR_QUALITY_MIDDLE", m_SSRSetting.quality == SSRSetting.SSRQuality.Middle);
            CoreUtils.SetKeyword(cmd, "_SSR_QUALITY_HIGH", m_SSRSetting.quality == SSRSetting.SSRQuality.High);
            context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
            
            cmd.EndSample("Ray March");
        }

        void DoResolved(CommandBuffer cmd)
        {
            cmd.BeginSample("Resolved");
            BlitSp(cmd, ShaderIDs.m_resolvedTex, ShaderIDs.m_lowResDepthTex, m_material, Passes.m_resolved);
            cmd.EndSample("Resolved");
        }

        void DoTAA(CommandBuffer cmd)
        {
            cmd.BeginSample("Temporalfilter");
            if (m_isFirstPreTex == true)
            {
                cmd.Blit(ShaderIDs.m_resolvedTex, ShaderIDs.m_TAATex);
                m_isFirstPreTex = false;
            }
            BlitSp(cmd, ShaderIDs.m_TAATex, ShaderIDs.m_lowResDepthTex, m_material, Passes.m_temporalfilter);
            cmd.Blit(ShaderIDs.m_TAATex, ShaderIDs.m_TAAPreTex);
            
            _Pre_Matrix_VP = _Curr_Matrix_VP;
            cmd.EndSample("Temporalfilter");
        }

        void DoUpSample(CommandBuffer cmd)
        {
            cmd.BeginSample("Up Sample");
            cmd.Blit(ShaderIDs.m_TAATex, ShaderIDs.m_upSampleTex, m_material, Passes.m_upSample);
            cmd.EndSample("Up Sample");
        }
        
        void DoMipMapBlurReflect(CommandBuffer cmd)
        {
            cmd.BeginSample("Blur Reflect in mipmap");
            var tempDesc = m_descriptor;

            int currWidth = tempDesc.width / 2;
            int currHeight = tempDesc.height / 2;
            
            for (int i = 0; i < m_MaxPyramidSize; ++i)
            {
                int downVertical   = m_blurLevels[i].downVertical;
                int downHorizontal = m_blurLevels[i].downHorizontal;
                int upVertical     = m_blurLevels[i].upVertical;
                int upHorizontal   = m_blurLevels[i].upHorizontal;
                
                cmd.GetTemporaryRT(downVertical, currWidth, currHeight, 0, FilterMode.Point, RenderTextureFormat.ARGB64);
                cmd.GetTemporaryRT(downHorizontal, currWidth, currHeight, 0, FilterMode.Point, RenderTextureFormat.ARGB64);
                cmd.GetTemporaryRT(upVertical, currWidth, currHeight, 0, FilterMode.Point, RenderTextureFormat.ARGB64);
                cmd.GetTemporaryRT(upHorizontal, currWidth, currHeight, 0, FilterMode.Point, RenderTextureFormat.ARGB64);
                
                currWidth = Mathf.Max(currWidth / 2, 1);
                currHeight = Mathf.Max(currHeight / 2, 1);
            }
            
            var lastBlur = RTIs.m_upSample;
            for (int i = 0; i < m_MaxPyramidSize; ++i)
            {
                cmd.SetGlobalTexture("_MainTex", lastBlur);
                cmd.SetGlobalVector(ShaderIDs.m_blurOffset, new Vector4(m_SSRSetting.blurRadius / tempDesc.width, 0, 0, 0));
                cmd.Blit(lastBlur, m_blurLevels[i].downHorizontal, m_material, Passes.m_blurReflect);
                
                cmd.SetGlobalTexture("_MainTex", m_blurLevels[i].downHorizontal);
                cmd.SetGlobalVector(ShaderIDs.m_blurOffset, new Vector4(0, m_SSRSetting.blurRadius / tempDesc.height, 0, 0));
                cmd.Blit(m_blurLevels[i].downHorizontal, m_blurLevels[i].downVertical, m_material, Passes.m_blurReflect);

                lastBlur = m_blurLevels[i].downVertical;
                cmd.CopyTexture(m_blurLevels[i].downVertical, 0, 0, RTIs.m_upSample, 0, i + 1);
            }

            // int lastBlurUp = m_blurLevels[m_SSRSetting.blurIteration - 1].downVertical;
            // cmd.CopyTexture(lastBlurUp, 0, 0, RTIs.m_upSample, 0, m_SSRSetting.blurIteration - 1);
            // for (int i = m_SSRSetting.blurIteration - 2; i >= 0; --i)
            // {
            //     int upVertical     = m_blurLevels[i].upVertical;
            //     int upHorizontal   = m_blurLevels[i].upHorizontal;
            //     
            //     cmd.SetGlobalTexture("_MainTex", lastBlurUp);
            //     cmd.SetGlobalVector(ShaderIDs.m_blurOffset, new Vector4(m_SSRSetting.blurRadius / tempDesc.width, 0, 0, 0));
            //     cmd.Blit(lastBlurDown, upHorizontal, m_material, Passes.m_blurReflect);
            //     
            //     cmd.SetGlobalTexture("_MainTex", upHorizontal);
            //     cmd.SetGlobalVector(ShaderIDs.m_blurOffset, new Vector4(0, m_SSRSetting.blurRadius / tempDesc.height, 0, 0));
            //     cmd.Blit(upHorizontal, upVertical, m_material, Passes.m_blurReflect);
            //
            //     lastBlurUp = upHorizontal;
            //     
            //     cmd.CopyTexture(lastBlurUp, 0, 0, RTIs.m_upSample, 0, i);
            // }

            // int j = m_SSRSetting.blurIteration - 1;
            // if (j < m_MaxPyramidSize - 1)
            // {
            //     cmd.Blit(m_blurLevels[j].downVertical, m_blurLevels[j+1].downVertical);
            //     cmd.CopyTexture(m_blurLevels[j+1].downVertical, 0, 0, RTIs.m_upSample, 0, j + 1);
            //     j++;
            // }
            
            
            cmd.EndSample("Blur Reflect in mipmap");
        }

        void DoCombine(CommandBuffer cmd, ref RenderingData renderingData)
        {
            cmd.BeginSample("Combine");
            CoreUtils.SetKeyword(cmd, "_DEBUG_HITUV", m_SSRDebugSetting.enableDebug == true && m_SSRDebugSetting.debugMode == SSRDebugMode.Hituv);
            CoreUtils.SetKeyword(cmd, "_DEBUG_HITDEPTH", m_SSRDebugSetting.enableDebug == true && m_SSRDebugSetting.debugMode == SSRDebugMode.HitDepth);
            CoreUtils.SetKeyword(cmd, "_DEBUG_HITMASK", m_SSRDebugSetting.enableDebug == true && m_SSRDebugSetting.debugMode == SSRDebugMode.HitMask);
            cmd.Blit(null, ShaderIDs.m_combineTex, m_material, Passes.m_combine);
            cmd.EndSample("Combine");
        }
    }
}