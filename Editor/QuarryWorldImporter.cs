// Pixygon — Quarry world importer.
//
// Brings a Thread World Manifest (the world.json that `thread level` writes)
// into a Unity scene. The manifest is the bill of materials: `assets` (glb
// files, relative to the manifest or absolute Quarry URLs), `prefabs` (a mesh
// reference plus a PBR material recipe) and `placements` (prefab + transform).
// This importer copies each glb into Assets/Art/Quarry/, lets glTFast import
// it, then instantiates every placement under one root object.
//
// Provenance is the point: every imported object carries a QuarryProvenance
// component naming the manifest, the asset uri and the Codex slug it came
// from, so nothing in the scene is ever "a mesh from somewhere". The founder's
// rule for the whole pipeline (2026-09-25): assets live in one shared place
// (the Quarry) and stay traceable to the canon that produced them.
//
// Static geometry only. Animation is a separate track (avatar/actor).
#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using GLTFast;
using UnityEditor;
using UnityEngine;

namespace Pixygon.Quarry
{
    // ── Manifest shapes (only the fields this importer reads) ───────────────
#pragma warning disable 0649 // filled by JsonUtility
    [Serializable] class WorldAsset { public string id; public string uri; public string kind; }
    [Serializable] class WorldMesh { public string asset; public string builtin; }
    [Serializable] class WorldMaterial { public float[] base_color; public float metallic; public float roughness; public float emissive; }
    [Serializable] class WorldPrefab { public string id; public WorldMesh mesh; public WorldMaterial material; }
    [Serializable] class WorldPlacement { public string prefab; public string name; public float[] position; public float[] rotation; public float[] scale; public string codex; }
    [Serializable] class WorldLight { public float[] at; public float warm; public float range; public float intensity; public bool fixture; }
    [Serializable] class WorldManifest
    {
        public string thread; public string world;
        public WorldAsset[] assets; public WorldPrefab[] prefabs; public WorldPlacement[] placements; public WorldLight[] lights;
    }
#pragma warning restore 0649

    public static class QuarryWorldImporter
    {
        const string ImportRoot = "Assets/Art/Quarry";

        [MenuItem("Pixygon/Quarry/Import world.json…")]
        public static async void ImportFromDialog()
        {
            var path = EditorUtility.OpenFilePanel("Thread world manifest", "", "json");
            if (string.IsNullOrEmpty(path)) return;
            try { await Import(path); }
            catch (Exception e) { Debug.LogError($"[Quarry] import failed: {e.Message}\n{e}"); }
        }

