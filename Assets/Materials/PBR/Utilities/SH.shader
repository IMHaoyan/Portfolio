Shader "URPCustom/Test/SH" {
    Properties {
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


        struct a2v {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
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
                o.normalWS = TransformObjectToWorldNormal(i.normalOS);
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                half3 SH = SampleSH(i.normalWS);
                half4 col = half4(SH, 1.0);
                return col;
            }
            ENDHLSL
        }
        
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
    }
}
