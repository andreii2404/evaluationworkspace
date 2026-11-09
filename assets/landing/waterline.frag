#version 460 core
#include <flutter/runtime_effect.glsl>

// Nimbus UI Waterline by Guglielmo Giannattasio, adapted for Flutter.
uniform vec2 uSize;
uniform vec4 uHead;
uniform vec4 uTail;
uniform float uSquash;
uniform float uSplit;
uniform float uTime;
uniform vec3 uMouse;
uniform vec4 uTap;
uniform vec4 uArrival;
out vec4 fragColor;

float capsuleDistance(vec2 p, vec4 drop, float squash) {
  p -= drop.xy;
  p.y /= squash;
  p.x = max(abs(p.x) - drop.z, 0.0);
  return (length(p) - drop.w) * min(1.0, squash);
}

float smoothMin(float a, float b) {
  float h = clamp(0.5 + 0.5 * (b - a) / 13.0, 0.0, 1.0);
  return mix(b, a, h) - 13.0 * h * (1.0 - h);
}

float dropDistance(vec2 p) {
  float head = capsuleDistance(p, uHead, uSquash);
  float tail = capsuleDistance(p, uTail, uSquash);
  // At rest the two drops coincide. Keep the resting rim at the slot edge.
  float distance = mix(min(head, tail), smoothMin(head, tail),
                       smoothstep(0.0, 12.0, abs(uHead.x - uTail.x)));
  if (uSplit > 0.0) {
    for (int i = 1; i <= 3; i++) {
      float n = float(i);
      vec2 center = mix(uTail.xy, uHead.xy, n / 4.0);
      center.y += sin(n * 2.6) * 7.0;
      distance = smoothMin(distance,
                           length(p - center) - (3.0 + 0.6 * n) * uSplit);
    }
  }
  return distance;
}

float pillDistance(vec2 p) {
  return capsuleDistance(p, vec4(uSize * 0.5,
      max(0.0, (uSize.x - uSize.y) * 0.5), uSize.y * 0.5), 1.0);
}

float lens(float distance, float width) {
  float t = clamp(-distance / width, 0.0, 1.0);
  return sqrt(1.0 - (1.0 - t) * (1.0 - t));
}

float ripple(vec2 p, vec4 wave) {
  float x = length(p - wave.xy) - wave.z * 240.0;
  return wave.w * exp(-wave.z * 1.7) * sin(x * 0.3) * exp(-x * x / 700.0);
}

float surface(vec2 p) {
  float pill = pillDistance(p);
  vec2 mouse = p - uMouse.xy;
  float waves = ripple(p, uTap) + ripple(p, uArrival);
  waves += uMouse.z * 3.6 * exp(-dot(mouse, mouse) / 1000.0);
  waves += sin(p.x * 0.05 + uTime * 1.2) * 0.45
         + sin(p.x * 0.13 - uTime * 0.85 + p.y * 0.2) * 0.25;
  return lens(pill, uSize.y * 0.36) * 2.4
       + lens(dropDistance(p), 11.0) * 7.5
       + waves * smoothstep(0.0, 7.0, -pill);
}

float caustics(vec2 p, float time) {
  float value = 0.0;
  for (int i = 0; i < 3; i++) {
    p += vec2(sin(p.y * 1.1 + time), cos(p.x * 1.3 - time * 0.7)) * 0.6;
    value += 1.0 / (1.0 + 16.0 * abs(sin(p.x) * sin(p.y)));
  }
  return value / 3.0;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float pill = pillDistance(p);
  if (pill >= 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  float drop = dropDistance(p);
  float height = surface(p);
  vec3 n = normalize(vec3(height - surface(p + vec2(1.0, 0.0)),
                          height - surface(p + vec2(0.0, 1.0)), 1.0));
  float spec = pow(max(reflect(-normalize(vec3(-0.45, -0.8, 0.85)), n).z,
                       0.0), 70.0);
  float spec2 = pow(max(reflect(-normalize(vec3(0.6, 0.75, 0.7)), n).z,
                        0.0), 22.0) * 0.3;
  float fresnel = clamp((1.0 - n.z) * 4.0, 0.0, 1.0);
  vec3 ice = vec3(0.73, 0.85, 1.0);
  vec3 sapphire = vec3(0.012, 0.325, 0.643);
  vec3 sheen = mix(ice, vec3(0.29, 0.61, 1.0),
                   0.5 + 0.5 * cos(6.2831 *
                       (fresnel * 0.85 + p.x * 0.0028 + uTime * 0.035)));
  float pm = 1.0 - smoothstep(-1.0, 1.0, pill);
  float dm = (1.0 - smoothstep(-1.0, 1.0, drop)) *
             (1.0 - smoothstep(-2.0, 1.0, pill));
  float shadow = (1.0 - smoothstep(-9.0, 9.0, dropDistance(p - vec2(0.0, 5.0))))
               * (1.0 - dm) * pm * 0.18;
  vec4 result = vec4(vec3(0.0, 0.07, 0.2) * shadow, shadow);
  float surfaceAlpha = clamp(pm * (fresnel * 0.5 + spec * 0.9 + spec2), 0.0, 1.0);
  result = vec4(mix(ice, sheen, 0.5 * fresnel) * surfaceAlpha, surfaceAlpha)
         + result * (1.0 - surfaceAlpha);

  float thickness = lens(drop, 11.0);
  float pattern = caustics((p + n.xy * thickness * 18.0) * 0.085, uTime * 0.9);
  float rim = dm * (1.0 - smoothstep(0.0, 8.0, -drop));
  float crescent = dm * smoothstep(0.12, 0.55, dot(n.xy, normalize(vec2(0.55, 0.85))))
                 * smoothstep(0.0, 3.0, -drop);
  float body = 0.5 + 0.5 * clamp(-n.y * 3.0, -1.0, 1.0);
  float alpha = dm * (0.26 + 0.14 * body) * 0.65;
  vec4 water = vec4(mix(sapphire, ice, body * 0.6) * alpha, alpha);
  alpha = rim * 0.22;
  water = vec4(vec3(0.016, 0.40, 0.78) * alpha, alpha) + water * (1.0 - alpha);
  alpha = clamp(crescent * 0.7 + smoothstep(0.6, 1.0, pattern) *
                0.28 * thickness * dm, 0.0, 1.0);
  water = vec4(ice * alpha, alpha) + water * (1.0 - alpha);
  alpha = clamp(dm * (spec * 1.2 + spec2 * 0.5), 0.0, 1.0);
  water = vec4(vec3(alpha), alpha) + water * (1.0 - alpha);
  alpha = dm * smoothstep(-2.0, 0.0, drop) * 0.4;
  water = vec4(mix(vec3(1.0), sheen, 0.35) * alpha, alpha) + water * (1.0 - alpha);
  fragColor = water + result * (1.0 - water.a);
}