        /// <summary>Import a manifest from a local path. Returns the scene root.</summary>
        public static async Task<GameObject> Import(string manifestPath)
        {
            var json = File.ReadAllText(manifestPath);
            var manifest = JsonUtility.FromJson<WorldManifest>(json);
            if (manifest == null || manifest.placements == null) throw new Exception("not a World Manifest (no placements)");
            var manifestDir = Path.GetDirectoryName(manifestPath) ?? "";
            var worldName = string.IsNullOrEmpty(manifest.world) ? Path.GetFileNameWithoutExtension(manifestPath) : manifest.world;
            var stamp = DateTime.UtcNow.ToString("o");

            // 1. Assets: copy every glb next to the project so it is an ordinary
            //    imported asset (glTFast's editor importer handles the file), and
            //    remember where each asset id now lives.
            Directory.CreateDirectory(ImportRoot);
            var assetPath = new Dictionary<string, string>();
            foreach (var a in manifest.assets ?? Array.Empty<WorldAsset>())
            {
                if (a.kind != null && a.kind != "gltf") continue;
                var src = a.uri.StartsWith("http", StringComparison.OrdinalIgnoreCase) ? a.uri : Path.Combine(manifestDir, a.uri);
                var dest = Path.Combine(ImportRoot, Path.GetFileName(a.uri));
                if (src.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                {
                    using var http = new System.Net.Http.HttpClient();
                    var bytes = await http.GetByteArrayAsync(src);
                    File.WriteAllBytes(dest, bytes);
                }
                else if (File.Exists(src)) File.Copy(src, dest, true);
                else { Debug.LogWarning($"[Quarry] asset missing: {src}"); continue; }
                assetPath[a.id] = dest.Replace('\\', '/');
            }
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

            // 2. Prefabs: an asset-backed prefab is the imported glb's main object;
            //    a builtin prefab (floor slab, cylinder) is a primitive wearing the
            //    manifest's flat PBR values. Recipe textures are already baked into
            //    the glbs; the builtin only carries what the manifest states.
            var prefabSource = new Dictionary<string, GameObject>();
            foreach (var p in manifest.prefabs ?? Array.Empty<WorldPrefab>())
            {
                GameObject go = null;
                if (p.mesh != null && !string.IsNullOrEmpty(p.mesh.asset) && assetPath.TryGetValue(p.mesh.asset, out var ap))
                {
                    go = AssetDatabase.LoadAssetAtPath<GameObject>(ap);
                    if (go == null) Debug.LogWarning($"[Quarry] glTFast produced no prefab for {ap} — is com.unity.cloud.gltfast installed?");
                }
                else if (p.mesh != null && !string.IsNullOrEmpty(p.mesh.builtin))
                {
                    go = BuiltinTemplate(p);
                }
                if (go != null) prefabSource[p.id] = go;
            }

            // 3. Placements under one root, provenance on every object.
            var root = new GameObject($"Quarry — {worldName}");
            Undo.RegisterCreatedObjectUndo(root, "Import Quarry world");
            int placed = 0, missing = 0;
            foreach (var pl in manifest.placements)
            {
                if (!prefabSource.TryGetValue(pl.prefab, out var src)) { missing++; continue; }
                var isAsset = AssetDatabase.Contains(src);
                var inst = isAsset ? (GameObject)PrefabUtility.InstantiatePrefab(src) : UnityEngine.Object.Instantiate(src);
                inst.name = string.IsNullOrEmpty(pl.name) ? pl.prefab : pl.name;
                inst.transform.SetParent(root.transform, false);
                inst.transform.localPosition = V3(pl.position, Vector3.zero);
                inst.transform.localRotation = Q(pl.rotation);
                inst.transform.localScale = V3(pl.scale, Vector3.one);
                var prov = inst.AddComponent<QuarryProvenance>();
                prov.manifest = manifestPath;
                prov.prefabId = pl.prefab;
                prov.codexSlug = pl.codex;
                prov.importedAt = stamp;
                if (TryAssetUri(manifest, pl.prefab, out var uri)) { prov.assetUri = uri; prov.design = DesignFromUri(uri); }
                placed++;
            }
            // Builtin templates were scene objects used only as sources.
            foreach (var kv in prefabSource) if (!AssetDatabase.Contains(kv.Value)) UnityEngine.Object.DestroyImmediate(kv.Value);

            // 4. Lights, as the manifest states them (warm = tint toward amber).
            foreach (var l in manifest.lights ?? Array.Empty<WorldLight>())
            {
                var lgo = new GameObject(l.fixture ? "light-fixture" : "light");
                lgo.transform.SetParent(root.transform, false);
                lgo.transform.localPosition = V3(l.at, Vector3.zero);
                var light = lgo.AddComponent<Light>();
                light.type = LightType.Point;
                light.range = l.range > 0 ? l.range : 8f;
                light.intensity = l.intensity > 0 ? l.intensity : 1f;
                light.color = Color.Lerp(Color.white, new Color(1f, 0.72f, 0.42f), Mathf.Clamp01(l.warm));
            }

            Debug.Log($"[Quarry] {worldName}: {placed} placed, {missing} placements had no prefab, {assetPath.Count} glb(s) in {ImportRoot}");
            Selection.activeGameObject = root;
            // Anything that came in with Grove's wind channels moves from now on.
            var windy = GroveWindMaterials.Apply(root);
            if (windy > 0) Debug.Log($"[Quarry] Grove Wind on {windy} material(s)");
            return root;
        }

        static GameObject BuiltinTemplate(WorldPrefab p)
        {
            var prim = p.mesh.builtin switch
            {
                "cylinder" => PrimitiveType.Cylinder,
                "sphere" => PrimitiveType.Sphere,
                "capsule" => PrimitiveType.Capsule,
                "plane" => PrimitiveType.Plane,
                "quad" => PrimitiveType.Quad,
                _ => PrimitiveType.Cube,
            };
            var go = GameObject.CreatePrimitive(prim);
            go.name = $"builtin-{p.mesh.builtin}";
            // Unity's cylinder is 2 units tall; the Thread's is 1. Match the manifest's unit.
            if (prim == PrimitiveType.Cylinder) go.transform.localScale = new Vector3(1f, 0.5f, 1f);
            var r = go.GetComponent<Renderer>();
            if (r != null && p.material != null)
            {
                var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
                var m = new Material(shader);
                if (p.material.base_color != null && p.material.base_color.Length >= 3)
                    m.color = new Color(p.material.base_color[0], p.material.base_color[1], p.material.base_color[2], p.material.base_color.Length > 3 ? p.material.base_color[3] : 1f);
                if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", p.material.metallic);
                if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", 1f - Mathf.Clamp01(p.material.roughness));
                r.sharedMaterial = m;
            }
            return go;
        }

        static bool TryAssetUri(WorldManifest m, string prefabId, out string uri)
        {
            uri = null;
            foreach (var p in m.prefabs ?? Array.Empty<WorldPrefab>())
            {
                if (p.id != prefabId || p.mesh == null || string.IsNullOrEmpty(p.mesh.asset)) continue;
                foreach (var a in m.assets ?? Array.Empty<WorldAsset>()) if (a.id == p.mesh.asset) { uri = a.uri; return true; }
            }
            return false;
        }

        /// <summary>A Quarry URL ends in the design hash; a local commission does not carry one.</summary>
        static string DesignFromUri(string uri)
        {
            if (string.IsNullOrEmpty(uri) || !uri.Contains("/models/")) return null;
            var file = Path.GetFileNameWithoutExtension(uri);
            return file.Length == 16 ? file : null;
        }

        static Vector3 V3(float[] v, Vector3 fallback) => v != null && v.Length >= 3 ? new Vector3(v[0], v[1], v[2]) : fallback;
        static Quaternion Q(float[] v) => v != null && v.Length >= 4 ? new Quaternion(v[0], v[1], v[2], v[3]) : Quaternion.identity;
    }
}
#endif
