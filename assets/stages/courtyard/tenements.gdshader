shader_type spatial;
// Distant Kowloon tenements (build_courtyard_stage.gd): a grid of windows on every wall,
// computed from the world position, so thousands of windows cost one material. At dawn
// (day = 0) a share of them are lit; as the day comes up the lights go out and the
// glass picks up the sky. CourtyardLife drives `day`. Vertex colour = wall colour.

uniform float day : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glass_day : source_color = vec3(0.42, 0.5, 0.6);
uniform vec3 lamp : source_color = vec3(1.0, 0.78, 0.5);

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float along = abs(world_normal.z) > 0.5 ? world_pos.x : world_pos.z;
	vec2 cell = vec2(along / 1.6, world_pos.y / 2.9);
	vec2 f = fract(cell);
	vec2 id = floor(cell);
	float window = step(0.2, f.x) * step(f.x, 0.75) * step(0.28, f.y) * step(f.y, 0.82);
	window *= step(abs(world_normal.y), 0.5) * step(0.8, world_pos.y);
	float h = hash(id + floor(vec2(world_pos.z, world_pos.x) * 0.05) * 17.0);
	float lit = step(h, mix(0.3, 0.0, smoothstep(0.0, 0.7, day))) * window;
	vec3 glass = mix(vec3(0.05, 0.06, 0.09), glass_day, day);
	ALBEDO = mix(COLOR.rgb, glass, window);
	ROUGHNESS = mix(0.95, 0.25, window);
	EMISSION = lamp * lit * (1.2 + h * 0.8);
}
