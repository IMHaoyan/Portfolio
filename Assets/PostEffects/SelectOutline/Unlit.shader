Shader "URPCustom/UnLit" {
    Properties { }
    SubShader {
        ZTest Always
        //ZWrite Off
        //Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        struct a2v {
            float3 positionOS : POSITION;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
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
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                return half4(1, 1, 1, 1);
            }
            ENDHLSL
        }
    }
}