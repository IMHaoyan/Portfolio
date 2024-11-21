using System.Collections.Generic;
using Unity.Mathematics;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class myBloom : ScriptableRendererFeature
{
    public class CustomRenderPass : ScriptableRenderPass
    {
        private Settings settings;
        private FilteringSettings filteringSettings;
        private ProfilingSampler _profilingSampler;
        private List<ShaderTagId> shaderTagsList = new List<ShaderTagId>();
        private RTHandle rtSolidColor, rtSolidTemp, rtSolidDepth, rtTempColor0, rtTempColor1;

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
            colorDesc.depthBufferBits = 0;

            RenderingUtils.ReAllocateIfNeeded(ref rtSolidColor, colorDesc, name: "_mySolidRT");
            RenderingUtils.ReAllocateIfNeeded(ref rtSolidTemp, colorDesc, name: "_mySolidRT1");

            Vector2 scaleFactor = new Vector2(1.0f, 1.0f)/settings.Downsample;
            RenderingUtils.ReAllocateIfNeeded(ref rtTempColor0, scaleFactor, colorDesc, FilterMode.Bilinear, name: "_TestRT0");
            RenderingUtils.ReAllocateIfNeeded(ref rtTempColor1, scaleFactor, colorDesc, FilterMode.Bilinear, name: "_TestRT1");

            rtSolidDepth = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            ConfigureTarget(rtSolidColor, rtSolidDepth);
            ConfigureClear(ClearFlag.Color, new Color(0, 0, 0, 0));

            settings.blitMaterial.SetVector("_camsize", new Vector4(colorDesc.width, colorDesc.height));

            //settings.blitMaterial.SetFloat("_Loop", settings.Loop);
            settings.blitMaterial.SetFloat("_BlurIntensity", settings.BlurIntensity);
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


                RTHandle camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                //Blitter.BlitCameraTexture(cmd, rtSolidColor, camTarget, settings.blitMaterial, 0);
                cmd.SetGlobalTexture("_mySolidRT", rtSolidColor);
                settings.blitMaterial.SetFloat("_BloomThreshold",settings.BloomThreshold);

                Blitter.BlitCameraTexture(cmd, camTarget, rtSolidTemp, settings.blitMaterial, 2);
                Blitter.BlitCameraTexture(cmd, rtSolidTemp, rtSolidColor);

                for (int t = 0; t < settings.Loop; t++)
                {
                    settings.blitMaterial.SetFloat("_Blur", t * settings.Blur + 1);
                    if (t == 0)
                    {
                        Blitter.BlitCameraTexture(cmd, rtSolidColor, rtTempColor0, settings.blitMaterial, 0);
                    }
                    else if (t % 2 == 1)
                    {
                        Blitter.BlitCameraTexture(cmd, rtTempColor0, rtTempColor1, settings.blitMaterial, 0);
                    }
                    else
                    {

                        Blitter.BlitCameraTexture(cmd, rtTempColor1, rtTempColor0, settings.blitMaterial, 0);
                    }
                }
                Blitter.BlitCameraTexture(cmd, settings.Loop % 2 == 1 ? rtTempColor0 : rtTempColor1, rtSolidColor);


                settings.blitMaterial.SetFloat("_showBlur", settings.showBlur ? 1 : 0);
                Blitter.BlitCameraTexture(cmd, camTarget, rtSolidTemp, settings.blitMaterial, 1);
                Blitter.BlitCameraTexture(cmd, rtSolidTemp, camTarget);

            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }

        public void Dispose()
        {
            rtSolidColor?.Release();
            rtSolidDepth?.Release();
            rtSolidTemp?.Release();
            rtTempColor0?.Release();
            rtTempColor1?.Release();
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

        [Header("Blur Settings")]
        [Range(2, 10)]
        public int Downsample = 2;
        [Range(1, 10)]
        public int Loop = 2;
        [Range(0.0f, 5)]
        public float Blur = 0.5f;
        public bool showBlur = false;

        [Range(0.0f, 2)]
        public float BloomThreshold = 0.5f;
        
        [Range(0.0f, 5)]
        public float BlurIntensity = 1.0f;

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