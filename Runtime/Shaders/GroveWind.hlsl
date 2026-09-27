// Grove Wind — the vertex side of the wind Grove bakes into every plant.
//
// A plant from the Thread's Grove carries its wind in four vertex channels,
// because the wood knows its own hierarchy (thread-engine/crates/grove):
//
//   TEXCOORD_2.x  trunk sway   0 at the ground, 1 at the top of the trunk, and
//                              whatever a limb left the trunk with all the way out
//   TEXCOORD_2.y  branch sway  0 along the trunk, climbing each generation to 1
//                              at the outermost twigs
//   TEXCOORD_3.x  leaf flutter the tremble only a leaf has; 0 on wood
//   TEXCOORD_3.y  phase        0..1 per branch, so no two limbs march in step
//   COLOR_0.a     rigidity     1 − sway; Infinite's channel (TERRA §6.3) — kept,
//                              not read here
//
// glTFast lands them in uv3 / uv4 (TEXCOORD_n → uv(n+1)). A mesh without them
// reads zeros and stands still, which is the right default for every mesh
// that predates the wind.
//
// Everything happens in world space so a whole tree leans in the world's wind
// and neighbours do not move in unison: the gust field is sampled at the
// object's origin, the phase comes from the vertex.
#ifndef PIXYGON_GROVE_WIND_INCLUDED
#define PIXYGON_GROVE_WIND_INCLUDED

CBUFFER_START(GroveWind)
    float4 _WindDirection;   // xz used; normalised here
    float  _WindStrength;    // 0 = still, 1 = a steady breeze, 3 = a gale
    float  _WindSpeed;       // time scale
    float  _TrunkSway;       // metres at the top of the trunk, at strength 1
    float  _BranchSway;      // metres at the outermost twigs, at strength 1
    float  _Flutter;         // leaf tremble, metres, at strength 1
CBUFFER_END

// The displaced world position of one vertex.
//   positionWS   the vertex, already in world space
//   originWS     the object's origin in world space (unity_ObjectToWorld._m03_m13_m23)
//   sway         TEXCOORD_2: (trunk, branch)
//   leaf         TEXCOORD_3: (flutter, phase)
float3 GroveWindDisplace(float3 positionWS, float3 originWS, float2 sway, float2 leaf)
{
    float t = _Time.y * _WindSpeed;
    float2 dir2 = _WindDirection.xz;
    dir2 = dot(dir2, dir2) > 1e-6 ? normalize(dir2) : float2(1.0, 0.0);
    float3 along = float3(dir2.x, 0.0, dir2.y);

    // One gust field over the world: where a tree stands decides when the
    // gust reaches it, so a stand ripples instead of nodding together.
    float where = dot(originWS.xz, dir2);
    float gust = 0.55 + 0.45 * sin(t * 0.31 + where * 0.13) * sin(t * 0.17 + where * 0.05 + 1.3);
    gust *= _WindStrength;

    float phase = leaf.y * 6.2831853;

    // The trunk: one slow lean, the whole tree together, most at the top.
    float trunk = sway.x * sin(t * 0.85 + where * 0.2);
    // The limb: its own swing, its own phase, breathing a little.
    float branch = sway.y * sin(t * 2.1 + phase) * (0.7 + 0.3 * sin(t * 0.5 + phase * 2.0));

    float3 d = along * (trunk * _TrunkSway + branch * _BranchSway) * gust;

    // The leaf: a fast tremble in three axes, keyed to its twig and its height,
    // so a cluster shivers as one and a crown does not.
    float fl = leaf.x * _Flutter * gust;
    d += float3(sin(t * 6.3 + phase * 3.0 + positionWS.y * 3.1),
                0.5 * cos(t * 5.1 + phase * 5.0),
                sin(t * 7.7 + phase)) * fl * 0.08;

    // What leans forward dips a little: a branch is a length, not a spring.
    d.y -= 0.12 * length(d.xz) * saturate(sway.x + sway.y);

    return positionWS + d;
}

#endif
