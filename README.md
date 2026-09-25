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
