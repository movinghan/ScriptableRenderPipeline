using System.Collections.Generic;
using UnityEditor.Graphing;
using UnityEditor.ShaderGraph;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.HDPipeline;

namespace UnityEditor.Experimental.Rendering.HDPipeline
{
    public class HDLitSubShader : ILitSubShader
    {
        Pass m_PassGBuffer = new Pass()
        {
            Name = "GBuffer",
            LightMode = "GBuffer",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_GBUFFER",

            ExtraDefines = new List<string>()
            {
                "#pragma multi_compile _ DEBUG_DISPLAY",
                "#pragma multi_compile _ LIGHTMAP_ON",
                "#pragma multi_compile _ DIRLIGHTMAP_COMBINED",
                "#pragma multi_compile _ DYNAMICLIGHTMAP_ON",
                "#pragma multi_compile _ SHADOWS_SHADOWMASK",
                "#pragma multi_compile DECALS_OFF DECALS_3RT DECALS_4RT",
                "#pragma multi_compile _ LIGHT_LAYERS",
            },
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassGBuffer.hlsl\"",
            },
            RequiredFields = new List<string>()
            {
                "FragInputs.worldToTangent",
                "FragInputs.positionRWS",
                "FragInputs.texCoord1",
                "FragInputs.texCoord2"
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlbedoSlotId,
                LitMasterNode.NormalSlotId,
                LitMasterNode.BentNormalSlotId,
                LitMasterNode.TangentSlotId,
                LitMasterNode.SubsurfaceMaskSlotId,
                LitMasterNode.ThicknessSlotId,
                LitMasterNode.DiffusionProfileSlotId,
                LitMasterNode.IridescenceMaskSlotId,
                LitMasterNode.IridescenceThicknessSlotId,
                LitMasterNode.SpecularSlotId,
                LitMasterNode.CoatMaskSlotId,
                LitMasterNode.MetallicSlotId,
                LitMasterNode.EmissionSlotId,
                LitMasterNode.SmoothnessSlotId,
                LitMasterNode.OcclusionSlotId,
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId,
                LitMasterNode.AnisotropySlotId,
                LitMasterNode.SpecularAAScreenSpaceVarianceSlotId,
                LitMasterNode.SpecularAAThresholdSlotId,
                LitMasterNode.RefractionIndexSlotId,
                LitMasterNode.RefractionColorSlotId,
                LitMasterNode.RefractionDistanceSlotId,
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true,

            OnGeneratePassImpl = (IMasterNode node, ref Pass pass) =>
            {
                var masterNode = node as LitMasterNode;
                pass.StencilOverride = new List<string>()
                {
                    "// Stencil setup",
                    "Stencil",
                    "{",
                    "   WriteMask 7",
                        masterNode.RequiresSplitLighting() ? "   Ref  1" : "   Ref  2",
                    "   Comp Always",
                    "   Pass Replace",
                    "}"
                };

                pass.ExtraDefines.Remove("#define SHADERPASS_GBUFFER_BYPASS_ALPHA_TEST");
                if (masterNode.surfaceType == SurfaceType.Opaque && masterNode.alphaTest.isOn)
                {
                    pass.ExtraDefines.Add("#define SHADERPASS_GBUFFER_BYPASS_ALPHA_TEST");
                    pass.ZTestOverride = "ZTest Equal";
                }
                else
                {
                    pass.ZTestOverride = null;
                }
            }
        };

