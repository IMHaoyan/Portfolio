// Tessellation programs based on the article by Catlike Coding:
// https://mp.weixin.qq.com/s/XjU6Ujgmtt33aZRM8mTJOw

struct vertexInput {
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
};

struct vertexOutput {
    float4 positionOS : SV_POSITION;
    float3 normalOS : TEXCOORD0;
    float4 tangentOS : TEXCOORD1;
};

vertexOutput vert(vertexInput i) {
    vertexOutput o;
    //放到geo中进行坐标变换
    o.positionOS = i.positionOS;
    o.normalOS = i.normalOS;
    o.tangentOS = i.tangentOS;
    return o;
}


struct TessellationFactors {
    float edge[3] : SV_TessFactor;
    float inside : SV_InsideTessFactor;
};

float _TessellationUniform;
float _GrassDistanceMax;
float _GrassDistanceMin;

float tessellationEdgeFactor(vertexInput vert0, vertexInput vert1) {
    float3 v0 = vert0.positionOS.xyz;
    float3 v1 = vert1.positionOS.xyz;
    float edgeLength = distance(v0, v1);

    float2 vertexXZ = v0.xz;
    float disVertexAndCamera = distance(vertexXZ, _WorldSpaceCameraPos.xz);
    
    //tessClamp = clamp((1 - (disVertexAndCamera - 10) / (_GrassDistanceMax - _GrassDistanceMin)), 0.5, 1);
    float nom = _GrassDistanceMax - disVertexAndCamera;
    float tessClamp = clamp(step(0, nom) * nom / (_GrassDistanceMax - _GrassDistanceMin), 0, 1.0);
    return edgeLength * tessClamp * _TessellationUniform;
}


TessellationFactors patchConstantFunc(InputPatch < vertexInput, 3 > patch) {
    TessellationFactors f;
    f.edge[0] = tessellationEdgeFactor(patch[1], patch[2]);
    f.edge[1] = tessellationEdgeFactor(patch[2], patch[0]);
    f.edge[2] = tessellationEdgeFactor(patch[0], patch[1]);
    f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0f;
    return f;
}

//定义细分的图元，可以为tri、 quad 或 isoline
[domain("tri")]
//定义hull shader创建的输出控制点数量
[outputcontrolpoints(3)]
//定义输出的图元类型point、line、triangle_cw（顺）、triangle_ccw（逆）
[outputtopology("triangle_cw")]
//integer：把一条边n等分
[partitioning("integer")]
//定义计算patch constant data的函数
[patchconstantfunc("patchConstantFunc")]

vertexInput hull(InputPatch < vertexInput, 3 > patch, uint id : SV_OutputControlPointID) {
    return patch[id];
}

[domain("tri")]
vertexOutput domain(TessellationFactors factors, OutputPatch < vertexInput, 3 > patch, float3 barycentricCoordinates : SV_DomainLocation) {
    vertexInput v;

    #define INTERPOLATE(fieldName) v.fieldName = \
        patch[0].fieldName * barycentricCoordinates.x + \
        patch[1].fieldName * barycentricCoordinates.y + \
        patch[2].fieldName * barycentricCoordinates.z;

    INTERPOLATE(positionOS)
    INTERPOLATE(normalOS)
    INTERPOLATE(tangentOS)

    return vert(v);
}