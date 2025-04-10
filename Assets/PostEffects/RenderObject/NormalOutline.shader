Shader "Toon/Basic Outline" {
    Properties {
        _OutlineColor ("Outline Color", Color) = (1, 0, 0, 1)
        _Outline ("Outline width", Range(.002, 0.1)) = .005
    }
    SubShader {
        Tags { "RenderType" = "Opaque" }
        
        Cull Front
        ColorMask RGB
        Blend SrcAlpha OneMinusSrcAlpha
        
        Pass {
            Name "OUTLINE"
            
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            
            CBUFFER_START(UnityPerMaterial)
                float _Outline;
                float4 _OutlineColor;
            CBUFFER_END
            
            struct Attributes {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings {
                float4 positionCS : SV_POSITION;
                half fogCoord : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            Varyings vert(Attributes input) {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                
                input.positionOS.xyz += input.normalOS.xyz * _Outline;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                
                output.fogCoord = ComputeFogFactor(output.positionCS.z);
                return output;
            }
            
            half4 frag(Varyings i) : SV_Target {
                half3 col = MixFog(_OutlineColor.rgb, i.fogCoord);
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}