// After glTFast has imported a Quarry model, any mesh that carries Grove's
// wind channels (TEXCOORD_2/3 → uv3/uv4) gets the Grove Wind material in
// place of the one glTFast made — same maps, same colour, same cull — so a
// tree that came in from the Thread moves the moment it lands in a scene.
//
// It is a swap, not a rewrite: the glTFast material stays in the asset for
// anyone who wants a still tree back.
using UnityEngine;
using UnityEngine.Rendering;

namespace Pixygon.Quarry
{
    public static class GroveWindMaterials
    {
        const string ShaderName = "Pixygon/Grove Wind";

        /// Swap the material on every renderer under `root` whose mesh carries
        /// the wind. Returns how many were swapped.
        public static int Apply(GameObject root)
        {
            var shader = Shader.Find(ShaderName);
            if (shader == null)
            {
                Debug.LogWarning($"[Quarry] shader '{ShaderName}' not found — is the Runtime folder of com.pixygon.quarry in the project?");
                return 0;
            }
            int swapped = 0;
            foreach (var mf in root.GetComponentsInChildren<MeshFilter>(true))
            {
                var mesh = mf.sharedMesh;
                if (mesh == null || !mesh.HasVertexAttribute(VertexAttribute.TexCoord2)) continue;
                var r = mf.GetComponent<MeshRenderer>();
                if (r == null) continue;
                var mats = r.sharedMaterials;
                for (int i = 0; i < mats.Length; i++)
                {
                    if (mats[i] == null || mats[i].shader == shader) continue;
                    mats[i] = Windy(mats[i], shader);
                    swapped++;
                }
                r.sharedMaterials = mats;
            }
            return swapped;
        }

        /// A Grove Wind material carrying what the glTFast (or URP Lit) one had.
        static Material Windy(Material from, Shader shader)
        {
            var m = new Material(shader) { name = from.name + " (wind)" };
            // glTFast's URP materials name the glTF properties; URP Lit names its own.
            m.SetTexture("_BaseMap", Tex(from, "baseColorTexture", "_BaseMap", "_MainTex"));
            m.SetColor("_BaseColor", Col(from, Color.white, "baseColorFactor", "_BaseColor", "_Color"));
            var normal = Tex(from, "normalTexture", "_BumpMap");
            if (normal != null) m.SetTexture("_BumpMap", normal);
            m.SetFloat("_BumpScale", Num(from, 1f, "normalScale", "_BumpScale"));
            // glTF packs occlusion / roughness / metallic into one map, the way chisel exports it.
            var orm = Tex(from, "metallicRoughnessTexture", "occlusionTexture", "_MetallicGlossMap");
            if (orm != null) m.SetTexture("_OrmMap", orm);
            m.SetFloat("_Metallic", Num(from, 1f, "metallicFactor", "_Metallic"));
            m.SetFloat("_Roughness", Num(from, 1f, "roughnessFactor"));
            m.SetFloat("_Occlusion", Num(from, 1f, "occlusionStrength", "_OcclusionStrength"));
            m.SetColor("_EmissionColor", Col(from, Color.black, "emissiveFactor", "_EmissionColor"));
            var cull = Num(from, (float)CullMode.Back, "cull", "_Cull", "_CullMode");
            m.SetFloat("_Cull", cull);
            m.SetFloat("_Cutoff", Num(from, 0.5f, "alphaCutoff", "_Cutoff"));
            bool clip = from.IsKeywordEnabled("_ALPHATEST_ON") || from.renderQueue == (int)RenderQueue.AlphaTest;
            m.SetFloat("_AlphaClip", clip ? 1f : 0f);
            if (clip) m.EnableKeyword("_ALPHATEST_ON"); else m.DisableKeyword("_ALPHATEST_ON");
            m.renderQueue = from.renderQueue;
            return m;
        }

        static Texture Tex(Material m, params string[] names)
        {
            foreach (var n in names) if (m.HasProperty(n) && m.GetTexture(n) != null) return m.GetTexture(n);
            return null;
        }
        static Color Col(Material m, Color fallback, params string[] names)
        {
            foreach (var n in names) if (m.HasProperty(n)) return m.GetColor(n);
            return fallback;
        }
        static float Num(Material m, float fallback, params string[] names)
        {
            foreach (var n in names) if (m.HasProperty(n)) return m.GetFloat(n);
            return fallback;
        }
    }
}
