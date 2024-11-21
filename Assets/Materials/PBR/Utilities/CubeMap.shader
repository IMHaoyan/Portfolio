Shader "URPCustom/Test/CubeMap" {
    Properties {
        _CubeMap("Cube Map", Cube) = "_Skybox"{ }
        _lod("LOD value", Range(0,7)) = 0
        [Toggle]_showDiffwithSH("_showDiffwithSH", Float) = 0
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
             
        CBUFFER_START(UnityPerMaterial)
            float _lod;
            float _showDiffwithSH;
        CBUFFER_END

        TEXTURECUBE(_CubeMap);
        SAMPLER(sampler_CubeMap);

        struct a2v {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float3 normalWS :TEXCOORD1;
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
                //half3 col = SAMPLE_TEXTURECUBE(_CubeMap, sampler_CubeMap, i.normalWS).rgb;
                half3 col = SAMPLE_TEXTURECUBE_LOD(_CubeMap, sampler_CubeMap, i.normalWS, _lod).rgb;
                if(_showDiffwithSH)
                    col = col - SampleSH(i.normalWS);
                return half4(col, 1.0);
            }
            ENDHLSL
        }
        
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
    }
}
