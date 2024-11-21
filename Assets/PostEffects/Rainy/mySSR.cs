using System.Collections.Generic;
using Unity.Mathematics;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System;

public class mySSR : ScriptableRendererFeature
{
    public class CustomRenderPass : ScriptableRenderPass
    {
        private FilteringSettings filteringSettings;
        private List<ShaderTagId> shaderTagsList = new List<ShaderTagId>();

        //private RTHandle rtSolidColor, rtSolidDepth, mSSRTexture0, mSSRTexture1;

        Settings settings;
        ProfilingSampler _profilingSampler;
        RenderTextureDescriptor mSSRDescriptor;
        int mProjectionParams2ID = Shader.PropertyToID("_ProjectionParams2");
        int mCameraViewTopLeftCornerID = Shader.PropertyToID("_CameraViewTopLeftCorner");
        int mCameraViewXExtentID = Shader.PropertyToID("_CameraViewXExtent");
        int mCameraViewYExtentID = Shader.PropertyToID("_CameraViewYExtent");
        int mSourceSizeID = Shader.PropertyToID("_SourceSize");
        int mHiZBufferFromMiplevelID = Shader.PropertyToID("_HierarchicalZBufferTextureFromMipLevel");
        int mHiZBufferToMiplevelID = Shader.PropertyToID("_mHiZBufferToMiplevel");
        int mMaxHiZBufferTextureipLevelID = Shader.PropertyToID("_MaxHierarchicalZBufferTextureMipLevel");
        int mHiZBufferTextureID = Shader.PropertyToID("_HierarchicalZBufferTexture");
        string mHiZBufferTextureName = "_mHiZBufferTexture";
        RTHandle mCameraColorTexture, mCameraDepthTexture, mDestinationTexture;
        RTHandle rtSolidColor, rtSolidDepth, rtSSR, rtRes;
        RTHandle mSSRTexture0, mSSRTexture1;
        RTHandle mHiZBufferTexture;
        RTHandle[] mHiZBufferTextures = new RTHandle[5];
        RenderTextureDescriptor mHiZBufferDescriptor;
        RenderTextureDescriptor[] mHiZBufferDescriptors = new RenderTextureDescriptor[8];

        public CustomRenderPass(Settings settings, string name)
        {
            filteringSettings = new FilteringSettings(RenderQueueRange.all, settings.layerMask);
            shaderTagsList.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagsList.Add(new ShaderTagId("UniversalForward"));
            shaderTagsList.Add(new ShaderTagId("UniversalForwardOnly"));

            this.settings = settings;
            _profilingSampler = new ProfilingSampler(name);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            // 把高和宽变换为2的整次幂 然后除以2
            var width = Math.Max((int)Math.Ceiling(Mathf.Log(desc.width, 2) - 1.0f), 1);
            var height = Math.Max((int)Math.Ceiling(Mathf.Log(desc.height, 2) - 1.0f), 1);
            width = 1 << width;
            height = 1 << height;
            width = desc.width;
            height = desc.height;

            var mHiZBufferDescriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.RFloat, 0, settings.MipCount);
            mHiZBufferDescriptor.msaaSamples = 1;
            mHiZBufferDescriptor.useMipMap = true;
            mHiZBufferDescriptor.sRGB = false;// linear
            RenderingUtils.ReAllocateIfNeeded(ref mHiZBufferTexture, mHiZBufferDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: mHiZBufferTextureName);

            for (int i = 0; i < settings.MipCount; i++)
            {
                mHiZBufferDescriptors[i] = new RenderTextureDescriptor(width, height, RenderTextureFormat.RFloat, 0, 1);
                mHiZBufferDescriptors[i].msaaSamples = 1;
                mHiZBufferDescriptors[i].useMipMap = false;
                mHiZBufferDescriptors[i].sRGB = false;// linear
                RenderingUtils.ReAllocateIfNeeded(ref mHiZBufferTextures[i], mHiZBufferDescriptors[i], FilterMode.Bilinear, TextureWrapMode.Clamp, name: mHiZBufferTextureName + i);
                // generate mipmap
                width = Math.Max(width / 2, 1);
                height = Math.Max(height / 2, 1);
            }

            // 发送参数
            Matrix4x4 view = renderingData.cameraData.GetViewMatrix();
            Matrix4x4 proj = renderingData.cameraData.GetProjectionMatrix();
            Matrix4x4 vp = proj * view;

            // 将camera view space 的平移置为0，用来计算world space下相对于相机的vector
            Matrix4x4 cview = view;
            cview.SetColumn(3, new Vector4(0.0f, 0.0f, 0.0f, 1.0f));
            Matrix4x4 cviewProj = proj * cview;

