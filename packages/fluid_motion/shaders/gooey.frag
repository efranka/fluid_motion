// Gooey neck between two rounded rects – the same maths as the CPU version
// (GooeyNeckCpu), computed per pixel on the GPU.
//
// Coordinates are the canvas's local coordinates (logical pixels).

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uRectA;   // left, top, right, bottom
uniform vec4 uRectB;
uniform vec2 uRadius;  // corner radius of A and B
uniform vec4 uRipA;    // strongest ripple on A: cx, cy, amplitude, 1/r²
uniform vec4 uRipB;
uniform vec4 uBump;    // the bumps: focus x, focus y, amplitude, 1/sigma²
uniform vec4 uParams;  // k, overlap, addsAtLeast, blendWidth (0 = simple)
uniform vec4 uColA;    // colours (r, g, b, a) 0..1
uniform vec4 uColB;

out vec4 fragColor;

float sdRoundRect(vec2 p, vec4 r, float radius) {
  vec2 c = (r.xy + r.zw) * 0.5;
  vec2 h = (r.zw - r.xy) * 0.5 - vec2(radius);
  vec2 q = abs(p - c) - h;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float ripple(vec2 p, vec4 rp) {
  vec2 d = p - rp.xy;
  return rp.z * exp(-dot(d, d) * rp.w);
}

float smin(float a, float b, float k) {
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  float da = sdRoundRect(p, uRectA, uRadius.x) - ripple(p, uRipA);
  float db = sdRoundRect(p, uRectB, uRadius.y) - ripple(p, uRipB);

  vec2 d = p - uBump.xy;
  float bump = uBump.z * exp(-dot(d, d) * uBump.w);

  // Only what the merge ADDS outside the shapes (plus a thin rim tucked
  // under them, so there is no seam).
  float sm = smin(da - bump, db - bump, uParams.x);
  float plain = min(da, db);
  float v = max(max(sm, -(plain + uParams.y)), sm - plain + uParams.z);

  // Anti-aliasing over about one pixel.
  float alpha = clamp(0.5 - v, 0.0, 1.0);
  if (alpha <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  // Colour: the same blend as the colour field (two nearest shapes).
  float w = uParams.w > 0.0 ? uParams.w : 8.0;
  float t = clamp(0.5 + (da - db) / (2.0 * w), 0.0, 1.0);
  t = t * t * (3.0 - 2.0 * t);
  vec4 col = mix(uColA, uColB, t);

  // Premultiplied alpha.
  float a = col.a * alpha;
  fragColor = vec4(col.rgb * a, a);
}
