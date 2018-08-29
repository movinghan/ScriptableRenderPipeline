#ifndef LIGHTWEIGHT_PASS_LIT_TERRAIN_INCLUDED
#define LIGHTWEIGHT_PASS_LIT_TERRAIN_INCLUDED

#include "LWRP/ShaderLibrary/Lighting.hlsl"

struct VertexInput
{
    float4 vertex : POSITION;
    float4 tangent : TANGENT;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct VertexOutput
{
    float4 uvMainAndLM              : TEXCOORD0; // xy: control, zw: lightmap
#ifndef TERRAIN_SPLAT_BASEPASS
    float4 uvSplat01                : TEXCOORD1; // xy: splat0, zw: splat1
    float4 uvSplat23                : TEXCOORD2; // xy: splat2, zw: splat3
#endif

#if _NORMALMAP
    half4 normal                    : TEXCOORD3;    // xyz: normal, w: viewDir.x
    half4 tangent                   : TEXCOORD4;    // xyz: tangent, w: viewDir.y
    half4 binormal                  : TEXCOORD5;    // xyz: binormal, w: viewDir.z
#else
    half3 normal                    : TEXCOORD3;
    half3 viewDir                   : TEXCOORD4;
#endif

    half4 fogFactorAndVertexLight   : TEXCOORD6; // x: fogFactor, yzw: vertex light
    float3 positionWS               : TEXCOORD7;
    float4 shadowCoord              : TEXCOORD8;
    float4 clipPos                  : SV_POSITION;
};

void InitializeInputData(VertexOutput IN, half3 normalTS, out InputData input)
{
    input = (InputData)0;

    input.positionWS = IN.positionWS;

#ifdef _NORMALMAP
    half3 viewDir = half3(IN.normal.w, IN.tangent.w, IN.binormal.w);
    input.normalWS = TangentToWorldNormal(normalTS, IN.tangent.xyz, IN.binormal.xyz, IN.normal.xyz);
#else
    half3 viewDir = IN.viewDir;
    input.normalWS = FragmentNormalWS(IN.normal);
#endif

    input.viewDirectionWS = FragmentViewDirWS(viewDir);
#ifdef _SHADOWS_ENABLED
    input.shadowCoord = IN.shadowCoord;
#else
    input.shadowCoord = float4(0, 0, 0, 0);
#endif
    input.fogCoord = IN.fogFactorAndVertexLight.x;
    input.vertexLighting = IN.fogFactorAndVertexLight.yzw;

#ifdef LIGHTMAP_ON
    input.bakedGI = SampleLightmap(IN.uvMainAndLM.zw, input.normalWS);
#endif
}

#ifndef TERRAIN_SPLAT_BASEPASS

void SplatmapMix(VertexOutput IN, half4 defaultAlpha, out half4 splatControl, out half weight, out half4 mixedDiffuse, inout half3 mixedNormal)
{
    splatControl = SAMPLE_TEXTURE2D(_Control, sampler_Control, IN.uvMainAndLM.xy);
    weight = dot(splatControl, 1.0h);

#if !defined(SHADER_API_MOBILE) && defined(TERRAIN_SPLAT_ADDPASS)
    clip(weight == 0.0h ? -1.0h : 1.0h);
#endif

    // Normalize weights before lighting and restore weights in final modifier functions so that the overal
    // lighting result can be correctly weighted.
    splatControl /= (weight + HALF_MIN);

    half4 alpha = defaultAlpha * splatControl;

    mixedDiffuse = 0.0h;
    mixedDiffuse += SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0, IN.uvSplat01.xy) * half4(splatControl.rrr, alpha.r);
    mixedDiffuse += SAMPLE_TEXTURE2D(_Splat1, sampler_Splat0, IN.uvSplat01.zw) * half4(splatControl.ggg, alpha.g);
    mixedDiffuse += SAMPLE_TEXTURE2D(_Splat2, sampler_Splat0, IN.uvSplat23.xy) * half4(splatControl.bbb, alpha.b);
    mixedDiffuse += SAMPLE_TEXTURE2D(_Splat3, sampler_Splat0, IN.uvSplat23.zw) * half4(splatControl.aaa, alpha.a);

#ifdef _NORMALMAP
    half4 nrm = 0.0f;
    nrm += SAMPLE_TEXTURE2D(_Normal0, sampler_Normal0, IN.uvSplat01.xy) * splatControl.r;
    nrm += SAMPLE_TEXTURE2D(_Normal1, sampler_Normal0, IN.uvSplat01.zw) * splatControl.g;
    nrm += SAMPLE_TEXTURE2D(_Normal2, sampler_Normal0, IN.uvSplat23.xy) * splatControl.b;
    nrm += SAMPLE_TEXTURE2D(_Normal3, sampler_Normal0, IN.uvSplat23.zw) * splatControl.a;
    mixedNormal = UnpackNormal(nrm);
#else
    mixedNormal = half3(0.0h, 0.0h, 1.0h);
#endif
}