            // 计算viewProj逆矩阵，即从裁剪空间变换到世界空间
            Matrix4x4 cviewProjInv = cviewProj.inverse;

            // 计算世界空间下，近平面四个角的坐标
            var near = renderingData.cameraData.camera.nearClipPlane;
            Vector4 topLeftCorner = cviewProjInv * new Vector4(-near, near, -near, near);
            Vector4 topRightCorner = cviewProjInv * new Vector4(near, near, -near, near);
            Vector4 bottomLeftCorner = cviewProjInv * new Vector4(-near, -near, -near, near);

            // 计算相机近平面上方向向量
            Vector4 cameraXExtent = topRightCorner - topLeftCorner;
            Vector4 cameraYExtent = bottomLeftCorner - topLeftCorner;

            near = renderingData.cameraData.camera.nearClipPlane;

            // 发送ReconstructViewPos参数
            settings.blitMaterial.SetVector(mCameraViewTopLeftCornerID, topLeftCorner);
            settings.blitMaterial.SetVector(mCameraViewXExtentID, cameraXExtent);
            settings.blitMaterial.SetVector(mCameraViewYExtentID, cameraYExtent);
            settings.blitMaterial.SetVector(mProjectionParams2ID, new Vector4(1.0f / near, renderingData.cameraData.worldSpaceCameraPos.x, renderingData.cameraData.worldSpaceCameraPos.y, renderingData.cameraData.worldSpaceCameraPos.z));

            // 分配RTHandle
            mSSRDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            mSSRDescriptor.msaaSamples = 1;
            mSSRDescriptor.depthBufferBits = 0;
            // colorDesc.colorFormat = RenderTextureFormat.ARGB32;


            Vector2 scaleFactor = 1.0f / settings.Downsample * new Vector2(1, 1);
            RenderingUtils.ReAllocateIfNeeded(ref mSSRTexture0, scaleFactor, mSSRDescriptor, FilterMode.Bilinear, name: "_SSRTexture0");
            RenderingUtils.ReAllocateIfNeeded(ref mSSRTexture1, scaleFactor, mSSRDescriptor, FilterMode.Bilinear, name: "_SSRTexture1");

            RenderingUtils.ReAllocateIfNeeded(ref rtSolidColor, mSSRDescriptor, name: "_mySolidRT");
            cmd.SetGlobalTexture("_mySolidRT", rtSolidColor);

            RenderingUtils.ReAllocateIfNeeded(ref rtSSR, mSSRDescriptor, name: "_rtSSR");
            RenderingUtils.ReAllocateIfNeeded(ref rtRes, mSSRDescriptor, name: "_ssrResult");

            // 发送SSR参数
            settings.blitMaterial.SetVector(mSourceSizeID, new Vector4(mSSRDescriptor.width, mSSRDescriptor.height, 1.0f / mSSRDescriptor.width, 1.0f / mSSRDescriptor.height));
            settings.blitMaterial.SetFloat("MAXDISTANCE", settings.MaxDistance);
            settings.blitMaterial.SetFloat("STRIDE", settings.Stride);
            settings.blitMaterial.SetFloat("STEP_COUNT", settings.StepCount);
            settings.blitMaterial.SetFloat("THICKNESS", settings.Thickness);

            settings.blitMaterial.SetFloat("_debugSSR", settings._debugSSR ? 1 : 0);
            settings.blitMaterial.SetFloat("INTENSITY", settings.Intensity);

            settings.blitMaterial.SetVector("_myBlitTextureSize", new Vector4(mSSRDescriptor.width, mSSRDescriptor.height));

            // 渲染目标
            rtSolidDepth = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            //ConfigureInput(ScriptableRenderPassInput.Normal);
            ConfigureTarget(rtSolidColor, rtSolidDepth); //实验中 rtSolidDepth不加好像没有深度测试效果
            ConfigureClear(ClearFlag.Color, Color.black);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            mCameraColorTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
            mCameraDepthTexture = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            mDestinationTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;

            using (new ProfilingScope(cmd, _profilingSampler))
            {
                // draw mask
                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagsList, ref renderingData, sortingCriteria);
                drawingSettings.overrideMaterialPassIndex = 0;
                drawingSettings.overrideMaterial = settings.overrideMaterial;
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);

                // 0.Mip init
                Blitter.BlitCameraTexture(cmd, mCameraDepthTexture, mHiZBufferTextures[0]);
                cmd.CopyTexture(mHiZBufferTextures[0], 0, 0, mHiZBufferTexture, 0, 0);

