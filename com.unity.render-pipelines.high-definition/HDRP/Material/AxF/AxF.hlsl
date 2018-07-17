//-----------------------------------------------------------------------------
// SurfaceData and BSDFData
//-----------------------------------------------------------------------------
// SurfaceData is defined in AxF.cs which generates AxF.cs.hlsl
#include "AxF.cs.hlsl"
//#include "../SubsurfaceScattering/SubsurfaceScattering.hlsl"
//#include "CoreRP/ShaderLibrary/VolumeRendering.hlsl"

// Declare the BSDF specific FGD property and its fetching function
#include "../PreIntegratedFGD/PreIntegratedFGD.hlsl"
#include "./Resources/PreIntegratedFGD.hlsl"

// Add support for LTC Area Lights
#include "HDRP/Material/LTCAreaLight/LTCAreaLight.hlsl"


//-----------------------------------------------------------------------------
#define CLEAR_COAT_ROUGHNESS 0.03
#define CLEAR_COAT_PERCEPTUAL_ROUGHNESS RoughnessToPerceptualRoughness(CLEAR_COAT_ROUGHNESS)

#define FLAKES_ROUGHNESS 0.03
#define FLAKES_PERCEPTUAL_ROUGHNESS RoughnessToPerceptualRoughness(FLAKES_ROUGHNESS)
#define FLAKES_F0 1.0


// Define this to recompute vectors after refraction by clear coat
// At the moment, this gives ugly results that I haven't debugged yet so I left it off... :/
//#define RECOMPUTE_VECTORS_AFTER_REFRACTION  1


// Define this to sample the environment maps for each lobe, instead of a single sample for an average lobe
#define USE_COOK_TORRANCE_MULTI_LOBES   1

// Enable reference mode for IBL and area lights
// Both reference define below can be define only if LightLoop is present, else we get a compile error
#ifdef HAS_LIGHTLOOP
// #define AXF_DISPLAY_REFERENCE_AREA
// #define AXF_DISPLAY_REFERENCE_IBL
#endif


//-----------------------------------------------------------------------------
// Debug method (use to display values)
//-----------------------------------------------------------------------------
void GetSurfaceDataDebug( uint paramId, SurfaceData surfaceData, inout float3 result, inout bool needLinearToSRGB ) {
    GetGeneratedSurfaceDataDebug( paramId, surfaceData, result, needLinearToSRGB );

    // Overide debug value output to be more readable
    switch ( paramId ) {
        case DEBUGVIEW_AXF_SURFACEDATA_NORMAL_VIEW_SPACE:
            // Convert to view space
            result = TransformWorldToViewDir(surfaceData.normalWS) * 0.5 + 0.5;
            break;
    }
}

void GetBSDFDataDebug( uint paramId, BSDFData BsdfData, inout float3 result, inout bool needLinearToSRGB ) {
    GetGeneratedBSDFDataDebug(paramId, BsdfData, result, needLinearToSRGB);

    // Overide debug value output to be more readable
    switch ( paramId ) {
        case DEBUGVIEW_AXF_BSDFDATA_NORMAL_VIEW_SPACE:
            // Convert to view space
            result = TransformWorldToViewDir(BsdfData.normalWS) * 0.5 + 0.5;
            break;
    }
}



// This function is use to help with debugging and must be implemented by any lit material
// Implementer must take into account what are the current override component and
// adjust SurfaceData properties accordingdly
void ApplyDebugToSurfaceData( float3x3 worldToTangent, inout SurfaceData surfaceData ) {
    #ifdef DEBUG_DISPLAY
        // NOTE: THe _Debug* uniforms come from /HDRP/Debug/DebugDisplay.hlsl

        // Override value if requested by user this can be use also in case of debug lighting mode like diffuse only
        bool overrideAlbedo = _DebugLightingAlbedo.x != 0.0;
        bool overrideSmoothness = _DebugLightingSmoothness.x != 0.0;
        bool overrideNormal = _DebugLightingNormal.x != 0.0;

        if ( overrideAlbedo ) {
	        surfaceData.diffuseColor = _DebugLightingAlbedo.yzw;
        }

        if ( overrideSmoothness ) {
            //NEWLITTODO
            float overrideSmoothnessValue = _DebugLightingSmoothness.y;
//            surfaceData.perceptualSmoothness = overrideSmoothnessValue;
            surfaceData.specularLobe = overrideSmoothnessValue;
        }

        if ( overrideNormal ) {
	        surfaceData.normalWS = worldToTangent[2];
        }
    #endif
}

// This function is similar to ApplyDebugToSurfaceData but for BSDFData
//
// NOTE:
//
// This will be available and used in ShaderPassForward.hlsl since in AxF.shader,
// just before including the core code of the pass (ShaderPassForward.hlsl) we include
// Material.hlsl (or Lighting.hlsl which includes it) which in turn includes us,
// AxF.shader, via the #if defined(UNITY_MATERIAL_*) glue mechanism.
//
void ApplyDebugToBSDFData( inout BSDFData BsdfData ) {
    #ifdef DEBUG_DISPLAY
        // Override value if requested by user
        // this can be use also in case of debug lighting mode like specular only

        //NEWLITTODO
        //bool overrideSpecularColor = _DebugLightingSpecularColor.x != 0.0;

        //if (overrideSpecularColor)
        //{
        //   float3 overrideSpecularColor = _DebugLightingSpecularColor.yzw;
        //    BsdfData.fresnel0 = overrideSpecularColor;
        //}
    #endif


// DEBUG Anisotropy
//BsdfData.anisotropyAngle = _DEBUG_anisotropyAngle;
//BsdfData.anisotropyAngle += _DEBUG_anisotropyAngle;
//BsdfData.roughness = _SVBRDF_SpecularLobeMap_Scale * float2( _DEBUG_anisotropicRoughessX, _DEBUG_anisotropicRoughessY );

// DEBUG Clear coat
//BsdfData.clearCoatIOR = max( 1.001, _DEBUG_clearCoatIOR );
//BsdfData.clearCoatIOR = max( 1.0, _DEBUG_clearCoatIOR );


}

//----------------------------------------------------------------------
// From Walter 2007 eq. 40
// Expects incoming pointing AWAY from the surface
// eta = IOR_above / IOR_below
// rayIntensity returns 0 in case of total internal reflection
//
float3	Refract( float3 incoming, float3 normal, float eta, out float rayIntensity ) {
	float	c = dot( incoming, normal );
	float	b = 1.0 + eta * (c*c - 1.0);
	if ( b >= 0.0 ) {
		float	k = eta * c - sign(c) * sqrt( b );
		float3	R = k * normal - eta * incoming;
        rayIntensity = 1;
		return normalize( R );
	} else {
        rayIntensity = 0;
		return -incoming;	// Total internal reflection
	}
}

//----------------------------------------------------------------------
// Ref: https://seblagarde.wordpress.com/2013/04/29/memo-on-fresnel-equations/
// Fresnel dieletric / dielectric
real F_FresnelDieletricSafe(real ior, real u) {
    u = max( 1e-3, u ); // Prevents NaNs
    real g = sqrt(max( 0.0, Sq(ior) + Sq(u) - 1.0 ));
    return 0.5 * Sq((g - u) / max( 1e-4, g + u )) * (1.0 + Sq(((g + u) * u - 1.0) / ((g - u) * u + 1.0)));
}


//----------------------------------------------------------------------
// Cook-Torrance functions as provided by X-Rite in the "AxF-Decoding-SDK-1.5.1/doc/html/page2.html#carpaint_BrightnessBRDF" document from the SDK
//static const float  MIN_ROUGHNESS = 0.01;

float CT_D( float N_H, float m ) {
    float cosb_sqr = N_H*N_H;
    float m_sqr = m*m;
    float e = (cosb_sqr - 1.0) / (cosb_sqr*m_sqr);  // -tan(a)² / m²
    return exp(e) / (m_sqr*cosb_sqr*cosb_sqr);  // exp( -tan(a)² / m² ) / (m² * cos(a)^4)
}

// Classical Schlick approximation for Fresnel
float CT_F( float H_V, float F0 ) {
    float f_1_sub_cos = 1.0 - H_V;
    float f_1_sub_cos_sqr = f_1_sub_cos*f_1_sub_cos;
    float f_1_sub_cos_fifth= f_1_sub_cos_sqr*f_1_sub_cos_sqr*f_1_sub_cos;
    return F0 + (1.0 -F0) * f_1_sub_cos_fifth;
}

float CT_G( float N_H, float N_V, float N_L, float H_V ) {
    return min( 1.0, 2.0 * N_H * min( N_V, N_L ) / H_V );
}

float3  MultiLobesCookTorrance( float NdotL, float NdotV, float NdotH, float VdotH ) {
    // Ensure numerical stability
    if ( NdotV < 0.00174532836589830883577820272085 && NdotL < 0.00174532836589830883577820272085 ) //sin(0.1°)
        return 0.0;

    float   specularIntensity = 0.0;
    for ( uint lobeIndex=0; lobeIndex < _CarPaint_lobesCount; lobeIndex++ ) {
        float   F0 = _CarPaint_CT_F0s[lobeIndex];
        float   coeff = _CarPaint_CT_coeffs[lobeIndex];
        float   spread = _CarPaint_CT_spreads[lobeIndex];

//spread = max( MIN_ROUGHNESS, spread );

        specularIntensity += coeff * CT_D( NdotH, spread ) * CT_F( VdotH, F0 );
    }
    specularIntensity *= CT_G( NdotH, NdotV, NdotL, VdotH )  // Shadowing/Masking term
                       / (PI * max( 1e-3, NdotV * NdotL ));

    return specularIntensity;
}


//----------------------------------------------------------------------
// Simple Oren-Nayar implementation
//  normal, unit surface normal
//  light, unit vector pointing toward the light
//  view, unit vector pointing toward the view
//  roughness, Oren-Nayar roughness parameter in [0,PI/2]
//
float   OrenNayar( in float3 n, in float3 v, in float3 l, in float roughness ) {
    float   LdotN = dot( l, n );
    float   VdotN = dot( v, n );

    float   gamma = dot( v - n * VdotN, l - n * LdotN )
                    / (sqrt( saturate( 1.0 - VdotN*VdotN ) ) * sqrt( saturate( 1.0 - LdotN*LdotN ) ));

    float rough_sq = roughness * roughness;
//    float A = 1.0 - 0.5 * (rough_sq / (rough_sq + 0.33));   // You can replace 0.33 by 0.57 to simulate the missing inter-reflection term, as specified in footnote of page 22 of the 1992 paper
    float A = 1.0 - 0.5 * (rough_sq / (rough_sq + 0.57));   // You can replace 0.33 by 0.57 to simulate the missing inter-reflection term, as specified in footnote of page 22 of the 1992 paper
    float B = 0.45 * (rough_sq / (rough_sq + 0.09));

    // Original formulation
//  float angle_vn = acos( VdotN );
//  float angle_ln = acos( LdotN );
//  float alpha = max( angle_vn, angle_ln );
//  float beta  = min( angle_vn, angle_ln );
//  float C = sin(alpha) * tan(beta);

    // Optimized formulation (without tangents, arccos or sines)
    float2  cos_alpha_beta = VdotN < LdotN ? float2( VdotN, LdotN ) : float2( LdotN, VdotN );   // Here we reverse the min/max since cos() is a monotonically decreasing function
    float2  sin_alpha_beta = sqrt( saturate( 1.0 - cos_alpha_beta*cos_alpha_beta ) );           // Saturate to avoid NaN if ever cos_alpha > 1 (it happens with floating-point precision)
    float   C = sin_alpha_beta.x * sin_alpha_beta.y / (1e-6 + cos_alpha_beta.y);

    return A + B * max( 0.0, gamma ) * C;
}


