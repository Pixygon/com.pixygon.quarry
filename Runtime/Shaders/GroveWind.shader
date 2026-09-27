// Pixygon / Grove Wind — a URP lit surface that reads the wind Grove bakes
// into every plant (see GroveWind.hlsl for the four channels).
//
// Materials: the glTF PBR set as chisel exports it — base colour (with alpha
// for cutouts), a normal map, and the ORM map packed the glTF way (R occlusion,
// G roughness, B metallic). QuarryWorldImporter swaps glTFast's material for
// this one on any mesh that carries the wind channels and copies the maps over.
Shader "Pixygon/Grove Wind"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1.0
        _OrmMap ("Occlusion / Roughness / Metallic", 2D) = "white" {}
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        _Roughness ("Roughness", Range(0, 1)) = 0.9
        _Occlusion ("Occlusion Strength", Range(0, 1)) = 1.0
        [HDR] _EmissionColor ("Emission", Color) = (0, 0, 0, 1)
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Toggle(_ALPHATEST_ON)] _AlphaClip ("Alpha Clip", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2

        [Header(Wind)]
        _WindDirection ("Wind Direction (xz)", Vector) = (1, 0, 0.3, 0)
        _WindStrength ("Wind Strength", Range(0, 3)) = 1.0
        _WindSpeed ("Wind Speed", Range(0, 3)) = 1.0
        _TrunkSway ("Trunk Sway (m)", Range(0, 1)) = 0.15
        _BranchSway ("Branch Sway (m)", Range(0, 1)) = 0.25
        _Flutter ("Leaf Flutter", Range(0, 3)) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" "IgnoreProjector" = "True" }
        LOD 300
        Cull [_Cull]

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "GroveWind.hlsl"

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
        TEXTURE2D(_OrmMap);  SAMPLER(sampler_OrmMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _BumpScale;
            half   _Metallic;
            half   _Roughness;
            half   _Occlusion;
            half4  _EmissionColor;
            half   _Cutoff;
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            float4 tangentOS  : TANGENT;
            float2 uv         : TEXCOORD0;
            float2 sway       : TEXCOORD2;   // Grove: (trunk, branch)
            float2 leaf       : TEXCOORD3;   // Grove: (flutter, phase)
        };

        // The one place every pass gets its vertex from.
        float3 WindPositionWS(Attributes IN)
        {
            float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
            float3 originWS = float3(unity_ObjectToWorld._m03, unity_ObjectToWorld._m13, unity_ObjectToWorld._m23);
            return GroveWindDisplace(positionWS, originWS, IN.sway, IN.leaf);
        }

        half4 SampleBase(float2 uv)
        {
            return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
        }

        void ClipIfCut(half alpha)
        {
            #if defined(_ALPHATEST_ON)
            clip(alpha - _Cutoff);
            #endif
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3  normalWS   : TEXCOORD2;
                half4  tangentWS  : TEXCOORD3;   // xyz tangent, w sign
                float  fogFactor  : TEXCOORD4;
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 5);
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                float3 positionWS = WindPositionWS(IN);
                VertexNormalInputs n = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.positionWS = positionWS;
                OUT.positionCS = TransformWorldToHClip(positionWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = n.normalWS;
                OUT.tangentWS = half4(n.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
                OUT.fogFactor = ComputeFogFactor(OUT.positionCS.z);
                OUTPUT_SH(OUT.normalWS, OUT.vertexSH);
                return OUT;
            }

            half4 frag(Varyings IN, half facing : VFACE) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                half4 base = SampleBase(IN.uv);
                ClipIfCut(base.a);

                half3 orm = SAMPLE_TEXTURE2D(_OrmMap, sampler_OrmMap, IN.uv).rgb;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv), _BumpScale);

                // A leaf is one sheet: light its back with its back.
                half3 normalWS = normalize(IN.normalWS) * (facing < 0 ? -1.0 : 1.0);
                half3 bitangent = cross(normalWS, IN.tangentWS.xyz) * IN.tangentWS.w;
                half3x3 tbn = half3x3(IN.tangentWS.xyz, bitangent, normalWS);
                normalWS = normalize(mul(normalTS, tbn));

                SurfaceData s = (SurfaceData)0;
                s.albedo = base.rgb;
                s.alpha = base.a;
                s.metallic = orm.b * _Metallic;
                s.smoothness = 1.0 - saturate(orm.g * _Roughness);
                s.occlusion = lerp(1.0, orm.r, _Occlusion);
                s.normalTS = normalTS;
                s.emission = _EmissionColor.rgb;

                InputData d = (InputData)0;
                d.positionWS = IN.positionWS;
                d.positionCS = IN.positionCS;
                d.normalWS = normalWS;
                d.viewDirectionWS = SafeNormalize(GetWorldSpaceViewDir(IN.positionWS));
                d.shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                d.fogCoord = IN.fogFactor;
                d.bakedGI = SAMPLE_GI(IN.staticLightmapUV, IN.vertexSH, normalWS);
                d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                d.shadowMask = SAMPLE_SHADOWMASK(IN.staticLightmapUV);

                half4 color = UniversalFragmentPBR(d, s);
                color.rgb = MixFog(color.rgb, IN.fogFactor);
                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                // The shadow moves with the wood, or the tree stands in a still shadow.
                float3 positionWS = WindPositionWS(IN);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
                #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                OUT.positionCS = positionCS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                ClipIfCut(SampleBase(IN.uv).a);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile_instancing

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                OUT.positionCS = TransformWorldToHClip(WindPositionWS(IN));
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half frag(Varyings IN) : SV_Target
            {
                ClipIfCut(SampleBase(IN.uv).a);
                return IN.positionCS.z;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile_instancing

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                OUT.positionCS = TransformWorldToHClip(WindPositionWS(IN));
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return OUT;
            }

            half4 frag(Varyings IN, half facing : VFACE) : SV_Target
            {
                ClipIfCut(SampleBase(IN.uv).a);
                half3 n = normalize(IN.normalWS) * (facing < 0 ? -1.0 : 1.0);
                return half4(NormalizeNormalPerPixel(n), 0.0);
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
