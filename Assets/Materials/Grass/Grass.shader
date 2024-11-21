Shader "URPCustom/UnLit" {
    Properties {
        [IntRange]_TessellationUniform ("Tessellation Uniform", Range(1, 15)) = 1
        _GrassDistanceMin ("DistanceMin", Range(0, 10)) = 1
        _GrassDistanceMax ("DistanceMax", Range(0, 300)) = 70

        _TopColor ("TopColor", Color) = (1, 1, 1, 1)
        _BottomColor ("BottomColor", Color) = (1, 1, 1, 1)
        _BendRotationRandom ("Bend Rotation Random", Range(0, 1)) = 0.2
        _BladeWidth ("Blade Width", Float) = 0.05
        _BladeWidthRandom ("Blade Width Random", Float) = 0.02
        _BladeHeight ("Blade Height", Float) = 0.5
        _BladeHeightRandom ("Blade Height Random", Range(0, 1)) = 0.3
        
        _WindDistortionMap ("Wind Distortion Map", 2D) = "white" { }
        _WindFrequency ("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
        _WindStrength ("Wind Strength", Range(0.001, 1)) = 0.05
        
        _BladeForward ("Blade Forward Amount", Range(0, 1)) = 0.2
        _BladeCurve ("Blade Curvature Amount", Range(1, 4)) = 2

        _Gloss ("Gloss", Range(8, 32)) = 20
        _ambientScale ("_ambientScale", Range(0, 1)) = 0.2
    }
    SubShader {
        Cull Off
        //Cull Back

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Assets/Materials/Grass/CustomTessellation.cginc"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TopColor;
            half4 _BottomColor;
            float _BendRotationRandom;
            float _BladeHeight;
            float _BladeHeightRandom;
            float _BladeWidth;
            float _BladeWidthRandom;

            float _WindStrength;
            float4 _WindFrequency;
            float4 _WindDistortionMap_ST;

            float _BladeForward;
            float _BladeCurve;

            float facing;

            float _Gloss;
            float _ambientScale;

            float3 _PositionMoving;
            float _Strength;
            float _Radius;
        CBUFFER_END
        
        TEXTURE2D(_WindDistortionMap);
        SAMPLER(sampler_WindDistortionMap);

        struct geometryOutput {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS : TEXCOORD2;
        };

        float rand(float3 co) {
            return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
        }

        float3x3 AngleAxis3x3(float angle, float3 axis) {
            float c, s;
            sincos(angle, s, c);

            float t = 1 - c;
            float x = axis.x;
            float y = axis.y;
            float z = axis.z;

            return float3x3(
                t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                t * x * z - s * y, t * y * z + s * x, t * z * z + c
            );
        }

        //Space Transformation
        geometryOutput TransformGeomToClip(float3 positionOS, float2 uv, float3 normalOS) {
            geometryOutput o;
            o.uv = uv;
            o.positionCS = TransformObjectToHClip(positionOS);
            o.positionWS = TransformObjectToWorld(positionOS);
            o.normalWS = TransformObjectToWorldNormal(normalOS);
            return o;
        }

        geometryOutput GenerateGrassVertex(float3 positionOS, float width, float height, float forward, float2 uv, float3x3 transformMatrix) {
            float3 pointTS = float3(width, forward, height);

            float3 normalTS = float3(0, -1, forward);
            float3 normalOS = mul(transformMatrix, normalTS);

            float3 localPosition = positionOS + mul(transformMatrix, pointTS);
            return TransformGeomToClip(localPosition, uv, normalOS);
        }

        #define BLADE_SEGMENTS 3

        [maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
        void geo(triangle vertexOutput IN[3], inout TriangleStream<geometryOutput> triStream) {
            vertexOutput i = IN[0];
            float3 positionOS = IN[0].positionOS.xyz;
            float3 normalOS = i.normalOS;
            float4 tangentOS = i.tangentOS;
            float3 bitangentOS = cross(normalOS, tangentOS.xyz) * tangentOS.w;
            //Tangent to Object
            float3x3 TBN_OS = float3x3(
                tangentOS.x, bitangentOS.x, normalOS.x,
                tangentOS.y, bitangentOS.y, normalOS.y,
                tangentOS.z, bitangentOS.z, normalOS.z
            );

            float3x3 facingRotationMatrix = AngleAxis3x3(rand(positionOS) * PI * 2, float3(0, 0, 1));
            //facingRotationMatrix = float3x3(1, 0, 0, 0, 1, 0, 0, 0, 1);

            float3x3 bendRotationMatrix = AngleAxis3x3(rand(positionOS.zzx) * _BendRotationRandom * PI * 0.5, float3(-1, 0, 0));
            
            float2 uv = positionOS.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency.xy * _Time.y;
            float2 windSample = (SAMPLE_TEXTURE2D_LOD(_WindDistortionMap, sampler_WindDistortionMap, uv, 0).xy * 2 - 1) * _WindStrength;
            
            float3 wind = normalize(float3(windSample.x, windSample.y, 0));
            float3x3 windRotation = AngleAxis3x3(PI * windSample.x, wind);

            float3x3 transformationMatrix = mul(mul(mul(TBN_OS, windRotation), facingRotationMatrix), bendRotationMatrix);
            //根部不动
            float3x3 transformationMatrixFacing = mul(TBN_OS, facingRotationMatrix);
            
            float height = (rand(positionOS.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
            float width = (rand(positionOS.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;

            float forward = rand(positionOS.yyz) * _BladeForward;
            //forward = 1 * _BladeForward;


            // Interactivity
            float3 positionWS = TransformObjectToWorld(IN[0].positionOS.xyz);
            float3 dis = distance(_PositionMoving, positionWS); // distance for radius
            float3 radius = 1 - saturate(dis / _Radius); // in world radius based on objects interaction radius
            float3 sphereDisp = positionWS - _PositionMoving; // position comparison
            sphereDisp *= radius; // position multiplied by radius for falloff
            // increase strength
            sphereDisp = clamp(sphereDisp.xyz * _Strength, -0.8, 0.8);



            for (int index = 0; index < BLADE_SEGMENTS; index++) {
                float t = index / (float)BLADE_SEGMENTS;
                float segmentHeight = height * t;
                float segmentWidth = width * (1 - t);
                
                float segmentForward = pow(t, _BladeCurve) * forward;

                float3x3 transformMatrix = index == 0 ? transformationMatrixFacing : transformationMatrix;

                float3 newPos = (index == 0) ? positionOS : positionOS + (float3(sphereDisp.x, sphereDisp.y, sphereDisp.z)) * t;

                triStream.Append(GenerateGrassVertex(newPos, segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
                triStream.Append(GenerateGrassVertex(newPos, -segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
            }
            triStream.Append(GenerateGrassVertex(positionOS
            + float3(sphereDisp.x * 1.5, sphereDisp.y, sphereDisp.z * 1.5),
            0, height, forward, float2(0.5, 1), transformationMatrix));
        }

        ENDHLSL

        Pass {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma geometry geo
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

            half4 frag(geometryOutput i, float facing : VFACE) : SV_Target {

                //return half4(i.uv, 0, 1);;
                half4 albedo = lerp(_BottomColor, _TopColor, i.uv.y);
                
                float3 positionWS = i.positionWS;
                //return half4(positionWS, 1.0);
                
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                //return half4(mainLight.shadowAttenuation,0,0, 1.0);

                float3 normalWS = facing > 0 ? i.normalWS : - i.normalWS;
                //return half4(normalWS, 1);
                
                half3 ambient = 0;
                ambient += SampleSH(normalWS) * albedo.rgb * _ambientScale;

                float diff = 0.5 * dot(normalWS, mainLight.direction) + 0.5;
                half3 diffuse = diff * albedo.rgb * mainLight.color;
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float spec = pow(saturate(dot(halfDir, normalWS)), _Gloss);
                half3 specular = spec * albedo.rgb * mainLight.color;
                
                half3 col = ambient + (diffuse + specular) * mainLight.shadowAttenuation;
                return half4(col, 1);
            }

            ENDHLSL
        }

        Pass {
            Tags { "LightMode" = "ShadowCaster" }
            
            HLSLPROGRAM

            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma geometry geo
            #pragma fragment fragShadowCaster
            
            half4 fragShadowCaster(geometryOutput i) : SV_Target {
                return 0;
            }

            ENDHLSL
        }
    }
}