Shader "Hidden/HDRenderPipeline/OpaqueAtmosphericScattering"
{
    HLSLINCLUDE
        #pragma target 4.5
        #pragma only_renderers d3d11 ps4 xboxone vulkan metal switch

        #pragma multi_compile _ DEBUG_DISPLAY

        // #pragma enable_d3d11_debug_symbols

        Texture2DMS<float> _DepthTextureMS;
        
        #include "CoreRP/ShaderLibrary/Common.hlsl"
        #include "CoreRP/ShaderLibrary/Color.hlsl"
        #include "HDRP/ShaderVariables.hlsl"
        #include "HDRP/Lighting/AtmosphericScattering/AtmosphericScattering.hlsl"

        struct Attributes
        {
            uint vertexID : SV_VertexID;
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 texcoord   : TEXCOORD0;
        };

        Varyings Vert(Attributes input)
        {
            Varyings output;
            output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
            output.texcoord   = GetFullScreenTriangleTexCoord(input.vertexID);
            return output;
        }

        inline float4 AtmosphericScatteringCompute(Varyings input, float depth)
        {
            PositionInputs posInput = GetPositionInput(input.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);

            if (depth == UNITY_RAW_FAR_CLIP_VALUE)
            {
                // When a pixel is at far plane, the world space coordinate reconstruction is not reliable.
                // So in order to have a valid position (for example for height fog) we just consider that the sky is a sphere centered on camera with a radius of 5km (arbitrarily chosen value!)
                // And recompute the position on the sphere with the current camera direction.
                float3 viewDirection = -GetWorldSpaceNormalizeViewDir(posInput.positionWS) * 5000.0f;
                posInput.positionWS = GetPrimaryCameraPosition() + viewDirection;
            }

            return EvaluateAtmosphericScattering(posInput);
        }

        float4 Frag(Varyings input) : SV_Target
        {
            float depth = LOAD_TEXTURE2D(_CameraDepthTexture, input.positionCS.xy).x;
            return AtmosphericScatteringCompute(input, depth);
        }

        float4 FragMSAA(Varyings input, uint sampleIndex: SV_SampleIndex) : SV_Target
        {
            int2 msTex = int2(input.texcoord.xy * _ScreenSize.xy);
            float depth = _DepthTextureMS.Load(msTex, sampleIndex).x;
            return AtmosphericScatteringCompute(input, depth);
        }
    ENDHLSL

    SubShader
    {
        // 0: NOMSAA
        Pass
        {
            Cull Off ZTest  Always ZWrite Off Blend  SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment Frag
            ENDHLSL
        }

        // 1: MSAA
        Pass
        {
            Cull Off ZTest  Always ZWrite Off Blend  SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragMSAA
            ENDHLSL
        }
    }
}
