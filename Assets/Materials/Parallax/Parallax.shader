Shader "URPCustom/Parallax" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 1, 1, 1)
        _MainTex ("BaseMap", 2D) = "white" { }
        _NormalMap ("NormalMap", 2D) = "bump" { }
        _NormalScale ("NormalScale", Range(-1, 1)) = 1.0
        _Gloss ("Gloss", Range(8, 64)) = 20

        _DepthMap ("DepthMap", 2D) = "white" { }
        _DepthMapScale ("DepthMapScale", Range(0.0001, 0.1)) = 0.05


        [Toggle]_UseParallax ("UseParallax", Float) = 1
        [IntRange]_LayerCount ("LayerCount", Range(5, 50)) = 15
        [IntRange]_SLayer ("ShadowLayerCount", Range(5, 50)) = 15
        [IntRange]_ParallaxType ("ParallaxType", Range(0, 2)) = 2
        [IntRange]_ShadowScale ("ShadowScale", Range(0, 128)) = 128
        [Toggle]_DebugShadow ("_DebugShadow", Float) = 0
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
            float _DepthMapScale;
            float _LayerCount;
            float _SLayer;

            float _UseParallax;
            float _ParallaxType;
            float _ShadowScale;
            float _DebugShadow;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);
        TEXTURE2D(_DepthMap);
        SAMPLER(sampler_DepthMap);

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
                float3 positionWS = float3(i.tangentWS.w, i.bitangentWS.w, i.normalWS.w);
                float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                
                float PDepth = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, i.uv, 0).r * _DepthMapScale;
                float marchedDepth = 0;
                //使用视差贴图
                if (_UseParallax == 1) {
                    float3 viewDirTS = normalize(mul(TBN, viewDir));
                    
                    //1.基础视差
                    if (_ParallaxType == 0) {
                        float2 offset = -viewDirTS.xy / viewDirTS.z;// z always > 0 (Tangent space)
                        i.uv = i.uv + PDepth * offset;
                    }
                    //2.陡峭视差
                    else if (_ParallaxType == 1) {
                            float2 currUV = i.uv;
                        
                        float2 delta = -viewDirTS.xy / viewDirTS.z / _LayerCount * _DepthMapScale;
                        while (marchedDepth < PDepth) {
                            currUV += delta;
                            marchedDepth += 1.0 / _LayerCount * _DepthMapScale;
                            PDepth = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, currUV, 0).r * _DepthMapScale;
                        }
                        i.uv = currUV;
                    }
                    //3.视差遮蔽
                    else if (_ParallaxType == 2) {
                            float2 currUV = i.uv;
                        
                        float2 delta = -viewDirTS.xy / viewDirTS.z / _LayerCount * _DepthMapScale;
                        while (marchedDepth < PDepth) {
                            currUV += delta;
                            marchedDepth += 1.0 / _LayerCount * _DepthMapScale;
                            PDepth = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, currUV, 0).r * _DepthMapScale;
                        }

                        float2 oldUV = currUV - delta;
                        float oldPDepth = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, oldUV, 0).r * _DepthMapScale;
                        float oldMarchedDepth = marchedDepth - 1.0 / _LayerCount * _DepthMapScale;;

                        float oldWeight = oldPDepth - oldMarchedDepth;
                        float currWeight = marchedDepth - PDepth;
                        float weight = currWeight / (currWeight + oldWeight);
                        currUV = lerp(oldUV, currUV, 1 - weight);

                        i.uv = currUV;
                    }
                }
                
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalScale);
                normalTS.z = sqrt(1 - dot(normalTS.xy, normalTS.xy));//normalize after scaled by _NormalScale
                float3 normalWS = normalize(mul(normalTS, TBN));
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * _TintColor;

                Light mainLight = GetMainLight();
                mainLight = GetAdditionalLight(0, positionWS);

                float shadow = 0;
                if (_UseParallax == 1) {
                    float3 lightDir = mainLight.direction;
                    float3 LTS = mul(lightDir, TBN);
                    float2 newUV = i.uv;
                    float2 deltaL = LTS.xy / LTS.z / _SLayer * _DepthMapScale;

                    if (dot(normalWS, lightDir) > 0) {
                        float2 tempUV1 = newUV + deltaL;
                        
                        float marchedDepth_LightDir = marchedDepth - 1.0 / _SLayer * _DepthMapScale;
                        float PDepth_LightDir = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, tempUV1, 0).r * _DepthMapScale;

                        float underNum = 0;
                        float stepIndex = 1;
                        while (marchedDepth_LightDir > 0) {
                            //occlusion occurred（注意depth是到水平面的距离）
                            if (marchedDepth_LightDir > PDepth_LightDir) {
                                underNum += 1;
                                float attenuation = 1 - stepIndex / _SLayer;//越靠近内部（index越小），遮挡影响越大
                                float newShadow = (marchedDepth_LightDir - PDepth_LightDir) * attenuation;
                                shadow = max(shadow, newShadow); //取最大的遮挡影响

                            }
                            //marching
                            tempUV1 += deltaL;
                            marchedDepth_LightDir -= 1.0 / _SLayer * _DepthMapScale;
                            PDepth_LightDir = SAMPLE_TEXTURE2D_LOD(_DepthMap, sampler_DepthMap, tempUV1, 0).r * _DepthMapScale;
                            
                            stepIndex += 1;
                        }
                    }
                }

                half3 ambient = 0;
                ambient += SampleSH(normalWS) * albedo * 0.3;

                float diff = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = diff * albedo.rgb * mainLight.color * mainLight.distanceAttenuation;
                
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float spec = pow(saturate(dot(halfDir, normalWS)), _Gloss);
                half3 specular = spec * albedo.rgb * mainLight.color * mainLight.distanceAttenuation;

                float visibility = (1 - shadow);
                visibility = pow(visibility, _ShadowScale);
                half3 col = (diffuse + specular) * visibility;
                if (_DebugShadow)
                    return half4(half3(1, 1, 1) * visibility, 1);
                return half4(col , 1);
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}
