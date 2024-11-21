using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class BakeBRDFLutCS : MonoBehaviour
{
    public ComputeShader computeShader;
    Texture2D outputTex;
    //public Texture2D outputTex;
    //public Material pbrMat;
    void Start()
    {
        int kernal = computeShader.FindKernel("CSMainBRDF");
        int resolution = 512;
        int resolution2 = resolution * resolution;

        outputTex = new Texture2D(resolution, resolution, TextureFormat.RGBA32, false, true);
        ComputeBuffer resultBuffer = new ComputeBuffer(resolution2, sizeof(float) * 4);
        computeShader.SetBuffer(kernal, "_Result", resultBuffer);
        computeShader.SetInt("_Resolution", resolution);
        computeShader.Dispatch(kernal, resolution / 8, resolution / 8, 1);
        Color[] tempColors = new Color[resolution2];
        resultBuffer.GetData(tempColors);
        outputTex.SetPixels(tempColors, 0);
        resultBuffer.Release();
        outputTex.Apply();

        // if (pbrMat == null)
        // {
        //     Debug.LogWarning("pbrMat is not assigned!");
        //     return;
        // }
        // pbrMat.SetTexture("_brdfLut", outputTex);
        byte[] bytes = outputTex.EncodeToPNG();
        System.IO.File.WriteAllBytes("./brdfLUT.png", bytes);
    }
}