Shader "URPCustom/myEffects/mySSDecal" {
    Properties {
        _MainTex ("Texture", 2D) = "white" { }
        _TintColor ("Tint Color", Color) = (1, 1, 1, 1)
        _EdgeStretchPrevent ("EdgeStretchPrevent", Range(-1, 1)) = 1
    }
    SubShader {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Overlay" "Queue" = "Transparent-1"
            "DisableBatch" = "True" }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            half4 _TintColor;
            float _EdgeStretchPrevent;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_CameraDepthTexture);
        SAMPLER(sampler_CameraDepthTexture);

        struct a2v {
            float4 positionOS : POSITION;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float4 SSuv : TEXCOORD1;
            float4 cam2vertexRayOS : TEXCOORD2;
            float3 cameraPosOS : TEXCOORD3;
        };

        ENDHLSL

        Pass {
            Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert(a2v i) {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);

                o.SSuv.xy = o.positionCS.xy * 0.5 + 0.5 * o.positionCS.w;//without divided by w
            #ifdef UNITY_UV_STARTS_AT_TOP
                o.SSuv.y = o.positionCS.w - o.SSuv.y;
            #endif
                o.SSuv.zw = o.positionCS.zw;
                float4 posVS = mul(UNITY_MATRIX_MV, i.positionOS);
                o.cam2vertexRayOS.xyz = mul(UNITY_MATRIX_I_M, mul(UNITY_MATRIX_I_V, float4(posVS.xyz, 0))).xyz;
                o.cam2vertexRayOS.w = -posVS.z;//depth
                o.cameraPosOS = mul(UNITY_MATRIX_I_M, mul(UNITY_MATRIX_I_V, float4(0, 0, 0, 1))).xyz;
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                float2 SSuv = i.SSuv.xy / i.SSuv.w;
                float SSdepth = LinearEyeDepth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, SSuv).r, _ZBufferParams);
                
                i.cam2vertexRayOS.xyz /= i.cam2vertexRayOS.w;//为了射线法
                float3 decalPos = i.cameraPosOS + i.cam2vertexRayOS.xyz * SSdepth;//相似关系，与射线法原理一样
        
                //return half4(decalPos.xz,0, 1);
                
                float mask = (abs(decalPos.x) < 0.5 ? 1 : 0) * (abs(decalPos.y) < 0.5 ? 1 : 0) * (abs(decalPos.z) < 0.5 ? 1 : 0);
                
                float3 decalNormal = normalize(cross(ddy(decalPos), ddx(decalPos)));
                //return half4(decalNormal, 1);

                mask *= decalNormal.y > 0.2 * _EdgeStretchPrevent ? 1 : 0;

                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, decalPos.xz + 0.5) * _TintColor;
                return col * mask;
            }
            ENDHLSL
        }
    }
}

