using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class processEnvmapCS : MonoBehaviour
{
    public ComputeShader computeShader;
    [Tooltip("需要设置的输入天空盒")]
    public Cubemap envCubemap;
    [Tooltip("输出")]
    public Cubemap outputIrradianceMap;
    [Tooltip("输出")]
    public Cubemap outputFilteredEnvMap;

    void Start()
    {
        //Irradiance
        Color[] tempColors1;
        int resolution = outputIrradianceMap.width;
        ComputeBuffer resultBuffer1 = new ComputeBuffer(resolution * resolution, sizeof(float) * 4);
        tempColors1 = new Color[resolution * resolution];
        int kernal1 = computeShader.FindKernel("CSMainDiffuse");

        for (int face = 0; face < 6; face++)
        {
            computeShader.SetInt("_Face", face);
            computeShader.SetTexture(kernal1, "_envCubemap", envCubemap);
            computeShader.SetInt("_Resolution", resolution);
            computeShader.SetBuffer(kernal1, "_Result1", resultBuffer1);
            computeShader.Dispatch(kernal1, resolution / 8, resolution / 8, 1);

            resultBuffer1.GetData(tempColors1);
            outputIrradianceMap.SetPixels(tempColors1, (CubemapFace)face);

        }
        resultBuffer1.Release();
        outputIrradianceMap.Apply(false);

        //FilteredEnv
        int maxMip = outputFilteredEnvMap.mipmapCount;
        outputFilteredEnvMap.filterMode = FilterMode.Trilinear;
        int kernal2 = computeShader.FindKernel("CSMainSpecular");
        Debug.Log(maxMip);
        for (int mip = 0; mip < maxMip; mip++)
        {
            int size = outputFilteredEnvMap.width;
            size = size >> mip;
            int size2 = size * size;
            Color[] tempColors2 = new Color[size2];
            float roughness = (float)mip / (maxMip - 1);
            ComputeBuffer resultBuffer2 = new ComputeBuffer(size2, sizeof(float) * 4);
            for (int face = 0; face < 6; ++face)
            {
                computeShader.SetInt("_Face", face);
                computeShader.SetTexture(kernal2, "_envCubemap", envCubemap);
                computeShader.SetFloat("_envCubemapSize", envCubemap.width);//env resolution
                computeShader.SetInt("_Resolution", size);//output resolution at current mip
                //Debug.Log("roughness" + roughness);
                computeShader.SetFloat("_FilterMipRoughness", roughness);
                computeShader.SetBuffer(kernal2, "_Result2", resultBuffer2);
                computeShader.Dispatch(kernal2, size, size, 1);
                resultBuffer2.GetData(tempColors2);
                outputFilteredEnvMap.SetPixels(tempColors2, (CubemapFace)face, mip);
            }
            resultBuffer2.Release();
        }
        outputFilteredEnvMap.Apply(false);
    }
}