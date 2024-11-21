using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumeLight : ScriptableRendererFeature
{

    public class CustomRenderPass : ScriptableRenderPass
    {

        private Settings settings;
        private FilteringSettings filteringSettings;
        private ProfilingSampler _profilingSampler;
        private List<ShaderTagId> shaderTagsList = new List<ShaderTagId>();
        private RTHandle rtSolid, rtResult, rtTemp0, rtTemp1;

        public CustomRenderPass(Settings settings, string name)
        {
            this.settings = settings;
            filteringSettings = new FilteringSettings(RenderQueueRange.opaque, settings.layerMask);

            // Use default tags
            shaderTagsList.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagsList.Add(new ShaderTagId("UniversalForward"));
            shaderTagsList.Add(new ShaderTagId("UniversalForwardOnly"));
            _profilingSampler = new ProfilingSampler(name);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var colorDesc = renderingData.cameraData.cameraTargetDescriptor;
            colorDesc.depthBufferBits = 0;

            RenderingUtils.ReAllocateIfNeeded(ref rtSolid, colorDesc, name: settings.rtSolidName);
            cmd.SetGlobalTexture(settings.rtSolidName, rtSolid);//链接到shader中的全局变量

            RenderingUtils.ReAllocateIfNeeded(ref rtResult, colorDesc, name: "_rtResult");

            Vector2 scaleFactor = 1.0f / settings.Downsample * new Vector2(1, 1);
            RenderingUtils.ReAllocateIfNeeded(ref rtTemp0, scaleFactor, colorDesc, FilterMode.Bilinear, name: "_rtTemp0");
            RenderingUtils.ReAllocateIfNeeded(ref rtTemp1, scaleFactor, colorDesc, FilterMode.Bilinear, name: "_rtTemp1");

            // Using camera's depth target (that way we can ZTest with scene objects still)
            RTHandle rtCameraDepth = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            ConfigureTarget(rtSolid, rtCameraDepth);
            ConfigureClear(ClearFlag.Color, new Color(0, 0, 0, 0));

            settings.blitMaterial.SetVector("_myBlitTextureSize", new Vector4(colorDesc.width, colorDesc.height));
            settings.blitMaterial.SetColor("_TintColor", settings.tintColor);
            settings.blitMaterial.SetFloat("_StepCount", settings.StepCount);
            settings.blitMaterial.SetFloat("_Intensity", settings.Intensity);
            //settings.blitMaterial.SetFloat("_RandomNumber", Random.Range(0.0f, 1.0f));
            settings.blitMaterial.SetFloat("_RandomNumber", 0.6f);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            using (new ProfilingScope(cmd, _profilingSampler))
            {
                // Draw Renderers to Render Target (set up in OnCameraSetup)
                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagsList, ref renderingData, sortingCriteria);
                drawingSettings.overrideMaterialPassIndex = 0;
                drawingSettings.overrideMaterial = settings.overrideMaterial;
                //context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);


                RTHandle camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;

                // 1.Raymarching
                Blitter.BlitCameraTexture(cmd, camTarget, rtResult, settings.blitMaterial, 0);
                //Blitter.BlitCameraTexture(cmd, rtResult, camTarget);

                // 2.Kawase Blur
                for (int t = 0; t < settings.Loop; t++)
                {
                    settings.blitMaterial.SetFloat("_Blur", t * settings.Blur + 1);
                    if (t == 0)
                    {
                        Blitter.BlitCameraTexture(cmd, rtResult, rtTemp0, settings.blitMaterial, 1);
                    }
                    else if (t % 2 == 1)
                    {
                        Blitter.BlitCameraTexture(cmd, rtTemp0, rtTemp1, settings.blitMaterial, 1);
                    }
                    else
                    {
                        Blitter.BlitCameraTexture(cmd, rtTemp1, rtTemp0, settings.blitMaterial, 1);
                    }
                }

                // 3.Additive Pass
                if (settings._debug == 0)
                {
                    Blitter.BlitCameraTexture(cmd, rtResult, camTarget);
                }
                else if (settings._debug == 1)
                {
                    Blitter.BlitCameraTexture(cmd, settings.Loop % 2 == 1 ? rtTemp0 : rtTemp1, camTarget);
                }
                else
                {
                    Blitter.BlitCameraTexture(cmd, settings.Loop % 2 == 1 ? rtTemp0 : rtTemp1, camTarget, settings.blitMaterial, 2);
                }
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }

        // Cleanup Called by feature below
        public void Dispose()
        {
            rtSolid?.Release();
            rtResult?.Release();
            rtTemp0?.Release();
            rtTemp1?.Release();
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
        public string rtSolidName = "_myRT";

        [Header("Blit Settings")]
        public Material blitMaterial;
        public Color tintColor = new Color(1, 1, 1, 1);

        [Range(2, 64)]
        public int StepCount = 16;
        public float Intensity = 100;

        [Header("Blur Settings")]
        [Range(1, 10)]
        public int Downsample = 3;
        [Range(1, 10)]
        public int Loop = 4;
        [Range(0.0f, 5)]
        public float Blur = 2.0f;
        [Header("Debug")]
        [Range(0, 2)]
        public int _debug = 2;
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