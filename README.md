# Pixygon — Quarry (Unity)

Bring what the Thread's tools make into Unity, and keep every object traceable to the canon that produced it.

The pipeline this package closes (2026-09-25):

```
Codex entry (style lock in attributes, concept images in gallery)
   → recipe (chisel model JSON / Weft model_lib)
   → thread model … -o x.glb --preview        one model, PBR-baked
   → thread level --figure … -o world.json     a place: assets + prefabs + placements
   → Quarry (quarry.pixygon.io)                the shared, re-derivable store
   → this package                              into a Unity scene, with provenance
```

## Install

`Packages/manifest.json`:

```json
"com.pixygon.quarry": "https://github.com/Pixygon/com.pixygon.quarry.git",
"com.unity.cloud.gltfast": "6.19.0"
```

## Use

**Pixygon → Quarry → Import world.json…** and pick the manifest `thread level` wrote. The importer

1. copies each glb in `assets` into `Assets/Art/Quarry/` (or downloads it when the uri is a Quarry URL) and lets glTFast import it;
2. turns each `prefab` into a source: the imported glb's main object, or a Unity primitive wearing the manifest's flat PBR values for `builtin` meshes;
3. instantiates every `placement` under one root named after the world, with position, rotation (quaternion) and scale from the manifest;
4. places the manifest's `lights` as point lights, tinted toward amber by `warm`;
5. adds a `QuarryProvenance` to every placed object: manifest path, asset uri, prefab id, Codex slug, Quarry design hash.

Static geometry only. Animation is the avatar/actor system's job.

## Why provenance

An asset that cannot say where it came from cannot be regenerated, restyled or replaced consistently. The Quarry derives every model from a recipe and names it by the recipe's hash; this package carries that name into the scene so a Unity object and a Codex entry can always find each other.

## Wind

Every plant grown by the Thread's Grove carries its wind in four vertex
channels — it knows its own hierarchy, so the shader does not have to guess:

| channel | meaning |
| --- | --- |
| `TEXCOORD_2.x` (uv3.x) | trunk sway: 0 at the ground, 1 at the top of the trunk, inherited out along every limb |
| `TEXCOORD_2.y` (uv3.y) | branch sway: 0 along the trunk, climbing each generation to 1 at the outermost twigs |
| `TEXCOORD_3.x` (uv4.x) | leaf flutter: the tremble only a leaf has; 0 on wood |
| `TEXCOORD_3.y` (uv4.y) | phase, 0..1 per branch, so no two limbs march in step |
| `COLOR_0.a` | rigidity (1 − sway): Infinite's channel, kept for it, not read here |

`Runtime/Shaders/GroveWind.shader` (`Pixygon/Grove Wind`) is a URP lit surface
that reads them — one slow whole-tree lean, a limb's own swing at its own
phase, a leaf's fast tremble, all in world space off one gust field so a stand
ripples instead of nodding together — in every pass, shadows included.
Material properties: the glTF PBR set as chisel exports it (base colour with
alpha, normal map, ORM map packed R occlusion / G roughness / B metallic) and
the wind (`_WindDirection`, `_WindStrength`, `_WindSpeed`, `_TrunkSway`,
`_BranchSway`, `_Flutter`).

glTFast imports up to eight UV sets (its own shaders read two; this one
reads four), so nothing about the import has to change.

After an import, `GroveWindMaterials.Apply(root)` swaps the Grove Wind material
onto every mesh that carries the channels, copying the maps from glTFast's
material; the importer does this itself. A mesh without the channels reads
zeros and stands still, which is the right default for everything that
predates the wind. `TEXCOORD_1` on the same meshes is the branch id
(`id = (uint)uv2.x | ((uint)uv2.y << 16)`), for hit-testing a swing — see
`thread-engine/crates/grove`.
