Shader "URPCustom/Unlit/FFTWave" {
    Properties {
        _OceanColorShallow ("Ocean Color Shallow", Color) = (1, 1, 1, 1)
        _OceanColorDeep ("Ocean Color Deep", Color) = (1, 1, 1, 1)
        _BubblesColor ("Bubbles Color", Color) = (1, 1, 1, 1)
        _Specular ("Specular", Color) = (1, 1, 1, 1)
        _Gloss ("Gloss", Range(8.0, 256)) = 20
        _FresnelScale ("Fresnel Scale", Range(0, 1)) = 0.5
        _Displace ("Displace", 2D) = "black" { }
        _Normal ("Normal", 2D) = "black" { }
        _Bubbles ("Bubbles", 2D) = "black" { }
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _OceanColorShallow;
            half4 _OceanColorDeep;
            half4 _BubblesColor;
            half4 _Specular;
            float _Gloss;
            half _FresnelScale;
            float4 _Displace_ST;
        CBUFFER_END
        
        TEXTURE2D(_Displace);
        SAMPLER(sampler_Displace);
        TEXTURE2D(_Normal);
        SAMPLER(sampler_Normal);
        TEXTURE2D(_Bubbles);
        SAMPLER(sampler_Bubbles);

        struct a2v {
            float4 positionOS : POSITION;
            float2 texcoord : TEXCOORD0;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
        };

        ENDHLSL

        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            

            v2f vert(a2v i) {
                v2f o;
                o.uv = TRANSFORM_TEX(i.texcoord, _Displace);

                float4 displace = SAMPLE_TEXTURE2D_LOD(_Displace, sampler_Displace, o.uv, 0);
                i.positionOS += float4(displace.xyz, 0);

                VertexPositionInputs positionInputs = GetVertexPositionInputs(i.positionOS.xyz);
                o.positionCS = positionInputs.positionCS;
                o.positionWS = positionInputs.positionWS;

                return o;
            }

            half4 frag(v2f i) : SV_Target {
                float3 normalWS = TransformObjectToWorldNormal(SAMPLE_TEXTURE2D(_Normal, sampler_Normal, i.uv).rgb);
                half bubbles = SAMPLE_TEXTURE2D(_Bubbles, sampler_Bubbles, i.uv).r;

                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 reflectDir = reflect(-viewDir, normalWS);

                //采样反射探头
                half3 sky = SampleSH(reflectDir);
                // half3 sky = DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectDir, 0), unity_SpecCube0_HDR);
                
                //菲涅尔
                half fresnel = saturate(_FresnelScale + (1 - _FresnelScale) * pow(1 - dot(normalWS, viewDir), 5));
                
                half facing = saturate(dot(viewDir, normalWS));
                half3 oceanColor = lerp(_OceanColorShallow, _OceanColorDeep, facing).rgb;
                
                half3 ambient = UNITY_LIGHTMODEL_AMBIENT.rgb;
                //泡沫颜色
                half3 bubblesDiffuse = _BubblesColor.rbg * mainLight.color * saturate(dot(lightDir, normalWS));
                //海洋颜色
                half3 oceanDiffuse = oceanColor * mainLight.color * saturate(dot(lightDir, normalWS));
                half3 halfDir = normalize(lightDir + viewDir);
                half3 specular = mainLight.color * _Specular.rgb * pow(max(0, dot(normalWS, halfDir)), _Gloss);
                
                half3 diffuse = lerp(oceanDiffuse, bubblesDiffuse, bubbles);
                
                half3 col = ambient + lerp(diffuse, sky, fresnel) + specular ;
                
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