//----------------------------------------------------------------------
float   G_smith( float NdotV, float roughness ) {
    float   a2 = Sq( roughness );
    return 2 * NdotV / (NdotV + sqrt( a2 + (1 - a2) * Sq(NdotV) ));
}


//-----------------------------------------------------------------------------
// conversion function for forward
//-----------------------------------------------------------------------------

BSDFData ConvertSurfaceDataToBSDFData( uint2 positionSS, SurfaceData surfaceData ) {
	BSDFData    data;
//	ZERO_INITIALIZE(BSDFData, data);

	data.normalWS = surfaceData.normalWS;
	data.tangentWS = surfaceData.tangentWS;
	data.biTangentWS = surfaceData.biTangentWS;

    ////////////////////////////////////////////////////////////////////////////////////////
    #ifdef _AXF_BRDF_TYPE_SVBRDF
	    data.diffuseColor = surfaceData.diffuseColor;
        data.specularColor = surfaceData.specularColor;
        data.fresnelF0 = surfaceData.fresnelF0;
        data.roughness = surfaceData.specularLobe;
        data.height_mm = surfaceData.height_mm;
        data.anisotropyAngle = surfaceData.anisotropyAngle;
        data.clearCoatColor = surfaceData.clearCoatColor;
        data.clearCoatNormalWS = surfaceData.clearCoatNormalWS;
        data.clearCoatIOR = surfaceData.clearCoatIOR;

// Useless but pass along anyway
data.flakesUV = surfaceData.flakesUV;
data.flakesMipLevel = surfaceData.flakesMipLevel;

    ////////////////////////////////////////////////////////////////////////////////////////
    #elif defined(_AXF_BRDF_TYPE_CAR_PAINT)
	    data.diffuseColor = surfaceData.diffuseColor;
	    data.flakesUV = surfaceData.flakesUV;
        data.flakesMipLevel = surfaceData.flakesMipLevel;
        data.clearCoatColor = 1.0;  // Not provided, assume white...
        data.clearCoatIOR = surfaceData.clearCoatIOR;
        data.clearCoatNormalWS = surfaceData.clearCoatNormalWS;

// Although not used, needs to be initialized... :'(
data.specularColor = 0;
data.fresnelF0 = 0;
data.roughness = 0;
data.height_mm = 0;
data.anisotropyAngle = 0;
    #endif

	ApplyDebugToBSDFData(data);
	return data;
}

//-----------------------------------------------------------------------------
// PreLightData
//
// Make sure we respect naming conventions to reuse ShaderPassForward as is,
// ie struct (even if opaque to the ShaderPassForward) name is PreLightData,
// GetPreLightData prototype.
//-----------------------------------------------------------------------------

// Precomputed lighting data to send to the various lighting functions
struct PreLightData {
	float   NdotV;                  // Could be negative due to normal mapping, use ClampNdotV()
    float3  IOR;

    #ifdef _AXF_BRDF_TYPE_SVBRDF
        // Anisotropy
        float2  anisoX;
        float2  anisoY;
    #endif

    // Clear coat
    float   clearCoatF0;
    float3  clearCoatViewWS;        // World-space view vector refracted by clear coat

    // IBL
    float3  IBLDominantDirectionWS; // Dominant specular direction, used for IBL in EvaluateBSDF_Env() and also in area lights when clear coat is enabled
    #ifdef _AXF_BRDF_TYPE_SVBRDF
        float   IBLPerceptualRoughness;
	    float3  specularFGD;
	    float   diffuseFGD;
    #endif

    // Area lights (17 VGPRs)
    // TODO: 'orthoBasisViewNormal' is just a rotation around the normal and should thus be just 1x VGPR.
    float3x3    orthoBasisViewNormal;       // Right-handed view-dependent orthogonal basis around the normal (6x VGPRs)
    #ifdef _AXF_BRDF_TYPE_SVBRDF
        float3x3    ltcTransformDiffuse;    // Inverse transformation                                         (4x VGPRs)
        float       ltcTransformDiffuse_Amplitude;
        float3x3    ltcTransformSpecular;   // Inverse transformation                                         (4x VGPRs)
        float3      ltcTransformSpecular_Amplitude;
    #endif
    float3x3    ltcTransformClearCoat;      // Inverse transformation for GGX                                 (4x VGPRs)
    float3      ltcTransformClearCoat_Amplitude;
};

PreLightData    GetPreLightData( float3 viewWS, PositionInputs posInput, inout BSDFData BsdfData ) {
	PreLightData    preLightData;
//	ZERO_INITIALIZE( PreLightData, preLightData );

	float3  normalWS = BsdfData.normalWS;
	preLightData.NdotV = dot( normalWS, viewWS );
    preLightData.IOR = GetIorN( BsdfData.fresnelF0, 1.0 );

	float   NdotV = ClampNdotV( preLightData.NdotV );
    float   clearCoatNdotV = NdotV;

    #ifdef _AXF_BRDF_TYPE_SVBRDF
        // Handle anisotropy
        float2  anisoDir = float2( 1, 0 );
        if ( _flags & 1 ) {
//            sincos( BsdfData.anisotropyAngle, anisoDir.y, anisoDir.x );
            sincos( BsdfData.anisotropyAngle, anisoDir.x, anisoDir.y );    // Eyeballed the fact that an angle of 0 is actually 90° from tangent axis!
        }

        preLightData.anisoX = anisoDir;
        preLightData.anisoY = float2( -anisoDir.y, anisoDir.x );
    #endif


    // ==============================================================================
    // Handle clear coat
//  preLightData.clearCoatF0 = IorToFresnel0( BsdfData.clearCoatIOR );
    preLightData.clearCoatF0 = Sq( (BsdfData.clearCoatIOR - 1) / (BsdfData.clearCoatIOR + 1) );
    float   TIRIntensity;
    preLightData.clearCoatViewWS = -Refract( viewWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR, TIRIntensity );    // This is independent of lighting

    if ( (_flags & 0x6U) == 0x6U ) {
        // If refraction is enabled then bend view vector and update NdotV
        viewWS =  preLightData.clearCoatViewWS;
	    preLightData.NdotV = dot( normalWS, viewWS );
	    NdotV = ClampNdotV( preLightData.NdotV );
    }


    // ==============================================================================
    // Handle IBL +  multiscattering
    preLightData.IBLDominantDirectionWS = reflect( -viewWS, normalWS );

    #ifdef _AXF_BRDF_TYPE_SVBRDF
        preLightData.IBLPerceptualRoughness = RoughnessToPerceptualRoughness( 0.5 * (BsdfData.roughness.x + BsdfData.roughness.y) );    // @TODO => Anisotropic IBL?
        float specularReflectivity;
        switch ( (_SVBRDF_BRDFType >> 1) & 7 ) {
            case 0: GetPreIntegratedFGDWardLambert( NdotV, preLightData.IBLPerceptualRoughness, BsdfData.fresnelF0, preLightData.specularFGD, preLightData.diffuseFGD, specularReflectivity ); break;
//            case 1: // @TODO: Support Blinn-Phong FGD?
            case 2: GetPreIntegratedFGDCookTorranceLambert( NdotV, preLightData.IBLPerceptualRoughness, BsdfData.fresnelF0, preLightData.specularFGD, preLightData.diffuseFGD, specularReflectivity ); break;
            case 3: GetPreIntegratedFGDGGXAndDisneyDiffuse( NdotV, preLightData.IBLPerceptualRoughness, BsdfData.fresnelF0, preLightData.specularFGD, preLightData.diffuseFGD, specularReflectivity ); break;
//            case 4: // @TODO: Support Blinn-Phong FGD?
            default:    // Use GGX by default
                GetPreIntegratedFGDGGXAndDisneyDiffuse( NdotV, preLightData.IBLPerceptualRoughness, BsdfData.fresnelF0, preLightData.specularFGD, preLightData.diffuseFGD, specularReflectivity );
                break;
        }

    #elif defined(_AXF_BRDF_TYPE_CAR_PAINT)
        #if !USE_COOK_TORRANCE_MULTI_LOBES
            // ==============================================================================
            // Computes weighted average of roughness values
            // Used to sample IBL with a single roughness but useless if we sample as many times as there are lobes?? (*gasp*)
            float2  sumRoughness = 0.0;
            for ( uint lobeIndex=0; lobeIndex < _CarPaint_lobesCount; lobeIndex++ ) {
                float   coeff = _CarPaint_CT_coeffs[lobeIndex];
                float   spread = _CarPaint_CT_spreads[lobeIndex];

//spread = max( MIN_ROUGHNESS, spread );

                sumRoughness += coeff * float2( spread, 1 );
            }
            preLightData.IBLPerceptualRoughness = RoughnessToPerceptualRoughness( sumRoughness.x / sumRoughness.y );    // Not used if sampling the environment for each Cook-Torrance lobe
        #endif
    #endif


    // ==============================================================================
    // Area lights

    // Construct a right-handed view-dependent orthogonal basis around the normal
    preLightData.orthoBasisViewNormal[0] = normalize( viewWS - normalWS * preLightData.NdotV ); // Do not clamp NdotV here
    preLightData.orthoBasisViewNormal[2] = normalWS;
    preLightData.orthoBasisViewNormal[1] = cross( preLightData.orthoBasisViewNormal[2], preLightData.orthoBasisViewNormal[0] );

    #ifdef _AXF_BRDF_TYPE_SVBRDF
        // UVs for sampling the LUTs
        float2  UV = LTCGetSamplingUV( NdotV, preLightData.IBLPerceptualRoughness );

        // Load diffuse LTC
        if ( _SVBRDF_BRDFType & 1 ) {
            preLightData.ltcTransformDiffuse = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_OREN_NAYAR );
            preLightData.ltcTransformDiffuse_Amplitude = 1.0;   // @TODO: Sample Oren-Nayar FGD!
        } else {
            preLightData.ltcTransformDiffuse = k_identity3x3;   // Lambert
            preLightData.ltcTransformDiffuse_Amplitude = 1.0;
        }

        // Load specular LTC
        switch ( (_SVBRDF_BRDFType >> 1) & 7 ) {
            case 0: preLightData.ltcTransformSpecular = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_WARD ); break;
            case 2: preLightData.ltcTransformSpecular = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_COOK_TORRANCE ); break;
            case 3: preLightData.ltcTransformSpecular = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_GGX ); break;
            case 1: // BLINN-PHONG
            case 4: // PHONG;
            {
                // According to https://computergraphics.stackexchange.com/questions/1515/what-is-the-accepted-method-of-converting-shininess-to-roughness-and-vice-versa
                //  float   exponent = 2/roughness^4 - 2;
                //
                float   exponent = PerceptualRoughnessToRoughness( preLightData.IBLPerceptualRoughness );
                float   roughness = pow( max( 0.0, 2.0 / (exponent + 2) ), 1.0 / 4.0 );
                float2  UV = LTCGetSamplingUV( NdotV, RoughnessToPerceptualRoughness( roughness ) );
                preLightData.ltcTransformSpecular = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_COOK_TORRANCE );
                break;
            }

            default:    // @TODO
                preLightData.ltcTransformSpecular = 0;
                break;
        }

        // LTC amplitude is actually BRDF's albedo for a given N.V and roughness, which is conveniently the FGD table term we already computed! <3
        // ref: http://advances.realtimerendering.com/s2016/s2016_ltc_fresnel.pdf
        preLightData.ltcTransformSpecular_Amplitude = preLightData.specularFGD;

    #elif defined(_AXF_BRDF_TYPE_CAR_PAINT)



    #endif  // _AXF_BRDF_TYPE_SVBRDF

    // Load clear-coat LTC
    preLightData.ltcTransformClearCoat = 0.0;
    preLightData.ltcTransformClearCoat_Amplitude = 0;
    if ( _flags & 2 ) {
        float2  UV = LTCGetSamplingUV( clearCoatNdotV, CLEAR_COAT_PERCEPTUAL_ROUGHNESS );
        preLightData.ltcTransformClearCoat = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_GGX );
        float   specularReflectivity, dummyDiffuseFGD;
        GetPreIntegratedFGDGGXAndDisneyDiffuse( clearCoatNdotV, CLEAR_COAT_PERCEPTUAL_ROUGHNESS, preLightData.clearCoatF0, preLightData.ltcTransformClearCoat_Amplitude, dummyDiffuseFGD, specularReflectivity );
    }

	return preLightData;
}


