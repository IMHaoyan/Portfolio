Shader "URPCustom/UnLit" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 0, 0, 1)
        [Toggle]_DebugCustomRT ("DebugCustomRT", Float) = 0
    }
    SubShader {
        ZWrite Off Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TintColor;
            float _DebugCustomRT;
            float _Distance;
            float2 _camsize;
        CBUFFER_END

        TEXTURE2D(_mySolidRT);

        ENDHLSL
        
        Pass {
            Name "SelectOutline"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            

            #define SAMPLE_COUNT 16

            half4 frag(Varyings i) : SV_Target {
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                if(_DebugCustomRT){
                    return half4(color.rgb, 1);
                }
                if (color.a > 0.1f) {
                    return half4(1, 1, 0, 0);
                }
                float2 _BlitTexture_TexelSize = 1.0 / _camsize;

                int insideCount = 0;
                for (int index = 0; index < SAMPLE_COUNT; index++) {
                    float s;
                    float c;
                    sincos(radians(360.0f / ((float)SAMPLE_COUNT) * ((float)index)), s, c);
                    // 采样一圈 16 个像素
                    float2 uv = i.texcoord + float2(s, c) * _BlitTexture_TexelSize * _Distance;
                    float4 sampleColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, uv);
                    if (sampleColor.a > 0.1f) {
                        insideCount += 1;
                    }
                }

                if (insideCount >= 1)
                    return _TintColor;
                
                return float4(0, 0, 0, 0);
            }

            ENDHLSL
        }
    }
}