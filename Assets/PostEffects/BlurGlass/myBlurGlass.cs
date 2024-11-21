using System.Collections.Generic;
using Unity.Mathematics;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class myBlurGlass : ScriptableRendererFeature
{
    public class CustomRenderPass : ScriptableRenderPass
    {
        private Settings settings;
        private ProfilingSampler _profilingSampler;
        private RTHandle rtBlurColor, rtTempColor0, rtTempColor1;

        public CustomRenderPass(Settings settings, string name)
        {
            this.settings = settings;
            _profilingSampler = new ProfilingSampler(name);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var colorDesc = renderingData.cameraData.cameraTargetDescriptor;
            colorDesc.colorFormat = RenderTextureFormat.ARGB32;
            colorDesc.depthBufferBits = 0;

            RenderingUtils.ReAllocateIfNeeded(ref rtBlurColor, colorDesc, name: "_myBlurRT");

            Vector2 scaleFactor = 1.0f / settings.Downsample * new Vector2(1, 1);
            RenderingUtils.ReAllocateIfNeeded(ref rtTempColor0, scaleFactor, colorDesc, FilterMode.Bilinear, name: "_TestRT0");
            RenderingUtils.ReAllocateIfNeeded(ref rtTempColor1, scaleFactor, colorDesc, FilterMode.Bilinear, name: "_TestRT1");


            settings.blitMaterial.SetVector("_camsize", new Vector4(colorDesc.width, colorDesc.height));
            settings.blitMaterial.SetFloat("_Loop", settings.Loop);

            settings.BlurGlassMaterial.SetFloat("_IsBlur", settings.IsBlur ? 1 : 0);
            settings.BlurGlassMaterial.SetFloat("_TintScale", settings.TintScale);
            settings.BlurGlassMaterial.SetFloat("_Amount", settings.DistortAmount);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, _profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                RTHandle camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;

                for (int t = 0; t < settings.Loop; t++)
                {
                    settings.blitMaterial.SetFloat("_Blur", t * settings.Blur + 1);
                    if (t == 0)
                    {
                        Blitter.BlitCameraTexture(cmd, camTarget, rtTempColor0, settings.blitMaterial, 0);
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
                Blitter.BlitCameraTexture(cmd, settings.Loop % 2 == 1 ? rtTempColor0 : rtTempColor1, rtBlurColor);
                cmd.SetGlobalTexture("_myBlurRT", rtBlurColor);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }

        public void Dispose()
        {
            rtBlurColor?.Release();
            rtTempColor0?.Release();
            rtTempColor1?.Release();
        }
    }

    //--------------------------------------------------------------------------------------------
    [System.Serializable]
    public class Settings
    {
        public bool showInSceneView = true;
        public RenderPassEvent _event = RenderPassEvent.BeforeRenderingTransparents;

        [Header("Blur Glass Material")]
        public Material BlurGlassMaterial;

        [Range(0, 100)]
        public int DistortAmount = 10;
        [Range(0.0f, 1.0f)]
        public float TintScale = 0.5f;
        public bool IsBlur = false;

        [Header("Blur Settings")]
        [Range(2, 10)]
        public int Downsample = 2;
        [Range(1, 10)]
        public int Loop = 2;
        [Range(0.0f, 5)]
        public float Blur = 0.5f;

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
        if (settings.BlurGlassMaterial == null || settings.blitMaterial == null) return;

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