//-----------------------------------------------------------------------------
// bake lighting function
//-----------------------------------------------------------------------------

//
// GetBakedDiffuseLighting will be called from ShaderPassForward.hlsl.
//
// GetBakedDiffuseLighting function compute the bake lighting + emissive color to be store in emissive buffer (Deferred case)
// In forward it must be add to the final contribution.
// This function require the 3 structure surfaceData, builtinData, BsdfData because it may require both the engine side data, and data that will not be store inside the gbuffer.
float3  GetBakedDiffuseLighting( SurfaceData surfaceData, BuiltinData builtinData, BSDFData BsdfData, PreLightData preLightData ) {

    #ifdef DEBUG_DISPLAY
        if ( _DebugLightingMode == DEBUGLIGHTINGMODE_LUX_METER ) {
            // The lighting in SH or lightmap is assume to contain bounced light only (i.e no direct lighting), and is divide by PI (i.e Lambert is apply), so multiply by PI here to get back the illuminance
            return builtinData.bakeDiffuseLighting * PI;
        }
    #endif

	//NEWLITTODO
    #ifdef _AXF_BRDF_TYPE_SVBRDF
	    // Premultiply bake diffuse lighting information with DisneyDiffuse pre-integration
	    return builtinData.bakeDiffuseLighting * preLightData.diffuseFGD * BsdfData.diffuseColor + builtinData.emissiveColor;
    #else
	    return builtinData.bakeDiffuseLighting * BsdfData.diffuseColor + builtinData.emissiveColor;
    #endif
}


//-----------------------------------------------------------------------------
// light transport functions
//-----------------------------------------------------------------------------
LightTransportData	GetLightTransportData( SurfaceData surfaceData, BuiltinData builtinData, BSDFData BsdfData ) {
    LightTransportData lightTransportData;

    lightTransportData.diffuseColor = BsdfData.diffuseColor;
    lightTransportData.emissiveColor = builtinData.emissiveColor;

    return lightTransportData;
}

//-----------------------------------------------------------------------------
// LightLoop related function (Only include if required)
// HAS_LIGHTLOOP is define in Lighting.hlsl
//-----------------------------------------------------------------------------

#ifdef HAS_LIGHTLOOP

#ifndef _SURFACE_TYPE_TRANSPARENT
    // For /Lighting/LightEvaluation.hlsl:
    #define USE_DEFERRED_DIRECTIONAL_SHADOWS // Deferred shadows are always enabled for opaque objects
#endif

#include "../../Lighting/LightEvaluation.hlsl"
#include "../../Lighting/Reflection/VolumeProjection.hlsl"

//-----------------------------------------------------------------------------
// Lighting structure for light accumulation
//-----------------------------------------------------------------------------

// These structure allow to accumulate lighting accross the Lit material
// AggregateLighting is init to zero and transfer to EvaluateBSDF, but the LightLoop can't access its content.
//
// In fact, all structures here are opaque but used by LightLoop.hlsl.
// The Accumulate* functions are also used by LightLoop to accumulate the contributions of lights.
//
struct DirectLighting {
	float3  diffuse;
	float3  specular;
};

struct IndirectLighting {
	float3  specularReflected;
	float3  specularTransmitted;
};

struct AggregateLighting {
	DirectLighting      direct;
	IndirectLighting    indirect;
};

void AccumulateDirectLighting( DirectLighting src, inout AggregateLighting dst ) {
	dst.direct.diffuse += src.diffuse;
	dst.direct.specular += src.specular;
}

void AccumulateIndirectLighting( IndirectLighting src, inout AggregateLighting dst ) {
	dst.indirect.specularReflected += src.specularReflected;
	dst.indirect.specularTransmitted += src.specularTransmitted;
}

//-----------------------------------------------------------------------------
// BSDF share between directional light, punctual light and area light (reference)
//-----------------------------------------------------------------------------

float3  ComputeClearCoatExtinction( inout float3 viewWS, inout float3 lightWS, PreLightData preLightData, BSDFData BsdfData ) {
    // Compute input/output Fresnel attenuations
    float   LdotN = saturate( dot( lightWS, BsdfData.clearCoatNormalWS ) );
    float3  Fin = F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotN );

    float   VdotN = saturate( dot( viewWS, BsdfData.clearCoatNormalWS ) );
    float3  Fout = F_FresnelDieletricSafe( BsdfData.clearCoatIOR, VdotN );

    // Apply optional refraction
    float   TIRIntensity = 1.0;
    if ( _flags & 4U ) {
        lightWS = -Refract( lightWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR, TIRIntensity );
        float   TIRIntensityView;
        viewWS = -Refract( viewWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR, TIRIntensityView );
        TIRIntensity *= TIRIntensityView;
//        viewWS = preLightData.clearCoatViewWS;
    }

    return TIRIntensity * (1-Fin) * (1-Fout);
}


#ifdef _AXF_BRDF_TYPE_SVBRDF

float3  ComputeWard( float3 H, float LdotH, float NdotL, float NdotV, float3 positionWS, PreLightData preLightData, BSDFData BsdfData ) {

    // Evaluate Fresnel term
    float3  F = 0.0;
    switch ( _SVBRDF_BRDFVariants & 3 ) {
        case 1: F = F_FresnelDieletricSafe( BsdfData.fresnelF0.y, LdotH ); break;
        case 2: F = F_Schlick( BsdfData.fresnelF0, LdotH ); break;
    }

    // Evaluate normal distribution function
    float3  tsH = float3( dot( H, BsdfData.tangentWS ), dot( H, BsdfData.biTangentWS ), dot( H, BsdfData.normalWS ) );
    float2  rotH = (tsH.x * preLightData.anisoX + tsH.y * preLightData.anisoY) / tsH.z;
    float   N = exp( -Sq(rotH.x / BsdfData.roughness.x) - Sq(rotH.y / BsdfData.roughness.y) )
              / (PI * BsdfData.roughness.x*BsdfData.roughness.y);

    switch ( (_SVBRDF_BRDFVariants >> 2) & 3 ) {
        case 0: N /= 4.0 * Sq( LdotH ) * Sq(Sq(tsH.z)); break; // Moroder
        case 1: N /= 4.0 * NdotL; break;                       // Duer
        case 2: N /= 4.0 * sqrt( NdotL ); break;               // Ward
    }

    return BsdfData.specularColor * F * N;
}

float3  ComputeBlinnPhong( float3 H, float LdotH, float NdotL, float NdotV, float3 positionWS, PreLightData preLightData, BSDFData BsdfData ) {
    float2  exponents = exp2( BsdfData.roughness );

    // Evaluate normal distribution function
    float3  tsH = float3( dot( H, BsdfData.tangentWS ), dot( H, BsdfData.biTangentWS ), dot( H, BsdfData.normalWS ) );
    float2  rotH = tsH.x * preLightData.anisoX + tsH.y * preLightData.anisoY;

    float3  N = 0;
    switch ( (_SVBRDF_BRDFVariants >> 4) & 3 ) {
        case 0: {   // Ashikmin-Shirley
            N   = sqrt( (1+exponents.x) * (1+exponents.y) ) / (8 * PI)
                * pow( saturate( tsH.z ), (exponents.x * Sq(rotH.x) + exponents.y * Sq(rotH.y)) / (1 - Sq(tsH.z)) )
                / (LdotH * max( NdotL, NdotV ));
            break;
        }

        case 1: {   // Blinn
            float   exponent = 0.5 * (exponents.x + exponents.y);    // Should be isotropic anyway...
            N   = (exponent + 2) / (8 * PI)
                * pow( saturate( tsH.z ), exponent );
            break;
        }

        case 2: // VRay
        case 3: // Lewis
            N = 1000 * float3( 1, 0, 1 );   // Not documented...
            break;
    }

    return BsdfData.specularColor * N;
}

float3  ComputeCookTorrance( float3 H, float LdotH, float NdotL, float NdotV, float3 positionWS, PreLightData preLightData, BSDFData BsdfData ) {
    float   NdotH = dot( H, BsdfData.normalWS );
    float   sqNdotH = Sq( NdotH );

    // Evaluate Fresnel term
    float3  F = F_Schlick( BsdfData.fresnelF0, LdotH );

    // Evaluate (isotropic) normal distribution function (Beckmann)
    float   sqAlpha = BsdfData.roughness.x * BsdfData.roughness.y;
    float   N = exp( (sqNdotH - 1) / (sqNdotH * sqAlpha) )
              / (PI * Sq(sqNdotH) * sqAlpha);

    // Evaluate shadowing/masking term
    float   G = CT_G( NdotH, NdotV, NdotL, LdotH );

    return BsdfData.specularColor * F * N * G;
}

