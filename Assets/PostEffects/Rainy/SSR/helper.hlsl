HLSLPROGRAM

// 从视角空间坐标 获得 片元uv和深度
void reconstructUVAndDepth(float3 positionWS, out float2 uv, out float depth) {
    float4 positionCS = mul(UNITY_MATRIX_VP, positionWS);
    uv = float2(positionCS.x, positionCS.y * _ProjectionParams.x) / positionCS.w * 0.5 + 0.5;
    depth = positionCS.w;   /* positionCS.w == -positionVS.z = depthVS */
}

bool ScreenSpaceRayMarching(inout float2 P, inout float3 Q, inout float K, float2 dp, float3 dq, float dk, float rayZ,
bool permute, out float depthDistance, inout float2 hitUV) {
    float rayZMin = rayZ;
    float rayZMax = rayZ;
    float preZ = rayZ;

    float mipLevel = 0.0;
    
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
        float surfaceDepth = -LinearEyeDepth(rawDepth, _ZBufferParams);

        float bias = 0.1;
        bool isBehind = (rayZMin + bias <= surfaceDepth); // 加一个bias 防止stride过小，自反射

        depthDistance = abs(surfaceDepth - rayZMax);
        
        if (isBehind) {
            return true;
        }
    }
    return false;
}

bool BinarySearchRaymarchingRaw(float3 startVS, float3 reflectDirVS, inout float2 hitUV) {
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

    UNITY_LOOP
    for (int i = 0; i < BINARY_COUNT; i++) {
        float2 ditherUV = fmod(P, 4);
        float jitter = dither[ditherUV.x * 4 + ditherUV.y];
        
        P += dp * jitter;
        Q += dq * jitter;
        K += dk * jitter;
        //加上 jitter offset 之后开始闪屏？


        //在最近的表面之后
        if (ScreenSpaceRayMarching(P, Q, K, dp, dq, dk, rayZ, permute, depthDistance, hitUV)) {
            //与最近的表面相交
            if (depthDistance < THICKNESS)
                return true;
            //未与最近相交
            P -= dp;
            Q -= dq;
            K -= dk;
            rayZ = Q / K;

            dp *= 0.5;
            dq *= 0.5;
            dk *= 0.5;
        }
        //不在之后
        else {
            return false;
        }
    }
    return false;
}

ENDHLSL