        Pass m_PassMETA = new Pass()
        {
            Name = "META",
            LightMode = "Meta",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_LIGHT_TRANSPORT",
            CullOverride = "Cull Off",
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassLightTransport.hlsl\"",
            },
            RequiredFields = new List<string>()
            {
                "AttributesMesh.normalOS",
                "AttributesMesh.tangentOS",     // Always present as we require it also in case of Variants lighting
                "AttributesMesh.uv0",
                "AttributesMesh.uv1",
                "AttributesMesh.color",
                "AttributesMesh.uv2",           // SHADERPASS_LIGHT_TRANSPORT always uses uv2
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlbedoSlotId,
                LitMasterNode.NormalSlotId,
                LitMasterNode.BentNormalSlotId,
                LitMasterNode.TangentSlotId,
                LitMasterNode.SubsurfaceMaskSlotId,
                LitMasterNode.ThicknessSlotId,
                LitMasterNode.DiffusionProfileSlotId,
                LitMasterNode.IridescenceMaskSlotId,
                LitMasterNode.IridescenceThicknessSlotId,
                LitMasterNode.SpecularSlotId,
                LitMasterNode.CoatMaskSlotId,
                LitMasterNode.MetallicSlotId,
                LitMasterNode.EmissionSlotId,
                LitMasterNode.SmoothnessSlotId,
                LitMasterNode.OcclusionSlotId,
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId,
                LitMasterNode.AnisotropySlotId,
                LitMasterNode.SpecularAAScreenSpaceVarianceSlotId,
                LitMasterNode.SpecularAAThresholdSlotId,
                LitMasterNode.RefractionIndexSlotId,
                LitMasterNode.RefractionColorSlotId,
                LitMasterNode.RefractionDistanceSlotId,
            },
            VertexShaderSlots = new List<int>()
            {
                //LitMasterNode.PositionSlotId
            },
            UseInPreview = true
        };

        Pass m_PassShadowCaster = new Pass()
        {
            Name = "ShadowCaster",
            LightMode = "ShadowCaster",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_SHADOWS",
            BlendOverride = "Blend One Zero",
            ZWriteOverride = "ZWrite On",
            ColorMaskOverride = "ColorMask 0",
            ExtraDefines = new List<string>()
            {
                "#define USE_LEGACY_UNITY_MATRIX_VARIABLES",
            },
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassDepthOnly.hlsl\"",
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true
        };

        Pass m_PassDepthOnly = new Pass()
        {
            Name = "DepthOnly",
            LightMode = "DepthOnly",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_DEPTH_ONLY",
            ExtraDefines = new List<string>()
            {
                "#pragma multi_compile _ WRITE_NORMAL_BUFFER",
            },
            ColorMaskOverride = "ColorMask 0",
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassDepthOnly.hlsl\"",
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true
        };

        Pass m_PassMotionVectors = new Pass()
        {
            Name = "Motion Vectors",
            LightMode = "MotionVectors",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_VELOCITY",
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassVelocity.hlsl\"",
            },
            RequiredFields = new List<string>()
            {
                "FragInputs.positionRWS",
            },
            StencilOverride = new List<string>()
            {
                "// If velocity pass (motion vectors) is enabled we tag the stencil so it don't perform CameraMotionVelocity",
                "Stencil",
                "{",
                "   WriteMask 128",         // [_StencilWriteMaskMV]        (int) HDRenderPipeline.StencilBitMask.ObjectVelocity   // this requires us to pull in the HD Pipeline assembly...
                "   Ref 128",               // [_StencilRefMV]
                "   Comp Always",
                "   Pass Replace",
                "}"
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true
        };

        Pass m_PassDistortion = new Pass()
        {
            Name = "Distortion",
            LightMode = "DistortionVectors",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_DISTORTION",
            BlendOverride = "Blend One One, One One",   // [_DistortionSrcBlend] [_DistortionDstBlend], [_DistortionBlurSrcBlend] [_DistortionBlurDstBlend]
            BlendOpOverride = "BlendOp Add, Add",       // Add, [_DistortionBlurBlendOp]
            ZTestOverride = "ZTest LEqual",             // [_ZTestModeDistortion]
            ZWriteOverride = "ZWrite Off",
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassDistortion.hlsl\"",
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId,
                LitMasterNode.DistortionSlotId,
                LitMasterNode.DistortionBlurSlotId,
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true,

            OnGeneratePassImpl = (IMasterNode node, ref Pass pass) =>
            {
                var masterNode = node as LitMasterNode;
                if (masterNode.distortionDepthTest.isOn)
                {
                    pass.ZTestOverride = "ZTest LEqual";
                }
                else
                {
                    pass.ZTestOverride = "ZTest Always";
                }
                if (masterNode.distortionMode == DistortionMode.Add)
                {
                    pass.BlendOverride = "Blend One One, One One";
                    pass.BlendOpOverride = "BlendOp Add, Max";
                }
                else if (masterNode.distortionMode == DistortionMode.Multiply)
                {
                    pass.BlendOverride = "Blend DstColor Zero, DstAlpha Zero";
                    pass.BlendOpOverride = "BlendOp Add, Add";
                }
            }
        };