float3  ComputeGGX( float3 H, float LdotH, float NdotL, float NdotV, float3 positionWS, PreLightData preLightData, BSDFData BsdfData ) {
    // Evaluate Fresnel term
    float3  F = F_Schlick( BsdfData.fresnelF0, LdotH );

    // Evaluate normal distribution function (Trowbridge-Reitz)
    float3  tsH = float3( dot( H, BsdfData.tangentWS ), dot( H, BsdfData.biTangentWS ), dot( H, BsdfData.normalWS ) );
    float3  rotH = float3( (tsH.x * preLightData.anisoX + tsH.y * preLightData.anisoY) / BsdfData.roughness, tsH.z );
    float   N = 1.0 / (PI * BsdfData.roughness.x*BsdfData.roughness.y) * 1.0 / Sq( dot( rotH, rotH ) );

    // Evaluate shadowing/masking term
    float   roughness = 0.5 * (BsdfData.roughness.x + BsdfData.roughness.y);
    float   G = G_smith( NdotL, roughness ) * G_smith( NdotV, roughness );
            G /= 4.0 * NdotL * NdotV;

    return BsdfData.specularColor * F * N * G;
}

float3  ComputePhong( float3 H, float LdotH, float NdotL, float NdotV, float3 positionWS, PreLightData preLightData, BSDFData BsdfData ) {
    return 1000 * float3( 1, 0, 1 );
}


// This function applies the BSDF. Assumes that NdotL is positive.
void	BSDF(   float3 viewWS, float3 lightWS, float NdotL, float3 positionWS, PreLightData preLightData, BSDFData BsdfData,
                out float3 diffuseLighting, out float3 specularLighting ) {

    // Compute half vector used by various components of the BSDF
    float3  H = normalize( viewWS + lightWS );
    float   LdotH = saturate( dot( H, lightWS ) );

    // Apply clear coat
    float3  clearCoatExtinction = 1.0;
    float3  clearCoatReflection = 0.0;
    if ( _flags & 2 ) {
        clearCoatReflection = (BsdfData.clearCoatColor / PI) * F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotH ); // Full reflection in mirror direction (we use expensive Fresnel here so the clear coat properly disappears when IOR -> 1)
        clearCoatExtinction = ComputeClearCoatExtinction( viewWS, lightWS, preLightData, BsdfData );
        #if RECOMPUTE_VECTORS_AFTER_REFRACTION
            if ( _flags & 4U ) {
                // Recompute half vector after refraction
                H = normalize( viewWS + lightWS );
                LdotH = saturate( dot( H, lightWS ) );
                preLightData.NdotV = dot( BsdfData.normalWS, viewWS );
            }
        #endif
    }

    float   NdotV = ClampNdotV( preLightData.NdotV );

    // Compute diffuse term
    float3  diffuseTerm = Lambert();
    if ( _SVBRDF_BRDFType & 1 ) {
        float   diffuseRoughness = 0.5 * HALF_PI;    // Arbitrary roughness (not specified in the documentation...)
//        float   diffuseRoughness = _DEBUG_anisotropicRoughessX * HALF_PI;    // Arbitrary roughness (not specified in the documentation...)
        diffuseTerm = INV_PI * OrenNayar( BsdfData.normalWS, viewWS, lightWS, diffuseRoughness );
    }

    // Compute specular term
    float3  specularTerm = float3( 1, 0, 0 );
    switch ( (_SVBRDF_BRDFType >> 1) & 7 ) {
        case 0: specularTerm = ComputeWard( H, LdotH, NdotL, NdotV, positionWS, preLightData, BsdfData ); break;
        case 1: specularTerm = ComputeBlinnPhong( H, LdotH, NdotL, NdotV, positionWS, preLightData, BsdfData ); break;
        case 2: specularTerm = ComputeCookTorrance( H, LdotH, NdotL, NdotV, positionWS, preLightData, BsdfData ); break;
        case 3: specularTerm = ComputeGGX( H, LdotH, NdotL, NdotV, positionWS, preLightData, BsdfData ); break;
        case 4: specularTerm = ComputePhong( H, LdotH, NdotL, NdotV, positionWS, preLightData, BsdfData ); break;
        default:    // @TODO
            specularTerm = 1000 * float3( 1, 0, 1 );
            break;
    }

    // We don't multiply by 'BsdfData.diffuseColor' here. It's done only once in PostEvaluateBSDF().
    diffuseLighting = clearCoatExtinction * diffuseTerm;
    specularLighting = clearCoatExtinction * specularTerm + clearCoatReflection;
}

#elif defined(_AXF_BRDF_TYPE_CAR_PAINT)

// Samples the "BRDF Color Table" as explained in "AxF-Decoding-SDK-1.5.1/doc/html/page2.html#carpaint_ColorTable" from the SDK
float3  GetBRDFColor( float thetaH, float thetaD ) {

#if 0   // <== BMAYAUX: Define this to use the code from the documentation
    // In the documentation they write that we must divide by PI/2 (it would seem)
    float2  UV = float2( 2.0 * thetaH / PI, 2.0 * thetaD / PI );

    // BMAYAUX: Problem here is that the BRDF color tables are only defined in the upper-left triangular part of the texture
    // It's not indicated anywhere in the SDK documentation but I decided to clamp to the diagonal otherwise we get black values if UV.x+UV.y > 0.5!
    UV *= 2.0;
    UV *= saturate( UV.x + UV.y ) / max( 1e-3, UV.x + UV.y );
    UV *= 0.5;
#else
    // BMAYAUX: But the acos yields values in [0,PI] and the texture seems to be indicating the entire PI range is covered so...
    float2  UV = float2( thetaH / PI, thetaD / PI );
#endif

    // Rescale UVs to account for 0.5 texel offset
    uint2   textureSize;
    _CarPaint_BRDFColorMap_sRGB.GetDimensions( textureSize.x, textureSize.y );
    UV = (0.5 + UV * (textureSize-1)) / textureSize;

    return _CarPaint_BRDFColorMap_Scale * SAMPLE_TEXTURE2D_LOD( _CarPaint_BRDFColorMap_sRGB, sampler_CarPaint_BRDFColorMap_sRGB, float2( UV.x, 1 - UV.y ), 0 ).xyz;
}

// Samples the "BTF Flakes" texture as explained in "AxF-Decoding-SDK-1.5.1/doc/html/page2.html#carpaint_FlakeBTF" from the SDK
uint    SampleFlakesLUT( uint index ) {
    return 255.0 * _CarPaint_thetaFI_sliceLUTMap[uint2( index, 0 )].x;
// Hardcoded LUT
//    uint    pipoLUT[] = { 0, 8, 16, 24, 32, 40, 47, 53, 58, 62, 65, 67 };
//    return pipoLUT[min(11, _index)];
}

float3  SamplesFlakes( float2 UV, uint sliceIndex, float mipLevel ) {
    return _CarPaint_BTFFlakesMap_Scale * SAMPLE_TEXTURE2D_ARRAY_LOD( _CarPaint_BTFFlakesMap_sRGB, sampler_CarPaint_BTFFlakesMap_sRGB, UV, sliceIndex, mipLevel ).xyz;
}

#if 0
// Original code from the SDK, cleaned up a bit...
float3  CarPaint_BTF( float thetaH, float thetaD, BSDFData BsdfData ) {
    float2  UV = BsdfData.flakesUV;
    float   mipLevel = BsdfData.flakesMipLevel;

    // thetaH sampling defines the angular sampling, i.e. angular flake lifetime
    float   binIndexH = _CarPaint_numThetaF * (2.0 * thetaH / PI) + 0.5;
    float   binIndexD = _CarPaint_numThetaF * (2.0 * thetaD / PI) + 0.5;

    // Bilinear interpolate indices and weights
    uint    thetaH_low = floor( binIndexH );
    uint    thetaD_low = floor( binIndexD );
    uint    thetaH_high = thetaH_low + 1;
    uint    thetaD_high = thetaD_low + 1;
    float   thetaH_weight = binIndexH - thetaH_low;
    float   thetaD_weight = binIndexD - thetaD_low;

    // To allow lower thetaD samplings while preserving flake lifetime, "virtual" thetaD patches are generated by shifting existing ones 
    float2   offset_l = 0;
    float2   offset_h = 0;
// BMAYAUX: At the moment I couldn't find any car paint material with the condition below
//    if ( _CarPaint_numThetaI < _CarPaint_numThetaF ) {
//        offset_l = float2( rnd_numbers[2*thetaD_low], rnd_numbers[2*thetaD_low+1] );
//        offset_h = float2( rnd_numbers[2*thetaD_high], rnd_numbers[2*thetaD_high+1] );
//        if ( thetaD_low & 1 )
//            UV.xy = UV.yx;
//        if ( thetaD_high & 1 )
//            UV.xy = UV.yx;
//
//        // Map to the original sampling
//        thetaD_low = floor( thetaD_low * float(_CarPaint_numThetaI) / _CarPaint_numThetaF );
//        thetaD_high = floor( thetaD_high * float(_CarPaint_numThetaI) / _CarPaint_numThetaF );
//    }

    float3  H0_D0 = 0.0;
    float3  H1_D0 = 0.0;
    float3  H0_D1 = 0.0;
    float3  H1_D1 = 0.0;

    // Access flake texture - make sure to stay in the correct slices (no slip over)
    if ( thetaD_low < _CarPaint_maxThetaI ) {
        float2  UVl = UV + offset_l;
        float2  UVh = UV + offset_h;

        uint    LUT0 = SampleFlakesLUT( thetaD_low );
        uint    LUT1 = SampleFlakesLUT( thetaD_high );
        uint    LUT2 = SampleFlakesLUT( thetaD_high+1 );

        if ( LUT0 + thetaH_low < LUT1 ) {
            H0_D0 = SamplesFlakes( UVl, LUT0 + thetaH_low, mipLevel );
            if ( LUT0 + thetaH_high < LUT1 ) {
                H1_D0 = SamplesFlakes( UVl, LUT0 + thetaH_high, mipLevel );
            }
            else H1_D0 = H0_D0 ??
        }

        if ( thetaD_high < _CarPaint_maxThetaI ) {
            if ( LUT1 + thetaH_low < LUT2 ) {
                H0_D1 = SamplesFlakes( UVh, LUT1 + thetaH_low, mipLevel );
                if ( LUT1 + thetaH_high < LUT2 ) {
                    H1_D1 = SamplesFlakes( UVh, LUT1 + thetaH_high, mipLevel );
                }
            }
        }
    }
    
    // Bilinear interpolation
    float3  D0 = lerp( H0_D0, H1_D0, thetaH_weight );
    float3  D1 = lerp( H0_D1, H1_D1, thetaH_weight );
    return lerp( D0, D1, thetaD_weight );
}

#else

