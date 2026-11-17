// The whole screen is one triangle: no blending, no filtering, no overdraw.
// Per pixel: at most 2 cell-texture reads + 1 glyph-atlas read. Empty cells exit early.
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; };

vertex VOut vmain(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

struct CellSizes { uint2 globe; uint2 overlay; };
struct Palette { float4 c[8]; };

// Cell texel: r = ASCII code, g = palette index, b = brightness 0..255, a = non-zero when overlay cell is occupied.
fragment float4 fmain(VOut in [[stage_in]],
                      texture2d<uint>  gCells [[texture(0)]],
                      texture2d<float> gAtlas [[texture(1)]],
                      texture2d<uint>  oCells [[texture(2)]],
                      texture2d<float> oAtlas [[texture(3)]],
                      constant CellSizes &cs [[buffer(0)]],
                      constant Palette &pal [[buffer(1)]]) {
    uint2 p = uint2(in.pos.xy);

    // Text overlay layer (labels / panel) wins and knocks out the globe behind it.
    uint2 oc = p / cs.overlay;
    uint4 o = oCells.read(oc);
    if (o.a != 0) {
        if (o.r <= 32) return float4(0, 0, 0, 1);
        uint g = o.r - 32;
        uint2 ap = uint2(g % 16, g / 16) * cs.overlay + (p - oc * cs.overlay);
        float cov = oAtlas.read(ap).r;
        return float4(pal.c[o.g & 7].rgb * (float(o.b) / 255.0) * cov, 1);
    }

    uint2 gc = p / cs.globe;
    uint4 c = gCells.read(gc);
    if (c.r <= 32) return float4(0, 0, 0, 1);
    uint g = c.r - 32;
    uint2 ap = uint2(g % 16, g / 16) * cs.globe + (p - gc * cs.globe);
    float cov = gAtlas.read(ap).r;
    return float4(pal.c[c.g & 7].rgb * (float(c.b) / 255.0) * cov, 1);
}