        Pass m_PassTransparentDepthPrepass = new Pass()
        {
            Name = "TransparentDepthPrepass",
            LightMode = "TransparentDepthPrepass",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_DEPTH_ONLY",
            BlendOverride = "Blend One Zero",
            ZWriteOverride = "ZWrite On",
            ColorMaskOverride = "ColorMask 0",
            ExtraDefines = new List<string>()
            {
                "#define CUTOFF_TRANSPARENT_DEPTH_PREPASS",
            },
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassDepthOnly.hlsl\"",
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdDepthPrepassSlotId,
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true
        };

        Pass m_PassTransparentBackface = new Pass()
        {
            Name = "TransparentBackface",
            LightMode = "TransparentBackface",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_FORWARD",
            CullOverride = "Cull Front",
            ExtraDefines = new List<string>()
            {
                "#pragma multi_compile _ DEBUG_DISPLAY",
                "#pragma multi_compile _ LIGHTMAP_ON",
                "#pragma multi_compile _ DIRLIGHTMAP_COMBINED",
                "#pragma multi_compile _ DYNAMICLIGHTMAP_ON",
                "#pragma multi_compile _ SHADOWS_SHADOWMASK",
                "#pragma multi_compile DECALS_OFF DECALS_3RT DECALS_4RT",
                "#define LIGHTLOOP_TILE_PASS",
                "#pragma multi_compile USE_FPTL_LIGHTLIST USE_CLUSTERED_LIGHTLIST",
            },
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassForward.hlsl\"",
            },
            RequiredFields = new List<string>()
            {
                "FragInputs.worldToTangent",
                "FragInputs.positionRWS",
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlbedoSlotId,
                LitMasterNode.NormalSlotId,
                LitMasterNode.BentNormalSlotId,
                LitMasterNode.TangentSlotId,
                LitMasterNode.SubsurfaceMaskSlotId,
                LitMasterNode.ThicknessSlotId,
                LitMasterNode.DiffusionProfileSlotId,
                LitMasterNode.IridescenceMaskSlotId,
                LitMasterNode.IridescenceThicknessSlotId,
                LitMasterNode.SpecularSlotId,
                LitMasterNode.CoatMaskSlotId,
                LitMasterNode.MetallicSlotId,
                LitMasterNode.EmissionSlotId,
                LitMasterNode.SmoothnessSlotId,
                LitMasterNode.OcclusionSlotId,
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId,
                LitMasterNode.AnisotropySlotId,
                LitMasterNode.SpecularAAScreenSpaceVarianceSlotId,
                LitMasterNode.SpecularAAThresholdSlotId,
                LitMasterNode.RefractionIndexSlotId,
                LitMasterNode.RefractionColorSlotId,
                LitMasterNode.RefractionDistanceSlotId,
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true
        };

