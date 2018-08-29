//
// This file was automatically generated. Please don't edit by hand.
//

#ifndef HDSHADOWMANAGER_CS_HLSL
#define HDSHADOWMANAGER_CS_HLSL
// Generated from UnityEngine.Experimental.Rendering.HDPipeline.HDShadowData
// PackingRules = Exact
struct HDShadowData
{
    float4x4 viewProjection;
    float4x4 shadowToWorld;
    float4 scaleOffset;
    float4 textureSize;
    float4 texelSizeRcp;
    float4 viewBias;
    float4 normalBias;
    int flags;
    float edgeTolerance;
};

// Generated from UnityEngine.Experimental.Rendering.HDPipeline.HDDirectionalShadowData
// PackingRules = Exact
struct HDDirectionalShadowData
{
    float4 sphereCascade1;
    float4 sphereCascade2;
    float4 sphereCascade3;
    float4 sphereCascade4;
    float4 cascadeDirection;
    float cascadeBorder1;
    float cascadeBorder2;
    float cascadeBorder3;
    float cascadeBorder4;
};

//
// Accessors for UnityEngine.Experimental.Rendering.HDPipeline.HDShadowData
//
float4x4 GetViewProjection(HDShadowData value)
{
    return value.viewProjection;
}
float4x4 GetShadowToWorld(HDShadowData value)
{
    return value.shadowToWorld;
}
float4 GetScaleOffset(HDShadowData value)
{
    return value.scaleOffset;
}
float4 GetTextureSize(HDShadowData value)
{
    return value.textureSize;
}
float4 GetTexelSizeRcp(HDShadowData value)
{
    return value.texelSizeRcp;
}
float4 GetViewBias(HDShadowData value)
{
    return value.viewBias;
}
float4 GetNormalBias(HDShadowData value)
{
    return value.normalBias;
}
int GetFlags(HDShadowData value)
{
    return value.flags;
}
float GetEdgeTolerance(HDShadowData value)
{
    return value.edgeTolerance;
}

//
// Accessors for UnityEngine.Experimental.Rendering.HDPipeline.HDDirectionalShadowData
//
float4 GetSphereCascade1(HDDirectionalShadowData value)
{
    return value.sphereCascade1;
}
float4 GetSphereCascade2(HDDirectionalShadowData value)
{
    return value.sphereCascade2;
}
float4 GetSphereCascade3(HDDirectionalShadowData value)
{
    return value.sphereCascade3;
}
float4 GetSphereCascade4(HDDirectionalShadowData value)
{
    return value.sphereCascade4;
}
float4 GetCascadeDirection(HDDirectionalShadowData value)
{
    return value.cascadeDirection;
}
float GetCascadeBorder1(HDDirectionalShadowData value)
{
    return value.cascadeBorder1;
}
float GetCascadeBorder2(HDDirectionalShadowData value)
{
    return value.cascadeBorder2;
}
float GetCascadeBorder3(HDDirectionalShadowData value)
{
    return value.cascadeBorder3;
}
float GetCascadeBorder4(HDDirectionalShadowData value)
{
    return value.cascadeBorder4;
}


#endif