#endif

void SplatmapFinalColor(inout half4 color, half fogCoord)
{
    color.rgb *= color.a;
    #ifdef TERRAIN_SPLAT_ADDPASS
        ApplyFogColor(color.rgb, half3(0,0,0), fogCoord);
    #else
        ApplyFog(color.rgb, fogCoord);
    #endif
}
#ifdef UNITY_INSTANCING_ENABLED
    TEXTURE2D(_TerrainHeightmapTexture);
    TEXTURE2D(_TerrainNormalmapTexture);
    float4 _TerrainHeightmapRecipSize;   // float4(1.0f/width, 1.0f/height, 1.0f/(width-1), 1.0f/(height-1))
    float4 _TerrainHeightmapScale;       // float4(hmScale.x, hmScale.y / (float)(kMaxHeight), hmScale.z, 0.0f)
#endif

UNITY_INSTANCING_BUFFER_START(Terrain)
    UNITY_DEFINE_INSTANCED_PROP(float4, _TerrainPatchInstanceData)  // float4(xBase, yBase, skipScale, ~)
UNITY_INSTANCING_BUFFER_END(Terrain)

void TerrainInstancing(inout float4 vertex, inout float3 normal, inout float2 uv)
{
#ifdef UNITY_INSTANCING_ENABLED
    float2 patchVertex = vertex.xy;
    float4 instanceData = UNITY_ACCESS_INSTANCED_PROP(Terrain, _TerrainPatchInstanceData);

    float2 sampleCoords = (patchVertex.xy + instanceData.xy) * instanceData.z; // (xy + float2(xBase,yBase)) * skipScale
    float height = UnpackHeightmap(_TerrainHeightmapTexture.Load(int3(sampleCoords, 0)));

    vertex.xz = sampleCoords * _TerrainHeightmapScale.xz;
    vertex.y = height * _TerrainHeightmapScale.y;

    normal = _TerrainNormalmapTexture.Load(int3(sampleCoords, 0)).rgb * 2 - 1;
    uv = sampleCoords * _TerrainHeightmapRecipSize.zw;
#endif
}

void TerrainInstancing(inout float4 vertex, inout float3 normal)
{
    float2 uv = { 0, 0 };
    TerrainInstancing(vertex, normal, uv);
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard Terrain shader
VertexOutput SplatmapVert(VertexInput v)
{
    VertexOutput o = (VertexOutput)0;

    UNITY_SETUP_INSTANCE_ID(v);
    TerrainInstancing(v.vertex, v.normal, v.texcoord);

    float3 positionWS = TransformObjectToWorld(v.vertex.xyz);
    float4 clipPos = TransformWorldToHClip(positionWS);

    o.uvMainAndLM.xy = v.texcoord;
    o.uvMainAndLM.zw = v.texcoord * unity_LightmapST.xy + unity_LightmapST.zw;
#ifndef TERRAIN_SPLAT_BASEPASS
    o.uvSplat01.xy = TRANSFORM_TEX(v.texcoord, _Splat0);
    o.uvSplat01.zw = TRANSFORM_TEX(v.texcoord, _Splat1);
    o.uvSplat23.xy = TRANSFORM_TEX(v.texcoord, _Splat2);
    o.uvSplat23.zw = TRANSFORM_TEX(v.texcoord, _Splat3);
#endif

    half3 viewDir = VertexViewDirWS(GetCameraPositionWS() - positionWS.xyz);

#ifdef _NORMALMAP
    float4 vertexTangent = float4(cross(v.normal, float3(0, 0, 1)), -1.0);
    OutputTangentToWorld(vertexTangent, v.normal, o.tangent.xyz, o.binormal.xyz, o.normal.xyz);

    o.normal.w = viewDir.x;
    o.tangent.w = viewDir.y;
    o.binormal.w = viewDir.z;
#else
    o.normal = TransformObjectToWorldNormal(v.normal);
    o.viewDir = viewDir;
#endif
    o.fogFactorAndVertexLight.x = ComputeFogFactor(clipPos.z);
    o.fogFactorAndVertexLight.yzw = VertexLighting(positionWS, o.normal);
    o.positionWS = positionWS;
    o.clipPos = clipPos;

#ifdef _SHADOWS_ENABLED
    #if SHADOWS_SCREEN
        o.shadowCoord = ComputeShadowCoord(o.clipPos);
    #else
        o.shadowCoord = TransformWorldToShadowCoord(positionWS);
    #endif
#endif

    return o;
}

TEXTURE2D(_MetallicTex);   SAMPLER(sampler_MetallicTex);

// Used in Standard Terrain shader
half4 SplatmapFragment(VertexOutput IN) : SV_TARGET
{
#ifdef TERRAIN_SPLAT_BASEPASS
    half3 normalTS = float3(0, 1, 0);
    half3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uvMainAndLM.xy).rgb;
    half smoothness = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uvMainAndLM.xy).a;
    half metallic = SAMPLE_TEXTURE2D(_MetallicTex, sampler_MetallicTex, IN.uvMainAndLM.xy).r;
    half alpha = 1;