        Pass m_PassForward = new Pass()
        {
            Name = "Forward",
            LightMode = "Forward",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_FORWARD",
            ExtraDefines = new List<string>()
            {
                "#pragma multi_compile _ DEBUG_DISPLAY",
                "#pragma multi_compile _ LIGHTMAP_ON",
                "#pragma multi_compile _ DIRLIGHTMAP_COMBINED",
                "#pragma multi_compile _ DYNAMICLIGHTMAP_ON",
                "#pragma multi_compile _ SHADOWS_SHADOWMASK",
                "#pragma multi_compile DECALS_OFF DECALS_3RT DECALS_4RT",
                "#define LIGHTLOOP_TILE_PASS",
                "#pragma multi_compile USE_FPTL_LIGHTLIST USE_CLUSTERED_LIGHTLIST",
            },
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassForward.hlsl\"",
            },
            RequiredFields = new List<string>()
            {
                "FragInputs.worldToTangent",
                "FragInputs.positionRWS",
                "FragInputs.texCoord2" // lightmap
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlbedoSlotId,
                LitMasterNode.NormalSlotId,
                LitMasterNode.BentNormalSlotId,
                LitMasterNode.TangentSlotId,
                LitMasterNode.SubsurfaceMaskSlotId,
                LitMasterNode.ThicknessSlotId,
                LitMasterNode.DiffusionProfileSlotId,
                LitMasterNode.IridescenceMaskSlotId,
                LitMasterNode.IridescenceThicknessSlotId,
                LitMasterNode.SpecularSlotId,
                LitMasterNode.CoatMaskSlotId,
                LitMasterNode.MetallicSlotId,
                LitMasterNode.EmissionSlotId,
                LitMasterNode.SmoothnessSlotId,
                LitMasterNode.OcclusionSlotId,
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdSlotId,
                LitMasterNode.AnisotropySlotId,
                LitMasterNode.SpecularAAScreenSpaceVarianceSlotId,
                LitMasterNode.SpecularAAThresholdSlotId,
                LitMasterNode.RefractionIndexSlotId,
                LitMasterNode.RefractionColorSlotId,
                LitMasterNode.RefractionDistanceSlotId,
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true,

            OnGeneratePassImpl = (IMasterNode node, ref Pass pass) =>
            {
                var masterNode = node as LitMasterNode;
                pass.StencilOverride = new List<string>()
                {
                    "// Stencil setup",
                    "Stencil",
                    "{",
                    "   WriteMask 7",
                        masterNode.RequiresSplitLighting() ? "   Ref  1" : "   Ref  2",
                    "   Comp Always",
                    "   Pass Replace",
                    "}"
                };

                pass.ExtraDefines.Remove("#define SHADERPASS_FORWARD_BYPASS_ALPHA_TEST");
                if (masterNode.surfaceType == SurfaceType.Opaque && masterNode.alphaTest.isOn)
                {
                    pass.ExtraDefines.Add("#define SHADERPASS_FORWARD_BYPASS_ALPHA_TEST");
                    pass.ZTestOverride = "ZTest Equal";
                }
                else
                {
                    pass.ZTestOverride = null;
                }

                if (masterNode.surfaceType == SurfaceType.Transparent && masterNode.backThenFrontRendering.isOn)
                {
                    pass.CullOverride = "Cull Back";
                }
                else
                {
                    pass.CullOverride = null;
                }
            }
        };

        Pass m_PassTransparentDepthPostpass = new Pass()
        {
            Name = "TransparentDepthPostpass",
            LightMode = "TransparentDepthPostpass",
            TemplateName = "HDPBRPass.template",
            ShaderPassName = "SHADERPASS_DEPTH_ONLY",
            BlendOverride = "Blend One Zero",
            ZWriteOverride = "ZWrite On",
            ColorMaskOverride = "ColorMask 0",
            ExtraDefines = new List<string>()
            {
                "#define CUTOFF_TRANSPARENT_DEPTH_POSTPASS",
            },
            Includes = new List<string>()
            {
                "#include \"HDRP/ShaderPass/ShaderPassDepthOnly.hlsl\"",
            },
            PixelShaderSlots = new List<int>()
            {
                LitMasterNode.AlphaSlotId,
                LitMasterNode.AlphaThresholdDepthPostpassSlotId,
            },
            VertexShaderSlots = new List<int>()
            {
                LitMasterNode.PositionSlotId
            },
            UseInPreview = true
        };

