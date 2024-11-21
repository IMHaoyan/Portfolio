Shader "URPCustom/UnLit" {
    Properties {
        _Blur ("Blur", Float) = 1
    }
    SubShader {
        Cull Off
        ZWrite Off
        ZTest Always

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float _Blur;
            float2 _camsize;
        CBUFFER_END

        ENDHLSL
        
        
        Pass {
            Name "Blur"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            half4 frag(Varyings i) : SV_TARGET {
                float2 _BlitTexture_TexelSize = 1.0 / _camsize;

                half4 tex = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(-1, -1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(1, -1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(-1, 1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(1, 1) * _BlitTexture_TexelSize * _Blur);
                return tex / 5.0;
            }
            ENDHLSL
        }
        
    }
}