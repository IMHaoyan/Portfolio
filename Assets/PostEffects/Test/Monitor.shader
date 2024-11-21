Shader "URPCustom/Test" {
    Properties {
        //_TestRT ("BaseMap", 2D) = "white" { }
        _TintColor ("TintColor", Color) = (1, 1, 1, 1)
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float4 _TestRT_ST;
            half4 _TintColor;
        CBUFFER_END
        
        TEXTURE2D(_TestRT);
        SAMPLER(sampler_TestRT);

        struct a2v {
            float4 positionOS : POSITION;
            float2 texcoord : TEXCOORD0;
            float3 normalOS : NORMAL;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 normalWS : TEXCOORD1;
        };

        ENDHLSL

        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.uv = TRANSFORM_TEX(i.texcoord, _TestRT);
                o.normalWS = TransformObjectToWorldNormal(i.normalOS);
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                float3 normalWS = normalize(i.normalWS);
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);

                half3 albedo = SAMPLE_TEXTURE2D(_TestRT, sampler_TestRT, i.uv).rgb * _TintColor.rgb;
                float diff = saturate(dot(normalWS, lightDir));
                half3 diffuse = mainLight.color * diff * albedo;

                half4 col = half4(diffuse, 1);
                return col;
            }
            ENDHLSL
        }
    }
    Fallback "Diffuse"
}