        private static HashSet<string> GetActiveFieldsFromMasterNode(INode iMasterNode, Pass pass)
        {
            HashSet<string> activeFields = new HashSet<string>();

            LitMasterNode masterNode = iMasterNode as LitMasterNode;
            if (masterNode == null)
            {
                return activeFields;
            }

            if (masterNode.doubleSidedMode != DoubleSidedMode.Disabled)
            {
                activeFields.Add("DoubleSided");
                if (pass.ShaderPassName != "SHADERPASS_VELOCITY")   // HACK to get around lack of a good interpolator dependency system
                {                                                   // we need to be able to build interpolators using multiple input structs
                                                                    // also: should only require isFrontFace if Normals are required...
                    if (masterNode.doubleSidedMode == DoubleSidedMode.FlippedNormals)
                    {
                        activeFields.Add("DoubleSided.Flip");
                    }
                    else if (masterNode.doubleSidedMode == DoubleSidedMode.MirroredNormals)
                    {
                        activeFields.Add("DoubleSided.Mirror");
                    }
                        
                    activeFields.Add("FragInputs.isFrontFace");     // will need this for determining normal flip mode
                }
            }

            switch (masterNode.materialType)
            {
                case LitMasterNode.MaterialType.Anisotropy:
                    activeFields.Add("Material.Anisotropy");
                    break;
                case LitMasterNode.MaterialType.Iridescence:
                    activeFields.Add("Material.Iridescence");
                    break;
                case LitMasterNode.MaterialType.SpecularColor:
                    activeFields.Add("Material.SpecularColor");
                    break;
                case LitMasterNode.MaterialType.Standard:
                    activeFields.Add("Material.Standard");
                    break;
                case LitMasterNode.MaterialType.SubsurfaceScattering:
                    {
                        activeFields.Add("Material.SubsurfaceScattering");
                        if (masterNode.sssTransmission.isOn)
                        {
                            activeFields.Add("Material.Transmission");
                        }
                    }
                    break;
                case LitMasterNode.MaterialType.Translucent:
                    {
                        activeFields.Add("Material.Translucent");
                        activeFields.Add("Material.Transmission");
                    }
                    break;
                default:
                    UnityEngine.Debug.LogError("Unknown material type: " + masterNode.materialType);
                    break;
            }

            if (masterNode.alphaTest.isOn)
            {
                int count = 0;
                if (pass.PixelShaderUsesSlot(LitMasterNode.AlphaThresholdSlotId))
                { 
                    activeFields.Add("AlphaTest");
                    ++count;
                }
                if (pass.PixelShaderUsesSlot(LitMasterNode.AlphaThresholdDepthPrepassSlotId))
                {
                    activeFields.Add("AlphaTestPrepass");
                    ++count;
                }
                if (pass.PixelShaderUsesSlot(LitMasterNode.AlphaThresholdDepthPostpassSlotId))
                {
                    activeFields.Add("AlphaTestPostpass");
                    ++count;
                }
                UnityEngine.Debug.Assert(count == 1, "Alpha test value not set correctly");
            }

            if (masterNode.surfaceType != SurfaceType.Opaque)
            {
                activeFields.Add("SurfaceType.Transparent");

                if (masterNode.alphaMode == AlphaMode.Alpha)
                {
                    activeFields.Add("BlendMode.Alpha");
                }
                else if (masterNode.alphaMode == AlphaMode.Premultiply)
                {
                    activeFields.Add("BlendMode.Premultiply");
                }
                else if (masterNode.alphaMode == AlphaMode.Additive)
                {
                    activeFields.Add("BlendMode.Add");
                }

                if (masterNode.blendPreserveSpecular.isOn)
                {
                    activeFields.Add("BlendMode.PreserveSpecular");
                }

                if (masterNode.transparencyFog.isOn)
                {
                    activeFields.Add("AlphaFog");
                }
            }

            if (masterNode.receiveDecals.isOn)
            {
                activeFields.Add("Decals");
            }

            if (masterNode.specularAA.isOn && pass.PixelShaderUsesSlot(LitMasterNode.SpecularAAThresholdSlotId) && pass.PixelShaderUsesSlot(LitMasterNode.SpecularAAScreenSpaceVarianceSlotId))
            {
                activeFields.Add("Specular.AA");
            }

            if (masterNode.energyConservingSpecular.isOn)
            {
                activeFields.Add("Specular.EnergyConserving");
            }

            if (masterNode.albedoAffectsEmissive.isOn)
            {
                activeFields.Add("AlbedoAffectsEmissive");
            }

            if (masterNode.HasRefraction())
            {
                activeFields.Add("Refraction");
                switch (masterNode.refractionModel)
                {
                    case ScreenSpaceLighting.RefractionModel.Plane:
                        activeFields.Add("RefractionPlane");
                        break;

                    case ScreenSpaceLighting.RefractionModel.Sphere:
                        activeFields.Add("RefractionSphere");
                        break;

                    default:
                        UnityEngine.Debug.LogError("Unknown refraction model: " + masterNode.refractionModel);
                        break;
                }

                switch (masterNode.projectionModel)
                {
                    case ScreenSpaceLighting.PickableProjectionModel.Proxy:
                        activeFields.Add("RefractionSSRayProxy");
                        break;

                    case ScreenSpaceLighting.PickableProjectionModel.HiZ:
                        activeFields.Add("RefractionSSRayHiZ");
                        break;

                    default:
                        UnityEngine.Debug.LogError("Unknown projection model: " + masterNode.projectionModel);
                        break;
                }
            }

            if (masterNode.IsSlotConnected(LitMasterNode.BentNormalSlotId) && pass.PixelShaderUsesSlot(LitMasterNode.BentNormalSlotId))
            {
                activeFields.Add("BentNormal");
            }

            if (masterNode.IsSlotConnected(LitMasterNode.TangentSlotId) && pass.PixelShaderUsesSlot(LitMasterNode.TangentSlotId))
            {
                activeFields.Add("Tangent");
            }

            switch (masterNode.specularOcclusionMode)
            {
                case SpecularOcclusionMode.Off:
                    break;
                case SpecularOcclusionMode.On:
                    activeFields.Add("SpecularOcclusion");
                    break;
                case SpecularOcclusionMode.OnUseBentNormal:
                    activeFields.Add("BentNormalSpecularOcclusion");
                    break;
                default:
                    break;
            }

            if (pass.PixelShaderUsesSlot(LitMasterNode.OcclusionSlotId))
            {
                var occlusionSlot = masterNode.FindSlot<Vector1MaterialSlot>(LitMasterNode.OcclusionSlotId);
                if (occlusionSlot.value != occlusionSlot.defaultValue)
                {
                    activeFields.Add("Occlusion");
                }
            }

            return activeFields;
        }

