// Rain-soaked rooftop deck: concrete (or paint) darkened by the wet, glossy puddles where
// the water collects, rain ripples in them, and baked contact shadows (ambient occlusion
// from tools/build_rooftop_stage.gd) over the whole roof. Puddles come from world-space
// noise, so the concrete and the painted markings on top share the same water.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform bool textured = true; // concrete textures; false = flat paint colour
uniform vec3 tint : source_color = vec3(0.62, 0.62, 0.66);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tiling = 0.35; // texture repeats per metre
uniform float dry_roughness = 0.75;
uniform sampler2D ao_tex : hint_default_white, filter_linear, repeat_disable;
uniform float roof_half = 13.0; // the AO texture spans ±roof_half on X and Z
uniform float ao_strength = 1.0;
uniform float wetness = 0.55; // dampness everywhere (0 dry .. 1 soaked)
uniform float puddles = 0.5; // how much of the floor is standing water
uniform float ripples = 0.12;
uniform float ripple_speed = 1.3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

// Rain drops: in each 0.45 m cell a drop lands at a random spot and time, and a ring
// spreads out and fades. Returns the slope (normal offset) of the rings at `p`.
vec2 rings(vec2 p, float t) {
	vec2 slope = vec2(0.0);
	for (int layer = 0; layer < 1; layer++) {
		vec2 q = p / 0.45 + float(layer) * vec2(0.37, 0.71);
		vec2 cell = floor(q);
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 c = cell + vec2(float(x), float(y));
				vec2 center = c + vec2(hash(c + 3.1), hash(c + 7.7));
				float phase = fract(t * ripple_speed * (0.7 + 0.6 * hash(c + 1.3)) + hash(c));
				vec2 d = q - center;
				float dist = length(d);
				float radius = phase * 0.35;
				float ring = sin(clamp((dist - radius) * 60.0, -3.1416, 3.1416)) * step(abs(dist - radius), 0.052);
				slope += normalize(d + 1e-4) * ring * (1.0 - phase) * (1.0 - phase);
			}
		}
	}
	return slope;
}

void fragment() {
	vec2 uv = world_pos.xz * tiling;
	vec3 base = tint;
	float rough = dry_roughness;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (textured) {
		base *= texture(albedo_tex, uv).rgb;
		rough *= texture(rough_tex, uv).r / 0.75;
		nm = texture(normal_tex, uv).rgb;
	}
	// Standing water where the noise is high, with soft but defined edges.
	float n = fbm(world_pos.xz * 0.32 + vec2(3.1, 7.7));
	float level = 0.62 - puddles * 0.22;
	float puddle = smoothstep(level, level + 0.05, n);
	float damp = clamp(wetness + smoothstep(level - 0.12, level, n) * 0.5, 0.0, 1.0);
	base *= mix(1.0, 0.5, damp); // wet concrete is darker
	rough = mix(rough, 0.32, wetness);
	rough = mix(rough, 0.03, puddle); // still water is a mirror
	nm = mix(nm, vec3(0.5, 0.5, 1.0), puddle * 0.92);
	if (puddle > 0.01) { // ripples only where there's standing water
		nm.xy += rings(world_pos.xz, TIME) * ripples * puddle * 0.5;
	}
	// Baked contact shadows: darken the ambient light fully and the direct light partly.
	vec2 ao_uv = world_pos.xz / (2.0 * roof_half) + 0.5;
	float ao = mix(1.0, texture(ao_tex, ao_uv).r, ao_strength);
	ALBEDO = base * mix(1.0, ao, 0.55);
	AO = ao;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = 0.5;
	NORMAL_MAP = nm;
}
