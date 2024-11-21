Shader "URPCustom/UnLit" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 1, 1, 1)
        [IntRange]_TessellationUniform ("Tessellation Uniform", Range(1, 10)) = 1
        _Scale (" _Scale", Float) = 1
    }

    SubShader {
        Cull Back

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Assets/Materials/Grass/CustomTessellation.cginc"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TintColor;
        CBUFFER_END

        ENDHLSL

        Pass {

            HLSLPROGRAM
            #pragma vertex myVert
            #pragma fragment frag
            #pragma hull hull
            #pragma domain domain

            vertexOutput myVert(vertexInput i) {
                vertexOutput o;
                //此处 positionOS : SV_POSITION;
                o.positionOS = TransformObjectToHClip(i.positionOS.xyz);
                //o.positionWS = TransformObjectToWorld(i.positionOS.xyz);
                return o;
            }

            half4 frag(vertexOutput i) : SV_Target {
                // float3 normalWS = TransformObjectToWorldNormal(i.normalOS);
                // return half4(i.positionWS.xyz,1);
                return _TintColor;
            }

            ENDHLSL
        }
    }
}