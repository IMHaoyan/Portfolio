Shader "URPCustom/UnLit" {
    Properties {
        
    }
    SubShader {
        Cull Off
        ZWrite Off
        ZTest Always

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float _Blur;
            float _DebugCustomRT;
            float2 _camsize;
            float _showBlur;
            float _BloomThreshold;
            float _BlurIntensity;
        CBUFFER_END
        
        TEXTURE2D(_mySolidRT);

        ENDHLSL
        
        
        Pass {
            Name "Blur"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            // v2f vert(a2v i) {
            //     v2f o;
            //     o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
            //     o.uv = i.texcoord;
            //     return o;
            // }

            half4 frag(Varyings i) : SV_TARGET {
                float2 _BlitTexture_TexelSize = 1.0 / _camsize;

                half4 tex = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(-1, -1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(1, -1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(-1, 1) * _BlitTexture_TexelSize * _Blur);
                tex += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord + float2(1, 1) * _BlitTexture_TexelSize * _Blur);
                return tex / 5.0;
            }
            ENDHLSL
        }

        Pass {
            Name "SelectOutline"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag1
            

            #define SAMPLE_COUNT 16

            half4 frag1(Varyings i) : SV_Target {
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                half4 color1 = SAMPLE_TEXTURE2D(_mySolidRT, sampler_LinearClamp, i.texcoord);
                float2 _BlitTexture_TexelSize = 1.0 / _camsize;

                if (_showBlur == 1) {
                    return color1;
                }
                return color + color1 * _BlurIntensity;
            }

            ENDHLSL
        }
        Pass {
            Name "Extract"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag2
            
            half4 frag2(Varyings i) : SV_Target {
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                half4 solidColor = SAMPLE_TEXTURE2D(_mySolidRT, sampler_LinearClamp, i.texcoord);
                if (solidColor.r > 0 && Luminance(color) > _BloomThreshold) {
                    return color;
                }
                return half4(0,0,0,0);
            }

            ENDHLSL
        }
    }
}