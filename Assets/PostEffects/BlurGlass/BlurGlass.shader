Shader "URPCustom/BlurGlass" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 1, 1, 1)
        _MainTex ("BaseMap", 2D) = "white" { }
        _NormalMap ("NormalMap", 2D) = "bump" { }
        _NormalScale ("NormalScale", Range(0, 1)) = 1.0
        //_Gloss ("Gloss", Range(8, 32)) = 20
        _Amount ("Distort Amount", Range(0, 100)) = 10
        _TintScale ("TintScale", Range(0, 1)) = 0.5
        [Toggle]_IsBlur ("IsBlur", Float) = 1
    }
    SubShader {
        //ZWrite On
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Transparent" "Queue" = "Transparent" }
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TintColor;
            float4 _MainTex_ST;
            float _NormalScale;
            //float _Gloss;
            float _Amount;
            float4 _CameraOpaqueTexture_TexelSize;
            float _IsBlur;
            float _TintScale;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);

        TEXTURE2D(_myBlurRT);
        SAMPLER(sampler_myBlurRT);
        TEXTURE2D(_CameraOpaqueTexture);
        SAMPLER(sampler_CameraOpaqueTexture);

        struct a2v {
            float3 positionOS : POSITION;
            float2 texcoord : TEXCOORD0;
            float3 normalOS : NORMAL;
            float4 tangentOS : TANGENT;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float4 tangentWS : TEXCOORD1;
            float4 bitangentWS : TEXCOORD2;
            float4 normalWS : TEXCOORD3;
        };

        ENDHLSL

        Pass {

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert(a2v i) {
                v2f o;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(i.positionOS.xyz);
                o.positionCS = positionInputs.positionCS;
                float3 positionWS = positionInputs.positionWS;

                o.uv = TRANSFORM_TEX(i.texcoord, _MainTex);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(i.normalOS, i.tangentOS);
                o.tangentWS.xyz = normalInputs.tangentWS;// TransformObjectToWorldDir(i.tangentOS.xyz);
                o.normalWS.xyz = normalInputs.normalWS; // TransformObjectToWorldNormal(i.normalOS);
                o.bitangentWS.xyz = normalInputs.bitangentWS; //cross(o.normalWS.xyz, o.tangentWS.xyz) * i.tangentOS.w * unity_WorldTransformParams.w;
                
                o.tangentWS.w = positionWS.x;
                o.bitangentWS.w = positionWS.y;
                o.normalWS.w = positionWS.z;
                
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                float3x3 TBN = {
                    i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz
                };
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalScale);
                normalTS.z = sqrt(1 - dot(normalTS.xy, normalTS.xy));//normalize after scaled by _NormalScale
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                // float3 positionWS = float3(i.tangentWS.w, i.bitangentWS.w, i.normalWS.w);
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * _TintColor;
                // Light mainLight = GetMainLight();
                // half3 ambient = 0;
                // ambient += SampleSH(normalWS) * albedo.rgb * 0.3;

                // float diff = saturate(dot(normalWS, mainLight.direction));
                // half3 diffuse = diff * albedo.rgb * mainLight.color;
                
                // float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                // float3 halfDir = normalize(mainLight.direction + viewDir);
                // float spec = pow(saturate(dot(halfDir, normalWS)), _Gloss);
                // half3 specular = spec * albedo.rgb * mainLight.color;
                
                half3 col = half3(0, 0, 0);
                //col += ambient + diffuse + specular;
                float2 uv = i.positionCS.xy / _ScreenParams.xy;
                float2 biasSS = normalTS.xy * _Amount * _CameraOpaqueTexture_TexelSize.xy;
                if (_IsBlur == 0)
                    col = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_LinearClamp, uv + biasSS).rgb;
                else
                    col = SAMPLE_TEXTURE2D(_myBlurRT, sampler_LinearClamp, uv + biasSS).rgb;
                //col = half3(1,0,0);
                col *= lerp(half3(1, 1, 1), albedo.rgb, half3(1,1,1)*_TintScale);
                return half4(col, 1);
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        //UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
}