// Simplified code
float3  CarPaint_BTF( float thetaH, float thetaD, BSDFData BsdfData ) {
    float2  UV = BsdfData.flakesUV;
    float   mipLevel = BsdfData.flakesMipLevel;

    // thetaH sampling defines the angular sampling, i.e. angular flake lifetime
    float   binIndexH = _CarPaint_numThetaF * (2.0 * thetaH / PI) + 0.5;
    float   binIndexD = _CarPaint_numThetaI * (2.0 * thetaD / PI) + 0.5;

    // Bilinear interpolate indices and weights
    uint    thetaH_low = floor( binIndexH );
    uint    thetaD_low = floor( binIndexD );
    uint    thetaH_high = thetaH_low + 1;
    uint    thetaD_high = thetaD_low + 1;
    float   thetaH_weight = binIndexH - thetaH_low;
    float   thetaD_weight = binIndexD - thetaD_low;

    // Access flake texture - make sure to stay in the correct slices (no slip over)
    // @TODO: Store RGB value with all 3 integers? Single tap into LUT...
    uint    LUT0 = SampleFlakesLUT( min( _CarPaint_maxThetaI-1, thetaD_low ) );
    uint    LUT1 = SampleFlakesLUT( min( _CarPaint_maxThetaI-1, thetaD_high ) );
    uint    LUT2 = SampleFlakesLUT( min( _CarPaint_maxThetaI-1, thetaD_high+1 ) );

    float3  H0_D0 = SamplesFlakes( UV, min( LUT0 + thetaH_low, LUT1-1 ), mipLevel );
    float3  H1_D0 = SamplesFlakes( UV, min( LUT0 + thetaH_high, LUT1-1 ), mipLevel );
    float3  H0_D1 = SamplesFlakes( UV, min( LUT1 + thetaH_low, LUT2-1 ), mipLevel );
    float3  H1_D1 = SamplesFlakes( UV, min( LUT1 + thetaH_high, LUT2-1 ), mipLevel );
    
    // Bilinear interpolation
    float3  D0 = lerp( H0_D0, H1_D0, thetaH_weight );
    float3  D1 = lerp( H0_D1, H1_D1, thetaH_weight );
    return lerp( D0, D1, thetaD_weight );
}

#endif


// This function applies the BSDF. Assumes that NdotL is positive.
void	BSDF(   float3 viewWS, float3 lightWS, float NdotL, float3 positionWS, PreLightData preLightData, BSDFData BsdfData,
                out float3 diffuseLighting, out float3 specularLighting ) {

    // Compute half vector used by various components of the BSDF
    float3  H = normalize( viewWS + lightWS );
    float   LdotH = dot( H, lightWS );

    // Apply clear coat
    float3  clearCoatExtinction = 1.0;
    float3  clearCoatReflection = 0.0;
    if ( _flags & 2 ) {
        clearCoatReflection = (BsdfData.clearCoatColor / PI) * F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotH ); // Full reflection in mirror direction (we use expensive Fresnel here so the clear coat properly disappears when IOR -> 1)
        clearCoatExtinction = ComputeClearCoatExtinction( viewWS, lightWS, preLightData, BsdfData );
        #if RECOMPUTE_VECTORS_AFTER_REFRACTION
            if ( _flags & 4U ) {
                // Recompute half vector after refraction
                H = normalize( viewWS + lightWS );
                LdotH = saturate( dot( H, lightWS ) );
                preLightData.NdotV = dot( BsdfData.normalWS, viewWS );
            }
        #endif
    }

    // Compute remaining values AFTER potential clear coat refraction
    float   NdotV = ClampNdotV( preLightData.NdotV );
            NdotL = dot( BsdfData.normalWS, lightWS );
    float   NdotH = dot( BsdfData.normalWS, H );
    float   VdotH = LdotH;

    float   thetaH = acos( clamp( NdotH, -1, 1 ) );
    float   thetaD = acos( clamp( LdotH, -1, 1 ) );

    // Simple lambert
    float3  diffuseTerm = Lambert();

    // Apply multi-lobes Cook-Torrance
    float3  specularTerm = MultiLobesCookTorrance( NdotL, NdotV, NdotH, VdotH );

    // Apply BRDF color
    float3  BRDFColor = GetBRDFColor( thetaH, thetaD );
    diffuseTerm *= BRDFColor;
    specularTerm *= BRDFColor;

    // Apply flakes
    specularTerm += CarPaint_BTF( thetaH, thetaD, BsdfData );

    // We don't multiply by 'BsdfData.diffuseColor' here. It's done only once in PostEvaluateBSDF().
    diffuseLighting = clearCoatExtinction * diffuseTerm;
    specularLighting = clearCoatExtinction * specularTerm + clearCoatReflection;


#if 0   // DEBUG

#if 0
    // Debug BRDF Color texture
//    float2  UV = float2( 2.0 * thetaH / PI, 2.0 * thetaD / PI );
//thetaD = min( thetaH, thetaD );
    float2  UV = float2( 2.0 * thetaH / PI, 2.0 * thetaD / PI );

//UV = BsdfData.flakesUV;
    BRDFColor = _CarPaint_BRDFColorMap_Scale * SAMPLE_TEXTURE2D_LOD( _CarPaint_BRDFColorMap_sRGB, sampler_CarPaint_BRDFColorMap_sRGB, float2( UV.x, 1.0 - UV.y ), 0 ).xyz;

//BRDFColor = 2 * thetaH / PI;
//if ( UV.x + UV.y > 37.0 / 64.0 )
////if ( UV.y > 37.0 / 64.0 )
//    BRDFColor = _CarPaint_BRDFColorMap_Scale * float3( 1, 0, 1 );
////BRDFColor = float3( UV, 0 );

    diffuseLighting = BRDFColor;
#else
    // Debug flakes
    diffuseLighting = SamplesFlakes( BsdfData.flakesUV, _DEBUG_clearCoatIOR, 0 );
    diffuseLighting = CarPaint_BTF( thetaH, thetaD, BsdfData );

#endif

// Normalize so 1 is white
diffuseLighting /= BsdfData.diffuseColor;

#endif
}

#else

// This function applies the BSDF. Assumes that NdotL is positive.
void	BSDF(   float3 viewWS, float3 lightWS, float NdotL, float3 positionWS, PreLightData preLightData, BSDFData BsdfData,
                out float3 diffuseLighting, out float3 specularLighting ) {

    float  diffuseTerm = Lambert();

    // We don't multiply by 'BsdfData.diffuseColor' here. It's done only once in PostEvaluateBSDF().
    diffuseLighting = diffuseTerm;
    specularLighting = float3(0.0, 0.0, 0.0);
}

#endif

//-----------------------------------------------------------------------------
// EvaluateBSDF_Directional
//-----------------------------------------------------------------------------

