Shader "URPCustom/AlphaTest" {
    Properties {
        _MainTex ("MainTex", 2D) = "white" { }
        _TintColor("BaseColor", Color) = (1,1,1,1)
        _CutOff("Cutoff", Range(0, 1)) = 0.5
        [HDR]_BurnColor("BurnColor", Color) = (2.5,1,1,1)
        [HideInInspector]_Gloss("Gloss", Range(8, 64)) = 16
    }
    SubShader {
        Tags { 
                "RenderPipeline"="UniversalPipeline" 
                "RenderType"="TransparentCutout" 
                "Queue"="AlphaTest"
            }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            half4 _TintColor;
            half4 _BurnColor;
            float _CutOff;
            float _Gloss;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);

        struct a2v {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float2 texcoord : TEXCOORD0;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 normalWS : TEXCOORD1;
            float3 positionWS : TEXCOORD2;
        };

        ENDHLSL

        //PrePass: Depth Only
        Pass {
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.uv = TRANSFORM_TEX(i.texcoord, _MainTex);
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                half3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb * _TintColor.rgb;
                clip(step(_CutOff, albedo.r)-0.01);
                return 0;
            }
            ENDHLSL
        }

        Pass {
            Tags { "LightMode" = "UniversalForward" }

            ZTest Equal
            ZWrite Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.uv = TRANSFORM_TEX(i.texcoord, _MainTex);
                o.normalWS = TransformObjectToWorldNormal(i.normalOS);
                o.positionWS = TransformObjectToWorld(i.positionOS.xyz);
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                
                half3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb * _TintColor.rgb;
                //clip(step(_CutOff, albedo.r)-0.01);
                albedo = lerp(albedo, _BurnColor, step(albedo.r, saturate(_CutOff + 0.01)));
                //abledo.r小于_CutOff+0.1的范围都step得到0，输出albedo（灰色）, 否则得到1，输出_BurnColor（黄色）

                float diff = 0.5 + 0.5 * dot(i.normalWS, lightDir);
                half3 diffuse = mainLight.color * albedo * diff;

                float3 viewDir = normalize(_WorldSpaceCameraPos - i.positionWS);
                float spec = pow(saturate(dot(normalize(lightDir + viewDir), i.normalWS)), _Gloss);
                half3 specular = mainLight.color * half3(1,1,1) * spec;


                return half4(diffuse + specular, _CutOff);
            }
            ENDHLSL
        }
        
    }
    //Fallback "Diffuse"
}