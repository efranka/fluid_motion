// fluid_motion – the gooey shader. Draws, for any built-in outline:
//
//  mode 0: the neck between shape A and shape B (only what the merge ADDS
//          outside the shapes), coloured from the same blend as the shapes.
//  mode 1: shape A's own surface – including blobs (ripples) – with its
//          colour blending into up to three connected neighbours (B, C, D)
//          near their contacts, all at once.
//
// The maths is the same as the CPU version (GooeyNeckCpu, GooeyColorField),
// computed per pixel. Coordinates: p = FlutterFragCoord() + origin, in scene
// coordinates (logical pixels).

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uParams;   // mode, k, overlap, addsAtLeast
uniform vec4 uParams2;  // blendWidth (neck), origin x, origin y, pixel ratio
uniform vec4 uBump;     // focus x, focus y, amplitude, 1/sigma²
uniform vec4 uColA;     // colour (r, g, b, a) 0..1
uniform vec4 uColB;
uniform vec4 uColC;
uniform vec4 uColD;
uniform vec4 uWidths;   // surface: blend width towards B, C, D (0 = none)

// Shape A
uniform vec4 uRectA;    // left, top, right, bottom
uniform vec4 uShapeA;   // type, p1, p2, vertex count (type < 0 = none)
uniform vec4 uRipA[3];  // ripples: cx, cy, amplitude, 1/r²
uniform vec2 uVertA[24];

// Shape B
uniform vec4 uRectB;
uniform vec4 uShapeB;
uniform vec4 uRipB[3];
uniform vec2 uVertB[24];

// Shapes C and D: more neighbours for the surface (mode 1 only).
uniform vec4 uRectC;
uniform vec4 uShapeC;
uniform vec4 uRipC[3];
uniform vec2 uVertC[24];

uniform vec4 uRectD;
uniform vec4 uShapeD;
uniform vec4 uRipD[3];
uniform vec2 uVertD[24];

uniform sampler2D uFieldA;
uniform sampler2D uFieldB;
uniform sampler2D uFieldC;
uniform sampler2D uFieldD;

out vec4 fragColor;

const int MAX_VERTS = 24;