                for (int i = 1; i < settings.MipCount; i++)
                {
                    cmd.SetGlobalFloat(mHiZBufferFromMiplevelID, i - 1);
                    cmd.SetGlobalFloat(mHiZBufferToMiplevelID, i);
                    cmd.SetGlobalVector(mSourceSizeID, new Vector4(mHiZBufferDescriptors[i - 1].width, mHiZBufferDescriptors[i - 1].height, 1.0f / mHiZBufferDescriptors[i - 1].width, 1.0f / mHiZBufferDescriptors[i - 1].height));
                    Blitter.BlitCameraTexture(cmd, mHiZBufferTextures[i - 1], mHiZBufferTextures[i], settings.blitMaterial, 0);

                    cmd.CopyTexture(mHiZBufferTextures[i], 0, 0, mHiZBufferTexture, 0, i);
                }

                // set hiz texture
                cmd.SetGlobalFloat(mMaxHiZBufferTextureipLevelID, settings.MipCount - 1);
                cmd.SetGlobalTexture(mHiZBufferTextureID, mHiZBufferTexture);

                // 1.SSR
                Blitter.BlitCameraTexture(cmd, mCameraColorTexture, rtSSR, settings.blitMaterial, 1);
                //Blitter.BlitCameraTexture(cmd, rtSolidColor, mDestinationTexture);

                // 2.Kawase Blur
                for (int t = 0; t < settings.Loop; t++)
                {
                    settings.blitMaterial.SetFloat("_Blur", t * settings.Blur + 1);
                    if (t == 0)
                    {
                        Blitter.BlitCameraTexture(cmd, rtSSR, mSSRTexture0, settings.blitMaterial, 2);
                    }
                    else if (t % 2 == 1)
                    {
                        Blitter.BlitCameraTexture(cmd, mSSRTexture0, mSSRTexture1, settings.blitMaterial, 2);
                    }
                    else
                    {
                        Blitter.BlitCameraTexture(cmd, mSSRTexture1, mSSRTexture0, settings.blitMaterial, 2);
                    }
                }
                if (settings._debugSSR)
                {
                    Blitter.BlitCameraTexture(cmd, settings.Loop % 2 == 1 ? mSSRTexture0 : mSSRTexture1, mDestinationTexture);
                }
                else
                {
                    // 3.Additive Pass
                    Blitter.BlitCameraTexture(cmd, settings.Loop % 2 == 1 ? mSSRTexture0 : mSSRTexture1, rtRes);
                }
                cmd.SetGlobalTexture("_ssrResult", rtRes);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            mCameraColorTexture = null;
            mCameraDepthTexture = null;
            mDestinationTexture = null;
        }

        public void Dispose()
        {
            mCameraColorTexture?.Release();
            mCameraDepthTexture?.Release();
            mDestinationTexture?.Release();

            mSSRTexture0?.Release();
            mSSRTexture1?.Release();

            rtSolidColor?.Release();
            rtSolidDepth?.Release();
            rtSSR?.Release();

            for (var i = 0; i < 5; i++)
            {
                mHiZBufferTextures[i]?.Release();
            }
        }
    }

    //--------------------------------------------------------------------------------------------
    [System.Serializable]
    public class Settings
    {
        public bool showInSceneView = true;
        public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingOpaques;

        [Header("Draw Renderers Settings")]
        public LayerMask layerMask = 1;
        public Material overrideMaterial;

        [Header("Blur Settings")]
        [Range(1, 10)]
        public int Downsample = 2;
        [Range(1, 10)]
        public int Loop = 3;
        [Range(0.0f, 5)]
        public float Blur = 3.0f;

        [Header("Blit Settings")]
        public Material blitMaterial;

        [Header("SSR Settings")]
        [Range(0.0f, 1.0f)]
        public float Intensity = 0.7f;
        public float MaxDistance = 10f;
        public float Stride = 2f;
        public int StepCount = 200;
        public float Thickness = 0.25f;
        public int MipCount = 3;
        [Header("Debug")]
        public bool _debugSSR = true;
    }

    public Settings settings = new Settings();
    CustomRenderPass m_ScriptablePass;

    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass(settings, this.name);
        m_ScriptablePass.renderPassEvent = settings.passEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.overrideMaterial == null || settings.blitMaterial == null) return;

        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType == CameraType.Preview) return; // Ignore feature for editor/inspector previews & asset thumbnails
        if (!settings.showInSceneView && cameraType == CameraType.SceneView) return;

        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        m_ScriptablePass.Dispose();
    }
}