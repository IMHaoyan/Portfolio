Shader "URPCustom/UnLit" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 0, 0, 1)
        [Toggle]_DebugCustomRT ("DebugCustomRT", Float) = 0
    }
    SubShader {
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TintColor;
            float _DebugCustomRT;
        CBUFFER_END

        TEXTURE2D(_myRT);
        SAMPLER(sampler_myRT);

        ENDHLSL
        

        Pass {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            half4 frag(Varyings i) : SV_Target {
                
                half4 myrt = SAMPLE_TEXTURE2D(_myRT, sampler_myRT, i.texcoord);
                half4 albedo = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearRepeat, i.texcoord);
                
                if (_DebugCustomRT == 1)
                    return myrt;
                
                return myrt + albedo;
            }
            ENDHLSL
        }
    }
}