        private static bool GenerateShaderPassLit(LitMasterNode masterNode, Pass pass, GenerationMode mode, ShaderGenerator result, List<string> sourceAssetDependencyPaths)
        {
            if (mode == GenerationMode.ForReals || pass.UseInPreview)
            {
                SurfaceMaterialOptions materialOptions = HDSubShaderUtilities.BuildMaterialOptions(masterNode.surfaceType, masterNode.alphaMode, masterNode.doubleSidedMode != DoubleSidedMode.Disabled, masterNode.HasRefraction());

                pass.OnGeneratePass(masterNode);

                // apply master node options to active fields
                HashSet<string> activeFields = GetActiveFieldsFromMasterNode(masterNode, pass);

                // use standard shader pass generation
                bool vertexActive = masterNode.IsSlotConnected(LitMasterNode.PositionSlotId);
                return HDSubShaderUtilities.GenerateShaderPass(masterNode, pass, mode, materialOptions, activeFields, result, sourceAssetDependencyPaths, vertexActive);
            }
            else
            {
                return false;
            }
        }

        public string GetSubshader(IMasterNode iMasterNode, GenerationMode mode, List<string> sourceAssetDependencyPaths = null)
        {
            if (sourceAssetDependencyPaths != null)
            {
                // HDLitSubShader.cs
                sourceAssetDependencyPaths.Add(AssetDatabase.GUIDToAssetPath("4f0bba2c9470edc4c8873e124ec9ecb6"));
                // HDSubShaderUtilities.cs
                sourceAssetDependencyPaths.Add(AssetDatabase.GUIDToAssetPath("713ced4e6eef4a44799a4dd59041484b"));
            }

            var masterNode = iMasterNode as LitMasterNode;

            var subShader = new ShaderGenerator();
            subShader.AddShaderChunk("SubShader", true);
            subShader.AddShaderChunk("{", true);
            subShader.Indent();
            {
                SurfaceMaterialTags materialTags = HDSubShaderUtilities.BuildMaterialTags(masterNode.surfaceType, masterNode.alphaTest.isOn, masterNode.drawBeforeRefraction.isOn, masterNode.sortPriority);

                // Add tags at the SubShader level
                {
                    var tagsVisitor = new ShaderStringBuilder();
                    materialTags.GetTags(tagsVisitor);
                    subShader.AddShaderChunk(tagsVisitor.ToString(), false);
                }

                // generate the necessary shader passes
                bool opaque = (masterNode.surfaceType == SurfaceType.Opaque);
                bool transparent = !opaque;
                bool velocity = masterNode.motionVectors.isOn;

                bool distortionActive = transparent && masterNode.distortion.isOn;
                bool transparentBackfaceActive = transparent && masterNode.backThenFrontRendering.isOn;
                bool transparentDepthPrepassActive = transparent && masterNode.alphaTest.isOn && masterNode.alphaTestDepthPrepass.isOn;
                bool transparentDepthPostpassActive = transparent && masterNode.alphaTest.isOn && masterNode.alphaTestDepthPostpass.isOn;

                GenerateShaderPassLit(masterNode, m_PassGBuffer, mode, subShader, sourceAssetDependencyPaths);
                GenerateShaderPassLit(masterNode, m_PassMETA, mode, subShader, sourceAssetDependencyPaths);
                GenerateShaderPassLit(masterNode, m_PassShadowCaster, mode, subShader, sourceAssetDependencyPaths);

                if (opaque)
                {
                    GenerateShaderPassLit(masterNode, m_PassDepthOnly, mode, subShader, sourceAssetDependencyPaths);
                }

                if (velocity)
                {
                    GenerateShaderPassLit(masterNode, m_PassMotionVectors, mode, subShader, sourceAssetDependencyPaths);
                }

                if (distortionActive)
                {
                    GenerateShaderPassLit(masterNode, m_PassDistortion, mode, subShader, sourceAssetDependencyPaths);
                }

                if (transparentBackfaceActive)
                {
                    GenerateShaderPassLit(masterNode, m_PassTransparentBackface, mode, subShader, sourceAssetDependencyPaths);
                }

                GenerateShaderPassLit(masterNode, m_PassForward, mode, subShader, sourceAssetDependencyPaths);

                if (transparentDepthPrepassActive)
                {
                    GenerateShaderPassLit(masterNode, m_PassTransparentDepthPrepass, mode, subShader, sourceAssetDependencyPaths);
                }

                if (transparentDepthPostpassActive)
                {
                    GenerateShaderPassLit(masterNode, m_PassTransparentDepthPostpass, mode, subShader, sourceAssetDependencyPaths);
                }
            }
            subShader.Deindent();
            subShader.AddShaderChunk("}", true);
            subShader.AddShaderChunk(@"CustomEditor ""UnityEditor.ShaderGraph.HDLitGUI""");

            return subShader.GetShaderString(0);
        }

        public bool IsPipelineCompatible(RenderPipelineAsset renderPipelineAsset)
        {
            return renderPipelineAsset is HDRenderPipelineAsset;
        }
    }
}
