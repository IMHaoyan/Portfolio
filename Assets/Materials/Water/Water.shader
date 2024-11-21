Shader "URPCustom/Water" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 1, 1, 1)
        _MainTex ("BaseMap", 2D) = "white" { }
        _NormalMap ("NormalMap", 2D) = "bump" { }
        _CubeMap ("CubeMap", Cube) = "_Skybox" { }
        _WaveXSpeed ("_WaveXSpeed", Range(-0.1, 0.1)) = 0.01
        _WaveYSpeed ("_WaveYSpeed", Range(-0.1, 0.1)) = 0.01
        _Distortion ("Distortion", Range(0, 100)) = 10
        _NormalScale ("NormalScale", Range(0, 1)) = 1.0
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" "Queue" = "Transparent" }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TintColor;
            float4 _MainTex_ST;
            float4 _NormalMap_ST;
            float _WaveXSpeed;
            float _WaveYSpeed;
            float _Distortion;
            float _NormalScale;
            float4 _CameraOpaqueTexture_TexelSize;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);
        TEXTURECUBE(_CubeMap);
        SAMPLER(sampler_CubeMap);
        TEXTURE2D(_CameraOpaqueTexture);
        SAMPLER(sampler_CameraOpaqueTexture);

        struct a2v {
            float4 positionOS : POSITION;
            float4 texcoord : TEXCOORD0;
            float4 tangentOS : TANGENT;
            float3 normalOS : NORMAL;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float4 uv : TEXCOORD0;
            float4 tangentWS : TEXCOORD1;
            float4 bitangentWS : TEXCOORD2;
            float4 normalWS : TEXCOORD3;
            float4 positionSS : TEXCOORD4;
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
                o.positionSS = positionInputs.positionNDC;// unityNDC是未做透视除法且范围为: 0 < xy < w （与传统ndc概念不太一样）
                float3 positionWS = positionInputs.positionWS;

                o.uv.xy = TRANSFORM_TEX(i.texcoord, _MainTex);
                o.uv.zw = TRANSFORM_TEX(i.texcoord, _NormalMap);

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

                float3 positionWS = float3(i.tangentWS.w, i.bitangentWS.w, i.normalWS.w);
                float3x3 TBN = {
                    i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz
                };


                float2 speed = _Time.y * float2(_WaveXSpeed, _WaveYSpeed);
                half3 normalTS1 = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv.zw + speed), _NormalScale);
                normalTS1.z = sqrt(1 - dot(normalTS1.xy, normalTS1.xy));//normalize after scaled by _NormalScale
                half3 normalTS2 = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv.zw - speed), _NormalScale);
                normalTS2.z = sqrt(1 - dot(normalTS2.xy, normalTS2.xy));//normalize after scaled by _NormalScale
                half3 normalTS = normalize(normalTS1 + normalTS2);


                float2 offset = normalTS.xy * _Distortion * _CameraOpaqueTexture_TexelSize.xy;
                float3 refractColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, i.positionSS.xy / i.positionSS.w + offset).rgb;
                
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv.xy + 0.2 * speed) * _TintColor;
                refractColor = lerp(refractColor, albedo.rgb, 0.05);

                float3 normalWS = normalize(mul(normalTS, TBN));
                float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                float3 reflectDir = reflect(-viewDir, normalWS);
                float3 reflectColor = SAMPLE_TEXTURECUBE(_CubeMap, sampler_CubeMap, reflectDir).rgb * albedo.rgb;
                
                half fresnel = pow(1 - saturate(dot(viewDir, normalWS)), 4);
                half3 finalColor = lerp(refractColor, reflectColor, fresnel);

                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