DirectLighting  EvaluateBSDF_Directional(   LightLoopContext lightLoopContext,
                                            float3 viewWS, PositionInputs posInput, PreLightData preLightData,
                                            DirectionalLightData lightData, BSDFData BsdfData,
                                            BakeLightingData bakedLightingData ) {

    DirectLighting lighting;
    ZERO_INITIALIZE(DirectLighting, lighting);

    float3  normalWS = BsdfData.normalWS;
    float3  lightWS = -lightData.forward; // Lights point backward in Unity
    //float  NdotV = ClampNdotV(preLightData.NdotV);
    float   NdotL = dot(normalWS, lightWS);
    //float  LdotV = dot(lightWS, viewWS);

    // color and attenuation are outputted  by EvaluateLight:
    float3  color;
    float   attenuation = 0;
    EvaluateLight_Directional( lightLoopContext, posInput, lightData, bakedLightingData, normalWS, lightWS, color, attenuation );

    float intensity = max(0, attenuation * NdotL); // Warning: attenuation can be greater than 1 due to the inverse square attenuation (when position is close to light)

    // Note: We use NdotL here to early out, but in case of clear coat this is not correct. But we are ok with this
    UNITY_BRANCH if ( intensity > 0.0 ) {
        BSDF( viewWS, lightWS, NdotL, posInput.positionWS, preLightData, BsdfData, lighting.diffuse, lighting.specular );

        lighting.diffuse  *= intensity * lightData.diffuseScale;
        lighting.specular *= intensity * lightData.specularScale;
    }

    // NEWLITTODO: Mixed thickness, transmission

    // Save ALU by applying light and cookie colors only once.
    lighting.diffuse  *= color;
    lighting.specular *= color;

    #ifdef DEBUG_DISPLAY
        if ( _DebugLightingMode == DEBUGLIGHTINGMODE_LUX_METER ) {
            lighting.diffuse = color * intensity * lightData.diffuseScale;	// Only lighting, not BSDF
        }

//float   TIRIntensity;
//lighting.specular = -Refract( lightWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR, TIRIntensity );
//lighting.specular = dot( -Refract( lightWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR ), BsdfData.clearCoatNormalWS );
//lighting.specular = dot( -Refract( viewWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR ), BsdfData.clearCoatNormalWS );

//lighting.specular = (BsdfData.clearCoatIOR - 1.0) * 1;
//lighting.specular = 0.5 * (1.0 + BsdfData.clearCoatNormalWS);
//lighting.specular = 100.0 * (1.0 - dot( BsdfData.normalWS, BsdfData.clearCoatNormalWS) );


//lighting.diffuse = 0;
//lighting.specular = 0;

    #endif

    return lighting;
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_Punctual (supports spot, point and projector lights)
//-----------------------------------------------------------------------------

DirectLighting  EvaluateBSDF_Punctual(  LightLoopContext lightLoopContext,
                                        float3 viewWS, PositionInputs posInput,
                                        PreLightData preLightData, LightData lightData, BSDFData BsdfData, BakeLightingData bakedLightingData ) {
    DirectLighting	lighting;
    ZERO_INITIALIZE(DirectLighting, lighting);

    float3	lightToSample = posInput.positionWS - lightData.positionRWS;
    int		lightType     = lightData.lightType;

    float3 lightWS;
    float4 distances; // {d, d^2, 1/d, d_proj}
    distances.w = dot(lightToSample, lightData.forward);

    if ( lightType == GPULIGHTTYPE_PROJECTOR_BOX ) {
	    lightWS = -lightData.forward;
	    distances.xyz = 1; // No distance or angle attenuation
    } else {
	    float3 unL     = -lightToSample;
	    float  distSq  = dot(unL, unL);
	    float  distRcp = rsqrt(distSq);
	    float  dist    = distSq * distRcp;

	    lightWS = unL * distRcp;
	    distances.xyz = float3(dist, distSq, distRcp);
    }

    float3 normalWS     = BsdfData.normalWS;
    float  NdotV = ClampNdotV(preLightData.NdotV);
    float  NdotL = dot(normalWS, lightWS);
    float  LdotV = dot(lightWS, viewWS);

    // NEWLITTODO: mixedThickness, transmission

    float3 color;
    float attenuation;
    EvaluateLight_Punctual( lightLoopContext, posInput, lightData, bakedLightingData, normalWS, lightWS,
						    lightToSample, distances, color, attenuation);


    float intensity = max(0, attenuation * NdotL); // Warning: attenuation can be greater than 1 due to the inverse square attenuation (when position is close to light)

    // Note: We use NdotL here to early out, but in case of clear coat this is not correct. But we are ok with this
    UNITY_BRANCH if ( intensity > 0.0 ) {
        // Simulate a sphere light with this hack
        // Note that it is not correct with our pre-computation of PartLambdaV (mean if we disable the optimization we will not have the
        // same result) but we don't care as it is a hack anyway

        //NEWLITTODO: Do we want this hack in stacklit ? Yes we have area lights, but cheap and not much maintenance to leave it here.
        // For now no roughness anyways.

        //BsdfData.coatRoughness = max(BsdfData.coatRoughness, lightData.minRoughness);
        //BsdfData.roughnessT = max(BsdfData.roughnessT, lightData.minRoughness);
        //BsdfData.roughnessB = max(BsdfData.roughnessB, lightData.minRoughness);

        BSDF(viewWS, lightWS, NdotL, posInput.positionWS, preLightData, BsdfData, lighting.diffuse, lighting.specular);

        lighting.diffuse  *= intensity * lightData.diffuseScale;
        lighting.specular *= intensity * lightData.specularScale;
    }

    // Save ALU by applying light and cookie colors only once.
    lighting.diffuse  *= color;
    lighting.specular *= color;

    #ifdef DEBUG_DISPLAY
        if ( _DebugLightingMode == DEBUGLIGHTINGMODE_LUX_METER ) {
            lighting.diffuse = color * intensity * lightData.diffuseScale;		// Only lighting, not BSDF
        }
    #endif

	return lighting;
}

#include "AxFReference.hlsl"

//-----------------------------------------------------------------------------
// EvaluateBSDF_Line - Approximation with Linearly Transformed Cosines
//-----------------------------------------------------------------------------

DirectLighting  EvaluateBSDF_Line(  LightLoopContext lightLoopContext,
                                    float3 viewWS, PositionInputs posInput,
                                    PreLightData preLightData, LightData lightData, BSDFData BsdfData, BakeLightingData bakedLightingData ) {
    DirectLighting lighting;
    ZERO_INITIALIZE(DirectLighting, lighting);

    //NEWLITTODO

// Apply coating
//specularLighting += F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotN ) * Irradiance;

    return lighting;
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_Area - Approximation with Linearly Transformed Cosines
//-----------------------------------------------------------------------------

// #define ELLIPSOIDAL_ATTENUATION

// Computes the best light direction given an initial light direction
// The direction will be projected onto the area light's plane and clipped by the rectangle's bounds, the resulting normalized vector is returned
//
//  lightPositionLS, the rectangular area light's position in local space (i.e. relative to the point currently being lit)
//  lightWS, the light direction in world-space
//
float3  ComputeBestLightDirection( float3 lightPositionLS, float3 lightWS, LightData lightData ) {
//        float   t = dot( lightLS, lightData.forward ) / dot( reflectedViewWS, lightData.forward );                  // Distance until we intercept light plane following light direction
    float   halfWidth  = lightData.size.x * 0.5;
    float   halfHeight = lightData.size.y * 0.5;

    float   t = dot( lightPositionLS, lightData.forward ) / dot( lightWS, lightData.forward );                  // Distance until we intercept the light plane following light direction
    float3  hitPosLS = t * lightWS;                                                                             // Position of intersection with light plane
    float2  hitPosTS = float2( dot( hitPosLS, lightData.right ), dot( hitPosLS, lightData.up ) );               // Same but in tangent space
            hitPosTS = clamp( hitPosTS, float2( -halfWidth, -halfHeight ), float2( halfWidth, halfHeight ) );   // Clip to rectangle
    hitPosLS = lightWS + hitPosTS.x * lightData.right + hitPosTS.y * lightData.up;                              // Recompose clipped intersection
    return normalize( hitPosLS );                                                                               // Now use that direction as best light vector
}

DirectLighting  EvaluateBSDF_Rect(  LightLoopContext lightLoopContext,
                                    float3 viewWS, PositionInputs posInput,
                                    PreLightData preLightData, LightData lightData, BSDFData BsdfData, BakeLightingData bakedLightingData ) {
    DirectLighting lighting;
    ZERO_INITIALIZE(DirectLighting, lighting);

    float3  positionWS = posInput.positionWS;

#ifdef AXF_DISPLAY_REFERENCE_AREA
    IntegrateBSDF_AreaRef( viewWS, positionWS, preLightData, lightData, BsdfData,
                           lighting.diffuse, lighting.specular );
#else
    float3  unL = lightData.positionRWS - positionWS;
    if ( dot(lightData.forward, unL) >= 0.0001 ) {
        return lighting;    // The light is back-facing.
    }

    // Rotate the light direction into the light space.
    float3x3    lightToWorld = float3x3( lightData.right, lightData.up, -lightData.forward );
    unL = mul( unL, transpose(lightToWorld) );

    // TODO: This could be precomputed.
    float   halfWidth  = lightData.size.x * 0.5;
    float   halfHeight = lightData.size.y * 0.5;

    // Define the dimensions of the attenuation volume.
    // TODO: This could be precomputed.
    float   radius     = rsqrt( lightData.rangeAttenuationScale ); // rangeAttenuationScale is inverse Square Radius
    float3  invHalfDim = rcp( float3(   radius + halfWidth,
                                        radius + halfHeight,
                                        radius ) );

    // Compute the light attenuation.
    #ifdef ELLIPSOIDAL_ATTENUATION
        // The attenuation volume is an axis-aligned ellipsoid s.t.
        // r1 = (r + w / 2), r2 = (r + h / 2), r3 = r.
        float intensity = EllipsoidalDistanceAttenuation(unL, invHalfDim);
    #else
        // The attenuation volume is an axis-aligned box s.t.
        // hX = (r + w / 2), hY = (r + h / 2), hZ = r.
        float intensity = BoxDistanceAttenuation(unL, invHalfDim);
    #endif

    // Terminate if the shaded point is too far away.
    if ( intensity == 0.0 )
        return lighting;

    lightData.diffuseScale  *= intensity;
    lightData.specularScale *= intensity;

    // Translate the light s.t. the shaded point is at the origin of the coordinate system.
    float3  lightLS = lightData.positionRWS - positionWS;

    // TODO: some of this could be precomputed.
    float4x3    lightVerts;
                lightVerts[0] = lightLS + lightData.right *  halfWidth + lightData.up *  halfHeight;
                lightVerts[1] = lightLS + lightData.right *  halfWidth + lightData.up * -halfHeight;
                lightVerts[2] = lightLS + lightData.right * -halfWidth + lightData.up * -halfHeight;
                lightVerts[3] = lightLS + lightData.right * -halfWidth + lightData.up *  halfHeight;

    // Rotate the endpoints into tangent space
    lightVerts = mul( lightVerts, transpose(preLightData.orthoBasisViewNormal) );

    float   ltcValue;

    #if defined(_AXF_BRDF_TYPE_SVBRDF)

        // Evaluate the diffuse part
        // Polygon irradiance in the transformed configuration.
        ltcValue  = PolygonIrradiance( mul(lightVerts, preLightData.ltcTransformDiffuse) );
        ltcValue *= lightData.diffuseScale;
        lighting.diffuse = preLightData.ltcTransformDiffuse_Amplitude * ltcValue;
        

        // Evaluate the specular part
        // Polygon irradiance in the transformed configuration.
        ltcValue  = PolygonIrradiance( mul(lightVerts, preLightData.ltcTransformSpecular) );
        ltcValue *= lightData.specularScale;
        lighting.specular = BsdfData.specularColor * preLightData.ltcTransformSpecular_Amplitude * ltcValue;
        

    #elif defined(_AXF_BRDF_TYPE_CAR_PAINT)

        float   NdotV = ClampNdotV( preLightData.NdotV );

        // Use Lambert for diffuse
        ltcValue  = PolygonIrradiance( lightVerts );    // No transform: Lambert uses identity
        ltcValue *= lightData.diffuseScale;
        lighting.diffuse = ltcValue;

        // Evaluate multi-lobes Cook-Torrance
        // Each CT lobe samples the environment with the appropriate roughness
        for ( uint lobeIndex=0; lobeIndex < _CarPaint_lobesCount; lobeIndex++ ) {
            float   F0 = _CarPaint_CT_F0s[lobeIndex];
            float   coeff = _CarPaint_CT_coeffs[lobeIndex];
            float   spread = _CarPaint_CT_spreads[lobeIndex];

            float   perceptualRoughness = RoughnessToPerceptualRoughness( spread );

            float2      UV = LTCGetSamplingUV( NdotV, perceptualRoughness );
            float3x3    ltcTransformSpecular = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_COOK_TORRANCE );

            ltcValue  = PolygonIrradiance( mul( lightVerts, ltcTransformSpecular ) );

            // Apply FGD
            float3  specularFGD = 1;
            float   diffuseFGD, reflectivity;
            GetPreIntegratedFGDCookTorranceLambert( NdotV, perceptualRoughness, F0, specularFGD, diffuseFGD, reflectivity );

            lighting.specular += coeff * specularFGD * ltcValue;
        }
        lighting.specular *= lightData.specularScale;

        // Evaluate average BRDF response in specular direction
        float3  bestLightWS = ComputeBestLightDirection( lightLS, preLightData.IBLDominantDirectionWS, lightData );

        float3  H = normalize( viewWS + bestLightWS );
        float   NdotH = dot( BsdfData.normalWS, H );
        float   VdotH = dot( viewWS, H );

        float   thetaH = acos( clamp( NdotH, -1, 1 ) );
        float   thetaD = acos( clamp( VdotH, -1, 1 ) );

        lighting.diffuse *= GetBRDFColor( thetaH, thetaD );
        lighting.specular *= GetBRDFColor( thetaH, thetaD );

        // Sample flakes
        float2      UV = LTCGetSamplingUV( NdotV, FLAKES_PERCEPTUAL_ROUGHNESS );
        float3x3    ltcTransformFlakes = LTCSampleMatrix( UV, LTC_MATRIX_INDEX_GGX );

        ltcValue = PolygonIrradiance( mul( lightVerts, ltcTransformFlakes ) );
        ltcValue *= lightData.specularScale;

            // Apply FGD
        float3  flakes_FGD;
        float   specularReflectivity, dummyDiffuseFGD;
        GetPreIntegratedFGDGGXAndDisneyDiffuse( NdotV, FLAKES_PERCEPTUAL_ROUGHNESS, FLAKES_F0, flakes_FGD, dummyDiffuseFGD, specularReflectivity );

        lighting.specular += flakes_FGD * ltcValue * CarPaint_BTF( thetaH, thetaD, BsdfData );

    #endif


    // Evaluate the clear-coat
    if ( _flags & 2 ) {

        // Here we compute the reflected view direction and use it as optimal light direction
//        float3  reflectedViewWS = reflect( -viewWS, BsdfData.normalWS );
        float3  reflectedViewWS = preLightData.IBLDominantDirectionWS;

        // But we also clip it to the area light's rectangle...
        float3  bestLightWS = ComputeBestLightDirection( lightLS, reflectedViewWS, lightData );
//        float   t = dot( lightLS, lightData.forward ) / dot( reflectedViewWS, lightData.forward );                  // Distance until we intercept light plane following light direction
//        float3  hitPosLS = t * reflectedViewWS;                                                                     // Position of intersection with light plane
//        float2  hitPosTS = float2( dot( hitPosLS, lightData.right ), dot( hitPosLS, lightData.up ) );               // Same but in tangent space
//                hitPosTS = clamp( hitPosTS, float2( -halfWidth, -halfHeight ), float2( halfWidth, halfHeight ) );   // Clip to rectangle
//        hitPosLS = lightLS + hitPosTS.x * lightData.right + hitPosTS.y * lightData.up;                              // Recompose clipped intersection
//        float3  bestLightWS = normalize( hitPosLS );                                                                // Now use that direction as best light vector

        float3  H = normalize( viewWS + bestLightWS );
        float   LdotH = saturate( dot( bestLightWS, H ) );
        float   NdotH = saturate( dot( BsdfData.normalWS, H ) );

        float3  clearCoatReflection = (BsdfData.clearCoatColor / PI) * F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotH ); // Full reflection in mirror direction (we use expensive Fresnel here so the clear coat properly disappears when IOR -> 1)
        float3  clearCoatExtinction = ComputeClearCoatExtinction( viewWS, bestLightWS, preLightData, BsdfData );

        // Apply clear-coat extinction to existing lighting
        lighting.diffuse *= clearCoatExtinction;
        lighting.specular *= clearCoatExtinction;

        // Then add clear-coat contribution
        ltcValue = PolygonIrradiance( mul(lightVerts, preLightData.ltcTransformClearCoat) );
        ltcValue *= lightData.specularScale;
        lighting.specular += preLightData.ltcTransformClearCoat_Amplitude * ltcValue * clearCoatReflection;
    }

    // Save ALU by applying 'lightData.color' only once.
    lighting.diffuse *= lightData.color;
    lighting.specular *= lightData.color;

    #ifdef DEBUG_DISPLAY
        if (_DebugLightingMode == DEBUGLIGHTINGMODE_LUX_METER) {
            // Only lighting, not BSDF
            // Apply area light on lambert then multiply by PI to cancel Lambert
            lighting.diffuse = PolygonIrradiance(mul(lightVerts, k_identity3x3));
            lighting.diffuse *= PI * lightData.diffuseScale;
        }
    #endif



//*
float3  averageLightWS = normalize( lightLS );
float   TIRIntensity;
//lighting.specular = -Refract( averageLightWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR, TIRIntensity );
//lighting.specular = -Refract( viewWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR, TIRIntensity );
//lighting.specular = dot( -Refract( averageLightWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR ), BsdfData.clearCoatNormalWS );
//lighting.specular = dot( -Refract( viewWS, BsdfData.clearCoatNormalWS, BsdfData.clearCoatIOR ), BsdfData.clearCoatNormalWS );
//lighting.specular *= TIRIntensity;

//lighting.specular = ComputeClearCoatExtinction( viewWS, averageLightWS, preLightData, BsdfData );

//lighting.diffuse = 0;
lighting.specular = 0;
//*/


#endif // AXF_DISPLAY_REFERENCE_AREA


//lighting.diffuse = 0.0;
//lighting.specular = 0.0;


    return lighting;
}

