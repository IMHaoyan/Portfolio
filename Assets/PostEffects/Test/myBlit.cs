using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class myBlit : ScriptableRendererFeature
{
    class myBlitPass : ScriptableRenderPass
    {
        public Material passMat = null;
        RenderTargetIdentifier passSource { get; set; }
        int tempID = Shader.PropertyToID("_TestRT");

        public myBlitPass(Setting mySetting)
        {
            passMat = mySetting.myMat;
        }
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            passSource = renderingData.cameraData.renderer.cameraColorTargetHandle;

            RenderTextureDescriptor CameraTexDesc = renderingData.cameraData.cameraTargetDescriptor;
            CameraTexDesc.depthBufferBits = 0;
            cmd.GetTemporaryRT(tempID, CameraTexDesc);
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("myBlit");//Get a new Command Buffer and assign a name to it.

            cmd.Blit(passSource, tempID, passMat);
            cmd.Blit(tempID, passSource);

            context.ExecuteCommandBuffer(cmd);//执行命令

            cmd.ReleaseTemporaryRT(tempID);
            cmd.Clear();
            cmd.Release();
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    [System.Serializable]
    public class Setting
    {
        public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingPostProcessing;
        public Material myMat;
        public Color TintColor = new Color(1, 1, 0);
    }

    public Setting mySetting = new Setting();
    myBlitPass myPass;

    public override void Create()
    {
        mySetting.myMat.SetColor("_TintColor", mySetting.TintColor);
        myPass = new myBlitPass(mySetting);
        myPass.renderPassEvent = mySetting.passEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (mySetting.myMat == null)
        {
            Debug.LogError("材质球丢失！请设置材质球");
        }
        renderer.EnqueuePass(myPass);
    }
}


