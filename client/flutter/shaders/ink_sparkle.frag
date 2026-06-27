// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#version 320 es
precision highp float;

layout(location = 0) out vec4 fragColor;

uniform sampler2D u_textureColorSampler;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_offset;
uniform vec4 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  vec4 textureColor = texture(u_textureColorSampler, uv);

  float distance = length(gl_FragCoord.xy - u_offset.xy);
  float radius = u_offset.z;
  float strength = max(0.0, 1.0 - (distance / radius));
  strength = pow(strength, 2.0);

  vec4 sparkleColor = u_color * strength;

  fragColor = mix(textureColor, textureColor + sparkleColor, strength);
}