#else
    half4 splatControl;
    half weight;
    half4 mixedDiffuse;
    half4 defaultSmoothness = half4(_Smoothness0, _Smoothness1, _Smoothness2, _Smoothness3);
    half3 normalTS;
    SplatmapMix(IN, defaultSmoothness, splatControl, weight, mixedDiffuse, normalTS);

    half3 albedo = mixedDiffuse.rgb;
    half smoothness = mixedDiffuse.a;
    half metallic = dot(splatControl, half4(_Metallic0, _Metallic1, _Metallic2, _Metallic3));
    half alpha = weight;
#endif

    InputData inputData;
    InitializeInputData(IN, normalTS, inputData);
    half4 color = LightweightFragmentPBR(inputData, albedo, metallic, half3(0.0h, 0.0h, 0.0h), smoothness, /* occlusion */ 1.0, /* emission */ half3(0, 0, 0), alpha);

    SplatmapFinalColor(color, inputData.fogCoord);

    return half4(color.rgb, 1.0h);
}

// Shadow pass

// x: global clip space bias, y: normal world space bias
float4 _ShadowBias;
float3 _LightDirection;

struct VertexInputLean
{
    float4 position     : POSITION;
    float3 normal       : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

float4 ShadowPassVertex(VertexInputLean v) : SV_POSITION
{
    VertexOutput o;
    UNITY_SETUP_INSTANCE_ID(v);
    TerrainInstancing(v.position, v.normal);

    float3 positionWS = TransformObjectToWorld(v.position.xyz);
    float3 normalWS = TransformObjectToWorldDir(v.normal);

    float invNdotL = 1.0 - saturate(dot(_LightDirection, normalWS));
    float scale = invNdotL * _ShadowBias.y;

    // normal bias is negative since we want to apply an inset normal offset
    positionWS = normalWS * scale.xxx + positionWS;
    float4 clipPos = TransformWorldToHClip(positionWS);

    // _ShadowBias.x sign depens on if platform has reversed z buffer
    clipPos.z += _ShadowBias.x;

#if UNITY_REVERSED_Z
    clipPos.z = min(clipPos.z, clipPos.w * UNITY_NEAR_CLIP_VALUE);
#else
    clipPos.z = max(clipPos.z, clipPos.w * UNITY_NEAR_CLIP_VALUE);
#endif

    return clipPos;
}

half4 ShadowPassFragment() : SV_TARGET
{
    return 0;
}

// Depth pass

float4 DepthOnlyVertex(VertexInputLean v) : SV_POSITION
{
    VertexOutput o = (VertexOutput)0;
    UNITY_SETUP_INSTANCE_ID(v);
    TerrainInstancing(v.position, v.normal);
    return TransformObjectToHClip(v.position.xyz);
}

half4 DepthOnlyFragment() : SV_TARGET
{
    return 0;
}

#endif // LIGHTWEIGHT_PASS_LIT_TERRAIN_INCLUDED
