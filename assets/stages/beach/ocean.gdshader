shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
// Tropical sea for the beach stage: turquoise in the shallows deepening to blue out to
// the horizon, animated ripples (procedural value noise as a normal map), glossy sun
// highlights, and a foam line that laps along the shore at `shore_z`.

uniform vec3 shallow_color : source_color = vec3(0.12, 0.78, 0.74);
uniform vec3 deep_color : source_color = vec3(0.02, 0.27, 0.52);
uniform float shore_z = -12.5; // world z of the waterline (sea extends toward -z)
uniform float depth_falloff = 70.0; // metres from shore to full deep colour
uniform float ripple_scale = 0.35;
uniform float ripple_strength = 0.55;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float waves(vec2 p) {
	float t = TIME;
	return value_noise(p + vec2(t * 0.25, t * 0.4)) * 0.6
		+ value_noise(p * 2.3 - vec2(t * 0.35, t * 0.15)) * 0.3
		+ value_noise(p * 5.1 + vec2(t * 0.6, -t * 0.5)) * 0.1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float out_to_sea = shore_z - world_pos.z;
	float depth = clamp(out_to_sea / depth_falloff, 0.0, 1.0);
	vec3 water = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, depth));

	// Ripples: gradient of the wave height as a tangent-space normal (calmer far away).
	vec2 p = world_pos.xz * ripple_scale;
	float e = 0.08;
	float h = waves(p);
	float dx = waves(p + vec2(e, 0.0)) - h;
	float dz = waves(p + vec2(0.0, e)) - h;
	float strength = ripple_strength * mix(1.0, 0.35, depth);
	NORMAL_MAP = normalize(vec3(-dx / e * strength, -dz / e * strength, 1.0)) * 0.5 + 0.5;

	// Foam that laps in and out along the shore, broken up by noise.
	float lap = 0.9 + 0.5 * sin(TIME * 1.3 + world_pos.x * 0.35);
	float foam = smoothstep(lap + 0.6, lap - 0.2, out_to_sea) * smoothstep(-0.3, 0.2, out_to_sea);
	foam *= 0.55 + 0.45 * value_noise(world_pos.xz * 2.0 + TIME * 0.4);

	ALBEDO = mix(water, vec3(0.95, 0.98, 1.0), clamp(foam, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
