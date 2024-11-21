Shader "URPCustom/Effects/myPBR" {
    Properties {
        _irradianceMap ("irradianceMap", Cube) = "_Skybox" { }
        _filteredMap ("filteredMap", Cube) = "_Skybox" { }
        _brdfLut ("brdfLut", 2D) = "black" { }

        _BaseMap ("BaseMap", 2D) = "white" { }
        _TintColor ("Base Color", Color) = (1, 1, 1, 1)

        _NormalMap ("NormalMap", 2D) = "bump" { }
        _NormalScale ("NormalScale", Range(0, 1)) = 1

        _MetallicMap ("MetallicMap", 2D) = "white" { }
        _MetallicScale ("MetallicScale", Range(0, 1)) = 1
        _RoughnessMap ("RoughnessMap", 2D) = "white" { }
        [Toggle]_constRoughness ("constRoughness", Float) = 1
        _Smoothness ("Smoothness", Range(0, 1)) = 0.6
        
        _OcclusionMap ("OcclusionMap", 2D) = "white" { }
        _OcclusionScale ("_OcclusionScale", Range(0, 1)) = 0.775



        [KeywordEnum(ON, OFF)] _ADD_LIGHT ("AddLight", Float) = 0
        [Toggle]_test ("_test", Float) = 0
        //_DiffMultifier ("_DiffMultifier", Range(1, 1000)) = 1.0
        _exposion0 ("_exposion0", Float) = 1.5
        _exposion ("_exposion", Float) = 1.5

        [IntRange]_showGIOrDI ("_showGIOrDI", Range(0, 2)) = 1
        [Toggle]_DiffMultiInvPi ("_DiffMultiInvPi", Float) = 0
        [Toggle]_rawF ("_rawF", Float) = 1
        [Toggle]_SpecMultiPi ("_SpecMultiPi", Float) = 0

        _threshold ("_threshold", Range(0, 100)) = 0.6
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _TintColor;

            float _NormalScale;

            float _MetallicScale;
            float _Smoothness;

            float _OcclusionScale;

            // float _DiffMultifier;
            float _test;
            float _constRoughness;
            float _exposion0;
            float _exposion;
            float _DiffMultiInvPi;
            float _showGIOrDI;
            float _rawF;
            float _SpecMultiPi;

            float _threshold;

        CBUFFER_END
        
        TEXTURECUBE(_irradianceMap);
        SAMPLER(sampler_irradianceMap);

        TEXTURECUBE(_filteredMap);
        SAMPLER(sampler_filteredMap);

        TEXTURE2D(_brdfLut);
        SAMPLER(sampler_brdfLut);

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);
        
        TEXTURE2D(_MetallicMap);
        SAMPLER(sampler_MetallicMap);
        
        TEXTURE2D(_OcclusionMap);
        SAMPLER(sampler_OcclusionMap);

        TEXTURE2D(_RoughnessMap);
        SAMPLER(sampler_RoughnessMap);

        struct a2v {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float4 tangentOS : TANGENT;
            float2 texcoord : TEXCOORD0;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float4 tangentWS : TEXCOORD1;
            float4 normalWS : TEXCOORD2;
            float4 bitangentWS : TEXCOORD3;
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

            #define INT_MAX  0x7FFFFFFF
            #define FLT_INF  asfloat(0x7F800000)
            #define FLT_EPS  5.960464478e-8  // 2^-24, machine epsilon: 1 + EPS = 1 (half of the ULP for 1.0f)
            #define FLT_MIN  1.175494351e-38 // Minimum normalized positive floating-point number
            #define HALF_EPS 4.8828125e-4    // 2^-11, machine epsilon: 1 + EPS = 1 (half of the ULP for 1.0f)
            #define HALF_MIN 6.103515625e-5  // 2^-14, the same value for 10, 11 and 16-bit: https://www.khronos.org/opengl/wiki/Small_Float_Formats
            #define HALF_MIN_SQRT 0.0078125  // 2^-7 == sqrt(HALF_MIN), useful for ensuring HALF_MIN after x^2
            #define HALF_MAX 65504.0
            #define UINT_MAX 0xFFFFFFFFu
            
            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.uv = TRANSFORM_TEX(i.texcoord, _BaseMap);

                o.tangentWS.xyz = TransformObjectToWorldDir(i.tangentOS.xyz);
                o.normalWS.xyz = TransformObjectToWorldNormal(i.normalOS);
                o.bitangentWS.xyz = cross(o.normalWS.xyz, o.tangentWS.xyz) * i.tangentOS.w * unity_WorldTransformParams.w;
                
                float3 positonWS = TransformObjectToWorld(i.positionOS.xyz);
                o.tangentWS.w = positonWS.x;
                o.bitangentWS.w = positonWS.y;
                o.normalWS.w = positonWS.z;

                return o;
            }

            float D_Function(float NdotH, float roughness) {
                //GGX
                float a = max(roughness * roughness, HALF_MIN_SQRT);
                float a2 = max(a * a, HALF_MIN);
                float NdotH2 = NdotH * NdotH;
                float nom = a2;
                float denom = NdotH2 * (a2 - 1.0) + 1.0;
                denom = PI * denom * denom;
                return nom / denom;
            }
            
            float G_section(float dot, float k) {
                //SchlickGGX
                float nom = dot;
                float denom = lerp(dot, 1, k);
                return nom / (denom + 1e-5f);
            }

            float G_Function(float NdotL, float NdotV, float roughness, float HdotL) {
                float k = pow(1 + roughness, 2) / 8;
                float Gnl = G_section(NdotL, k);
                float Gnv = G_section(NdotV, k);
                if (_test) {
                    float a = max(roughness * roughness, HALF_MIN_SQRT);
                    return PI / (max(HdotL * HdotL, 0.1) * (a * 4.0 + 2.0)) / NdotL;
                }
                return Gnl * Gnv;
            }

            float3 F_Function(float HdotV, float HdotL, float3 F0) {
                //Unity改进的F函数
                float Fre = exp2((-5.55473 * HdotL - 6.98316) * HdotL);
                if (_rawF)
                    Fre = pow(1 - HdotV, 5);
                return lerp(Fre, 1, F0);
            }
            

            float3 F_Roughness(float NdotV, float3 F0, float roughness) {
                //修正roughness过大的时候fresnel过大
                return F0 + (max(float3(1, 1, 1) * (1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);
            }

            ///目前直接光和环境光的高光部分都有偏暗的问题
            half3 DirectPBR(float HdotL, float NdotL, float NdotV, float NdotH, float HdotV, float3 Albedo, float metallic, float roughness, float3 F0, float3 lightColor) {
                float D = D_Function(NdotH, roughness);
                float G = G_Function(NdotL, NdotV, roughness, HdotL);
                float3 F = F_Function(HdotV, HdotL, F0);
                //if( G > _threshold)
                //return half3(1,0,0);

                float3 DirectSpecular = D * G * F / (4 * max(NdotL * NdotV, 0.001));
                if (_SpecMultiPi)
                    DirectSpecular = D * G * F / (4 * max(NdotL * NdotV, 0.001)) * PI;
                
                float3 Ks = F;
                float3 Kd = (1 - Ks) * (1 - metallic);
                //Unity的直接光的漫反射没有除以PI！！！！！
                float3 DirectDiffuse = Kd * Albedo;
                if (_DiffMultiInvPi)
                    DirectDiffuse /= PI;

                return (_exposion * DirectSpecular + _exposion0 * DirectDiffuse) * lightColor * NdotL;
                //return (DirectSpecular + DirectDiffuse) * lightColor * NdotL;

            }

            half3 DirectLightPBR(Light light, float3 normalWS, float3 viewDir, float3 Albedo, float metallic, float roughness, float3 F0, float NdotV) {
                float3 lightDir = normalize(light.direction);
                float NdotL = max(dot(normalWS, lightDir), 0.000001);
                float3 H = normalize(viewDir + lightDir);
                float HdotL = max(dot(H, lightDir), 0.000001);
                float NdotH = max(dot(normalWS, H), 0.000001);
                float HdotV = max(dot(H, viewDir), 0.000001);
                return DirectPBR(HdotL, NdotL, NdotV, NdotH, HdotV, Albedo, metallic, roughness, F0, light.color);
            }

            half4 frag(v2f i) : SV_Target {
                float3 Albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _TintColor.rgb;
                
                float4 NormalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
                float3 normalTS = UnpackNormalScale(NormalMap, _NormalScale);
                normalTS.z = pow(1 - dot(normalTS.xy, normalTS.xy), 0.5);//normalize after scaled by _NormalScale
                float3x3 TBN = {
                    i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz
                };
                float3 normalWS = normalize(mul(normalTS, TBN));

                float4 MetallicMap = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, i.uv);
                float metallic = MetallicMap.r * _MetallicScale;

                float4 RoughnessMap = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, i.uv);
                
                float roughness = 1 - (1 - RoughnessMap.r) * _Smoothness;
                //for test test.0
                if (_constRoughness)
                    roughness = (1 - _Smoothness);// *(1 - _Smoothness);//此处Roughness 为 perceptualRoughness
               // return half4(half3(1,1,1)* roughness,1);

                float occlusion = lerp(1, SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, i.uv).r, _OcclusionScale);

                float3 positionWS = float3(i.tangentWS.w, i.bitangentWS.w, i.normalWS.w);
                float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                float3 reflectDir = reflect(-viewDir, normalWS);
                float NdotV = max(dot(normalWS, viewDir), 0.000001);


                float3 F0 = lerp(0.04, Albedo, metallic);

                ///Main directLight Part
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS));
                half3 DirectColor = DirectLightPBR(mainLight, normalWS, viewDir, Albedo, metallic, roughness, F0, NdotV) * mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                
                //Additional lights part
                half3 addColor = half3(0, 0, 0);
            #if _ADD_LIGHT_ON
                int addLightNum = GetAdditionalLightsCount();
                for (int index = 0; index < addLightNum; index++) {
                    Light addLight = GetAdditionalLight(index, positionWS, half4(1, 1, 1, 1));
                    addColor += DirectLightPBR(addLight, normalWS, viewDir, Albedo, metallic, roughness, F0, NdotV) * addLight.distanceAttenuation * addLight.shadowAttenuation;
                }
            #endif
                DirectColor += addColor;
                ///
                

                ///IBL Part
                //IBL diffuse
                half3 irradiance = SAMPLE_TEXTURECUBE_LOD(_irradianceMap, sampler_irradianceMap, normalWS, 0).rgb;
                float3 Ks = F_Roughness(NdotV, F0, roughness);
                float3 Kd = 1 - Ks;
                float3 diffuse = (1 - metallic) * Kd * irradiance * Albedo;

                //IBL specular
                int maxMip = 8 - 1;
                float3 filteredEnv = SAMPLE_TEXTURECUBE_LOD(_filteredMap, sampler_filteredMap, reflectDir, roughness * maxMip).rgb;
                float2 BRDFLut = SAMPLE_TEXTURE2D_LOD(_brdfLut, sampler_brdfLut, float2(NdotV, roughness), 0).rg;
                float3 specular = filteredEnv * (Ks * BRDFLut.x + BRDFLut.y);
                
                float3 AmbientColor = (diffuse * _exposion0 + specular * _exposion) * occlusion; //???为啥偏暗啊
                
                ///
                float x = 1, y = 1;
                if (_showGIOrDI == 0) {
                    //return half4(1,0,0,0);
                    x = 0;
                } else if (_showGIOrDI == 1) {
                    //return half4(0,1,0,0);
                    y = 0;
                }
                return float4((DirectColor * x + AmbientColor * y), 1);
            }
            ENDHLSL
        }
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
}