DirectLighting  EvaluateBSDF_Area(  LightLoopContext lightLoopContext,
                                    float3 viewWS, PositionInputs posInput,
                                    PreLightData preLightData, LightData lightData,
                                    BSDFData BsdfData, BakeLightingData bakedLightingData ) {

    if (lightData.lightType == GPULIGHTTYPE_LINE) {
        return EvaluateBSDF_Line( lightLoopContext, viewWS, posInput, preLightData, lightData, BsdfData, bakedLightingData );
    } else {
        return EvaluateBSDF_Rect( lightLoopContext, viewWS, posInput, preLightData, lightData, BsdfData, bakedLightingData );
    }
}

//-----------------------------------------------------------------------------
// EvaluateBSDF_SSLighting for screen space lighting
// ----------------------------------------------------------------------------

IndirectLighting    EvaluateBSDF_SSLighting(    LightLoopContext lightLoopContext,
                                                float3 viewWS, PositionInputs posInput,
                                                PreLightData preLightData, BSDFData BsdfData,
                                                EnvLightData _envLightData,
                                                int _GPUImageBasedLightingType,
                                                inout float hierarchyWeight ) {

    IndirectLighting lighting;
    ZERO_INITIALIZE(IndirectLighting, lighting);

    //NEWLITTODO

// Apply coating
//specularLighting += F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotN ) * Irradiance;

    return lighting;
}


//-----------------------------------------------------------------------------
// EvaluateBSDF_Env
// ----------------------------------------------------------------------------

// _preIntegratedFGD and _CubemapLD are unique for each BRDF
IndirectLighting    EvaluateBSDF_Env(   LightLoopContext lightLoopContext,
                                        float3 viewWS, PositionInputs posInput,
                                        PreLightData preLightData, EnvLightData lightData, BSDFData BsdfData,
                                        int _influenceShapeType, int _GPUImageBasedLightingType,
                                        inout float hierarchyWeight ) {

    IndirectLighting lighting;
    ZERO_INITIALIZE(IndirectLighting, lighting);

    if ( _GPUImageBasedLightingType != GPUIMAGEBASEDLIGHTINGTYPE_REFLECTION )
        return lighting;    // We don't support transmission

    float3  positionWS = posInput.positionWS;
    float   weight = 1.0;

    float   NdotV = ClampNdotV( preLightData.NdotV );

    float3  environmentSamplingDirectionWS = preLightData.IBLDominantDirectionWS;

    #if defined(_AXF_BRDF_TYPE_SVBRDF)
        if ( (lightData.envIndex & 1) == ENVCACHETYPE_CUBEMAP ) {
            // When we are rough, we tend to see outward shifting of the reflection when at the boundary of the projection volume
            // Also it appear like more sharp. To avoid these artifact and at the same time get better match to reference we lerp to original unmodified reflection.
            // Formula is empirical.
            environmentSamplingDirectionWS = GetSpecularDominantDir( BsdfData.normalWS, environmentSamplingDirectionWS, preLightData.IBLPerceptualRoughness, NdotV );
            float   IBLRoughness = PerceptualRoughnessToRoughness( preLightData.IBLPerceptualRoughness );
            environmentSamplingDirectionWS = lerp( environmentSamplingDirectionWS, preLightData.IBLDominantDirectionWS, saturate(smoothstep(0, 1, IBLRoughness * IBLRoughness)) );
        }

        // Note: using _influenceShapeType and projectionShapeType instead of (lightData|proxyData).shapeType allow to make compiler optimization in case the type is know (like for sky)
        EvaluateLight_EnvIntersection( positionWS, BsdfData.normalWS, lightData, _influenceShapeType, environmentSamplingDirectionWS, weight );

        // TODO: We need to match the PerceptualRoughnessToMipmapLevel formula for planar, so we don't do this test (which is specific to our current lightloop)
        // Specific case for Texture2Ds, their convolution is a gaussian one and not a GGX one - So we use another roughness mip mapping.
        float   IBLMipLevel;
        if ( IsEnvIndexTexture2D( lightData.envIndex ) ) {
            // Empirical remapping
            IBLMipLevel = PositivePow( preLightData.IBLPerceptualRoughness, 0.8 ) * uint( max( 0, _ColorPyramidScale.z - 1 ) );
        } else {
            IBLMipLevel = PerceptualRoughnessToMipmapLevel( preLightData.IBLPerceptualRoughness );
        }

        //-----------------------------------------------------------------------------
        // Use FGD as factor for the env map
        float3  envBRDF = preLightData.specularFGD;

        // Sample the actual environment lighting
        float4  preLD = SampleEnv( lightLoopContext, lightData.envIndex, environmentSamplingDirectionWS, IBLMipLevel );
        weight *= preLD.w; // Used by planar reflection to discard pixel

        float3  envLighting = envBRDF * preLD.xyz;

    //-----------------------------------------------------------------------------
    #elif defined(_AXF_BRDF_TYPE_CAR_PAINT)
        // Evaluate average BRDF response in specular direction
// @TODO: Use FGD table! => Ward / Cook-Torrance both use Beckmann so it should be easy...

        float3  safeLightWS = environmentSamplingDirectionWS;
//        float3  safeLightWS = preLightData.IBLDominantDirectionWS;
//                safeLightWS += max( 1e-2, dot( safeLightWS, BsdfData.normalWS ) ) * BsdfData.normalWS;    // Move away from surface to avoid super grazing angles
//                safeLightWS = normalize( safeLightWS );

        float3  H = normalize( viewWS + safeLightWS );
        float   NdotL = saturate( dot( BsdfData.normalWS, safeLightWS ) );
        float   NdotH = dot( BsdfData.normalWS, H );
        float   VdotH = dot( viewWS, H );

        float   thetaH = acos( clamp( NdotH, -1, 1 ) );
        float   thetaD = acos( clamp( VdotH, -1, 1 ) );

        //-----------------------------------------------------------------------------
        #if USE_COOK_TORRANCE_MULTI_LOBES
            // Multi-lobes approach
            // Each CT lobe samples the environment with the appropriate roughness
            float3  envLighting = 0.0;
            float   sumWeights = 0.0;
            for ( uint lobeIndex=0; lobeIndex < _CarPaint_lobesCount; lobeIndex++ ) {
                float   F0 = _CarPaint_CT_F0s[lobeIndex];
                float   coeff = _CarPaint_CT_coeffs[lobeIndex];
                float   spread = _CarPaint_CT_spreads[lobeIndex];

                float   perceptualRoughness = RoughnessToPerceptualRoughness( spread );

                float   lobeIntensity = coeff * CT_D( NdotH, spread ) * CT_F( VdotH, F0 );
                float   lobeMipLevel = PerceptualRoughnessToMipmapLevel( perceptualRoughness );
                float4  preLD = SampleEnv( lightLoopContext, lightData.envIndex, environmentSamplingDirectionWS, lobeMipLevel );

                // Apply FGD
                float3  specularFGD = 1;
                float   diffuseFGD, reflectivity;
                GetPreIntegratedFGDCookTorranceLambert( NdotV, perceptualRoughness, F0, specularFGD, diffuseFGD, reflectivity );

                envLighting += lobeIntensity * specularFGD * preLD.xyz;
                sumWeights += preLD.w;
            }
            envLighting *= CT_G( NdotH, NdotV, NdotL, VdotH )  // Shadowing/Masking term
                         / (PI * max( 1e-3, NdotV * NdotL ));
            envLighting *= GetBRDFColor( thetaH, thetaD );

            // Sample flakes
            float   flakesMipLevel = 0;   // Flakes are supposed to be perfect mirrors...
            envLighting += CarPaint_BTF( thetaH, thetaD, BsdfData ) * SampleEnv( lightLoopContext, lightData.envIndex, environmentSamplingDirectionWS, flakesMipLevel ).xyz;

            envLighting *= NdotL;

            weight *= sumWeights / _CarPaint_lobesCount;

        #else
            // Single lobe approach
            // We computed an average mip level stored in preLightData.IBLPerceptualRoughness that we use for all CT lobes
            //
            float3  envBRDF = MultiLobesCookTorrance( NdotL, NdotV, NdotH, VdotH ); // Specular multi-lobes CT
                    envBRDF *= GetBRDFColor( thetaH, thetaD );
                    envBRDF += CarPaint_BTF( thetaH, thetaD, BsdfData );           // Sample flakes

            envBRDF *= NdotL;

            // Sample the actual environment lighting
            float4  preLD = SampleEnv( lightLoopContext, lightData.envIndex, environmentSamplingDirectionWS, IBLMipLevel );
            float3  envLighting = envBRDF * preLD.xyz;

            weight *= preLD.w; // Used by planar reflection to discard pixel

        #endif

    //-----------------------------------------------------------------------------
    #else

        float3  envLighting = 0;

    #endif

    //-----------------------------------------------------------------------------
    // Evaluate the Clear Coat component if needed
    if ( _flags & 2 ) {

        // Evaluate clear coat sampling direction
        float   unusedWeight = 0.0;
        float3  clearCoatSamplingDirectionWS = environmentSamplingDirectionWS;
        EvaluateLight_EnvIntersection( positionWS, BsdfData.clearCoatNormalWS, lightData, _influenceShapeType, clearCoatSamplingDirectionWS, unusedWeight );

        // Evaluate clear coat fresnel
        #if 1   // Use LdotH ==> Makes more sense! Stick to Cook-Torrance here...
            float3  H = normalize( viewWS + clearCoatSamplingDirectionWS );
            float   LdotH = saturate( dot( clearCoatSamplingDirectionWS, H ) );
            float3  clearCoatF = F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotH );
        #else   // Use LdotN
            float   LdotN = saturate( dot( clearCoatSamplingDirectionWS, BsdfData.clearCoatNormalWS ) );
            float3  clearCoatF = F_FresnelDieletricSafe( BsdfData.clearCoatIOR, LdotN );
        #endif

        // Attenuate environment lighting under the clear coat by the complement to the Fresnel term
        envLighting *= 1.0 - clearCoatF;

        // Then add the environment lighting reflected by the clear coat
        // We assume the BRDF here is perfect mirror so there's no masking/shadowing, only the Fresnel term * clearCoatColor/PI
        float4  preLD = SampleEnv( lightLoopContext, lightData.envIndex, clearCoatSamplingDirectionWS, 0.0 );
        envLighting += (BsdfData.clearCoatColor / PI) * clearCoatF * preLD.xyz;

        // Can't attenuate diffuse lighting here, may try to apply something on bakeLighting in PostEvaluateBSDF
    }

    UpdateLightingHierarchyWeights( hierarchyWeight, weight );
    envLighting *= weight * lightData.multiplier;

    lighting.specularReflected = envLighting;

    return lighting;
}

