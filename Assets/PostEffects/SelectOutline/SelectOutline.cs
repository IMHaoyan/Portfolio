using System.Collections.Generic;
using Unity.Mathematics;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SelectOutline : ScriptableRendererFeature
{
    public class CustomRenderPass : ScriptableRenderPass
    {
        private Settings settings;
        private FilteringSettings filteringSettings;
        private ProfilingSampler _profilingSampler;
        private List<ShaderTagId> shaderTagsList = new List<ShaderTagId>();
        private RTHandle rtSolidColor, rtTempColor, rtSolidDepth;

        public CustomRenderPass(Settings settings, string name)
        {
            this.settings = settings;
            filteringSettings = new FilteringSettings(RenderQueueRange.all, settings.layerMask);

            // Use default tags
            shaderTagsList.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagsList.Add(new ShaderTagId("UniversalForward"));
            shaderTagsList.Add(new ShaderTagId("UniversalForwardOnly"));
            _profilingSampler = new ProfilingSampler(name);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var colorDesc = renderingData.cameraData.cameraTargetDescriptor;
            colorDesc.colorFormat = RenderTextureFormat.ARGB32;
            //RenderingUtils.ReAllocateIfNeeded(ref rtSolidDepth, colorDesc, name: "_rtSolidDepth");
            colorDesc.depthBufferBits = 0;

            RenderingUtils.ReAllocateIfNeeded(ref rtTempColor, colorDesc, name: "_rtTempColor");

            // Set up custom color target buffer (to render objects into)
            //, 1.0f/4.0f*new Vector2(1,1)
            RenderingUtils.ReAllocateIfNeeded(ref rtSolidColor, colorDesc, name: "_mySolidRT");
            // Using camera's depth target (that way we can ZTest with scene objects still)

            rtSolidDepth = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            settings.blitMaterial.SetColor("_TintColor", settings.tintColor);
            settings.blitMaterial.SetVector("_camsize", new Vector4(colorDesc.width, colorDesc.height));
            settings.blitMaterial.SetFloat("_Distance", settings.Distance);

            ConfigureTarget(rtSolidColor, rtSolidDepth);
            //因为我们要用到当前的DepthBuffer，所以只清空Color
            ConfigureClear(ClearFlag.Color, new Color(0, 0, 0, 0));
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, _profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                // Draw Renderers to Render Target (set up in OnCameraSetup)
                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagsList, ref renderingData, sortingCriteria);
                drawingSettings.overrideMaterialPassIndex = settings.overrideMaterialPass; drawingSettings.overrideMaterial = settings.overrideMaterial;

                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
                //cmd.SetGlobalTexture("_mySolidRT", rtSolidColor);

                RTHandle camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                //Blitter.BlitCameraTexture(cmd, camTarget, rtTempColor, settings.blitMaterial, 0);
                //Blitter.BlitCameraTexture(cmd, rtTempColor, camTarget);
                Blitter.BlitCameraTexture(cmd, rtSolidColor, camTarget, settings.blitMaterial, 0);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }

        public void Dispose()
        {
            rtSolidColor?.Release();
            rtTempColor?.Release();
        }
    }

    //--------------------------------------------------------------------------------------------
    [System.Serializable]
    public class Settings
    {
        public bool showInSceneView = true;
        public RenderPassEvent _event = RenderPassEvent.AfterRenderingOpaques;

        [Header("Draw Renderers Settings")]
        public LayerMask layerMask = 1;
        public Material overrideMaterial;
        public int overrideMaterialPass;
        [Range(1, 100)]
        public int Distance = 10;
        public Color tintColor = new Color(1, 1, 1, 1);
        public string rtSolidColorName = "";

        [Header("Blit Settings")]
        public Material blitMaterial;
    }

    public Settings settings = new Settings();
    CustomRenderPass m_ScriptablePass;

    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass(settings, this.name);
        m_ScriptablePass.renderPassEvent = settings._event;
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