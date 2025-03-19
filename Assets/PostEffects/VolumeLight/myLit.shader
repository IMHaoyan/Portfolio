Shader "URPCustom/Lit" {
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
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.positionWS);
                half3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb * _TintColor.rgb;
                i.normalWS = normalize(i.normalWS);
                //mainlight part
                

                //return half4(i.positionWS,1);
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                float col =  mainLight.shadowAttenuation;//GetLightAttenuation(positionWS);
               //return half4(col,col,col, 1);


                float3 lightDir = normalize(mainLight.direction);
                float diff = 0.5 + 0.5 * dot(i.normalWS, lightDir);
                if (!_IsHalfLambert) {//使用half lambert的时候会和mainLight.shadowAttenuation作用造成边缘的acne
                    diff = saturate(dot(i.normalWS, lightDir));
                }
                half3 diffuse = mainLight.color * albedo * diff;
                float spec = pow(saturate(dot(i.normalWS, normalize(lightDir + viewDir))), _Gloss);
                half3 specular = mainLight.color * albedo * spec;
                half3 mainColor = (diffuse + specular) * mainLight.shadowAttenuation;
            

                //multi lights part
                half3 addColor = half3(0, 0, 0);
            #if _ADD_LIGHT_ON
                int addLightNum = GetAdditionalLightsCount();
                for (int index = 0; index < addLightNum; index++) {
                    Light addLight = GetAdditionalLight(index, i.positionWS, half4(1, 1, 1, 1));
                    float3 addLightDir = normalize(addLight.direction);
                    float diff = 0.5 + 0.5 * dot(i.normalWS, addLightDir);
                    half3 diffuse = addLight.color * albedo * diff;
                    float spec = pow(saturate(dot(i.normalWS, normalize(addLightDir + viewDir))), _Gloss);
                    half3 specular = addLight.color * albedo * spec;
                    addColor += (diffuse + specular) * addLight.distanceAttenuation * addLight.shadowAttenuation;
                }
            #endif
                half3 ambient = SampleSH(i.normalWS) * _Ambient_Scale;
                return half4(mainColor + addColor + ambient, 1.0);
            }
            ENDHLSL
        }
        //UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
        
    }
}