//-----------------------------------------------------------------------------
// PostEvaluateBSDF
// ----------------------------------------------------------------------------

void    PostEvaluateBSDF(   LightLoopContext lightLoopContext,
                            float3 viewWS, PositionInputs posInput,
                            PreLightData preLightData, BSDFData BsdfData, BakeLightingData bakedLightingData, AggregateLighting lighting,
                            out float3 diffuseLighting, out float3 specularLighting ) {

//    AmbientOcclusionFactor  AOFactor;
//    // Use GTAOMultiBounce approximation for ambient occlusion (allow to get a tint from the baseColor)
//#if 0
//    GetScreenSpaceAmbientOcclusion( posInput.positionSS, preLightData.NdotV, BsdfData.perceptualRoughness, 1.0, BsdfData.specularOcclusion, AOFactor );
//#else
//    GetScreenSpaceAmbientOcclusionMultibounce( posInput.positionSS, preLightData.NdotV, BsdfData.perceptualRoughness, 1.0, BsdfData.specularOcclusion, BsdfData.diffuseColor, BsdfData.fresnel0, AOFactor);
//#endif
//
//    // Add indirect diffuse + emissive (if any) - Ambient occlusion is multiply by emissive which is wrong but not a big deal
//    bakeDiffuseLighting                 *= AOFactor.indirectAmbientOcclusion;
//    lighting.indirect.specularReflected *= AOFactor.indirectSpecularOcclusion;
//    lighting.direct.diffuse             *= AOFactor.directAmbientOcclusion;


    // Apply the albedo to the direct diffuse lighting and that's about it.
    // diffuse lighting has already had the albedo applied in GetBakedDiffuseLighting().
    diffuseLighting = BsdfData.diffuseColor * lighting.direct.diffuse + bakedLightingData.bakeDiffuseLighting;
    specularLighting = lighting.direct.specular + lighting.indirect.specularReflected;

#if !defined(_AXF_BRDF_TYPE_SVBRDF) && !defined(_AXF_BRDF_TYPE_CAR_PAINT)
    diffuseLighting = 10 * float3( 1, 0.3, 0.01 );  // @TODO!
#endif

    #ifdef DEBUG_DISPLAY
// Make this work!
//        PostEvaluateBSDFDebugDisplay( aoFactor, bakeLightingData, lighting, bsdfData.diffuseColor, diffuseLighting, specularLighting );
        if ( _DebugLightingMode != 0 ) {
            bool keepSpecular = false;

            switch ( _DebugLightingMode ) {
                case DEBUGLIGHTINGMODE_SPECULAR_LIGHTING:
                    keepSpecular = true;
                    break;

                case DEBUGLIGHTINGMODE_LUX_METER:
                    diffuseLighting = lighting.direct.diffuse + bakedLightingData.bakeDiffuseLighting;
                    break;

                case DEBUGLIGHTINGMODE_INDIRECT_DIFFUSE_OCCLUSION:
//                  diffuseLighting = AOFactor.indirectAmbientOcclusion;
                    break;

                case DEBUGLIGHTINGMODE_INDIRECT_SPECULAR_OCCLUSION:
//                  diffuseLighting = AOFactor.indirectSpecularOcclusion;
                    break;

                case DEBUGLIGHTINGMODE_SCREEN_SPACE_TRACING_REFRACTION:
//                  if (_DebugLightingSubMode != DEBUGSCREENSPACETRACING_COLOR)
//                  	diffuseLighting = lighting.indirect.specularTransmitted;
//                  else
//                  	keepSpecular = true;
                    break;

                case DEBUGLIGHTINGMODE_SCREEN_SPACE_TRACING_REFLECTION:
//                  if (_DebugLightingSubMode != DEBUGSCREENSPACETRACING_COLOR)
//                      diffuseLighting = lighting.indirect.specularReflected;
//                  else
//                      keepSpecular = true;
                    break;
            }

            if ( !keepSpecular )
                specularLighting = float3(0.0, 0.0, 0.0); // Disable specular lighting

        } else if ( _DebugMipMapMode != DEBUGMIPMAPMODE_NONE ) {
            diffuseLighting = BsdfData.diffuseColor;
            specularLighting = float3(0.0, 0.0, 0.0); // Disable specular lighting
        }

//diffuseLighting = float3( 1, 0, 0 );

    #endif

// DEBUG: Make sure the flakes texture2DArray is correct!
//#if defined(_AXF_BRDF_TYPE_CAR_PAINT)
//diffuseLighting = 0;
////specularLighting = float3( 1, 0, 0 );
//specularLighting = SamplesFlakes( BsdfData.flakesUV, _DEBUG_clearCoatIOR, 0 );
//#endif

/*
// DEBUG DFG Texture
diffuseLighting = 0;
specularLighting = _PreIntegratedFGD_WardLambert.SampleLevel( s_linear_clamp_sampler, BsdfData.flakesUV, 0.0 ).xyz;
//specularLighting = _PreIntegratedFGD_CookTorranceLambert.SampleLevel( s_linear_clamp_sampler, BsdfData.flakesUV, 0.0 ).xyz;
//specularLighting = _PreIntegratedFGD_GGXDisneyDiffuse.SampleLevel( s_linear_clamp_sampler, BsdfData.flakesUV, 0.0 ).xyz;
//specularLighting = _PreIntegratedFGD_CharlieAndCloth.SampleLevel( s_linear_clamp_sampler, BsdfData.flakesUV, 0.0 ).xyz;
specularLighting.z = 0;
//specularLighting = float3( BsdfData.flakesUV, 0.0 );
//specularLighting = float3( 0.5, 0, 0 );
*/

/*
// DEBUG LTC Texture
diffuseLighting = 0;
//specularLighting = float3( BsdfData.flakesUV, 0.0 );
//specularLighting = float3( 1, 0.5, 0.25 );

float3x3    LTCMat;
float4      LTC0, LTC1, LTC2, LTC3, LTC4, LTC5, LTC6;
float2      UV;

float       roughness = BsdfData.flakesUV.x;
float       NdotV = BsdfData.flakesUV.y;

// Former tables used theta
UV.x = roughness;
UV.y = FastACosPos(NdotV) * INV_HALF_PI;

LTCMat = LTCSampleMatrix( UV, 0 ); LTC0 = LTCMat._m00_m11_m02_m20;
LTCMat = LTCSampleMatrix( UV, 1 ); LTC1 = LTCMat._m00_m11_m02_m20;

// New tables use cos(theta)
UV.y = sqrt( 1 - NdotV );
LTCMat = LTCSampleMatrix( UV, 2 ); LTC2 = LTCMat._m00_m11_m02_m20;
LTCMat = LTCSampleMatrix( UV, 3 ); LTC3 = LTCMat._m00_m11_m02_m20;
LTCMat = LTCSampleMatrix( UV, 4 ); LTC4 = LTCMat._m00_m11_m02_m20;
LTCMat = LTCSampleMatrix( UV, 5 ); LTC5 = LTCMat._m00_m11_m02_m20;
LTCMat = LTCSampleMatrix( UV, 6 ); LTC6 = LTCMat._m00_m11_m02_m20;

specularLighting = float3( abs(LTC0.xy), 0 );
//specularLighting = float3( abs(LTC2._m00_m11_m02_m20.xy), 0 );
specularLighting *= 0.01;

// Compare Disney
specularLighting = float3( abs(LTC1.xy) - 1, 0 );
//specularLighting = float3( abs(LTC3.xy) - 1, 0 );

float   V = LTC0.x;

//float   bias = 1;
//float   scale = 20.0;
float   bias = 0;
float   scale = 0.1;
specularLighting = V < bias ? (bias-V) * float3( 0, 0, 1 ) : (V-bias) * float3( 1, 0, 0 );
specularLighting *= scale;


//UV = BsdfData.flakesUV;
//specularLighting = SAMPLE_TEXTURE2D_ARRAY_LOD( _LtcData, s_linear_clamp_sampler, UV, 3, 0 ).xyz;
////specularLighting = float3( UV, 0 );

specularLighting  = pow( max( 0, specularLighting ), 2.2 );
*/
}

#endif // #ifdef HAS_LIGHTLOOP
