Shader "URPCustom/PostEffects/myBlitter" {
    Properties { }
    SubShader {
        Cull Off
        ZWrite Off
        ZTest Always

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

        float4 _ProjectionParams2;
        float4 _CameraViewTopLeftCorner;
        float4 _CameraViewXExtent;
        float4 _CameraViewYExtent;

        float MAXDISTANCE;
        float STRIDE;
        float STEP_COUNT;
        float THICKNESS;

        float INTENSITY;

        float _HierarchicalZBufferTextureFromMipLevel;
        float _HierarchicalZBufferTextureToMipLevel;
        float _MaxHierarchicalZBufferTextureMipLevel;

        float4 _SourceSize;
        float _Blur;
        float2 _myBlitTextureSize;
        
        half4 GetSource(half2 uv, float2 offset = 0.0, float mipLevel = 0.0) {
            offset *= _SourceSize.zw;
            return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + offset, mipLevel);
        }

        TEXTURE2D(_HierarchicalZBufferTexture);
        SAMPLER(sampler_HierarchicalZBufferTexture);

        TEXTURE2D(_mySolidRT);
        SAMPLER(sampler_mySolidRT);

        ENDHLSL

        // 0 Mipmap
        Pass {
            Name "Mipmap"
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment SSAOPassFragment

            half4 SSAOPassFragment(Varyings input) : SV_Target {
                float2 uv = input.texcoord;

                half4 minDepth = half4(
                    GetSource(uv, float2(-1, -1), _HierarchicalZBufferTextureFromMipLevel).r,
                    GetSource(uv, float2(-1, 1), _HierarchicalZBufferTextureFromMipLevel).r,
                    GetSource(uv, float2(1, -1), _HierarchicalZBufferTextureFromMipLevel).r,
                    GetSource(uv, float2(1, 1), _HierarchicalZBufferTextureFromMipLevel).r
                );

                return max(max(minDepth.r, minDepth.g), max(minDepth.b, minDepth.a));
            }
            ENDHLSL
        }

        // 1 Raymaching
        Pass {
            Name "Raymaching"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment SSRPassFragment

            void swap(inout float v0, inout float v1) {
                float temp = v0;
                v0 = v1;
                v1 = temp;
            }

            half3 reconstructViewPos(float2 uv, float linearEyeDepth) {
                uv.y = 1.0 - uv.y;  // Screen is y-inverted
                float zScale = linearEyeDepth * _ProjectionParams2.x; //  1/znear
                float3 positionWSview = _CameraViewTopLeftCorner.xyz + _CameraViewXExtent.xyz * uv.x + _CameraViewYExtent.xyz * uv.y;
                positionWSview *= zScale;
                return positionWSview;
            }

            // 从视角坐标转裁剪屏幕ao坐标
            // z: -near, far    w: -positionVS.z
            float4 TransformViewToHScreen(float3 vpos, float2 screenSize) {
                float4 cpos = mul(UNITY_MATRIX_P, vpos);
                cpos.xy = float2(cpos.x, cpos.y * _ProjectionParams.x) * 0.5 + 0.5 * cpos.w;
                cpos.xy *= screenSize;
                return cpos;
            }
            

            static half dither[16] = {
                0.0, 0.5, 0.125, 0.625,
                0.75, 0.25, 0.875, 0.375,
                0.187, 0.687, 0.0625, 0.562,
                0.937, 0.437, 0.812, 0.312
            };

            bool HierarchicalZScreenSpaceRayMarching(float3 startVS, float3 reflectDirVS, inout float2 hitUV) {
                float magnitude = MAXDISTANCE;

                // view space z: [-far, -near]
                float endVSz = startVS.z + reflectDirVS.z * magnitude;
                if (endVSz > - _ProjectionParams.y) // >-near
                magnitude = (-_ProjectionParams.y - startVS.z) / reflectDirVS.z;
                float3 endVS = startVS + reflectDirVS * magnitude;

                // 齐次屏幕空间坐标
                float4 startHScreen = TransformViewToHScreen(startVS, _SourceSize.xy);
                float4 endHScreen = TransformViewToHScreen(endVS, _SourceSize.xy);

                // inverse w
                float startK = 1.0 / startHScreen.w;
                float endK = 1.0 / endHScreen.w;

                //  结束屏幕空间坐标
                float2 startSS = startHScreen.xy * startK;
                float2 endSS = endHScreen.xy * endK;

                // 经过齐次除法的视角坐标
                float3 startQ = startVS * startK;
                float3 endQ = endVS * endK;

                float stride = STRIDE;
                float depthDistance = 0.0;
                bool permute = false;

                // 根据斜率将dx=1 dy = delta
                float2 diff = endSS - startSS;
                if (abs(diff.x) < abs(diff.y)) {
                    permute = true;

                    diff = diff.yx;
                    startSS = startSS.yx;
                    endSS = endSS.yx;
                }

                // 计算屏幕坐标、齐次视坐标、inverse-w的线性增量
                float dir = sign(diff.x);
                float invdx = dir / diff.x;
                float2 dp = float2(dir, invdx * diff.y);
                float3 dq = (endQ - startQ) * invdx;
                float dk = (endK - startK) * invdx;

                dp *= stride;
                dq *= stride;
                dk *= stride;

                // 缓存当前深度和位置
                float rayZ = startVS.z;

                float2 P = startSS;
                float3 Q = startQ;
                float K = startK;

                //....
                float2 ditherUV = fmod(P, 4);
                float jitter = dither[ditherUV.x * 4 + ditherUV.y];
                
                // P += dp * jitter;
                // Q += dq * jitter;
                // K += dk * jitter;
                //加上 jitter offset 之后开始闪屏？

                float rayZMin = rayZ;
                float rayZMax = rayZ;
                float preZ = rayZ;

                float mipLevel = 0.0;

                //float2 hitUV = 0.0;

                // 进行屏幕空间射线步近
                UNITY_LOOP
                for (int i = 0; i < STEP_COUNT; i++) {
                    // 步近
                    P += dp * exp2(mipLevel);
                    Q += dq * exp2(mipLevel);
                    K += dk * exp2(mipLevel);

                    // 得到步近前后两点的深度
                    rayZMin = preZ;
                    rayZMax = (dq.z * 0.5 * exp2(mipLevel) + Q.z) / (dk * exp2(mipLevel) * 0.5 + K);//求当前位置的positionVS.z ,即负深度。raymax是一个阈值上限，raymin是上一次的上限
                    //👆Q线性相关 K线性相关，所以可以插值，（I/zview的形式）然后通过插值结果还原得到positionVS，我们只取z分量
                    //原理：http://wingerzeng.com/2021/11/11/%E5%9B%BE%E5%BD%A2%E5%AD%A6%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0%E2%80%94%E8%AF%A6%E8%A7%A3%E5%B1%8F%E5%B9%95%E7%A9%BA%E9%97%B4%E4%B8%8B%E7%9A%84%E7%BA%BF%E6%80%A7%E6%8F%92%E5%80%BC/
                    preZ = rayZMax;
                    if (rayZMin > rayZMax)
                        swap(rayZMin, rayZMax);

                    // 得到交点uv
                    hitUV = permute ? P.yx : P;
                    hitUV *= _SourceSize.zw;

                    if (any(hitUV < 0.0) || any(hitUV > 1.0))
                        return false;

                    //float surfaceDepth = -LinearEyeDepth(SampleSceneDepth(hitUV), _ZBufferParams);
                    // float rawDepth = SAMPLE_TEXTURE2D_X_LOD(_HierarchicalZBufferTexture, sampler_HierarchicalZBufferTexture, hitUV, mipLevel);
                    
                    float rawDepth = SampleSceneDepth(hitUV);
                    rawDepth = SAMPLE_TEXTURE2D_X_LOD(_HierarchicalZBufferTexture, sampler_CameraDepthTexture, hitUV, mipLevel);
                    float surfaceDepth = -LinearEyeDepth(rawDepth, _ZBufferParams);

                    float bias = 0.1;
                    bool isBehind = (rayZMin + bias <= surfaceDepth); // 加一个bias 防止stride过小，自反射

                    depthDistance = abs(surfaceDepth - rayZMax);
                    
                    if (!isBehind) {
                        mipLevel = min(mipLevel + 1, _MaxHierarchicalZBufferTextureMipLevel);
                    } else {
                        if (mipLevel == 0) {
                            if (abs(surfaceDepth - rayZMax) < THICKNESS) {
                                // return float4(hitUV, rayZMin, 0.0);
                                //return float4(hitUV, rayZMin, 1.0);
                                return true;
                            }
                        } else {
                            P -= dp * exp2(mipLevel);
                            Q -= dq * exp2(mipLevel);
                            K -= dk * exp2(mipLevel);
                            preZ = Q.z / K;

                            mipLevel--;
                        }
                    }
                }
                return false;
            }

            half4 SSRPassFragment(Varyings input) : SV_Target {
                
                if (SAMPLE_TEXTURE2D_X_LOD(_mySolidRT, sampler_mySolidRT, input.texcoord, 0).r == 0)
                    return half4(0, 0, 0, 1);
                float rawDepth = SampleSceneDepth(input.texcoord);
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                float3 vpos = reconstructViewPos(input.texcoord, linearDepth);
                float3 normal = SampleSceneNormals(input.texcoord);
                float3 vDir = normalize(vpos);
                float3 reflectDirVSVS = TransformWorldToViewDir(normalize(reflect(vDir, normal)));
                float3 positionWS = _WorldSpaceCameraPos + vpos;// 视空间坐标
                //vpos = ComputeWorldSpacePosition(input.texcoord, rawDepth, UNITY_MATRIX_I_VP);

                // get startVS & endVSz
                float3 startVS = TransformWorldToView(positionWS);

                // 判断与物体相交
                float2 hitUV;
                half4 SSR = half4(0, 0, 0, 0);
                if (HierarchicalZScreenSpaceRayMarching(startVS, reflectDirVSVS, hitUV))
                    SSR = GetSource(hitUV) ;//+ GetSource(input.texcoord);
                return SSR;
            }

            ENDHLSL
        }

        // 2 Blur
        Pass {
            Name "Blur"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            half4 frag(Varyings i) : SV_TARGET {
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
            // ZTest NotEqual
            // ZWrite Off
            // Cull Off
            Blend One One

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment SSRFinalPassFragment

            half4 SSRFinalPassFragment(Varyings input) : SV_Target {
                return half4(GetSource(input.texcoord).rgb * INTENSITY, 1.0);
            }
            ENDHLSL
        }
    }
}