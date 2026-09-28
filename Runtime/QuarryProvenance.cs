// What an imported object knows about where it came from. Lives in the
// Runtime assembly, in a file of its own name, so Unity can serialize it on
// scene objects and it survives into builds.
using UnityEngine;

namespace Pixygon.Quarry
{
    /// <summary>What an imported object knows about where it came from.</summary>
    [DisallowMultipleComponent]
    public sealed class QuarryProvenance : MonoBehaviour
    {
        [Tooltip("Path or URL of the world.json this was imported from.")] public string manifest;
        [Tooltip("The asset uri inside that manifest (relative path or Quarry URL).")] public string assetUri;
        [Tooltip("Prefab id in the manifest.")] public string prefabId;
        [Tooltip("Codex slug of the place or object this belongs to, when the manifest names one.")] public string codexSlug;
        [Tooltip("Quarry design hash, when the asset came from the Quarry.")] public string design;
        public string importedAt;
    }
}