float sdRoundedRect(vec2 p, vec4 r, float rad) {
  vec2 c = (r.xy + r.zw) * 0.5;
  vec2 h = (r.zw - r.xy) * 0.5 - rad;
  vec2 q = abs(p - c) - h;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

float sdRing(vec2 p, vec4 r, float outer, float halfT) {
  float len = length(p - (r.xy + r.zw) * 0.5);
  if (halfT <= 0.0) return len - outer;
  return abs(len - (outer - halfT)) - halfT;
}

float smin(float a, float b, float k) {
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

// One polygon edge from VJ (previous corner) to VI (current corner), after
// Inigo Quilez's exact polygon distance.
#define EDGE(VJ, VI)                                                        \
  {                                                                         \
    vec2 e = VJ - VI;                                                       \
    vec2 w = p - VI;                                                        \
    float ee = dot(e, e);                                                   \
    float t = ee < 1e-12 ? 0.0 : clamp(dot(w, e) / ee, 0.0, 1.0);           \
    vec2 b = w - e * t;                                                     \
    d = min(d, dot(b, b));                                                  \
    bool c1 = p.y >= VI.y;                                                  \
    bool c2 = p.y < VJ.y;                                                   \
    bool c3 = e.x * w.y > e.y * w.x;                                        \
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;                    \
  }

#define SD_POLYGON(NAME, V)                                                 \
  float NAME(vec2 p, float n, float round) {                                \
    float d = 1e20;                                                         \
    float s = 1.0;                                                          \
    vec2 first = V[0];                                                      \
    vec2 prev = first;                                                      \
    for (int i = 1; i < MAX_VERTS; i++) {                                   \
      if (float(i) >= n) break;                                             \
      vec2 cur = V[i];                                                      \
      EDGE(prev, cur)                                                       \
      prev = cur;                                                           \
    }                                                                       \
    EDGE(prev, first)                                                       \
    return s * sqrt(d) - round;                                             \
  }

SD_POLYGON(polygonA, uVertA)
SD_POLYGON(polygonB, uVertB)
SD_POLYGON(polygonC, uVertC)
SD_POLYGON(polygonD, uVertD)

// A sampled distance field, bilinearly interpolated by hand (sampling at
// texel centres works with any texture filtering).
#define FIELD(TEX, GC, SIZE, OUT)                                           \
  {                                                                         \
    vec2 g = clamp(GC, vec2(0.0), SIZE - 1.001);                            \
    vec2 i0 = floor(g);                                                     \
    vec2 f = g - i0;                                                        \
    float a = texture(TEX, (i0 + vec2(0.5, 0.5)) / SIZE).r;                 \
    float b = texture(TEX, (i0 + vec2(1.5, 0.5)) / SIZE).r;                 \
    float c = texture(TEX, (i0 + vec2(0.5, 1.5)) / SIZE).r;                 \
    float e = texture(TEX, (i0 + vec2(1.5, 1.5)) / SIZE).r;                 \
    OUT = mix(mix(a, b, f.x), mix(c, e, f.x), f.y);                         \
  }

#define SD_SHAPE(NAME, RECT, SHAPE, RIP, V, TEX, POLY)                      \
  float NAME(vec2 p) {                                                      \
    float t = SHAPE.x;                                                      \
    float d;                                                                \
    if (t < 0.5) {                                                          \
      d = sdRoundedRect(p, RECT, SHAPE.y);                                  \
    } else if (t < 1.5) {                                                   \
      d = sdRing(p, RECT, SHAPE.y, SHAPE.z);                                \
    } else if (t < 2.5) {                                                   \
      d = POLY(p, SHAPE.w, SHAPE.y);                                        \
    } else {                                                                \
      vec2 gc = p * V[0] + V[1];                                            \
      vec2 size = vec2(V[4].y, V[5].x);                                     \
      float raw;                                                            \
      FIELD(TEX, gc, size, raw)                                             \
      d = (raw - 0.5) * V[4].x;                                             \
      vec2 c = (V[2] + V[3]) * 0.5;                                         \
      vec2 h = (V[3] - V[2]) * 0.5;                                         \
      vec2 q = abs(p - c) - h;                                              \
      d += length(max(q, 0.0));                                             \
    }                                                                       \
    for (int k = 0; k < 3; k++) {                                           \
      vec4 r = RIP[k];                                                      \
      vec2 dp = p - r.xy;                                                   \
      d -= r.z * exp(-dot(dp, dp) * r.w);                                   \
    }                                                                       \
    return d;                                                               \
  }

SD_SHAPE(sdA, uRectA, uShapeA, uRipA, uVertA, uFieldA, polygonA)
SD_SHAPE(sdB, uRectB, uShapeB, uRipB, uVertB, uFieldB, polygonB)
SD_SHAPE(sdC, uRectC, uShapeC, uRipC, uVertC, uFieldC, polygonC)
SD_SHAPE(sdD, uRectD, uShapeD, uRipD, uVertD, uFieldD, polygonD)

// The colour field between two shapes: how far (0..1) the colour at a point
// has moved from the shape at distance da towards the one at distance db.
float towards(float da, float db, float w) {
  float u = clamp(0.5 + (da - db) / (2.0 * w), 0.0, 1.0);
  return u * u * (3.0 - 2.0 * u);
}

vec4 blend(float da, float db, float w) {
  return mix(uColA, uColB, towards(da, db, w));
}

// A neighbour's weight relative to shape A (whose weight is 1). With one
// neighbour this is exactly mix(A, B, u); with more, each neighbour pulls
// the colour towards itself near its own contact, and the pulls add up
// smoothly – so a shape touching two others blends towards both, with no
// edge where one takes over from the other.
float weight(float da, float dk, float w) {
  float u = min(towards(da, dk, w), 0.999);
  return u / (1.0 - u);
}

// A cheap lower bound for a neighbour's distance: its box, minus whatever
// its ripples bulge out. When even that is too far away to blend, the exact
// distance is skipped.
#define FAR(RECT, RIP, DA, W)                                               \
  (length(max(abs(p - (RECT.xy + RECT.zw) * 0.5) -                          \
              (RECT.zw - RECT.xy) * 0.5, 0.0)) -                            \
       (max(RIP[0].z, 0.0) + max(RIP[1].z, 0.0) + max(RIP[2].z, 0.0)) >=     \
   DA + W)

void main() {
  vec2 p = FlutterFragCoord().xy + uParams2.yz;
  float pr = max(uParams2.w, 1.0);
  float w = uParams2.x;
  float da = sdA(p);

  vec4 color;
  float v;
  if (uParams.x < 0.5) {
    // The neck: only what the merge ADDS outside the shapes (plus a thin rim
    // tucked under them, so there is no seam).
    float db = sdB(p);
    vec2 f = p - uBump.xy;
    float bump = uBump.z * exp(-dot(f, f) * uBump.w);
    float sm = smin(da - bump, db - bump, uParams.y);
    float plain = min(da, db);
    v = max(max(sm, -(plain + uParams.z)), sm - plain + uParams.w);
    color = blend(da, db, w > 0.0 ? w : 8.0);
  } else {
    // The surface of shape A, blended towards each connected neighbour.
    v = da;
    vec4 sum = uColA;
    float total = 1.0;
    if (uShapeB.x > -0.5 && uWidths.x > 0.0 && !FAR(uRectB, uRipB, da, uWidths.x)) {
      float k = weight(da, sdB(p), uWidths.x);
      sum += uColB * k;
      total += k;
    }
    if (uShapeC.x > -0.5 && uWidths.y > 0.0 && !FAR(uRectC, uRipC, da, uWidths.y)) {
      float k = weight(da, sdC(p), uWidths.y);
      sum += uColC * k;
      total += k;
    }
    if (uShapeD.x > -0.5 && uWidths.z > 0.0 && !FAR(uRectD, uRipD, da, uWidths.z)) {
      float k = weight(da, sdD(p), uWidths.z);
      sum += uColD * k;
      total += k;
    }
    color = sum / total;
  }

  // Anti-aliasing over about one device pixel.
  float alpha = clamp(0.5 - v * pr, 0.0, 1.0) * color.a;
  // Premultiplied alpha.
  fragColor = vec4(color.rgb * alpha, alpha);
}
