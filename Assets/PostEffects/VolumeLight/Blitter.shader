Shader "URPCustom/UnLit" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 0, 0, 1)
        //[Toggle]_DebugCustomRT ("DebugCustomRT", Float) = 0

    }
    SubShader {
        HLSLINCLUDE
        // #define MAIN_LIGHT_CALCULATE_SHADOWS  //定义阴影采样
        // #define _MAIN_LIGHT_SHADOWS_CASCADE //启用级联阴影
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
        #pragma multi_compile _ _SHADOWS_SOFT
        // #pragma multi_compile _ _ADD_LIGHT_ON
        // #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

        // #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"
        // #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"

        half4 _TintColor;
        float _StepCount;
        float _Intensity;
        float _Blur;
        float2 _myBlitTextureSize;
        float _RandomNumber;

        TEXTURE2D(_myRT);
        SAMPLER(sampler_myRT);

        ENDHLSL
        

        // 1 Raymaching
        Pass {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #define random(seed) sin(seed * 641.5467987313875 + 1.943856175)
            
            float3 GetpositionWSition(float2 UV) {
                /* get world space position from clip position */
                //float2 UV = positionHCS.xy / _ScaledScreenParams.xy;
            #if UNITY_REVERSED_Z
                real depth = SampleSceneDepth(UV);
            #else
                real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(UV));
            #endif
                return ComputeWorldSpacePosition(UV, depth, UNITY_MATRIX_I_VP);
            }

            float GetLightAttenuation(float3 position) {
                float4 shadowPos = TransformWorldToShadowCoord(position); //把采样点的世界坐标转到阴影空间
                float intensity = MainLightRealtimeShadow(shadowPos); //进行shadow map采样
                return intensity; //返回阴影值

            }

            half4 frag(Varyings i) : SV_Target {
                float MAX_RAY_LENGTH = 100;

                float2 UV = i.positionCS.xy / _ScaledScreenParams.xy;
                float3 positionWS = GetpositionWSition(UV);

                float3 startPos = _WorldSpaceCameraPos;
                float3 dir = normalize(positionWS - startPos);
                float rayLength = length(positionWS - startPos);
                rayLength = min(rayLength, MAX_RAY_LENGTH);
                
                float3 final = startPos + dir * rayLength; //定义步进结束点
                
                // return half4(positionWS, 1);
                //Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS));
                //float col = mainLight.shadowAttenuation;//GetLightAttenuation(positionWS);
                //return half4(col, col, col, 1);

                half3 intensity = 0;
                float2 step = 1.0 / _StepCount;

                step.y *= 0.4;
                float seed = random((_ScreenParams.y * i.texcoord.y + i.texcoord.x) * _ScreenParams.x + _RandomNumber);
                
                for (float index = 0; index < 1; index += step.x) {
                    
                    seed = random(seed);

                    float3 currPos = lerp(startPos, final, index + seed * step.y);
                    float atten = GetLightAttenuation(currPos) * _Intensity;

                    float3 light = atten;
                    intensity += light;
                }
                intensity /= _StepCount;
                return half4(intensity, 1) * _TintColor;
            }
            ENDHLSL
        }

        // 2 Blur
        Pass {
            Name "Blur"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment BlurPassFragment

            half4 BlurPassFragment(Varyings i) : SV_TARGET {
                float2 _BlitTexture_TexelSize = 1.0 / _myBlitTextureSize;

                half4 tex = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(-1, -1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(1, -1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(-1, 1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(1, 1) * _BlitTexture_TexelSize * _Blur);
                return tex / 5.0;
            }
            ENDHLSL
        }
        
        // 3 Addtive
        Pass {
            Name "Addtive"
            Blend One One

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FinalPassFragment

            half4 FinalPassFragment(Varyings i) : SV_Target {
                
                half4 myrt = SAMPLE_TEXTURE2D(_myRT, sampler_myRT, i.texcoord);
                half4 albedo = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                
                return albedo;
            }
            ENDHLSL
        }
    }
}