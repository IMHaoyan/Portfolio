using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FFTOcean : MonoBehaviour
{

    [Range(3, 14)]
    public int FFTPow = 9;         //生成海洋纹理大小 2的次幂，例 为10时，纹理大小为1024*1024
    public int MeshSize = 64;		//网格长宽数量
    public float MeshLength = 512;	//网格长度
    public float A = 75;			//phillips谱参数，影响波浪高度
    public float Lambda = 12;       //用来控制偏移大小
    public float HeightScale = 60;   //高度影响
    public float BubblesScale = 1.2f;  //泡沫强度
    public float BubblesThreshold = 0.9f;//泡沫阈值
    public float WindScale = 30;     //风强
    public float TimeScale = 2;     //时间影响
    public Vector4 WindAndSeed = new Vector4(1f, 1f, 0, 0);//风向和随机种子 xy为风, zw为两个随机种子
    public ComputeShader OceanCS;   //计算海洋的cs
    public Material OceanMaterial;  //渲染海洋的材质
    public Material DisplaceXMat;   //x偏移材质
    public Material DisplaceYMat;   //y偏移材质
    public Material DisplaceZMat;   //z偏移材质
    public Material DisplaceMat;    //偏移材质
    public Material NormalMat;      //法线材质
    public Material BubblesMat;     //泡沫材质
    public Material GaussianMat;     //泡沫材质

    [Range(0, 15)]
    public int ControlM = 12;       //控制m,控制FFT变换阶段
    public bool isControlH = true;  //是否控制横向FFT，否则控制纵向FFT

    int fftSize;            //fft纹理大小 = pow(2,FFTPow)
    float time = 0;             //时间

    int[] vertIndexs;       //网格三角形索引
    Vector3[] positions;    //位置
    Vector2[] uvs;          //uv坐标
    Mesh mesh;
    MeshFilter filetr;
    MeshRenderer render;
    int kernelComputeGaussianRandom;            //计算高斯随机数
    int kernelCreateHeightSpectrum;             //创建高度频谱
    int kernelCreateDisplaceSpectrum;           //创建偏移频谱
    int kernelFFTHorizontal;                    //FFT横向
    int kernelFFTHorizontalEnd;                 //FFT横向，最后阶段
    int kernelFFTVertical;                      //FFT纵向
    int kernelFFTVerticalEnd;                   //FFT纵向,最后阶段
    int kernelTextureGenerationDisplace;        //生成偏移纹理
    int kernelTextureGenerationNormalBubbles;   //生成法线和泡沫纹理
    RenderTexture GaussianRandomRT;             //高斯随机数
    RenderTexture HeightSpectrumRT;             //高度频谱
    RenderTexture DisplaceXSpectrumRT;          //X偏移频谱
    RenderTexture DisplaceZSpectrumRT;          //Z偏移频谱
    RenderTexture DisplaceRT;                   //偏移频谱
    RenderTexture OutputRT;                     //临时储存输出纹理
    RenderTexture NormalRT;                     //法线纹理
    RenderTexture BubblesRT;                    //泡沫纹理

    public bool flag = false;
    void Awake()
    {
        //添加网格及渲染组件
        filetr = gameObject.GetComponent<MeshFilter>();
        render = gameObject.GetComponent<MeshRenderer>();
        mesh = new Mesh();
        filetr.mesh = mesh;
        render.material = OceanMaterial;
    }

    void Start()
    {
        //创建网格
        CreateMesh();
        //初始化ComputerShader相关数据
        InitializeCSvalue();
    }

    void Update()
    {
        // 实时调mesh使用
        // CreateMesh();
        // 实时调参使用
        InitializeCSvalue();

        time += Time.deltaTime * TimeScale;
        //计算海洋数据
        ComputeOceanValue();
    }

    void InitializeCSvalue()
    {
        fftSize = (int)Mathf.Pow(2, FFTPow);

        //创建渲染纹理
        if (GaussianRandomRT != null && GaussianRandomRT.IsCreated())
        {
            GaussianRandomRT.Release();
            HeightSpectrumRT.Release();
            DisplaceXSpectrumRT.Release();
            DisplaceZSpectrumRT.Release();
            DisplaceRT.Release();
            OutputRT.Release();
            NormalRT.Release();
            BubblesRT.Release();
        }
        GaussianRandomRT = CreateRT(fftSize);
        HeightSpectrumRT = CreateRT(fftSize);
        DisplaceXSpectrumRT = CreateRT(fftSize);
        DisplaceZSpectrumRT = CreateRT(fftSize);
        DisplaceRT = CreateRT(fftSize);
        OutputRT = CreateRT(fftSize);
        NormalRT = CreateRT(fftSize);
        BubblesRT = CreateRT(fftSize);

        //获取所有kernelID
        kernelComputeGaussianRandom = OceanCS.FindKernel("ComputeGaussianRandom");
        kernelCreateHeightSpectrum = OceanCS.FindKernel("CreateHeightSpectrum");
        kernelCreateDisplaceSpectrum = OceanCS.FindKernel("CreateDisplaceSpectrum");
        kernelFFTHorizontal = OceanCS.FindKernel("FFTHorizontal");
        kernelFFTHorizontalEnd = OceanCS.FindKernel("FFTHorizontalEnd");
        kernelFFTVertical = OceanCS.FindKernel("FFTVertical");
        kernelFFTVerticalEnd = OceanCS.FindKernel("FFTVerticalEnd");
        kernelTextureGenerationDisplace = OceanCS.FindKernel("TextureGenerationDisplace");
        kernelTextureGenerationNormalBubbles = OceanCS.FindKernel("TextureGenerationNormalBubbles");

        //设置ComputerShader数据
        OceanCS.SetInt("N", fftSize);
        OceanCS.SetFloat("OceanLength", MeshLength);

        //生成高斯随机数
        OceanCS.SetTexture(kernelComputeGaussianRandom, "GaussianRandomRT", GaussianRandomRT);
        OceanCS.Dispatch(kernelComputeGaussianRandom, fftSize / 8, fftSize / 8, 1);

    }

    void ComputeOceanValue()
    {
        OceanCS.SetBool("flag", flag);

        OceanCS.SetFloat("A", A);
        WindAndSeed.z = Random.Range(1, 10f);
        WindAndSeed.w = Random.Range(1, 10f);
        Vector2 wind = new Vector2(WindAndSeed.x, WindAndSeed.y);
        wind.Normalize();
        wind *= WindScale;
        OceanCS.SetVector("WindAndSeed", new Vector4(wind.x, wind.y, WindAndSeed.z, WindAndSeed.w));
        OceanCS.SetFloat("Time", time);
        OceanCS.SetFloat("Lambda", Lambda);
        OceanCS.SetFloat("HeightScale", HeightScale);
        OceanCS.SetFloat("BubblesScale", BubblesScale);
        OceanCS.SetFloat("BubblesThreshold", BubblesThreshold);

        //生成高度频谱
        OceanCS.SetTexture(kernelCreateHeightSpectrum, "GaussianRandomRT", GaussianRandomRT);
        OceanCS.SetTexture(kernelCreateHeightSpectrum, "HeightSpectrumRT", HeightSpectrumRT);
        OceanCS.Dispatch(kernelCreateHeightSpectrum, fftSize / 8, fftSize / 8, 1);

        //生成偏移频谱
        OceanCS.SetTexture(kernelCreateDisplaceSpectrum, "HeightSpectrumRT", HeightSpectrumRT);
        OceanCS.SetTexture(kernelCreateDisplaceSpectrum, "DisplaceXSpectrumRT", DisplaceXSpectrumRT);
        OceanCS.SetTexture(kernelCreateDisplaceSpectrum, "DisplaceZSpectrumRT", DisplaceZSpectrumRT);
        OceanCS.Dispatch(kernelCreateDisplaceSpectrum, fftSize / 8, fftSize / 8, 1);

        if (ControlM == 0)
        {
            SetMaterialTex();
            return;
        }

        //进行横向FFT
        for (int m = 1; m <= FFTPow; m++)
        {
            int ns = (int)Mathf.Pow(2, m - 1);
            OceanCS.SetInt("Ns", ns);
            //最后一次进行特殊处理
            if (m != FFTPow)
            {
                ComputeFFT(kernelFFTHorizontal, ref HeightSpectrumRT);
                ComputeFFT(kernelFFTHorizontal, ref DisplaceXSpectrumRT);
                ComputeFFT(kernelFFTHorizontal, ref DisplaceZSpectrumRT);
            }
            else
            {
                ComputeFFT(kernelFFTHorizontalEnd, ref HeightSpectrumRT);
                ComputeFFT(kernelFFTHorizontalEnd, ref DisplaceXSpectrumRT);
                ComputeFFT(kernelFFTHorizontalEnd, ref DisplaceZSpectrumRT);
            }
            if (isControlH && ControlM == m)
            {
                SetMaterialTex();
                return;
            }
        }
        //进行纵向FFT
        for (int m = 1; m <= FFTPow; m++)
        {
            int ns = (int)Mathf.Pow(2, m - 1);
            OceanCS.SetInt("Ns", ns);
            //最后一次进行特殊处理
            if (m != FFTPow)
            {
                ComputeFFT(kernelFFTVertical, ref HeightSpectrumRT);
                ComputeFFT(kernelFFTVertical, ref DisplaceXSpectrumRT);
                ComputeFFT(kernelFFTVertical, ref DisplaceZSpectrumRT);
            }
            else
            {
                ComputeFFT(kernelFFTVerticalEnd, ref HeightSpectrumRT);
                ComputeFFT(kernelFFTVerticalEnd, ref DisplaceXSpectrumRT);
                ComputeFFT(kernelFFTVerticalEnd, ref DisplaceZSpectrumRT);
            }
            if (!isControlH && ControlM == m)
            {
                SetMaterialTex();
                return;
            }
        }

        //计算纹理偏移
        OceanCS.SetTexture(kernelTextureGenerationDisplace, "HeightSpectrumRT", HeightSpectrumRT);
        OceanCS.SetTexture(kernelTextureGenerationDisplace, "DisplaceXSpectrumRT", DisplaceXSpectrumRT);
        OceanCS.SetTexture(kernelTextureGenerationDisplace, "DisplaceZSpectrumRT", DisplaceZSpectrumRT);
        OceanCS.SetTexture(kernelTextureGenerationDisplace, "DisplaceRT", DisplaceRT);
        OceanCS.Dispatch(kernelTextureGenerationDisplace, fftSize / 8, fftSize / 8, 1);

        //生成法线和泡沫纹理
        OceanCS.SetTexture(kernelTextureGenerationNormalBubbles, "DisplaceRT", DisplaceRT);
        OceanCS.SetTexture(kernelTextureGenerationNormalBubbles, "NormalRT", NormalRT);
        OceanCS.SetTexture(kernelTextureGenerationNormalBubbles, "BubblesRT", BubblesRT);
        OceanCS.Dispatch(kernelTextureGenerationNormalBubbles, fftSize / 8, fftSize / 8, 1);

        SetMaterialTex();
    }

    void CreateMesh()
    {
        //fftSize = (int)Mathf.Pow(2, FFTPow);
        vertIndexs = new int[(MeshSize - 1) * (MeshSize - 1) * 6];
        positions = new Vector3[MeshSize * MeshSize];
        uvs = new Vector2[MeshSize * MeshSize];

        //MeshSize实际上是顶点数量
        int inx = 0;
        for (int i = 0; i < MeshSize; i++)
        {
            for (int j = 0; j < MeshSize; j++)
            {
                int index = i * MeshSize + j;
                positions[index] = new Vector3((j - MeshSize / 2.0f) * MeshLength / MeshSize, 0, (i - MeshSize / 2.0f) * MeshLength / MeshSize);
                uvs[index] = new Vector2(j / (MeshSize - 1.0f), i / (MeshSize - 1.0f));

                if (i != MeshSize - 1 && j != MeshSize - 1)
                {
                    vertIndexs[inx++] = index;
                    vertIndexs[inx++] = index + MeshSize;
                    vertIndexs[inx++] = index + MeshSize + 1;

                    vertIndexs[inx++] = index;
                    vertIndexs[inx++] = index + MeshSize + 1;
                    vertIndexs[inx++] = index + 1;
                }
            }
        }
        mesh.vertices = positions;
        mesh.SetIndices(vertIndexs, MeshTopology.Triangles, 0);
        mesh.uv = uvs;
    }

    //创建渲染纹理
    RenderTexture CreateRT(int size)
    {
        RenderTexture rt = new RenderTexture(size, size, 0, RenderTextureFormat.ARGBFloat);
        rt.enableRandomWrite = true;
        rt.Create();
        return rt;
    }
    //计算fft
    void ComputeFFT(int kernel, ref RenderTexture input)
    {
        OceanCS.SetTexture(kernel, "InputRT", input);
        OceanCS.SetTexture(kernel, "OutputRT", OutputRT);
        OceanCS.Dispatch(kernel, fftSize / 8, fftSize / 8, 1);

        //交换输入输出纹理
        RenderTexture rt = input;
        input = OutputRT;
        OutputRT = rt;
    }
    //设置材质纹理
    void SetMaterialTex()
    {
        //设置海洋材质纹理
        OceanMaterial.SetTexture("_Displace", DisplaceRT);
        OceanMaterial.SetTexture("_Normal", NormalRT);
        OceanMaterial.SetTexture("_Bubbles", BubblesRT);

        //设置显示纹理
        DisplaceXMat.SetTexture("_BaseMap", DisplaceXSpectrumRT);
        DisplaceYMat.SetTexture("_BaseMap", HeightSpectrumRT);
        DisplaceZMat.SetTexture("_BaseMap", DisplaceZSpectrumRT);
        DisplaceMat.SetTexture("_BaseMap", DisplaceRT);
        NormalMat.SetTexture("_BaseMap", NormalRT);
        BubblesMat.SetTexture("_BaseMap", BubblesRT);
        GaussianMat.SetTexture("_BaseMap", GaussianRandomRT);
    }
}