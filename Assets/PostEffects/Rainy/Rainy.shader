Shader "URPCustom/BumpMap" {
    Properties {
        _Speed ("_Speed", Float) = 1.0
        _Tiling ("_Tiling", Float) = 1.0


        _TintColor ("TintColor", Color) = (1, 1, 1, 1)
        _MainTex ("BaseMap", 2D) = "white" { }
        _NormalMap ("NormalMap", 2D) = "bump" { }
        _NormalScale ("NormalScale", Range(-1, 1)) = 1.0
        _Gloss ("Gloss", Range(8, 32)) = 20
    }
    SubShader {
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TintColor;
            float4 _MainTex_ST;
            float _NormalScale;
            float _Gloss;

            float _Tiling;

            float _Speed;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);

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
            float3 objectWS : TEXCOORD4;
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
                //o.uv2 = TRANSFORM_TEX(i.texcoord + float2(0.5, 0.5), _MainTex);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(i.normalOS, i.tangentOS);
                o.tangentWS.xyz = normalInputs.tangentWS;// TransformObjectToWorldDir(i.tangentOS.xyz);
                o.normalWS.xyz = normalInputs.normalWS; // TransformObjectToWorldNormal(i.normalOS);
                o.bitangentWS.xyz = normalInputs.bitangentWS; //cross(o.normalWS.xyz, o.tangentWS.xyz) * i.tangentOS.w * unity_WorldTransformParams.w;
                
                o.tangentWS.w = positionWS.x;
                o.bitangentWS.w = positionWS.y;
                o.normalWS.w = positionWS.z;

                o.objectWS = TransformObjectToWorld(float3(0, 0, 0));

                // if (o.normalWS.z < 0)
                //     o.uv = -o.uv;
                return o;
            }

            half4 frag(v2f i) : SV_Target {
            #if 0
                float3x3 TBN = {
                    i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz
                };
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalScale);
                normalTS.z = sqrt(1 - dot(normalTS.xy, normalTS.xy));//normalize after scaled by _NormalScale
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                float3 positionWS = float3(i.tangentWS.w, i.bitangentWS.w, i.normalWS.w);
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * _TintColor;
                Light mainLight = GetMainLight();
                half3 ambient = 0;
                ambient += SampleSH(normalWS) * albedo * 0.3;

                float diff = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = diff * albedo.rgb * mainLight.color;
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float spec = pow(saturate(dot(halfDir, normalWS)), _Gloss);
                half3 specular = spec * albedo.rgb * mainLight.color;
                
                half3 col = ambient + diffuse + specular;
            #endif
                
                float3 positionWS = float3(i.tangentWS.w, i.bitangentWS.w, i.normalWS.w);

                float emissive = 1 - frac(_Time.y * _Speed);
                float emissive2 = 1 - frac(_Time.y * _Speed + 0.5);
                float3 mask = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                float3 mask2 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + float2(0.5, 0.5));

                float maskValue = saturate(1 - distance(mask.r - emissive, 0.05) / 0.05) * mask.r;
                float maskValue2 = saturate(1 - distance(mask2.r - emissive2, 0.05) / 0.05) * mask2.r;
                float maskColor = maskValue + maskValue2;
                float3 rippleColor = float3(maskColor, maskColor, maskColor);


                float2 verticalUv = float2(positionWS.x, positionWS.y) * _Tiling;
                float2 verticalUv2 = float2(positionWS.z, positionWS.y) * _Tiling;
                mask = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, verticalUv);
                mask2 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, verticalUv2);
                float4 finalColor = lerp(mask.g, mask2.g, abs(i.normalWS.x));
                if (abs(i.normalWS.y) > 0.99)
                    finalColor = 0;
                //finalColor = 1;
                
                float3 mask3 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, (i.uv + float2(0, _Time.y * 0.5)));
                finalColor *= 1 - mask3.b;
                finalColor += half4(rippleColor, 1);
                return finalColor;
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
}
