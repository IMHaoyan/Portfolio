Shader "URPCustom/DebugGrass" {
    Properties {
        _MainTex ("Texture", 2D) = "white" { }
        _TintColor ("Base Color", Color) = (1, 1, 1, 1)
        _Gloss ("Gloss", Range(8, 64)) = 16
        _Ambient_Scale("Ambient Scale", Range(0,1)) = 0.1
        [Toggle] _IsHalfLambert ("IsHalfLambert", float) = 0
        [KeywordEnum(ON, OFF)] _ADD_LIGHT ("AddLight", Float) = 0
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            half4 _TintColor;
            float _Gloss;
            bool _IsHalfLambert;
            float _CutOut;
            float _Ambient_Scale;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);

        struct a2v {
            float4 positionOS : POSITION;
            float2 texcoord : TEXCOORD0;
            float3 normalOS : NORMAL;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 normalWS : TEXCOORD1;
            float3 positionWS : TEXCOORD2;
        };

        ENDHLSL

        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _ADD_LIGHT_ON

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.uv = TRANSFORM_TEX(i.texcoord, _MainTex);
                o.normalWS = TransformObjectToWorldNormal(i.normalOS);
                o.positionWS = TransformObjectToWorld(i.positionOS.xyz);
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                //mainlight part
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                
                return half4(i.positionWS, 1.0);
                return half4(mainLight.shadowAttenuation,0,0, 1.0);
            }
            ENDHLSL
        }
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
        
    }
}