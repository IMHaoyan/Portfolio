Shader "URPCustom/PostEffects/myBlit"{
    Properties {
        _MainTex ("Texture", 2D) = "white" { }
        _TintColor ("Tint Color", Color) = (1, 1, 1, 1)
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Overlay" }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            half4 _TintColor;
        CBUFFER_END
    
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);

        struct a2v {
            float4 positionOS : POSITION;
            float2 texcoord : TEXCOORD0;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
        };

        ENDHLSL

        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.uv = i.texcoord;
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * _TintColor;
                return col;
            }
            ENDHLSL
        }
    }
}
